#!/bin/bash

# 创建 Block_Bandwidth.sh 脚本的完整路径
ks_Block_Bandwidth="/usr/local/Data-source/Block_Bandwidth.sh"

# 创建目标目录（如果不存在）
mkdir -p "$(dirname "$ks_Block_Bandwidth")"

# 创建脚本内容
cat << 'EOF' > "$ks_Block_Bandwidth"
#!/bin/bash

# 设置输出目录和文件
output_dir="/var/log/mx-cIndicator"
output_file="$output_dir/ks_LH.prom"

# 确保输出目录存在
mkdir -p "$output_dir"

# 检查输出目录是否有写入权限
if [ ! -w "$output_dir" ]; then
    echo "错误: 对目录 $output_dir 没有写入权限"
    echo "请使用sudo运行此脚本或更改目录权限"
    exit 1
fi

# 获取本地GUID值
echo "正在获取本地GUID值..."
GUID=$(ps -ef | grep ksp2p | grep -oP '(?<=--guid=)[^ ]*' | head -n 1)

# 检查是否成功获取GUID
if [ -z "$GUID" ]; then
    echo "错误: 无法从进程信息中提取GUID值"
    echo "请确保ksp2p进程正在运行"
    exit 1
fi

echo "找到GUID: $GUID"

# 计算日期（格式：YYYYMMDD）
PREVIOUS_DATE=$(date -d "yesterday" +"%Y%m%d")  # 用于下载数据的前一天日期
CURRENT_DATE=$(date +"%Y%m%d")                  # 用于文件命名的当前日期
echo "使用日期（下载）: $PREVIOUS_DATE"
echo "使用日期（文件命名）: $CURRENT_DATE"

# 构建动态URL
BASE_URL="http://103.215.140.118:4433/provider/lfsy3289476/${PREVIOUS_DATE}/limitNodeList/limitNodeList.txt?wework_cfm_code=OEjWajEpq9AVo%2B08KWQl5NwNwNfjoAtA%2B0WTsetr3wMCHwSa7KagTuk7Uv27wzp%2Fv0zUFqI%2Fk7mzXq%2BnWSlwvr6TyAmasHGAHTU5AVYw%2FkAe8x3bAggPfvz2VQqBGVrE%2BWZvYlAY%2Fex9"
echo "目标URL: $BASE_URL"

# 定义文件路径
TEMP_FILE="${output_dir}/temp_download.txt"
DATA_FILE="${output_dir}/limitNodeList_${CURRENT_DATE}.txt"
EXTRACTED_FILE="${output_dir}/extracted_data_${CURRENT_DATE}.txt"
PROMETHEUS_FILE="${output_dir}/ks_LH.prom"  # Prometheus输出文件

# 下载数据
echo "正在从服务器下载数据..."
curl -s "$BASE_URL" -o "$TEMP_FILE"

# 检查下载是否成功
if [ $? -ne 0 ] || [ ! -s "$TEMP_FILE" ]; then
    echo "下载失败，请检查网络连接或URL有效性"
    rm -f "$TEMP_FILE"
    exit 1
fi

# 过滤数据（保留标题行和匹配GUID的行）
echo "正在过滤数据..."
head -n 1 "$TEMP_FILE" > "$DATA_FILE"
grep " $GUID " "$TEMP_FILE" >> "$DATA_FILE"

# 检查匹配数据量
LINE_COUNT=$(wc -l < "$DATA_FILE")
if [ $LINE_COUNT -le 1 ]; then
    echo "警告: 未找到与GUID '$GUID' 匹配的数据"
    echo "但已创建包含标题的空文件: $DATA_FILE"
    rm -f "$TEMP_FILE"
    exit 0  # 无数据时不继续生成Prometheus指标
fi

echo "数据过滤完成，有效记录数: $LINE_COUNT - 1"
echo "过滤后数据保存至: $DATA_FILE"

# 清理临时下载文件
rm -f "$TEMP_FILE"

# 提取指定字段（guid, 接口, 单线带宽，临界值, 拉黑带宽）
echo "正在提取指定字段..."
echo "guid 线路网卡名称 单线带宽(Gbps) 跑量临界值(Gbps) 拉黑带宽(Gbps)" > "$EXTRACTED_FILE"

# 处理数据行（跳过标题行）
tail -n +2 "$DATA_FILE" | while read -r line; do
    guid=$(echo "$line" | awk '{print $2}')
    interface=$(echo "$line" | awk '{print $4}')
    singleline=$(echo "$line" | awk '{print $9}')
    threshold=$(echo "$line" | awk '{print $11}')
    blacklist=$(echo "$line" | awk '{print $12}')

    # 写入提取后的文件（注意：若字段包含空格需调整分隔符）
    echo "$guid $interface $singleline $threshold $blacklist" >> "$EXTRACTED_FILE"
done

echo "字段提取完成，结果保存至: $EXTRACTED_FILE"

# ---------------------------- 生成Prometheus指标 ----------------------------
echo -e "
正在生成Prometheus格式指标文件..."

# 检查提取后的文件是否存在（理论上不会，因前面已做检查）
if [ ! -f "$EXTRACTED_FILE" ]; then
    echo "错误: 提取文件 $EXTRACTED_FILE 不存在"
    exit 1
fi

# 清空或创建Prometheus输出文件
> "$PROMETHEUS_FILE"

# 添加指标头部
echo '# HELP Ks_block_bandwidth Combined network metrics with threshold and blacklist values' >> "$PROMETHEUS_FILE"
echo '# TYPE Ks_block_bandwidth gauge' >> "$PROMETHEUS_FILE"

# 处理数据行并生成指标（将Gbps转换为Mbps并去除末尾多余的0）
tail -n +2 "$EXTRACTED_FILE" | while read -r guid  interface singleline threshold blacklist; do
    # 从GUID提取简化hostname（假设GUID格式：xxx_xxx_xxx_xxx:xxx）
    hostname=$(echo "$guid" | cut -d'_' -f4 | cut -d':' -f1)

    # 将阈值和拉黑值从Gbps转换为Mbps（乘以1000），并去除末尾多余的.000
    threshold_mbps=$(echo "$threshold * 1000" | bc -l | sed -E 's/\.0+$//; s/\..*//')
    blacklist_mbps=$(echo "$blacklist * 1000" | bc -l | sed -E 's/\.0+$//; s/\..*//')
    
# 3. 执行核心命令：smallnode_control -l --json
    json_output=$(smallnode_control -l --json 2>/dev/null)
    cmd_exit_code=$?

# 检查命令是否成功执行
if [ $cmd_exit_code -ne 0 ]; then
    echo "Error executing smallnode_control"
    exit $cmd_exit_code
fi

# 6. 解析 JSON 生成指标（只取第一个接口的 Bandwidth）
bandwidth=$(echo "$json_output" | jq -r '.interface_list[0].Bandwidth // ""' 2>/dev/null)

get_planform() {
    local target_script="/usr/bin/issue.sh"
    local version_val=""
    
    # 优先级1：优先匹配 portal.chxyun.cn 域名的qrencode命令（原业务域名）
    local chxyun_line=$(grep -E "qrencode.*https://portal.chxyun.cn/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
    if [ -n "$chxyun_line" ]; then
        # 提取portal.chxyun.cn对应的version值
        version_val=$(echo "$chxyun_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
    else
        # 优先级2：匹配 www.smogfly.com 域名的qrencode命令
        local smogfly_line=$(grep -E "qrencode.*https://www.smogfly.com/H5Login.*version=" "$target_script" 2>/dev/null | head -n 1)
        if [ -n "$smogfly_line" ]; then
            # 提取www.smogfly.com对应的version值
            version_val=$(echo "$smogfly_line" | sed -n 's/.*version=//p' | sed 's/[&" ].*//' | tr -d '; ')
        fi
    fi

    # 按version值匹配planform（覆盖两种域名的版本规则）
    case "$version_val" in
        010|1)  echo "mx"    ;;  
        012|2)  echo "wc"    ;;  
        *)      echo "unknown" ;; 
    esac
}
# 调用函数获取 planform 值
planform=$(get_planform)  

# 输出结果
echo "Bandwidth: $bandwidth"

  if (( bandwidth > threshold_mbps )); then
        metric_value="0"
    else
        metric_value="1"
    fi

    # 写入Prometheus指标（每个接口指标，保留必要精度并优化格式）
    echo "Ks_block_bandwidth{interface=\"$interface\", planform=\"$planform\", Bandwidth=\"$bandwidth\",blacklist_mbps=\"$blacklist_mbps\",threshold_mbps=\"$threshold_mbps\"} $metric_value" >> "$PROMETHEUS_FILE"
done

echo "Prometheus指标文件生成完成: $PROMETHEUS_FILE"
echo "指标文件内容预览:"
cat "$PROMETHEUS_FILE"

echo -e "
所有任务执行完成"
EOF

# 赋予脚本可执行权限
chmod +x "$ks_Block_Bandwidth"
# 创建服务单元文件（保持不变）
cat << 'EOF' > /etc/systemd/system/Block_Bandwidth.service
[Unit]
Description=Run Block_Bandwidth.sh script to check for ks Block

[Service]
Type=oneshot
ExecStart=/usr/local/Data-source/Block_Bandwidth.sh  # 脚本路径与实际存储路径一致
EOF

# 创建定时器单元文件（修改为每天中午12点执行一次）
cat << 'EOF' > /etc/systemd/system/Block_Bandwidth.timer
[Unit]
Description=Run Block_Bandwidth.sh daily at 12:00 PM

[Timer]
# 每天中午12点执行（格式：年-月-日 时:分:秒）
OnCalendar=*-*-* 12:00:00
# 如果系统在预定时间关机，下次启动时补执行
Persistent=true

[Install]
WantedBy=timers.target
EOF

# 重新加载systemd配置并启用/启动定时器
systemctl daemon-reload
systemctl enable Block_Bandwidth.timer
systemctl start Block_Bandwidth.timer 

# 验证定时任务状态（可选输出）
echo "定时任务已设置完成，每天中午12点执行一次"
echo "当前定时任务状态："
systemctl list-timers | grep Block_Bandwidth