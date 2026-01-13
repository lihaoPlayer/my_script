#!/bin/bash
set -e  # 出错立即终止，保证部署完整性

# 基础配置
script_dir="/usr/local/Data-source"
script_file="$script_dir/ppp-speed.sh"
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/ppp-speed.prom"
tmp_file="$output_dir/ppp-speed.tmp"

# ================== 1. 创建目录（静默执行） ==================
mkdir -p "$script_dir" "$output_dir" >/dev/null 2>&1

# ================== 2. 写入带宽统计脚本（核心逻辑保留，仅改统计间隔为10秒） ==================
cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail
##获取平台信息
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

# 基础配置
output_file="/var/log/mx-cIndicator/ppp-speed.prom"
tmp_file="/var/log/mx-cIndicator/ppp-speed.tmp"
hostname_file="/allconf/hostname.conf"
stat_interval=10  # 10秒统计一次流量差
default_usage="0.0000"

# 写入临时文件（核心：原子替换）
> "$tmp_file"
cat > "$tmp_file" << EOM
# HELP bandwidth_usage_ratio Ratio of bandwidth usage (only UP physical NIC)
# TYPE bandwidth_usage_ratio gauge
EOM

# 获取标签值
hostname=$(grep -oP 'hostname=\K.*' "$hostname_file" 2>/dev/null || hostname)
hostname=${hostname:-"unknown"}
planform=$(get_planform)

# 核心统计逻辑（全兜底）
{
    total_bandwidth_mbps=0
    if command -v smallnode_control &>/dev/null; then
        output=$(smallnode_control -l --json 2>/dev/null)
        if echo "$output" | jq -e '.' &>/dev/null; then
            total_bandwidth_mbps=$(echo "$output" | jq -r '.total_bandwidth // 0')
        fi
    fi
    total_bandwidth_mbps=$(( total_bandwidth_mbps + 0 ))

    if [ "$total_bandwidth_mbps" -eq 0 ]; then
        usage_ratio="$default_usage"
        echo "bandwidth_usage_ratio{hostname=\"$hostname\",planform=\"$planform\"} $usage_ratio" >> "$tmp_file"
        mv -f "$tmp_file" "$output_file"
        exit 0
    fi

    valid_nics=""
    up_nics=$(ip -br a | grep -E ' +UP +' | awk '{print $1}' 2>/dev/null)
    for nic in $up_nics; do
        [ -d "/sys/class/net/${nic}/device" ] && valid_nics="$valid_nics $nic"
    done
    valid_nics=$(echo "$valid_nics" | xargs)

    if [ -z "$valid_nics" ]; then
        usage_ratio="$default_usage"
        echo "bandwidth_usage_ratio{hostname=\"$hostname\",planform=\"$planform\"} $usage_ratio" >> "$tmp_file"
        mv -f "$tmp_file" "$output_file"
        exit 0
    fi

    declare -A tx1_map
    for nic in $valid_nics; do
        tx1=$(grep -E "^[[:space:]]*${nic}:" /proc/net/dev | awk '{print $10}' 2>/dev/null || echo 0)
        tx1_map[$nic]=$tx1
    done

    sleep "$stat_interval"  # 这里会按修改后的10秒休眠

    total_tx_speed_mbps=0.0
    for nic in $valid_nics; do
        tx1=${tx1_map[$nic]}
        tx1=$(( tx1 + 0 ))
        tx2=$(grep -E "^[[:space:]]*${nic}:" /proc/net/dev | awk '{print $10}' 2>/dev/null || echo 0)
        tx2=$(( tx2 + 0 ))
        
        tx_diff=$(( tx2 - tx1 ))
        [ "$tx_diff" -lt 0 ] && tx_diff=0
        
        if command -v bc &>/dev/null; then
            nic_speed_mbps=$(echo "scale=4; ($tx_diff * 8) / $stat_interval / 1024 / 1024" | bc -l 2>/dev/null)
        else
            nic_speed_mbps="$default_usage"
        fi
        total_tx_speed_mbps=$(echo "scale=4; $total_tx_speed_mbps + $nic_speed_mbps" | bc -l 2>/dev/null || "$default_usage")
    done

    if command -v bc &>/dev/null && [ "$total_tx_speed_mbps" != "" ]; then
        usage_ratio=$(echo "scale=4; $total_tx_speed_mbps / $total_bandwidth_mbps" | bc -l 2>/dev/null)
        usage_ratio=$(echo "$usage_ratio" | sed -e 's/^\./0./' 2>/dev/null)
    else
        usage_ratio="$default_usage"
    fi

    if ! echo "$usage_ratio" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        usage_ratio="$default_usage"
    fi
} || {
    usage_ratio="$default_usage"
}

echo "bandwidth_usage_ratio{hostname=\"$hostname\",planform=\"$planform\"} $usage_ratio" >> "$tmp_file"
mv -f "$tmp_file" "$output_file"

exit 0
EOF

# 赋予执行权限
chmod +x "$script_file"

# ================== 3. 创建systemd服务文件 ==================
cat > /etc/systemd/system/ppp-speed.service << 'EOF'
[Unit]
Description=Bandwidth Usage Statistics Script
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/ppp-speed.sh
TimeoutSec=30
ProtectSystem=off
EOF

chmod 644 /etc/systemd/system/ppp-speed.service

# ================== 4. 创建systemd定时器文件 ==================
cat > /etc/systemd/system/ppp-speed.timer << 'EOF'
[Unit]
Description=Run bandwidth script every 90 seconds

[Timer]
Unit=ppp-speed.service
OnBootSec=30
OnUnitInactiveSec=90
Persistent=yes
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

chmod 644 /etc/systemd/system/ppp-speed.timer

# ================== 5. 启动定时器（静默执行） ==================
systemctl daemon-reload >/dev/null 2>&1
systemctl disable --now ppp-speed.service >/dev/null 2>&1 || true
systemctl disable --now ppp-speed.timer >/dev/null 2>&1 || true
systemctl start ppp-speed.service >/dev/null 2>&1
systemctl enable --now ppp-speed.timer >/dev/null 2>&1