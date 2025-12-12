#!/bin/bash
# OpenWrt编译智能修复脚本 v3.3
# 最后更新: 2024-01-16

set -e

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 日志函数 ==========
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "========================================"
echo "🔧 OpenWrt构建修复脚本"
echo "========================================"

# 创建必要目录
log_info "创建必要目录..."
mkdir -p firmware-config/scripts
mkdir -p firmware-config/Toolchain
mkdir -p firmware-config/config-backup
mkdir -p firmware-config/custom-files
mkdir -p .github/workflows
mkdir -p scripts

# 检查工作流文件
if [ -f ".github/workflows/firmware-build.yml" ]; then
    log_success "工作流文件已存在"
else
    log_info "创建工作流文件..."
    cp firmware-build.yml .github/workflows/
fi

# 检查主脚本
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    log_success "主脚本已存在"
else
    log_info "复制主脚本..."
    if [ -f "build_firmware_main.sh" ]; then
        cp build_firmware_main.sh firmware-config/scripts/
        chmod +x firmware-config/scripts/build_firmware_main.sh
    fi
fi

# 检查修复脚本自身
if [ ! -f "firmware-config/scripts/fix-build.sh" ]; then
    log_info "复制修复脚本..."
    cp "$0" firmware-config/scripts/fix-build.sh
    chmod +x firmware-config/scripts/fix-build.sh
fi

# 修复权限
log_info "修复脚本权限..."
find . -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true

log_success "修复完成！"
echo "========================================"
