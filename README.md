# TikTokCapture

TikTok profile/self API 抓包 dylib，巨魔注入器注入使用。

## 功能

- ✅ 抓取 profile/self 完整 URL（包含所有参数）
- ✅ 抓取完整响应 JSON（author_stats、头像URL等）
- ✅ 内置 HTTP 服务器（端口 9999）实时查看
- ✅ 远程日志上报（159.75.14.193:8899）

## 安装

### 方法 1: GitHub Release（推荐）

1. 下载最新 release 的 `TikTokCapture.zip`
2. 解压得到 `TikTokCapture.dylib` 和 `TikTokCapture.plist`
3. 用**巨魔注入器（TrollStore Injector）**注入到 TikTok：
   - 打开巨魔注入器
   - 选择 TikTok
   - 添加 dylib 和 plist
   - 重启 TikTok

## 使用

1. 注入 dylib 后启动 TikTok
2. 浏览器访问 `http://localhost:9999` 查看抓包数据
3. 在 TikTok 内刷新个人主页，数据自动捕获

## API

- `GET http://localhost:9999/` - Web 界面（每5秒自动刷新）
- `GET http://localhost:9999/api/data` - JSON 数据接口

## 数据结构

```json
{
  "id": 1,
  "timestamp": 1723622400,
  "type": "response",
  "url": "https://api-va.tiktokv.com/tiktok/user/profile/self/v1?...",
  "response": "{...完整JSON...}"
}
```

## Hook 点

1. `NSJSONSerialization +JSONObjectWithData:` - 捕获所有 JSON 响应
2. `TTHttpResponseChromium -initWithURL:` - 捕获请求 URL

## 兼容性

- iOS 14.0+
- TikTok 46.3.0 (测试版本)
- 需要巨魔注入器（TrollStore Injector）

## 服务器

远程日志服务器: http://159.75.14.193:8899/log

## 依赖

- GCDWebServer (HTTP 服务器)
- Substrate (hook 框架)

## License

MIT
