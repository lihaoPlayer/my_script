#!/bin/bash

# 核心配置
TARGET_KERNEL="5.4.119-19-0006"  # 目标内核版本
CONTAINER_PREFIX="k8s_pcdn-lego-server"  # 容器名称前缀
LOG_ABSOLUTE_PATH="/lego/log/lego_server.ERROR"  # 日志绝对路径
TARGET_ERROR="No such file or directory"  # 需要检测的错误信息
PROMPT_MSG="【提示】检测到 '${TARGET_ERROR}' 错误，请执行t2重启不跑命令！"  # 错误提示信息
# 挂载点配置（支持通配符）
MANDATORY_MOUNT1="/pcdn_data/pcdn_index_data"  # 固定挂载点
MANDATORY_MOUNT2_PATTERN="/pcdn_data/storage*_ssd"  # 通配符挂载点（storage1_ssd、storage2_ssd等）

# ==================== 第一步：检查内核版本 ====================
echo "=== 1. 内核版本检查 ==="
CURRENT_KERNEL=$(uname -r)
echo "当前内核版本：${CURRENT_KERNEL}"

if [ "${CURRENT_KERNEL}" = "${TARGET_KERNEL}" ]; then
    echo -e "\033[32m[正常] 内核版本符合要求！\033[0m\n"
else
    echo -e "\033[31m[错误] 内核版本不匹配！请升级内核到 ${TARGET_KERNEL} 版本！\033[0m"
    exit 1
fi

# ==================== 第二步：检查必要挂载点 ====================
echo "=== 2. 挂载点检查 ==="

# 检查固定挂载点（/pcdn_data/pcdn_index_data）
if [ ! -d "${MANDATORY_MOUNT1}" ] || ! mountpoint -q "${MANDATORY_MOUNT1}"; then
    echo -e "\033[31m[错误] 挂载方式不正确！未找到挂载点 ${MANDATORY_MOUNT1}，请重新挂载！\033[0m"
    exit 1
fi

# 检查通配符挂载点（/pcdn_data/storage*_ssd）
# 查找所有匹配通配符的挂载点，且必须是有效挂载点
MATCHED_MOUNTS=$(find /pcdn_data -maxdepth 1 -type d -path "${MANDATORY_MOUNT2_PATTERN}" | while read -r mount; do
    mountpoint -q "${mount}" && echo "${mount}"
done)

if [ -z "${MATCHED_MOUNTS}" ]; then
    echo -e "\033[31m[错误] 挂载方式不正确！未找到符合 ${MANDATORY_MOUNT2_PATTERN} 的有效挂载点，请重新挂载！\033[0m"
    exit 1
fi

# 挂载点检查通过，输出匹配到的挂载点
echo -e "已找到有效挂载点："
echo "  - ${MANDATORY_MOUNT1}"
echo "  - $(echo "${MATCHED_MOUNTS}" | tr '\n' ' ')"
echo -e "\033[32m[正常] 所有必要挂载点均存在且挂载有效！\033[0m\n"

# ==================== 第三步：检查容器和日志错误 ====================
echo "=== 3. 容器及日志错误检查 ==="

# 1. 查找目标容器ID
CONTAINER_ID=$(docker ps --filter "name=^/${CONTAINER_PREFIX}" --format "{{.ID}}" | head -n 1)
if [ -z "${CONTAINER_ID}" ]; then
    echo -e "\033[31m[错误] 未找到名称以 '${CONTAINER_PREFIX}' 开头的运行中容器！\033[0m"
    exit 1
fi

echo "找到目标容器，容器ID：${CONTAINER_ID}"
echo "正在检测日志中的目标错误..."

# 2. 静默检测日志中的目标错误（不输出日志内容）
if docker exec -i "${CONTAINER_ID}" tail -n 50 "${LOG_ABSOLUTE_PATH}" | grep -F -q "${TARGET_ERROR}"; then
    echo -e "\n\033[31m${PROMPT_MSG}\033[0m"
else
    echo -e "\n\033[32m[正常] 未检测到 '${TARGET_ERROR}' 错误！\033[0m"
fi
