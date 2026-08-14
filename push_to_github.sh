#!/bin/bash

# 检查是否已有 remote
if git remote | grep -q origin; then
    echo "已存在 origin，移除旧的..."
    git remote remove origin
fi

# 添加 GitHub remote
echo "添加 GitHub remote..."
git remote add origin https://github.com/yy166431/TikTokCapture.git

# 推送
echo "推送到 GitHub..."
git branch -M main
git push -u origin main --force

echo "✓ 推送完成！"
echo "✓ GitHub Actions 将自动编译"
echo "✓ 查看进度: https://github.com/yy166431/TikTokCapture/actions"
