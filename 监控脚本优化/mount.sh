#!/bin/bash
set -euo pipefail

# 部署配置（通用）
MOUNT_SCRIPT="/usr/local/Data-source/mount-monitor.sh"
SERVICE_FILE="/etc/systemd/system/mount-monitor.service"
TIMER_FILE="/etc/systemd/system/mount-monitor.timer"
OUTPUT_DIR="/var/log/mx-cIndicator"

# 创建目录
mkdir -p "$(dirname "$MOUNT_SCRIPT")" "$OUTPUT_DIR" && chmod 755 "$(dirname "$MOUNT_SCRIPT")" "$OUTPUT_DIR" || exit 1

# 写入核心监控脚本
cat << 'EOF' > "$MOUNT_SCRIPT"
#!/bin/bash
set -eo pipefail

# 基础配置
OUTPUT_DIR="/var/log/mx-cIndicator"
OUTPUT_FILE="${OUTPUT_DIR}/mount-status.prom"
TMP_FILE="${OUTPUT_FILE}.tmp"
HIST_FILE="${OUTPUT_DIR}/history_mounts.txt"

# 初始化临时文件（严格固定HELP在第一行，TYPE在第二行）
cat > "$TMP_FILE" << EOF_HEAD
# HELP mount_status Status of disk mount points (1 = mounted, 0 = unmounted)
# TYPE mount_status gauge
EOF_HEAD

# 动态识别系统盘（兼容LUKS/dm/mapper）
identify_sys_disk() {
    local root_src=$(findmnt -n -o SOURCE / 2>/dev/null)
    [ -z "$root_src" ] && { echo "sda|vda|hda|nvme0n1"; return; }

    local phy_part=""
    if [[ "$root_src" =~ ^/dev/mapper/ ]]; then
        local dm_dev=$(basename "$root_src")
        dm_dev=$(dmsetup info -c --noheadings -o devname "$dm_dev" 2>/dev/null || echo "$dm_dev")
        if [[ "$dm_dev" =~ ^dm-[0-9]+$ ]]; then
            phy_part=$(lsblk -n -o pkname "/dev/$dm_dev" 2>/dev/null || 
                       lsblk -n -o NAME,TYPE "/dev/$dm_dev" 2>/dev/null | awk '$2 ~ /part/ {print $1}')
        else
            phy_part=$(lsblk -n -o pkname "$root_src" 2>/dev/null | head -1)
        fi
    else
        phy_part=$(echo "$root_src" | sed 's/\/dev\///g')
    fi

    local sys_disk=$(lsblk -n -o pkname "/dev/$phy_part" 2>/dev/null || 
                     echo "$phy_part" | sed -E 's/^([a-zA-Z]+[0-9]+n?[0-9]*)(p?[0-9]+)$/\1/' ||
                     lsblk -n -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" && $1 ~ /^sd|^nvme|^vd/ {print $1}' | head -1)
    
    # 最终兜底
    [[ -z "$sys_disk" || "$sys_disk" =~ dm|mapper|luks|/ ]] && sys_disk="sda|vda|hda|nvme0n1"
    echo "$sys_disk"
}

# 获取平台信息
get_platform() {
    local plt="third"
    [ -r /usr/bin/issue.sh ] && {
        grep -q "portal.chxyun.cn" /usr/bin/issue.sh 2>/dev/null && plt="mx"
        grep -q "www.smogfly.com" /usr/bin/issue.sh 2>/dev/null && plt="wc"
    }
    echo "$plt"
}

# 核心变量
PLATFORM=$(get_platform)
SYS_DISK=$(identify_sys_disk)
SYS_DISK_PAT="^($SYS_DISK)"

# 实时筛选挂载设备（disk/part/lvm，过滤loop）
CURRENT_MOUNTS=$(lsblk -n -o NAME,MOUNTPOINT,TYPE 2>/dev/null | 
    awk '{gsub(/^[├└─│ ]+/,"",$1); if ($3 ~ /^disk|part|lvm$/ && $1 !~ /^loop/) print $1 "|" ($2?$2:"")}' | 
    grep -v '^|' || true)

# 构建当前设备映射（保留所有设备，不提前unset）
declare -A DEV_MAP=()
DEV_LIST=() # 保留设备顺序，避免丢失
while IFS='|' read -r dev_name dev_mount; do
    dev_name=$(echo "$dev_name" | sed -e 's/[^a-zA-Z0-9_-]//g' -e 's/--/-/g')
    [ -z "$dev_name" ] && continue
    DEV_MAP["$dev_name"]="$dev_mount"
    DEV_LIST+=("$dev_name") # 记录顺序
done <<< "$CURRENT_MOUNTS"

# 直接写入所有实时设备（抛弃复杂的历史记录处理，避免丢失）
> "$HIST_FILE" # 清空旧历史，重新写入所有实时设备
for dev_name in "${DEV_LIST[@]}"; do
    dev_mount="${DEV_MAP[$dev_name]}"
    status=$([ -n "$dev_mount" ] && echo 1 || echo 0)
    # 写入指标
    echo "mount_status{name=\"$dev_name\", mountpoint=\"$dev_mount\", planform=\"$PLATFORM\"} $status" >> "$TMP_FILE"
    # 写入历史记录
    echo "$dev_name|$dev_mount|sys" >> "$HIST_FILE"
done

# 兜底逻辑（无设备时）
if ! grep -q 'mount_status{' "$TMP_FILE"; then
    echo "mount_status{name=\"none\", mountpoint=\"\", planform=\"$PLATFORM\"} 0" >> "$TMP_FILE"
fi

# 去重（保留顺序，仅去重重复行，不丢失设备）
awk '
    NR==1 {print; next} 
    NR==2 {print; next} 
    !seen[$0]++
' "$TMP_FILE" > "${TMP_FILE}.final"

# 原子替换（确保完整）
mv -f "${TMP_FILE}.final" "$OUTPUT_FILE" || cp "$TMP_FILE" "$OUTPUT_FILE"

# 清理临时文件+权限
rm -f "$TMP_FILE" "${TMP_FILE}.final" 2>/dev/null
chmod 644 "$OUTPUT_FILE" "$HIST_FILE" 2>/dev/null || true
EOF

# 赋予执行权限
chmod +x "$MOUNT_SCRIPT"

# 创建服务文件（使用你指定的内容）
cat << 'EOF' > "$SERVICE_FILE"
[Unit]
Description=Universal Disk Mount Monitor (Edge Nodes)

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/mount-monitor.sh
TimeoutSec=30
ProtectSystem=off
EOF

# 创建定时器文件（使用你指定的内容）
cat << 'EOF' > "$TIMER_FILE"
[Unit]
Description=Run Disk Mount Monitor every 1 minute 30 seconds

[Timer]
Unit=mount-monitor.service
OnBootSec=30
OnUnitInactiveSec=90
Persistent=yes
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

# 设置权限（使用你指定的内容）
chmod 644 "$SERVICE_FILE" "$TIMER_FILE"
chown root:root "$SERVICE_FILE" "$TIMER_FILE"

# 部署生效（强制重启，使用你指定的内容）
systemctl daemon-reload
systemctl disable --now mount-monitor.service 2>/dev/null || true
systemctl disable --now mount-monitor.timer 2>/dev/null || true
rm -f "${OUTPUT_DIR}/history_mounts.txt" "${OUTPUT_DIR}/mount-status.prom" 2>/dev/null
systemctl start mount-monitor.service 2>/dev/null || true
systemctl enable --now mount-monitor.timer 2>/dev/null || true