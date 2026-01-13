Name:           edge-agent
Version:        1.0.3
Release:        1%{?dist}
Summary:        Edge Agent Service for MXcom Custom System
License:        Proprietary
Source0:        edge-agent-v%{version}.zip
BuildArch:      x86_64
BuildRequires:  rpm-build rpmdevtools Unzip
Requires:       curl unzip systemd

# 详细描述（可选，不影响功能）
%description
Edge Agent Service for MXcom Custom CentOS7 System
- Offline deploy from local zip package
- Managed by systemd service
- Auto clean old version before install

# 安装阶段（核心部署逻辑）
%install
set -e
version="%{version}"
base_dir="/usr/local/edge-agent"

# 从SOURCES拷贝本地压缩包到临时目录
cp %{SOURCE0} /usr/local/edge-agent.zip

# 解压并清理压缩包
unzip -o /usr/local/edge-agent.zip -d /usr/local/ || { echo "Unzip failed"; exit 1; }
rm -f /usr/local/edge-agent.zip

# 移动目录+设置执行权限
mv /usr/local/edge-agent-v${version} "$base_dir" || exit 1
chmod +x "$base_dir"/edge-agent "$base_dir"/modules/*.so

# 创建systemd服务文件（必须写入%{buildroot}，RPM规范）
mkdir -p %{buildroot}/etc/systemd/system
cat << 'EOF' > %{buildroot}/etc/systemd/system/edge-agent.service
[Unit]
Description=Edge Agent Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/usr/local/edge-agent
ExecStart=/usr/local/edge-agent/edge-agent
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# 安装前：清理旧版本+停止旧服务
%pre
set -e
base_dir="/usr/local/edge-agent"
# 清理旧目录
if [ -d "$base_dir" ]; then
    rm -rf "$base_dir"
fi
# 停止/禁用旧服务
if systemctl is-active --quiet edge-agent; then
    systemctl stop edge-agent || exit 1
fi
if systemctl is-enabled --quiet edge-agent; then
    systemctl disable edge-agent || exit 1
fi
# 兜底安装unzip（防止极端情况依赖缺失）
if ! command -v unzip &>/dev/null; then
    yum install -y unzip || exit 1
fi

# 安装后：启动+启用服务
%post
set -e
systemctl daemon-reload
systemctl start edge-agent.service || { echo "Start service failed"; exit 1; }
systemctl enable edge-agent.service || { echo "Enable service failed"; exit 1; }

# 卸载前：停止+禁用服务
%preun
if systemctl is-active --quiet edge-agent; then
    systemctl stop edge-agent.service || exit 1
fi
if systemctl is-enabled --quiet edge-agent; then
    systemctl disable edge-agent.service || exit 1
fi

# 卸载后：清理残留文件
%postun
rm -rf /usr/local/edge-agent
rm -f /etc/systemd/system/edge-agent.service
systemctl daemon-reload

# RPM包文件清单（必须声明，否则安装后无文件）
%files
/usr/local/edge-agent/
/etc/systemd/system/edge-agent.service

# 变更日志（规范用，无需修改）
%changelog
* Mon Jan 05 2026 MXcom Admin <admin@mxcom.com> - 1.0.3-1
- Initial offline RPM package for edge-agent
- Support CentOS7 x86_64 offline deploy
- Auto clean old version and manage systemd service