#!/bin/bash
set -e

############################################
# 1. 检查并安装 lm_sensors
############################################
check_and_install_sensors() {
    if command -v sensors >/dev/null 2>&1; then
        echo "✅ sensors 已存在"
        return
    fi

    echo "⚠️ sensors 不存在，开始安装 lm_sensors"

    if [ -f /etc/redhat-release ]; then
        yum install -y lm_sensors >/dev/null 2>&1 || {
            echo "❌ lm_sensors 安装失败"
            exit 1
        }
    else
        echo "❌ 非 RHEL/CentOS 系统，不支持自动安装"
        exit 1
    fi

    command -v sensors >/dev/null 2>&1 || {
        echo "❌ sensors 安装后仍不可用"
        exit 1
    }

    echo "✅ lm_sensors 安装完成"
}

############################################
# 2. 后台执行 sensors-detect（不阻塞）
############################################
auto_sensors_detect_background() {
    LOG_FILE="/var/log/sensors_detect.log"

    echo "✅ 后台执行 sensors-detect（不阻塞）"
    nohup sensors-detect --auto </dev/null >"$LOG_FILE" 2>&1 &

    # 常见模块，失败无所谓
    modprobe coretemp >/dev/null 2>&1 || true
    modprobe it87 >/dev/null 2>&1 || true
}

############################################
# 3. 路径定义
############################################
SCRIPT_DIR="/usr/local/Data-source"
SCRIPT_FILE="${SCRIPT_DIR}/sensors-exporter.sh"
OUT_DIR="/var/log/mx-cIndicator"

SERVICE_FILE="/etc/systemd/system/sensors-exporter.service"
TIMER_FILE="/etc/systemd/system/sensors-exporter.timer"

############################################
# 4. 前置执行
############################################
check_and_install_sensors
auto_sensors_detect_background

mkdir -p "$SCRIPT_DIR" "$OUT_DIR"

############################################
# 5. 写入 exporter 脚本（重点：修改指标名，添加 custom_ 前缀）
############################################
cat > "$SCRIPT_FILE" << 'EOF'
#!/bin/bash
set -euo pipefail

OUT_DIR="/var/log/mx-cIndicator"
OUT_FILE="${OUT_DIR}/sensors.prom"
TMP_FILE="${OUT_FILE}.tmp"

mkdir -p "$OUT_DIR"

############################################
# Prometheus 头（修改指标名，添加 custom_ 前缀）
############################################
cat > "$TMP_FILE" << 'HEAD'
# HELP node_hwmon_custom_temp_global_avg_celsius Global average temperature from all hwmon sensors (custom script)
# TYPE node_hwmon_custom_temp_global_avg_celsius gauge
# HELP node_hwmon_custom_fan_rpm Fan speed (custom script)
# TYPE node_hwmon_custom_fan_rpm gauge
# HELP node_hwmon_custom_voltage_volt Hardware voltage readings (custom script)
# TYPE node_hwmon_custom_voltage_volt gauge
HEAD

if ! command -v sensors >/dev/null 2>&1; then
    echo "# sensors command not found" >> "$TMP_FILE"
    mv "$TMP_FILE" "$OUT_FILE"
    exit 0
fi

############################################
# 1️⃣ 采集【所有温度】（修改指标名，添加 custom_ 前缀）
############################################
TEMP_TMP=$(mktemp)

sensors 2>/dev/null | awk '
/°C/ {
    for (i = 1; i <= NF; i++) {
        if ($i ~ /°C/) {
            val = $i
            gsub(/\+|°C/, "", val)
            if (val ~ /^[0-9.]+$/ && val+0 >= 0 && val+0 < 200) {
                print val
            }
        }
    }
}
' > "$TEMP_TMP" || true

if [ -s "$TEMP_TMP" ]; then
    awk '
    {
        sum += $1
        cnt++
    }
    END {
        if (cnt > 0) {
            printf "node_hwmon_custom_temp_global_avg_celsius %.2f\n", sum / cnt
        } else {
            printf "node_hwmon_custom_temp_global_avg_celsius 0\n"
        }
    }
    ' "$TEMP_TMP" >> "$TMP_FILE"
else
    echo "node_hwmon_custom_temp_global_avg_celsius 0" >> "$TMP_FILE"
fi

rm -f "$TEMP_TMP"

############################################
# 2️⃣ 风扇 RPM（修改指标名，添加 custom_ 前缀）
############################################
sensors 2>/dev/null | awk '
/RPM/ {
    name=$1
    sub(":", "", name)
    rpm=$2
    if (rpm ~ /^[0-9]+$/) {
        printf "node_hwmon_custom_fan_rpm{fan=\"%s\"} %s\n", name, rpm
    }
}
' >> "$TMP_FILE" || true

############################################
# 3️⃣ 电压（修改指标名，添加 custom_ 前缀）
############################################
sensors 2>/dev/null | awk '
/ V/ && !/RPM/ {
    name=$1
    sub(":", "", name)
    val=$2
    gsub(/\+|V/, "", val)
    if (val ~ /^[0-9.]+$/) {
        printf "node_hwmon_custom_voltage_volt{voltage=\"%s\"} %s\n", name, val
    }
}
' >> "$TMP_FILE" || true

############################################
# 原子替换
############################################
mv "$TMP_FILE" "$OUT_FILE"
EOF

chmod +x "$SCRIPT_FILE"

############################################
# 6. systemd service
############################################
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=HW Sensors Exporter for Prometheus
After=network.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_FILE
TimeoutSec=30
ProtectSystem=off
EOF

############################################
# 7. systemd timer
############################################
cat > "$TIMER_FILE" << EOF
[Unit]
Description=Run sensors exporter every 90 seconds

[Timer]
OnBootSec=30
OnUnitInactiveSec=90
AccuracySec=1
Persistent=true

[Install]
WantedBy=timers.target
EOF

############################################
# 8. 启动
############################################
systemctl daemon-reload
systemctl disable --now sensors-exporter.service >/dev/null 2>&1 || true
systemctl disable --now sensors-exporter.timer   >/dev/null 2>&1 || true
systemctl start sensors-exporter.service > /dev/null 2>&1
systemctl enable  --now sensors-exporter.timer >/dev/null 2>&1