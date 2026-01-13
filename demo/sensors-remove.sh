#!/bin/bash
# 脚本名称：cleanup-sensors-exporter.sh
# 功能：彻底清理原有传感器采集脚本、systemd定时器及相关文件（保留指定目录，去掉reset-failed命令）
# 要求：root权限执行

set -euo pipefail

# ================== 配置项（与原有安装脚本对应，无需修改） ==================
SCRIPT_DIR="/usr/local/Data-source"
SCRIPT_FILE="${SCRIPT_DIR}/sensors-exporter.sh"
OUT_DIR="/var/log/mx-cIndicator"
OUT_FILE="${OUT_DIR}/sensors.prom"
SERVICE_FILE="/etc/systemd/system/sensors-exporter.service"
TIMER_FILE="/etc/systemd/system/sensors-exporter.timer"
SENSORS_LOG="/var/log/sensors_detect.log"

# ================== 步骤1：检查是否为root权限（必须） ==================
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用root权限执行该脚本"
    exit 1
fi

# ================== 步骤2：停止并禁用systemd服务和定时器 ==================
systemctl stop sensors-exporter.timer sensors-exporter.service >/dev/null 2>&1 || true
systemctl disable --now sensors-exporter.timer sensors-exporter.service >/dev/null 2>&1 || true
echo "✅ 停止并禁用 sensors-exporter 服务/定时器"

# ================== 步骤3：删除systemd配置文件 ==================
[ -f "$SERVICE_FILE" ] && rm -f "$SERVICE_FILE" && echo "✅ 删除 $SERVICE_FILE" || echo "⚠️  无需删除 $SERVICE_FILE（不存在）"
[ -f "$TIMER_FILE" ] && rm -f "$TIMER_FILE" && echo "✅ 删除 $TIMER_FILE" || echo "⚠️  无需删除 $TIMER_FILE（不存在）"

systemctl daemon-reload >/dev/null 2>&1
echo "✅ 重载systemd配置"

# ================== 步骤4：删除核心采集脚本（保留目录） ==================
if [ -d "$SCRIPT_DIR" ]; then
    [ -f "$SCRIPT_FILE" ] && rm -f "$SCRIPT_FILE" && echo "✅ 删除 $SCRIPT_FILE" || echo "⚠️  无需删除 $SCRIPT_FILE（不存在）"
else
    echo "⚠️  $SCRIPT_DIR 目录不存在，跳过脚本删除"
fi
echo "✅ 保留目录：$SCRIPT_DIR"

# ================== 步骤5：删除指标输出文件（保留目录） ==================
if [ -d "$OUT_DIR" ]; then
    [ -f "$OUT_FILE" ] && rm -f "$OUT_FILE" && echo "✅ 删除 $OUT_FILE" || echo "⚠️  无需删除 $OUT_FILE（不存在）"
    rm -f "${OUT_DIR}/sensors.prom.tmp" >/dev/null 2>&1 || true
else
    echo "⚠️  $OUT_DIR 目录不存在，跳过指标文件删除"
fi
echo "✅ 保留目录：$OUT_DIR"

# ================== 步骤6：删除传感器探测日志 ==================
[ -f "$SENSORS_LOG" ] && rm -f "$SENSORS_LOG" && echo "✅ 删除 $SENSORS_LOG" || echo "⚠️  无需删除 $SENSORS_LOG（不存在）"

# ================== 步骤7：清理完成提示 ==================
echo -e "\n🎉 清理完成！"
echo "✅ 保留关键目录，不影响 lm_sensors 和 node_exporter 自带采集功能"