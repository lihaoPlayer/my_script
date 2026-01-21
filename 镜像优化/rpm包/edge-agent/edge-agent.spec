Name:           edge-agent
Version:        1.0.3
Release:        1%{?dist}
Summary:        Edge Agent Service (v1.0.3)
License:        GPLv3
URL:            https://file.chxyun.cn/mx/701/edge-agent-v1.0.3.zip
Source0:        edge-agent-v1.0.3.zip
BuildArch:      x86_64
Requires:       unzip
Requires:       systemd
Requires:       curl

%description
This RPM package automatically deploys Edge Agent v1.0.3:
1. Clean old edge-agent environment before installation
2. Deploy files to /usr/local/edge-agent/
3. Create systemd service and auto-start

%pre
if [ -d "/usr/local/edge-agent" ]; then
    rm -rf "/usr/local/edge-agent"
fi

if systemctl is-active --quiet edge-agent; then
    systemctl stop edge-agent || exit 1
fi

if systemctl is-enabled --quiet edge-agent; then
    systemctl disable edge-agent || exit 1
fi

exit 0

%prep
unzip -q %{SOURCE0} -d %{_builddir}/edge-agent-tmp

%install
mkdir -p %{buildroot}/usr/local/edge-agent
cp -r %{_builddir}/edge-agent-tmp/edge-agent-%{version}/* %{buildroot}/usr/local/edge-agent/

chmod +x %{buildroot}/usr/local/edge-agent/edge-agent
chmod +x %{buildroot}/usr/local/edge-agent/modules/*.so

mkdir -p %{buildroot}/etc/systemd/system

%files
/usr/local/edge-agent/
%defattr(-, root, root, -)

%post
cat << 'EOF' > /etc/systemd/system/edge-agent.service
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

systemctl daemon-reload || { echo "Failed to reload systemd daemon"; exit 1; }
systemctl start edge-agent.service || { echo "Failed to start edge-agent"; exit 1; }
systemctl enable edge-agent.service || { echo "Failed to enable edge-agent"; exit 1; }

exit 0

%postun
if systemctl is-active --quiet edge-agent; then
    systemctl stop edge-agent || true
fi

if systemctl is-enabled --quiet edge-agent; then
    systemctl disable edge-agent || true
fi

rm -rf /usr/local/edge-agent
rm -f /etc/systemd/system/edge-agent.service

exit 0

%changelog
* Wed Jan 14 2026 Root <root@centos7> 1.0.3-1
- First release of edge-agent v1.0.3
- Integrate auto-cleanup and systemd service auto-deployment