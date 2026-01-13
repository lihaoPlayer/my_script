#!/bin/bash
set -e

# ================== 基础配置 ==================
script_dir="/usr/local/Data-source"
script_file="$script_dir/Block_Bandwidth.sh"
output_dir="/var/log/mx-cIndicator"
hostname_file="/allconf/hostname.conf"  # 保留模板变量（未使用但兼容）

# ================== 1. 创建目录（静默执行） ==================
mkdir -p "$script_dir" "$output_dir" >/dev/null 2>&1

# ================== 2. 写入核心脚本（修复必生成文件问题） ==================
cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail  # 严格的错误检查

# ================== 基础配置 ==================
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/ks_LH.prom"
tmp_file="$output_dir/ks_LH.tmp"
base_url="http://103.215.140.118:4433/provider/lfsy3289476"

# ================== 函数定义 ==================
# 1. 获取平台信息
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

# 2. 清理临时文件
cleanup() {
    rm -f "${output_dir}/temp_download.txt"
}
trap cleanup EXIT

# ================== 前置检查 ==================
if [ ! -w "$output_dir" ]; then
    echo "错误: 对目录 $output_dir 没有写入权限" >&2
    exit 1
fi

# ================== 核心逻辑 ==================
# 初始化指标值：默认未拉黑（值为1）
metric_value=1
# 初始化标签默认值
interface="unknown"
threshold_mbps="0"
blacklist_mbps="0"
blacklisted_flag="false"
planform=$(get_planform)

# 主动清理历史临时文件
find "$output_dir" -maxdepth 1 -name "temp_download.txt" -type f -mtime +1 -delete 2>/dev/null || true

# 1. 获取GUID
GUID=$(ps -ef | grep ksp2p | grep -oP '(?<=--guid=)[^ ]*' | head -n 1)
if [ -n "$GUID" ]; then
    # 2. 构建日期和URL
    PREVIOUS_DATE=$(date -d "yesterday" +"%Y%m%d")
    full_url="${base_url}/${PREVIOUS_DATE}/limitNodeList/limitNodeList.txt" 

    # 3. 下载数据（静默）
    curl -s -o "${output_dir}/temp_download.txt" "$full_url"
    
    # 4. 检查下载文件非空，且能匹配到GUID → 代表被拉黑
    if [ -s "${output_dir}/temp_download.txt" ] && grep -q " $GUID " "${output_dir}/temp_download.txt"; then
        # 核心逻辑：匹配到GUID = 被拉黑 → 值为0
        metric_value=0
        blacklisted_flag="true"
        
        # 提取拉黑记录的字段（保持原有逻辑）
        line=$(grep " $GUID " "${output_dir}/temp_download.txt" | head -n 1)
        interface=$(echo "$line" | awk '{print $4}' || echo "unknown")
        threshold=$(echo "$line" | awk '{print $11}' || echo "0")
        blacklist=$(echo "$line" | awk '{print $12}' || echo "0")
        
        # 单位转换：Gbps → Mbps，清理小数点后无效0
        threshold_mbps=$(echo "$threshold * 1000" | bc -l | sed -E 's/\.0+$//; s/\..*//; s/^$/0/')
        blacklist_mbps=$(echo "$blacklist * 1000" | bc -l | sed -E 's/\.0+$//; s/\..*//; s/^$/0/')
    fi
fi

# ================== 强制生成新文件（所有场景必执行） ==================
> "$tmp_file"
echo "# HELP Ks_block_bandwidth Combined network metrics with threshold and blacklist values" >> "$tmp_file"
echo "# TYPE Ks_block_bandwidth gauge" >> "$tmp_file"
echo "Ks_block_bandwidth{interface=\"$interface\", planform=\"$planform\", blacklist_mbps=\"$blacklist_mbps\",threshold_mbps=\"$threshold_mbps\", blacklisted=\"$blacklisted_flag\"} $metric_value" >> "$tmp_file"

# 原子替换正式文件，覆盖旧文件
mv -f "$tmp_file" "$output_file"

# ================== 完成 ==================
echo "成功生成指标文件: $output_file，拉黑状态：$blacklisted_flag，指标值：$metric_value"
exit 0
EOF

# 赋予执行权限
chmod +x "$script_file"

# ================== 3. 创建systemd服务文件（标准化） ==================
cat > /etc/systemd/system/Block_Bandwidth.service << 'EOF'
[Unit]
Description=Run Block_Bandwidth.sh script to check for ks Block
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/Block_Bandwidth.sh
TimeoutSec=30
ProtectSystem=off
StandardOutput=null
StandardError=journal+console
EOF

# ================== 4. 创建systemd定时器文件（标准化） ==================
cat > /etc/systemd/system/Block_Bandwidth.timer << 'EOF'
[Unit]
Description=Run Block_Bandwidth.sh daily at 12:00 PM

[Timer]
OnCalendar=*-*-* 12:00:00
Persistent=true
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

# ================== 5. 启动配置（静默执行，和模板对齐） ==================
chmod 644 /etc/systemd/system/Block_Bandwidth.service
chmod 644 /etc/systemd/system/Block_Bandwidth.timer

systemctl daemon-reload >/dev/null 2>&1
systemctl disable --now Block_Bandwidth.service >/dev/null 2>&1 || true
systemctl disable --now Block_Bandwidth.timer >/dev/null 2>&1 || true
systemctl start Block_Bandwidth.service >/dev/null 2>&1 || true
systemctl enable --now Block_Bandwidth.timer >/dev/null 2>&1