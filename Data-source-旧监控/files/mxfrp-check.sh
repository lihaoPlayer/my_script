#!/bin/bash

# ==================== 1. 业务脚本（核心：每次写入前清空文件） ====================
script_path="/usr/local/Data-source/mxfrp-check.py"
mkdir -p /usr/local/Data-source

cat << 'EOF' > "$script_path"
#!/usr/bin/env python
# -*- coding: utf-8 -*-

import subprocess
import json
import urllib
import urllib2
import ssl
import datetime

log_path = "/var/log/mxfrp_check.log"

#日志函数
def log(msg):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    line = "[%s] %s\n" % (now, msg)
    with open(log_path, "a") as f:
        f.write(line)


def get_machine_id():
    try:
        result = subprocess.check_output("cat /etc/machine-id", shell=True)
        if isinstance(result, bytes):
            result = result.decode('utf-8')
        return result.strip()
    except Exception as e:
        log("获取 machine-id 失败: %s" % str(e))
        return "error"

def get_frp_status():
    instance = get_machine_id()
    if not instance and instance == "error":
        return "error"
    
    query = 'frp_status{instance="%s"}' % instance
    url = "https://monitor.9yb.life/api/v1/query"
    params = {'query': query}
    
    query_string = urllib.urlencode(params)
    
    #完整查询url
    full_url = "%s?%s" % (url, query_string)
    
    try:
        # 处理SSL
        if hasattr(ssl, '_create_unverified_context'):
            ssl_context = ssl._create_unverified_context()
            response = urllib2.urlopen(full_url, context=ssl_context)
        else:
            response = urllib2.urlopen(full_url)
        
        resp_data = response.read()
        if isinstance(resp_data, bytes):
            resp_data = resp_data.decode('utf-8')
        
        data = json.loads(resp_data)

        
        result = data.get("data", {}).get("result", [])
        if result:
            value = result[0].get("value", [None, None])[1]
            return "online" if value == "1" else "offline"
        return "offline"
    except Exception as e:
        return "error"
    
def download_run_script(status):
    url = "https://ss.bscstorage.com/recruit-lixiaodong/mx/701/mxfrp_check.py"
    script_path = "/tmp/mxfrp_check.py"  
    try:
        response = urllib2.urlopen(url)
        with open(script_path, "wb") as f:
            f.write(response.read())
        log("下载脚本成功: %s" % script_path)
    except Exception as e:
        log("下载脚本失败: %s" % str(e))

    try:
        subprocess.check_call(["python", script_path, status])
        log("执行脚本成功: %s" % script_path)
    except Exception as e:
        log("执行脚本失败: %s" % str(e))


def main():
    log("开始检测frp状态")
    status = get_frp_status()
    if status == "error":
        log("获取 frp 状态失败,等待下次检测")
    elif status == "offline":
        log("frp 状态异常,尝试修复")
        download_run_script(status)
    elif status == "online":
        log("frp 状态正常,检查公钥配置")
        download_run_script(status)
    log("frp检测完成")

if __name__ == "__main__":
    main()
EOF



# 赋予脚本执行权限
chmod +x "$script_path"

# ==================== 2. 服务单元文件 ====================
cat << 'EOF' > /etc/systemd/system/mxfrp-check.service
[Unit]
Description=Run mxfrp-check script

[Service]
Type=oneshot
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/python /usr/local/Data-source/mxfrp-check.py
WorkingDirectory=/usr/local/Data-source
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
EOF

# ==================== 3. 定时器文件 ====================
cat << 'EOF' > /etc/systemd/system/mxfrp-check.timer
[Unit]
Description=Run MX FRP Check every 10 minutes
Requires=mxfrp-check.service

[Timer]
OnBootSec=5min
OnCalendar=*:0/10
Unit=mxfrp-check.service

[Install]
WantedBy=timers.target
EOF


# ==================== 4. 生效配置并验证 ====================
systemctl daemon-reload
systemctl enable  mxfrp-check.timer
systemctl restart mxfrp-check.timer
systemctl enable  mxfrp-check.service
systemctl restart mxfrp-check.service
