# 1. 基础信息段（必填，定义RPM包属性和依赖）
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

# 2. 详细描述段
%description
This RPM package automatically deploys node_exporter and vmagent:
1. Clean old environment before installation
2. Deploy files to /usr/local/
3. Generate vmagent.yml configuration automatically
4. Start and enable systemd services

# 3. 安装前脚本（%pre）：清理旧环境（对应你的stop_service、kill_process、delete_history_directory）
%pre
# 停止旧服务
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

# 杀死node-pusher进程
pid=$(ps -ef | grep node-pusher | grep -v grep | awk '{print $2}')
if [ -n "$pid" ]; then
    kill $pid >/dev/null 2>&1 || true
fi

# 删除历史目录
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

# 4. 预处理段（%prep）：解压zip包到BUILD目录
%prep
# 解压zip包到RPM构建临时目录（%{_builddir} = /root/rpmbuild/BUILD）
unzip -q %{SOURCE0} -d %{_builddir}/mx-monitor

# 5. 安装段（%install）：模拟安装到BUILDROOT（核心，对应脚本的文件部署）
%install
# 1. 创建模拟根目录下的必要目录（%{buildroot} = /root/rpmbuild/BUILDROOT/...）
mkdir -p %{buildroot}/usr/local/node_exporter
mkdir -p %{buildroot}/usr/local/vmagent
mkdir -p %{buildroot}/etc/systemd/system
mkdir -p %{buildroot}/var/log/mx-cIndicator/

# 2. 复制node_exporter相关文件（从BUILD目录到模拟根目录）
cp -r %{_builddir}/mx-monitor/node_exporter/* %{buildroot}/usr/local/node_exporter/

# 3. 移动vmagent目录（对应脚本的mv_directory函数）
if [ -d "%{_builddir}/mx-monitor/node_exporter/vmagent" ]; then
    cp -r %{_builddir}/mx-monitor/node_exporter/vmagent/* %{buildroot}/usr/local/vmagent/
fi

# 4. 赋予可执行权限（对应脚本的chmod +x）
chmod +x %{buildroot}/usr/local/node_exporter/node_exporter
chmod +x %{buildroot}/usr/local/vmagent/vmagent

# 5. 移动systemd服务文件（对应脚本的mv service文件）
if [ -f "%{buildroot}/usr/local/node_exporter/node_exporter.service" ]; then
    mv %{buildroot}/usr/local/node_exporter/node_exporter.service %{buildroot}/etc/systemd/system/
fi
if [ -f "%{buildroot}/usr/local/vmagent/vmagent.service" ]; then
    mv %{buildroot}/usr/local/vmagent/vmagent.service %{buildroot}/etc/systemd/system/
fi

# 6. 文件段（%files）：指定要打包的所有文件（必须与%install中的路径对应）
%files
# 节点监控工具文件
/usr/local/node_exporter/
/usr/local/vmagent/
# systemd服务配置文件
/etc/systemd/system/node_exporter.service
/etc/systemd/system/vmagent.service
# 日志目录（%attr指定权限，root:root 755）
%attr(755, root, root) /var/log/mx-cIndicator/

# 定义默认权限（所有文件归root:root，可执行文件保持755）
%defattr(-, root, root, -)

# 7. 安装后脚本（%post）：生成配置文件 + 启动服务（对应脚本的get_mac、start_service）
%post
# 生成vmagent.yml配置文件（对应get_mac函数，获取目标系统的真实hostname/machine-id）
hostname=\$(cat /etc/hostname)
if [[ ! "\$hostname" =~ ^[a-f0-9]{32}$ ]]; then
    hostname=\$(cat /etc/machine-id)
fi

cat > /usr/local/vmagent/vmagent.yml <<EOF
global:
  scrape_interval: 60s

scrape_configs:
  - job_name: "node_export"
    static_configs:
      - targets: ["localhost:5046"]
        labels:
          instance: "\$hostname"
EOF

# 启动并启用服务（对应start_service函数）
systemctl daemon-reload || { echo "Failed to reload systemd daemon"; exit 1; }
systemctl start node_exporter || { echo "Failed to start node_exporter"; exit 1; }
systemctl start vmagent || { echo "Failed to start vmagent"; exit 1; }
systemctl enable node_exporter || { echo "Failed to enable node_exporter"; exit 1; }
systemctl enable vmagent || { echo "Failed to enable vmagent"; exit 1; }

# 验证服务状态
systemctl is-active --quiet node_exporter || { echo "node_exporter service is not active"; exit 1; }
systemctl is-active --quiet vmagent || { echo "vmagent service is not active"; exit 1; }

exit 0

# 8. 卸载后脚本（%postun）：可选，卸载RPM时自动清理环境
%postun
# 停止服务
if systemctl is-active --quiet node_exporter; then
    systemctl stop node_exporter || true
fi
if systemctl is-active --quiet vmagent; then
    systemctl stop vmagent || true
fi

# 禁用服务
systemctl disable node_exporter || true
systemctl disable vmagent || true

# 清理残留目录（可选，根据需求决定是否保留日志）
rm -rf /usr/local/node_exporter
rm -rf /usr/local/vmagent
# rm -rf /var/log/mx-cIndicator/

exit 0

# 9. 变更日志
%changelog
* Wed Jan 14 2026 Root <root@centos7> 1.0.0-1
- First release, integrate node_exporter and vmagent auto-deployment
- Include old environment cleanup and service auto-start