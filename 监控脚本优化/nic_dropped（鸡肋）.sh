#!/bin/bash
set -euo pipefail

# ==================== 1. 定义脚本路径 ====================
script_path="/usr/local/Data-source/nic-dropped.sh"
parent_dir=$(dirname "$script_path")
mkdir -p "$parent_dir"

# ==================== 2. 写入 nic-dropped.sh 脚本内容 ====================
cat << 'EOF' > "$script_path"
#!/bin/bash
set -euo pipefail

# ==================== 配置项  ====================
# Prom指标文件路径（可直接覆盖原有文件）
PROM_DIR="/var/log/mx-cIndicator"
PROM_FILE="${PROM_DIR}/nic_dropped.prom"
PROM_TMP_FILE="${PROM_DIR}/nic_dropped.prom.tmp"
STATUS_CACHE="${PROM_DIR}/history_nicInfo.txt"

# ==================== 初始化目录/文件 ====================
mkdir -p "${PROM_DIR}"
touch "${STATUS_CACHE}"

# ==================== 函数：获取平台信息 ====================
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

# ==================== 核心函数：识别物理网卡 ====================
get_physical_nics() {
    local net_dir="/sys/class/net"
    for nic in "${net_dir}"/*; do
        nic_name=$(basename "${nic}")
        if [ -d "${net_dir}/${nic_name}/device" ]; then
            echo "${nic_name}"
        fi
    done
}

# ==================== 核心函数：获取网卡当前状态 ====================
get_nic_status() {
    local nic="$1"
    local status=$(ip -br a show "${nic}" 2>/dev/null | awk '{print $2}' | tr '[:lower:]' '[:upper:]')
    echo "${status:-UNKNOWN}"
}

# ==================== 核心逻辑：处理网卡状态+生成Prom指标 ====================
# 清空临时Prom文件
> "${PROM_TMP_FILE}"

# 获取平台标识
planform=$(get_planform)

# 写入Prom指标头部（匹配你的格式）
echo "# HELP nic_dropped Current status of network interfaces (1=currently dropped, 0=normal)" >> "${PROM_TMP_FILE}"
echo "# TYPE nic_dropped gauge" >> "${PROM_TMP_FILE}"

# 遍历所有物理网卡处理状态
while read -r nic; do
    [ -z "${nic}" ] && continue

    # 获取当前状态和历史状态
    current_status=$(get_nic_status "${nic}")
    last_status=$(grep "^${nic}=" "${STATUS_CACHE}" | cut -d'=' -f2- || echo "UNKNOWN")

    # 更新缓存
    if [ "${current_status}" != "${last_status}" ]; then
        sed -i "/^${nic}=/d" "${STATUS_CACHE}" 2>/dev/null || true
        echo "${nic}=${current_status}" >> "${STATUS_CACHE}"
    fi

    # 状态转数值（1=掉线，0=正常）
    case "${current_status}" in
        DOWN) nic_value=1 ;;
        UP) nic_value=0 ;;
        *) nic_value=0 ;;
    esac

    # 写入Prom临时文件
    echo "nic_dropped{interface=\"${nic}\", planform=\"${planform}\"} ${nic_value}" >> "${PROM_TMP_FILE}"

done < <(get_physical_nics)

# 原子替换Prom文件（避免空文件）
mv -f "${PROM_TMP_FILE}" "${PROM_FILE}"

# 权限调整（确保监控进程可读取）
chmod 644 "${PROM_FILE}" "${STATUS_CACHE}"

EOF

# ==================== 4. 给脚本添加执行权限 ====================
chmod +x "$script_path"

# ==================== 5. 创建 systemd 服务文件 ====================
cat << 'EOF' > /etc/systemd/system/nic-dropped.service
[Unit]
Description=Physical NIC Status Monitoring Script
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/nic-dropped.sh
TimeoutSec=30
ProtectSystem=off
EOF

# ==================== 6. 创建 systemd 定时器文件 ====================
cat << 'EOF' > /etc/systemd/system/nic-dropped.timer
[Unit]
Description=Run nic-dropped.sh every 90 seconds (monitor physical nic status)

[Timer]
Unit=nic-dropped.service
OnBootSec=30
OnUnitInactiveSec=90
Persistent=yes
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

# ==================== 7. 重新加载 systemd 配置 + 启用并启动定时器（修复拼写错误+补充服务首次执行） ====================
systemctl daemon-reload
# 清理旧状态
systemctl disable --now nic-dropped.service 2>/dev/null || true
systemctl disable --now nic-dropped.timer 2>/dev/null || true 
systemctl start nic-dropped.service 2>/dev/null || true
# 启用并启动定时器
systemctl enable --now nic-dropped.timer >/dev/null 2>&1

# ==================== 8. 输出部署成功提示 ====================
echo -e "\n✅ 简化版网卡监控脚本部署完成！"
echo "📌 脚本路径：${script_path}"
echo "📌 定时器状态：$(systemctl is-active nic-dropped.timer)"
echo "📌 测试方法：停掉物理网卡后执行 /usr/local/Data-source/nic-dropped.sh 查看Prom值"