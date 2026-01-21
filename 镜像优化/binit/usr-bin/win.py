#!/bin/env python
# coding: utf-8
# 用于替换掉控制台程序
import os
import re
import sys
import bstools
import datetime
import threading
import subprocess
import time

sys.path.insert(0, '/usr/lib/python2.7/site-packages/bstools/')

from bstools import urwid
from bstools import netfunc
from bstools.adapter import Adapters, Adapter
from bstools.ping import is_net_ok
from bstools.dig import is_dns_ok
from bstools.allconf import is_service_break

ATTR_BANNER = 'banner'
ATTR_ERROR = 'error'
ATTR_WARN = 'warn'
ATTR_INFO = 'info'
ATTR_FOCUS = 'focus'
ATTR_OPTION = 'option'
ATTR_BG = 'bg'

DEAULT_PALETTE = [
    # (属性, 前景色, 背景色)
    (ATTR_BANNER, 'black', 'light gray'),
    (ATTR_ERROR, 'black', 'light red'),
    (ATTR_WARN, 'black', 'yellow'),
    (ATTR_INFO, 'black', 'light green'),
    (ATTR_FOCUS, 'black', 'light red'),
    (ATTR_OPTION, 'black', 'light blue'),
    (ATTR_BG, 'black', 'dark blue'),
]

LANGUAGE = os.getenv("TTY_LANGUAGE", "")
TIMEOUT = 7200

class Prompt():
    def __init__(self, en, zh):
        self.en = en
        self.zh = zh

    def __str__(self):
        if LANGUAGE == "ZH":
            return self.zh
        else:
            return self.en

    def __add__(self, other):
        return str(self) + str(other)


PROMPT_OK = Prompt("OK", "确认")
PROMPT_FORBIDDEN = Prompt("no permit to run this function now", "当前状态不允许执行该功能")
PROMPT_FORBIDDEN_CHANGE_BOND_SLAVE = Prompt("unable to change bond-slave config", "无法修改bond-slave配置")
PROMOT_NETWORK_SETTING = Prompt("Network setting", "网络设置")
PROMOT_DISPLAY_SN = Prompt("Display system SN", "显示系统序列哈")
PROMOT_DNS_SETTING = Prompt("Config DNS", "配置DNS")
PROMPT_CONFIG_IP = Prompt("Config Static IP", "配置静态IP")
PROMPT_CONFIG_DHCP = Prompt("Config DHCP IP", "配置动态IP")
PROMPT_CONFIG_BOND = Prompt("Config Bond", "配置Bond")
# 新增PPPoE相关提示
PROMPT_CONFIG_PPPOE = Prompt("Config PPPoE", "配置PPPoE")
PROMPT_PPPOE_ACCOUNT = Prompt("Account", "账号")
PROMPT_PPPOE_PASSWORD = Prompt("Password", "密码")
PROMPT_PPPOE_BANDWIDTH = Prompt("Bandwidth", "带宽")
PROMPT_PPPOE_SAVE_SUCCESS = Prompt("PPPoE config saved to /etc/pppoe.conf", "PPPoE配置已保存到/etc/pppoe.conf")
PROMPT_PPPOE_EXECUTING = Prompt("Executing sn-ppp...", "正在执行sn-ppp...")
PROMPT_PPPOE_EXECUTE_RESULT = Prompt("sn-ppp execute result", "sn-ppp执行结果")
PROMPT_PPPOE_EMPTY_ACCOUNT = Prompt("Account cannot be empty", "账号不能为空")
PROMPT_PPPOE_EMPTY_PASSWORD = Prompt("Password cannot be empty", "密码不能为空")
PROMPT_PPPOE_PROCESSING = Prompt("Processing... Please wait", "处理中... 请等待")
# 在 Prompt 类新增两个提示，用于展示 smallnode_control 执行状态
PROMPT_SMALLNODE_EXECUTING = Prompt("wait check", "正在检测网络")
PROMPT_SMALLNODE_EXECUTE_RESULT = Prompt("network result", "网络检测结果")

PROMPT_NETCARD = Prompt("Adapter", "网卡")
PROMOT_NETCARD_SHOW = Prompt("ip link show", "显示网卡")
PROMPT_NETCARD_SELECT_NUM = Prompt("Please select 2-3 netcards", "请选择2-3个网卡")
PROMPT_NETCARD_SELECT_SPEED = Prompt("selected netcard has different speed",
                                     "选择的网卡有不同的速率")
PROMPT_VLAN_HINT = Prompt("* if not vlan, leave VLAN_ID blank", "如果非vlan, 则VLAN_ID留空")
PROMPT_CHECK_PASS = Prompt("check passed", "校验通过")
PROMOT_IPADDR_SHOW = Prompt("ip address show", "显示IP")
PROMOT_IP_ROUTE_SHOW = Prompt("ip route show", "显示路由")
PROMOT_PING = Prompt("ping test", "ping测试")
PROMOT_NET_STATUS = Prompt("network status: ", "网络状态: ")
PROMOT_DNS_STATUS = Prompt("dns resolve status: ", "dns解析状态: ")
PROMOT_GEN_BOND = Prompt("generating bond...", "生成bond网卡中...")
PROMOT_CHECKING_NET = Prompt("checking network...", "检测网络中...")
PROMOT_PINGING = Prompt("start ping...", "开始ping...")
PROMOT_CONNECTED = Prompt("connected", "连通")
PROMOT_DISCONNECTED = Prompt("disconnected", "断开")
PROMPT_CONFIRM_DHCP = Prompt("Are you sure configure to DHCP?", "确认配置为DHCP?")
PROMPT_PING_HINT = Prompt("* ping ipv4/ipv6/domain", "* ping ipv4/ipv6/域名")
PROMPT_INVALID_ADDR = Prompt("invalid address", "无效地址")
PROMPT_COMMAND_ERROR = Prompt("command excute error, please check addr",
                              "命令执行出错, 请检查地址")

# 全局变量用于跟踪PPPoE执行状态
pppoe_executing = False

def can_run():
    if not os.path.exists("/etc/bsc_common_disable_network_win"):
        return True
    if is_service_break():
        return True
    if not is_net_ok():
        return True
    return False


def exit_on_timeout(*args):
    raise urwid.ExitMainLoop()

def control_button(name):
    return urwid.Button(("banner", name))


def option_button(name):
    button = urwid.Button(str(name))
    return urwid.AttrMap(button, 'option', focus_map='focus')


class Node:
    def __init__(self, data):
        self.data = data
        self.prev = None


class Track:
    """用作于当前窗口堆栈, 即每次进入下一个窗口时, 将窗口入栈, 这样子便于回退到上个窗口
    """
    def __init__(self):
        self._current = None
        self._size = 0

    def add(self, data):
        node = Node(data)
        node.prev = self._current
        self._current = node
        self._size += 1

    def prev(self):
        if self._size != 0:
            self._current = self._current.prev
            self._size -= 1

    @property
    def size(self):
        return self._size

    @property
    def current(self):
        return self._current.data


def default_loop(top, palette=None):
    return urwid.MainLoop(top, palette)


class Win:

    _WIN = None

    class WinManager:

        _WM = None

        def __init__(self, top):
            self._track = Track()
            self._top = top
            self._track.add(self._top)
            self._loop = default_loop(urwid.Filler(self._top, 'top'),
                                      palette=DEAULT_PALETTE)
            self._loop.set_alarm_in(TIMEOUT, exit_on_timeout)

        def new_win(self, win):
            self._track.add(win)

        def back_win(self):
            self._track.prev()

        def return_win(self):
            while self._track.size > 1:
                self._track.prev()

        def display(self):
            self._loop.widget.original_widget = self._track.current

        def run(self):
            self._loop.run()

        def refresh(self):
            self._loop.draw_screen()

        def restart(self):
            self._loop.stop()
            self._loop.run()

    @classmethod
    def init(cls, **kw):
        if cls.get():
            raise Exception("It can be not reinit...")

        cls._WIN = cls.WinManager(**kw)

    @classmethod
    def get(cls):
        return cls._WIN


def _BACK():
    button = control_button(str(Prompt("BACK", "返回")))

    def _callback(button):
        wm = Win.get()
        wm.back_win()
        wm.display()

    urwid.connect_signal(button, 'click', _callback)

    return button


BACK = _BACK()


def _HOME():
    button = control_button(str(Prompt("HOME", "主菜单")))

    def _callback(button):
        wm = Win.get()
        wm.return_win()
        wm.display()

    urwid.connect_signal(button, 'click', _callback)

    return button


HOME = _HOME()

def get_width(button):
    label = button.get_label()
    label_len = len(label)
    if label.isalpha():
        return label_len + 4
    return label_len + 2


def common_col(*args):
    l = [BACK]
    l.extend(args)
    l.append(HOME)
    return urwid.Columns([('fixed', get_width(i), urwid.Pile([i])) for i in l],
                         dividechars=1)


def register_dns_ok_win(button, edit_nameservers, response, dig_result):
    def _callback(button):
        response.set_text("Output: ")

        nameservers = []
        for i in edit_nameservers:
            nameserver = i.get_edit_text()
            if nameserver:
                if netfunc.is_valid_ipv4_address(nameserver):
                    nameservers.append(nameserver)
                else:
                    err = Prompt(
                        "nameserver {} is not a valid IP address".format(
                            nameserver),
                        "nameserver {} 不是有效的IP地址".format(nameserver))
                    response.set_text((ATTR_ERROR, "Error: {}".format(err)))
                    return
        if len(nameservers) == 0:
            err = Prompt("at least specify one nameserver",
                         "至少需指定一个nameserver")
            response.set_text((ATTR_ERROR, "Error: {}".format(err)))
            return

        netfunc.cfg_resolv(nameservers)
        response.set_text((ATTR_INFO, str(Prompt("modify succeeded", "修改成功"))))

        def set_dig_result():
            dig_result.set_text(
                (ATTR_WARN, Prompt("checking dns", "检查dns中") + "..."))
            if is_dns_ok():
                dig_result.set_text(
                    (ATTR_INFO, PROMOT_DNS_STATUS + Prompt("ok", "正常")))
            else:
                dig_result.set_text(
                    (ATTR_ERROR, PROMOT_DNS_STATUS + Prompt(ATTR_ERROR, "异常")))
            wm.refresh()

        thread = threading.Thread(target=set_dig_result)
        thread.start()

    urwid.connect_signal(button, 'click', _callback)


def get_mac_address(interface):
    # 方法1：读取/sys/class/net/<interface>/address
    path = "/sys/class/net/{}/address".format(interface)
    try:
        with open(path, 'r') as f:
            mac = f.read().strip()
        if mac:
            return mac
    except IOError:
        pass

    try:
        output = subprocess.check_output(['ip', 'link', 'show', interface], stderr=subprocess.STDOUT)
        output = output.decode('utf-8') if isinstance(output, bytes) else output
        m = re.search(r'link/ether\s+([0-9a-f:]{17})', output)
        if m:
            return m.group(1)
    except Exception:
        pass

    return None

def register_dhcp_ok_win(button, name, **kw):
    def _callback(button):

        response = kw["response"]
        net = kw["net"]
        addr_show = kw["addr_show"]
        response.set_text("Output: ")

        bstools.ifdown(name)

        # 修复：移除mac参数，因为ifcfg_dhcp_ip不接受该参数
        mac = get_mac_address(name)
        netfunc.ifcfg_dhcp_ip(name)

        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        if bstools.ifup(name):
            response.set_text(
                (ATTR_INFO, "{}: ifup {} succeeded".format(now, name)))
        else:
            response.set_text(
                (ATTR_WARN, "{}: ifup {} failed".format(now, name)))

        dhcp_ip = bstools.ip_address_show(name).split()[-1].strip()
        if dhcp_ip:
            addr_show.set_text((ATTR_INFO, "DHCP IP: {}".format(dhcp_ip)))
        else:
            addr_show.set_text((ATTR_WARN, "DHCP IP: none"))

        def set_net():
            net.set_text((ATTR_WARN, str(PROMOT_CHECKING_NET)))
            if is_net_ok():
                net.set_text((ATTR_INFO, PROMOT_NET_STATUS + PROMOT_CONNECTED))
            else:
                net.set_text(
                    (ATTR_ERROR, PROMOT_NET_STATUS + PROMOT_DISCONNECTED))
            wm.refresh()

        thread = threading.Thread(target=set_net)
        thread.start()
        #netfunc.restart_network_service() # 重启network service

    urwid.connect_signal(button, 'click', _callback)


# 好像可以使用观察者模式, 即回调时通知
# 这里没想好优雅的处理方式, 目前还没有错误检测功能
# 比如不合法ip, 不合法的vlan等
def register_ip_ok_win(button, name, ip, netmask, gateway, vlan_id, **kw):
    """ip配置界面的回调操作, 这里应该配置ip, 但信息反馈是个问题
    @param: button: 即OK按钮本身
    @param: name: 网卡名
    @param: ip: ipv4
    @param: netmask: 掩码
    @param: gateway: 网关
    """
    def _callback(button):

        response = kw["response"]
        net = kw["net"]
        _name = name
        response.set_text("Output: ")

        if netfunc.get_vlanid_from_adapter_name(_name) == None and vlan_id.get_edit_text():
            _name = "{}.{}".format(_name, vlan_id.get_edit_text())

        err = netfunc.chk_ifcfg_content(_name,
                                        ip.get_edit_text(),
                                        netmask.get_edit_text(),
                                        gateway.get_edit_text(),
                                        vlan_id.get_edit_text(),
                                        language=LANGUAGE)
        if err:
            response.set_text((ATTR_ERROR, "Error: {}".format(err)))
            return

        bstools.ifdown(_name)

        # 修复：移除mac参数，因为auto_ifcfg_static_ip不接受该参数
        mac = get_mac_address(_name)
        netfunc.auto_ifcfg_static_ip(_name, ip.get_edit_text(),
                                netmask.get_edit_text(),
                                gateway.get_edit_text())

        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        if bstools.ifup(_name):
            response.set_text(
                (ATTR_INFO, "{}: ifup {} succeeded".format(now, _name)))
        else:
            response.set_text(
                (ATTR_WARN, "{}: ifup {} failed".format(now, _name)))

        def set_net():
            net.set_text((ATTR_WARN, str(PROMOT_CHECKING_NET)))
            if is_net_ok():
                net.set_text((ATTR_INFO, PROMOT_NET_STATUS + PROMOT_CONNECTED))
            else:
                net.set_text(
                    (ATTR_ERROR, PROMOT_NET_STATUS + PROMOT_DISCONNECTED))
            wm.refresh()

        thread = threading.Thread(target=set_net)
        thread.start()
        #netfunc.restart_network_service() # 重启network service

    urwid.connect_signal(button, 'click', _callback)


# 用于格式化网卡按钮的显示
def space_pad(name, width):
    l = len(name)
    delta = width - l
    if delta > 0:
        return "{}{}".format(name, " " * delta)
    return name


def format_adapter(adapter):
    return "{}{}{}{}".format(space_pad(adapter.name, 15),
                             space_pad(adapter.status, 7),
                             space_pad(str(adapter.speed), 8), adapter.address)


def create_adapter_button(adapter):
    """用于创建adapter按钮
    @params: adapter: adapter实例

    :return: urwid.Button: 返回按钮实例
    """
    text = format_adapter(adapter)
    return option_button(text)


class CommonWin:
    """所有需要渲染的窗口都通过此类来实现"""
    def __init__(self):
        self._items = []  # 窗口的widget元素死列表

    @property
    def items(self):
        """通过此方法来增加窗口元素, 即urwid.widget"""
        return self._items

    @property
    def win(self, wrapper=urwid.Pile):
        """最终的窗口布局由此提供"""
        return wrapper(self.items)


WinWidgetsContainer = CommonWin


def button_new_win(button, callback=None):
    """用于对button创建一个新的窗口并展示
    @param: button: 注册的button
    @param: callback: 业务的回调函数
    """
    def _callback(button):  # 每次按钮按下时调用此函数
        win = WinWidgetsContainer()  # 窗口元素

        # 也许也需要把button本身传到业务逻辑去
        # 但好像又没什么卵用……
        if callback:
            callback(win)  # 业务回调函数, 主要是填充新窗口元素

        wm = Win.get()
        wm.new_win(win.win)  # 添加此窗口, 代表要显示
        wm.display()  # 展示此窗口

    urwid.connect_signal(button, 'click', _callback)


def register_bind_config_on_adapter(button, adapters):

    ok = control_button(str(PROMPT_OK))
    response = urwid.Text('\n'.join(adapters))
    addr_show = urwid.Text("")

    def _callback(win):

        win.items.extend([
            urwid.Text("* {}".format(PROMPT_CONFIG_BOND)),
            response,
            urwid.Divider(),
            common_col(ok),
        ])

    button_new_win(button, _callback)


def register_dhcp_config_on_adapter(button, adapter):

    # 添加Back, OK, Return三个按钮
    ok = control_button(str(PROMPT_OK))
    response = urwid.Text("")
    addr_show = urwid.Text("")
    net = urwid.Text("")

    # 注册按钮回调动作
    # 如果对应条目没输入, 则为空
    register_dhcp_ok_win(
        ok,
        name=adapter.name,
        response=response,
        addr_show=addr_show,
        net=net,
    )

    # 将窗口元素添加到窗口中
    def _callback(win):
        win.items.extend([
            urwid.Text("* {}".format(PROMPT_CONFIG_DHCP)),
            urwid.Text("* {}: {}".format(PROMPT_NETCARD, adapter.name)),
            urwid.Divider(),
            urwid.Text(str(PROMPT_CONFIRM_DHCP)),
            urwid.Divider(),
            response,
            urwid.Divider(),
            addr_show,
            urwid.Divider(),
            net,
            urwid.Divider(),
            common_col(ok),
        ])

    button_new_win(button, _callback)


def register_static_ip_config_on_adapter(button, adapter):
    """进入ip配置界面"""
    data = netfunc.load_ifcfg_content(adapter.name)
    ip = urwid.Edit("IP     : ", data.get("IPADDR", ""))
    netmask = urwid.Edit("NETMASK: ", data.get("NETMASK", "255.255.255.0"))
    gateway = urwid.Edit("GATEWAY: ", data.get("GATEWAY", ""))
    name_split = adapter.name.split(".")
    vlan_id = urwid.IntEdit("VLAN_ID: ", "")
    if len(name_split) == 2:
        vlan_id.set_edit_text(name_split[1])

    ok = control_button(str(PROMPT_OK))
    clean = control_button(str(Prompt("clean", "清空")))
    response = urwid.Text("")

    net = urwid.Text("")

    def on_clean(button):
        for i in [ip, netmask, gateway, vlan_id]:
            i.set_edit_text("")

    urwid.connect_signal(clean, 'click', on_clean)

    # 注册按钮回调动作
    # 如果对应条目没输入, 则为空
    register_ip_ok_win(
        ok,
        name=adapter.name,
        ip=ip,
        netmask=netmask,
        gateway=gateway,
        response=response,
        net=net,
        vlan_id=vlan_id,
    )

    # 将窗口元素添加到窗口中
    def _callback(win):
        if data.get("NAME") == "bond-slave":
            body = [
                urwid.Text((ATTR_ERROR, str(PROMPT_FORBIDDEN_CHANGE_BOND_SLAVE))),
                urwid.Divider(),
                BACK,
            ]
            win.items.extend(body)
            return
        win.items.extend([
            urwid.Text("* {}".format(PROMPT_CONFIG_IP)),
            urwid.Text("* {}: {}".format(PROMPT_NETCARD, adapter.name)),
            urwid.Text(str(PROMPT_VLAN_HINT)),
            urwid.Divider(),
            ip,
            netmask,
            gateway,
            vlan_id,
            urwid.Divider(),
            response,
            urwid.Divider(),
            net,
            urwid.Divider(),
            common_col(clean),
            urwid.Divider(),
            ok,
        ])

    button_new_win(button, _callback)

# -------------------- 新增PPPoE配置读取函数 --------------------
def load_pppoe_config(adapter_name):
    """
    读取/etc/pppoe.conf配置文件，解析对应网卡的PPPoE参数
    :param adapter_name: 当前选中的网卡名称
    :return: 字典格式的PPPoE配置参数（account/password/vlan_id/bandwidth）
    """
    pppoe_config = {
        "account": "",
        "password": "",
        "vlan_id": "",
        "bandwidth": ""
    }
    conf_path = "/etc/pppoe.conf"
    
    # 若文件不存在，返回空配置
    if not os.path.exists(conf_path):
        return pppoe_config
    
    try:
        with open(conf_path, "r") as f:
            # 读取文件所有行，按行解析
            lines = f.readlines()
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                # 配置格式：网卡名,VLAN_ID,账号,密码,带宽,true
                parts = line.split(",")
                if len(parts) < 5:
                    continue
                # 匹配当前选中的网卡
                if parts[0] == adapter_name:
                    pppoe_config["vlan_id"] = parts[1].strip()
                    pppoe_config["account"] = parts[2].strip()
                    pppoe_config["password"] = parts[3].strip()
                    pppoe_config["bandwidth"] = parts[4].strip()
                    break  # 找到对应网卡配置后退出循环
    except Exception as e:
        # 读取/解析失败时返回空配置，不影响后续操作
        pass
    
    return pppoe_config

# -------------------- 新增PPPoE相关功能 --------------------
def register_pppoe_ok_win(button, adapter, account, password, vlan_id, bandwidth, **kw):
    """PPPoE配置确认按钮回调"""
    global pppoe_executing
    
    def _callback(button):
        global pppoe_executing
        
        response = kw["response"]
        exec_result = kw["exec_result"]
        
        # 检查是否正在执行中
        if pppoe_executing:
            response.set_text((ATTR_WARN, str(PROMPT_PPPOE_PROCESSING)))
            return
        
        # 清空响应信息
        response.set_text("Output: ")
        exec_result.set_text("")
        
        # 校验必填项
        account_val = account.get_edit_text().strip()
        password_val = password.get_edit_text().strip()
        if not account_val:
            response.set_text((ATTR_ERROR, "Error: {}".format(PROMPT_PPPOE_EMPTY_ACCOUNT)))
            return
        if not password_val:
            response.set_text((ATTR_ERROR, "Error: {}".format(PROMPT_PPPOE_EMPTY_PASSWORD)))
            return
        
        # 获取配置值
        vlan_id_val = vlan_id.get_edit_text().strip()
        bandwidth_val = bandwidth.get_edit_text().strip()
        adapter_name = adapter.name
        
        # 标记为执行中
        pppoe_executing = True
        wm.refresh()
        
        # 构建配置内容
        config_line = "{},{},{},{},{},true".format(
            adapter_name,
            vlan_id_val,
            account_val,
            password_val,
            bandwidth_val
        )
        
        try:
            # 覆盖写入配置文件
            with open("/etc/pppoe.conf", "w") as f:
                f.write(config_line + "\n")
            response.set_text((ATTR_INFO, str(PROMPT_PPPOE_SAVE_SUCCESS)))
            
            # 执行sn-ppp和smallnode_control的线程函数
            def execute_commands():
                global pppoe_executing
                try:
                    # 第一步：执行 sn-ppp（仅展示提示，不输出结果）
                    exec_result.set_text((ATTR_WARN, "Please wait, dialing..."))  # 英文提示：请稍等，拨号中
                    wm.refresh()
                    
                    # 执行sn-ppp（替换为实际绝对路径）
                    sn_ppp_path = "/usr/bin/sn-ppp"  # 请替换为实际路径
                    bstools.run_command_with_capture_output([sn_ppp_path])  # 执行但不获取结果
                    
                    # 第二步：执行 smallnode_control -f 并展示结果
                    exec_result.set_text((ATTR_WARN, "Checking network status..."))  # 可选：新增网络检测提示
                    wm.refresh()
                    
                    # 执行smallnode_control（替换为实际绝对路径）
                    smallnode_path = "/usr/local/bin/smallnode_control"  # 请替换为实际路径
                    stdout_small, stderr_small = bstools.run_command_with_capture_output([smallnode_path, "-f"])
                    
                    # 展示smallnode_control的执行结果
                    if stderr_small:
                        small_result = "{}:\n{}".format(str(PROMPT_SMALLNODE_EXECUTE_RESULT), stderr_small)
                        exec_result.set_text((ATTR_ERROR, small_result))
                    else:
                        small_result = "{}:\n{}".format(str(PROMPT_SMALLNODE_EXECUTE_RESULT), stdout_small)
                        exec_result.set_text((ATTR_INFO, small_result))
                    
                except Exception as e:
                    # 异常处理
                    error_msg = "Network configuration failed: {}".format(str(e))
                    exec_result.set_text((ATTR_ERROR, error_msg))
                finally:
                    pppoe_executing = False
                    wm.refresh()

            # 启动线程执行命令
            thread = threading.Thread(target=execute_commands)
            thread.start()
            
        except Exception as e:
            response.set_text((ATTR_ERROR, "Error: {}".format(str(e))))
            pppoe_executing = False
            wm.refresh()
    
    urwid.connect_signal(button, 'click', _callback)

def register_pppoe_config_on_adapter(button, adapter):
    """进入PPPoE配置界面（新增配置自动填充功能）"""
    # 读取/etc/pppoe.conf中的配置
    pppoe_config = load_pppoe_config(adapter.name)
    
    # 创建输入框，并为输入框赋初始值（从配置文件读取）
    account = urwid.Edit("{}: ".format(PROMPT_PPPOE_ACCOUNT), pppoe_config["account"])
    password = urwid.Edit("{}: ".format(PROMPT_PPPOE_PASSWORD), pppoe_config["password"])
    vlan_id = urwid.IntEdit("VLAN_ID: ", pppoe_config["vlan_id"] if pppoe_config["vlan_id"] else "")
    bandwidth = urwid.Edit("{}: ".format(PROMPT_PPPOE_BANDWIDTH), pppoe_config["bandwidth"])
    
    # 创建按钮
    ok = control_button(str(PROMPT_OK))
    clean = control_button(str(Prompt("clean", "清空")))
    response = urwid.Text("")
    exec_result = urwid.Text("")
    
    # 清空按钮回调
    def on_clean(button):
        global pppoe_executing
        # 重置执行状态
        pppoe_executing = False
        # 清空输入框
        for i in [account, password, vlan_id, bandwidth]:
            i.set_edit_text("")
        # 清空输出
        response.set_text("")
        exec_result.set_text("")
        wm.refresh()
    
    urwid.connect_signal(clean, 'click', on_clean)
    
    # 注册OK按钮回调
    register_pppoe_ok_win(
        ok,
        adapter=adapter,
        account=account,
        password=password,
        vlan_id=vlan_id,
        bandwidth=bandwidth,
        response=response,
        exec_result=exec_result
    )
    
    # 窗口布局
    def _callback(win):
        # 检查是否为bond-slave
        data = netfunc.load_ifcfg_content(adapter.name)
        if data.get("NAME") == "bond-slave":
            body = [
                urwid.Text((ATTR_ERROR, str(PROMPT_FORBIDDEN_CHANGE_BOND_SLAVE))),
                urwid.Divider(),
                BACK,
            ]
            win.items.extend(body)
            return
        
        win.items.extend([
            urwid.Text("* {}".format(PROMPT_CONFIG_PPPOE)),
            urwid.Text("* {}: {}".format(PROMPT_NETCARD, adapter.name)),
            urwid.Text(str(PROMPT_VLAN_HINT)),
            urwid.Divider(),
            account,
            password,
            vlan_id,
            bandwidth,
            urwid.Divider(),
            response,
            urwid.Divider(),
            exec_result,
            urwid.Divider(),
            common_col(clean, ok),  # back, clean, ok, home
        ])
    
    button_new_win(button, _callback)

# -------------------- 原有代码继续 --------------------

def register_adapters_choice(button, register_func):
    # 展示网卡的界面
    def _callback(win):
        # 故障状态 或 网络不通方可继续
        if not can_run():
            body = [
                urwid.Text((ATTR_ERROR, str(PROMPT_FORBIDDEN))),
                urwid.Divider(),
                BACK,
            ]
            win.items.extend(body)
            return
        body = [
            urwid.Text(str(Prompt("* Choose Adapter", "* 选择网卡"))),
            urwid.Text("* name status speed mac "),
            urwid.Divider()
        ]
        # 网卡列表
        for _adapter in Adapters.adapters():
            if _adapter.is_special():
                continue
            _b = create_adapter_button(_adapter)  # 创建网卡按钮, 主要是按钮上的显示
            body.append(_b)  # 添加按钮到界面上
            register_func(_b.original_widget, _adapter)  # 注册按钮的回调, 即触发的动作

        body.extend([urwid.Divider(), BACK])

        win.items.extend(body)

    button_new_win(button, _callback)


def register_multi_adapters_choice(button, register_func):
    def _callback(win):
        if not can_run():
            body = [
                urwid.Text((ATTR_ERROR, str(PROMPT_FORBIDDEN))),
                urwid.Divider(),
                BACK,
            ]
            win.items.extend(body)
            return
        response = urwid.Text("")
        body = [
            urwid.Text(
                str(
                    Prompt("* Choose Adapter which you want to bond",
                           "* 选择要绑成bond的网卡"))),
            urwid.Divider(),
        ]
        adapter_options = []
        # 网卡列表
        count = 0
        for _adapter in Adapters.adapters():
            if _adapter.is_virtual():
                # 物理网卡才可绑bond
                continue
            if _adapter.speed == 10000 and count < 2:
                isSelect = True
            else:
                isSelect = False
            adapter_options.append(urwid.CheckBox(str(_adapter), state=isSelect))
            count += 1

        body.append(urwid.Pile(adapter_options))
        ok = control_button(str(PROMPT_OK))

        def on_ok(button):
            select_adapters = [
                option.label for option in adapter_options
                if option.get_state()
            ]
            response.set_text((ATTR_WARN, str(PROMOT_GEN_BOND)))
            wm.refresh()
            # 校验选择的网卡数量
            if len(select_adapters) not in [2, 3]:
                response.set_text(
                    (ATTR_ERROR,
                     "Error: {}".format(PROMPT_NETCARD_SELECT_NUM)))
                return
            # 校验网卡速率是否一致
            speeds = set()
            for adapter in select_adapters:
                s = adapter.split()
                name = s[0]
                if len(s) < 3:
                    continue
                if s[1] != "up":
                    bstools.ifup(adapter)
                    speeds.add(Adapter(name).speed)
                else:
                    speeds.add(s[2])
            if len(speeds) > 1:
                response.set_text(
                    (ATTR_ERROR,
                     "Error: {}".format(PROMPT_NETCARD_SELECT_SPEED)))
                return
            # register_func(ok, select_adapters)
            for adapter in select_adapters:
                name = adapter.split()[0]
                netfunc.ifcfg_bond_slave(name, "bond0")
                bstools.ifup(name)
            netfunc.ifcfg_bond_master("bond0")
            bstools.ifup("bond0")
            response.set_text((ATTR_INFO, "config bond done"))

        urwid.connect_signal(ok, 'click', on_ok)

        body.extend([
            urwid.Divider(),
            response,
            urwid.Divider(),
            common_col(ok),
        ])
        win.items.extend(body)

    button_new_win(button, _callback)


def register_dns_setting(button):
    """dns配置

    Args:
        button (_type_): _description_

    """
    def _callback(win):
        if not can_run():
            body = [
                urwid.Text((ATTR_ERROR, str(PROMPT_FORBIDDEN))),
                urwid.Divider(),
                BACK,
            ]
            win.items.extend(body)
            return
        body = [
            urwid.Text(str(Prompt("* Config dns server", "* 配置dns服务器"))),
            urwid.Text(
                str(
                    Prompt(
                        "* NOTE: the libc resolver may not support more than 3 nameservers",
                        "* 提示: 超出3个的nameserver可能不生效"))),
            urwid.Divider()
        ]
        nameservers = netfunc.load_resolv()
        total = min(max(3, len(nameservers)), 5)
        edit_nameservers = []
        for i in range(total):
            if i < len(nameservers):
                _t = urwid.Edit("nameserver{}: ".format(i + 1), nameservers[i])
            else:
                _t = urwid.Edit("nameserver{}: ".format(i + 1))
            edit_nameservers.append(_t)

        ok = control_button(str(PROMPT_OK))
        response = urwid.Text("")
        dig_result = urwid.Text("")

        register_dns_ok_win(ok,
                            edit_nameservers,
                            response=response,
                            dig_result=dig_result)
        body.extend(edit_nameservers)

        body.extend([
            urwid.Divider(),
            response,
            urwid.Divider(),
            dig_result,
            urwid.Divider(),
            common_col(ok),
        ])

        win.items.extend(body)

    button_new_win(button, _callback)


class CommandWin:
    """常用的命令窗口布局
    * 标题
    * 空行
    * 命令输出展示
    * 空行
    * 后退按钮
    """
    def __init__(self):
        self.title = urwid.Text("")
        self.body = urwid.Text("")

    @property
    def win(self):
        return [self.title, urwid.Divider(), self.body, urwid.Divider(), BACK]


def register_ip_link_show(button):
    """用于显示ip link show命令信息
    @param: button: 进入此窗口的按钮
    @param: wm: 窗口管理
    """
    def _callback(win):
        cw = CommandWin()
        cw.title.set_text("* ip -br link show")
        cw.body.set_text(bstools.ip_link_show())
        win.items.extend(cw.win)

    button_new_win(button, _callback)


def register_ip_address_show(button):
    """用于显示ip地址信息
    @param: button: 触发展示此窗口的按钮
    """
    def _callback(win):
        cw = CommandWin()
        cw.title.set_text("* ip -br -4 address show")
        cw.body.set_text(bstools.ip_address_show())
        win.items.extend(cw.win)

    button_new_win(button, _callback)


def register_ip_route_show(button):
    def _callback(win):
        cw = CommandWin()
        cw.title.set_text("* ip route show")
        cw.body.set_text(bstools.ip_route_show())
        win.items.extend(cw.win)

    button_new_win(button, _callback)  # 注册回调, 即显示此win


def register_ping_test(button):
    def _callback(win):
        hint = urwid.Text(str(PROMPT_PING_HINT))
        input_addr = urwid.Edit("ping: ", "8.8.8.8")
        ok = control_button(str(PROMPT_OK))
        output = urwid.Text("")

        def on_ok(button):
            addr = input_addr.get_edit_text().decode('utf-8')
            if not bstools.netfunc.chk_addr(addr):
                output.set_text(
                    (ATTR_ERROR, "Error: {}".format(PROMPT_INVALID_ADDR)))
                return
            output.set_text((ATTR_WARN, str(PROMOT_PINGING)))
            wm.refresh()
            cmd = ["ping", "-c", "4", "-i", "0.1"]
            if ':' in addr:
                cmd.append("-6")
            cmd.append(addr)
            stdout, stderr = bstools.run_command_with_capture_output(cmd)
            if stderr:
                output.set_text((ATTR_ERROR, stderr))
            else:
                output.set_text(stdout)

        urwid.connect_signal(ok, 'click', on_ok)
        win.items.extend([
            hint,
            urwid.Divider(),
            input_addr,
            urwid.Divider(),
            output,
            urwid.Divider(),
            common_col(ok),
        ])

    button_new_win(button, _callback)  # 注册回调, 即显示此win


def register_network_on_top(button):
    """network按钮按下后的展示
    @param: button: 首页的Network按钮
    """
    def _callback(win):
        # 用于展示的元素
        body = [
            option_button(PROMPT_CONFIG_IP),
            option_button(PROMPT_CONFIG_DHCP),
            option_button(PROMPT_CONFIG_BOND),
            option_button(PROMPT_CONFIG_PPPOE),  # 新增PPPoE选项
            option_button(PROMOT_DNS_SETTING),
            option_button(PROMOT_NETCARD_SHOW),
            option_button(PROMOT_IPADDR_SHOW),
            option_button(PROMOT_IP_ROUTE_SHOW),
            option_button(PROMOT_PING),
            urwid.Divider(), BACK
        ]
        win.items.extend(body)

        # 对应的按钮动作
        register_adapters_choice(
            body[0].original_widget,
            register_static_ip_config_on_adapter)  # 用于选择网卡并配置静态ip
        register_adapters_choice(body[1].original_widget,
                                 register_dhcp_config_on_adapter)
        register_multi_adapters_choice(body[2].original_widget,
                                       register_bind_config_on_adapter)
        # 新增PPPoE按钮注册
        register_adapters_choice(body[3].original_widget,
                                 register_pppoe_config_on_adapter)
        register_dns_setting(body[4].original_widget)
        register_ip_link_show(body[5].original_widget)  # 以下都是用于展示对应命令
        register_ip_address_show(body[6].original_widget)
        register_ip_route_show(body[7].original_widget)
        register_ping_test(body[8].original_widget)

    button_new_win(button, _callback)


if __name__ == '__main__':
    top = CommonWin()
    network = option_button(PROMOT_NETWORK_SETTING)
    top.items.extend([
                      network,
                      urwid.Divider(),
                      urwid.Text("SN: {}".format(bstools.sn_show())),
                      ])

    # wm = WinManager(urwid.Filler(top.win, 'top'))
    Win.init(top=top.win)
    wm = Win.get()
    # wm = WinManager(top.win)
    register_network_on_top(network.original_widget)

    wm.run()
