#!/bin/bash
set -euo pipefail

# 创建 disk-monitor.sh 脚本的完整路径
disk_script_path="/usr/local/Data-source/disk-monitor.sh"
mkdir -p "$(dirname "$disk_script_path")"

# 写入核心脚本内容
cat << 'EOF' > "$disk_script_path"
#!/bin/bash
set -euo pipefail

output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/disk-status.prom"
previous_disks_file="$output_dir/previous_disks.txt"
mkdir -p "$output_dir" || exit 1

#获取平台信息
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

planform=$(get_planform)
disks=$(lsblk -d -n -r -o NAME,SERIAL | grep -Ev '^loop|^ram|^sr' | tr ' ' '\t') || exit 1

tmp_file="${output_file}.tmp"
echo "# HELP disk_status Status of disk devices (1 = present, 0 = missing)" > "$tmp_file"
echo "# TYPE disk_status gauge" >> "$tmp_file"

declare -A current_disks_map
declare -A current_disks_sn_map

if [ -n "$disks" ]; then
    while IFS=$'\t' read -r name sn; do
        [ -z "$sn" ] || [ "$sn" = "-" ] && sn="unknown_${name}"
        current_disks_map["$name"]="$sn"
        current_disks_sn_map["$sn"]="$name"
        echo "disk_status{name=\"$name\", sn=\"$sn\", planform=\"$planform\"} 1" >> "$tmp_file"
    done <<< "$disks"
fi

if [ -f "$previous_disks_file" ] && [ -s "$previous_disks_file" ]; then
    while IFS=$'\t' read -r prev_name prev_sn; do
        [ -z "$prev_name" ] || [ -z "$prev_sn" ] && continue
        if [ -z "${current_disks_sn_map[$prev_sn]}" ] && [ -z "${current_disks_map[$prev_name]}" ]; then
            original_sn=${prev_sn#unknown_}
            [ "$original_sn" != "$prev_sn" ] && original_sn=""
            echo "disk_status{name=\"$prev_name\", sn=\"$original_sn\", planform=\"$planform\"} 0" >> "$tmp_file"
        fi
    done < "$previous_disks_file"
fi

mv -f "$tmp_file" "$output_file" || { rm -f "$tmp_file"; exit 1; }
echo "$disks" > "$previous_disks_file" || true
EOF

chmod +x "$disk_script_path"

# 服务文件
cat > /etc/systemd/system/disk-monitor.service << 'EOF'
[Unit]
Description=Run disk-monitor.sh script to check for disk failures

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/disk-monitor.sh
TimeoutSec=30s
ProtectSystem=off

[Install]
WantedBy=multi-user.target
EOF

# 定时器文件
cat > /etc/systemd/system/disk-monitor.timer << 'EOF'
[Unit]
Description=Run disk-monitor.sh every 90 seconds
[Timer]
Unit=disk-monitor.service
OnBootSec=30
OnUnitInactiveSec=90
Persistent=yes
AccuracySec=1
[Install]
WantedBy=timers.target
EOF

# 设置正确权限
chmod 644 /etc/systemd/system/disk-monitor.service
chmod 644 /etc/systemd/system/disk-monitor.timer
chown root:root /etc/systemd/system/disk-monitor.service
chown root:root /etc/systemd/system/disk-monitor.timer

# 重新加载并启用
systemctl daemon-reload
systemctl disable --now disk-monitor.service >/dev/null 2>&1 || true
systemctl disable --now disk-monitor.timer >/dev/null 2>&1 || true
systemctl start disk-monitor.service >/dev/null 2>&1 || true
systemctl enable --now disk-monitor.timer >/dev/null 2>&1