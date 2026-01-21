#!/bin/bash
# Copyright (c) 2022 baishan.com, Inc. All Rights Reserved 
# 
# Author: Adam Gao <adam.gao@baishan.com>
# Date: 2022-05-23 17:14:05
# Description: 
#   主要是创建network用户给idc使用，即去配置网络 

set -eu
set -o pipefail

# shopt -s extglob  # 使用扩展的文件通配(file expasion)
# shopt -s nullglob  # 如果没有通配到文件，则使用空值而非字符本身

# 环境变量定义
#PATH=$PATH
#export PATH

# 引用其它库文件
#source lib.sh

# 常量定义
#readonly PI=3.14

readonly DEBUG=1

# 函数定义
# 引脚本帮助信息
# ------------------------------------------
# 用于选项后带参数的情况
function parse:store(){
    cat<<BOOL
    --destination   <destination>   指定安装目标盘，可选，没指定则表示原系统盘
BOOL
}

# 用于选项不带参数的情况
function parse:bool(){
    cat<<STORE
    --init     是否安装完成后进行初始化
STORE
}

function parse:help(){
    echo "Usage: $(basename $0) --source <sdN> [options]"
    echo "Options:"
    parse:bool
    parse:store
}

# 将--no-id选项变为bool_no_id变量，并赋值为空
function parse:set_vars(){
    local prefix=$1  # bool or store
    while read define description; do
        local name=${define:2}
        name=${name//-/_}
        eval ${prefix}_${name}=""
    done< <(parse:$prefix)
}

function parse(){
    parse:set_vars bool
    parse:set_vars store

    local opt_error=
    local opt_help=

    while [[ $# -gt 0 ]]; do
        # 处理参数为help的情况
        # 处理-h的情况或者其它错误情况
        case $1 in
            -h|--help)
                opt_help=yes
                break
               ;;
            -[a-zA-Z0-9]*|[a-zA-Z0-9]*)
                opt_error="${opt_error}@未知的参数或选项:'$1'"
                break
                ;;
        esac

        local temp=${1:2}   # 截掉前缀--
        temp=${temp//-/_}  # 将-转换为__
        # 处理bool前缀的的变量，如果有设置就用yes
        case bool_$temp in
            $(eval echo \${!bool_$temp*}))
                eval bool_$temp=yes
                shift
                continue
                ;;
        esac

        # 处理store前缀变量，如果有设置为第二个值
        case store_$temp in
            $(eval echo \${!store_$temp*}))
                if [[ $# -eq 1 ]]; then
                    opt_error="${opt_error}@选项'$1'未提供必需的参数"
                    break
                fi
                shift
                eval "store_$temp='$1'"
                shift
                continue
                ;;
            *)
                opt_error="${opt_error}@未知的选项:'$1'"
                shift
                break
                ;;
        esac
    done


    # 以key=value的方式打印出所有变量，使用时只需要source <(parse $@)即可
    for key in opt bool store; do
        for var in $(eval echo \${!${key}_*}); do
            # echo "${var}=$(eval echo \$$var)"
            echo "${var}='${!var}'"
        done
    done
}
# ------------------------------------------

# 红色显示
function _colorful_display(){
    local color=$1 
    shift

    echo -n -e "\033[${color}m"
    echo -n "$@"
    echo -e "\033[0m"
}

# 红色显示
function _red_display(){
    _colorful_display "31" "$@"
}

# 绿色显示
function _green_display(){
    _colorful_display "32" "$@"
}

function _log_with_green(){
    _green_display "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@ "
}

# 用于显示警告信息
function _warn(){
    _red_display "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: WARN: $@" >&2
}

# 用出显示错误并退出的函数
function _exit_with_red_display() {
    _red_display "ERROR: $@" >&2
    exit 1
}

# 断言函数，如果值为假，显示给定信息并退出
function _assert(){
    local value=$1
    local message=$2
    if [[ ! "$value" ]]; then
        _exit_with_red_display "$message"
    fi

}

# 用于打印出调试信息的函数
function _debug() {
    if [[ "$DEBUG" == "1" ]]; then
        _log_with_green "debug - $@" >&2
    fi
}

function user:network:sudoers(){
    local user=$1
    local shell=$2
    cat<<EOF
$user ALL=(root)NOPASSWD: $shell
EOF
}

function user:network:new(){
    local user=$1
    local shell=$2
    local passwd_hash=$3

    if ! getent passwd network &>/dev/null; then
        useradd "$user"
    fi

    usermod "$user" -s "/usr/bin/sudo $shell" -p "$passwd_hash"
}

function user:network:init(){
    local user=network
    local shell=/bin/win.py
    local passwd_hash='$6$DCR5QVdtYbH1kYoP$nU6pnbripbMvInjYWxE/oRQRkxAdinAELiSQYmMKYA2FTUU6bRM1YtgFo2qLpnbx4.YKMJgRdO/WZBDSMEYvF0'

    local sudoers=/etc/sudoers.d/user-$user

    if [[ ! -x "$shell" ]]; then
        _exit_with_red_display "用户shell文件: '$shell'不存在"
    fi

    # 添加用户
    user:network:new "$user" "$shell" "$passwd_hash"

    # 添加sudo权限
    _debug "-->设置network用户登陆shell为: $shell"
    user:network:sudoers "$user" "$shell" >$sudoers
}


# 主函数定义
function main(){
    # 如果需要分析命令行参数，仅仅需要将:改成#:即可
    :<<'###'
    . <(parse "$@")
    if [[ "$opt_help" ]]; then
        parse:help
        exit 0
    fi
    if [[ "$opt_error" ]]; then
        parse:help
        _exit_with_red_display "$opt_error"
    fi
###

    # 所有的代码从这里开始
    user:network:init
}
# 执行主函数
main "$@"
