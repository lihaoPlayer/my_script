#!/bin/bash
# 2. 创建执行脚本
script_path="/usr/local/Data-source/ksp2p_gap_monitor.sh"
cat << 'EOF' > "$script_path"
#!/bin/bash

# 配置参数
LOG_FILE="/usr/local/ksp2p-comm/log/nexusplugin.log"
PROM_DIR="/var/log/mx-cIndicator"
PROM_FILE="${PROM_DIR}/ksp2p_gap.prom"
SPECIFIC_ERROR="login rsp error!!! errcode:102"

# 调试信息输出
DEBUG_LOG="/tmp/ksp2p_gap_debug.log"
MAX_LOG_SIZE=$((10 * 1024 * 1024))

# 限制调试日志大小的函数
log_debug() {
    # 检查日志文件大小，如果超过限制则清空
    if [ -f "$DEBUG_LOG" ] && [ $(stat -c%s "$DEBUG_LOG" 2>/dev/null || echo 0) -gt $MAX_LOG_SIZE ]; then
        > "$DEBUG_LOG"  # 清空文件
        echo "$(date '+%Y-%m-%d %H:%M:%S') [LOG_ROTATE] 调试日志已清空" >> "$DEBUG_LOG"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$DEBUG_LOG"
}

# 确保目录存在
mkdir -p "$PROM_DIR" || exit 1
mkdir -p "$(dirname "$LOG_FILE")" || exit 1

# 检查KSP2P进程是否存在
check_ksp2p_process() {
    if ! pgrep -f "nexusplugin::worker" > /dev/null; then
        log_debug "KSP2P进程不存在"
        return 1
    fi
    return 0
}

# 初始化指标文件头部
init_prom_file() {
    log_debug "初始化指标文件: $PROM_FILE"
    echo "# HELP ksp2p_gap_log Error logs detected in ksp2p service" > "$PROM_FILE"
    echo "# TYPE ksp2p_gap_log counter" >> "$PROM_FILE"
    chmod 644 "$PROM_FILE"
}

# 清空指标文件内容
clear_prom_file() {
    log_debug "清空指标文件: $PROM_FILE"
    > "$PROM_FILE"  # 清空文件内容
    chmod 644 "$PROM_FILE"
}

# 获取KSP2P进程的标签信息
get_ksp2p_labels() {
    # 检查进程是否存在
    if ! check_ksp2p_process; then
        log_debug "无法获取标签信息：KSP2P进程不存在"
        echo "status=\"stopped\""
        return
    fi
    
    # 查找ksp2p工作进程
    local pid=$(pgrep -f "nexusplugin::worker" | head -1)
    
    if [ -z "$pid" ]; then
        log_debug "无法找到KSP2P进程"
        echo "status=\"stopped\""
        return
    fi
    
    # 获取完整的命令行
    local cmdline=$(ps -p "$pid" -o cmd= 2>/dev/null)
    
    if [ -z "$cmdline" ]; then
        log_debug "无法获取进程命令行信息"
        echo "status=\"unknown\""
        return
    fi
    
    # 提取参数
    local guid=$(echo "$cmdline" | grep -o -- "--guid=[^ ]*" | cut -d= -f2)
    local limited_area=$(echo "$cmdline" | grep -o -- "--limited_area=[^ ]*" | cut -d= -f2)
    local isp=$(echo "$cmdline" | grep -o -- "--isp=[^ ]*" | cut -d= -f2)
    
    # 拆分GUID
    local region=""
    local operator=""
    if [ -n "$guid" ]; then
        IFS='_' read -r _ region operator _ _ <<< "$guid"
    fi
    
    echo "region=\"$region\",operator=\"$operator\",limited_area=\"$limited_area\",isp=\"$isp\",status=\"running\""
}



# 更新Prometheus指标（有错误时）
update_prom_metric_error() {
    local process_labels=$(get_ksp2p_labels)
    
    # 使用文件锁确保并发安全
    (
        flock -x 200
        
        # 重新创建指标文件
        {
            echo "# HELP ksp2p_gap_log Error logs detected in ksp2p service"
            echo "# TYPE ksp2p_gap_log counter"
            echo "ksp2p_gap_log{$process_labels} 1"
        } > "$PROM_FILE"
        
        chmod 644 "$PROM_FILE"
        
        log_debug "已更新指标文件（有错误），当前指标: ksp2p_gap_log{$process_labels} 1"
    ) 200>"${PROM_FILE}.lock"
}

# 更新Prometheus指标（无错误时）
update_prom_metric_normal() {
    local process_labels=$(get_ksp2p_labels)
    
    # 使用文件锁确保并发安全
    (
        flock -x 200
        
        # 重新创建指标文件
        {
            echo "# HELP ksp2p_gap_log Error logs detected in ksp2p service"
            echo "# TYPE ksp2p_gap_log counter"
            echo "ksp2p_gap_log{$process_labels} 0"
        } > "$PROM_FILE"
        
        chmod 644 "$PROM_FILE"
        
        log_debug "已更新指标文件（无错误），当前指标: ksp2p_gap_log{$process_labels} 0"
    ) 200>"${PROM_FILE}.lock"
}

# 主监控循环
monitor_loop() {
    log_debug "开始监控循环"
    
    # 清空指标文件内容
    clear_prom_file
    
    # 初始化指标文件头部
    init_prom_file
    
    # 记录上次检查时间
    local last_check_time=$(date +%s)
    local error_detected=false
    local process_was_running=true
    
    while true; do
        # 检查进程状态
        if check_ksp2p_process; then
            # 进程正在运行
            if [ "$process_was_running" = false ]; then
                log_debug "KSP2P进程已启动"
                process_was_running=true
                # 重置错误状态
                error_detected=false
                update_prom_metric_normal
            fi
            
            # 检查最近的日志（非阻塞方式）
            if [ -f "$LOG_FILE" ]; then
                # 只检查最近1分钟的日志，避免处理过多历史数据
                local recent_logs=$(tail -n 100 "$LOG_FILE" 2>/dev/null | grep -F "$SPECIFIC_ERROR" | tail -1)
                
                if [ -n "$recent_logs" ]; then
                    log_debug "检测到特定错误: $recent_logs"
                    error_detected=true
                    update_prom_metric_error
                    last_check_time=$(date +%s)
                fi
            fi
            
            # 定期检查：如果超过30秒没有错误，且之前检测到错误，则重置为0
            local current_time=$(date +%s)
            if [ $((current_time - last_check_time)) -ge 30 ] && [ "$error_detected" = true ]; then
                log_debug "超过30秒未检测到新错误，重置指标为0"
                error_detected=false
                update_prom_metric_normal
                last_check_time=$current_time
            fi
            
        else
            # 进程已停止
            if [ "$process_was_running" = true ]; then
                log_debug "KSP2P进程已停止"
                process_was_running=false
            fi
        fi
        
        # 等待5秒后再次检查
        sleep 10
    done
}

# 启动监控循环
monitor_loop
EOF

# 赋予脚本执行权限
chmod +x "$script_path"

# 3. 创建服务单元文件
cat <<'EOF' > /etc/systemd/system/ksp2p-gap.service
[Unit]
Description=KSP2P Log Monitor Service
After=network.target


[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/local/Data-source
ExecStart=/usr/local/Data-source/ksp2p_gap_monitor.sh
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=ksp2p-monitor
ExecStartPre=/bin/mkdir -p /usr/local/ksp2p-comm/log
ExecStartPre=/bin/mkdir -p /var/log/mx-cIndicator

[Install]
WantedBy=multi-user.target
EOF

# 4. 重新加载systemd配置
systemctl daemon-reload

# 5. 启用并启动服务
systemctl enable ksp2p-gap.service
systemctl start ksp2p-gap.service

# 6. 检查服务状态
systemctl status ksp2p-gap.service