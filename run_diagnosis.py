#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# run_diagnosis.py - 运行所有诊断脚本的主控程序

import sys
import time
import frida
import json

DEVICE = "192.168.9.102:27042"  # 修改为你的设备地址
TARGET_APP = "TikTok"  # 或 "Aweme"

def on_message(msg, data):
    """处理 Frida 消息"""
    if msg.get('type') == 'send':
        payload = msg.get('payload', {})
        msg_type = payload.get('type', 'unknown')

        if msg_type == 'profile_object':
            print("\n" + "="*60)
            print("🎯 找到 Profile 对象!")
            print("="*60)
            print(f"类名: {payload.get('className')}")
            print(f"地址: {payload.get('address')}")
            print(f"内容:\n{payload.get('content')[:1000]}")

            # 保存到文件
            with open('profile_found.json', 'w', encoding='utf-8') as f:
                json.dump(payload, f, ensure_ascii=False, indent=2)
            print("\n✅ 已保存到 profile_found.json")

        elif msg_type == 'profile_json':
            print("\n" + "="*60)
            print("🎯 JSON 解析出 Profile!")
            print("="*60)
            print(payload.get('data')[:1000])

        elif msg_type == 'profile_userdefaults':
            print("\n" + "="*60)
            print("🎯 NSUserDefaults 中找到 Profile!")
            print("="*60)
            print(f"Key: {payload.get('key')}")
            print(f"Data: {payload.get('data')[:800]}")

        else:
            print(f"[INFO] {payload}")

    elif msg.get('type') == 'error':
        print(f"[ERROR] {msg.get('description')}")

def run_script(device, pid, script_name, script_code):
    """运行单个 Frida 脚本"""
    print(f"\n{'='*60}")
    print(f"🚀 运行脚本: {script_name}")
    print(f"{'='*60}\n")

    try:
        session = device.attach(pid)
        script = session.create_script(script_code)
        script.on('message', on_message)
        script.load()

        print(f"[+] {script_name} 已加载")
        print(f"[*] 现在请操作 TikTok：进入个人主页\n")

        # 运行 60 秒
        time.sleep(60)

        session.detach()
        print(f"\n[*] {script_name} 执行完成")

    except Exception as e:
        print(f"[!] 脚本执行失败: {e}")

def main():
    print("""
╔═══════════════════════════════════════════════════════╗
║   TikTok Profile/Self 数据抓取 - 全面诊断工具        ║
╚═══════════════════════════════════════════════════════╝
    """)

    # 连接设备
    print(f"[*] 连接设备: {DEVICE}")
    try:
        dm = frida.get_device_manager()
        device = dm.add_remote_device(DEVICE)
    except Exception as e:
        print(f"[!] 设备连接失败: {e}")
        print(f"[!] 请确认设备地址正确，frida-server 正在运行")
        return

    # 查找进程
    print(f"[*] 查找进程: {TARGET_APP}")
    pid = None
    for p in device.enumerate_processes():
        if TARGET_APP in p.name or 'Aweme' in p.name:
            pid = p.pid
            print(f"[+] 找到进程: {p.name} (PID: {pid})")
            break

    if not pid:
        print(f"[!] 未找到 TikTok 进程")
        print(f"[!] 请确保 TikTok 正在运行")
        return

    # 读取脚本文件
    scripts = [
        ('enum_all_objects.js', '枚举所有对象'),
        ('diagnose_full.js', '全面诊断'),
    ]

    for script_file, desc in scripts:
        try:
            with open(script_file, 'r', encoding='utf-8') as f:
                script_code = f.read()

            print(f"\n[?] 是否运行 {desc} ({script_file})? [Y/n] ", end='', flush=True)
            choice = input().strip().lower()

            if choice in ('', 'y', 'yes'):
                run_script(device, pid, desc, script_code)
            else:
                print(f"[*] 跳过 {desc}")

        except FileNotFoundError:
            print(f"[!] 找不到脚本文件: {script_file}")
        except Exception as e:
            print(f"[!] 读取脚本失败: {e}")

    print("\n" + "="*60)
    print("✅ 诊断完成")
    print("="*60)
    print("\n检查输出和 profile_found.json 文件")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n[!] 用户中断")
        sys.exit(0)
