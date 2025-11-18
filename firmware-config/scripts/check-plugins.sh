#!/bin/bash
# check-plugins.sh - 检查插件在feeds中的可用性

set -e

BUILD_DIR="${1:-.}"
cd "$BUILD_DIR"

echo "=== 开始检查插件在feeds中的可用性 ==="

# 更新feeds
echo "更新feeds..."
./scripts/feeds update -a > /dev/null 2>&1

# 读取normal-new.config文件，提取CONFIG_PACKAGE_*=y的包
CONFIG_FILE="config-templates/normal-new.config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 提取所有启用的包（CONFIG_PACKAGE_*=y）
PACKAGES=$(grep "^CONFIG_PACKAGE_" "$CONFIG_FILE" | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//')

echo "在 $CONFIG_FILE 中启用的包数量: $(echo "$PACKAGES" | wc -l)"

# 检查每个包是否在feeds中
MISSING_PACKAGES=()
AVAILABLE_PACKAGES=()

for pkg in $PACKAGES; do
    # 检查包是否在feeds中
    if ./scripts/feeds list | grep -q "^$pkg"; then
        AVAILABLE_PACKAGES+=("$pkg")
        echo "✅ $pkg"
    else
        MISSING_PACKAGES+=("$pkg")
        echo "❌ $pkg"
    fi
done

echo ""
echo "=== 检查结果 ==="
echo "可用的包数量: ${#AVAILABLE_PACKAGES[@]}"
echo "缺失的包数量: ${#MISSING_PACKAGES[@]}"

if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    echo "缺失的包:"
    for pkg in "${MISSING_PACKAGES[@]}"; do
        echo "  $pkg"
    done
    # 退出状态为1表示有缺失的包
    exit 1
else
    echo "所有包都在feeds中可用。"
    exit 0
fi
