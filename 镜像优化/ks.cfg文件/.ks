# 为 CentOS 7 重新打包，用于自动化安装（除了系统磁盘选择和网络配置）
# 作者：Gaodan<adam.gao@baishan.com>

%include /.base.ks  # 包含基础配置文件
%include /tmp/other.ks  # 包含其他配置文件

%addon com_redhat_kdump --disable  # 禁用 kdump（内核崩溃转储功能）
%end

%packages  # 开始定义软件包列表
@^minimal  # 最小化包组
@core  # 核心包组
rp-pppoe-3.11-7.el7.x86_64  # PPPoE 协议支持
bs-decrypt  # 白山解密工具
bs-frpc  # 白山内网穿透工具
rc-init  # 初始化脚本
binit  # 二进制初始化工具
kernel-5.4.96-201bs.el7.x86_64  # 自定义内核版本
qrencode  # 二维码生成工具
chrony  # NTP 时间同步服务
-dracut-config-rescue  # 排除 dracut 救援配置（加号表示移除）
ppp  # PPP 拨号协议
psmisc  # 进程工具集
sn-agent  # 序列号代理
bs-sn-ppp  # 白山 PPP 管理工具
%end  # 结束软件包定义

%pre  # 安装前执行的脚本
rm -f /tmp/other.ks  # 删除临时配置文件
_tty=$(tty)  # 获取终端设备
# rc-ask.py <$_tty &>$_tty  # 注释掉交互式脚本
rc-disk.py <$_tty &>$_tty  # 执行磁盘配置脚本
rc-net.py <$_tty &>$_tty  # 执行网络配置脚本
%end  # 结束前处理脚本

%post  # 安装后执行的脚本
mount -L recruit-x86 /mnt  # 挂载标签为 recruit-x86 的磁盘
cp -a /mnt/manxingpxe/ /opt/  # 复制完整的 manxingpxe 目录到 /opt/
umount /mnt  # 卸载已挂载的磁盘
rc-init.sh  # 运行初始化脚本
mxfrpc.sh  # 运行内网穿透配置脚本
issue.sh --host portal.chxyun.cn  # 配置系统发行版信息
network-user.sh  # 配置网络用户
rc-grub.sh  # 配置 GRUB 引导加载程序
sn-ppp.sh  # 配置序列号 PPP
rpm -ivh /opt/manxingpxe/bind-utils/*.rpm  # 安装 bind-utils（DNS 工具）
rpm -ivh /opt/manxingpxe/jq/*.rpm  # 安装 jq（JSON 处理工具）
rpm -ivh /opt/manxingpxe/bash-completion/*.rpm  # 安装 bash 命令补全
rpm -ivh /opt/manxingpxe/docker-ce/*.rpm  # 安装 Docker CE
rpm -ivh /opt/manxingpxe/epel-release/*.rpm  # 安装 EPEL 扩展源
rpm -ivh /opt/manxingpxe/iperf3/*.rpm  # 安装 iperf3（网络性能测试工具）
rpm -ivh /opt/manxingpxe/pciutils/*.rpm  # 安装 pciutils（PCI 设备工具）
rpm -ivh /opt/manxingpxe/python36/*.rpm  # 安装 Python 3.6
rpm -ivh /opt/manxingpxe/vim-enhanced/*.rpm  # 安装增强版 Vim 编辑器
systemctl start docker  # 启动 Docker 服务
systemctl enable docker  # 设置 Docker 开机自启
%end  # 结束后处理脚本
