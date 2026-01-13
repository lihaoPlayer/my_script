#!/bin/bash

# ==================== 1. 业务脚本 ====================
script_path="/usr/local/Data-source/business-type.sh"

cat << 'EOF' > "$script_path"
#!/bin/bash
set -euo pipefail

# 基础配置
API_URL="https://service.chxyun.cn/client/node/queryNodeInfoByAdmin"
AUTH_TOKEN="7552E7071B118CBFFEC8C930455B4297"
CONFIG_FILE="/allconf/hostname.conf"
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/business_type.prom"
tmp_file="$output_dir/business_type.prom.tmp"

# 初始化输出目录
mkdir -p "$output_dir" || exit 1

# 关键优化：不再直接清空目标文件，改为清空/创建临时文件（避免目标文件为空）
> "$tmp_file"

#获取平台信息
get_planform() {
    local target_script="/usr/bin/issue.sh"
    local planform="third"
    [ ! -f "$target_script" ] || [ ! -r "$target_script" ] && { echo "$planform"; return; }
    grep -q "portal.chxyun.cn" "$target_script" 2>/dev/null && planform="mx"
    grep -q "www.smogfly.com" "$target_script" 2>/dev/null && planform="wc"
    echo "$planform"
}

# 调用函数获取 planform 值
planform=$(get_planform)  


# 依赖检查（依赖缺失时仍写入指标，metric_value=1）
dependency_ok=true
if [ ! -x "$(command -v jq)" ]; then
    dependency_ok=false
    dep_error="jq_not_found"
elif [ ! -x "$(command -v curl)" ]; then
    dependency_ok=false
    dep_error="curl_not_found"
elif [ ! -f "$CONFIG_FILE" ]; then
    dependency_ok=false
    dep_error="config_file_missing"
fi

# 提取目标MAC（MAC提取失败归类为“查询业务名失败”）
target_mac=""
if $dependency_ok; then
    target_mac=$(grep "^hostname=" "$CONFIG_FILE" | cut -d'=' -f2- | tr -d '[:space:]')
    if [ -z "$target_mac" ]; then
        dependency_ok=false
        dep_error="mac_extract_failed"
    fi
fi

# 初始化核心变量：默认查询失败，metric_value先设为1
business_type="query_failed"
check_result=true  # 业务检查默认通过（因查询失败时无需验证业务）
metric_value=1     # 核心优化：查询失败时默认值为1


# ------------------- 仅当依赖正常时，执行API查询和业务检查 -------------------
if $dependency_ok; then
    # 构造请求数据 - 使用提取到的MAC地址
    REQUEST_DATA=$(jq -n --arg mac "$target_mac" '{"mac": $mac}')

    # API调用 - 发送包含MAC的请求体
    api_response=$(curl -s -m 60 --connect-timeout 15 --retry 2 --retry-delay 3 \
        -w "HTTP_STATUS:%{http_code}" -X POST "$API_URL" \
        -H "Authorization: Bearer $AUTH_TOKEN" -H "Content-Type: application/json" -d "$REQUEST_DATA")

    # 解析HTTP状态码
    http_status=$(echo "$api_response" | awk -F 'HTTP_STATUS:' '{print $2}')

    # API请求失败（HTTP非200）：保持business_type=query_failed，metric_value=1
    if [ "$http_status" -eq 200 ]; then
        # 提取API响应体
        api_body=$(echo "$api_response" | awk -F 'HTTP_STATUS:' '{print $1}')
        # 验证API返回码（业务码非200：仍归类为查询失败）
        response_code=$(echo "$api_body" | jq -r '.code // 500')
        if [ "$response_code" -eq 200 ]; then
            # 解析业务数据（data为空/Null：归类为查询失败）
            result=$(echo "$api_body" | jq '.data // null')
            if [ "$result" != "null" ] && [ -n "$result" ]; then
                # 提取业务名成功：更新business_type，执行业务检查
                business_type=$(echo "$result" | jq -r '.business_type // "unknown_business"')
                
                # 业务检查逻辑（仅查询成功时执行）
                ksp2p=("快手" "快手直播" "K1跨电信" "K1跨移动" "K1跨联通" "K200扣移动跨电联业务" "K200扣移动跨电信业务" "K200扣移动跨联通业务" "K200扣业务" "小K-30业务" "AK业务")
                t2=("T2业务" "T2省内业务" "T2电联互跨" "T2电联跨移动" "T2移动跨电联" "T2移动跨电信" "T2移动跨联通" "T2_udp业务" "T2_udp省内业务" "T2_udp移动跨电信" "T2_udp移动跨联通")
                d1=("D1业务" "D1-8业务")

                check_result=true
                [[ " ${ksp2p[@]} " =~ " $business_type " ]] && ! ps -ef | grep "ksp2p" | grep -v "grep" > /dev/null && check_result=false
                [[ " ${t2[@]} " =~ " $business_type " ]] && [ "$(uname -r)" != "5.4.119-19-0006" ] && check_result=false
                [[ " ${d1[@]} " =~ " $business_type " ]] && ! systemctl is-active --quiet jdcfrp.service && check_result=false

                # 业务检查结果决定metric_value（仅查询成功时更新）
                metric_value=$([ "$check_result" = true ] && echo 1 || echo 0)
            fi
        fi
    fi
fi


# 所有指标写入临时文件（而非直接写入目标文件）
echo "# HELP business_type 业务部署状态（1=成功/查询失败，0=业务检查失败）" >> "$tmp_file"
echo "# TYPE business_type gauge" >> "$tmp_file"
echo "business_type{business=\"$business_type\",planform=\"$planform\"} $metric_value" >> "$tmp_file"

# 原子重命名：临时文件 → 目标文件（Linux中mv是原子操作，瞬间完成，无空文件间隙）
mv -f "$tmp_file" "$output_file"
EOF

# 赋予脚本执行权限
chmod +x "$script_path"

# ==================== 2. 服务单元文件 ====================
cat << 'EOF' > /etc/systemd/system/business-type.service
[Unit]
Description=Run business-type script

[Service]
Type=oneshot
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/local/Data-source/business-type.sh
TimeoutStartSec=180
EOF

# ==================== 3. 定时器文件 ====================
cat << 'EOF' > /etc/systemd/system/business-type.timer
[Unit]
Description=Run /usr/local/Data-source/business-type.sh daily at 18:20

[Timer]
# 每天18点20分执行
OnCalendar=*-*-* 18:20:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ==================== 4. 生效配置并验证 ====================
systemctl daemon-reload
systemctl disable --now business-type.service >/dev/null 2>&1
systemctl enable --now business-type.timer >/dev/null 2>&1