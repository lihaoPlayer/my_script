#!/bin/bash
set -e

# 1. 检查依赖（bc/grep/awk/tail/date，无则自动安装）
check_dependency() {
    local dep=$1
    if ! command -v $dep &> /dev/null; then
        echo "安装${dep}工具..."
        if [ -f /etc/redhat-release ]; then
            yum install -y $dep &> /dev/null
        else
            apt update &> /dev/null && apt install -y $dep &> /dev/null
        fi
    fi
}
check_dependency "bc"
check_dependency "grep"
check_dependency "awk"
check_dependency "tail"
check_dependency "date"

# 2. 创建系统日志错误率采集脚本
script_path="/usr/local/Data-source/syslog-error-rate.sh"
mkdir -p /usr/local/Data-source
cat << 'EOF' > "$script_path"
#!/bin/bash
# 基础配置
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/syslog_error_rate.prom"
tmp_file="${output_file}.tmp"
mkdir -p "$output_dir" &> /dev/null

# 1. 获取平台信息
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

# 2. 核心配置
LOG_FILE="/var/log/messages"
TIME_RANGE=5
TAIL_LINES=2000
ERROR_KEYWORDS="ERROR|error|Failed|failed|FATAL|fatal|CRITICAL|critical|Warning|warning"

# 3. 前置检查：日志文件不存在则直接退出
if [ ! -f "$LOG_FILE" ] || [ ! -r "$LOG_FILE" ]; then
    exit 0
fi

# 4. 初始化临时文件
> "$tmp_file"
planform=$(get_planform)

# 5. 极速统计最近5分钟日志错误率
# 5.1 生成时间匹配维度
current_time=$(date +"%b %d %H %M")
log_month=$(echo "$current_time" | awk '{print $1}')
log_day=$(echo "$current_time" | awk '{print $2}')
log_hour=$(echo "$current_time" | awk '{print $3}')
current_min=$(echo "$current_time" | awk '{print $4}')

# 5.2 计算5分钟前的分钟数
start_min=$((current_min - TIME_RANGE))
cross_hour=0
if [ $start_min -lt 0 ]; then
    start_min=$((start_min + 60))
    log_hour=$((log_hour - 1))
    [ $log_hour -lt 0 ] && log_hour=23 && cross_hour=1
fi

# 5.3 筛选+统计
stats=$(tail -n $TAIL_LINES $LOG_FILE | awk -v mon="$log_month" -v day="$log_day" -v hour="$log_hour" -v s_min="$start_min" -v c_min="$current_min" -v cross="$cross_hour" -v kw="$ERROR_KEYWORDS" '
BEGIN {total=0; error=0}
{
    # 跳过格式异常行
    if (NF < 3) next;
    l_mon=$1; l_day=$2; split($3, hm, ":");
    if (length(hm) < 2) next;
    l_h=hm[1]+0; l_m=hm[2]+0;
    
    # 匹配同天同月的日志
    if (l_mon != mon || l_day != day) next;
    
    # 匹配最近5分钟时间范围
    if (cross == 1) {
        if ((l_h == hour && l_m >= s_min) || (l_h == hour+1 && l_m <= c_min)) {
            total++; if($0~kw) error++;
        }
    } else {
        if (l_h == hour && l_m >= s_min && l_m <= c_min) {
            total++; if($0~kw) error++;
        }
    }
}
END {print total","error}
')

# 6. 计算错误率
TOTAL_LOGS=$(echo "$stats" | cut -d',' -f1 2>/dev/null || echo 0)
ERROR_LOGS=$(echo "$stats" | cut -d',' -f2 2>/dev/null || echo 0)
ERROR_RATE=0.0000  # 默认0.0000（四位小数）
if [ "$TOTAL_LOGS" -gt 0 ] && [ "$ERROR_LOGS" -gt 0 ]; then
    # 第一步：bc计算原始值（可能输出.1050）
    raw_rate=$(echo "scale=3; $ERROR_LOGS / $TOTAL_LOGS" | bc 2>/dev/null || echo 0.0000)
    # 第二步：补前导零
    ERROR_RATE=$(echo "$raw_rate" | awk '{if ($0 ~ /^\./) print "0"$0; else print $0}')
fi

# 7. 写入Prometheus格式指标
echo "# HELP syslog_error_rate_percent 系统日志错误率（原始小数，0-1范围，统计最近${TIME_RANGE}分钟）" >> "$tmp_file"
echo "# TYPE syslog_error_rate_percent gauge" >> "$tmp_file"
echo "syslog_error_rate_percent{log=\"messages\",planform=\"$planform\"} $ERROR_RATE" >> "$tmp_file"

# 8. 原子替换正式文件
mv -f "$tmp_file" "$output_file"

exit 0
EOF
chmod +x "$script_path"

# 3. 创建systemd服务文件
cat > /etc/systemd/system/syslog-errRate.service << 'EOF'
[Unit]
Description=Syslog Error Rate Collection Script
After=syslog.target

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/syslog-error-rate.sh
TimeoutSec=30
ProtectSystem=off
EOF

# 4. 创建systemd定时器文件
cat > /etc/systemd/system/syslog-errRate.timer << 'EOF'
[Unit]
Description=Run Syslog Error Rate Collection Every 5 Minutes

[Timer]
Unit=syslog-errRate.service
OnBootSec=30
OnUnitInactiveSec=300
Persistent=yes
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

# 5. 设置文件权限
chmod 644 /etc/systemd/system/syslog-errRate.service
chmod 644 /etc/systemd/system/syslog-errRate.timer

# 6. 重新加载并启用定时器
systemctl daemon-reload
systemctl disable --now syslog-errRate.service &> /dev/null || true
systemctl disable --now syslog-errRate.timer &> /dev/null || true
systemctl start syslog-errRate.service &> /dev/null || true
systemctl enable --now syslog-errRate.timer &> /dev/null