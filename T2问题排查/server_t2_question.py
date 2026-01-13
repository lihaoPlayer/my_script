#!/usr/bin/env python
# -*- coding: utf-8 -*-
import subprocess
import sys
# import requests
import json
# import time
import urllib2
# import urllib
import os 
import ssl
import time
from datetime import datetime, timedelta
# import subprocess32 as subprocess

reload(sys)
sys.setdefaultencoding('utf-8')

#pppo汇聚
#    网卡名称   |  拨号账号   | 拨号密码 |    ID    | 网卡状态 | 平台状态 | 是否内网IP |      IP       |                 IPV6                  |      拨上时间        
# -----------------------------------------------------------------------------------------------------------------------------------------------------------
#   ppp13209904 | 93716582894 |   112233 | 13209904 | DOWN     | None     | None       | None          | None                                  | 2025-12-02 03:13:35  
#   ppp13209908 | 93716436184 |   123456 | 13209908 | DOWN     | None     | None       | None          | None                                  | 2025-12-02 03:13:39  
#   ppp13209905 | 93716582902 |   112233 | 13209905 | UP       | None     | YES        | 10.48.6.181   | 2409:8a47:300:914:2d82:74e5:819f:4fa3 | 2025-12-02 03:13:38  
#   ppp13209906 | 93711317206 |   123456 | 13209906 | UP       | None     | YES        | 10.48.2.120   | 2409:8a47:300:a28:39b7:433f:77ca:1b17 | 2025-12-04 15:36:33  
#   ppp13209907 | 93715543660 |   112233 | 13209907 | UP       | None     | YES        | 10.48.146.219 | 2409:8a47:210:ac0:84cc:22b0:8c70:8380 | 2025-12-04 15:22:54  


#固定多ip   
#   网卡名称 |    ID    | 网卡状态 | 平台状态 | 是否内网IP | 是否管理IP |      IP      |    配置IP    |     网关      |    掩码     | IPV6  
# --------------------------------------------------------------------------------------------------------------------------------
#   eth0     | 13354274 | UP       | None     | YES        | NO         | 192.168.7.25 | 192.168.7.25 | 192.168.1.252 | 255.255.0.0 | None  
#   eth1     | 13354275 | UP       | None     | YES        | NO         | 192.168.7.45 | 192.168.7.45 | 192.168.1.252 | 255.255.0.0 | None  

#专线
#   网卡名称 | 网卡状态 | 是否内网IP |       IP       | IPV6  
# --------------------------------------------------------
#   enp8s0   | UP       | NO         | 39.164.152.104 | None  
# --------------------------------------------------------

# [root@e44f001bc531209e9a278f03dce0b4d5 ~]# cat /allconf/hostname.conf
# hostname=e44f001bc531209e9a278f03dce0b4d5


auth_token_manxing='Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJsb2dpblR5cGUiOiJsb2dpbiIsImxvZ2luSWQiOiJzeXNfdXNlcjoxOTE5OTYzNjY5ODIyMjU1MTA1Iiwicm5TdHIiOiJxMjg2cjI3SUVROE80V21mbGd0ZmNzcmQ0QXBLSmdiUyIsImNsaWVudGlkIjoiZTVjZDdlNDg5MWJmOTVkMWQxOTIwNmNlMjRhN2IzMmUiLCJ0ZW5hbnRJZCI6IjAwMDAwMCIsInVzZXJJZCI6MTkxOTk2MzY2OTgyMjI1NTEwNSwidXNlck5hbWUiOiJ4aWF0aWFuIiwiZGVwdElkIjoxMDIsImRlcHROYW1lIjoi6L-Q57u056CU5Y-R6YOoIn0.lzCxkG0pblRilxgDziHmP8KSyvd77uEZdZEp4cQ8ptw'
hezuokaifangh_cookie='fog-login-type=normal; username=manxingyun; oversea=1; session=eyJfcGVybWFuZW50Ijp0cnVlLCJwcm92aWRlcl9pZCI6MTM0LCJwcm92aWRlcl9uYW1lIjoi5ryr5pif5LqRIn0.aTpyAw.FKMJHkZD8dTEdh1QxiYyrRIq0Vw'
# cmd_get_account_mac="'ip -o link show | awk -F 'link/ether ' '/link\/ether/ {print $2}' | awk '{print $1}''"

def log_info(message):
    print("[INFO] " + str(message))

def log_fatal(*args):
    message = " ".join(str(arg
                           ) for arg in args)
    print("\033[31m[FATAL] " + str(message) + "\033[0m")

def log_success(message):
    print("\033[32m[SUCCESS] " + str(message) + "\033[0m")


def get_local_mac_addresses():
    mac_list = execute_local_mac_command()
    if mac_list:
        # log_info("共获取到 " + str(len(mac_list)) + " 个MAC地址")
        for i, mac in enumerate(mac_list, 1):
            log_info("MAC地址 " + str(i) + ": " + mac)
        return mac_list
    else:
        log_fatal("未能获取到有效的MAC地址")
        return []
    
# def run_shell_cmd(cmd):
#     try:
#         result = subprocess.check_output(
#             cmd,
#             stderr=subprocess.STDOUT,
#             shell=True
#         )
#         return result
#     except Exception:
#         return ""


def get_T2_deliver_platform_log(hostname):
    """{
  "code": 200,
  "data": {
    "list": [
      {
        "id": 2046,
        "created_at": "2025-12-10 10:00:12",
        "updated_at": "2025-12-10 10:00:12",
        "node_id": 444568,
        "mac": "bb585d8cc334a8cbf9f0c3cb1a2128b9",
        "deliver_type": "T2",
        "deliver_status": "交付成功",
        "business_type": "T2_udp业务",
        "deliver_log": "腾讯交付成功",
        "platform_name": "漫星云"
      }
    ],
    "total": 1,
    "page": 1,
    "pageSize": 20
  },
  "msg": "操作成功"
}"""

    url = 'https://service.chxyun.cn/admin/node/getDeliverData'
    auth_token = auth_token_manxing

    payload = {
        "page": 1,
        "pagesize": 3000,
        "macs": [hostname]
    }
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": auth_token,
    }
    
    try:
        log_info("正在查询T2交付日志: ")
        # log_info("正在查询T2交付日志: " + url)
        # log_info("请求数据: " + json.dumps(payload))
        
        data = json.dumps(payload)
        req = urllib2.Request(url, data=data, headers=headers)
        
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        

        response = urllib2.urlopen(req, timeout=30, context=context)
        response_data = response.read()
        
        # log_info("响应状态码: " + str(response.getcode()))
        # log_info("响应头: " + str(dict(response.info())))
        
        if response.getcode() == 200:
            content_type = response.info().get('content-type', '')
            if 'application/json' in content_type:
                return json.loads(response_data)
            else:
                log_info("非JSON响应，内容类型: " + content_type)
                log_info("响应内容前500字符: " + response_data[:500])
                return {"error": "非JSON响应", "content": response_data[:1000]}
        else:
            log_info("HTTP错误状态码: " + str(response.getcode()))
            log_info("响应内容: " + response_data[:500])
            
    except urllib2.HTTPError as e:
        log_fatal("HTTP错误: " + str(e) + ", 响应内容: " + e.read()[:500])
        return None
    except urllib2.URLError as e:
        log_fatal("URL错误: " + str(e))
        return None
    except Exception as e:
        log_fatal("请求失败: " + str(e))
        return None

def execute_hostname_command():
    try:
        log_info("执行本地命令获取hostname: ")
        
        fixed_command = "cut -d '=' -f 2 /allconf/hostname.conf"
    
        process = subprocess.Popen(
            fixed_command, 
            shell=True, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        )
        stdout, stderr = process.communicate()
        
        if process.returncode == 0:
            output = stdout.strip()
            if output:
                hostname = output
                return hostname
            else:
                log_info("命令执行成功但未返回MAC地址")
                return []
        else:
            log_fatal("命令执行失败: " + stderr)
            return []
            
    except Exception as e:
        log_fatal("执行本地命令时发生异常: " + str(e))
        return []

def execute_local_mac_command():
    try:
        log_info("执行本地命令获取MAC地址: ")
        
        fixed_command = "ip -o link show | awk -F 'link/ether ' '/link\\/ether/ {print $2}' | awk '{print $1}'"
    
        process = subprocess.Popen(
            fixed_command, 
            shell=True, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        )
        stdout, stderr = process.communicate()
        
        if process.returncode == 0:
            output = stdout.strip()
            if output:
                mac_list = [mac.strip() for mac in output.split('\n') if mac.strip()]
                # log_success("成功获取MAC地址列表: " + str(mac_list))
                return mac_list
            else:
                log_info("命令执行成功但未返回MAC地址")
                return []
        else:
            log_fatal("命令执行失败: " + stderr)
            return []
            
    except Exception as e:
        log_fatal("执行本地命令时发生异常: " + str(e))
        return []
    

def execute_T2_server_log_command():
    try:
        log_info("执行本地命令获取MAC地址: ")
        
        fixed_command = "tail -n 20 /var/log/pcdn-installer.log"
    
        process = subprocess.Popen(
            fixed_command, 
            shell=True, 
            stdout=subprocess.PIPE, 
            stderr=subprocess.PIPE
        )
        stdout, stderr = process.communicate()
        
        if process.returncode == 0:
            output = stdout.strip()
            if output:
                install_log = output
                # log_success("成功获取MAC地址列表: " + str(mac_list))
                return install_log
            else:
                log_info("命令执行成功但 T2_install_log 为空")
                return []
        else:
            log_fatal("命令执行失败: " + stderr)
            return []
            
    except Exception as e:
        log_fatal("执行本地命令时发生异常: " + str(e))
        return []

#TODO：暂时只配 质量异常质量流水 的mac问题获取
def hezuokaifang_query_mac(mac_address):
    """
     {
   'data': [{
     'Gend': '2025-12-08 11:48:01 +0800 CST',
     'Gnow': '2025-12-08 11:37:01 +0800 CST',
     'IncidentType': '雾计算:高重传与慢速禁用',
     'Mac': '00:07:b3:dd:ae:e9',
     'Severity': '严重',
     'Status': '00:07:b3:dd:ae:e9 重传率持续过高且传输慢速；重传率均值：107.3%，传输速度：12.154345KB/s。'
   }, {
     'Gend': '2025-12-08 10:14:01 +0800 CST',
     'Gnow': '2025-12-08 10:05:01 +0800 CST',
     'IncidentType': '雾计算:高重传与慢速禁用',
     'Mac': '00:07:b3:dd:ae:e9',
     'Severity': '严重',
     'Status': '00:07:b3:dd:ae:e9 重传率持续过高且传输慢速；重传率均值：58.39%，传输速度：14.178493KB/s。'
   }],
   'ret_code': 0,
   'ret_msg': '成功',
   'total': 11
 }
    """
    now = time.time()
    end_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(now))
    begin_time = time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(now - 24*60*60))
    if isinstance(mac_address, list):
        mac_str = ",".join(mac_address)
    else:
        mac_str = mac_address

    url = 'http://52.81.55.45:9190/fog_cal_device_mgr_ext/api/v1/pcdn_device_abnormal/get_flow_data'
    
    payload = {
        "beginTime": begin_time,
        "endTime": end_time,
        "mac": mac_str,
        "optionValue": "incidents"
    }

    headers = {
        "Accept": "application/json",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6",
        "Connection": "keep-alive",
        "Content-Type": "application/json",
        "Cookie": hezuokaifangh_cookie,
        "DNT": "1",
        "Host": "52.81.55.45:9190",
        "Origin": "http://52.81.55.45:9190",
        "Referer": "http://52.81.55.45:9190/?wework_cfm_code=MO%2FF2raCOBIey4eOtBJxVmhoagxNDc%2FRUnfHeC8x1wjg8b6TLkdzuJMke9rYYjfqESUYgQOKXLxxS7PmItVojjSNKr6z1jxg%2Fe6Fhbn1CaAfcO7NPZyG9XY%3D",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0"
    }
    
    try:
        # log_info("正在查询: ")
        log_info("正在查询: " + url)
        # log_info("请求数据: " + json.dumps(payload))
        
        data = json.dumps(payload)
        req = urllib2.Request(url, data=data, headers=headers)
        
        response = urllib2.urlopen(req, timeout=30)
        response_data = response.read()
        
        # log_info("响应状态码: " + str(response.getcode()))
        # log_info("响应头: " + str(dict(response.info())))
        
        if response.getcode() == 200:
            content_type = response.info().get('content-type', '')
            if 'application/json' in content_type:
                return json.loads(response_data)       
            else:
                log_info("非JSON响应，内容类型: " + content_type)
                log_info("响应内容前500字符: " + response_data[:500])
                return {"error": "非JSON响应", "content": response_data[:1000]}
        else:
            log_info("HTTP错误状态码: " + str(response.getcode()))
            log_info("响应内容: " + response_data[:500])
            
    except urllib2.HTTPError as e:
        log_fatal("HTTP错误: " + str(e) + ", 响应内容: " + e.read()[:500])
        return None
    except urllib2.URLError as e:
        log_fatal("URL错误: " + str(e))
        return None
    except Exception as e:
        log_fatal("请求失败: " + str(e))
        return None

def main():
    log_info("开始查询...")
    
    T2_install_log = execute_T2_server_log_command()
    if T2_install_log:
        log_success("\nT2_install_log 查询成功")
        print("\033[1;36m=== T2_install_log 交付信息 ===\033[0m")
        print(T2_install_log)
    else:
        log_fatal("T2_install_log  查询失败")

    sever_sn = execute_hostname_command()
    if sever_sn:
        log_info("正在查询: " + sever_sn)
        result = get_T2_deliver_platform_log(sever_sn)
        if result and 'data' in result and 'list' in result['data']:
            log_success("\nT2交付日志查询成功")
            deliver_list = result['data']['list']
            
            if deliver_list:
                print("\033[1;36m=== T2交付信息 ===\033[0m")
                for item in deliver_list:
                    
                    deliver_type = item.get('deliver_type', 'N/A')
                    deliver_status = item.get('deliver_status', 'N/A')
                    business_type = item.get('business_type', 'N/A')
                    deliver_log = item.get('deliver_log', 'N/A')
                    platform_name = item.get('platform_name', 'N/A')

                    print("交付类型: {}".format(deliver_type))
                    print("交付状态: {}".format(deliver_status))
                    print("业务类型: {}".format(business_type))
                    print("交付日志: {}".format(deliver_log))
                    print("平台名称: {}".format(platform_name))
                    print("-" * 30)
            else:
                log_info("未找到T2交付记录")
        else:
            log_fatal("T2交付日志查询失败或返回数据格式不正确")
    else:
        log_fatal("未能获取服务器序列号")




    mac_addresses = get_local_mac_addresses()
    filtered_macs = [mac.strip() for mac in mac_addresses if mac.strip()]
    # TODO  
    result = hezuokaifang_query_mac(mac_addresses)
    all_results = []
    for mac in filtered_macs:
        log_info("查询MAC地址: " + mac)
        # result = hezuokaifang_query_mac(mac)
        if result and 'data' in result:
            # log_success("查询MAC " + mac + " 成功")
            all_results.append({
                'mac': mac,
                'data': result['data']
            })
            
            for item in result['data']:
                severity = item.get('Severity', 'N/A')
                status = item.get('Status', 'N/A')
                incident_type = item.get('IncidentType', 'N/A')
                gend = item.get('Gend', 'N/A')
                
                print("\033[33m[{}] MAC: {} | 严重程度: {} | ���型: {}\033[0m".format(
                    gend, mac, severity, incident_type))
                print("  状态详情: {}".format(status))
        elif result:
            log_info("查询MAC " + mac + " 成功，但无异常数据")
        else:
            log_fatal("查询MAC " + mac + " 失败")
    
    if all_results:
        log_success("\n=== 异常汇总报告 ===")
        total_issues = sum(len(result['data']) for result in all_results)
        log_success("总共发现 {} 个异常项".format(total_issues))
        
        for result in all_results:
            mac = result['mac']
            print("\033[1;36mMAC地址: {}\033[0m".format(mac))
            for item in result['data']:
                severity = item.get('Severity', 'N/A')
                status = item.get('Status', 'N/A')
                incident_type = item.get('IncidentType', 'N/A')
                gend = item.get('Gend', 'N/A')
                
                if severity == '严重':
                    color_code = '\033[31m'  # 红
                elif severity == '警告':
                    color_code = '\033[33m'  # 黄
                else:
                    color_code = '\033[37m'  # 白
                
                print("{}严重程度: {} | 类型: {} | 时间: {}\033[0m".format(
                    color_code, severity, incident_type, gend))
                print("  状态详情: {}".format(status))
    else:
        log_success("未发现任何异常")

if __name__ == "__main__":
    main()