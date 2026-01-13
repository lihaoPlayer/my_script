#!/bin/bash

rm -rf /pcdn_data/pcdn_index_data/*
rm -rf /pcdn_data/storage*_ssd/*
systemctl stop kubelet
systemctl disable kubelet
docker stop $(docker ps -qa)
docker rm $(docker ps -aq)
docker rmi $(docker images -q)

for service in $(ls /etc/systemd/system/pcdn_data-*.mount 2>/dev/null); do
    systemctl stop "$(basename $service)" >/dev/null 2>&1
    systemctl disable "$(basename $service)" >/dev/null 2>&1
    rm -f "$service"
done

systemctl daemon-reload

declare -A processed_disks

get_system_disk() {
    bp=$(get_boot_partition)
    
    for name in /sys/block/*; do
        if [[ -e "$name/$bp" ]]; then
            basename "$name"
            return
        fi
    done

    output=$(lsblk -n -o NAME,TYPE)
    found=false

    echo "$output" | tac | while read -r line; do
        if [[ $line == *"$bp"* ]]; then
            found=true
        fi

        if ! $found; then
            continue
        fi

        if [[ ${line:0:1} =~ [a-zA-Z] ]]; then
            echo "$line" | awk '{print $1}'
            return
        fi
    done
}

get_boot_partition() {
    lsblk -n -o NAME,MOUNTPOINT | awk '$2=="/boot"{print $1}'
}

format_and_mount_disk() {
    local device=$1
    
    if [[ ${processed_disks[$device]} ]]; then
        return
    fi
    
    processed_disks[$device]=1
    
    mkfs.xfs -f "/dev/$device" >/dev/null 2>&1
    sleep 5
    
    mount_path="/pcdn_data/storage${ssd_count}_ssd"
    mount_disk1="storage${ssd_count}_ssd"
    mount_disk2="pcdn_data"
    ssd_count=$((ssd_count + 1))
    
    mkdir -p "$mount_path"
    create_mount_service "$device" "$mount_path" "$mount_disk1" "$mount_disk2"
}

check_index_on_system_disk() {
    index_dev=$(findmnt -n -o SOURCE "/pcdn_data/pcdn_index_data" 2>/dev/null)
    [ -z "$index_dev" ] && return 1
    
    sys_disk=$(get_system_disk)
    
    if [[ "$index_dev" == *"$sys_disk"* ]]; then
        echo "警告：/pcdn_data/pcdn_index_data 挂载在系统盘 $sys_disk 上，建议迁移！"
        return 0
    else
        return 1
    fi
}

check_pcdn_index_mounted() {
    mountpoint -q "/pcdn_data/pcdn_index_data"
    return $?
}

partition_and_format_disk() {
    local device=$1
    local part1_size=$2
    
    processed_disks[$device]=1
    
    parted -s "/dev/$device" mklabel gpt
    parted -s "/dev/$device" mkpart primary ext4 0% "${part1_size}GB"
    parted -s "/dev/$device" mkpart primary ext4 "${part1_size}GB" 100%
    partprobe "/dev/$device"
    sleep 3

    if [[ $device == nvme* ]]; then
        part1="/dev/${device}p1"
        part2="/dev/${device}p2"
    else
        part1="/dev/${device}1"
        part2="/dev/${device}2"
    fi

    mkfs.xfs -f "$part1"  >/dev/null 2>&1
    mkfs.xfs -f "$part2"  >/dev/null 2>&1
    sleep 5
}

create_mount_service() {
    local device=$1
    local mount_path=$2
    local mount_disk1=$3
    local mount_disk2=$4
    
    uuid=$(blkid -s UUID -o value "/dev/$device" 2>/dev/null)
    
    if [ -z "$uuid" ]; then
        uuid_source="/dev/$device"
    else
        uuid_source="/dev/disk/by-uuid/$uuid"
    fi
    
    service_file="/etc/systemd/system/$mount_disk2-$mount_disk1.mount"
    
    if [ -f "$service_file" ]; then
        systemctl stop "$mount_disk2-$mount_disk1.mount" 2>/dev/null || true
        systemctl disable "$mount_disk2-$mount_disk1.mount" 2>/dev/null || true
        rm -f "$service_file"
    fi
    
    cat << EOF > "$service_file"
[Unit]
Documentation=man:fstab(5) man:systemd-fstab-generator(8)
Before=local-fs.target

[Mount]
What=${uuid_source}
Where=$mount_path
Type=xfs
Options=defaults

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl start "$mount_disk2-$mount_disk1.mount" 2>/dev/null || true
    systemctl enable "$mount_disk2-$mount_disk1.mount" >/dev/null 2>&1
}

umount /cache* >/dev/null 2>&1

mount_points=$(mount | grep '/pcdn_data/' | awk '{print $3}')

if mountpoint -q "/pcdn_data/pcdn_index_data" && ! check_index_on_system_disk; then
    umount "/pcdn_data/pcdn_index_data"
fi

for mount_point in $mount_points; do
    if [ "$mount_point" != "/pcdn_data/pcdn_index_data" ]; then
        umount "$mount_point" >/dev/null 2>&1
    fi
done

ssd_count=1

if ! check_pcdn_index_mounted; then
    sys_disk=$(get_system_disk)
    ssd_disks=()
    
    while IFS= read -r line; do
        device=$(echo "$line" | awk '{print $1}')
        if [ "$device" == "$sys_disk" ]; then
            continue
        fi
        ssd_disks+=("$device")
    done < <(lsblk -n -o NAME,TYPE | grep disk | awk '{print $1}')
    
    if [ ${#ssd_disks[@]} -gt 0 ]; then
        selected_disk=${ssd_disks[0]}
        
        partition_and_format_disk "$selected_disk" 70
        
        mkdir -p "/pcdn_data/pcdn_index_data"
        mkdir -p "/pcdn_data/storage1_ssd"
        
        if [[ $selected_disk == nvme* ]]; then
            create_mount_service "${selected_disk}p1" "/pcdn_data/pcdn_index_data" "pcdn_index_data" "pcdn_data"
            create_mount_service "${selected_disk}p2" "/pcdn_data/storage1_ssd" "storage1_ssd" "pcdn_data"
        else
            create_mount_service "${selected_disk}1" "/pcdn_data/pcdn_index_data" "pcdn_index_data" "pcdn_data"
            create_mount_service "${selected_disk}2" "/pcdn_data/storage1_ssd" "storage1_ssd" "pcdn_data"
        fi

        ssd_count=2
        
        for ((i=1; i<${#ssd_disks[@]}; i++)); do
            device=${ssd_disks[$i]}
            format_and_mount_disk "$device"
        done
    else
        echo "警告：没有找到可用的非系统盘用于分区！"
    fi
fi

for device in $(lsblk -n -o NAME,TYPE | grep disk | awk '{print $1}'); do
    sys_disk=$(get_system_disk)
    if [ "$device" == "$sys_disk" ]; then
        continue
    fi
    
    if lsblk -n -o NAME | grep -q "${device}[0-9]"; then
        continue
    fi
    
    if [[ $device == nvme* ]] && lsblk -n -o NAME "/dev/$device" | grep -q "[p]1"; then
        continue
    fi

    format_and_mount_disk "$device"
done