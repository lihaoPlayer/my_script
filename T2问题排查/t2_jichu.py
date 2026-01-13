#!/usr/bin/env python
# -*- coding: utf-8 -*-
import os
import subprocess
import sys

# 核心配置（可根据实际需求调整）
TARGET_KERNEL = "5.4.119-19-0006"
CONTAINER_PREFIX = "k8s_pcdn-lego-server"
LOG_ABSOLUTE_PATH = "/lego/log/lego_server.ERROR"
TARGET_ERROR = "No such file or directory"
PROMPT_MSG = "【提示】检测到 '{}' 错误，请执行t2重启不跑命令！".format(TARGET_ERROR)
MANDATORY_MOUNT1 = "/pcdn_data/pcdn_index_data"
MANDATORY_MOUNT2_PATTERN = "/pcdn_data/storage*_ssd"

# 颜色输出配置
COLOR_GREEN = "\033[32m"
COLOR_RED = "\033[31m"
COLOR_RESET = "\033[0m"


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


def check_kernel_version():
    """检查内核版本"""
    print "=== 1. 内核版本检查 ==="
    ret_code, current_kernel, _ = execute_cmd("uname -r")
    if ret_code != 0:
        print COLOR_RED + "[错误] 无法获取内核版本！" + COLOR_RESET
        return False
    
    print "当前内核版本：{}".format(current_kernel)
    if current_kernel == TARGET_KERNEL:
        print COLOR_GREEN + "[正常] 内核版本符合要求！" + COLOR_RESET + "\n"
        return True
    else:
        print COLOR_RED + "[错误] 内核版本不匹配！请升级内核到 {} 版本！".format(TARGET_KERNEL) + COLOR_RESET
        return False


def check_mount_points():
    """检查必要挂载点"""
    print "=== 2. 挂载点检查 ==="

    # 检查固定挂载点
    if not os.path.isdir(MANDATORY_MOUNT1):
        print COLOR_RED + "[错误] 挂载方式不正确！未找到挂载点 {}，请重新挂载！".format(MANDATORY_MOUNT1) + COLOR_RESET
        return False
    
    ret_code, _, _ = execute_cmd("mountpoint -q {}".format(MANDATORY_MOUNT1))
    if ret_code != 0:
        print COLOR_RED + "[错误] 挂载方式不正确！{} 未挂载，请重新挂载！".format(MANDATORY_MOUNT1) + COLOR_RESET
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
        print COLOR_RED + "[错误] 挂载方式不正确！未找到符合 {} 的有效挂载点，请重新挂载！".format(MANDATORY_MOUNT2_PATTERN) + COLOR_RESET
        return False

    # 输出有效挂载点
    print "已找到有效挂载点："
    print "  - {}".format(MANDATORY_MOUNT1)
    print "  - {}".format(" ".join(matched_mounts))
    print COLOR_GREEN + "[正常] 所有必要挂载点均存在且挂载有效！" + COLOR_RESET + "\n"
    return True


def check_container_log():
    """检查容器和日志错误"""
    print "=== 3. 容器及日志错误检查 ==="

    # 提取容器ID（稳定方案）
    docker_cmd = "docker ps | grep '{}' | head -n 1 | awk '{{print $1}}'".format(CONTAINER_PREFIX)
    ret_code, container_id, docker_err = execute_cmd(docker_cmd)
    
    if ret_code != 0 or not container_id:
        print COLOR_RED + "[错误] 未找到名称以 '{}' 开头的运行中容器！".format(CONTAINER_PREFIX) + COLOR_RESET
        if docker_err:
            print "Docker命令执行错误：{}".format(docker_err)
        return False
    
    print "找到目标容器，容器ID：{}".format(container_id)
    print "正在检测日志中的目标错误..."

    # 检测日志错误
    log_cmd = "docker exec -i {} tail -n 50 {}".format(container_id, LOG_ABSOLUTE_PATH)
    ret_code, log_content, log_err = execute_cmd(log_cmd)
    if ret_code != 0:
        print COLOR_RED + "[错误] 读取容器日志失败！容器ID：{}，错误信息：{}".format(container_id, log_err) + COLOR_RESET
        return False

    if TARGET_ERROR in log_content:
        print "\n" + COLOR_RED + PROMPT_MSG + COLOR_RESET
    else:
        print "\n" + COLOR_GREEN + "[正常] 未检测到 '{}' 错误！".format(TARGET_ERROR) + COLOR_RESET
    return True


def main():
    """主执行函数"""
    if not check_kernel_version():
        sys.exit(1)
    if not check_mount_points():
        sys.exit(1)
    check_container_log()
    print "\n=== 所有检查完成 ==="
    sys.exit(0)


if __name__ == "__main__":
    main()