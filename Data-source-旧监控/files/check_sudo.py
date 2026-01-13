#!/usr/bin/env python
# -*- coding: utf-8 -*-
import subprocess
import sys
import urllib2
import json
import ssl


def run_shell_cmd(cmd):
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT, shell=True)
        if isinstance(result, bytes):
            result = result.decode('utf-8')
        return result
    except subprocess.CalledProcessError:
        return "10002"
    
def get_machine_id():
    cmd = "cat /etc/machine-id"
    result = run_shell_cmd(cmd)
    if result == "10002":
        print("Error: Failed to get machine ID")
        sys.exit(1)
    return result.strip()

def is_self_mirror():
    mac = get_machine_id()
    url = "https://service.chxyun.cn/client/node/queryNodeInfoByAdmin"
    headers = {
        'Authorization': 'Bearer 7552E7071B118CBFFEC8C930455B4297',
        'Content-Type': 'application/json',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }

    try:
        # 忽略 SSL 证书验证（如果网站使用自签名证书）
        context = ssl._create_unverified_context()
        req = urllib2.Request(url, json.dumps({"mac": mac}), headers)
        response = urllib2.urlopen(req, context=context, timeout=30)
        
        # 获取响应状态码
        status_code = response.getcode()
        if status_code != 200:
            print("查询镜像类型失败，检查下网络，状态码: {}".format(status_code))
            return False
        
        response_data = response.read()
        data = json.loads(response_data)
        is_mirror = data.get("data", {}).get("is_self_mirror")
        if is_mirror is None:
            return True
        elif is_mirror == 1:
            return True
        elif is_mirror == 0:
            return False

    except Exception as e:
        print("查询镜像类型错误: {}".format(str(e)))
        return False

def system_user_sudocheck():
    believe_trust_user = ["root","op","lighthouse"]
    bad_user =[]
    with open("/etc/passwd","r") as f:
        lines = f.readlines()
        for line in lines:
            if not line or line.startswith("#"):
                continue
            user = line.split(":")[0]
            if user not in believe_trust_user:
                a = run_shell_cmd("sudo -l -U {} |grep -q 'NOPASSWD: ALL'".format(user))
                shell = line.split(":")[6].strip()
                #只输出能登录的用户
                if a == "" and shell == "/bin/bash":
                    bad_user.append(user)
    if bad_user:
        self_mirror = is_self_mirror()
        if self_mirror:
            pass
        else:
            print("存在拥有无密码sudo权限的非信任用户: {}".format(", ".join(bad_user)))
            sys.exit(1)
if __name__ == "__main__":
    system_user_sudocheck()