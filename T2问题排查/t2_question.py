#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os
import subprocess
import sys
import json
import urllib2
import time
import ssl
from datetime import datetime

reload(sys)
sys.setdefaultencoding('utf-8')

# ========== 基础环境检查配置 ==========
TARGET_KERNEL = "5.4.119-19-0006"
CONTAINER_PREFIX = "k8s_pcdn-lego-server"
LOG_ABSOLUTE_PATH = "/lego/log/lego_server.ERROR"
TARGET_ERROR = "No such file or directory"
PROMPT_MSG = "【提示】检测到 '{}' 错误，请执行t2重启不跑命令！".format(TARGET_ERROR)
MANDATORY_MOUNT1 = "/pcdn_data/pcdn_index_data"
MANDATORY_MOUNT2_PATTERN = "/pcdn_data/storage*_ssd"

# ========== 颜色输出配置 ==========
COLOR_GREEN = "\033[32m"
COLOR_RED = "\033[31m"
COLOR_YELLOW = "\033[33m"
COLOR_BLUE = "\033[34m"
COLOR_CYAN = "\033[36m"
COLOR_PURPLE = "\033[35m"
COLOR_BOLD = "\033[1m"
COLOR_RESET = "\033[0m"

# ========== 硬编码的配置 ==========
# 从本地config.json文件中复制的内容
CONFIG = {
  "AUTH_TOKEN_MANXING": "Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJsb2dpblR5cGUiOiJsb2dpbiIsImxvZ2luSWQiOiJzeXNfdXNlcjoxOTYwMjIyMzU3MzM2NDYxMzE0Iiwicm5TdHIiOiI2VUhsbmN3MFE3b0Z0Wjh3U29DNnAwWU9jQWkxQ2FoYSIsImNsaWVudGlkIjoiZTVjZDdlNDg5MWJmOTVkMWQxOTIwNmNlMjRhN2IzMmUiLCJ0ZW5hbnRJZCI6IjAwMDAwMCIsInVzZXJJZCI6MTk2MDIyMjM1NzMzNjQ2MTMxNCwidXNlck5hbWUiOiJsaWhhbyIsImRlcHRJZCI6MTAyLCJkZXB0TmFtZSI6Iui_kOe7tOeglOWPkemDqCJ9.yfom2Kd3W7bWP1zjLgTAZTinoaJ0eAZMFT_Pm2wjEJU",
  "HEZUOKAIFANG_COOKIE": "fog-login-type=normal; username=manxingyun; oversea=1; session=eyJfcGVybWFuZW50Ijp0cnVlLCJwcm92aWRlcl9pZCI6MTM0LCJwcm92aWRlcl9uYW1lIjoi5ryr5pif5LqRIn0.aUYyFQ.Rah_zu_QdNhWCmF6YbtmS4se3mc; sidebarStatus=0"
}

AUTH_TOKEN_MANXING = CONFIG.get("AUTH_TOKEN_MANXING", "")
HEZUOKAIFANG_COOKIE = CONFIG.get("HEZUOKAIFANG_COOKIE", "")

# ========== 通用函数 ==========
def execute_cmd(cmd):
    """执行系统命令，返回 (返回码, 标准输出, 标准错误)"""
    try:
        proc = subprocess.Popen(
            cmd,
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            close_fds=True
        )
        stdout, stderr = proc.communicate()
        return proc.returncode, stdout.strip(), stderr.strip()
    except Exception as e:
        return 1, "", str(e)

def log_info(message):
    """信息日志"""
    print COLOR_BLUE + "[INFO] " + str(message) + COLOR_RESET

def log_error(message):
    """错误日志"""
    print COLOR_RED + "[ERROR] " + str(message) + COLOR_RESET

def log_success(message):
    """成功日志"""
    print COLOR_GREEN + "[SUCCESS] " + str(message) + COLOR_RESET

def log_warning(message):
    """警告日志"""
    print COLOR_YELLOW + "[WARNING] " + str(message) + COLOR_RESET

def print_section_title(title):
    """打印部分标题"""
    print COLOR_CYAN + COLOR_BOLD + "\n" + "="*60 + COLOR_RESET
    print COLOR_CYAN + COLOR_BOLD + title + COLOR_RESET
    print COLOR_CYAN + COLOR_BOLD + "="*60 + COLOR_RESET

def print_check_item(title, number):
    """打印检查项标题"""
    print COLOR_PURPLE + COLOR_BOLD + "\n{}. {}".format(number, title) + COLOR_RESET
    print "-" * 40

# ========== T2基础环境检查函数 ==========
def check_kernel_version():
    """检查内核版本"""
    print_check_item("内核版本检查", 1)
    ret_code, current_kernel, _ = execute_cmd("uname -r")
    if ret_code != 0:
        log_error("无法获取内核版本！")
        return False
    
    print "当前内核版本：{}".format(current_kernel)
    if current_kernel == TARGET_KERNEL:
        log_success("内核版本符合要求！")
        return True
    else:
        log_error("内核版本不匹配！请升级内核到 {} 版本！".format(TARGET_KERNEL))
        return False

def check_mount_points():
    """检查必要挂载点"""
    print_check_item("挂载点检查", 2)
    
    # 检查固定挂载点
    if not os.path.isdir(MANDATORY_MOUNT1):
        log_error("挂载方式不正确！未找到挂载点 {}，请重新挂载！".format(MANDATORY_MOUNT1))
        return False
    
    ret_code, _, _ = execute_cmd("mountpoint -q {}".format(MANDATORY_MOUNT1))
    if ret_code != 0:
        log_error("挂载方式不正确！{} 未挂载，请重新挂载！".format(MANDATORY_MOUNT1))
        return False

    # 检查通配符挂载点
    find_cmd = "find /pcdn_data -maxdepth 1 -type d -path '{}'".format(MANDATORY_MOUNT2_PATTERN)
    ret_code, matched_dirs, _ = execute_cmd(find_cmd)
    
    matched_mounts = []
    if matched_dirs:
        for dir_path in matched_dirs.split("\n"):
            dir_path = dir_path.strip()
            if not dir_path:
                continue
            ret, _, _ = execute_cmd("mountpoint -q {}".format(dir_path))
            if ret == 0:
                matched_mounts.append(dir_path)
    
    if not matched_mounts:
        log_error("挂载方式不正确！未找到符合 {} 的有效挂载点，请重新挂载！".format(MANDATORY_MOUNT2_PATTERN))
        return False

    # 输出有效挂载点
    print "已找到有效挂载点："
    print "  - {}".format(MANDATORY_MOUNT1)
    for mount in matched_mounts:
        print "  - {}".format(mount)
    log_success("所有必要挂载点均存在且挂载有效！")
    return True

def get_hostname():
    """获取hostname"""
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
                return output
            else:
                log_warning("命令执行成功但未返回hostname")
                return ""
        else:
            log_error("获取hostname命令执行失败: " + stderr)
            return ""
            
    except Exception as e:
        log_error("执行本地命令时发生异常: " + str(e))
        return ""

def get_T2_deliver_platform_log(hostname):
    """查询T2平台交付记录"""
    if not AUTH_TOKEN_MANXING:
        log_error("AUTH_TOKEN_MANXING未配置，无法查询T2平台交付记录")
        return None
    
    url = 'https://service.chxyun.cn/admin/node/getDeliverData'
    
    payload = {
        "page": 1,
        "pagesize": 3000,
        "macs": [hostname]
    }
    
    headers = {
        "Content-Type": "application/json",
        "Authorization": AUTH_TOKEN_MANXING,
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
                log_warning("非JSON响应，内容类型: " + content_type)
                return {"error": "非JSON响应"}
        else:
            log_error("HTTP错误状态码: " + str(response.getcode()))
            return None
            
    except urllib2.HTTPError as e:
        log_error("HTTP错误: " + str(e))
        return None
    except urllib2.URLError as e:
        log_error("URL错误: " + str(e))
        return None
    except Exception as e:
        log_error("请求失败: " + str(e))
        return None

def check_T2_deliver_record():
    """检查T2平台交付记录"""
    print_check_item("T2平台交付记录检查", 3)
    
    if not AUTH_TOKEN_MANXING:
        log_error("AUTH_TOKEN_MANXING未配置，跳过T2平台交付记录检查")
        log_warning("请在config.json中配置AUTH_TOKEN_MANXING")
        return False
    
    sever_sn = get_hostname()
    if not sever_sn:
        log_error("未能获取服务器hostname")
        return False
    
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
                deliver_time = item.get('updated_at', 'N/A')

                print("交付类型: {}".format(deliver_type))
                print("交付状态: {}".format(deliver_status))
                print("业务类型: {}".format(business_type))
                print("交付时间: {}".format(deliver_time))
                print("交付日志: {}".format(deliver_log))
                print("平台名称: {}".format(platform_name))
                
                # 判断交付状态
                if deliver_status == "交付成功":
                    log_success("T2平台交付记录检查通过")
                    return True
                else:
                    log_error("T2平台交付状态异常: {}".format(deliver_status))
                    return False
        else:
            log_error("未找到T2交付记录")
            return False
    else:
        log_error("T2交付日志查询失败或返回数据格式不正确")
        return False

def get_T2_install_log():
    """获取T2安装日志"""
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
            log_error("命令执行失败: " + stderr)
            return ""
            
    except Exception as e:
        log_error("执行本地命令时发生异常: " + str(e))
        return ""

def check_T2_install_log():
    """检查T2安装日志"""
    print_check_item("T2安装日志检查", 4)
    T2_install_log = get_T2_install_log()
    if T2_install_log:
        log_lines = T2_install_log.split('\n')
        last_two_lines = log_lines[-2:] if len(log_lines) >=2 else log_lines
        print "最近日志："
        for line in last_two_lines:
            if line.strip():
                print "  " + line
        
        status_found = False
        for line in reversed(log_lines):
            if 'status:' in line:
                status_str = line.split('status:')[-1].strip()
                if status_str == '0':
                    log_success("T2安装状态正常（status: 0）")
                    return True
                else:
                    log_error("T2安装状态异常（status: {}）".format(status_str))
                    return False
                status_found = True
                break
        if not status_found:
            log_warning("未找到status状态标识")
            return True  # 未找到status但日志存在，视为正常
    else:
        log_error("T2安装日志查询失败或日志为空")
        return False

def check_container_log():
    """检查容器和日志错误"""
    print_check_item("T2容器及日志检查", 5)

    # 提取容器ID
    docker_cmd = "docker ps | grep '{}' | head -n 1 | awk '{{print $1}}'".format(CONTAINER_PREFIX)
    ret_code, container_id, docker_err = execute_cmd(docker_cmd)
    
    if ret_code != 0 or not container_id:
        log_error("未找到名称以 '{}' 开头的运行中容器！".format(CONTAINER_PREFIX))
        if docker_err:
            log_info("Docker命令执行错误：{}".format(docker_err))
        return False
    
    print "找到目标容器，容器ID：{}".format(container_id)
    log_info("正在检测日志中的目标错误...")

    # 检测日志错误
    log_cmd = "docker exec -i {} tail -n 50 {}".format(container_id, LOG_ABSOLUTE_PATH)
    ret_code, log_content, log_err = execute_cmd(log_cmd)
    if ret_code != 0:
        log_error("读取容器日志失败！容器ID：{}，错误信息：{}".format(container_id, log_err))
        return False

    if TARGET_ERROR in log_content:
        print "\n" + COLOR_RED + COLOR_BOLD + PROMPT_MSG + COLOR_RESET
        return False
    else:
        log_success("容器日志正常，未检测到 '{}' 错误！".format(TARGET_ERROR))
        return True

# ========== T2业务质量检查函数 ==========
def get_local_mac_addresses():
    """获取MAC地址"""
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
                log_warning("命令执行成功但未获取到MAC地址")
                return []
        else:
            log_error("获取MAC地址命令执行失败: " + stderr)
            return []
            
    except Exception as e:
        log_error("执行本地命令时发生异常: " + str(e))
        return []

def query_mac_abnormal_data(mac_address):
    """查询MAC异常数据"""
    if not HEZUOKAIFANG_COOKIE:
        log_error("HEZUOKAIFANG_COOKIE未配置，无法查询MAC异常数据")
        return None
    
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
        "Cookie": HEZUOKAIFANG_COOKIE,
        "DNT": "1",
        "Host": "52.81.55.45:9190",
        "Origin": "http://52.81.55.45:9190",
        "Referer": "http://52.81.55.45:9190/",
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0"
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
                return {"error": "非JSON响应"}
        else:
            log_error("HTTP错误状态码: " + str(response.getcode()))
            return None
            
    except urllib2.HTTPError as e:
        log_error("MAC[{}] HTTP错误: ".format(mac_address) + str(e))
        return None
    except urllib2.URLError as e:
        log_error("MAC[{}] URL错误: ".format(mac_address) + str(e))
        return None
    except Exception as e:
        log_error("MAC[{}] 请求失败: ".format(mac_address) + str(e))
        return None

def check_server_mac_addresses():
    """检查服务器MAC地址列表"""
    print_check_item("服务器MAC地址列表", 1)
    mac_addresses = get_local_mac_addresses()
    filtered_macs = [mac.strip() for mac in mac_addresses if mac.strip()]
    
    if filtered_macs:
        # 直接输出MAC地址，每行一个，方便复制
        for mac in filtered_macs:
            print mac
        print ""  # 空行分隔
        return filtered_macs
    else:
        log_error("未获取到有效MAC地址")
        return []

def check_mac_abnormal_data(filtered_macs):
    """检查MAC地址异常数据"""
    print_check_item("MAC地址异常数据汇总（最近24小时）", 2)
    
    if not filtered_macs:
        log_warning("无有效MAC地址，跳过异常查询")
        return
    
    if not HEZUOKAIFANG_COOKIE:
        log_error("HEZUOKAIFANG_COOKIE未配置，跳过MAC异常数据检查")
        log_warning("请在config.json中配置HEZUOKAIFANG_COOKIE")
        return
    
    all_results = []
    for mac in filtered_macs:
        result = query_mac_abnormal_data(mac)
        if result and 'data' in result and len(result['data']) > 0:
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
    
    if all_results:
        log_error("共 {} 个MAC存在异常数据".format(len(all_results)))
        print "-" * 80
        for item in all_results:
            mac = item['mac']
            data = item['latest_data']
            severity = data.get('Severity', 'N/A')
            incident_type = data.get('IncidentType', 'N/A')
            gnow = data.get('Gnow', 'N/A')
            gend = data.get('Gend', 'N/A')
            status = data.get('Status', 'N/A')
            
            if severity == '严重':
                color = COLOR_RED
            elif severity == '中度':
                color = COLOR_YELLOW
            else:
                color = COLOR_GREEN
            
            print(COLOR_CYAN + "MAC地址: {}".format(mac) + COLOR_RESET)
            print("{}严重程度: {} | 异常类型: {} | 时间范围: {}~{}\033[0m".format(
                color, severity, incident_type, gnow, gend))
            print("详情: {}".format(status))
            print("-" * 80)
    else:
        log_success("所有MAC地址均无异常数据")

# ========== 主执行函数 ==========
def check_t2_basic_environment():
    """T2基础环境检查"""
    print_section_title("第一部分：T2基础环境检查")
    
    basic_check_results = []
    
    # 1. 内核版本检查
    result = check_kernel_version()
    basic_check_results.append(("内核版本", result))
    
    # 2. 挂载点检查
    result = check_mount_points()
    basic_check_results.append(("挂载点", result))
    
    # 3. T2平台交付记录检查
    result = check_T2_deliver_record()
    basic_check_results.append(("T2交付记录", result))
    
    # 4. T2安装日志检查
    result = check_T2_install_log()
    basic_check_results.append(("T2安装日志", result))
    
    # 5. T2容器及日志检查
    result = check_container_log()
    basic_check_results.append(("容器日志", result))
    
    # 统计结果
    passed = sum(1 for _, result in basic_check_results if result)
    total = len(basic_check_results)
    
    print COLOR_BOLD + "\n" + "="*60 + COLOR_RESET
    print COLOR_BOLD + "T2基础环境检查汇总" + COLOR_RESET
    print COLOR_BOLD + "="*60 + COLOR_RESET
    
    for check_name, result in basic_check_results:
        status = COLOR_GREEN + "✓ 通过" + COLOR_RESET if result else COLOR_RED + "✗ 失败" + COLOR_RESET
        print "{}: {}".format(check_name.ljust(12), status)
    
    print "\n总计: {}/{} 项检查通过".format(passed, total)
    if passed == total:
        log_success("T2基础环境检查全部通过！")
    else:
        log_warning("T2基础环境检查有 {} 项未通过".format(total - passed))
    
    return passed == total

def check_t2_business_quality():
    """T2业务质量检查"""
    print_section_title("第二部分：T2业务质量检查")
    
    # 1. 服务器MAC地址列表
    filtered_macs = check_server_mac_addresses()
    
    # 2. MAC地址异常数据汇总
    if filtered_macs:
        check_mac_abnormal_data(filtered_macs)

def main():
    """主执行函数"""
    # 第一部分：T2基础环境检查
    basic_passed = check_t2_basic_environment()
    
    # 第二部分：T2业务质量检查
    check_t2_business_quality()

if __name__ == "__main__":
    main()