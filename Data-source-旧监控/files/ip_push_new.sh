#!/bin/bash

# 2. 创建执行脚本
script_path="/usr/local/Data-source/ip_push.sh"
cat << 'EOF' > "$script_path" 
#!/bin/bash

# 检查并加载Realtek驱动
load_realtek_driver() {
   
    # 尝试移除现有驱动（如果有）
    sudo /usr/sbin/rmmod r8169 2>/dev/null
    
    # 加载驱动
    if sudo /usr/sbin/modprobe r8169; then
        # 等待驱动完全初始化
        sleep 3
        return 1
    else
        return 1
    fi
}

# 接口配置 - 使用环境变量，如果没有则使用默认值
API_URL="https://service.chxyun.cn/client/node/updateIp"

API_TOKEN="EB935730CBFB9BE6A216CC27BD4906C5"

# 检查并安装smallnode_control（如果不存在）
check_and_install_smallnode_control() {
    if ! command -v smallnode_control &> /dev/null; then
        exit 1
    fi
}

# 获取拨号账号和IP信息
get_network_info() {
    json_output=$(smallnode_control -f --json 2>/dev/null)
    
    if [ -z "$json_output" ]; then
        exit 1
    fi
    
    # 检查是否存在interface_list数组
    if echo "$json_output" | jq -e '.interface_list' >/dev/null 2>&1; then
        array_length=$(echo "$json_output" | jq '.interface_list | length')
        
        accounts=()
        ips=()
        ipv6s=()
        macs=()
        check_nets=()
        int_ips=()
        check_nets_v6=()
        for ((i=0; i<$array_length; i++)); do
            element=$(echo "$json_output" | jq -r ".interface_list[$i]")
            
            ip=$(echo "$element" | jq -r '.ip // .Ip // empty')
            username=$(echo "$element" | jq -r '.username // .account // empty')
            ipv6=$(echo "$element" | jq -r '.ipv6 // empty')
            mac=$(echo "$element" | jq -r '.mac // empty')
            check_net=$(echo "$element" | jq -r '.check_net // empty')
            int_ip=$(echo "$element" | jq -r '.int_ip // empty')
            check_net_v6=$(echo "$element" | jq -r '.check_net_ipv6 // empty')
            
            # 转换网络状态值为指定格式
            case "$check_net" in
                "") check_net="None" ;;
                "ERROR") check_net="ERR" ;;
            esac
            
            case "$check_net_v6" in
                "") check_net_v6="None" ;;
                "ERROR") check_net_v6="ERR" ;;
            esac
            
            # 即使某些字段为空也保留该拨号账号
            accounts+=("$username")
            ips+=("$ip")
            ipv6s+=("$ipv6")
            macs+=("$mac")
            check_nets+=("$check_net")
            int_ips+=("$int_ip")
            check_nets_v6+=("$check_net_v6")
            
        done
        
        if [ ${#accounts[@]} -eq 0 ]; then
            exit 1
        fi
        
        export accounts
        export ips
        export ipv6s
        export macs
        export check_nets
        export int_ips
        export check_nets_v6
    else
        exit 1
    fi
}
# 上报信息到API
report_to_api() {
    if [ ${#accounts[@]} -eq 0 ] || [ ${#ips[@]} -eq 0 ]; then
       
        exit 1
    fi

    # 使用循环构建合法的 JSON 数组
    json_payload="["
    first=true
    for i in "${!accounts[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            json_payload+="," 
        fi
        json_payload+="{\"token\": \"$API_TOKEN\", \"dial_up_account\": \"${accounts[$i]}\", \"ip\": \"${ips[$i]}\", "
        json_payload+="\"ipv6\": \"${ipv6s[$i]}\", \"mac\": \"${macs[$i]}\", "
        json_payload+="\"is_intranet_ip\": \"${int_ips[$i]}\", \"check_net_v4\": \"${check_nets[$i]}\", "
        json_payload+="\"check_net_v6\": \"${check_nets_v6[$i]}\""
        json_payload+=",\"machine_mac\": \"$machine_mac\"}"

    done
    json_payload+="]"

    

    # 发送请求到API
    local response=$(curl --request POST \
        --url "$API_URL" \
        --header 'Accept: */*' \
        --header 'Accept-Encoding: gzip, deflate, br' \
        --header "Authorization: Bearer $API_TOKEN" \
        --header 'Connection: keep-alive' \
        --header 'Content-Type: application/json' \
        --header 'User-Agent: PostmanRuntime-ApipostRuntime/1.1.0' \
        --data "$json_payload" \
        --silent \
        --show-error \
        --write-out "HTTP_STATUS:%{http_code}")

    local status=$?
    echo "API响应详情:"
    echo "$response"

    if [ $status -ne 0 ]; then
        exit 1
    fi

    local success=$(echo "$response" | jq -r '.msg == "修改成功"' 2>/dev/null)

    if [ "$success" = "true" ]; then
        echo "信息上报成功:"
        for i in "${!accounts[@]}"; do
            echo "拨号账号: ${accounts[$i]}, IP地址: ${ips[$i]}, IPv6: ${ipv6s[$i]}, MAC: ${macs[$i]}, 内网IP标志: ${int_ips[$i]}, 网络检测v6状态: ${check_nets_v6[$i]}, 网络检测v4状态: ${check_nets[$i]}, 设备SN: $machine_mac"
        done
    else
        local error_msg=$(echo "$response" | jq -r '.msg // "未知错误"' 2>/dev/null)
        echo "信息上报失败: $error_msg"
        exit 1
    fi
}

# 新增 extract_machine_mac 函数
extract_machine_mac() {
    if [ -f "/allconf/hostname.conf" ]; then
        machine_mac=$(grep -oP '(?<=hostname=).*' /allconf/hostname.conf)
        if [ -z "$machine_mac" ]; then 
            exit 1  
        fi
    else
        exit 1
    fi
}

# 确保 last_ips 是全局变量
declare -a last_ips

# 新增 check_ip_change 函数
check_ip_change() {
    new_ips=("${ips[@]}")
    
    # 添加详细日志以便调试
  
    
    if [ -z "${last_ips+x}" ]; then
    
        last_ips=("${new_ips[@]}")
        return 0
    fi
    
    changed=false
    for i in "${!new_ips[@]}"; do
        if [ "${new_ips[$i]}" != "${last_ips[$i]}" ]; then
        
            changed=true
        fi
    done
    
    if $changed; then
    
        last_ips=("${new_ips[@]}")  # 更新为新的IP地址
        report_to_api
    fi
}

# 更新主函数 main
main() {
    # 检查并安装必要工具
    check_and_install_smallnode_control
    
    # 检查jq是否安装
    if ! command -v jq &> /dev/null; then
        exit 1
    fi
    
    # 提取设备SN
    extract_machine_mac
    
    # 初始化网络信息
    get_network_info
    
    # 首次上报信息
    report_to_api
    
    # 定时检查IP变化
     while true; do
    #     echo "等待120秒后再次检查IP地址..."
        sleep 10
    #     
    #     # 获取最新网络信息
         get_network_info
    #     
    #     # 检测IP变化并重新上报
         check_ip_change
        done
}


# 执行主函数
main 
EOF

# 赋予脚本执行权限
chmod +x "$script_path"

# 3. 创建服务单元文件
cat <<'EOF' > /etc/systemd/system/ip-push.service
[Unit]
Description=IP PUSH Service
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/usr/local/Data-source
ExecStart=/usr/local/Data-source/ip_push.sh
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog




[Install]
WantedBy=multi-user.target
EOF

# 4. 重新加载systemd配置
systemctl daemon-reload

# 5. 启用并启动服务
systemctl enable ip-push.service
systemctl start ip-push.service