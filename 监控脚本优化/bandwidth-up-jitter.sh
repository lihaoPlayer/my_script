#!/bin/bash
set -e  # 出错立即终止

# 基础配置（删除hostname_file，其余不变）
script_dir="/usr/local/Data-source"
script_file="$script_dir/bandwidth-up-jitter.sh"
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/bandwidth_up_jitter.prom"
tmp_file="$output_dir/bandwidth_up_jitter.tmp"

# ================== 1. 创建目录（静默执行） ==================
mkdir -p "$script_dir" "$output_dir" >/dev/null 2>&1

# ================== 2. 写入上行带宽抖动采集脚本（移除所有hostname逻辑） ==================
cat > "$script_file" << 'EOF'
#!/bin/bash
set -euo pipefail

##获取平台信息（保留原逻辑）
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

# 基础配置（删除hostname_file，其余不变）
output_file="/var/log/mx-cIndicator/bandwidth_up_jitter.prom"
tmp_file="/var/log/mx-cIndicator/bandwidth_up_jitter.tmp"
collect_interval=1  # 1秒间隔采集（瞬时抖动）
jitter_scale=3      # 抖动率保留三位小数
default_jitter="0.000"

# 初始化临时文件
> "$tmp_file"
cat > "$tmp_file" << EOM
# HELP bandwidth_up_jitter_ratio 上行带宽瞬时抖动率（仅真实物理网卡，原始小数，0-1范围）
# TYPE bandwidth_up_jitter_ratio gauge
EOM

# 仅保留平台信息获取（删除hostname相关）
planform=$(get_planform)

# ================== 核心：筛选真实物理网卡（逻辑不变） ==================
valid_nics=""
up_nics=$(ip -br a | grep -E ' +UP +' | awk '{print $1}' 2>/dev/null)
for nic in $up_nics; do
    # 关键判断：存在device目录=真实物理网卡，虚拟网卡无此目录
    [ -d "/sys/class/net/${nic}/device" ] && valid_nics="$valid_nics $nic"
done
valid_nics=$(echo "$valid_nics" | xargs)  # 去空格

# 兜底：无真实网卡则写入默认值（移除hostname标签）
if [ -z "$valid_nics" ]; then
    echo "bandwidth_up_jitter_ratio{planform=\"$planform\"} $default_jitter" >> "$tmp_file"
    mv -f "$tmp_file" "$output_file"
    exit 0
fi

# ================== 采集真实网卡的上行字节数（汇总） ==================
# 声明数组存储第一次采集的tx字节数
declare -A tx1_map
total_tx1=0
for nic in $valid_nics; do
    # 采集每个真实网卡的tx_bytes（上行总字节数）
    tx1=$(grep -E "^[[:space:]]*${nic}:" /proc/net/dev | awk '{print $10}' 2>/dev/null || echo 0)
    tx1_map[$nic]=$tx1
    total_tx1=$((total_tx1 + tx1))
done

# 第一次休眠（1秒，保证瞬时性）
sleep "$collect_interval"

# 第二次采集，计算第一次瞬时速率
total_tx2=0
for nic in $valid_nics; do
    tx2=$(grep -E "^[[:space:]]*${nic}:" /proc/net/dev | awk '{print $10}' 2>/dev/null || echo 0)
    total_tx2=$((total_tx2 + tx2))
done
rate1=$((total_tx2 - total_tx1))  # 所有真实网卡汇总的第一次瞬时速率（字节/秒）

# 第二次休眠，采集第三次字节数
sleep "$collect_interval"

# 第三次采集，计算第二次瞬时速率
total_tx3=0
for nic in $valid_nics; do
    tx3=$(grep -E "^[[:space:]]*${nic}:" /proc/net/dev | awk '{print $10}' 2>/dev/null || echo 0)
    total_tx3=$((total_tx3 + tx3))
done
rate2=$((total_tx3 - total_tx2))  # 第二次瞬时速率

# ================== 计算瞬时抖动率（核心逻辑不变） ==================
jitter_rate="$default_jitter"
if [ "$rate1" -gt 0 ] && command -v bc &>/dev/null; then
    # 计算速率差值的绝对值
    diff=$((rate2 - rate1))
    [ "$diff" -lt 0 ] && diff=$((diff * -1))
    
    # 计算抖动率：|rate2-rate1| / rate1（保留三位小数）
    jitter_rate=$(echo "scale=$jitter_scale; $diff / $rate1" | bc -l 2>/dev/null || "$default_jitter")
    # 补前导零（如.052→0.052）
    jitter_rate=$(echo "$jitter_rate" | sed -e 's/^\./0./' 2>/dev/null)
fi

# 兜底：非数字则用默认值
if ! echo "$jitter_rate" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    jitter_rate="$default_jitter"
fi

# ================== 写入指标+原子替换（移除hostname标签） ==================
echo "bandwidth_up_jitter_ratio{planform=\"$planform\"} $jitter_rate" >> "$tmp_file"
mv -f "$tmp_file" "$output_file"

exit 0
EOF

# 赋予执行权限
chmod +x "$script_file"

# ================== 3. 创建systemd服务文件（逻辑不变） ==================
cat > /etc/systemd/system/bandwidth-up-jitter.service << 'EOF'
[Unit]
Description=Upstream Bandwidth Jitter Statistics Script (Only Physical NIC)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/bandwidth-up-jitter.sh
TimeoutSec=30
ProtectSystem=off
EOF

chmod 644 /etc/systemd/system/bandwidth-up-jitter.service

# ================== 4. 创建systemd定时器文件（逻辑不变） ==================
cat > /etc/systemd/system/bandwidth-up-jitter.timer << 'EOF'
[Unit]
Description=Run bandwidth jitter script every 10 seconds

[Timer]
Unit=bandwidth-up-jitter.service
OnBootSec=30
OnUnitInactiveSec=10
Persistent=yes
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

chmod 644 /etc/systemd/system/bandwidth-up-jitter.timer

# ================== 5. 启动定时器（静默执行） ==================
systemctl daemon-reload >/dev/null 2>&1
systemctl disable --now bandwidth-up-jitter.service >/dev/null 2>&1 || true
systemctl disable --now bandwidth-up-jitter.timer >/dev/null 2>&1 || true
systemctl start bandwidth-up-jitter.service >/dev/null 2>&1 || true
systemctl enable --now bandwidth-up-jitter.timer >/dev/null 2>&1