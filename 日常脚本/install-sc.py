#!/usr/bin/env python
# -*- encoding:utf-8 -*-
# 压测服务部署脚本
import subprocess
import sys
import os
import json

def run_cmd(cmd):
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True)
        if isinstance(result, bytes):
            result = result.decode('utf-8')
        return result
    except Exception as e:
        print("执行命令出错: {}".format(e))
        sys.exit(1)

def get_mac_id():
    mac_file = "/etc/machine-id"
    with open(mac_file, "r") as f:
        mac = f.read().strip()  # 读取内容并去掉换行符
    return mac

#=======部署压测环境===========
def install_base():
    mac = get_mac_id()
    sk = "de8ca01235821ee0e9bcceecf8876ca919e319dbac2f85c7589fae32b78d9e7b"
    url = "https://ss.bscstorage.com/recruit-lixiaodong/mx/701/sc"
    cmd = "curl -o /usr/local/sc/sc {} && chmod +x /usr/local/sc/sc".format(url)
    sperfs_addr = "https://sperfs.9yb.life"

    try:
        if not os.path.exists("/etc/app"):
            os.makedirs("/etc/app")
    except Exception as e:
        print("创建目录/etc/app失败:{}".format(e))
        sys.exit(1)

    try:
        with open("/etc/app/.sn","w") as f:
            f.write(mac)
    except Exception as e :
        print("写入文件/etc/app/.sn出错:{}".format(e))
        sys.exit(1)

    try:
        with open("/etc/app/.sk","w") as f:
            f.write(sk)
    except Exception as e :
        print("写入文件/etc/app/.sk出错:{}".format(e))
        sys.exit(1)

    try:
        if not os.path.exists("/usr/local/sc"):
            os.makedirs("/usr/local/sc") 
    except Exception as e:
        print("创建目录/usr/local/sc失败:{}".format(e))
        sys.exit(1)
    try:
        with open("/usr/local/sc/sperfs_addr","w") as f:
            f.write(sperfs_addr)
    except Exception as e:
        print("写入文件/usr/local/sc/sperfs_addr出错:{}".format(e))
        sys.exit(1)

    try:
        if not os.path.exists("/usr/local/sc/sc"):
            run_cmd(cmd)
    except Exception as e:
        print("执行命令出错: {}".format(e))
        sys.exit(1)
    


#=======启动信息上报，用作对端========
    service_info = """
[Unit]
Description=sc server 
After=network.target  

[Service]
WorkingDirectory=/usr/local/sc
ExecStart=/usr/local/sc/sc -s -log=true
Restart=on-failure
RestartSec=5 

[Install]
WantedBy=multi-user.target
"""
    try:
        with open("/etc/systemd/system/sc.service","w") as f:
            f.write(service_info)
    except Exception as e :
        print("写入文件/etc/systemd/system/sc.service出错:{}".format(e))
        sys.exit(1)

    run_cmd("systemctl daemon-reload")
    run_cmd("systemctl enable sc.service")
    run_cmd("systemctl restart sc.service")  
    status = run_cmd("systemctl is-active sc.service")
    if status.strip() == "active":
        return 0
    else:
        return 1

if __name__ == "__main__":
    result = install_base()
    if result == 0:
        result = {"status": "success", "message": "sc服务安装并启动成功"}
    else:
        result = {"status": "failure", "message": "sc服务启动失败"}

    print(json.dumps(result))




