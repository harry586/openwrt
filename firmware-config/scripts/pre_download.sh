#!/bin/bash
# pre_download.sh - 预下载常见依赖包（修复版）

DOWNLOAD_DIR="dl"
mkdir -p "$DOWNLOAD_DIR"

echo "=== 开始预下载常见依赖包 ==="

# 删除无效的lua-rsa下载，使用正确的包名
COMMON_PACKAGES=(
    "https://github.com/jow-/csstidy-cpp/archive/707feaec556c40c999514a598b1a1ea5b50826c6.tar.gz"
    "https://downloads.openwrt.org/releases/21.02.7/packages/x86_64/base/Packages.gz"
)

echo "下载基础依赖包..."
for url in "${COMMON_PACKAGES[@]}"; do
    filename=$(basename "$url")
    echo "下载: $filename"
    wget --tries=3 --timeout=30 --no-check-certificate -O "$DOWNLOAD_DIR/$filename.tmp" "$url" && \
        mv "$DOWNLOAD_DIR/$filename.tmp" "$DOWNLOAD_DIR/$filename" && \
        echo "✅ 下载成功: $filename" || \
        echo "⚠️ 下载失败: $filename (可能不影响构建)"
done

echo "=== 预下载完成 ==="
ls -la "$DOWNLOAD_DIR" | head -10
