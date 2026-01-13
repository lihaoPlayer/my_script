#!/bin/bash

# 目标目录和文件
script_dir="/usr/local/Data-source"
script_file="$script_dir/ppp-speed.sh"

# 检查并创建目录
if [ ! -d "$script_dir" ]; then
    mkdir -p "$script_dir"
fi

# 创建脚本内容（整合 planform 识别与原有带宽统计功能）
cat << 'EOF' > "$script_file"
#!/bin/bash

# ================== 新增：获取 planform 值（从 /usr/bin/issue.sh 的 version 参数提取） ==================
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local version_val=""
    local planform="mx"  # 默认为mx
    
    # 优先级1：优先匹配 portal.chxyun.cn 域名的qrencode命令（原业务域名）
    local chxyun_line=$(grep -E "qrencode.*https://portal.chxyun.cn/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
    if [ -n "$chxyun_line" ]; then
        # 提取portal.chxyun.cn对应的version值
        version_val=$(echo "$chxyun_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
        if [ "$version_val" = "010" ] || [ "$version_val" = "1" ]; then
            planform="mx"
        else
            # 不符合mx版本的情况
            planform="unknown"
        fi
    else
        # 优先级2：匹配 www.smogfly.com 域名的qrencode命令
        local smogfly_line=$(grep -E "qrencode.*https://www.smogfly.com/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
        if [ -n "$smogfly_line" ]; then
            # 提取www.smogfly.com对应的version值
            version_val=$(echo "$smogfly_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
            if [ "$version_val" = "012" ] || [ "$version_val" = "2" ]; then
                planform="wc"
            else
                # 不符合wc版本的情况
                planform="unknown"
            fi
        fi
        # 优先级1和2都不满足时，保持默认的mx
    fi

    echo "$planform"
}





# ================== 基础配置 ==================
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/ppp-speed.prom"
hostname_file="/allconf/hostname.conf"

# Prometheus API 配置
prom_url="https://monitor.9yb.life/api/v1/query_range"
instance_id="" # 如果不是用 hostname 作为 instance，请填写 SN ID
ignore_devices="lo|docker0|bond0|dummy0|tunl0|macvlan.*|veth.*|br-.*|virbr|vmnet|cni|tap|tun|bridge|dummy0|@|ppp.*"

# ================== 创建输出目录 ==================
mkdir -p "$output_dir"
> "$output_file"

echo "# HELP bandwidth_usage_ratio Ratio of bandwidth usage in the last hour" >> "$output_file"
echo "# TYPE bandwidth_usage_ratio gauge" >> "$output_file"

# ================== 获取 hostname 和 planform ==================
hostname=$(grep -oP 'hostname=\K.*' "$hostname_file" 2>/dev/null || echo "unknown")
planform=$(get_planform)  # 调用函数获取 planform 值
[ -z "$instance_id" ] && instance_id="$hostname"

# ================== 获取总可用带宽 ==================
total_bandwidth=0
if command -v smallnode_control &>/dev/null; then
    output=$(smallnode_control -l --json 2>/dev/null)
    if echo "$output" | jq empty &>/dev/null; then
        total_bandwidth=$(echo "$output" | jq -r '.total_bandwidth // 0')
    fi
fi

if [ "$total_bandwidth" -eq 0 ]; then
    # 指标中添加 planform 标签
    echo "bandwidth_usage_ratio{hostname=\"$hostname\",planform=\"$planform\"} 0" >> "$output_file"
    exit 0
fi

# 转换总带宽为比特（MB → Bytes → Bits）
total_bandwidth_bits=$(( total_bandwidth * 1024 * 1024 ))

# ================== 获取主网卡列表 ==================
main_ifaces=$(ip -br a | grep -v -E "$ignore_devices" | awk '{print $1}' | xargs | sed 's/ /|/g')
if [ -z "$main_ifaces" ]; then
    # 指标中添加 planform 标签
    echo "bandwidth_usage_ratio{hostname=\"$hostname\",planform=\"$planform\"} 0" >> "$output_file"
    exit 0
fi

# ================== 动态生成时间区间（近一小时） ==================
end_ts=$(date +%s)
start_ts=$((end_ts - 3600))

# ================== 组装 Prometheus 查询（计算 5 分钟平均速率，单位比特/秒） ==================
query="sum(irate(node_network_transmit_bytes_total{device=~\"$main_ifaces\",instance=~\"$instance_id\",process!~\"^PID_.*\"}) * 8)"

# ================== 调用 API 获取数据 ==================
monitor_data=$(curl -s --get \
    --data-urlencode "query=$query" \
    --data-urlencode "start=$start_ts" \
    --data-urlencode "end=$end_ts" \
    --data-urlencode "step=60s" \
    "$prom_url")

# ================== 解析 JSON 计算总平均带宽 ==================
avg_bandwidth=0
if echo "$monitor_data" | jq -e '.data.result' >/dev/null; then
    avg_bandwidth=$(echo "$monitor_data" | jq '
        .data.result[0].values
        | map(.[1] | tonumber)
        | add / length
    ')
fi

# ================== 计算带宽使用率 ==================
usage_ratio=$(awk "BEGIN {printf \"%.4f\", $avg_bandwidth / $total_bandwidth_bits}")

# ================== 写入 Prometheus 指标文件（含 planform 标签） ==================
echo "bandwidth_usage_ratio{hostname=\"$hostname\",planform=\"$planform\"} $usage_ratio" >> "$output_file"
EOF

# 赋予执行权限
chmod +x "$script_file"

# 创建服务单元文件
cat << 'EOF' > /etc/systemd/system/ppp-speed.service
[Unit]
Description=Run /usr/local/Data-source/ppp-speed.sh script

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/ppp-speed.sh
EOF

# 创建定时器单元文件
cat << 'EOF' > /etc/systemd/system/ppp-speed.timer
[Unit]
Description=Run /usr/local/Data-source/ppp-speed.sh every 1 minute and 30 seconds

[Timer]
# 系统启动后，延迟30秒执行第一次
OnBootSec=30s
# 每次执行完成后，间隔90秒（1分30秒）再次执行
OnUnitInactiveSec=90s
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 启用和启动定时器
systemctl enable ppp-speed.timer
systemctl start ppp-speed.timer
systemctl  enable ppp-speed.service 
systemctl  restart ppp-speed.service 