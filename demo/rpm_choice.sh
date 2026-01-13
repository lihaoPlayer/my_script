#!/bin/bash
# 定义工作目录（本地可写的Packages目录）
PKG_DIR="/root/rocky10_custom_iso/Minimal/Packages"
# 定义备份目录（避免误删）
BACKUP_DIR="/root/rocky10_package_backup"
mkdir -p $BACKUP_DIR

# 定义可删除的包名列表（仅包名，不含目录）
REMOVABLE_PACKAGES=(
# 小众硬件固件
"iwlwifi-dvm-firmware-20251008-15.8.el10_0.noarch.rpm"
"iwlwifi-mvm-firmware-20251008-15.8.el10_0.noarch.rpm"
"libertas-firmware-20251008-15.8.el10_0.noarch.rpm"
"netronome-firmware-20251008-15.8.el10_0.noarch.rpm"
"linux-firmware-whence-20251008-15.8.el10_0.noarch.rpm"

# 特定场景工具
"x3270-4.3ga8-8.el10.x86_64.rpm"
"x3270-text-4.3ga8-8.el10.x86_64.rpm"
"minicom-2.9-4.el10.x86_64.rpm"
"lrzsz-0.12.20-66.el10.x86_64.rpm"
"mtr-0.95-11.el10.x86_64.rpm"
"traceroute-2.1.6-3.el10.x86_64.rpm"
"rear-2.9-4.el10.x86_64.rpm"
"sos-4.10.0-4.el10_1.noarch.rpm"
"perftest-25.04.0.0.84-1.el10.x86_64.rpm"
"iotop-c-1.26-4.el10.x86_64.rpm"
"ipcalc-1.0.3-12.el10.x86_64.rpm"
"dos2unix-7.5.2-3.el10.x86_64.rpm"
"tree-2.1.0-8.el10.x86_64.rpm"
"unzip-6.0-69.el10.x86_64.rpm"
"zip-3.0-45.el10.x86_64.rpm"
"usbguard-1.1.3-6.el10.x86_64.rpm"
"usbutils-018-1.el10.x86_64.rpm"
"lmdb-libs-0.9.32-4.el10.x86_64.rpm"

# 图形/非必需字体
"dejavu-serif-fonts-2.37-25.el10.noarch.rpm"
"google-noto-serif-vf-fonts-20240401-5.el10.noarch.rpm"
"default-fonts-core-serif-4.1-3.el10.noarch.rpm"
"gsettings-desktop-schemas-47.1-3.el10_0.x86_64.rpm"
"graphite2-1.3.14-17.el10.x86_64.rpm"

# 小众服务/协议工具
"cockpit-344-1.el10.x86_64.rpm"
"cockpit-bridge-344-1.el10.noarch.rpm"
"cockpit-doc-344-1.el10.noarch.rpm"
"cockpit-system-344-1.el10.noarch.rpm"
"cockpit-ws-344-1.el10.x86_64.rpm"
"cockpit-ws-selinux-344-1.el10.x86_64.rpm"
"avahi-0.9~rc2-2.el10_0.x86_64.rpm"
"avahi-libs-0.9~rc2-2.el10_0.x86_64.rpm"
"autofs-5.1.9-13.el10.x86_64.rpm"
"isns-utils-0.103-1.el10.x86_64.rpm"
"isns-utils-libs-0.103-1.el10.x86_64.rpm"
"rdma-core-57.0-2.el10.x86_64.rpm"
"libibverbs-57.0-2.el10.x86_64.rpm"
"libibverbs-utils-57.0-2.el10.x86_64.rpm"

# 其他非必需工具
"samba-4.22.4-106.el10.x86_64.rpm"
"samba-client-libs-4.22.4-106.el10.x86_64.rpm"
"samba-common-4.22.4-106.el10.noarch.rpm"
"samba-common-libs-4.22.4-106.el10.x86_64.rpm"
"samba-common-tools-4.22.4-106.el10.x86_64.rpm"
"samba-dcerpc-4.22.4-106.el10.x86_64.rpm"
)

# 遍历所有可删除包，自动匹配分目录并备份删除
for pkg in "${REMOVABLE_PACKAGES[@]}"; do
    # 提取包名首字母（转小写），确定子目录
    FIRST_CHAR=$(echo $pkg | cut -c1 | tr 'A-Z' 'a-z')
    # 拼接包的完整路径
    PKG_FULL_PATH="$PKG_DIR/$FIRST_CHAR/$pkg"
    
    if [ -f "$PKG_FULL_PATH" ]; then
        # 备份到指定目录（保留原包名）
        mv "$PKG_FULL_PATH" "$BACKUP_DIR/"
        echo "✅ 已备份并删除：$PKG_FULL_PATH"
    else
        echo "⚠️  包不存在（忽略）：$PKG_FULL_PATH"
    fi
done

echo "===== 备份+删除完成 ====="
# 验证：列出备份目录中的包
ls -l $BACKUP_DIR/ | wc -l