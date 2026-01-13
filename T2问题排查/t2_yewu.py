#!/usr/bin/env python
# -*- coding: utf-8 -*-
import subprocess
import sys
import json
import urllib2
import os
import ssl
import time
from datetime import datetime, timedelta

reload(sys)
sys.setdefaultencoding('utf-8')


auth_token_manxing='Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJsb2dpblR5cGUiOiJsb2dpbiIsImxvZ2luSWQiOiJzeXNfdXNlcjoxOTE5OTYzNjY5ODIyMjU1MTA1Iiwicm5TdHIiOiJxMjg2cjI3SUVROE80V21mbGd0ZmNzcmQ0QXBLSmdiUyIsImNsaWVudGlkIjoiZTVjZDdlNDg5MWJmOTVkMWQxOTIwNmNlMjRhN2IzMmUiLCJ0ZW5hbnRJZCI6IjAwMDAwMCIsInVzZXJJZCI6MTkxOTk2MzY2OTgyMjI1NTEwNSwidXNlck5hbWUiOiJ4aWF0aWFuIiwiZGVwdElkIjoxMDIsImRlcHROYW1lIjoi6L-Q57u056CU5Y-R6YOoIn0.lzCxkG0pblRilxgDziHmP8KSyvd77uEZdZEp4cQ8ptw'
hezuokaifangh_cookie='fog-login-type=normal; username=manxingyun; oversea=1; session=eyJfcGVybWFuZW50Ijp0cnVlLCJwcm92aWRlcl9pZCI6MTM0LCJwcm92aWRlcl9uYW1lIjoi5ryr5pif5LqRIn0.aT5t0A.HAefZnna3UmOQhV-CVMXgxcGrX4'

def log_info(message):
    print("[INFO] " + str(message))

def log_fatal(*args):
    message = " ".join(str(arg) for arg in args)
    print("\033[31m[FATAL] " + str(message) + "\033[0m")

def log_success(message):
    print("\033[32m[SUCCESS] " + str(message) + "\033[0m")

def get_local_mac_addresses():
    """获取MAC地址（仅返回列表，不打印多余日志）"""
    mac_list = execute_local_mac_command()
    if mac_list:
        return mac_list
    else:
        log_fatal("未能获取到有效的MAC地址")
        return []

def get_T2_deliver_platform_log(hostname):
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
        data = json.dumps(payload)
        req = urllib2.Request(url, data=data, headers=headers)
        
        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

        response = urllib2.urlopen(req, timeout=30, context=context)
        response_data = response.read()
        
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
                log_info("命令执行成功但未返回hostname")
                return ""
        else:
            log_fatal("命令执行失败: " + stderr)
            return ""
            
    except Exception as e:
        log_fatal("执行本地命令时发生异常: " + str(e))
        return ""

def execute_local_mac_command():
    try:
        fixed_command = "cat /etc/pcdn/pcdn.conf | grep 'macs' | awk '{print $2}'"
    
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
                mac_list = [mac.strip() for mac in output.split(',') if mac.strip()]
                return mac_list
            else:
                log_info("命令执行成功但未获取到MAC地址")
                return []
        else:
            log_fatal("命令执行失败: " + stderr)
            return []
            
    except Exception as e:
        log_fatal("执行本地命令时发生异常: " + str(e))
        return []

def execute_T2_server_log_command():
    """获取T2安装日志（返回完整日志，后续处理）"""
    try:
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
            return output
        else:
            log_fatal("命令执行失败: " + stderr)
            return ""
            
    except Exception as e:
        log_fatal("执行本地命令时发生异常: " + str(e))
        return ""

def hezuokaifang_query_mac(mac_address):
    """查询MAC异常数据（无打印输出，仅返回结果）"""
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
        data = json.dumps(payload)
        req = urllib2.Request(url, data=data, headers=headers)
        response = urllib2.urlopen(req, timeout=30)
        response_data = response.read()
        
        if response.getcode() == 200:
            content_type = response.info().get('content-type', '')
            if 'application/json' in content_type:
                return json.loads(response_data)       
            else:
                return {"error": "非JSON响应", "content": response_data[:1000]}
        else:
            log_info("HTTP错误状态码: " + str(response.getcode()))
            return None
            
    except urllib2.HTTPError as e:
        log_fatal("MAC[{}] HTTP错误: ".format(mac_address) + str(e) + ", 响应内容: " + e.read()[:500])
        return None
    except urllib2.URLError as e:
        log_fatal("MAC[{}] URL错误: ".format(mac_address) + str(e))
        return None
    except Exception as e:
        log_fatal("MAC[{}] 请求失败: ".format(mac_address) + str(e))
        return None

def main():
    log_info("开始查询...\n")
    
    # ==================================
    # 1. 读取并显示MAC地址（按要求格式输出）
    # ==================================
    log_info("=== 服务器MAC地址列表 ===")
    mac_addresses = get_local_mac_addresses()
    filtered_macs = [mac.strip() for mac in mac_addresses if mac.strip()]
    if filtered_macs:
        for mac in filtered_macs:
            print(mac)  # 直接分行显示，无序号、无多余日志
        print('')  # 空行分隔
    else:
        log_fatal("未获取到有效MAC地址")
        print('')  # 空行分隔

    # ==================================
    # 2. 查询T2平台交付记录（添加“交付时间”：updated_at）
    # ==================================
    log_info("=== T2平台交付记录 ===")
    sever_sn = execute_hostname_command()
    if sever_sn:
        result = get_T2_deliver_platform_log(sever_sn)
        if result and 'data' in result and 'list' in result['data']:
            deliver_list = result['data']['list']
            if deliver_list:
                for item in deliver_list:
                    deliver_type = item.get('deliver_type', 'N/A')
                    deliver_status = item.get('deliver_status', 'N/A')
                    business_type = item.get('business_type', 'N/A')
                    deliver_log = item.get('deliver_log', 'N/A')
                    platform_name = item.get('platform_name', 'N/A')
                    # 新增：提取updated_at作为交付时间（默认N/A避免字段缺失）
                    deliver_time = item.get('updated_at', 'N/A')

                    print("交付类型: {}".format(deliver_type))
                    print("交付状态: {}".format(deliver_status))
                    print("业务类型: {}".format(business_type))
                    print("交付时间: {}".format(deliver_time))  # 新增：打印交付时间
                    print("交付日志: {}".format(deliver_log))
                    print("平台名称: {}".format(platform_name))
                    print("-" * 30)
            else:
                log_info("未找到T2交付记录")
        else:
            log_fatal("T2交付日志查询失败或返回数据格式不正确")
    else:
        log_fatal("未能获取服务器hostname")
    print('')  # 空行分隔

    # ==================================
    # 3. 查询T2安装日志（只显示最后2行，按status提示结果）
    # ==================================
    log_info("=== T2安装日志摘要 ===")
    T2_install_log = execute_T2_server_log_command()
    if T2_install_log:
        # 按行分割日志，取最后2行
        log_lines = T2_install_log.split('\n')
        last_two_lines = log_lines[-2:] if len(log_lines) >=2 else log_lines
        # 打印最后2行
        for line in last_two_lines:
            if line.strip():  # 过滤空行
                print(line)
        # 判断status状态
        status_found = False
        for line in reversed(log_lines):  # 倒序查找status行
            if 'status:' in line:
                status_str = line.split('status:')[-1].strip()
                if status_str == '0':
                    log_success("部署T2业务成功")
                else:
                    log_fatal("部署T2业务失败（status: {}）".format(status_str))
                status_found = True
                break
        if not status_found:
            log_info("未找到status状态标识，安装日志查询完成")
    else:
        log_fatal("T2安装日志查询失败或日志为空")
    print('')  # 空行分隔

    # ==================================
    # 4. MAC地址异常数据汇总（添加Gend结束时间，格式：Gnow~Gend）
    # ==================================
    log_info("=== MAC地址异常数据汇总（最近24小时） ===")
    all_results = []
    
    if not filtered_macs:
        log_fatal("无有效MAC地址，跳过异常查询")
        return
    
    # 批量查询所有MAC的异常数据（无打印）
    for mac in filtered_macs:
        result = hezuokaifang_query_mac(mac)
        if result and 'data' in result and len(result['data']) > 0:
            # 解析时间并取最新一条
            def parse_gnow(item):
                gnow = item.get('Gnow', '')
                try:
                    if 'CST' in gnow:
                        return datetime.strptime(gnow, '%Y-%m-%d %H:%M:%S %z CST')
                    else:
                        return datetime.strptime(gnow, '%Y-%m-%d %H:%M:%S')
                except:
                    return datetime.min
            
            sorted_items = sorted(result['data'], key=parse_gnow, reverse=True)
            latest_item = sorted_items[0]
            all_results.append({
                'mac': mac,
                'latest_data': latest_item
            })
    
    # 显示汇总结果
    if all_results:
        log_fatal("共 {} 个MAC存在异常数据".format(len(all_results)))
        print("-" * 80)
        for item in all_results:
            mac = item['mac']
            data = item['latest_data']
            severity = data.get('Severity', 'N/A')
            incident_type = data.get('IncidentType', 'N/A')
            gnow = data.get('Gnow', 'N/A')  # 开始时间
            gend = data.get('Gend', 'N/A')  # 结束时间（原样输出）
            status = data.get('Status', 'N/A')
            
            # 按严重程度着色
            if severity == '严重':
                color = '\033[31m'
            elif severity == '中度':
                color = '\033[33m'
            else:
                color = '\033[32m'
            
            print("\033[1;36mMAC地址: {}\033[0m".format(mac))
            print("{}严重程度: {} | 异常类型: {} | 时间范围: {}~{}\033[0m".format(
                color, severity, incident_type, gnow, gend))
            print("详情: {}".format(status))
            print("-" * 80)
    else:
        log_success("所有MAC地址均无异常数据")

if __name__ == "__main__":
    main()