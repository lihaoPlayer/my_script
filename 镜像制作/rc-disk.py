#!/bin/python
# coding: utf-8
# 用于选择系统盘

import os
import glob

import urwid


class Disks:
    __disks = []

    class Disk:
        def __init__(self, name):
            self.name = name

        @property
        def sys(self):
            return "/sys/block/{}".format(self.name)

        @property
        def dev(self):
            return "/dev/{}".format(self.name)

        @property
        def size(self):
            fp = open(self.dev)
            fp.seek(0, 2)
            return int(fp.tell())

        def is_removable(self):
            path = "{}/removable".format(self.sys)
            txt = open(path).read()
            return txt.strip() == "1"

        def is_virtual(self):
            path = "/sys/devices/virtual/block/{}".format(self.name)
            return os.path.exists(path)

        def __str__(self):
            return self.dev

        def __int__(self):
            return self.size

        def __repr__(self):
            return "<Disk name: {} size: {}>".format(self.dev, self.size)

    @classmethod
    def initialize(cls):
        for block in glob.glob("/sys/block/*"):
            name = os.path.basename(block)
            cls.__disks.append(cls.Disk(name))

    @classmethod
    def disks(cls):
        for d in cls.__disks:
            yield(d)

Disks.initialize()


class Partition:
    def __init__(self, disk):
        self.disk = disk
        self.passphrase = "Bsy@2018"
        self.grub2_passwd = "grub.pbkdf2.sha512.10000.4F08CD6161C599DCA3E6A0DB86B0DD2C9F82DEE65794C9FCD58954DAE9ED7DD0C52CEBE73DF1A6C8E226F3299C4BBD533E4ED7B601FF62AF5177A12AC362724B.8A8FD4939E56AC7A5ADB46E45F71AAECA6BF1816D8F8BAC171FB195FA6EBCD10CD1ADC7E9BB6A9B0886A3D65CB210FE7F948356D4DF2F78D60E9C5F64AD2ECF1"

    def config(self):
        disk = self.disk

        lines = []
        lines.append("reqpart")
        lines.append("zerombr")
        lines.append("ignoredisk --only-use={}".format(disk))
        lines.append("clearpart --all --initlabel --drives={}".format(disk))
        lines.append("bootloader --append=\"crashkernel=auto rd.shell=0 fsck.mode=force fsck.repair=yes loglevel=3 systemd.show_status=error net.ifnames=0 biosdevname=0\" --location=mbr --boot-drive={} --iscrypted --password={}".format(disk, self.grub2_passwd))
        lines.append("part /boot --fstype ext4 --ondisk={} --size=1000".format(disk))
        lines.append("part /data1 --fstype ext4 --ondisk={} --size=10240".format(disk))
        lines.append("part / --fstype ext4 --ondisk={} --size=1000 --grow --encrypted --passphrase=Bsy@2018".format(disk))

        return "\n".join(lines)

    def write(self, f, s='w'):
        with open(f, s) as fp:
            fp.write(self.config())
            fp.write("\n")

    def append(self, f):
        self.write(f, 'a')        

class DiskButton:
    def __init__(self, disk, callback):
        self.disk = disk
        self.callback = callback

    def button(self):
        return urwid.Button( 
            str(self), 
            on_press=self.callback,
            user_data=self.disk
        )

    def __str__(self):
        return "{}    {}G".format(str(self.disk), self.disk.size / 1024.0 / 1024 / 1024)


class DisksChoices:
    """用于选择硬盘的页面"""

    disks = [
        d for d in Disks.disks()
            if not d.is_virtual()
            and not d.is_removable()
            and d.size > 100 * 1024 * 1024 * 1024
    ]
    title = u"System Disk:"
    title = u"* {} ...".format("Select System Disk(240G+)")

    def __init__(self):
        self.response = [urwid.Text(self.title), urwid.Divider()]
        self.body = []
        for d in self.disks:
            button = DiskButton(d, self.click)
            self.body.append(button)

    def create(self):
        body = [urwid.AttrMap(d.button(), None, focus_map="reversed") for d in self.body]
        return urwid.Filler(urwid.Pile(self.response + body))


    def click(self, button, data):
        p = Partition(data)
        p.write("/tmp/other.ks")
        raise urwid.ExitMainLoop


main = urwid.Padding(DisksChoices().create(), left=2, right=2)
urwid.MainLoop(main, palette=[('reversed', 'standout', '')]).run()
