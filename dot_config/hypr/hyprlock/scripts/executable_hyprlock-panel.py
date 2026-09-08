#!/usr/bin/env python3
"""
hyprlock-panel.py -- Hyprlock 锁屏伴侣面板
底部交互面板：时间/日期 + 媒体控制和当前曲目信息。
自动适配 hyprlock/colors.conf 配色。
依赖: python-gobject, gtk-layer-shell, playerctl
"""
import argparse, os, subprocess, sys
from datetime import datetime
import gi
gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gtk, Gdk, GtkLayerShell, Pango

C = os.path.expanduser("~/.config/hypr/hyprlock/colors.conf")
FONT = chr(34) + "Google Sans Flex Medium, Noto Sans, sans-serif" + chr(34)
CO = {"text": "#d8e2ff", "bg": "rgba(0,10,30,0.55)", "accent": "#8e9099"}

def pc():
    if not os.path.isfile(C): return
    try:
        for L in open(C):
            L = L.strip()
            if L.startswith("$text_color"):
                CO["text"] = L.split("=",1)[1].strip().strip(chr(34)+chr(39))
            elif L.startswith("$entry_border_color"):
                CO["accent"] = L.split("=",1)[1].strip().strip(chr(34)+chr(39))
    except: pass

def rgba(s):
    c = Gdk.RGBA()
    return c if c.parse(s) else Gdk.RGBA(0.85,0.89,1,1)

def meta():
    try:
        r = subprocess.check_output(["playerctl","metadata","--format",
            "{{playerName}}||{{title}}||{{artist}}||{{status}}"],
            stderr=subprocess.DEVNULL, timeout=1).decode().strip()
        if "||" not in r: return None
        p = r.split("||",3)
        return {"player":p[0],"title":p[1],"artist":p[2],"status":p[3]}
    except: return None

def pctl(c):
    try: subprocess.check_call(["playerctl",c], stderr=subprocess.DEVNULL, timeout=1)
    except: pass

class Panel:
    def __init__(self, pid=None):
        self.pid = pid; self.mo = None
        pc()
        self.w = Gtk.Window.new(Gtk.WindowType.POPUP)
        self.w.set_title("hyprlock-panel")
        self.w.set_default_size(560,156)
        self.w.set_resizable(False)
        self.w.set_decorated(False)
        self.w.set_keep_above(True)
        self.w.set_app_paintable(True)
        GtkLayerShell.init_for_window(self.w)
        GtkLayerShell.set_layer(self.w, GtkLayerShell.Layer.OVERLAY)
        for e in [GtkLayerShell.Edge.BOTTOM, GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT]:
            GtkLayerShell.set_anchor(self.w, e, True)
        GtkLayerShell.set_margin(self.w, GtkLayerShell.Edge.BOTTOM, 36)
        GtkLayerShell.set_margin(self.w, GtkLayerShell.Edge.LEFT, 100)
        GtkLayerShell.set_margin(self.w, GtkLayerShell.Edge.RIGHT, 100)
        self._css(); self._ui()
        GLib.timeout_add_seconds(1, self._t1)
        GLib.timeout_add_seconds(2, self._t2)
        if self.pid: GLib.timeout_add(500, self._wd)
        self.w.connect("destroy", Gtk.main_quit)
        self.w.show_all()

    def _css(self):
        p = Gtk.CssProvider()
        t = rgba(CO["text"]).to_string()
        b = rgba(CO["bg"]).to_string()
        a = rgba(CO["accent"]).to_string()
        css = ".b{background:"+b+";border-radius:28px;padding:14px 28px;border:1px solid "+a+"44}"
        css += ".c{color:"+t+";font-size:38px;font-weight:bold;font-family:"+FONT+"}"
        css += ".d{color:"+a+";font-size:13px;font-family:"+FONT+"}"
        css += ".k{color:"+t+";font-size:15px;font-family:"+FONT+"}"
        css += ".ar{color:"+a+";font-size:12px;font-family:"+FONT+"}"
        css += ".mb{background:transparent;color:"+t+";border:none;border-radius:20px;padding:6px 12px;font-size:20px;min-width:40px;min-height:40px}"
        css += ".mb:hover{background:rgba(216,226,255,0.15)}"
        css += ".mb:active{background:rgba(216,226,255,0.25)}"
        css += ".pb{background:"+a+"33;border-radius:24px;padding:6px 18px}.pb:hover{background:"+a+"55}"
        css += ".s{color:"+a+";font-size:11px;font-family:"+FONT+"}"
        p.load_from_data(css.encode())
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(),p,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def _ui(self):
        o = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        o.get_style_context().add_class("b")
        r = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=16)
        r.set_halign(Gtk.Align.CENTER); r.set_valign(Gtk.Align.CENTER)
        L = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        L.set_halign(Gtk.Align.START)
        self.cl = Gtk.Label(label="00:00")
        self.cl.get_style_context().add_class("c")
        L.pack_start(self.cl,0,0,0)
        self.dl = Gtk.Label(label="")
        self.dl.get_style_context().add_class("d")
        L.pack_start(self.dl,0,0,0)
        r.pack_start(L,0,0,20)
        R = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        R.set_halign(Gtk.Align.CENTER)
        self.tl = Gtk.Label(label="没有正在播放的音乐")
        self.tl.get_style_context().add_class("k")
        self.tl.set_ellipsize(Pango.EllipsizeMode.END)
        self.tl.set_max_width_chars(38)
        R.pack_start(self.tl,0,0,0)
        self.al = Gtk.Label(label="")
        self.al.get_style_context().add_class("ar")
        self.al.set_ellipsize(Pango.EllipsizeMode.END)
        self.al.set_max_width_chars(38)
        R.pack_start(self.al,0,0,2)
        bb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        bb.set_halign(Gtk.Align.CENTER); bb.set_margin_top(4)
        self.pb = Gtk.Button(label="▶")
        self.pb.get_style_context().add_class("mb")
        self.pb.get_style_context().add_class("pb")
        self.pb.connect("clicked", lambda _: (pctl("play-pause"),GLib.timeout_add(300,self._t2)))
        bb.pack_start(self.pb,0,0,0)
        for lbl,cmd in [("⏮","previous"),("⏭","next")]:
            b = Gtk.Button(label=lbl)
            b.get_style_context().add_class("mb")
            b.connect("clicked", lambda _,c=cmd: pctl(c))
            bb.pack_start(b,0,0,0) if cmd=="previous" else bb.pack_end(b,0,0,0)
        R.pack_start(bb,0,0,0)
        r.pack_end(R,0,0,10)
        o.pack_start(r,1,1,0)
        sb = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4)
        sb.set_halign(Gtk.Align.CENTER); sb.set_margin_top(4)
        self.dt = Gtk.Label(label="○")
        self.dt.get_style_context().add_class("s")
        sb.pack_start(self.dt,0,0,0)
        st = Gtk.Label(label="锁屏中·键盘快捷键同样可用")
        st.get_style_context().add_class("s")
        sb.pack_start(st,0,0,0)
        o.pack_start(sb,0,0,0)
        self.w.add(o)

    def _t1(self):
        n = datetime.now()
        self.cl.set_text(n.strftime("%H:%M"))
        self.dl.set_text(n.strftime("%A · %m/%d · %Y"))
        return True

    def _t2(self):
        m = meta()
        if m and m.get("title"):
            self.mo = m; p = m["status"]=="Playing"
            self.tl.set_text(m["title"][:40])
            a = (m.get("artist") or "")[:40]
            self.al.set_text((a+" · "+m["player"]) if a else m["player"])
            self.pb.set_label("⏸" if p else "▶")
            self.dt.set_text("●")
            c = Gdk.RGBA(0.3,0.85,0.4,1) if p else Gdk.RGBA(0.9,0.6,0.2,1)
            self.dt.override_color(Gtk.StateFlags.NORMAL,c)
        else:
            self.tl.set_text("没有正在播放的音乐")
            self.al.set_text("打开音乐播放器开始享受")
            self.pb.set_label("▶")
            self.dt.set_text("○")
            self.dt.override_color(Gtk.StateFlags.NORMAL,Gdk.RGBA(0.5,0.5,0.5,0.6))
        return True

    def _wd(self):
        if self.pid:
            try: os.kill(self.pid,0); return True
            except: Gtk.main_quit(); return False
        return True

if __name__=="__main__":
    ap = argparse.ArgumentParser(description="hyprlock-panel")
    ap.add_argument("--watch-pid", type=int, default=None)
    a = ap.parse_args()
    Panel(pid=a.watch_pid)
    Gtk.main()
