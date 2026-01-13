#!/bin/bash

# 创建 disk-monitor.sh 脚本的完整路径
disk_script_path="/usr/local/Data-source/disk-monitor.sh"

# 创建目标目录（如果不存在）
mkdir -p "$(dirname "$disk_script_path")"

# 创建脚本内容
cat << 'EOF' > "$disk_script_path"
#!/bin/bash

# 设置输出目录和文件
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/disk-status.prom"

# 创建输出目录（如果不存在）
mkdir -p "$output_dir"

get_planform() {
    local target_script="/usr/bin/issue.sh"
    local version_val=""
    local planform="mx"  # 默认为mx
    
    # 优先级1：优先匹配 portal.chxyun.cn 域名的qrencode命令（原业务域名）
    local chxyun_line=$(grep -E "qrencode.*https://portal.chxyun.cn/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
    if [ -n "$chxyun_line" ]; then
        # 提取portal.chxyun.cn对应的version值
        version_val=$(echo "$chxyun_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
        if [ "$version_val" = "010" ] || [ "$version_val" = "1" ]; then
            planform="mx"
        else
            # 不符合mx版本的情况
            planform="unknown"
        fi
    else
        # 优先级2：匹配 www.smogfly.com 域名的qrencode命令
        local smogfly_line=$(grep -E "qrencode.*https://www.smogfly.com/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
        if [ -n "$smogfly_line" ]; then
            # 提取www.smogfly.com对应的version值
            version_val=$(echo "$smogfly_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
            if [ "$version_val" = "012" ] || [ "$version_val" = "2" ]; then
                planform="wc"
            else
                # 不符合wc版本的情况
                planform="unknown"
            fi
        fi
        # 优先级1和2都不满足时，保持默认的mx
    fi

    echo "$planform"
}

# 调用函数获取 planform 值
planform=$(get_planform) 


# 获取系统中的磁盘列表（排除loop设备），保留name、SERIAL
disks=$(lsblk -d -n -o NAME,SERIAL | grep -v loop)

# 创建或清空输出文件
> "$output_file"

# 写入Prometheus HELP和TYPE信息
echo "# HELP disk_status Status of disk devices (1 = present, 0 = missing)" >> "$output_file"
echo "# TYPE disk_status gauge" >> "$output_file"

# 记录当前检测到的所有磁盘
echo "$disks" | while read -r line; do
    # 提取磁盘信息
    name=$(echo "$line" | awk '{print $1}')
    sn=$(echo "$line" | awk '{print $2}')  # SERIAL作为磁盘SN

    # 对于存在的磁盘，状态设为1
    echo "disk_status{name=\"$name\",  sn=\"$sn\",planform=\"$planform\"} 1" >> "$output_file"
done

# 检查之前记录的磁盘是否有缺失（掉盘）
previous_disks_file="$output_dir/previous_disks.txt"

# 如果存在之前的磁盘记录，进行对比
if [ -f "$previous_disks_file" ]; then
    while read -r prev_name; do
        # 检查当前是否存在该磁盘
        if ! echo "$disks" | grep -q "^$prev_name "; then
            # 从之前的记录中获取该磁盘的详细信息
            prev_details=$(grep "^$prev_name " "$previous_disks_file")
            prev_sn=$(echo "$prev_details" | awk '{print $2}')

            # 掉盘的磁盘状态设为0
            echo "disk_status{name=\"$prev_name\", sn=\"$prev_sn\",planform=\"$planform\"} 0" >> "$output_file"
        fi
    done < <(awk '{print $1}' "$previous_disks_file")
fi

# 保存当前磁盘状态用于下次对比
echo "$disks" > "$previous_disks_file"
EOF

# 赋予脚本可执行权限
chmod +x "$disk_script_path"

# 创建服务单元文件（服务文件仍保留在/etc/systemd/system/目录，不影响功能）
cat << 'EOF' > /etc/systemd/system/disk-monitor.service
[Unit]
Description=Run disk-monitor.sh script to check for disk failures

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/disk-monitor.sh  # 同步更新脚本路径
EOF

# 创建定时器单元文件（修改为1分30秒执行一次）
cat << 'EOF' > /etc/systemd/system/disk-monitor.timer
[Unit]
Description=Run disk-monitor.sh every 1 minute and 30 seconds

[Timer]
OnCalendar=*:0/1:30
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 重新加载systemd配置并启用和启动定时器
systemctl daemon-reload
systemctl enable disk-monitor.timer
systemctl restart disk-monitor.timer
