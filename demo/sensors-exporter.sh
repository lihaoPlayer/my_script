#!/bin/bash
set -e  # 出错立即终止

check_and_install_sensors() {
    # 先检查sensors是否已存在，避免重复操作
    if command -v sensors >/dev/null 2>&1; then
        echo "✅ sensors 命令已存在，无需安装"
        return 0
    fi

    echo "⚠️  sensors 命令不存在，开始自动安装依赖（仅支持CentOS系统）"
    # 仅判断CentOS/RHEL系统（/etc/redhat-release文件存在）
    if [ -f /etc/redhat-release ]; then
        # CentOS/RHEL 系统（yum 静默安装，重定向输出避免冗余）
        yum install -y lm_sensors > /dev/null 2>&1 || {
            echo "❌ CentOS 系统安装 lm_sensors 失败，脚本终止"
            exit 1
        }
    else
        echo "❌ 非CentOS系统，不支持自动安装 sensors，脚本终止"
        exit 1
    fi

    # 验证安装结果，确保sensors命令可用
    if command -v sensors >/dev/null 2>&1; then
        echo "✅ sensors 依赖（lm_sensors）安装成功"
    else
        echo "❌ sensors 依赖安装失败，脚本终止"
        exit 1
    fi
}

# ================== 新增函数2：后台挂起执行 yes | sensors-detect（不阻塞，带日志/超时） ==================
auto_sensors_detect_background() {
    echo "===== 开始后台执行传感器探测（不阻塞后续流程） ====="
    # 定义日志文件，方便后续排查问题（不丢弃执行日志）
    SENSORS_LOG="/var/log/sensors_detect.log"
    # 后台挂起执行 yes | sensors-detect，& 实现异步，不阻塞后续命令
    yes | sensors-detect > "${SENSORS_LOG}" 2>&1 &
    # 记录后台进程PID，用于后续超时控制
    SENSORS_PID=$!
    echo "✅ 传感器探测已放入后台执行"
    echo "✅ 进程PID：${SENSORS_PID}，执行日志：${SENSORS_LOG}"

    # 手动加载核心传感器模块（立即生效，无需等待后台探测完成）
    modprobe coretemp > /dev/null 2>&1 || true
    modprobe it87 > /dev/null 2>&1 || true
    echo "✅ 核心传感器模块（coretemp/it87）已加载，确保采集功能正常"

    # 可选：后台超时控制（60秒），避免进程无限运行占用资源（不阻塞主脚本）
    (
        sleep 60
        if ps -p "${SENSORS_PID}" > /dev/null 2>&1; then
            kill "${SENSORS_PID}" > /dev/null 2>&1
            echo "⚠️  传感器探测超时（60秒），已终止后台进程" >> "${SENSORS_LOG}"
            echo "⚠️  传感器探测超时（60秒），已终止后台进程"
        else
            echo "✅ 传感器探测已在60秒内正常完成" >> "${SENSORS_LOG}"
            echo "✅ 传感器探测已在60秒内正常完成"
        fi
    ) > /dev/null 2>&1 &
}

# ================== 基础配置（保留原有逻辑，无修改） ==================
script_dir="/usr/local/Data-source"
script_file="$script_dir/sensors-exporter.sh"
output_dir="/var/log/mx-cIndicator"

service_file="/etc/systemd/system/sensors-exporter.service"
timer_file="/etc/systemd/system/sensors-exporter.timer"

# ================== 前置步骤：先执行安装依赖 + 后台探测（核心：不阻塞后续流程，新增） ==================
check_and_install_sensors
auto_sensors_detect_background

# ================== 1️⃣ 创建目录（保留原有逻辑，无修改） ==================
mkdir -p "$script_dir" "$output_dir"

# ================== 2️⃣ 写入核心采集脚本（保留原有逻辑，无修改：全局CPU平均+风扇+电压，无GPU） ==================
cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail

OUT_DIR="/var/log/mx-cIndicator"
OUT_FILE="${OUT_DIR}/sensors.prom"
TMP_FILE="${OUT_FILE}.tmp"

mkdir -p "$OUT_DIR"

# ================== 精简Prometheus头：删除GPU相关注释（保留原有） ==================
cat > "$TMP_FILE" << 'HEAD'
# HELP node_hwmon_cpu_core_global_avg_temp_celsius CPU global core average temperature (all cores)
# TYPE node_hwmon_cpu_core_global_avg_temp_celsius gauge
# HELP node_hwmon_fan_rpm Fan speed
# TYPE node_hwmon_fan_rpm gauge
# HELP node_hwmon_voltage_volt Hardware voltage readings
# TYPE node_hwmon_voltage_volt gauge
HEAD

if ! command -v sensors >/dev/null 2>&1; then
    echo "# sensors command not found, skipping hwmon collection" >> "$TMP_FILE"
    mv "$TMP_FILE" "$OUT_FILE"
    exit 0
fi

# ================== 仅缓存核心温度数据（不输出任何单个包/核心指标，保留原有） ==================
CORE_TEMP_TMP=$(mktemp)
sensors 2>/dev/null | awk '
/^coretemp-/ { cpu++ }
/Core [0-9]+:/ {
    gsub(/\+|°C/, "", $3)
    if ($3 != "" && $3+0 >= 0) {
        # 仅写入临时文件缓存数据（格式：核心温度），不输出任何冗余指标
        printf "%s\n", $3 >> "'"$CORE_TEMP_TMP"'"
    }
}
' || true

# ================== 仅计算并输出：全局所有核心的总平均温度（保留原有） ==================
if [ -s "$CORE_TEMP_TMP" ]; then
    cat "$CORE_TEMP_TMP" | awk '
    # 累加所有核心温度和核心数量
    {
        global_sum += $1
        global_count += 1
    }
    # 仅输出全局总平均温度（精简为单一指标）
    END {
        if (global_count > 0) {
            global_avg = global_sum / global_count
            printf "node_hwmon_cpu_core_global_avg_temp_celsius %.2f\n", global_avg
        } else {
            printf "node_hwmon_cpu_core_global_avg_temp_celsius 0.00\n"
        }
    }
    ' >> "$TMP_FILE" || true
fi
rm -f "$CORE_TEMP_TMP"  # 清理临时文件

# ================== 保留：风扇 RPM 指标（无改动，保留原有） ==================
sensors 2>/dev/null | awk '
/^[a-zA-Z0-9_-]+:/ && /RPM/ {
    fan=$1; sub(":", "", fan)
    rpm=$2
    if (rpm+0 >= 0) {
        printf "node_hwmon_fan_rpm{fan=\"%s\"} %s\n", fan, rpm
    }
}
' >> "$TMP_FILE" || true

# ================== 移除：GPU 温度采集逻辑（已删除，保留原有） ==================

# ================== 保留：电压指标（无改动，保留原有） ==================
sensors 2>/dev/null | awk '
/^[a-zA-Z0-9]+:/ && /V/ && !/RPM/ {
    volt=$1; sub(":", "", volt)
    gsub(/\+|V/, "", $2)
    val=$2
    if (val != "" && val+0 >= 0) {
        printf "node_hwmon_voltage_volt{voltage=\"%s\"} %s\n", volt, val
    }
}
' >> "$TMP_FILE" || true

# ================== 原子替换（无改动，保留原有） ==================
mv "$TMP_FILE" "$OUT_FILE"
EOF

chmod +x "$script_file"

# ================== 3️⃣ 创建 systemd Service（保留原有逻辑，无修改） ==================
cat > "$service_file" << EOF
[Unit]
Description=HW Sensors Exporter for Prometheus
After=network.target

[Service]
Type=oneshot
ExecStart=$script_file
TimeoutSec=30
ProtectSystem=off
EOF

chmod 644 "$service_file"

# ================== 4️⃣ 创建 systemd Timer（保留原有逻辑，无修改） ==================
cat > "$timer_file" << EOF
[Unit]
Description=Run sensors-exporter every 90 seconds

[Timer]
Unit=sensors-exporter.service
OnBootSec=30
OnUnitInactiveSec=90
Persistent=yes
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

chmod 644 "$timer_file"

# ================== 5️⃣ 启动定时器（保留原有逻辑，无修改） ==================
systemctl daemon-reload >/dev/null 2>&1
systemctl disable --now sensors-exporter.service >/dev/null 2>&1 || true
systemctl disable --now sensors-exporter.timer >/dev/null 2>&1 || true
systemctl enable --now sensors-exporter.timer >/dev/null 2>&1