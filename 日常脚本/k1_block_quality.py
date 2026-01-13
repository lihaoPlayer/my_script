#!/usr/bin/env python
# -*- coding: utf-8 -*-

import re
import ssl
import urllib2
from datetime import datetime, timedelta
import sys

# 在 Python 2 中设置默认编码为 UTF-8
reload(sys)
sys.setdefaultencoding('utf-8')

def get_guid_from_file():
    """从文件中获取GUID并处理"""
    try:
        with open('/usr/local/ksp2p-comm/ks.sh', 'r') as f:
            content = f.read()
        match = re.search(r'--guid=(\S+)', content)
        if match:
            guid = match.group(1)
            # 去掉冒号及后缀（例如 ":000"）
            if ':' in guid:
                guid = guid.split(':', 1)[0]
            return guid
        return None
    except Exception:
        return None

def fetch_url_data(url):
    """通用URL数据获取函数，支持SSL忽略验证"""
    try:
        if url.startswith('https://') and hasattr(ssl, '_create_unverified_context'):
            ssl_context = ssl._create_unverified_context()
            response = urllib2.urlopen(url, context=ssl_context)
        else:
            response = urllib2.urlopen(url)
        
        resp_data = response.read()
        try:
            return resp_data.decode('utf-8')
        except Exception:
            return resp_data
    except Exception as e:
        return None

def check_k_block_status(guid, date_time):
    """检查K是否被拉黑并输出所有匹配行的指定列数据"""
    url = "http://103.215.140.118:4433/provider/lfsy3289476/{}/limitNodeList/limitNodeList.txt?wework_cfm_code=OEjWajEpq9AVo%2B08KWQl5NwNwNfjoAtA%2B0WTsetr3wMCHwSa7KagTuk7Uv27wzp%2Fv0zUFqI%2Fk7mzXq%2BnWSlwvr6TyAmasHGAHTU5AVYw%2FkAe8x3bAggPfvz2VQqBGVrE%2BWZvYlAY%2Fex9".format(date_time)
    
    data = fetch_url_data(url)
    if data is None:
        return None, []  # 表示无法访问链接
    
    lines = data.splitlines()
    block_data_list = []
    for line in lines:
        if guid in line:
            parts = re.split(r'\s+', line.strip())
            # 获取第4列（线路网卡名称）和第12列（拉黑说明）
            nic_name = parts[3] if len(parts) > 3 else "N/A"
            block_desc = parts[12] if len(parts) > 12 else "N/A"
            block_data_list.append([nic_name, block_desc])
    
    is_blocked = len(block_data_list) > 0
    return is_blocked, block_data_list

def check_k_quality_metrics(guid, date_time):
    """检查K的质量指标"""
    url = "http://103.215.140.118:4433/provider/lfsy3289476/{}/night/allIndex.txt".format(date_time)
    
    # 英文指标列表
    english_metrics = [
        "reportOffLine",     # 带宽掉线次数
        "coredump",          # 程序崩溃
        "cachePerG",         # 缓存带宽比
        "cpuUsage",          # CPU使用率
        "cpuSoftIrq",        # CPU软中断
        "cpuIoWait",         # CPU I/O等待
        "ioDelay",           # I/O延迟
        "appGtNicBw",        # 业务带宽超限
        "hotPushTotalFiles", # 高峰期推送文件数
        "ispIdentifyError",  # 运营商识别错误
        "natIdentifyError",  # NAT类型识别异常
        "err500",            # 500错误率
        "tcpRetran",         # TCP重传率
        "avgLineTcpSpeed",   # 平均线路TCP速度
        "tcpstatus",         # TCP拨测状态
        "multiLineTcpRetran" # 多线路TCP重传
    ]
    
    # 简化的指标影响说明
    impact_explanations = {
        "reportOffLine": "影响：导致该线路完全离线，不产生任何流量。长期出现会严重拉低调度优先级，直接影响收益",
        "coredump": "影响：服务中断。若非硬件瓶颈导致，频繁崩溃表明程序本身可能存在缺陷，需要及时反馈修复",
        "cachePerG": "影响：缓存过低会降低调度优先级。正常应稳定在1000GB/1Gbps或以上",
        "cpuUsage": "影响：使用率高于80%表明CPU资源可能不足，会导致调度优先级降低或被直接拉黑",
        "cpuSoftIrq": "影响：占比高于20%需检查软中断是否均衡绑定、网卡队列配置是否正确，否则会降级或拉黑",
        "cpuIoWait": "影响：占比高于20%表明磁盘I/O压力过大，需要排查，否则会降低调度优先级或被拉黑",
        "ioDelay": "影响：延迟过大会直接影响数据传输效率，导致调度优先级降低或被拉黑",
        "appGtNicBw": "影响：很可能是网卡或设备被限速，导致性能瓶颈，直接影响跑量。",
        "hotPushTotalFiles": "影响：数量过少（少于500）可能被判定为限制缓存等作弊行为，会导致服务被降级或拉黑",
        "ispIdentifyError": "影响：此类机器必须直接下线，否则会严重影响调度跑量或被拉黑",
        "natIdentifyError": "影响：目前仅支持NAT0和NAT1，专线机器必须为NAT0。类型异常会影响节点连接性和调度",
        "err500": "影响：高于1%会浪费调度请求，导致机器调度优先级降低或被拉黑",
        "tcpRetran": "影响：大于5%被认为网络质量差，会被调度系统压制或少调度，严重时会被拉黑",
        "avgLineTcpSpeed": "影响：全局平均正常在50Mbps以上，低于15Mbps会直接影响跑量，并被调度压制或拉黑",
        "tcpstatus": "影响：拨测异常，基本不跑量，需自查防火墙或网络策略是否拦截",
        "multiLineTcpRetran": "影响：单线重传高会直接影响该线路的调度，即使整机指标正常，也会拉低整机跑量"
    }
    
    data = fetch_url_data(url)
    if data is None:
        return None  # 表示无法访问链接
    
    lines = data.splitlines()
    for line in lines:
        if guid in line:
            parts = re.split(r'\s+', line.strip())
            result = parts[7:] if len(parts) > 7 else []

            outputs = []
            for idx, value in enumerate(result):
                if not value or value == "-":
                    continue
                if idx < len(english_metrics):
                    metric_name = english_metrics[idx]
                    impact = impact_explanations.get(metric_name, "无影响说明")
                    outputs.append({
                        'metric': metric_name,
                        'value': value,
                        'impact': impact
                    })
            return outputs
    
    # 如果没有找到GUID，表示正常
    return []

def main():
    """主检查函数"""
    # 获取GUID
    guid = get_guid_from_file()
    if not guid:
        print("❌ 无法读取GUID，/usr/local/ksp2p-comm/ks.sh 文件不存在或格式错误")
        return
    
    print("🔍 检查GUID: {}".format(guid))
    print("=" * 80)
    
    # 获取日期
    date_time_tmp = datetime.now() - timedelta(days=1)
    date_time = date_time_tmp.strftime("%Y%m%d")
    print("📅 检查日期: {}".format(date_time))
    print("-" * 80)
    
    # 检查拉黑状态及所有匹配行的指定列数据
    print("1. 拉黑状态及数据检查:")
    block_status, block_data_list = check_k_block_status(guid, date_time)
    
    if block_status is None:
        print("   ❓ 无法访问拉黑链接")
    elif block_status:
        print("   ❌ K已被拉黑，共 {} 条记录".format(len(block_data_list)))
        print("     | 线路网卡名称 | 拉黑说明 |")
        for idx, data in enumerate(block_data_list, 1):
            nic_name, block_desc = data
            print("     | {} | {} |".format(nic_name, block_desc))
    else:
        print("   ✅ K未被拉黑")
    
    print("-" * 80)
    
    # 检查质量指标
    print("2. 质量指标检查:")
    quality_metrics = check_k_quality_metrics(guid, date_time)
    
    if quality_metrics is None:
        print("   ❓ 无法访问质量链接")
    elif isinstance(quality_metrics, list) and len(quality_metrics) == 0:
        print("   ✅ 所有质量指标正常")
    else:
        print("   📊 发现以下问题指标:")
        for item in quality_metrics:
            # 获取指标的中文名称
            chinese_name = {
                "reportOffLine": "网卡上报失败",
                "coredump": "程序崩溃",
                "cachePerG": "缓存带宽比",
                "cpuUsage": "CPU使用率",
                "cpuSoftIrq": "CPU软中断",
                "cpuIoWait": "CPU I/O等待",
                "ioDelay": "I/O延迟",
                "appGtNicBw": "业务带宽超限",
                "hotPushTotalFiles": "高峰期推送文件数",
                "ispIdentifyError": "运营商识别错误",
                "natIdentifyError": "NAT类型识别异常",
                "err500": "500错误率",
                "tcpRetran": "TCP重传率",
                "avgLineTcpSpeed": "平均线路TCP速度",
                "tcpstatus": "TCP拨测状态",
                "multiLineTcpRetran": "多线路TCP重传"
            }.get(item['metric'], item['metric'])
            
            print("     • {} （{}）: {} 【{}】".format(
                item['metric'], 
                chinese_name, 
                item['value'], 
                item['impact']
            ))
    
    print("=" * 80)
    print("检查完成")

if __name__ == "__main__":
    main()
