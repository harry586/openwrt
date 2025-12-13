#!/bin/bash
# OpenWrt智能构建主脚本

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

# ========== 工作流步骤函数（36个步骤完整版） ==========

workflow_main() {
    case $1 in
        # 阶段1：初始化和修复
        "step4_prepare_environment")
            workflow_step4_prepare_environment
            ;;
        
        "step5_setup_environment")
            setup_environment
            ;;
        
        "step6_create_build_dir")
            create_build_dir
            ;;
        
        "step7_check_toolchain_dir")
            check_toolchain_dir
            ;;
        
        "step8_init_build_env")
            workflow_step8_init_build_env "$2" "$3" "$4" "$5"
            ;;
        
        "step9_show_config")
            workflow_step9_show_config
            ;;
        
        # 阶段3：源码管理
        "step10_download_source")
            download_openwrt_source
            ;;
        
        # 阶段4：配置生成
        "step11_add_turboacc_support")
            add_turboacc_support
            ;;
        
        "step12_configure_feeds")
            configure_feeds
            ;;
        
        "step13_install_turboacc_packages")
            install_turboacc_packages
            ;;
        
        "step14_space_check")
            pre_build_space_check
            ;;
        
        "step15_generate_config")
            generate_config "$2"
            ;;
        
        "step16_verify_usb_config")
            verify_usb_config
            ;;
        
        "step17_check_usb_drivers_integrity")
            check_usb_drivers_integrity
            ;;
        
        "step18_apply_config")
            apply_config
            ;;
        
        "step19_backup_config")
            workflow_step19_backup_config
            ;;
        
        # 阶段5：工具链和依赖
        "step20_fix_network")
            workflow_step20_fix_network
            ;;
        
        "step21_load_toolchain")
            load_toolchain
            ;;
        
        "step22_check_toolchain_status")
            workflow_step22_check_toolchain_status
            ;;
        
        "step23_download_dependencies")
            download_dependencies
            ;;
        
        "step24_integrate_custom_files")
            integrate_custom_files
            ;;
        
        # 阶段6：构建前准备
        "step25_pre_build_error_check")
            pre_build_error_check
            ;;
        
        "step26_final_space_check")
            pre_build_space_check
            ;;
        
        # 阶段7：构建固件
        "step28_build_firmware")
            build_firmware "$2"
            ;;
        
        # 阶段8：构建后处理
        "step29_build_analysis")
            workflow_step29_build_analysis "$2"
            ;;
        
        "step30_post_build_space_check")
            post_build_space_check
            ;;
        
        "step31_check_firmware_files")
            check_firmware_files
            ;;
        
        # 阶段9：清理和总结
        "step35_cleanup")
            cleanup
            ;;
        
        "step36_final_summary")
            workflow_step36_final_summary "$2"
            ;;
        
        *)
            main "$@"
            ;;
    esac
}

# ========== 具体步骤实现 ==========

# 步骤4：准备构建环境
workflow_step4_prepare_environment() {
    echo "========================================"
    echo "📁 步骤4：准备构建环境"
    echo "========================================"
    
    echo "创建必要目录结构..."
    mkdir -p firmware-config/scripts
    mkdir -p firmware-config/Toolchain/common
    mkdir -p firmware-config/Toolchain/configs
    mkdir -p firmware-config/config-backup
    mkdir -p firmware-config/custom-files
    
    echo "✅ 环境准备完成"
    echo "目录结构:"
    echo "  firmware-config/scripts/"
    echo "  firmware-config/Toolchain/common/"
    echo "  firmware-config/Toolchain/configs/"
    echo "  firmware-config/config-backup/"
    echo "  firmware-config/custom-files/"
    echo "========================================"
}

# 步骤8：初始化构建环境
workflow_step8_init_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local extra_packages="${4:-}"
    
    echo "========================================"
    echo "🚀 步骤8：初始化构建环境"
    echo "========================================"
    
    initialize_build_env "$device_name" "$version_selection" "$config_mode" "$extra_packages"
    
    echo "✅ 构建环境初始化完成"
    echo "========================================"
}

# 步骤9：显示配置
workflow_step9_show_config() {
    echo "========================================"
    echo "⚡ 步骤9：显示配置"
    echo "========================================"
    
    load_env
    echo "构建配置摘要:"
    echo "  设备: $DEVICE"
    echo "  版本: $SELECTED_BRANCH"
    echo "  配置模式: $CONFIG_MODE"
    echo "  目标平台: $TARGET/$SUBTARGET"
    echo "  构建目录: $BUILD_DIR"
    
    if [ -n "$EXTRA_PACKAGES" ]; then
        echo "  额外插件: $EXTRA_PACKAGES"
    fi
    
    echo "✅ 配置显示完成"
    echo "========================================"
}

# 步骤19：备份配置
workflow_step19_backup_config() {
    echo "========================================"
    echo "💾 步骤19：备份配置"
    echo "========================================"
    
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    mkdir -p "$REPO_ROOT/firmware-config/config-backup"
    
    backup_file="$REPO_ROOT/firmware-config/config-backup/config_${DEVICE}_${SELECTED_BRANCH}_$(date +%Y%m%d_%H%M%S).config"
    
    cp ".config" "$backup_file"
    echo "✅ 配置文件备份到: $backup_file"
    echo "备份路径: firmware-config/config-backup/"
    echo "========================================"
}

# 步骤20：修复网络
workflow_step20_fix_network() {
    echo "========================================"
    echo "🌐 步骤20：修复网络"
    echo "========================================"
    
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    echo "设置git配置以加速下载..."
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    
    echo "设置环境变量..."
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    export CURL_SSL_NO_VERIFY=1
    
    echo "✅ 网络环境修复完成"
    echo "========================================"
}

# 步骤22：检查工具链状态
workflow_step22_check_toolchain_status() {
    echo "========================================"
    echo "📊 步骤22：检查工具链状态"
    echo "========================================"
    
    load_env
    cd $BUILD_DIR/openwrt
    
    echo "检查工具链状态..."
    
    if [ -d "staging_dir" ]; then
        echo "✅ staging_dir 目录存在"
        
        local toolchain_dirs=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null)
        local toolchain_count=$(echo "$toolchain_dirs" | wc -l)
        
        echo "找到 $toolchain_count 个工具链目录"
    else
        echo "❌ staging_dir 目录不存在"
    fi
    
    echo "✅ 工具链状态检查完成"
    echo "========================================"
}

# 步骤29：构建分析
workflow_step29_build_analysis() {
    local build_status="$1"
    
    echo "========================================"
    echo "📊 步骤29：构建分析"
    echo "========================================"
    
    echo "📅 分析时间: $(date)"
    echo "🏗️ 构建状态: $build_status"
    
    if [ -f "$BUILD_DIR/openwrt/build.log" ]; then
        echo "📄 构建日志大小: $(ls -lh $BUILD_DIR/openwrt/build.log | awk '{print $5}')"
        
        local error_count=$(grep -c -i "error:" "$BUILD_DIR/openwrt/build.log" 2>/dev/null || echo "0")
        local warning_count=$(grep -c -i "warning:" "$BUILD_DIR/openwrt/build.log" 2>/dev/null || echo "0")
        
        echo "❌ 错误数量: $error_count"
        echo "⚠️ 警告数量: $warning_count"
    else
        echo "❌ 构建日志不存在"
    fi
    
    echo "✅ 构建分析完成"
    echo "========================================"
}

# 步骤36：最终总结
workflow_step36_final_summary() {
    local build_status="$1"
    
    echo "========================================"
    echo "📈 步骤36：最终总结"
    echo "========================================"
    
    echo "🏁 构建完成"
    echo "状态: $build_status"
    echo "时间: $(date)"
    echo "设备: ${DEVICE:-未知}"
    echo "版本: ${SELECTED_BRANCH:-未知}"
    
    if [ "$build_status" = "success" ]; then
        echo "🎉 构建成功！"
        if [ -d "$BUILD_DIR/openwrt/bin/targets" ]; then
            local firmware_count=$(find "$BUILD_DIR/openwrt/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
            echo "📦 生成固件: $firmware_count 个文件"
        fi
    else
        echo "❌ 构建失败"
        echo "建议: 查看构建日志分析具体错误"
    fi
    
    echo "========================================"
}

# ========== 核心功能函数 ==========

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
    
    if [ ! -d "/mnt" ]; then
        log_info "创建/mnt目录..."
        sudo mkdir -p /mnt
    fi
    
    sudo chmod 777 /mnt 2>/dev/null || true
    
    if [ ! -d "$BUILD_DIR" ]; then
        log_info "创建构建目录..."
        sudo mkdir -p "$BUILD_DIR"
    fi
    
    sudo chmod 777 "$BUILD_DIR" 2>/dev/null || true
    
    log_success "构建目录: $BUILD_DIR"
    
    local available_space=$(df -h "$BUILD_DIR" | tail -1 | awk '{print $4}')
    log_info "可用空间: $available_space"
}

# 检查工具链目录状态
check_toolchain_dir() {
    log_info "检查工具链目录..."
    
    if [ -d "$TOOLCHAIN_DIR" ]; then
        log_success "工具链目录存在: $TOOLCHAIN_DIR"
        
        if [ -d "$TOOLCHAIN_DIR/common" ]; then
            local common_files=$(find "$TOOLCHAIN_DIR/common" -type f 2>/dev/null | wc -l)
            log_info "通用工具链文件: $common_files 个"
            
            if [ $common_files -gt 0 ]; then
                echo "已有工具链文件，可加速编译"
            fi
        fi
    else
        log_warn "工具链目录不存在，将自动创建"
        init_toolchain_dir
    fi
}

# 初始化工具链目录
init_toolchain_dir() {
    log_info "初始化工具链目录..."
    
    mkdir -p "$TOOLCHAIN_DIR/common"
    mkdir -p "$TOOLCHAIN_DIR/configs"
    
    log_success "工具链目录初始化完成"
}

# 加载通用工具链
load_toolchain() {
    log_info "加载通用工具链..."
    
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    mkdir -p staging_dir
    
    # 检查仓库中是否有通用工具链
    if [ -d "$TOOLCHAIN_DIR/common" ] && [ -n "$(ls -A "$TOOLCHAIN_DIR/common" 2>/dev/null)" ]; then
        log_info "发现通用工具链，尝试加载..."
        
        local toolchain_name="toolchain-common-$(date +%s)"
        mkdir -p "staging_dir/$toolchain_name"
        
        cp -r "$TOOLCHAIN_DIR/common/"* "staging_dir/$toolchain_name/" 2>/dev/null || true
        
        if [ -n "$(ls -A "staging_dir/$toolchain_name" 2>/dev/null)" ]; then
            log_success "通用工具链加载成功"
        else
            log_warn "通用工具链目录为空"
        fi
    else
        log_info "未找到通用工具链"
    fi
    
    export STAGING_DIR="$BUILD_DIR/openwrt/staging_dir"
    
    log_success "工具链环境设置完成"
}

# 保存通用工具链
save_essential_toolchain() {
    log_info "保存通用工具链..."
    
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    if [ ! -d "staging_dir" ]; then
        log_warn "构建目录中没有工具链，跳过保存"
        return 0
    fi
    
    local staging_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | head -1)
    
    if [ -z "$staging_toolchain" ]; then
        log_warn "未找到工具链目录，跳过保存"
        return 0
    fi
    
    log_info "找到工具链: $staging_toolchain"
    
    mkdir -p "$TOOLCHAIN_DIR/common"
    
    local essential_files=0
    
    if [ -d "$staging_toolchain/bin" ]; then
        log_info "保存通用编译工具..."
        
        local tools=("ccache" "gcc" "g++" "ld" "as" "ar" "nm" "objcopy" "objdump" "ranlib" "strip")
        for tool in "${tools[@]}"; do
            if find "$staging_toolchain/bin" -name "*$tool*" -type f -exec cp -v {} "$TOOLCHAIN_DIR/common/" \; 2>/dev/null; then
                essential_files=$((essential_files + 1))
            fi
        done
    fi
    
    if [ -f "$BUILD_DIR/openwrt/.config" ]; then
        cp "$BUILD_DIR/openwrt/.config" "$TOOLCHAIN_DIR/configs/build_config.txt"
        log_info "保存构建配置文件"
        essential_files=$((essential_files + 1))
    fi
    
    log_success "保存了 $essential_files 个通用工具链文件"
    log_info "工具链保存到: $TOOLCHAIN_DIR/common"
    
    return 0
}

# 下载OpenWrt源代码
download_openwrt_source() {
    log_info "下载OpenWrt源代码..."
    
    cd "$BUILD_DIR"
    
    local openwrt_url="https://github.com/openwrt/openwrt.git"
    local branch_name=""
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        branch_name="openwrt-23.05"
    elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
        branch_name="openwrt-21.02"
    else
        branch_name="master"
    fi
    
    if [ -d "$BUILD_DIR/openwrt" ] && [ -f "$BUILD_DIR/openwrt/feeds.conf.default" ]; then
        log_success "OpenWrt源码已存在，跳过下载"
        return 0
    fi
    
    if [ -d "$BUILD_DIR/openwrt" ]; then
        log_info "清理旧的源码目录..."
        rm -rf "$BUILD_DIR/openwrt"
    fi
    
    cd "$BUILD_DIR"
    
    log_info "正在下载OpenWrt源码: $branch_name"
    git clone --depth 1 --branch "$branch_name" "$openwrt_url" "openwrt"
    
    if [ ! -d "$BUILD_DIR/openwrt" ]; then
        log_error "OpenWrt源码下载失败"
        exit 1
    fi
    
    log_success "OpenWrt源码下载完成"
}

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
    
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_BRANCH="openwrt-23.05"
    elif [ "$version_selection" = "21.02" ]; then
        SELECTED_BRANCH="openwrt-21.02"
    else
        SELECTED_BRANCH="$version_selection"
    fi
    
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
    
    cat > "$ENV_FILE" << EOF
SELECTED_BRANCH="$SELECTED_BRANCH"
TARGET="$TARGET"
SUBTARGET="$SUBTARGET"
DEVICE="$DEVICE"
CONFIG_MODE="$config_mode"
EXTRA_PACKAGES="$extra_packages"
BUILD_DIR="$BUILD_DIR"
REPO_ROOT="$REPO_ROOT"
EOF
    
    log_success "构建环境初始化完成"
}

# 加载环境变量
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
}

# 配置Feeds
configure_feeds() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "配置Feeds..."
    
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

# 添加 TurboACC 支持
add_turboacc_support() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "添加 TurboACC 支持..."
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log_info "为正常模式添加 TurboACC 支持"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log_info "为 23.05 添加 TurboACC 支持"
            echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
            log_success "TurboACC feed 添加完成"
        else
            log_info "21.02 版本已内置 TurboACC，无需额外添加"
        fi
    else
        log_info "基础模式不添加 TurboACC 支持"
    fi
}

# 安装 TurboACC 包
install_turboacc_packages() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "安装 TurboACC 包..."
    
    ./scripts/feeds update turboacc || handle_error "更新turboacc feed失败"
    
    ./scripts/feeds install -p turboacc luci-app-turboacc || handle_error "安装luci-app-turboacc失败"
    ./scripts/feeds install -p turboacc kmod-shortcut-fe || handle_error "安装kmod-shortcut-fe失败"
    ./scripts/feeds install -p turboacc kmod-fast-classifier || handle_error "安装kmod-fast-classifier失败"
    
    log_success "TurboACC 包安装完成"
}

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
    
    # USB驱动
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
    
    # 平台专用驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
    fi
    
    # SCSI驱动（修复编译错误）
    echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> .config
    
    # 根据配置模式添加功能
    if [ "$CONFIG_MODE" = "normal" ]; then
        echo "# Luci界面" >> .config
        echo "CONFIG_PACKAGE_luci=y" >> .config
        echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
        
        echo "# 常用功能插件" >> .config
        echo "CONFIG_PACKAGE_luci-app-samba4=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-diskman=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-upnp=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-smartdns=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-access-control=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-vsftpd=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-sqm=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-vlmcsd=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-arpbind=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-cpulimit=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-hd-idle=y" >> .config
        echo "CONFIG_PACKAGE_luci-app-serverchan=y" >> .config
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

# 验证 USB 配置
verify_usb_config() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "验证USB配置..."
    
    echo "=== USB配置状态 ==="
    
    local usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-storage")
    for driver in "${usb_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "✅ $driver: 已启用"
        else
            echo "❌ $driver: 未启用"
        fi
    done
    
    log_success "USB配置验证完成"
}

# 检查 USB 驱动完整性
check_usb_drivers_integrity() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "检查USB驱动完整性..."
    
    local missing_drivers=()
    local required_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb-storage"
    )
    
    if [ "$TARGET" = "ipq40xx" ]; then
        required_drivers+=("kmod-usb-dwc3")
    fi
    
    for driver in "${required_drivers[@]}"; do
        if ! grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            log_warn "缺失驱动: $driver"
            missing_drivers+=("$driver")
        fi
    done
    
    if [ ${#missing_drivers[@]} -gt 0 ]; then
        log_warn "发现 ${#missing_drivers[@]} 个缺失的USB驱动"
        for driver in "${missing_drivers[@]}"; do
            echo "CONFIG_PACKAGE_${driver}=y" >> .config
            log_info "✅ 已添加: $driver"
        done
    fi
    
    log_success "USB驱动完整性检查完成"
}

# 应用配置并显示详情
apply_config() {
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "应用配置并显示详情..."
    
    if [ ! -f ".config" ]; then
        log_error ".config 文件不存在"
        return 1
    fi
    
    log_info "配置详情:"
    log_info "配置文件大小: $(ls -lh .config | awk '{print $5}')"
    log_info "配置行数: $(wc -l < .config)"
    
    echo ""
    echo "=== 已启用功能插件 ==="
    
    # 显示您的插件状态
    PLUGINS=(
        "luci-app-turboacc TurboACC 网络加速"
        "luci-app-upnp UPnP 自动端口转发"
        "luci-app-samba4 Samba 文件共享"
        "luci-app-diskman 磁盘管理"
        "luci-app-vlmcsd KMS 激活服务"
        "luci-app-smartdns SmartDNS 智能DNS"
        "luci-app-access-control 家长控制"
        "luci-app-serverchan 微信推送"
        "luci-app-sqm 流量控制 (SQM)"
        "luci-app-vsftpd FTP 服务器"
        "luci-app-arpbind ARP 绑定"
        "luci-app-cpulimit CPU 限制"
        "luci-app-hd-idle 硬盘休眠"
    )
    
    for plugin_info in "${PLUGINS[@]}"; do
        plugin_name=$(echo "$plugin_info" | cut -d' ' -f1)
        plugin_desc=$(echo "$plugin_info" | cut -d' ' -f2-)
        
        if grep -q "^CONFIG_PACKAGE_${plugin_name}=y" .config; then
            echo "  ✅ $plugin_desc"
        else
            echo "  ❌ $plugin_desc"
        fi
    done
    
    # 统计信息
    local enabled_count=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local disabled_count=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    
    echo ""
    echo "📊 配置统计:"
    echo "  已启用: $enabled_count 个插件"
    echo "  已禁用: $disabled_count 个插件"
    
    echo ""
    log_info "运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log_success "配置应用完成"
}

# 下载依赖包
download_dependencies() {
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "下载依赖包..."
    
    if [ ! -d "dl" ]; then
        mkdir -p dl
    fi
    
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    log_success "依赖包下载完成"
}

# 集成自定义文件
integrate_custom_files() {
    log_info "集成自定义文件..."
    
    cd "$BUILD_DIR/openwrt"
    
    local custom_files_dir="$REPO_ROOT/firmware-config/custom-files"
    
    if [ -d "$custom_files_dir" ]; then
        log_info "找到自定义文件目录"
        
        mkdir -p files
        cp -r "$custom_files_dir/"* files/ 2>/dev/null || true
        
        local copied_count=$(find files -type f 2>/dev/null | wc -l || echo "0")
        log_success "自定义文件复制完成，共复制 $copied_count 个文件"
    else
        log_info "无自定义文件目录"
    fi
    
    log_success "自定义文件集成完成"
}

# 前置错误检查
pre_build_error_check() {
    log_info "前置错误检查..."
    
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    if [ ! -f ".config" ]; then
        log_error ".config 文件不存在"
        exit 1
    fi
    
    log_info "检查磁盘空间..."
    local available_space=$(df -m "$BUILD_DIR" | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024))
    log_info "可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        log_error "磁盘空间不足 (需要至少5G，当前${available_gb}G)"
        exit 1
    fi
    
    log_success "前置错误检查完成"
}

# 编译前空间检查
pre_build_space_check() {
    log_info "编译前空间检查..."
    
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log_info "/mnt 可用空间: ${available_gb}G"
    
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
    
    if [ -d "$BUILD_DIR" ]; then
        local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "未知"
        echo "构建目录大小: $build_dir_usage"
    fi
}

# 构建固件
build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR/openwrt || handle_error "进入OpenWrt源码目录失败"
    
    log_info "编译固件..."
    
    load_toolchain
    
    local cpu_cores=$(nproc)
    local make_jobs=$cpu_cores
    
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_mem -lt 4096 ]; then
        make_jobs=$((cpu_cores / 2))
        if [ $make_jobs -lt 1 ]; then
            make_jobs=1
        fi
        log_warn "内存较低(${total_mem}MB)，减少并行任务到 $make_jobs"
    fi
    
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
        
        if [ -d "bin/targets" ]; then
            local firmware_count=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
            log_success "生成固件文件: $firmware_count 个"
        fi
    else
        log_error "编译失败，退出代码: $BUILD_EXIT_CODE"
        
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
        
        echo "=== 生成的固件文件 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \;
        
        local firmware_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        log_success "固件文件数: $firmware_files 个"
    else
        log_error "固件目录不存在"
        exit 1
    fi
}

# 清理目录
cleanup() {
    log_info "清理构建目录..."
    
    if [ -d "$BUILD_DIR" ]; then
        log_info "备份配置文件和日志..."
        
        if [ -f "$BUILD_DIR/openwrt/.config" ]; then
            mkdir -p /tmp/openwrt_backup
            cp "$BUILD_DIR/openwrt/.config" "/tmp/openwrt_backup/config_$(date +%Y%m%d_%H%M%S).config"
            log_info "配置文件备份到: /tmp/openwrt_backup/"
        fi
        
        sudo rm -rf $BUILD_DIR || log_warn "清理构建目录失败"
        log_success "构建目录已清理"
    else
        log_info "构建目录不存在，无需清理"
    fi
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
        "save_essential_toolchain")
            save_essential_toolchain
            ;;
        "add_turboacc_support")
            add_turboacc_support
            ;;
        "install_turboacc_packages")
            install_turboacc_packages
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
        "verify_usb_config")
            verify_usb_config
            ;;
        "check_usb_drivers_integrity")
            check_usb_drivers_integrity
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
        "integrate_custom_files")
            integrate_custom_files
            ;;
        "pre_build_error_check")
            pre_build_error_check
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
            echo ""
            echo "  构建命令:"
            echo "    setup_environment, create_build_dir, initialize_build_env"
            echo "    configure_feeds, generate_config, apply_config, download_dependencies"
            echo "    load_toolchain, build_firmware, check_firmware_files, cleanup"
            echo ""
            echo "  功能命令:"
            echo "    add_turboacc_support, install_turboacc_packages"
            echo "    verify_usb_config, check_usb_drivers_integrity"
            echo "    integrate_custom_files, pre_build_error_check"
            echo ""
            echo "  工具链命令:"
            echo "    init_toolchain_dir, check_toolchain_dir"
            echo "    save_essential_toolchain"
            echo ""
            echo "  检查命令:"
            echo "    pre_build_space_check, post_build_space_check"
            echo ""
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
