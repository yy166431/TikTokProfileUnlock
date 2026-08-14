#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import json
import re

with open('tiktok_logs.json', 'r', encoding='utf-8') as f:
    for line in f:
        try:
            log = json.loads(line.strip())
            if 'message' in log and 'nickname' in log['message']:
                msg = log['message']

                # 提取关键用户字段
                patterns = {
                    'nickname': r'"nickname":"([^"]*)"',
                    'sec_uid': r'"sec_uid":"([^"]*)"',
                    'unique_id': r'"unique_id":"([^"]*)"',
                    'follower_count': r'"follower_count":(\d+)',
                    'following_count': r'"following_count":(\d+)',
                    'aweme_count': r'"aweme_count":(\d+)',
                    'total_favorited': r'"total_favorited":"?(\d+)"?',
                    'signature': r'"signature":"([^"]*)"',
                    'region': r'"region":"([^"]*)"',
                    'uid': r'"uid":"([^"]*)"'
                }

                profile = {}
                for key, pattern in patterns.items():
                    match = re.search(pattern, msg)
                    if match:
                        profile[key] = match.group(1)

                if profile.get('nickname'):
                    print(f"\n{'='*60}")
                    print(f"昵称: {profile.get('nickname', 'N/A')}")
                    print(f"UID: {profile.get('uid', 'N/A')}")
                    print(f"SecUID: {profile.get('sec_uid', 'N/A')}")
                    print(f"UniqueID: {profile.get('unique_id', 'N/A')}")
                    print(f"粉丝数: {profile.get('follower_count', 'N/A')}")
                    print(f"关注数: {profile.get('following_count', 'N/A')}")
                    print(f"作品数: {profile.get('aweme_count', 'N/A')}")
                    print(f"获赞数: {profile.get('total_favorited', 'N/A')}")
                    print(f"地区: {profile.get('region', 'N/A')}")
                    print(f"签名: {profile.get('signature', 'N/A')}")
                    print(f"时间: {log.get('received_at', 'N/A')}")
                    print(f"{'='*60}")
        except:
            continue
