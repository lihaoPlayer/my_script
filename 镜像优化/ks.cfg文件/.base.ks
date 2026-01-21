skipx  # 跳过图形界面安装，使用命令行模式
install  # 执行全新安装（而不是升级）
cdrom  # 从 CD/DVD 光盘介质安装
reboot --kexec  # 安装完成后自动重启，使用 kexec 快速重启
firewall --disabled  # 禁用防火墙
selinux --disabled  # 禁用 SELinux（安全增强型 Linux）
unsupported_hardware  # 允许在不受官方支持的硬件上安装

lang en_US.UTF-8  # 设置系统语言为英文 UTF-8 编码
keyboard --vckeymap=us --xlayouts='us'  # 设置键盘布局为美式英文
timezone Asia/Shanghai  # 设置时区为上海（UTC+8）

services --disabled="NetworkManager" --enabled="network,chronyd"  # 禁用NetworkManager，启用传统网络服务和NTP时间同步
rootpw --iscrypted $1$1MIMGFF7$jo0bX6pkR4AwRbsEOXzcr1  # 设置加密后的 root 密码

authconfig --enableshadow --passalgo=sha512  # 启用密码影子文件，使用 SHA-512 加密算法
