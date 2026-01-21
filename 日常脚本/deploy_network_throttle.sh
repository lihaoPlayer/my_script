#!/bin/bash
set -e

# ================= 基础配置 =================
SCRIPT_DIR="/usr/local/Data-source"
MONITOR_SCRIPT="$SCRIPT_DIR/network_throttle_monitor.sh"
SERVICE_FILE="/etc/systemd/system/network-throttle-monitor.service"
TIMER_FILE="/etc/systemd/system/network-throttle-monitor.timer"
LOG_FILE="/var/log/network-throttle.log"

# 限速配置
BANDWIDTH=10             # Mbps
START_HOUR=20
END_HOUR=22
END_DATE="2026-12-30"    # 结束日期 (格式 YYYY-MM-DD)

# ================= 创建目录 =================
mkdir -p "$SCRIPT_DIR"

# ================= 日志函数 =================
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# ================= 权限检查 =================
if [ "$(id -u)" != "0" ]; then
    echo "错误：请使用 root 运行此脚本" >&2
    exit 1
fi

# ================= 清理旧服务 =================
cleanup() {
    systemctl stop network-throttle-monitor.timer 2>/dev/null || true
    systemctl disable network-throttle-monitor.timer 2>/dev/null || true
    systemctl stop network-throttle-monitor.service 2>/dev/null || true
    systemctl disable network-throttle-monitor.service 2>/dev/null || true
    [ -f "$SERVICE_FILE" ] && rm -f "$SERVICE_FILE"
    [ -f "$TIMER_FILE" ] && rm -f "$TIMER_FILE"
    [ -f "$MONITOR_SCRIPT" ] && rm -f "$MONITOR_SCRIPT"
    systemctl daemon-reload
}
cleanup

# ================= 创建监控脚本 =================
cat > "$MONITOR_SCRIPT" << 'EOF'
#!/bin/bash
SCRIPT_DIR="/usr/local/Data-source"
LOG_FILE="/var/log/network-throttle.log"

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 获取所有非 lo 接口
get_interfaces() {
    find /sys/class/net -maxdepth 1 -type l -printf '%f\n' | grep -v '^lo$'
}

apply_limit() {
    local bw="$1"
    for iface in $(get_interfaces); do
        # 清理旧规则
        tc qdisc del dev "$iface" root 2>/dev/null || true
        tc qdisc del dev "$iface" ingress 2>/dev/null || true
        tc qdisc del dev "$iface" handle ffff: 2>/dev/null || true

        # 添加限速
        tc qdisc add dev "$iface" root handle 1: htb default 10
        tc class add dev "$iface" parent 1: classid 1:10 htb rate "${bw}mbit" ceil "${bw}mbit"

        if tc qdisc show dev "$iface" | grep -q "htb"; then
            log "INFO" "接口 $iface 已限速至 ${bw}Mbps"
        else
            log "WARNING" "接口 $iface 限速失败"
        fi
    done
}

restore_network() {
    for iface in $(get_interfaces); do
        tc qdisc del dev "$iface" root 2>/dev/null || true
        tc qdisc del dev "$iface" ingress 2>/dev/null || true
        tc qdisc del dev "$iface" handle ffff: 2>/dev/null || true
    done
    log "INFO" "网络恢复正常"
}

# ================= 主循环 =================
BANDWIDTH=10
START_HOUR=20
END_HOUR=23
END_DATE="2026-02-14"

while [ "$(date +%Y-%m-%d)" \< "$END_DATE" ]; do
    HOUR=$(date +%H)
    if [ "$HOUR" -ge "$START_HOUR" ] && [ "$HOUR" -lt "$END_HOUR" ]; then
        apply_limit "$BANDWIDTH"
    else
        restore_network
    fi
    sleep 60
done

restore_network
log "INFO" "监控结束，到达结束日期 $END_DATE"
EOF

chmod +x "$MONITOR_SCRIPT"

# ================= 创建 systemd 服务 =================
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Network Throttle Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=$MONITOR_SCRIPT
Restart=always
EOF

# ================= 创建 systemd timer =================
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Network Throttle Monitor Timer

[Timer]
OnBootSec=1min
Unit=network-throttle-monitor.service
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ================= 启用服务 =================
systemctl daemon-reload
systemctl enable --now network-throttle-monitor.timer

echo "✅ 网络限速服务已部署：每天 ${START_HOUR}:00-${END_HOUR}:00 限速 ${BANDWIDTH}Mbps"
echo "日志查看：tail -f $LOG_FILE"
