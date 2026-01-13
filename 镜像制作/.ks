# Repacked the CentOS 7 for the installation of automation with exception of system disk selection and network configing.
# Author: Gaodan<adam.gao@baishan.com>

%include /.base.ks
%include /tmp/other.ks

%addon com_redhat_kdump --disable
%end

%packages
@^minimal
@core
rp-pppoe-3.11-7.el7.x86_64
bs-decrypt
bs-frpc
rc-init
binit
kernel-5.4.96-201bs.el7.x86_64
qrencode
chrony
-dracut-config-rescue
ppp
psmisc
sn-agent
bs-sn-ppp
%end

%pre
rm -f /tmp/other.ks
_tty=$(tty)
# rc-ask.py <$_tty &>$_tty
rc-disk.py <$_tty &>$_tty
rc-net.py <$_tty &>$_tty
%end

%post
mount -L recruit-x86 /mnt
cp -a /mnt/manxingpxe/ /opt/
umount /mnt
rc-init.sh
mxfrpc.sh
issue.sh
network-user.sh
rc-grub.sh
sn-ppp.sh
rpm -ivh /opt/manxingpxe/bind-utils/*.rpm
rpm -ivh /opt/manxingpxe/jq/*.rpm
rpm -ivh /opt/manxingpxe/bash-completion/*.rpm
rpm -ivh /opt/manxingpxe/docker-ce/*.rpm
rpm -ivh /opt/manxingpxe/epel-release/*.rpm
rpm -ivh /opt/manxingpxe/iperf3/*.rpm
rpm -ivh /opt/manxingpxe/pciutils/*.rpm
rpm -ivh /opt/manxingpxe/python36/*.rpm
rpm -ivh /opt/manxingpxe/vim-enhanced/*.rpm
systemctl start docker
systemctl enable docker
%end
