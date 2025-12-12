#!/bin/bash
# OpenWrt智能构建主脚本（整合版）
# 最后更新: 2024-01-16

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

# ========== 智能文件查找函数 ==========
smart_find() {
    local pattern="$1"
    local max_depth="${2:-3}"
    
    local common_locations=(
        "$REPO_ROOT"
        "$REPO_ROOT/firmware-config"
        "$REPO_ROOT/scripts"
        "$REPO_ROOT/.github"
        "/tmp"
        "."
    )
    
    for location in "${common_locations[@]}"; do
        if [ -d "$location" ]; then
            local found=$(find "$location" -maxdepth "$max_depth" -name "$pattern" 2>/dev/null | head -1)
            if [ -n "$found" ]; then
                echo "$found"
                return 0
            fi
        fi
    done
    
    return 1
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
    
    sudo mkdir -p "$BUILD_DIR"
    sudo chmod 777 "$BUILD_DIR"
    log_success "构建目录: $BUILD_DIR"
    
    # 检查磁盘空间
    local available_space=$(df -h "$BUILD_DIR" | tail -1 | awk '{print $4}')
    log_info "可用空间: $available_space"
}

# ========== 工具链管理（保留必要功能）==========

# 初始化工具链目录（仅创建结构）
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

# 保存通用工具链（仅保存必要的部分）
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
    
    # 下载OpenWrt源码
    log_info "正在下载OpenWrt源码: $branch_name"
    git clone --depth 1 --branch "$branch_name" "$openwrt_url" "$BUILD_DIR/openwrt"
    
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

# ========== 配置生成 ==========

# 生成配置
generate_config() {
    local extra_packages=$1
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "生成配置..."
    
    rm -f .config .config.old
    
    # 基础目标配置
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    # 基础包
    echo "CONFIG_PACKAGE_busybox=y" >> .config
    echo "CONFIG_PACKAGE_base-files=y" >> .config
    echo "CONFIG_PACKAGE_dropbear=y" >> .config
    echo "CONFIG_PACKAGE_firewall=y" >> .config
    echo "CONFIG_PACKAGE_fstools=y" >> .config
    echo "CONFIG_PACKAGE_libc=y" >> .config
    echo "CONFIG_PACKAGE_libgcc=y" >> .config
    echo "CONFIG_PACKAGE_mtd=y" >> .config
    echo "CONFIG_PACKAGE_netifd=y" >> .config
    echo "CONFIG_PACKAGE_opkg=y" >> .config
    echo "CONFIG_PACKAGE_procd=y" >> .config
    echo "CONFIG_PACKAGE_ubox=y" >> .config
    echo "CONFIG_PACKAGE_ubus=y" >> .config
    echo "CONFIG_PACKAGE_uci=y" >> .config
    
    # USB驱动（通用）
    echo "# USB驱动" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    
    # 文件系统支持
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
    
    # 网络基础
    echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
    echo "CONFIG_PACKAGE_iptables=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config
    
    # 根据配置模式添加功能
    if [ "$CONFIG_MODE" = "normal" ]; then
        echo "# 正常模式插件" >> .config
        echo "CONFIG_PACKAGE_luci=y" >> .config
        echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
        echo "CONFIG_PACKAGE_kmod-shortcut-fe=y" >> .config
        echo "CONFIG_PACKAGE_kmod-fast-classifier=y" >> .config
    fi
    
    # 处理额外插件
    if [ -n "$extra_packages" ]; then
        log_info "处理额外安装插件: $extra_packages"
        IFS=';' read -ra EXTRA_PKGS <<< "$extra_packages"
        for pkg_cmd in "${EXTRA_PKGS[@]}"; do
            if [ -n "$pkg_cmd" ]; then
                pkg_cmd_clean=$(echo "$pkg_cmd" | xargs)
                if [[ "$pkg_cmd_clean" == +* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log_info "启用插件: $pkg_name"
                    echo "CONFIG_PACKAGE_${pkg_name}=y" >> .config
                elif [[ "$pkg_cmd_clean" == -* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log_info "禁用插件: $pkg_name"
                    echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> .config
                else
                    log_info "启用插件: $pkg_cmd_clean"
                    echo "CONFIG_PACKAGE_${pkg_cmd_clean}=y" >> .config
                fi
            fi
        done
    fi
    
    log_success "配置生成完成"
}

# 应用配置
apply_config() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "应用配置..."
    
    if [ ! -f ".config" ]; then
        log_error ".config 文件不存在"
        exit 1
    fi
    
    # 显示配置摘要
    log_info "配置摘要:"
    log_info "  目标平台: $TARGET/$SUBTARGET"
    log_info "  设备: $DEVICE"
    log_info "  配置模式: $CONFIG_MODE"
    
    make defconfig || handle_error "应用配置失败"
    
    log_success "配置应用完成"
}

# ========== 构建流程 ==========

# 配置Feeds
configure_feeds() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "配置Feeds..."
    
    # 使用immortalwrt的feeds
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    log_info "更新Feeds..."
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log_info "安装Feeds..."
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log_success "Feeds配置完成"
}

# 下载依赖包
download_dependencies() {
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "下载依赖包..."
    
    # 检查依赖包目录
    if [ ! -d "dl" ]; then
        mkdir -p dl
    fi
    
    # 显示现有依赖包
    local existing_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log_info "现有依赖包数量: $existing_deps 个"
    
    # 下载依赖包
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    # 检查下载结果
    local downloaded_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log_info "下载后依赖包数量: $downloaded_deps 个"
    
    if [ $downloaded_deps -gt $existing_deps ]; then
        log_success "成功下载了 $((downloaded_deps - existing_deps)) 个新依赖包"
    else
        log_info "没有下载新的依赖包"
    fi
    
    log_success "依赖包下载完成"
}

# 构建固件
build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "编译固件..."
    
    # 加载工具链
    load_toolchain
    
    # 获取CPU核心数
    local cpu_cores=$(nproc)
    local make_jobs=$cpu_cores
    
    # 如果内存小于4GB，减少并行任务
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_mem -lt 4096 ]; then
        make_jobs=$((cpu_cores / 2))
        if [ $make_jobs -lt 1 ]; then
            make_jobs=1
        fi
        log_warn "内存较低(${total_mem}MB)，减少并行任务到 $make_jobs"
    fi
    
    # 开始编译
    if [ "$enable_cache" = "true" ]; then
        log_info "启用编译缓存，使用 $make_jobs 个并行任务"
        make -j$make_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    else
        log_info "普通编译模式，使用 $make_jobs 个并行任务"
        make -j$make_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        log_success "固件编译成功"
        
        # 检查生成的固件
        if [ -d "bin/targets" ]; then
            local firmware_count=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
            log_success "生成固件文件: $firmware_count 个"
            
            # 显示固件文件
            find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -3 | while read file; do
                log_info "固件: $file ($(du -h "$file" | cut -f1))"
            done
        fi
    else
        log_error "编译失败，退出代码: $BUILD_EXIT_CODE"
        
        # 分析失败原因
        if [ -f "build.log" ]; then
            log_error "编译错误摘要:"
            grep -i "Error\|error:" build.log | head -5
        fi
        
        exit $BUILD_EXIT_CODE
    fi
}

# 检查固件文件
check_firmware_files() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "固件文件检查..."
    
    if [ -d "bin/targets" ]; then
        log_success "固件目录存在"
        
        # 显示固件文件
        echo "=== 生成的固件文件 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \;
        
        # 统计固件文件
        local firmware_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        log_success "固件文件数: $firmware_files 个"
    else
        log_error "固件目录不存在"
        exit 1
    fi
}

# ========== 空间检查 ==========

# 编译前空间检查
pre_build_space_check() {
    log_info "编译前空间检查..."
    
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    
    # 磁盘信息
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 检查可用空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log_info "/mnt 可用空间: ${available_gb}G"
    
    # 编译所需空间估算
    local estimated_space=15
    if [ $available_gb -lt $estimated_space ]; then
        log_warn "可用空间(${available_gb}G)可能不足，建议至少${estimated_space}G"
    else
        log_success "磁盘空间充足"
    fi
}

# 编译后空间检查
post_build_space_check() {
    log_info "编译后空间检查..."
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 构建目录空间
    if [ -d "$BUILD_DIR" ]; then
        local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
        echo "构建目录大小: $build_dir_usage"
    fi
}

# ========== 清理函数 ==========

# 清理目录
cleanup() {
    log_info "清理构建目录..."
    
    if [ -d "$BUILD_DIR" ]; then
        log_info "备份配置文件和日志..."
        
        # 备份.config文件
        if [ -f "$BUILD_DIR/openwrt/.config" ]; then
            mkdir -p /tmp/openwrt_backup
            cp "$BUILD_DIR/openwrt/.config" "/tmp/openwrt_backup/config_$(date +%Y%m%d_%H%M%S).config"
            log_info "配置文件备份到: /tmp/openwrt_backup/"
        fi
        
        # 清理构建目录
        sudo rm -rf $BUILD_DIR || log_warn "清理构建目录失败"
        log_success "构建目录已清理"
    else
        log_info "构建目录不存在，无需清理"
    fi
}

# ========== 工作流步骤函数 ==========

# 工作流主调度
workflow_main() {
    case $1 in
        "step1_download_source")
            workflow_step1_download_source "$2"
            ;;
        "step2_upload_source")
            workflow_step2_upload_source
            ;;
        "step5_check_large_files")
            workflow_step5_check_large_files
            ;;
        "step6_check_toolchain_dir")
            workflow_step6_check_toolchain_dir
            ;;
        "step7_init_toolchain_dir")
            workflow_step7_init_toolchain_dir
            ;;
        "step8_setup_environment")
            workflow_step8_setup_environment
            ;;
        "step9_create_build_dir")
            workflow_step9_create_build_dir
            ;;
        "step10_init_build_env")
            workflow_step10_init_build_env "$2" "$3" "$4" "$5"
            ;;
        "step11_show_config")
            workflow_step11_show_config
            ;;
        "step13_configure_feeds")
            workflow_step13_configure_feeds
            ;;
        "step24_download_dependencies")
            workflow_step24_download_dependencies
            ;;
        "step27_final_space_check")
            workflow_step27_final_space_check
            ;;
        "step28_build_firmware")
            workflow_step28_build_firmware
            ;;
        "step29_save_essential_toolchain")
            workflow_step29_save_essential_toolchain
            ;;
        "step31_error_analysis")
            workflow_step31_error_analysis
            ;;
        "step32_post_build_space_check")
            workflow_step32_post_build_space_check
            ;;
        "step33_check_firmware_files")
            workflow_step33_check_firmware_files
            ;;
        "step37_cleanup")
            workflow_step37_cleanup
            ;;
        *)
            main "$@"
            ;;
    esac
}

# 步骤1：下载完整源代码
workflow_step1_download_source() {
    local workspace="$1"
    
    echo "========================================"
    echo "📥 步骤1：下载完整源代码"
    echo "========================================"
    
    cd "$workspace"
    
    # 克隆完整仓库
    local repo_url="https://github.com/$GITHUB_REPOSITORY.git"
    git clone --depth 1 "$repo_url" .
    
    if [ ! -d ".git" ]; then
        log_error "仓库克隆失败，.git目录不存在"
        exit 1
    fi
    
    echo "✅ 完整仓库克隆完成"
    echo "========================================"
}

# 步骤2：立即上传源代码
workflow_step2_upload_source() {
    echo "========================================"
    echo "📤 步骤2：上传源代码"
    echo "========================================"
    
    # 创建源代码压缩包
    mkdir -p /tmp/source-upload
    
    # 创建排除列表
    echo "firmware-config/Toolchain" > /tmp/exclude-list.txt
    echo ".git" >> /tmp/exclude-list.txt
    
    # 创建压缩包
    tar --exclude-from=/tmp/exclude-list.txt -czf /tmp/source-upload/source-code.tar.gz .
    
    echo "✅ 源代码压缩包创建完成"
    echo "========================================"
}

# 步骤5：大文件检查
workflow_step5_check_large_files() {
    echo "========================================"
    echo "📊 步骤5：大文件检查"
    echo "========================================"
    
    echo "扫描大文件..."
    find . -type f -size +50M 2>/dev/null | grep -v ".git" | head -10 || echo "未发现超过50MB的大文件"
    
    echo "========================================"
}

# 步骤6：工具链目录检查
workflow_step6_check_toolchain_dir() {
    echo "========================================"
    echo "🗂️ 步骤6：工具链目录检查"
    echo "========================================"
    
    check_toolchain_dir
    
    echo "========================================"
}

# 步骤7：初始化工具链目录
workflow_step7_init_toolchain_dir() {
    echo "========================================"
    echo "💾 步骤7：初始化工具链目录"
    echo "========================================"
    
    init_toolchain_dir
    
    echo "========================================"
}

# 步骤8：设置编译环境
workflow_step8_setup_environment() {
    echo "========================================"
    echo "🛠️ 步骤8：设置编译环境"
    echo "========================================"
    
    setup_environment
    
    echo "========================================"
}

# 步骤9：创建构建目录
workflow_step9_create_build_dir() {
    echo "========================================"
    echo "📁 步骤9：创建构建目录"
    echo "========================================"
    
    create_build_dir
    
    echo "========================================"
}

# 步骤10：初始化构建环境
workflow_step10_init_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local extra_packages="${4:-}"
    
    echo "========================================"
    echo "🚀 步骤10：初始化构建环境"
    echo "========================================"
    
    initialize_build_env "$device_name" "$version_selection" "$config_mode" "$extra_packages"
    
    echo "========================================"
}

# 步骤11：显示配置
workflow_step11_show_config() {
    echo "========================================"
    echo "⚡ 步骤11：显示配置"
    echo "========================================"
    
    load_env
    echo "构建配置摘要:"
    echo "  设备: $DEVICE"
    echo "  版本: $SELECTED_BRANCH"
    echo "  配置模式: $CONFIG_MODE"
    echo "  目标平台: $TARGET/$SUBTARGET"
    echo "  构建目录: $BUILD_DIR"
    
    echo "========================================"
}

# 步骤13：配置Feeds
workflow_step13_configure_feeds() {
    echo "========================================"
    echo "📦 步骤13：配置Feeds"
    echo "========================================"
    
    configure_feeds
    
    echo "========================================"
}

# 步骤24：下载依赖包
workflow_step24_download_dependencies() {
    echo "========================================"
    echo "📥 步骤24：下载依赖包"
    echo "========================================"
    
    download_dependencies
    
    echo "========================================"
}

# 步骤27：编译前的空间检查
workflow_step27_final_space_check() {
    echo "========================================"
    echo "💽 步骤27：编译前的空间检查"
    echo "========================================"
    
    pre_build_space_check
    
    echo "========================================"
}

# 步骤28：编译固件
workflow_step28_build_firmware() {
    echo "========================================"
    echo "🔨 步骤28：编译固件"
    echo "========================================"
    
    build_firmware "true"
    
    echo "========================================"
}

# 步骤29：保存通用工具链
workflow_step29_save_essential_toolchain() {
    echo "========================================"
    echo "💾 步骤29：保存通用工具链"
    echo "========================================"
    
    save_essential_toolchain
    
    echo "========================================"
}

# 步骤31：错误分析
workflow_step31_error_analysis() {
    echo "========================================"
    echo "⚠️ 步骤31：错误分析"
    echo "========================================"
    
    echo "=== 错误分析报告 ==="
    echo "分析时间: $(date)"
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    echo ""
    echo "=== 磁盘使用情况 ==="
    df -h
    echo ""
    echo "=== 内存使用情况 ==="
    free -h
    
    echo "========================================"
}

# 步骤32：编译后空间检查
workflow_step32_post_build_space_check() {
    echo "========================================"
    echo "📊 步骤32：编译后空间检查"
    echo "========================================"
    
    post_build_space_check
    
    echo "========================================"
}

# 步骤33：固件文件检查
workflow_step33_check_firmware_files() {
    echo "========================================"
    echo "📦 步骤33：固件文件检查"
    echo "========================================"
    
    check_firmware_files
    
    echo "========================================"
}

# 步骤37：清理目录
workflow_step37_cleanup() {
    echo "========================================"
    echo "🧹 步骤37：清理目录"
    echo "========================================"
    
    cleanup
    
    echo "========================================"
}

# ========== 主函数 ==========
main() {
    case $1 in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$2" "$3" "$4"
            ;;
        "configure_feeds")
            configure_feeds
            ;;
        "pre_build_space_check")
            pre_build_space_check
            ;;
        "generate_config")
            generate_config "$2"
            ;;
        "apply_config")
            apply_config
            ;;
        "download_dependencies")
            download_dependencies
            ;;
        "load_toolchain")
            load_toolchain
            ;;
        "check_toolchain_completeness")
            check_toolchain_completeness
            ;;
        "save_essential_toolchain")
            save_essential_toolchain
            ;;
        "build_firmware")
            build_firmware "$2"
            ;;
        "post_build_space_check")
            post_build_space_check
            ;;
        "check_firmware_files")
            check_firmware_files
            ;;
        "cleanup")
            cleanup
            ;;
        "init_toolchain_dir")
            init_toolchain_dir
            ;;
        "check_toolchain_dir")
            check_toolchain_dir
            ;;
        *)
            echo "可用命令:"
            echo "  构建命令:"
            echo "    setup_environment, create_build_dir, initialize_build_env"
            echo "    configure_feeds, generate_config, apply_config, download_dependencies"
            echo "    load_toolchain, build_firmware, check_firmware_files, cleanup"
            echo ""
            echo "  工具链命令:"
            echo "    init_toolchain_dir, check_toolchain_dir, check_toolchain_completeness"
            echo "    save_essential_toolchain"
            echo ""
            echo "  检查命令:"
            echo "    pre_build_space_check, post_build_space_check"
            echo ""
            echo "  工作流步骤命令:"
            echo "    以 'workflow_main' 开头，如: workflow_main step1_download_source"
            exit 1
            ;;
    esac
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$1" == "workflow_main" ]]; then
        workflow_main "${@:2}"
    else
        main "$@"
    fi
fi
