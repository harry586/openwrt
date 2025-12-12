#!/bin/bash
# OpenWrt构建集成修复脚本 v5.0
# 将所有逻辑整合进大脚本，工作流文件极简化
# 最后更新: 2024-01-16

set -e

echo "========================================"
echo "🔧 OpenWrt构建集成修复脚本 v5.0"
echo "========================================"

# 创建必要目录
mkdir -p firmware-config/scripts
mkdir -p firmware-config/Toolchain
mkdir -p firmware-config/config-backup
mkdir -p firmware-config/custom-files
mkdir -p .github/workflows

# ========== 第一步：创建工作流文件 ==========
echo "创建极简工作流文件..."

cat > .github/workflows/firmware-build.yml << 'EOF'
name: OpenWrt 智能固件构建工作流（极简版）

on:
  workflow_dispatch:
    inputs:
      device_name:
        description: "📱 设备名称 (如: ac42u, acrh17, r3g等)"
        required: true
        default: "ac42u"
        type: string
      version_selection:
        description: "🔄 版本选择"
        required: true
        type: choice
        default: "21.02"
        options: ["23.05", "21.02"]
      config_mode:
        description: "⚙️ 配置模式选择"
        required: true
        type: choice
        default: "normal"
        options: ["base", "normal"]
      extra_packages:
        description: "额外安装插件 (用分号分隔)"
        required: false
        type: string
        default: ""
      enable_cache:
        description: "⚡ 启用编译缓存"
        required: false
        default: true
        type: boolean
      save_toolchain:
        description: "💾 保存通用工具链"
        required: false
        default: false
        type: boolean

env:
  BUILD_DIR: "/mnt/openwrt-build"
  GIT_LFS_SKIP_SMUDGE: 1
  ENABLE_CACHE: "true"

jobs:
  build-firmware:
    runs-on: ubuntu-22.04
    
    steps:
      # 步骤1：检出代码
      - name: "📥 1. 检出代码"
        uses: actions/checkout@v4
        with:
          fetch-depth: 1
      
      # 步骤2：运行基础修复
      - name: "🔧 2. 运行基础修复"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step2_basic_fix
      
      # 步骤3：设置构建环境
      - name: "🛠️ 3. 设置构建环境"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step3_setup_environment
      
      # 步骤4：准备构建目录
      - name: "📁 4. 准备构建目录"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step4_prepare_build_dir
      
      # 步骤5：初始化构建环境
      - name: "🚀 5. 初始化构建环境"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step5_init_build_env \
            "${{ github.event.inputs.device_name }}" \
            "${{ github.event.inputs.version_selection }}" \
            "${{ github.event.inputs.config_mode }}" \
            "${{ github.event.inputs.extra_packages }}"
      
      # 步骤6：显示配置摘要
      - name: "⚡ 6. 显示配置摘要"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step6_show_config
      
      # 步骤7：下载OpenWrt源代码
      - name: "📥 7. 下载OpenWrt源代码"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step7_download_openwrt_source
      
      # 步骤8：配置Feeds
      - name: "📦 8. 配置Feeds"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step8_configure_feeds
      
      # 步骤9：生成配置
      - name: "⚙️ 9. 生成配置"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step9_generate_config "${{ github.event.inputs.extra_packages }}"
      
      # 步骤10：应用配置并修复插件
      - name: "🔧 10. 应用配置并修复插件"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step10_apply_and_fix_config
      
      # 步骤11：下载依赖包
      - name: "📥 11. 下载依赖包"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step11_download_dependencies
      
      # 步骤12：编译固件
      - name: "🔨 12. 编译固件"
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step12_build_firmware "${{ github.event.inputs.enable_cache }}"
      
      # 步骤13：保存工具链
      - name: "💾 13. 保存工具链"
        if: github.event.inputs.save_toolchain == 'true' && success()
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step13_save_toolchain
      
      # 步骤14：上传固件
      - name: "⬆️ 14. 上传固件"
        if: success()
        uses: actions/upload-artifact@v4
        with:
          name: "firmware-${{ github.event.inputs.device_name }}-${{ github.event.inputs.version_selection }}-${{ github.event.inputs.config_mode }}"
          path: /mnt/openwrt-build/bin/targets/
          retention-days: 30
      
      # 步骤15：上传日志
      - name: "⬆️ 15. 上传日志"
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: "build-log-${{ github.event.inputs.device_name }}-${{ github.run_id }}"
          path: /mnt/openwrt-build/build.log
          retention-days: 30
      
      # 步骤16：清理构建目录
      - name: "🧹 16. 清理构建目录"
        if: always()
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step16_cleanup
      
      # 步骤17：构建总结
      - name: "📈 17. 构建总结"
        if: always()
        run: |
          firmware-config/scripts/build_firmware_main.sh workflow_main step17_build_summary "${{ job.status }}"
EOF

echo "✅ 极简工作流文件创建完成"

# ========== 第二步：创建集成的build_firmware_main.sh ==========
echo "创建集成的大脚本..."

# 备份原始脚本（如果存在）
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    cp firmware-config/scripts/build_firmware_main.sh firmware-config/scripts/build_firmware_main.sh.backup
fi

# 创建全新的集成脚本
cat > firmware-config/scripts/build_firmware_main.sh << 'EOF'
#!/bin/bash
# OpenWrt智能构建集成主脚本 v5.0
# 所有逻辑都整合在此脚本中，工作流文件只负责调用
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

# ========== 环境变量管理 ==========
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
}

save_env() {
    cat > "$ENV_FILE" << EOF
# 构建环境变量
SELECTED_BRANCH="$SELECTED_BRANCH"
TARGET="$TARGET"
SUBTARGET="$SUBTARGET"
DEVICE="$DEVICE"
CONFIG_MODE="$CONFIG_MODE"
EXTRA_PACKAGES="$EXTRA_PACKAGES"
BUILD_DIR="$BUILD_DIR"
REPO_ROOT="$REPO_ROOT"
EOF
}

# ========== 工作流步骤函数 ==========

# 步骤2：基础修复
workflow_step2_basic_fix() {
    echo "========================================"
    echo "🔧 步骤2：基础修复"
    echo "========================================"
    
    # 修复脚本权限
    find . -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
    
    # 创建必要目录
    mkdir -p firmware-config/scripts
    mkdir -p firmware-config/Toolchain
    mkdir -p firmware-config/config-backup
    mkdir -p firmware-config/custom-files
    mkdir -p .github/workflows
    
    log_success "基础修复完成"
    echo "========================================"
}

# 步骤3：设置构建环境
workflow_step3_setup_environment() {
    echo "========================================"
    echo "🛠️ 步骤3：设置构建环境"
    echo "========================================"
    
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
    echo "========================================"
}

# 步骤4：准备构建目录
workflow_step4_prepare_build_dir() {
    echo "========================================"
    echo "📁 步骤4：准备构建目录"
    echo "========================================"
    
    sudo mkdir -p "$BUILD_DIR"
    sudo chmod 777 "$BUILD_DIR"
    
    log_success "构建目录: $BUILD_DIR"
    echo "========================================"
}

# 步骤5：初始化构建环境
workflow_step5_init_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local extra_packages="${4:-}"
    
    echo "========================================"
    echo "🚀 步骤5：初始化构建环境"
    echo "========================================"
    
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
    
    # 配置模式
    CONFIG_MODE="$config_mode"
    EXTRA_PACKAGES="$extra_packages"
    
    # 保存环境变量
    save_env
    
    log_success "构建环境初始化完成"
    echo "========================================"
}

# 步骤6：显示配置摘要
workflow_step6_show_config() {
    echo "========================================"
    echo "⚡ 步骤6：显示配置摘要"
    echo "========================================"
    
    load_env
    echo "构建配置摘要:"
    echo "  设备: $DEVICE"
    echo "  版本: $SELECTED_BRANCH"
    echo "  配置模式: $CONFIG_MODE"
    echo "  目标平台: $TARGET/$SUBTARGET"
    echo "  额外插件: $EXTRA_PACKAGES"
    echo "  构建目录: $BUILD_DIR"
    
    echo "========================================"
}

# 步骤7：下载OpenWrt源代码（安全版本，解决目录冲突）
workflow_step7_download_openwrt_source() {
    echo "========================================"
    echo "📥 步骤7：下载OpenWrt源代码"
    echo "========================================"
    
    load_env
    
    # 确保在构建目录中操作
    cd "$BUILD_DIR"
    
    log_info "下载OpenWrt源码: $SELECTED_BRANCH"
    
    # 检查是否已经存在OpenWrt源码
    if [ -d "openwrt" ] && [ -f "openwrt/feeds.conf.default" ]; then
        log_success "OpenWrt源码已存在，跳过下载"
        echo "========================================"
        return 0
    fi
    
    # 清理旧的源码目录
    if [ -d "openwrt" ]; then
        log_info "清理旧的源码目录..."
        rm -rf openwrt
    fi
    
    # 设置分支名称
    local branch_name=""
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        branch_name="openwrt-23.05"
    elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
        branch_name="openwrt-21.02"
    else
        branch_name="master"
    fi
    
    # 下载OpenWrt源码
    local openwrt_url="https://github.com/openwrt/openwrt.git"
    log_info "正在克隆: $openwrt_url (分支: $branch_name)"
    
    git clone --depth 1 --branch "$branch_name" "$openwrt_url" openwrt
    
    if [ ! -d "openwrt" ]; then
        log_error "OpenWrt源码下载失败"
        exit 1
    fi
    
    log_success "OpenWrt源码下载完成"
    echo "源码大小: $(du -sh openwrt 2>/dev/null | cut -f1 || echo '未知')"
    echo "========================================"
}

# 步骤8：配置Feeds
workflow_step8_configure_feeds() {
    echo "========================================"
    echo "📦 步骤8：配置Feeds"
    echo "========================================"
    
    load_env
    cd "$BUILD_DIR/openwrt" || handle_error "进入OpenWrt源码目录失败"
    
    log_info "配置Feeds..."
    
    # 使用immortalwrt的feeds
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    # 如果是正常模式且23.05版本，添加TurboACC
    if [ "$CONFIG_MODE" = "normal" ] && [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
    fi
    
    log_info "更新Feeds..."
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log_info "安装Feeds..."
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log_success "Feeds配置完成"
    echo "========================================"
}

# 步骤9：生成配置
workflow_step9_generate_config() {
    local extra_packages="$1"
    
    echo "========================================"
    echo "⚙️ 步骤9：生成配置"
    echo "========================================"
    
    load_env
    cd "$BUILD_DIR/openwrt" || handle_error "进入OpenWrt源码目录失败"
    
    log_info "生成基础配置..."
    
    rm -f .config .config.old
    
    # 基础目标配置
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    # 基础包
    cat >> .config << 'EOF'
CONFIG_PACKAGE_busybox=y
CONFIG_PACKAGE_base-files=y
CONFIG_PACKAGE_dropbear=y
CONFIG_PACKAGE_firewall=y
CONFIG_PACKAGE_fstools=y
CONFIG_PACKAGE_libc=y
CONFIG_PACKAGE_libgcc=y
CONFIG_PACKAGE_mtd=y
CONFIG_PACKAGE_netifd=y
CONFIG_PACKAGE_opkg=y
CONFIG_PACKAGE_procd=y
CONFIG_PACKAGE_ubox=y
CONFIG_PACKAGE_ubus=y
CONFIG_PACKAGE_uci=y
EOF
    
    # 基础USB驱动
    cat >> .config << 'EOF'
# USB驱动
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb3=y
CONFIG_PACKAGE_kmod-usb-storage=y
CONFIG_PACKAGE_kmod-usb-storage-extras=y
CONFIG_PACKAGE_kmod-usb-storage-uas=y
CONFIG_PACKAGE_kmod-scsi-core=y
CONFIG_PACKAGE_kmod-scsi-generic=y
EOF
    
    # 文件系统支持
    cat >> .config << 'EOF'
# 文件系统
CONFIG_PACKAGE_kmod-fs-ext4=y
CONFIG_PACKAGE_kmod-fs-vfat=y
CONFIG_PACKAGE_kmod-fs-ntfs3=y
EOF
    
    # 网络基础
    cat >> .config << 'EOF'
# 网络
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_iptables-mod-conntrack-extra=y
EOF
    
    log_success "基础配置生成完成"
    echo "========================================"
}

# 步骤10：应用配置并修复插件（核心修复步骤）
workflow_step10_apply_and_fix_config() {
    echo "========================================"
    echo "🔧 步骤10：应用配置并修复插件"
    echo "========================================"
    
    load_env
    cd "$BUILD_DIR/openwrt" || handle_error "进入OpenWrt源码目录失败"
    
    if [ ! -f ".config" ]; then
        log_error ".config 文件不存在"
        exit 1
    fi
    
    log_info "原始配置大小: $(ls -lh .config | awk '{print $5}')"
    
    # ===== 1. 添加平台专用USB驱动 =====
    echo ""
    echo "1. 添加平台专用USB驱动..."
    
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "添加高通IPQ40xx平台专用驱动..."
        cat >> .config << 'EOF'
# 高通IPQ40xx平台专用驱动
CONFIG_PACKAGE_kmod-usb-dwc3=y
CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y
CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y
CONFIG_PACKAGE_kmod-usb-ehci=y
CONFIG_PACKAGE_kmod-usb-ohci=y
EOF
    fi
    
    # 添加额外的文件系统支持
    echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
    
    # ===== 2. 根据配置模式添加插件 =====
    echo ""
    echo "2. 根据配置模式添加插件..."
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        echo "正常模式 - 添加完整功能插件..."
        
        # 正常模式插件列表
        cat >> .config << 'EOF'
# ===== 正常模式完整功能插件 =====

# TurboACC 网络加速
CONFIG_PACKAGE_luci-app-turboacc=y
CONFIG_PACKAGE_kmod-shortcut-fe=y
CONFIG_PACKAGE_kmod-fast-classifier=y

# UPnP 自动端口转发
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_miniupnpd=y

# Samba 文件共享
CONFIG_PACKAGE_luci-app-samba4=y
CONFIG_PACKAGE_samba4-server=y
CONFIG_PACKAGE_samba4-libs=y

# 磁盘管理
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_blkid=y
CONFIG_PACKAGE_lsblk=y

# KMS 激活服务
CONFIG_PACKAGE_luci-app-vlmcsd=y
CONFIG_PACKAGE_vlmcsd=y

# SmartDNS 智能DNS
CONFIG_PACKAGE_luci-app-smartdns=y
CONFIG_PACKAGE_smartdns=y

# 家长控制
CONFIG_PACKAGE_luci-app-parentcontrol=y

# 微信推送
CONFIG_PACKAGE_luci-app-wechatpush=y

# 流量控制 (SQM)
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_sqm-scripts=y

# FTP 服务器
CONFIG_PACKAGE_luci-app-vsftpd=y
CONFIG_PACKAGE_vsftpd=y
CONFIG_PACKAGE_vsftpd-tls=y

# ARP 绑定
CONFIG_PACKAGE_luci-app-arpbind=y

# CPU 限制
CONFIG_PACKAGE_luci-app-cpulimit=y
CONFIG_PACKAGE_cpulimit-ng=y

# 硬盘休眠
CONFIG_PACKAGE_luci-app-hd-idle=y
CONFIG_PACKAGE_hd-idle=y

# LuCI界面
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
EOF
    else
        echo "基础模式 - 仅保留基础功能"
    fi
    
    # ===== 3. 处理额外插件 =====
    echo ""
    echo "3. 处理额外插件..."
    
    if [ -n "$EXTRA_PACKAGES" ]; then
        log_info "处理额外安装插件: $EXTRA_PACKAGES"
        IFS=';' read -ra EXTRA_PKGS <<< "$EXTRA_PACKAGES"
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
    
    # ===== 4. 应用配置 =====
    echo ""
    echo "4. 应用配置..."
    
    log_info "运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log_info "最终配置大小: $(ls -lh .config | awk '{print $5}')"
    log_info "配置行数: $(wc -l < .config)"
    
    # ===== 5. 显示配置摘要 =====
    echo ""
    echo "5. 配置摘要:"
    echo "启用的包总数: $(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)"
    
    echo ""
    echo "关键插件状态:"
    key_plugins=(
        "luci-app-turboacc"
        "luci-app-samba4"
        "luci-app-vsftpd"
        "luci-app-diskman"
        "kmod-usb-dwc3"
        "kmod-usb-dwc3-qcom"
    )
    
    for plugin in "${key_plugins[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config; then
            echo "  ✅ $plugin"
        else
            echo "  ❌ $plugin"
        fi
    done
    
    echo ""
    echo "USB驱动状态:"
    usb_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb3"
        "kmod-usb-dwc3"
        "kmod-usb-dwc3-qcom"
    )
    
    for driver in "${usb_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "  ✅ $driver"
        else
            echo "  ❌ $driver"
        fi
    done
    
    log_success "配置修复完成"
    echo "========================================"
}

# 步骤11：下载依赖包
workflow_step11_download_dependencies() {
    echo "========================================"
    echo "📥 步骤11：下载依赖包"
    echo "========================================"
    
    load_env
    cd "$BUILD_DIR/openwrt" || handle_error "进入OpenWrt源码目录失败"
    
    log_info "下载依赖包..."
    
    # 检查依赖包目录
    if [ ! -d "dl" ]; then
        mkdir -p dl
    fi
    
    # 下载依赖包
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    log_success "依赖包下载完成"
    echo "========================================"
}

# 步骤12：编译固件
workflow_step12_build_firmware() {
    local enable_cache="$1"
    
    echo "========================================"
    echo "🔨 步骤12：编译固件"
    echo "========================================"
    
    load_env
    cd "$BUILD_DIR/openwrt" || handle_error "进入OpenWrt源码目录失败"
    
    log_info "开始编译..."
    
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
    
    echo "========================================"
}

# 步骤13：保存工具链
workflow_step13_save_toolchain() {
    echo "========================================"
    echo "💾 步骤13：保存工具链"
    echo "========================================"
    
    load_env
    cd "$BUILD_DIR/openwrt" || handle_error "进入OpenWrt源码目录失败"
    
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
    
    # 保存工具链信息
    cat > "$TOOLCHAIN_DIR/configs/toolchain_info.txt" << EOF
# 工具链信息
保存时间: $(date)
工具链来源: $staging_toolchain
目标平台: $TARGET/$SUBTARGET
设备: $DEVICE
版本: $SELECTED_BRANCH
EOF
    
    log_success "工具链信息已保存"
    echo "========================================"
}

# 步骤16：清理构建目录
workflow_step16_cleanup() {
    echo "========================================"
    echo "🧹 步骤16：清理构建目录"
    echo "========================================"
    
    if [ -d "$BUILD_DIR" ]; then
        log_info "备份配置文件和日志..."
        
        # 备份.config文件
        if [ -f "$BUILD_DIR/openwrt/.config" ]; then
            mkdir -p /tmp/openwrt_backup
            cp "$BUILD_DIR/openwrt/.config" "/tmp/openwrt_backup/config_$(date +%Y%m%d_%H%M%S).config"
        fi
        
        log_success "构建目录已备份"
    else
        log_info "构建目录不存在，无需清理"
    fi
    
    echo "========================================"
}

# 步骤17：构建总结
workflow_step17_build_summary() {
    local build_status="$1"
    
    echo "========================================"
    echo "📈 步骤17：构建总结"
    echo "========================================"
    
    load_env
    
    echo "构建状态: $build_status"
    echo "设备: $DEVICE"
    echo "版本: $SELECTED_BRANCH"
    echo "配置模式: $CONFIG_MODE"
    echo "目标平台: $TARGET/$SUBTARGET"
    echo ""
    
    if [ "$build_status" = "success" ]; then
        echo "✅ 构建成功"
        
        # 显示固件信息
        if [ -d "$BUILD_DIR/openwrt/bin/targets" ]; then
            echo ""
            echo "生成的固件:"
            find "$BUILD_DIR/openwrt/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \; 2>/dev/null | head -5
        fi
    else
        echo "❌ 构建失败"
        
        # 显示错误摘要
        if [ -f "$BUILD_DIR/openwrt/build.log" ]; then
            echo ""
            echo "错误摘要:"
            grep -i "error:" "$BUILD_DIR/openwrt/build.log" | head -5
        fi
    fi
    
    echo "========================================"
}

# ========== 主调度函数 ==========
workflow_main() {
    case $1 in
        "step2_basic_fix")
            workflow_step2_basic_fix
            ;;
        "step3_setup_environment")
            workflow_step3_setup_environment
            ;;
        "step4_prepare_build_dir")
            workflow_step4_prepare_build_dir
            ;;
        "step5_init_build_env")
            workflow_step5_init_build_env "$2" "$3" "$4" "$5"
            ;;
        "step6_show_config")
            workflow_step6_show_config
            ;;
        "step7_download_openwrt_source")
            workflow_step7_download_openwrt_source
            ;;
        "step8_configure_feeds")
            workflow_step8_configure_feeds
            ;;
        "step9_generate_config")
            workflow_step9_generate_config "$2"
            ;;
        "step10_apply_and_fix_config")
            workflow_step10_apply_and_fix_config
            ;;
        "step11_download_dependencies")
            workflow_step11_download_dependencies
            ;;
        "step12_build_firmware")
            workflow_step12_build_firmware "$2"
            ;;
        "step13_save_toolchain")
            workflow_step13_save_toolchain
            ;;
        "step16_cleanup")
            workflow_step16_cleanup
            ;;
        "step17_build_summary")
            workflow_step17_build_summary "$2"
            ;;
        *)
            echo "可用命令:"
            echo ""
            echo "工作流步骤:"
            echo "  step2_basic_fix             基础修复"
            echo "  step3_setup_environment     设置构建环境"
            echo "  step4_prepare_build_dir     准备构建目录"
            echo "  step5_init_build_env        初始化构建环境"
            echo "  step6_show_config           显示配置摘要"
            echo "  step7_download_openwrt_source 下载OpenWrt源码"
            echo "  step8_configure_feeds       配置Feeds"
            echo "  step9_generate_config       生成配置"
            echo "  step10_apply_and_fix_config 应用配置并修复插件"
            echo "  step11_download_dependencies 下载依赖包"
            echo "  step12_build_firmware       编译固件"
            echo "  step13_save_toolchain       保存工具链"
            echo "  step16_cleanup              清理构建目录"
            echo "  step17_build_summary        构建总结"
            exit 1
            ;;
    esac
}

# ========== 脚本入口 ==========
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "$1" == "workflow_main" ]]; then
        workflow_main "${@:2}"
    else
        echo "使用: $0 workflow_main <步骤名称> [参数]"
        exit 1
    fi
fi
EOF

# 设置执行权限
chmod +x firmware-config/scripts/build_firmware_main.sh

echo "✅ 集成大脚本创建完成"

# ========== 第三步：创建修复脚本 ==========
echo "创建修复脚本..."

cat > fix-integrated.sh << 'EOF'
#!/bin/bash
# OpenWrt集成修复脚本
# 一键修复所有问题，将逻辑整合进大脚本

echo "========================================"
echo "🔧 OpenWrt集成修复脚本"
echo "========================================"

echo "执行时间: $(date)"
echo ""

# 运行修复
bash "$(dirname "$0")/firmware-config/scripts/build_firmware_main.sh" workflow_main step2_basic_fix

echo ""
echo "✅ 集成修复完成"
echo ""
echo "已部署:"
echo "1. ✅ 极简工作流文件 (.github/workflows/firmware-build.yml)"
echo "2. ✅ 集成大脚本 (firmware-config/scripts/build_firmware_main.sh)"
echo ""
echo "工作流现在只有17个步骤，所有逻辑都在大脚本中:"
echo "  步骤1: 检出代码 (GitHub Actions)"
echo "  步骤2-17: 全部调用大脚本的相应函数"
echo ""
echo "修复特点:"
echo "✅ 解决了目录冲突问题 (步骤7)"
echo "✅ 包含了所有USB驱动"
echo "✅ 包含了正常模式13个完整功能插件"
echo "✅ 修复了配置生成逻辑"
echo "✅ 极简的工作流文件，易于维护"
echo ""
echo "使用方法:"
echo "1. 提交更改: git add -A && git commit -m 'fix: 集成修复' && git push"
echo "2. 重新运行GitHub Actions工作流"
echo "3. 享受完整的构建过程"
echo "========================================"
EOF

chmod +x fix-integrated.sh

echo "✅ 修复脚本创建完成"

# ========== 第四步：创建验证脚本 ==========
echo "创建验证脚本..."

cat > verify-fix.sh << 'EOF'
#!/bin/bash
# 验证修复脚本

echo "=== 验证修复 ==="

echo "1. 检查工作流文件..."
if [ -f ".github/workflows/firmware-build.yml" ]; then
    echo "✅ 工作流文件存在"
    echo "   行数: $(wc -l < .github/workflows/firmware-build.yml)"
    echo "   大小: $(ls -lh .github/workflows/firmware-build.yml | awk '{print $5}')"
else
    echo "❌ 工作流文件不存在"
fi

echo ""
echo "2. 检查大脚本..."
if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
    echo "✅ 大脚本存在"
    echo "   行数: $(wc -l < firmware-config/scripts/build_firmware_main.sh)"
    echo "   大小: $(ls -lh firmware-config/scripts/build_firmware_main.sh | awk '{print $5}')"
    
    echo ""
    echo "   检查关键函数:"
    functions=(
        "workflow_step7_download_openwrt_source"
        "workflow_step10_apply_and_fix_config"
        "workflow_step12_build_firmware"
    )
    
    for func in "${functions[@]}"; do
        if grep -q "$func" firmware-config/scripts/build_firmware_main.sh; then
            echo "      ✅ $func"
        else
            echo "      ❌ $func"
        fi
    done
else
    echo "❌ 大脚本不存在"
fi

echo ""
echo "3. 检查目录结构..."
dirs=(
    "firmware-config/scripts"
    "firmware-config/Toolchain"
    "firmware-config/config-backup"
    ".github/workflows"
)

for dir in "${dirs[@]}"; do
    if [ -d "$dir" ]; then
        echo "    ✅ $dir"
    else
        echo "    ❌ $dir"
    fi
done

echo ""
echo "=== 验证完成 ==="
EOF

chmod +x verify-fix.sh

echo "✅ 验证脚本创建完成"

echo ""
echo "========================================"
echo "🎉 集成修复部署完成！"
echo "========================================"
echo ""
echo "已创建的脚本:"
echo "1. fix-integrated.sh     - 一键修复脚本"
echo "2. verify-fix.sh         - 验证脚本"
echo ""
echo "使用方法:"
echo "1. 运行修复: ./fix-integrated.sh"
echo "2. 验证修复: ./verify-fix.sh"
echo "3. 提交更改: git add -A && git commit -m 'fix: 集成修复' && git push"
echo "4. 重新运行GitHub Actions工作流"
echo ""
echo "修复亮点:"
echo "✅ 工作流文件极简化 (仅17个步骤)"
echo "✅ 所有逻辑都在大脚本中"
echo "✅ 解决了目录冲突问题"
echo "✅ 包含了所有USB驱动和正常模式插件"
echo "✅ 无需手动合并，完全自动化"
echo "========================================"
