#!/bin/bash

# 创建 mount-monitor.sh 脚本的完整路径
mount_script_path="/usr/local/Data-source/mount-monitor.sh"

# 创建目标目录（如果不存在）
mkdir -p "$(dirname "$mount_script_path")"

# 创建脚本内容
cat << 'EOF' > "$mount_script_path"
#!/bin/bash

# 设置输出目录和文件
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/mount-status.prom"
temp_file="$output_dir/mount-status.tmp"
history_mounts="$output_dir/history_mounts.txt"

# 创建输出目录
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

# 1. 更可靠的系统盘识别逻辑
# 优先通过/boot分区的父设备识别系统盘
if boot_part=$(findmnt -n -o SOURCE /boot 2>/dev/null); then
    # 移除可能的/dev/前缀，只保留设备名
    boot_part=${boot_part##*/}
    system_disk=$(lsblk -n -o pkname "/dev/$boot_part" 2>/dev/null)
else
    # 从根分区识别系统盘（处理加密分区情况）
    root_part=$(findmnt -n -o SOURCE / 2>/dev/null)
    root_part=${root_part##*/}
    system_disk=$(lsblk -n -o pkname "/dev/$root_part" 2>/dev/null)
    
    # 如果识别到的不是磁盘（可能是分区），继续向上找父设备
    while [ -n "$system_disk" ] && ! lsblk -n -o TYPE "/dev/$system_disk" 2>/dev/null | grep -q disk; do
        system_disk=$(lsblk -n -o pkname "/dev/$system_disk" 2>/dev/null)
    done
fi

# 2. 安全处理：如果系统盘识别失败，默认排除常见系统盘名
if [ -z "$system_disk" ]; then
    echo "Warning: 系统盘识别失败，使用默认排除规则" >&2
    system_disk="sda|vda|hda"  # 常见系统盘名
else
    # 获取系统盘的所有子设备（包括嵌套分区）
    system_children=$(lsblk -n -o NAME "/dev/$system_disk" 2>/dev/null | tr '\n' '|' | sed 's/|$//')
fi

# 3. 构建排除规则：只排除系统盘及其子设备、loop设备
if [ -n "$system_children" ]; then
    exclude_pattern="^($system_disk|$system_children|loop)"
else
    exclude_pattern="^($system_disk|loop)"  # 识别失败时的备选规则
fi

# 4. 获取所有设备并过滤（保留数据盘）
current_mounts=$(lsblk -n -o NAME,MOUNTPOINT | 
    # 清除树形结构前缀（如├─、└─）
    awk '{gsub(/^[├└─│ ]+/, "", $1); print $1 "|" ($2?$2:"")}' | 
    # 应用排除规则，保留数据盘
    grep -Ev "$exclude_pattern" |
    # 过滤空设备名（避免无效条目）
    grep -v '^|')

# 5. 处理输出（确保即使没有历史记录也能输出当前数据盘）
> "$temp_file"

echo "# HELP mount_status Status of data disk mount points (1 = mounted, 0 = unmounted)" > "$output_file"
echo "# TYPE mount_status gauge" >> "$output_file"

# 保存当前设备列表
echo "$current_mounts" > "$output_dir/current_mounts.tmp"

declare -A current_devices
while IFS='|' read -r dev_name dev_mount; do
    if [ -n "$dev_name" ]; then  # 只处理非空设备名
        current_devices["$dev_name"]="$dev_mount"
    fi
done <<< "$current_mounts"

# 处理历史记录中的设备
if [ -f "$history_mounts" ]; then
    while IFS='|' read -r hist_name hist_mount; do
        if [ -n "${current_devices["$hist_name"]}" ]; then
            current_mount="${current_devices["$hist_name"]}"
            status=$([ -n "$current_mount" ] && [ "$current_mount" != "[SWAP]" ] && echo 1 || echo 0)
            echo "mount_status{name=\"$hist_name\", mountpoint=\"$current_mount\",planform=\"$planform\"} $status" >> "$temp_file"
            unset current_devices["$hist_name"]
        else
            echo "mount_status{name=\"$hist_name\", mountpoint=\"$hist_mount\",planform=\"$planform\"} 0" >> "$temp_file"
        fi
    done < "$history_mounts"
fi

# 处理当前新增的设备（确保数据盘被输出）
for dev_name in "${!current_devices[@]}"; do
    dev_mount="${current_devices["$dev_name"]}"
    status=$([ -n "$dev_mount" ] && [ "$dev_mount" != "[SWAP]" ] && echo 1 || echo 0)
    echo "mount_status{name=\"$dev_name\", mountpoint=\"$dev_mount\",planform=\"$planform\"} $status" >> "$temp_file"
done

# 去重并写入最终文件
awk -F'[{}]' '!a[$2]++' "$temp_file" >> "$output_file"

# 更新历史记录
mv "$output_dir/current_mounts.tmp" "$history_mounts"
rm -f "$temp_file"
EOF

# 赋予权限并配置服务
chmod +x "$mount_script_path"

cat << 'EOF' > /etc/systemd/system/mount-monitor.service
[Unit]
Description=Monitor data disks mount status (ensure data disks are included)

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/mount-monitor.sh  # 同步更新脚本路径
EOF

cat << 'EOF' > /etc/systemd/system/mount-monitor.timer
[Unit]
Description=Run mount-monitor.sh every 1 minute and 30 seconds

[Timer]
OnCalendar=*:0/1:30
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl restart mount-monitor.timer
systemctl enable mount-monitor.timer
