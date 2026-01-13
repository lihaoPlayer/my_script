#!/bin/bash

# 获取系统盘
get_system_disk() {
    # 获取引导分区
    bp=$(get_boot_partition)

    # 检查 /sys/block 下的设备
    for name in /sys/block/*; do
        if [[ -e "$name/$bp" ]]; then
            basename "$name"
            return
        fi
    done

    # 如果未找到，使用 lsblk 查找根盘所在的设备
    output=$(lsblk -n -o NAME,TYPE)
    found=false

    # 从后向前遍历 lsblk 输出
    echo "$output" | tac | while read -r line; do
        if [[ $line == *"$bp"* ]]; then
            found=true
        fi

        if ! $found; then
            continue
        fi

        # 找到引导分区后，返回第一个以字母开头的设备
        if [[ ${line:0:1} =~ [a-zA-Z] ]]; then
            echo "$line" | awk '{print $1}'
            return
        fi
    done
}


# 获取引导分区（示例实现）
get_boot_partition() {
    # 这里假设引导分区是 /boot 挂载的分区
    lsblk -n -o NAME,MOUNTPOINT | awk '$2=="/boot"{print $1}'
}

#得到系统盘sdb

#------------------------------------------------------------------------------------------
#先卸载磁盘
umount /cache* >/dev/null 2>&1
umount  /pcdn_data_hdd/* >/dev/null 2>&1



# 获取 /pcdn_data 下的所有挂载点
mount_points=$(mount | grep '/pcdn_data/' | awk '{print $3}')

check_index_on_system_disk() {
    # 获取索引数据挂载点对应的设备
    index_dev=$(findmnt -n -o SOURCE "/pcdn_data/pcdn_index_data" 2>/dev/null)
    [ -z "$index_dev" ] && return 1  # 未挂载返回false
    
    # 获取系统盘名称（不带分区号）
    sys_disk=$(get_system_disk)
    
    # 判断设备是否属于系统盘
    if [[ "$index_dev" == *"$sys_disk"* ]]; then
        echo "警告：/pcdn_data/pcdn_index_data 挂载在系统盘 $sys_disk 上，建议迁移！"
        return 0  # 挂载在系统盘上返回true
    else
        return 1  # 挂载在其他盘返回false
    fi
}

# 检查并卸载 /pcdn_data/pcdn_index_data（如果不在系统盘上）
 if mountpoint -q "/pcdn_data/pcdn_index_data" && ! check_index_on_system_disk; then
    #echo "卸载非系统盘上的 /pcdn_data/pcdn_index_data..."
    umount "/pcdn_data/pcdn_index_data"
fi

# 遍历挂载点
for mount_point in $mount_points; do
    # 排除 /pcdn_data/pcdn_index_data
    if [ "$mount_point" != "/pcdn_data/pcdn_index_data" ]; then
        umount "$mount_point" >/dev/null 2>&1
    fi
done

#------------------------------------------------------------------------------------------
# 初始化计数器
ssd_count=1
hdd_count=1


# 检查是否有/pcdn_data/pcdn_index_data挂载点
check_pcdn_index_mounted() {
    mountpoint -q "/pcdn_data/pcdn_index_data"
    return $?
}


# 分区并格式化磁盘
partition_and_format_disk() {
    local device=$1
    local part1_size=$2
    #清除分区
    # 创建 GPT 分区表
    parted -s "/dev/$device" mklabel gpt
    # 创建第一个分区
    parted -s "/dev/$device" mkpart primary ext4 0% "${part1_size}GB"
    # 创建第二个分区（使用剩余空间）
    parted -s "/dev/$device" mkpart primary ext4 "${part1_size}GB" 100%
    # 通知内核分区表已更改
    partprobe "/dev/$device"

    sleep 3

       # 根据硬盘类型确定分区命名规则
    if [[ $device == nvme* ]]; then
        part1="/dev/${device}p1"
        part2="/dev/${device}p2"
    else
        part1="/dev/${device}1"
        part2="/dev/${device}2"
    fi

    # 格式化分区
    mkfs.xfs -f "$part1"  >/dev/null 2>&1
    mkfs.xfs -f "$part2"  >/dev/null 2>&1

    sleep 5
}

# 创建挂载服务
create_mount_service() {
    local device=$1
    local mount_path=$2
    local mount_disk1=$3
    local mount_disk2=$4
    
    # 获取磁盘uuid
    uuid=$(lsblk -f | grep "$device" | awk '{print $3}')
    
    # 创建 systemd 服务文件
    service_file="/etc/systemd/system/$mount_disk2-$mount_disk1.mount"
    cat << EOF > "$service_file"
[Unit]
Documentation=man:fstab(5) man:systemd-fstab-generator(8)
Before=local-fs.target

[Mount]
What=/dev/disk/by-uuid/$uuid
Where=$mount_path
Type=xfs
Options=defaults

[Install]
WantedBy=multi-user.target
EOF

    # 启用并启动挂载服务
    systemctl daemon-reload
    systemctl start "$mount_disk2-$mount_disk1.mount"
    systemctl enable "$mount_disk2-$mount_disk1.mount"
}

#------------------------------------------------------------------------------------------
# 主逻辑
if ! check_pcdn_index_mounted; then
 #   echo "未找到/pcdn_data/pcdn_index_data挂载点，将选择一块硬盘进行分区..."
    
    # 获取所有非系统盘的SSD磁盘
    sys_disk=$(get_system_disk)
    ssd_disks=()
    
    while IFS= read -r line; do
        device=$(echo "$line" | awk '{print $1}')
        # 跳过系统盘
        if [ "$device" == "$sys_disk" ]; then
            continue
        fi
        # 检查是否是SSD
        disk_type=$(lsblk -d -o name,rota | grep "$device" | awk '{print $2}')
        if [ "$disk_type" == "0" ]; then
            ssd_disks+=("$device")
        fi
    done < <(lsblk -n -o NAME,TYPE | grep disk | awk '{print $1}')
    
    # 如果有SSD磁盘，选择第一个进行分区
    if [ ${#ssd_disks[@]} -gt 0 ]; then
        selected_disk=${ssd_disks[0]}
       # echo "选择磁盘 $selected_disk 进行分区..."
        
        # 分区并格式化
        partition_and_format_disk "$selected_disk" 70
        
        # 创建挂载点
        mkdir -p "/pcdn_data/pcdn_index_data"
        mkdir -p "/pcdn_data/storage1_ssd"
        
       # 根据硬盘类型确定分区命名规则
    if [[ $selected_disk == nvme* ]]; then
                # 创建挂载服务
        create_mount_service "${selected_disk}p1" "/pcdn_data/pcdn_index_data" "pcdn_index_data" "pcdn_data"
        create_mount_service "${selected_disk}p2" "/pcdn_data/storage1_ssd" "storage1_ssd" "pcdn_data"
    else
        create_mount_service "${selected_disk}1" "/pcdn_data/pcdn_index_data" "pcdn_index_data" "pcdn_data"
        create_mount_service "${selected_disk}2" "/pcdn_data/storage1_ssd" "storage1_ssd" "pcdn_data"
    fi

        # 更新计数器
        ssd_count=2
        
        # 处理剩余的磁盘
        for ((i=1; i<${#ssd_disks[@]}; i++)); do
            device=${ssd_disks[$i]}
            format_and_mount_disk "$device"
        done
    else
        echo "警告：没有找到可用的SSD磁盘用于分区！"
    fi
fi

# 格式化并挂载其他磁盘
format_and_mount_disk() {
    local device=$1
    
    # 获取磁盘类型
    disk_type=$(lsblk -d -o name,rota | grep "$device" | awk '{print $2}')
    
    # 格式化磁盘
    mkfs.xfs -f "/dev/$device" >/dev/null 2>&1
    
    sleep 5
    
    # 根据磁盘类型创建挂载目录
    if [ "$disk_type" == "0" ]; then
        mount_path="/pcdn_data/storage${ssd_count}_ssd"
        mount_disk1="storage${ssd_count}_ssd"
        mount_disk2="pcdn_data"
        ssd_count=$((ssd_count + 1))
    else
        mount_path="/pcdn_data_hdd/storage${hdd_count}_hdd"
        mount_disk1="storage${hdd_count}_hdd"
        mount_disk2="pcdn_data_hdd"
        hdd_count=$((hdd_count + 1))
    fi
    mkdir -p "$mount_path"
    
    # 创建挂载服务
    create_mount_service "$device" "$mount_path" "$mount_disk1" "$mount_disk2"
}

# 遍历所有磁盘设备
for device in $(lsblk -n -o NAME,TYPE | grep disk | awk '{print $1}'); do
    # 跳过系统盘
    sys_disk=$(get_system_disk)
    if [ "$device" == "$sys_disk" ]; then
        continue
    fi
    
    # 如果磁盘已经被分区并挂载（如我们刚刚处理的第一块SSD），则跳过
    if lsblk -n -o NAME | grep -q "${device}[0-9]"; then
        #echo "磁盘 $device 已被分区，跳过..."
        continue
    fi
    #nvme
    if [[ $device == nvme* ]] && lsblk -n -o NAME "/dev/$device" | grep -q "[p]1"; then
        continue
    fi

    #sd*

    format_and_mount_disk "$device"
done