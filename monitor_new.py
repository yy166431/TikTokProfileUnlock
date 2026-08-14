#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import time
import re

# 记录已经处理的行数
try:
    with open('tiktok_logs.json', 'r', encoding='utf-8') as f:
        processed = sum(1 for _ in f)
except:
    processed = 0

print(f"[*] 已处理 {processed} 行，开始监控新日志...")
print(f"[*] 请在 TikTok 中进入别人的主页！\n")

while True:
    try:
        with open('tiktok_logs.json', 'r', encoding='utf-8') as f:
            lines = f.readlines()

        if len(lines) > processed:
            # 处理新行
            for line in lines[processed:]:
                try:
                    if 'nickname' in line:
                        # 提取昵称
                        match = re.search(r'"nickname":"([^"]+)"', line)
                        if match:
                            nickname = match.group(1)

                            print(f"\n{'='*60}")
                            print(f"发现新用户: {nickname}")

                            # 提取其他字段
                            fields = {
                                'follower_count': r'"follower_count":(\d+)',
                                'following_count': r'"following_count":(\d+)',
                                'aweme_count': r'"aweme_count":(\d+)',
                                'total_favorited': r'"total_favorited":"?(\d+)"?',
                                'sec_uid': r'"sec_uid":"([^"]*)"',
                                'unique_id': r'"unique_id":"([^"]*)"',
                                'uid': r'"uid":"([^"]*)"',
                                'signature': r'"signature":"([^"]*)"',
                                'region': r'"region":"([^"]*)"'
                            }

                            for key, pattern in fields.items():
                                m = re.search(pattern, line)
                                if m:
                                    print(f"{key}: {m.group(1)}")

                            print(f"{'='*60}\n")
                except:
                    pass

            processed = len(lines)

    except Exception as e:
        print(f"[!] 错误: {e}")

    time.sleep(2)
