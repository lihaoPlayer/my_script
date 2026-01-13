#!/bin/bash

# 配置参数
API_URL="https://ansible-service-backend.chxyun.cn/api/server/ansibleBatch"
AUTH_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6InJlY3J1aXQiLCJwYXNzd29yZCI6ImowN2x4OGRlNXU0bnRKcmJkOE91IiwiZXhwIjoxNzY3MTkzMDYzLCJpc3MiOiJyZWNydWl0IiwibmJmIjoxNzY3MTc0MDYzfQ.gBrVxr_qRpmfiB9C46znq2J31CPMBAY-NyhssVobHe4"
YML_FILE="monitor-script.yml"
SERVICE_NAME="recruit_deployer"
NODES_FILE="nodes.txt"  # 存储节点地址的文件

# 检查节点文件是否存在
if [ ! -f "$NODES_FILE" ]; then
    echo "错误：节点文件 $NODES_FILE 不存在！"
    exit 1
fi

# 读取节点地址并构建JSON数组
NODE_LIST=$(awk '{print "\""$0"\","}' $NODES_FILE | sed '$s/,$//')

# 构建JSON数据
JSON_DATA=$(cat <<EOF
{
    "com-yml-file": "$YML_FILE",
    "nodeAddresses": [
        $NODE_LIST
    ],
    "serviceName": "$SERVICE_NAME"
}
EOF
)

# 执行curl请求
echo "正在发送请求到 $API_URL..."
response=$(curl -s -X POST \
  "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: $AUTH_TOKEN" \
  -d "$JSON_DATA")

# 显示响应结果
echo "响应结果："
echo "$response" | jq .  # 如果安装了jq可以格式化显示，否则直接echo "$response"