#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os  
import requests
import json
import argparse

# ---------------------- 读取JSON配置文件的函数 ----------------------
def read_config():
    # 1. 获取 sn_info.py 脚本本身所在的目录（现在是 /data/lihao）
    script_dir = os.path.dirname(os.path.abspath(__file__))
    # 2. 拼接 config.json 的绝对路径（/data/lihao/config.json，因为脚本和配置文件同级）
    config_file_path = os.path.join(script_dir, "config.json")
    
    try:
        with open(config_file_path, 'r', encoding='utf-8') as f:
            config = json.load(f)
        
        # 检查必要的 Token
        required_tokens = ["common_auth_token", "task_x_token"]
        for token in required_tokens:
            if token not in config or not str(config[token]).strip():
                log_fatal(f"配置文件错误：缺少或为空的 Token -> {token}")
                exit(1)
        
        return config
    except FileNotFoundError:
        log_fatal(f"未找到配置文件！请确保 config.json 在 {script_dir} 目录下（当前路径：{config_file_path}）")
        exit(1)
    except json.JSONDecodeError:
        log_fatal(f"config.json 格式错误！请检查逗号、引号是否正确（路径：{config_file_path}）")
        exit(1)
    except Exception as e:
        log_fatal(f"读取配置失败（路径：{config_file_path}）：{str(e)}")
        exit(1)


# ---------------------- 日志函数 ----------------------
def log_info(message):
    print(f"[INFO] {message}")

def log_fatal(*args, sep=" "):
    message = sep.join(str(arg) for arg in args)
    print(f"\033[31m[FATAL] {message}\033[0m")

def log_success(message):
    print(f"\033[32m[SUCCESS] {message}\033[0m")

# ---------------------- 加载配置 ----------------------
config = read_config()
common_auth_token = config["common_auth_token"].strip()
task_x_token = config["task_x_token"].strip()

# ---------------------- 故障状态映射 ----------------------
status_code_map_and_string = {
    "拨号失败": "dial_task_id",
    "部署失败": "deploy_task_id",
    "扫描失败": "scan_task_id",
    "环境初始化失败": "env_init_task_id",
    "清理失败": "clear_task_id"
}

# ---------------------- 查询故障状态 ----------------------
def get_task_status(taskId):
    url = "https://raven-recruit.bs58i.baishancdnx.com/api/task/status"
    headers = {
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'User-Agent': 'PostmanRuntime-ApipostRuntime/1.1.0',
        'x-token': task_x_token
    }
    params = {'taskId': taskId}
    
    try:
        response = requests.get(url, headers=headers, params=params, timeout=10)
        if response.status_code == 200:
            return {"success": True, "data": response.json()}
        else:
            return {"success": False, "status_code": response.status_code, "message": f"HTTP {response.status_code}"}
    except Exception as e:
        return {"success": False, "message": "故障查询失败", "error": str(e)}

# ---------------------- 查询设备信息 ----------------------
def query_devices(mac_list, server_type="wuchu"):
    url = 'https://service.smogfly.com/admin/node/list' if server_type == "wuchu" else 'https://service.chxyun.cn/admin/node/list'
    payload = json.dumps({"page": 1, "pagesize": 3000, "mac": mac_list})
    headers = {"Content-Type": "application/json", "Authorization": common_auth_token}
    
    try:
        response = requests.post(url, headers=headers, data=payload, timeout=15)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        log_fatal(f"{server_type}平台请求失败：{str(e)}")
        return None

# ---------------------- 打印设备信息 ----------------------
def print_device_info(devices, server_type=""):
    if not devices:
        print("没有查询到设备信息")
        return
    
    task_result = "无任务状态信息"
    for device in devices:
        original_status = device.get('status', '').strip()
        for fault_key, task_field in status_code_map_and_string.items():
            if fault_key in original_status:
                task_id = device.get(task_field)
                if task_id and task_id != 0:
                    task_result = get_task_status(task_id)
                break
    
    for idx, device in enumerate(devices, 1):
        print(f"\n【设备 {idx}】")
        base_info = f"""
        设备SN: {device.get('mac', '未知')}
        设备状态：{device.get('status', '未知')}
        ISP: {device.get('isp', '未知')}
        地址：{device.get('address', '未知')}
        资源类型: {device.get('resource_type_name', '未知')}
        网络类型: {device.get('net_type_name', '未知')}
        网络名称: {device.get('network_name', '未知')}
        失败原因: {device.get('fail_reason', '无')}
        业务类型: {device.get('business_type', '未知')}
        部署业务: {device.get('deploy_business', '未知')}
        交付SN：{device.get('delivery_sn', '无')}
        服务限制类型: {device.get('is_province_inner', '未知')}
        单条带宽大小：{device.get('band_single', 0)} Mps
        总带宽：{device.get('band_count', 0)} Mps"""
        
        if server_type != "wuchu":
            base_info += f"\n        设备自检：{device.get('health_content', '无')}"
        
        if isinstance(task_result, dict):
            task_str = json.dumps(task_result, indent=2, ensure_ascii=False)
        else:
            task_str = str(task_result)
        
        base_info += f"\n        {device.get('status', '状态')}原因：{task_str}\n"
        print(base_info)
        print("-" * 80)

# ---------------------- 平台查询入口（极简版，确保返回列表） ----------------------
def wuchu_server(mac_list):
    log_info("开始查询雾出平台...")
    data = query_devices(mac_list, "wuchu")
    devices = data.get("data", {}).get("list", []) if data else []
    if devices:
        log_success(f"雾出平台查询到 {len(devices)} 个设备")
        print("\n=== 雾出平台设备详情 ===")
        print_device_info(devices, "wuchu")
    else:
        log_info("雾出平台未查询到设备")
    return devices  # 直接返回列表（空或有数据）

def manxing_server(mac_list):
    log_info("开始查询漫星平台...")
    data = query_devices(mac_list, "manxing")
    devices = data.get("data", {}).get("list", []) if data else []
    if devices:
        log_success(f"漫星平台查询到 {len(devices)} 个设备")
        print("\n=== 漫星平台设备详情 ===")
        print_device_info(devices, "manxing")
    else:
        log_info("漫星平台未查询到设备")
    return devices  # 直接返回列表（空或有数据）

# ---------------------- 读取MAC文件 ----------------------
def read_macs_from_file(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            macs = [line.strip() for line in f if line.strip()]
        if not macs:
            log_fatal("文件中没有有效SN")
        return macs
    except FileNotFoundError:
        log_fatal(f"文件未找到：{file_path}")
        return []
    except Exception as e:
        log_fatal(f"读取文件失败：{str(e)}")
        return []

# ---------------------- 主函数 ----------------------
def main():
    parser = argparse.ArgumentParser(description='设备信息查询工具（支持雾出/漫星双平台）')
    parser.add_argument('-sn', '--serial-number', type=str, help='单个设备SN')
    parser.add_argument('-file', type=str, help='多个SN的文件路径（每行一个）')
    args = parser.parse_args()
    
    # 收集MAC列表
    mac_list = []
    if args.serial_number:
        mac_list = [args.serial_number.strip()]
    elif args.file:
        mac_list = read_macs_from_file(args.file)
    else:
        parser.print_help()
        return
    
    mac_list = [mac for mac in mac_list if mac]
    if not mac_list:
        log_fatal("没有有效的设备SN可查询")
        return
    
    log_info(f"共获取到 {len(mac_list)} 个设备SN，开始查询...")
    
    # 关键修复：强制转为列表（如果返回None，直接变成[]）
    wu_devices = wuchu_server(mac_list) or []
    man_devices = manxing_server(mac_list) or []
    
    # 汇总结果（绝对不会报错）
    total = len(wu_devices) + len(man_devices)
    print("\n" + "="*50)
    if total > 0:
        log_success(f"查询完成！共找到 {total} 个设备（雾出：{len(wu_devices)} 个，漫星：{len(man_devices)} 个）")
    else:
        log_info("查询完成！两个平台均未找到匹配设备")

if __name__ == "__main__":
    main()