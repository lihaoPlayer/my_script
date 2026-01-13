#!/bin/bash

# 配置文件路径
SCRIPT_DIR="/usr/local/Data-source"
MONITOR_SCRIPT="$SCRIPT_DIR/network_throttle_monitor.sh"
SERVICE_FILE="/etc/systemd/system/network-throttle-monitor.service"
LOG_FILE="/var/log/network-throttle.log"

# 确保目录存在
mkdir -p "$SCRIPT_DIR"

# 日志函数 - 只记录到文件，不输出到控制台
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 只记录特定级别的日志到文件
    case "$level" in
        "INFO"|"WARNING"|"ERROR")
            echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
            ;;
    esac
}

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须以root权限运行" >&2
    exit 1
fi

# 检查参数数量
if [ $# -lt 2 ]; then
    echo "用法：" >&2
    echo "  $0 \"开始时间\" \"结束时间\" [带宽]" >&2
    echo "" >&2
    echo "示例：" >&2
    echo "  $0 \"2025-12-01 16:00\" \"2025-12-01 16:10\"       # 默认带宽1Mbps" >&2
    echo "  $0 \"2025-12-01 16:00\" \"2025-12-01 16:10\" 100  # 指定带宽100Mbps" >&2
    exit 1
fi

# 简化参数处理：支持两种格式
start_time="$1"
end_time="$2"

# 带宽参数处理，默认为1Mbps
if [ $# -ge 3 ]; then
    bandwidth="$3"
else
    bandwidth="1"
fi

# 验证时间格式
validate_time_format() {
    local time="$1"
    
    # 检查基本格式 YYYY-MM-DD HH:MM
    if ! [[ "$time" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-2][0-9]:[0-5][0-9]$ ]]; then
        echo "错误：时间格式不正确，应为 'YYYY-MM-DD HH:MM'" >&2
        exit 1
    fi
    
    # 提取并验证具体时间部分
    local year=$(echo "$time" | cut -d'-' -f1)
    local month=$(echo "$time" | cut -d'-' -f2)
    local day=$(echo "$time" | cut -d'-' -f3 | cut -d' ' -f1)
    local hour=$(echo "$time" | cut -d' ' -f2 | cut -d':' -f1)
    local minute=$(echo "$time" | cut -d':' -f2)
    
    # 验证月份
    if [ "$month" -lt 1 ] || [ "$month" -gt 12 ]; then
        echo "错误：月份必须在01-12之间" >&2
        exit 1
    fi
    
    # 验证日期（简化验证，不检查每月具体天数）
    if [ "$day" -lt 1 ] || [ "$day" -gt 31 ]; then
        echo "错误：日期必须在01-31之间" >&2
        exit 1
    fi
    
    # 验证小时
    if [ "$hour" -gt 23 ]; then
        echo "错误：小时必须在00-23之间" >&2
        exit 1
    fi
    
    # 验证分钟
    if [ "$minute" -gt 59 ]; then
        echo "错误：分钟必须在00-59之间" >&2
        exit 1
    fi
}

# 验证时间格式
validate_time_format "$start_time"
validate_time_format "$end_time"

# 验证带宽值是正整数
if ! [[ "$bandwidth" =~ ^[0-9]+$ ]]; then
    echo "错误：带宽必须是正整数（单位：Mbps）" >&2
    exit 1
fi

# 转换为时间戳
start_ts=$(date -d "$start_time" +%s 2>/dev/null)
end_ts=$(date -d "$end_time" +%s 2>/dev/null)
current_ts=$(date +%s)

# 检查时间有效性
if [ -z "$start_ts" ] || [ -z "$end_ts" ]; then
    echo "错误：无法解析时间，请检查输入格式" >&2
    exit 1
fi

if [ "$end_ts" -le "$start_ts" ]; then
    echo "错误：结束时间必须大于开始时间" >&2
    exit 1
fi

# 清理之前的监控服务
cleanup_previous_monitor() {
    local cleaned=false
    
    # 停止并禁用服务
    if systemctl is-active network-throttle-monitor.service &>/dev/null; then
        systemctl stop network-throttle-monitor.service
        systemctl disable network-throttle-monitor.service
        cleaned=true
    fi
    
    # 删除服务文件
    if [ -f "$SERVICE_FILE" ]; then
        rm -f "$SERVICE_FILE"
        cleaned=true
    fi
    
    # 删除监控脚本
    if [ -f "$MONITOR_SCRIPT" ]; then
        rm -f "$MONITOR_SCRIPT"
        cleaned=true
    fi
    
    # 重新加载systemd
    systemctl daemon-reload 2>/dev/null
    
    if [ "$cleaned" = true ]; then
        echo "清理带宽限制服务成功"
    fi
}

# 创建系统服务文件
create_systemd_service() {
    local start_time="$1"
    local end_time="$2"
    local bandwidth="$3"
    
    # 创建服务文件
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Network Throttle Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=$MONITOR_SCRIPT "$start_time" "$end_time" "$bandwidth"
Restart=no

[Install]
WantedBy=multi-user.target
EOF

    # 创建监控脚本
    cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash

# 配置文件路径
SCRIPT_DIR="/usr/local/Data-source"
MONITOR_SCRIPT="$SCRIPT_DIR/network_throttle_monitor.sh"
LOG_FILE="/var/log/network-throttle.log"

# 日志函数 - 只记录到文件，不输出到控制台
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 只记录特定级别的日志到文件
    case "$level" in
        "INFO"|"WARNING"|"ERROR")
            echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
            ;;
    esac
}

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    log "ERROR" "此脚本必须以root权限运行"
    exit 1
fi

# 获取参数
start_time="$1"
end_time="$2"
bandwidth="$3"

log "INFO" "开始执行网络限速监控"
log "INFO" "开始时间: $start_time"
log "INFO" "结束时间: $end_time"
log "INFO" "带宽限制: ${bandwidth}Mbps"

# 转换为时间戳
start_ts=$(date -d "$start_time" +%s 2>/dev/null)
end_ts=$(date -d "$end_time" +%s 2>/dev/null)
current_ts=$(date +%s)

# 验证时间有效性
if [ -z "$start_ts" ] || [ -z "$end_ts" ]; then
    log "ERROR" "无法解析时间参数"
    exit 1
fi

if [ "$end_ts" -le "$start_ts" ]; then
    log "ERROR" "结束时间必须大于开始时间"
    exit 1
fi

# 获取所有网络接口
get_all_interfaces() {
    find /sys/class/net -maxdepth 1 -type l -printf '%f\n' | grep -v '^lo$'
}

# 网络限速函数
apply_network_limit() {
    local bw="$1"
    local interfaces
    interfaces=$(get_all_interfaces)
    
    if [ -z "$interfaces" ]; then
        log "ERROR" "未找到有效的网络接口"
        return 1
    fi
    
    log "INFO" "检测到以下网络接口:"
    echo "$interfaces" >> "$LOG_FILE"
    
    # 对每个接口应用限速
    for iface in $interfaces; do
        # 检查接口是否存在
        if [ ! -e "/sys/class/net/$iface" ]; then
            log "WARNING" "接口 $iface 不存在，跳过"
            continue
        fi
        
        # 检查接口状态
        if ! ip link show dev "$iface" >/dev/null 2>&1; then
            log "WARNING" "接口 $iface 不可用，跳过"
            continue
        fi
        
        # 获取接口的IP地址（用于日志记录）
        local ip_addr=$(ip -4 addr show dev "$iface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
        local mac_addr=$(cat /sys/class/net/"$iface"/address 2>/dev/null)
        
        # 彻底清除现有规则
        tc qdisc del dev "$iface" root 2>/dev/null
        tc qdisc del dev "$iface" ingress 2>/dev/null
        tc qdisc del dev "$iface" handle ffff: 2>/dev/null
        
        # 添加新规则 - 限制为指定带宽
        tc qdisc add dev "$iface" root handle 1: htb default 10
        tc class add dev "$iface" parent 1: classid 1:10 htb rate ${bw}mbit ceil ${bw}mbit
        
        # 检查是否成功
        if tc qdisc show dev "$iface" | grep -q "htb"; then
            local interface_info="接口 $iface"
            [ -n "$ip_addr" ] && interface_info="$interface_info IP: $ip_addr"
            [ -n "$mac_addr" ] && interface_info="$interface_info MAC: $mac_addr"
            log "INFO" "$interface_info 已限速至 ${bw}Mbps"
        else
            log "WARNING" "无法在接口 $iface 上设置限速"
        fi
    done
}

# 恢复网络函数
restore_network() {
    local interfaces
    interfaces=$(get_all_interfaces)
    
    for iface in $interfaces; do
        # 检查接口是否存在
        if [ ! -e "/sys/class/net/$iface" ]; then
            continue
        fi
        
        # 尝试清除规则
        tc qdisc del dev "$iface" root 2>/dev/null
        tc qdisc del dev "$iface" ingress 2>/dev/null
        tc qdisc del dev "$iface" handle ffff: 2>/dev/null
    done
}

# 如果开始时间是未来时间，则等待
if [ "$current_ts" -lt "$start_ts" ]; then
    wait_seconds=$((start_ts - current_ts))
    log "INFO" "等待直到开始时间: $start_time (约 $((wait_seconds/3600)) 小时 $(( (wait_seconds%3600)/60 )) 分钟 $((wait_seconds%60)) 秒)"
    while [ "$(date +%s)" -lt "$start_ts" ]; do
        sleep 1
    done
fi

# 应用网络限速
apply_network_limit "$bandwidth"

# 如果当前时间已经超过结束时间，立即恢复
if [ "$(date +%s)" -ge "$end_ts" ]; then
    log "INFO" "结束时间已过，立即恢复网络"
    restore_network
    
    # 清理服务
    systemctl disable network-throttle-monitor.service 2>/dev/null
    [ -f "/etc/systemd/system/network-throttle-monitor.service" ] && rm -f /etc/systemd/system/network-throttle-monitor.service
    [ -f "$MONITOR_SCRIPT" ] && rm -f "$MONITOR_SCRIPT"
    systemctl daemon-reload 2>/dev/null
    
    log "INFO" "服务已禁用并删除"
    exit 0
fi

# 等待到结束时间
log "INFO" "限速中，将在 $end_time 恢复网络"
while [ "$(date +%s)" -lt "$end_ts" ]; do
    # 每分钟检查一次，避免过于频繁的循环
    sleep 60
done

# 恢复网络
restore_network

# 禁用并删除服务
systemctl disable network-throttle-monitor.service 2>/dev/null
[ -f "/etc/systemd/system/network-throttle-monitor.service" ] && rm -f /etc/systemd/system/network-throttle-monitor.service
[ -f "$MONITOR_SCRIPT" ] && rm -f "$MONITOR_SCRIPT"
systemctl daemon-reload 2>/dev/null

log "INFO" "网络限制已恢复，服务已禁用并删除"
EOF

    # 设置权限
    chmod +x "$MONITOR_SCRIPT"
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用并启动服务
    systemctl enable --now network-throttle-monitor.service
    
    # 检查服务状态
    if systemctl is-active network-throttle-monitor.service &>/dev/null; then
        echo "网络限速服务已成功配置并启动"
    else
        echo "警告：服务可能未成功启动，请检查日志" >&2
    fi
    
    # 显示配置信息
    echo "开始时间: $start_time"
    echo "结束时间: $end_time"
    echo "带宽限制: ${bandwidth}Mbps"
    echo ""
    echo "服务状态检查: systemctl status network-throttle-monitor.service"
    echo "查看实时日志: tail -f $LOG_FILE"
}

# 清理之前的监控服务
cleanup_previous_monitor

# 创建并启动监控服务
create_systemd_service "$start_time" "$end_time" "$bandwidth"