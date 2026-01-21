#!/bin/python
# coding: utf-8
# 用于客户选择网络模式(dhcp/static/pppoe) - Python2兼容版（PPPOE仅选择不操作）

import os
import glob

import urwid

KS = "/tmp/other.ks"
PPPOE_CONF_FILE = "/etc/pppoe.conf"  # 保留路径（无需实际使用）

def dhcp_ip_config(adapter):
    """dhcp配置，需要传入device，即哪个网卡"""
    return "network --bootproto=dhcp --device={device} --onboot=on --ipv6=auto\n".format(device=adapter.name)

def static_ip_config(adapter, ip, netmask, gateway, vlanid=None):
    """生成ks的静态ip配置"""
    config = ' '.join([
        "network --bootproto=static --noipv6 --nodns --onboot=on",
        "--gateway={gateway}",
        "--ip={ip}",
        "--netmask={netmask}",
        "--device={device}"
    ]).format(
        gateway=gateway,
        ip=ip,
        netmask=netmask,
        device=adapter.name,
    )
    if vlanid and vlanid.isdigit() and int(vlanid) > 0:
        config = "{} --vlanid={}".format(config, vlanid)

    return config + "\n"

def write_to_file(content):
    with open(KS, 'a') as fp:
        fp.write(content)

def create_dhcp(*argv):
    content = dhcp_ip_config(*argv)
    write_to_file(content)
    
def create_static(*argv):
    content = static_ip_config(*argv)
    write_to_file(content)

# 移除PPPOE配置写入逻辑（无需执行任何操作）
# def create_pppoe(adapter, account, password, vlan_id, bandwidth):
#     无需实现

def read_text(f):
    with open(f) as fp:
        return fp.read()
        
def read_bypass_failure(f):
    try:
        return read_text(f).strip()
    except:
        pass
    
    return None

class Adapters:

    __adapters = []

    class Adapter:
        """主要为了查找物理网卡"""
        def __init__(self, name):
            self.name = name
            self._path = "/sys/class/net/{}".format(name)

        def get_file(self, name):
            return "{}/{}".format(self._path, name)

        @property
        def address(self):
            return read_bypass_failure(self.get_file("address"))
            
        @property
        def speed(self):
            speed = read_bypass_failure(self.get_file("speed"))
            if speed:
                return int(speed)

            return speed
            
        @property
        def status(self):
            return read_bypass_failure(self.get_file("operstate"))
            
        def is_virtual(self):
            """我们只需要物理网卡"""
            f = "/sys/devices/virtual/net/{}".format(self.name)
            return os.path.exists(f)


    @classmethod
    def initialize(cls):
        for path in glob.glob("/sys/class/net/*"):
            if os.path.isfile(path):
                continue

            adapter = cls.Adapter(os.path.basename(path))
            cls.__adapters.append(adapter)

    @classmethod
    def adapters(cls):
        return cls.__adapters

def space_pad(name, width):
    l = len(name)
    delta = width - l
    if delta > 0:
        return "{}{}".format(name, " "* delta)
    return name
    
def format_adapter(adapter):
    return "{}{}{}{}".format(
        space_pad(adapter.name, 15),
        space_pad(adapter.status, 7),
        space_pad(str(adapter.speed), 8),
        adapter.address
    )


Adapters.initialize()

def attrmap(button):
    """用于给button设置长条属性"""
    return urwid.AttrMap(button, None, focus_map="reversed")

class ButtonOnType:
    """用于DHCP/Static/PPPOE的按钮"""
    def __init__(self, title, main, adapter, callback):
        self.title = title
        self.main = main
        self.adapter = adapter
        self.callback = callback
        self.button = urwid.Button(title, on_press=self.click)

    @property
    def attr(self):
        return attrmap(self.button)

    def click(self, button):
        self.callback(button, {
            "title": self.title,
            "main": self.main,
            "adapter": self.adapter,
        })

def callback_button_DHCP(button, context):
    """用于生成dhcp的配置文件"""
    create_dhcp(context["adapter"]) # 创建配置文件
    context["main"].stop()  # 停止tui

def callback_button_Static(button, context):
    """用于进入配置静态ip的页面"""
    input = StaticInput(context["main"], context["adapter"], create_static)
    input.enter()

def callback_button_PPPOE(button, context):
    """PPPOE选择后直接结束程序，不执行任何操作"""
    context["main"].stop()  # 仅停止TUI界面，无其他操作

def callback_button_Adapter(button, context):
    """在网卡上按按钮后，需要进入dhcp/static/pppoe选择界面"""
    dhcp = ButtonOnType("DHCP", context["main"], context["adapter"], callback_button_DHCP)
    static = ButtonOnType("Static", context["main"], context["adapter"], callback_button_Static)
    pppoe = ButtonOnType("PPPOE", context["main"], context["adapter"], callback_button_PPPOE)  # 保留PPPOE按钮

    body = []
    body.append(urwid.Text("* Type Of Configuration ..."))
    body.append(urwid.Divider())
    body.extend([dhcp.attr, static.attr, pppoe.attr])  # 显示PPPOE按钮
    context["main"].renew(body)


class ButtonAdaptes:
    
    adapters = [a for a in Adapters.adapters() if not a.is_virtual()]

    def __init__(self, main):
        self.main = main
        self.buttons = []
        for adapter in sorted(self.adapters, key=lambda x:x.name):
            title = format_adapter(adapter)
            self.buttons.append(ButtonOnType(title, self.main, adapter, callback_button_Adapter))

    def screen(self):
        """选择网卡的界面"""
        title = urwid.Text("* Select Adapter ...")
        body = [title, urwid.Divider()]

        # 第三行为提示
        _s = " "
        _t = "  name{}status{}speed{}mac".format(_s * 11, _s, _s * 3)
        _b = urwid.Text(("Bold", _t))
        body.append(_b)

        body.extend(b.attr for b in self.buttons)
        return body

class StaticInput:
    """用于用户填入静态ip等信息"""
    
    title = "* Config IP/NETMASK/GATEWAY ..."
    header = "> vlanid is optional ..."
    
    def __init__(self, main, device, callback):
        self.main = main
        self.device = device
        self.callback = callback
        self.ip = urwid.Edit("IP     : ")
        self.netmask = urwid.Edit("NETMASK: ", "255.255.255.0")
        self.gateway = urwid.Edit("GATEWAY: ")
        self.vlanid = urwid.Edit("VLANID : ")
        
    def enter(self):
        self.main.renew(self.menu())
    
    def menu(self):
        """用于显示菜单的各元素"""
        body = []
        body.append(urwid.Text(self.title))
        body.append(urwid.Divider())
        body.extend([self.ip, self.netmask, self.gateway, self.vlanid])
        body.append(urwid.Divider())
        
        ok = attrmap(urwid.Button(u'OK', on_press=self.click))
        body.append(ok)
        return body


    def click(self, button):
        """按OK后，生成配置并退出，这里应该作校验"""
        self.callback(
            self.device,
            self.ip.edit_text,
            self.netmask.edit_text,
            self.gateway.edit_text,
            self.vlanid.edit_text or None
        )
        self.main.stop()

# 移除PPPoEInput类（无需输入界面）
# class PPPoEInput:
#     无需实现

class Main:
    def __init__(self):
        self.top = None

    def renew(self, eles):
        # self.top.original_widget = urwid.ListBox(urwid.SimpleFocusListWalker(eles))
        self.top.original_widget = urwid.Padding(urwid.Filler(urwid.Pile(eles)), left=2, right=2)

    def stop(self):
        """用于结束任务"""
        raise urwid.ExitMainLoop

    def start(self, pile, palette=None):
        self.top = urwid.Padding(pile)
        palette = palette or [('reversed', 'standout', ''), ('Bold', 'bold', '')]
        urwid.MainLoop(self.top, palette=palette).run()


if __name__ == "__main__":
    main = Main()
    adapters = ButtonAdaptes(main)
    body = adapters.screen()
    # l = urwid.ListBox(urwid.SimpleFocusListWalker(body))
    l = urwid.Padding(urwid.Filler(urwid.Pile(body)), left=2, right=2)

    main.start(l)
    # main.start(urwid.Pile(body))
