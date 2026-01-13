#!/bin/bash
set -e

# 1. 检查jq依赖（无则安装）
if ! command -v jq &> /dev/null; then
    echo "安装jq工具..."
    [ -f /etc/redhat-release ] && yum install -y jq &> /dev/null || apt update && apt install -y jq &> /dev/null
fi

# 2. 创建ppp-status.sh脚本（核心：无smallnode_control则不执行命令）
script_path="/usr/local/Data-source/ppp-status.sh"
mkdir -p /usr/local/Data-source
cat << 'EOF' > "$script_path"
#!/bin/bash
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/ppp-status.prom"
mkdir -p "$output_dir" &> /dev/null
> "$output_file"

# 1. 获取planform（默认mx）
get_planform() {
    local target="/usr/bin/issue.sh"
    local pf="mx"
    if [ -r "$target" ]; then
        local ch=$(grep -E "qrencode.*portal.chxyun.cn.*version=" "$target" 2>/dev/null | head -n1)
        if [ -n "$ch" ]; then
            local v=$(echo "$ch" | sed -n 's/.*version=//p' | sed 's/[&" ].*//')
            [ "$v" != "010" ] && [ "$v" != "1" ] && pf="unknown"
        else
            local sm=$(grep -E "qrencode.*smogfly.com.*version=" "$target" 2>/dev/null | head -n1)
            if [ -n "$sm" ]; then
                local v=$(echo "$sm" | sed -n 's/.*version=//p' | sed 's/[&" ].*//')
                [ "$v" = "012" ] || [ "$v" = "2" ] && pf="wc" || pf="unknown"
            fi
        fi
    fi
    echo "$pf"
}
planform=$(get_planform)

# 2. 关键判断：无smallnode_control -l则不执行后续命令
if ! command -v smallnode_control &> /dev/null || ! smallnode_control -l &> /dev/null; then
    exit 0  # 不存在/执行失败，直接退出，不报错
fi

# 3. 生成PPP指标（仅当smallnode_control -l有效时执行）
json=$(smallnode_control -l --json 2>/dev/null)
if ! echo "$json" | jq empty 2>/dev/null; then exit 0; fi

echo "# HELP ppp_status PPP状态(1=UP,0=DOWN)" >> "$output_file"
echo "# TYPE ppp_status gauge" >> "$output_file"

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
    echo "ppp_status{interface=\"$iface\",username=\"$user\",password=\"$pwd\",bandwidth=\"$bw\",vlan_id=\"$vlan\",status=\"$stat\",ip=\"$ip\",mac=\"$mac\",planform=\"$planform\"} $val" >> "$output_file"
done
exit 0
EOF
chmod +x "$script_path"

# 3. 创建systemd服务和定时器
cat << 'EOF' > /etc/systemd/system/ppp-status.service
[Unit]
Description=PPP Status Script
After=network.target
[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/ppp-status.sh
EOF

cat << 'EOF' > /etc/systemd/system/ppp-status.timer
[Unit]
Description=Run PPP Status Every 90s
[Timer]
OnBootSec=30s
OnUnitInactiveSec=90s
Persistent=true
[Install]
WantedBy=timers.target
EOF

# 4. 启动定时器（服务由定时器触发）
systemctl daemon-reload
systemctl enable --now ppp-status.timer
systemctl restart ppp-status.service

