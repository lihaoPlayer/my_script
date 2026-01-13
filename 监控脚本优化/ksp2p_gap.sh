#!/bin/bash
# 2. 创建执行脚本
script_path="/usr/local/Data-source/ksp2p_gap_monitor.sh"
cat << 'EOF' > "$script_path"
#!/bin/bash

# 基础配置（通用路径）
LOG_BASE_DIR="/usr/local/ksp2p-comm/log"
PROM_DIR="/var/log/mx-cIndicator"
PROM_FILE="${PROM_DIR}/ksp2p_gap.prom"
PROM_TMP_FILE="${PROM_FILE}.tmp"
SPECIFIC_ERROR="login rsp error!!! errcode:102"
LOG_CHECK_LINES=100  # 检查的日志行数
CHECK_INTERVAL=90    # 检查间隔为90秒

# 确保目录存在（仅创建目录，无进程时不生成文件）
mkdir -p "$PROM_DIR" || exit 1
mkdir -p "$LOG_BASE_DIR" || exit 1

# 删除prom文件的函数
delete_prom_file() {
    if [ -f "$PROM_FILE" ]; then
        rm -f "$PROM_FILE"
    fi
    # 清理临时文件（避免残留）
    if [ -f "$PROM_TMP_FILE" ]; then
        rm -f "$PROM_TMP_FILE"
    fi
}

# 识别服务类型（plugin/live/none）
get_service_type() {
    if pgrep -f "nexusplugin::worker" > /dev/null; then
        echo "plugin"
    elif pgrep -f "nexuslive::worker" > /dev/null; then
        echo "live"
    else
        echo "none"
    fi
}

# 检查工作进程是否存在（核心前提）
check_worker_process() {
    local service_type=$(get_service_type)
    if [ "$service_type" = "none" ]; then
        return 1  # 无进程
    fi
    return 0
}

# 获取进程PID
get_worker_pid() {
    local service_type=$(get_service_type)
    if [ "$service_type" = "plugin" ]; then
        pgrep -f "nexusplugin::worker" | head -1
    elif [ "$service_type" = "live" ]; then
        pgrep -f "nexuslive::worker" | head -1
    else
        echo ""
    fi
}

# 获取日志文件路径
get_log_file() {
    local service_type=$(get_service_type)
    if [ "$service_type" = "plugin" ]; then
        echo "${LOG_BASE_DIR}/nexusplugin.log"
    elif [ "$service_type" = "live" ]; then
        echo "${LOG_BASE_DIR}/nexuslive.log"
    else
        echo ""
    fi
}

# 获取进程的标签信息
get_ksp2p_labels() {
    # 检查进程是否存在（双重校验）
    if ! check_worker_process; then
        echo "status=\"stopped\""
        return
    fi
    
    local pid=$(get_worker_pid)
    if [ -z "$pid" ]; then
        echo "status=\"stopped\""
        return
    fi
    
    local cmdline=$(ps -p "$pid" -o cmd= 2>/dev/null)
    if [ -z "$cmdline" ]; then
        echo "status=\"unknown\""
        return
    fi
    
    # 提取参数
    local guid=$(echo "$cmdline" | grep -o -- "--guid=[^ ]*" | cut -d= -f2)
    local limited_area=$(echo "$cmdline" | grep -o -- "--limited_area=[^ ]*" | cut -d= -f2)
    
    # 拆分GUID
    local region=""
    if [ -n "$guid" ]; then
        IFS='_' read -r _ region _ _ _ <<< "$guid"
    fi
    
    # 输出标签（含业务类型）
    local service_type=$(get_service_type)
    echo "region=\"$region\",limited_area=\"$limited_area\",service_type=\"$service_type\",status=\"running\""
}

# 更新Prometheus指标
update_prom_metric() {
    local metric_value=$1
    local process_labels=$(get_ksp2p_labels)
    
    # 写入临时文件
    {
        echo "# HELP ksp2p_gap_log Error logs detected in ksp2p/nexuslive service"
        echo "# TYPE ksp2p_gap_log counter"
        echo "ksp2p_gap_log{$process_labels} $metric_value"
    } > "$PROM_TMP_FILE"
    
    # mv替换正式文件
    mv "$PROM_TMP_FILE" "$PROM_FILE"
    chmod 644 "$PROM_FILE"
}

# 主监控循环（核心：无进程直接退出+进程停止删文件）
monitor_loop() {
    # 【脚本启动前提】检查进程是否存在，无进程则删文件+退出
    if ! check_worker_process; then
        delete_prom_file
        echo "错误：未检测到nexusplugin/nexuslive::worker进程，脚本退出"
        exit 1
    fi
    
    # 有进程时初始化指标文件
    update_prom_metric 0
    
    # 初始化变量
    local last_check_time=$(date +%s)
    local error_detected=false
    local process_was_running=true
    
    while true; do
        # 检查进程状态
        if check_worker_process; then
            # 进程正在运行
            if [ "$process_was_running" = false ]; then
                process_was_running=true
                error_detected=false
                last_check_time=$(date +%s)
                update_prom_metric 0
            fi
            
            # 检查对应日志
            local LOG_FILE=$(get_log_file)
            local has_error=false
            if [ -f "$LOG_FILE" ]; then
                local recent_logs=$(tail -n "$LOG_CHECK_LINES" "$LOG_FILE" 2>/dev/null | grep -F "$SPECIFIC_ERROR" | tail -1)
                if [ -n "$recent_logs" ]; then
                    has_error=true
                    error_detected=true
                    last_check_time=$(date +%s)
                fi
            fi
            
            # 更新指标
            if [ "$has_error" = true ]; then
                update_prom_metric 1
            else
                local current_time=$(date +%s)
                if [ $((current_time - last_check_time)) -ge 30 ] && [ "$error_detected" = true ]; then
                    error_detected=false
                    last_check_time=$current_time
                fi
                update_prom_metric 0
            fi
            
        else
            # 【进程停止】删prom文件+退出循环（脚本终止）
            if [ "$process_was_running" = true ]; then
                process_was_running=false
                delete_prom_file
                echo "警告：nexusplugin/nexuslive::worker进程已停止，删除prom文件并退出脚本"
                exit 1
            fi
        fi
        
        # 休眠90秒
        sleep "$CHECK_INTERVAL"
    done
}

# 启动监控循环
monitor_loop
EOF

# 赋予脚本执行权限
chmod +x "$script_path"

# 3. 创建服务单元文件（RestartSec仍为10秒，异常重启无需调整）
cat <<'EOF' > /etc/systemd/system/ksp2p-gap.service
[Unit]
Description=KSP2P/Nexuslive Log Monitor Service
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/local/Data-source
ExecStart=/usr/local/Data-source/ksp2p_gap_monitor.sh
Restart=always
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

# 5. 重启服务（使修改生效）
systemctl restart ksp2p-gap.service >/dev/null 2>&1 || true
systemctl enable ksp2p-gap.service >/dev/null 2>&1 || true

# 6. 检查服务状态
systemctl status ksp2p-gap.service