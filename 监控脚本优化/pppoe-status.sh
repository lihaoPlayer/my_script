#!/bin/bash
set -e

# 1. 检查jq依赖（无则安装）
if ! command -v jq &> /dev/null; then
    echo "安装jq工具..."
    [ -f /etc/redhat-release ] && yum install -y jq &> /dev/null || (apt update &> /dev/null && apt install -y jq &> /dev/null)
fi

# 2. 创建ppp-status.sh脚本（修复语法错误+优化逻辑）
script_path="/usr/local/Data-source/ppp-status.sh"
mkdir -p /usr/local/Data-source
cat << 'EOF' > "$script_path"
#!/bin/bash
# 基础配置：临时文件（仅当有有效数据时使用）
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/ppp-status.prom"
tmp_file="${output_file}.tmp"
mkdir -p "$output_dir" &> /dev/null

# 1. 获取平台信息（仅当后续有需要时才会用到）
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

# 2. 关键判断：无smallnode_control -l则直接安全退出，不修改任何文件
if ! command -v smallnode_control &> /dev/null || ! smallnode_control -l &> /dev/null; then
    exit 0
fi

# 3. 只有工具存在且可用时，才初始化临时文件+处理数据
> "$tmp_file"
planform=$(get_planform)

# 4. 生成PPP指标（仅当smallnode_control -l有效时执行）
json=$(smallnode_control -l --json 2>/dev/null)
# JSON非法时，也直接退出，不修改正式文件（保留历史数据）
if ! echo "$json" | jq empty 2>/dev/null; then
    rm -f "$tmp_file"
    exit 0
fi

# 5. 写入Prometheus基础注释（到临时文件）
echo "# HELP ppp_status PPP状态(1=UP,0=DOWN)" >> "$tmp_file"
echo "# TYPE ppp_status gauge" >> "$tmp_file"

# 6. 遍历JSON生成指标（写入临时文件）
echo "$json" | jq -c '.interface_list[]?' 2>/dev/null | while read d; do
    [ -z "$d" ] && continue
    iface=$(echo "$d" | jq -r '.interface//""')
    user=$(echo "$d" | jq -r '.username//""')
    pwd=$(echo "$d" | jq -r '.password//""' )
    bw=$(echo "$d" | jq -r '.Bandwidth//""')
    vlan=$(echo "$d" | jq -r '.vlan_id//""')
    stat=$(echo "$d" | jq -r '.status//"unknown"')
    ip=$(echo "$d" | jq -r '.ip//""')
    mac=$(echo "$d" | jq -r '.mac//""')
    
    val=$([[ "$(echo "$stat" | tr A-Z a-z)" == "up" ]] && echo 1 || echo 0)
    echo "ppp_status{interface=\"$iface\",username=\"$user\",password=\"$pwd\",bandwidth=\"$bw\",vlan_id=\"$vlan\",status=\"$stat\",ip=\"$ip\",mac=\"$mac\",planform=\"$planform\"} $val" >> "$tmp_file"
done

# 7. 核心：原子替换正式文件（仅当数据生成成功时执行）
mv -f "$tmp_file" "$output_file"

exit 0
EOF
chmod +x "$script_path"

# 3. 创建systemd服务文件（标准化格式+超时配置）
cat > /etc/systemd/system/ppp-status.service << 'EOF'
[Unit]
Description=PPP Status Collection Script
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/ppp-status.sh
TimeoutSec=30
ProtectSystem=off
EOF

# 4. 创建systemd定时器文件（核心：补充Unit关联+标准化配置）
cat > /etc/systemd/system/ppp-status.timer << 'EOF'
[Unit]
Description=Run PPP Status Collection Every 90 Seconds

[Timer]
Unit=ppp-status.service
OnBootSec=30
OnUnitInactiveSec=90
Persistent=yes
AccuracySec=1

[Install]
WantedBy=timers.target
EOF

# 5. 设置文件权限（标准化）
chmod 644 /etc/systemd/system/ppp-status.service
chmod 644 /etc/systemd/system/ppp-status.timer

# 6. 重新加载并启用定时器（服务由定时器触发）
systemctl daemon-reload
systemctl disable --now ppp-status.service &> /dev/null || true
systemctl disable --now ppp-status.timer &> /dev/null || true
systemctl start ppp-status.service &> /dev/null || true
systemctl enable --now ppp-status.timer &> /dev/null
