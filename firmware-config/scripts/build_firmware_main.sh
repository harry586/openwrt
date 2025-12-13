#!/bin/bash
# OpenWrt智能构建主脚本（构建功能版）
# 修复脚本独立存在，不包含修复逻辑

set -e

# ========== 全局配置 ==========
BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLCHAIN_DIR="$REPO_ROOT/firmware-config/Toolchain"

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ========== 日志函数 ==========
log() { echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ========== 错误处理 ==========
handle_error() {
    log_error "错误发生在: $1"
    exit 1
}

# ========== 环境设置函数 ==========

# 设置编译环境
setup_environment() {
    log_info "设置编译环境..."
    
    log_info "安装必要软件包..."
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        ccache \
        ecj \
        fastjar \
        file \
        g++ \
        gawk \
        gettext \
        git \
        java-propose-classpath \
        libelf-dev \
        libncurses5-dev \
        libncursesw5-dev \
        libssl-dev \
        python3 \
        python3-distutils \
        python3-setuptools \
        rsync \
        subversion \
        unzip \
        wget \
        xsltproc \
        zlib1g-dev
    
    log_info "启用ccache..."
    export CCACHE_DIR="$BUILD_DIR/.ccache"
    mkdir -p "$CCACHE_DIR"
    ccache -M 5G
    
    log_success "编译环境设置完成"
}

# 创建构建目录
create_build_dir() {
    log_info "创建构建目录..."
    
    # 确保/mnt目录存在并有适当权限
    if [ ! -d "/mnt" ]; then
        log_info "创建/mnt目录..."
        sudo mkdir -p /mnt
    fi
    
    # 设置/mnt目录权限（如果可能）
    sudo chmod 777 /mnt 2>/dev/null || log_warn "无法修改/mnt目录权限，将继续尝试"
    
    # 创建构建目录并设置权限
    sudo mkdir -p "$BUILD_DIR"
    sudo chmod 777 "$BUILD_DIR"
    
    log_success "构建目录: $BUILD_DIR"
    log_info "构建目录权限: $(ls -ld $BUILD_DIR)"
    
    # 检查磁盘空间
    local available_space=$(df -h "$BUILD_DIR" | tail -1 | awk '{print $4}')
    log_info "可用空间: $available_space"
}

# ========== 工具链管理 ==========

# 初始化工具链目录
init_toolchain_dir() {
    log_info "初始化工具链目录..."
    
    mkdir -p "$TOOLCHAIN_DIR"
    
    # 创建说明文件
    cat > "$TOOLCHAIN_DIR/README.md" << 'EOF'
# OpenWrt 编译工具链目录

## 说明
此目录用于存放通用且必要的工具链文件，不存储完整的平台特定工具链。

## 管理策略
1. 保留通用编译工具（如gcc、binutils等）
2. 平台特定工具链在编译时自动下载
3. 避免Git LFS配额问题

## 目录结构
- README.md - 本文件
- .gitkeep - 保持目录结构
- common/ - 通用工具链组件
- configs/ - 工具链配置

## 通用工具链内容
- 基础编译工具（ccache, gcc, binutils等）
- 常用库文件
- 交叉编译工具链框架
EOF
    
    # 创建必要目录结构
    mkdir -p "$TOOLCHAIN_DIR/common"
    mkdir -p "$TOOLCHAIN_DIR/configs"
    touch "$TOOLCHAIN_DIR/.gitkeep"
    
    log_success "工具链目录初始化完成"
}

# 检查工具链目录状态
check_toolchain_dir() {
    log_info "检查工具链目录..."
    
    if [ -d "$TOOLCHAIN_DIR" ]; then
        log_success "工具链目录存在: $TOOLCHAIN_DIR"
        
        # 显示目录内容
        echo "目录结构:"
        find "$TOOLCHAIN_DIR" -maxdepth 2 -type d | sort
        
        # 检查通用工具链
        if [ -d "$TOOLCHAIN_DIR/common" ]; then
            local common_files=$(find "$TOOLCHAIN_DIR/common" -type f 2>/dev/null | wc -l)
            log_info "通用工具链文件: $common_files 个"
        else
            log_warn "通用工具链目录不存在"
        fi
    else
        log_warn "工具链目录不存在，将自动创建"
        init_toolchain_dir
    fi
}

# 加载通用工具链
load_toolchain() {
    log_info "加载通用工具链..."
    
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    # 确保构建目录存在
    mkdir -p staging_dir
    
    # 检查是否有现有的工具链
    local existing_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
    if [ -n "$existing_toolchain" ]; then
        log_success "发现现有工具链，将复用: $existing_toolchain"
        return 0
    fi
    
    # 检查仓库中是否有通用工具链
    if [ -d "$TOOLCHAIN_DIR/common" ] && [ -n "$(ls -A "$TOOLCHAIN_DIR/common" 2>/dev/null)" ]; then
        log_info "发现通用工具链，尝试加载..."
        
        # 创建工具链目录
        local toolchain_name="toolchain-common-$(date +%s)"
        mkdir -p "staging_dir/$toolchain_name"
        
        # 复制通用工具链文件
        cp -r "$TOOLCHAIN_DIR/common/"* "staging_dir/$toolchain_name/" 2>/dev/null || true
        
        # 检查是否复制成功
        if [ -n "$(ls -A "staging_dir/$toolchain_name" 2>/dev/null)" ]; then
            log_success "通用工具链加载成功"
            log_info "工具链大小: $(du -sh "staging_dir/$toolchain_name" 2>/dev/null | cut -f1 || echo '未知')"
        else
            log_warn "通用工具链目录为空，将在编译时自动下载"
        fi
    else
        log_info "未找到通用工具链，将在编译时自动下载"
    fi
    
    # 设置工具链环境变量
    export STAGING_DIR="$BUILD_DIR/openwrt/staging_dir"
    
    log_success "工具链环境设置完成"
}

# 保存通用工具链
save_essential_toolchain() {
    log_info "保存通用工具链..."
    
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    # 只保存构建目录中存在的通用工具链
    if [ ! -d "staging_dir" ]; then
        log_warn "构建目录中没有工具链，跳过保存"
        return 0
    fi
    
    # 查找工具链目录
    local staging_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
    
    if [ -z "$staging_toolchain" ]; then
        log_warn "未找到工具链目录，跳过保存"
        return 0
    fi
    
    log_info "找到工具链: $staging_toolchain"
    
    # 确保目标目录存在
    mkdir -p "$TOOLCHAIN_DIR/common"
    
    # 只保存必要的通用文件
    local essential_files=0
    
    # 保存编译器等关键文件
    if [ -d "$staging_toolchain/bin" ]; then
        log_info "保存通用编译工具..."
        
        # 查找并保存常用的编译器工具
        local tools=("ccache" "gcc" "g++" "ld" "as" "ar" "nm" "objcopy" "objdump" "ranlib" "strip")
        for tool in "${tools[@]}"; do
            if find "$staging_toolchain/bin" -name "*$tool*" -type f -exec cp -v {} "$TOOLCHAIN_DIR/common/" \; 2>/dev/null; then
                essential_files=$((essential_files + 1))
            fi
        done
    fi
    
    # 保存配置文件
    if [ -f "$BUILD_DIR/openwrt/.config" ]; then
        cp "$BUILD_DIR/openwrt/.config" "$TOOLCHAIN_DIR/configs/build_config.txt"
        log_info "保存构建配置文件"
        essential_files=$((essential_files + 1))
    fi
    
    # 保存工具链信息
    cat > "$TOOLCHAIN_DIR/configs/toolchain_info.txt" << EOF
# 通用工具链信息
保存时间: $(date)
工具链来源: $staging_toolchain
保存文件数: $essential_files 个
目标平台: ${TARGET:-未知}/${SUBTARGET:-未知}
设备: ${DEVICE:-未知}
版本: ${SELECTED_BRANCH:-未知}

# 通用文件列表
$(find "$TOOLCHAIN_DIR/common" -type f 2>/dev/null | head -20)
EOF
    
    log_success "保存了 $essential_files 个通用工具链文件"
    log_info "通用工具链保存到: $TOOLCHAIN_DIR/common"
    
    return 0
}

# 检查工具链完整性
check_toolchain_completeness() {
    log_info "检查工具链完整性..."
    
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    # 检查构建目录中的工具链
    local toolchain_dir=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -z "$toolchain_dir" ]; then
        log_warn "构建目录中没有工具链"
        return 1
    fi
    
    # 验证工具链完整性
    if [ -d "$toolchain_dir" ]; then
        log_success "找到工具链目录: $toolchain_dir"
        
        # 检查关键目录
        local critical_dirs=("bin" "lib" "include" "usr")
        local missing_dirs=0
        
        for dir in "${critical_dirs[@]}"; do
            if [ -d "$toolchain_dir/$dir" ]; then
                log_info "✅ 关键目录存在: $dir"
            else
                log_warn "⚠️ 关键目录缺失: $dir"
                missing_dirs=$((missing_dirs + 1))
            fi
        done
        
        # 检查编译器
        if [ -d "$toolchain_dir/bin" ]; then
            local compilers=$(find "$toolchain_dir/bin" -name "*gcc*" 2>/dev/null | wc -l)
            log_info "找到 $compilers 个编译器文件"
            
            if [ $compilers -eq 0 ]; then
                log_warn "⚠️ 未找到编译器"
                return 1
            fi
        else
            log_warn "⚠️ bin目录不存在"
            return 1
        fi
        
        if [ $missing_dirs -eq 0 ]; then
            log_success "工具链完整性检查通过"
            return 0
        else
            log_warn "工具链完整性检查失败: 缺失 $missing_dirs 个关键目录"
            return 1
        fi
    else
        log_error "工具链目录不存在"
        return 1
    fi
}

# ========== OpenWrt源码管理 ==========

# 下载OpenWrt源代码
download_openwrt_source() {
    log_info "下载OpenWrt源代码..."
    
    cd "$BUILD_DIR"
    
    # 根据分支选择下载对应的OpenWrt版本
    local openwrt_url="https://github.com/openwrt/openwrt.git"
    local branch_name=""
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        branch_name="openwrt-23.05"
    elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
        branch_name="openwrt-21.02"
    else
        branch_name="master"
    fi
    
    # 检查是否已经存在OpenWrt源码
    if [ -d "$BUILD_DIR/openwrt" ] && [ -f "$BUILD_DIR/openwrt/feeds.conf.default" ]; then
        log_success "OpenWrt源码已存在，跳过下载"
        return 0
    fi
    
    # 清理旧的源码目录
    if [ -d "$BUILD_DIR/openwrt" ]; then
        log_info "清理旧的源码目录..."
        rm -rf "$BUILD_DIR/openwrt"
    fi
    
    # 确保在正确目录下载
    cd "$BUILD_DIR"
    
    # 下载OpenWrt源码
    log_info "正在下载OpenWrt源码: $branch_name"
    git clone --depth 1 --branch "$branch_name" "$openwrt_url" "openwrt"
    
    if [ ! -d "$BUILD_DIR/openwrt" ]; then
        log_error "OpenWrt源码下载失败"
        exit 1
    fi
    
    log_success "OpenWrt源码下载完成"
    log_info "源码大小: $(du -sh "$BUILD_DIR/openwrt" 2>/dev/null | cut -f1 || echo '未知')"
}

# ========== 构建环境初始化 ==========

# 初始化构建环境
initialize_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local extra_packages="${4:-}"
    
    log_info "初始化构建环境..."
    
    log_info "设备: $device_name"
    log_info "版本: $version_selection"
    log_info "配置模式: $config_mode"
    log_info "额外插件: $extra_packages"
    
    # 设置版本分支
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_BRANCH="openwrt-23.05"
    elif [ "$version_selection" = "21.02" ]; then
        SELECTED_BRANCH="openwrt-21.02"
    else
        SELECTED_BRANCH="$version_selection"
    fi
    
    # 设备到目标的映射
    case "$device_name" in
        "ac42u")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-ac42u"
            ;;
        "acrh17")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-acrh17"
            ;;
        "r3g")
            TARGET="ramips"
            SUBTARGET="mt7621"
            DEVICE="xiaomi_mi-router-3g"
            ;;
        *)
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="$device_name"
            ;;
    esac
    
    # 保存环境变量到文件
    cat > "$ENV_FILE" << EOF
# 构建环境变量
SELECTED_BRANCH="$SELECTED_BRANCH"
TARGET="$TARGET"
SUBTARGET="$SUBTARGET"
DEVICE="$DEVICE"
CONFIG_MODE="$config_mode"
EXTRA_PACKAGES="$extra_packages"
BUILD_DIR="$BUILD_DIR"
REPO_ROOT="$REPO_ROOT"
EOF
    
    # 下载OpenWrt源代码
    download_openwrt_source
    
    log_success "构建环境初始化完成"
}

# 加载环境变量
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
}

# ========== 构建分析函数 ==========

# 构建分析函数
workflow_step31_build_analysis() {
    local build_status="$1"
    
    echo "========================================"
    echo "📊 步骤31：构建分析"
    echo "========================================"
    
    echo "📅 分析时间: $(date)"
    echo "🏗️ 构建状态: $build_status"
    echo "📁 构建目录: $BUILD_DIR"
    echo ""
    
    echo "=== 系统资源状态 ==="
    df -h
    echo ""
    free -h
    echo ""
    
    echo "=== 构建目录状态 ==="
    if [ -d "$BUILD_DIR" ]; then
        echo "✅ 构建目录存在"
        echo "📊 目录大小: $(du -sh $BUILD_DIR 2>/dev/null | cut -f1 || echo '未知')"
        
        # 检查OpenWrt源码目录
        if [ -d "$BUILD_DIR/openwrt" ]; then
            echo "📁 OpenWrt源码目录存在"
            
            # 检查构建日志
            if [ -f "$BUILD_DIR/openwrt/build.log" ]; then
                echo "📄 构建日志存在 ($(ls -lh $BUILD_DIR/openwrt/build.log | awk '{print $5}'))"
                
                # 分析构建日志
                echo ""
                echo "=== 构建日志分析 ==="
                
                # 统计错误和警告
                local error_count=$(grep -c -i "error:" "$BUILD_DIR/openwrt/build.log" 2>/dev/null || echo "0")
                local warning_count=$(grep -c -i "warning:" "$BUILD_DIR/openwrt/build.log" 2>/dev/null || echo "0")
                local failed_count=$(grep -c -i "failed" "$BUILD_DIR/openwrt/build.log" 2>/dev/null || echo "0")
                
                echo "❌ 错误数量: $error_count"
                echo "⚠️ 警告数量: $warning_count"
                echo "🚫 失败数量: $failed_count"
                
                # 显示前5个错误
                if [ $error_count -gt 0 ]; then
                    echo ""
                    echo "=== 前5个错误 ==="
                    grep -i "error:" "$BUILD_DIR/openwrt/build.log" | head -5
                fi
                
                # 显示前5个警告
                if [ $warning_count -gt 0 ]; then
                    echo ""
                    echo "=== 前5个警告 ==="
                    grep -i "warning:" "$BUILD_DIR/openwrt/build.log" | head -5
                fi
                
                # 检查常见问题
                echo ""
                echo "=== 常见问题检查 ==="
                
                # 检查内存不足
                if grep -q -i "out of memory\|oom\|killed" "$BUILD_DIR/openwrt/build.log" 2>/dev/null; then
                    echo "❌ 发现内存不足问题"
                else
                    echo "✅ 未发现内存不足问题"
                fi
                
                # 检查磁盘空间
                if grep -q -i "no space left\|disk full" "$BUILD_DIR/openwrt/build.log" 2>/dev/null; then
                    echo "❌ 发现磁盘空间问题"
                else
                    echo "✅ 未发现磁盘空间问题"
                fi
                
                # 检查网络问题
                if grep -q -i "connection.*failed\|timeout\|network" "$BUILD_DIR/openwrt/build.log" 2>/dev/null; then
                    echo "❌ 发现网络问题"
                else
                    echo "✅ 未发现网络问题"
                fi
                
                # 检查工具链问题
                if grep -q -i "toolchain\|compiler.*not found" "$BUILD_DIR/openwrt/build.log" 2>/dev/null; then
                    echo "❌ 发现工具链问题"
                else
                    echo "✅ 未发现工具链问题"
                fi
                
                # 检查依赖问题
                if grep -q -i "dependency\|requires\|depends" "$BUILD_DIR/openwrt/build.log" 2>/dev/null; then
                    echo "⚠️ 发现依赖问题"
                else
                    echo "✅ 未发现依赖问题"
                fi
            else
