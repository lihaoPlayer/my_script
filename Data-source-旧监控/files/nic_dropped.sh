#!/bin/bash

# 创建 nic-dropped.sh 脚本的完整路径
script_path="/usr/local/Data-source/nic-dropped.sh"
parent_dir=$(dirname "$script_path")

# 先创建父目录（如果不存在）
mkdir -p "$parent_dir"


# 创建修复后的脚本内容
cat << 'EOF' > "$script_path"
#!/bin/bash

# 设置输出目录和文件
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/nic_dropped.prom"
log_file="$output_dir/nic_dropped.log"   
state_cache="/var/log/nic_state_cache.txt"

# 彻底掉线阈值（连续DOWN次数，每次间隔90秒，20次=30分钟）
COMPLETE_DROP_THRESHOLD=2

# -------------------------- 工具函数定义 --------------------------
# 1. 获取planform（全局调用，避免作用域问题）
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local version_val=""
    
    # 优先级1：匹配原业务域名 portal.chxyun.cn
    local chxyun_line=$(grep -E "qrencode.*https://portal.chxyun.cn/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
    if [ -n "$chxyun_line" ]; then
        version_val=$(echo "$chxyun_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
    else
        # 优先级2：匹配备用域名 www.smogfly.com
        local smogfly_line=$(grep -E "qrencode.*https://www.smogfly.com/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
        if [ -n "$smogfly_line" ]; then
            version_val=$(echo "$smogfly_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
        fi
    fi

    # 按version匹配planform
    case "$version_val" in
        010|1)  echo "mx"    ;;  
        012|2)  echo "wc"    ;;  
        *)      echo "unknown" ;; 
    esac
}

# 2. 初始化必要文件（确保目录和文件存在，避免报错）
init_files() {
    mkdir -p "$output_dir"
    touch "$output_file" "$log_file" "$state_cache"
    # 清空输出文件（每次执行重新生成Prometheus指标）
    > "$output_file"
}

# 3. 收集当前有效网卡列表（排除虚拟网卡，去重）
get_valid_interfaces() {
    local exclude_pattern='lo|docker0|veth|virbr|vmnet|cni|tap|tun|bridge|dummy0|@|ppp*|br-*'
    # 输出格式：每行一个网卡名，已去重
    ip -br a | grep -v -E "$exclude_pattern" | awk '{print $1}' | sort -u
}

# 4. 从缓存获取指定网卡的历史数据（状态码+连续DOWN次数）
get_cache_data() {
    local interface=$1
    # 缓存格式：网卡名:状态码:连续DOWN次数，无匹配时返回默认值
    local cache_entry=$(grep "^${interface}:" "$state_cache" 2>/dev/null)
    if [ -n "$cache_entry" ]; then
        echo "$cache_entry" | cut -d: -f2-  # 返回：状态码:连续DOWN次数
    else
        echo "0:0"  # 默认：状态码0（DOWN）、连续DOWN次数0
    fi
}

# -------------------------- 主逻辑 --------------------------
# 初始化文件和全局变量
init_files
planform=$(get_planform)  # 全局planform，所有指标共用
current_interfaces=($(get_valid_interfaces))  # 当前有效网卡数组（去重）

# -------------------------- 1. 处理 nic_dropped 指标（当前掉线状态） --------------------------
# 指标含义：1=当前掉线（DOWN），0=正常（UP）
cat <<EOL >> "$output_file"
# HELP nic_dropped Current status of network interfaces (1=currently dropped, 0=normal)
# TYPE nic_dropped gauge
EOL

for interface in "${current_interfaces[@]}"; do
    # 获取当前网卡状态（UP/DOWN）
    current_state=$(ip -br a show "$interface" | awk '{print $2}')
    # 转换为状态码：1=UP，0=DOWN
    state_code=$([ "$current_state" == "UP" ] && echo 1 || echo 0)
    # 从缓存获取历史数据
    prev_data=$(get_cache_data "$interface")
    prev_state=$(echo "$prev_data" | cut -d: -f1)  # 历史状态码
    prev_down_count=$(echo "$prev_data" | cut -d: -f2)  # 历史连续DOWN次数

    # 计算当前掉线状态（1=掉线，0=正常）
    current_dropped=$((1 - state_code))

    # 记录状态变化日志（掉线/恢复）
    if [ "$prev_state" -eq 1 ] && [ "$state_code" -eq 0 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - 网卡 $interface 发生掉线（从UP变为DOWN）" >> "$log_file"
    elif [ "$prev_state" -eq 0 ] && [ "$state_code" -eq 1 ]; then
        echo "$(date +'%Y-%m-%d %H:%M:%S') - 网卡 $interface 恢复正常（从DOWN变为UP）" >> "$log_file"
    fi

    # 写入Prometheus指标
    echo "nic_dropped{interface=\"$interface\", planform=\"$planform\"} $current_dropped" >> "$output_file"
done

# -------------------------- 2. 处理 nic_completely_dropped 指标（彻底掉线状态） --------------------------
# 指标含义：1=彻底掉线（连续DOWN≥20次），0=正常
cat <<EOL >> "$output_file"
# HELP nic_completely_dropped Status of network interfaces (1=completely dropped, 0=normal)
# TYPE nic_completely_dropped gauge
EOL

for interface in "${current_interfaces[@]}"; do
    # 获取当前网卡状态和状态码
    current_state=$(ip -br a show "$interface" | awk '{print $2}')
    state_code=$([ "$current_state" == "UP" ] && echo 1 || echo 0)
    # 从缓存获取历史连续DOWN次数
    prev_down_count=$(get_cache_data "$interface" | cut -d: -f2)

    # 计算当前连续DOWN次数（关键修复：UP时重置为0）
    if [ "$state_code" -eq 0 ]; then
        current_down_count=$((prev_down_count + 1))
    else
        current_down_count=0  # UP状态时，连续DOWN次数清零
    fi

    # 判断是否彻底掉线
    completely_dropped=0
    if [ "$state_code" -eq 0 ] && [ "$current_down_count" -ge "$COMPLETE_DROP_THRESHOLD" ]; then
        completely_dropped=1
        # 仅在首次达到阈值时记录日志（避免重复输出）
        if [ "$current_down_count" -eq "$COMPLETE_DROP_THRESHOLD" ]; then
            local total_min=$((COMPLETE_DROP_THRESHOLD * 90 / 60))
            echo "$(date +'%Y-%m-%d %H:%M:%S') - 网卡 $interface 彻底掉线（持续DOWN超过 $total_min 分钟）" >> "$log_file"
        fi
    fi

    # 写入Prometheus指标
    echo "nic_completely_dropped{interface=\"$interface\", planform=\"$planform\"} $completely_dropped" >> "$output_file"

    # 更新缓存（覆盖旧记录或新增）
    if grep -q "^${interface}:" "$state_cache"; then
        sed -i "s/^${interface}:.*/${interface}:${state_code}:${current_down_count}/" "$state_cache"
    else
        echo "${interface}:${state_code}:${current_down_count}" >> "$state_cache"
    fi
done

# -------------------------- 3. 处理消失的网卡（从系统中移除的网卡） --------------------------
# 遍历缓存中的网卡，检查是否仍存在于系统中
while read -r cache_entry; do
    if [ -z "$cache_entry" ]; then continue; fi  # 跳过空行
    cached_interface=$(echo "$cache_entry" | cut -d: -f1)
    
    # 检查网卡是否存在（直接调用系统命令，避免冗余判断）
    if ! ip link show "$cached_interface" 2>/dev/null; then
        # 记录消失日志并写入指标
        echo "$(date +'%Y-%m-%d %H:%M:%S') - 网卡 $cached_interface 彻底掉线（已从系统中消失）" >> "$log_file"
        echo "nic_completely_dropped{interface=\"$cached_interface\", planform=\"$planform\"} 1" >> "$output_file"
        # 从缓存中删除该网卡记录
        sed -i "/^${cached_interface}:/d" "$state_cache"
    fi
done < "$state_cache"

EOF

# 赋予脚本可执行权限
chmod +x "$script_path"

# -------------------------- 创建 systemd 服务和定时器 --------------------------
# 1. 服务单元文件（oneshot类型，执行脚本）
cat << 'EOF' > /etc/systemd/system/nic-dropped.service
[Unit]
Description=Report network interface drop status (instant & complete)
After=network.target  # 确保网络就绪后执行，避免ip命令失败

[Service]
Type=oneshot
# 输出脚本执行日志到文件，便于排查错误
StandardOutput=append:/var/log/mx-cIndicator/nic_service.log
StandardError=append:/var/log/mx-cIndicator/nic_service.log
ExecStart=/usr/local/Data-source/nic-dropped.sh
EOF

# 2. 定时器单元文件（每90秒执行一次）
cat << 'EOF' > /etc/systemd/system/nic-dropped.timer
[Unit]
Description=Run nic-dropped.sh every 90 seconds (20 times = 30 minutes)

# 开机30秒后首次执行
 # 每次执行后间隔90秒再次执行
 # 系统关机错过执行，开机后补执行（避免遗漏）
[Timer]
OnBootSec=30s          
OnUnitActiveSec=90s   
Persistent=true        

[Install]
WantedBy=timers.target
EOF

# -------------------------- 启动并启用定时器 --------------------------
systemctl daemon-reload
systemctl enable --now nic-dropped.timer  
systemctl restart nic-dropped.timer 