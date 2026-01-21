Name:           mx-monitor
Version:        1.0.0
Release:        1%{?dist}
Summary:        MX Monitor Tools (node_exporter + vmagent)
License:        GPLv3
URL:            https://ss.bscstorage.com/recruit-lixiaodong/mx/701/node_exporter.zip
Source0:        node_exporter.zip
BuildArch:      x86_64
Requires:       unzip
Requires:       systemd

%description
This RPM package automatically deploys node_exporter and vmagent:
1. Clean old environment before installation
2. Deploy files to /usr/local/
3. Generate vmagent.yml configuration automatically
4. Start and enable systemd services

%pre
if systemctl is-active --quiet node-pusher; then
    systemctl stop node-pusher || exit 1
    systemctl disable node-pusher || exit 1
fi
if systemctl is-active --quiet node_exporter; then
    systemctl stop node_exporter || exit 1
    systemctl disable node_exporter || exit 1
fi
if systemctl is-active --quiet vmagent; then
    systemctl stop vmagent || exit 1
    systemctl disable vmagent || exit 1
fi

pid=$(ps -ef | grep node-pusher | grep -v grep | awk '{print $2}')
if [ -n "$pid" ]; then
    kill $pid >/dev/null 2>&1 || true
fi

if [ -d "/usr/local/test" ]; then
    rm -rf "/usr/local/test"
fi
if [ -d "/usr/local/node-pusher" ]; then
    rm -rf "/usr/local/node-pusher"
fi
if [ -d "/usr/local/vmagent" ]; then
    rm -rf "/usr/local/vmagent"
fi
if [ -d "/usr/local/node_exporter" ]; then
    rm -rf "/usr/local/node_exporter"
fi

exit 0

%prep
unzip -q %{SOURCE0} -d %{_builddir}/mx-monitor

%install
mkdir -p %{buildroot}/usr/local/node_exporter
mkdir -p %{buildroot}/usr/local/vmagent
mkdir -p %{buildroot}/etc/systemd/system
mkdir -p %{buildroot}/var/log/mx-cIndicator/

cp -r %{_builddir}/mx-monitor/node_exporter/* %{buildroot}/usr/local/node_exporter/

if [ -d "%{_builddir}/mx-monitor/node_exporter/vmagent" ]; then
    cp -r %{_builddir}/mx-monitor/node_exporter/vmagent/* %{buildroot}/usr/local/vmagent/
fi

chmod +x %{buildroot}/usr/local/node_exporter/node_exporter
chmod +x %{buildroot}/usr/local/vmagent/vmagent

if [ -f "%{buildroot}/usr/local/node_exporter/node_exporter.service" ]; then
    mv %{buildroot}/usr/local/node_exporter/node_exporter.service %{buildroot}/etc/systemd/system/
fi
if [ -f "%{buildroot}/usr/local/vmagent/vmagent.service" ]; then
    mv %{buildroot}/usr/local/vmagent/vmagent.service %{buildroot}/etc/systemd/system/
fi

%files
/usr/local/node_exporter/
/usr/local/vmagent/
/etc/systemd/system/node_exporter.service
/etc/systemd/system/vmagent.service
%attr(755, root, root) /var/log/mx-cIndicator/

%defattr(-, root, root, -)

%post
hostname=$(cat /etc/hostname)
if [[ ! "$hostname" =~ ^[a-f0-9]{32}$ ]]; then
    hostname=$(cat /etc/machine-id)
fi

cat > /usr/local/vmagent/vmagent.yml <<EOF
global:
  scrape_interval: 60s

scrape_configs:
  - job_name: "node_export"
    static_configs:
      - targets: ["localhost:5046"]
        labels:
          instance: "$hostname"
EOF

systemctl daemon-reload || { echo "Failed to reload systemd daemon"; exit 1; }
systemctl start node_exporter || { echo "Failed to start node_exporter"; exit 1; }
systemctl start vmagent || { echo "Failed to start vmagent"; exit 1; }
systemctl enable node_exporter || { echo "Failed to enable node_exporter"; exit 1; }
systemctl enable vmagent || { echo "Failed to enable vmagent"; exit 1; }

systemctl is-active --quiet node_exporter || { echo "node_exporter service is not active"; exit 1; }
systemctl is-active --quiet vmagent || { echo "vmagent service is not active"; exit 1; }

exit 0

%postun
if systemctl is-active --quiet node_exporter; then
    systemctl stop node_exporter || true
fi
if systemctl is-active --quiet vmagent; then
    systemctl stop vmagent || true
fi

systemctl disable node_exporter || true
systemctl disable vmagent || true

rm -rf /usr/local/node_exporter
rm -rf /usr/local/vmagent

exit 0

%changelog
* Wed Jan 14 2026 Root <root@centos7> 1.0.0-1
- First release, integrate node_exporter and vmagent auto-deployment
- Include old environment cleanup and service auto-start