#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TikTok插件日志接收服务器
监听端口: 8899
"""

from flask import Flask, request, jsonify
from datetime import datetime
import json

app = Flask(__name__)

# 日志存储
logs = []

@app.route('/log', methods=['POST'])
def receive_log():
    """接收插件日志"""
    try:
        data = request.get_json()

        # 添加接收时间
        data['received_at'] = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

        logs.append(data)

        # 打印到控制台
        print(f"\n[{data['received_at']}] 收到日志:")
        print(f"  设备: {data.get('device', 'unknown')}")
        print(f"  iOS: {data.get('ios_version', 'unknown')}")
        print(f"  类型: {data.get('type', 'unknown')}")
        print(f"  消息: {data.get('message', '')}")

        # 保存到文件
        with open('tiktok_logs.json', 'a', encoding='utf-8') as f:
            f.write(json.dumps(data, ensure_ascii=False) + '\n')

        return jsonify({'status': 'ok'}), 200

    except Exception as e:
        print(f"错误: {e}")
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/logs', methods=['GET'])
def get_logs():
    """查看所有日志"""
    return jsonify({
        'total': len(logs),
        'logs': logs[-100:]  # 最近100条
    })

@app.route('/', methods=['GET'])
def index():
    """首页"""
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title>TikTok插件日志</title>
        <style>
            body {{ font-family: monospace; padding: 20px; background: #1e1e1e; color: #d4d4d4; }}
            .log {{ background: #2d2d2d; padding: 10px; margin: 10px 0; border-left: 3px solid #007acc; }}
            .error {{ border-left-color: #f44336; }}
            .warning {{ border-left-color: #ff9800; }}
            .info {{ border-left-color: #4caf50; }}
            h1 {{ color: #569cd6; }}
            .time {{ color: #4ec9b0; }}
            .device {{ color: #ce9178; }}
        </style>
        <script>
            function refresh() {{
                fetch('/logs')
                    .then(r => r.json())
                    .then(data => {{
                        let html = '<h2>共 ' + data.total + ' 条日志</h2>';
                        data.logs.reverse().forEach(log => {{
                            let cls = log.type || 'info';
                            html += '<div class="log ' + cls + '">';
                            html += '<div class="time">' + log.received_at + '</div>';
                            html += '<div class="device">设备: ' + (log.device || 'unknown') + ' iOS ' + (log.ios_version || '?') + '</div>';
                            html += '<div>' + (log.message || '') + '</div>';
                            html += '</div>';
                        }});
                        document.getElementById('logs').innerHTML = html;
                    }});
            }}
            setInterval(refresh, 2000);
            refresh();
        </script>
    </head>
    <body>
        <h1>TikTok插件实时日志</h1>
        <div id="logs">加载中...</div>
    </body>
    </html>
    """
    return html

if __name__ == '__main__':
    print("="*50)
    print("TikTok插件日志服务器启动")
    print("监听端口: 8899")
    print("="*50)
    app.run(host='0.0.0.0', port=8899, debug=False)
