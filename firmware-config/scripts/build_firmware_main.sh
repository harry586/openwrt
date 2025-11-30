#!/bin/bash
set -e

# 全局变量
BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
CUSTOM_FILES_DIR="./firmware-config/custom-files"

# 日志函数
log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

# 错误处理函数
handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 保存环境变量到文件
save_env() {
    mkdir -p $BUILD_DIR
    echo "#!/bin/bash" > $ENV_FILE
    echo "export SELECTED_REPO_URL=\"$SELECTED_REPO_URL\"" >> $ENV_FILE
    echo "export SELECTED_BRANCH=\"$SELECTED_BRANCH\"" >> $ENV_FILE
    echo "export TARGET=\"$TARGET\"" >> $ENV_FILE
    echo "export SUBTARGET=\"$SUBTARGET\"" >> $ENV_FILE
    echo "export DEVICE=\"$DEVICE\"" >> $ENV_FILE
    echo "export CONFIG_MODE=\"$CONFIG_MODE\"" >> $ENV_FILE
    chmod +x $ENV_FILE
}

# 加载环境变量
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
}

# 步骤1: 设置编译环境
setup_environment() {
    log "=== 安装编译依赖包 ==="
    sudo apt-get update || handle_error "apt-get update失败"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip \
        zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath \
        libpython3-dev python3 python3-dev python3-pip python3-setuptools \
        python3-yaml xsltproc zip subversion ninja-build automake autoconf \
        libtool pkg-config help2man texinfo aria2 liblz4-dev zstd \
        libcurl4-openssl-dev groff texlive texinfo cmake || handle_error "安装依赖包失败"
    log "✅ 编译环境设置完成"
}

# 步骤2: 创建构建目录
create_build_dir() {
    log "=== 创建构建目录 ==="
    sudo mkdir -p $BUILD_DIR || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER $BUILD_DIR || handle_error "修改目录所有者失败"
    sudo chmod -R 755 $BUILD_DIR || handle_error "修改目录权限失败"
    log "✅ 构建目录创建完成"
}

# 步骤3: 初始化构建环境（合并版本选择、设备配置和克隆源码）
initialize_build_env() {
    local device_name=$1
    local version_selection=$2
    local config_mode=$3
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    # 版本选择
    log "=== 版本选择 ==="
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-23.05"
    else
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-21.02"
    fi
    log "✅ 版本选择完成: $SELECTED_BRANCH"
    
    # 设备配置
    log "=== 设备配置 ==="
    case "$device_name" in
        "ac42u"|"acrh17")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-ac42u"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            TARGET="ramips"
            SUBTARGET="mt76x8"
            DEVICE="xiaomi_mi-router-4a-gigabit"
            ;;
        "mi_router_3g"|"r3g")
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
    
    CONFIG_MODE="$config_mode"
    
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    
    # 保存环境变量
    save_env
    
    # 设置GitHub环境变量
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    
    # 克隆源码
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    # 清理目录
    sudo rm -rf ./* ./.git* 2>/dev/null || true
    
    # 克隆源码
    git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . || handle_error "克隆源码失败"
    log "✅ 源码克隆完成"
}

# 步骤4: 添加 TurboACC 支持
add_turboacc_support() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 添加 TurboACC 支持 ==="
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "🔧 为正常模式添加 TurboACC 支持"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log "🔧 为 23.05 添加 TurboACC 支持"
            echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
            log "✅ TurboACC feed 添加完成"
        else
            log "ℹ️  21.02 版本已内置 TurboACC，无需额外添加"
        fi
    else
        log "ℹ️  基础模式不添加 TurboACC 支持"
    fi
}

# 步骤5: 添加文件传输插件支持（修改为使用官方源）
add_filetransfer_support() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 添加文件传输插件支持 ==="
    
    # 所有版本都使用官方源的 luci-app-filetransfer
    log "🔧 所有版本使用官方源的 luci-app-filetransfer"
    
    # 确保 feeds.conf.default 包含基本 feeds
    if ! grep -q "src-git luci" feeds.conf.default; then
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            FEEDS_BRANCH="openwrt-23.05"
        else
            FEEDS_BRANCH="openwrt-21.02"
        fi
        echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    fi
    
    log "✅ 文件传输插件支持添加完成（使用官方源）"
}

# 步骤6: 配置Feeds
configure_feeds() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 配置Feeds ==="
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    # 确保 feeds.conf.default 包含基本 feeds
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    # 如果是 23.05 且正常模式，添加 turboacc feed
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
    fi
    
    # 更新和安装所有 feeds
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log "✅ Feeds配置完成"
}

# 步骤7: 安装 TurboACC 包
install_turboacc_packages() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 安装 TurboACC 包 ==="
    
    # 更新 turboacc feed
    ./scripts/feeds update turboacc || handle_error "更新turboacc feed失败"
    
    # 安装 turboacc 相关包
    ./scripts/feeds install -p turboacc luci-app-turboacc || handle_error "安装luci-app-turboacc失败"
    ./scripts/feeds install -p turboacc kmod-shortcut-fe || handle_error "安装kmod-shortcut-fe失败"
    ./scripts/feeds install -p turboacc kmod-fast-classifier || handle_error "安装kmod-fast-classifier失败"
    
    log "✅ TurboACC 包安装完成"
}

# 步骤8: 安装文件传输插件包（增强版本兼容性）
install_filetransfer_packages() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 安装文件传输插件包 ==="
    
    # 更新 luci feed
    ./scripts/feeds update luci || handle_error "更新luci feed失败"
    
    # 尝试安装官方源的文件传输插件
    log "🔧 尝试安装官方源 luci-app-filetransfer"
    if ./scripts/feeds install -p luci luci-app-filetransfer 2>/dev/null; then
        log "✅ 成功安装官方源 luci-app-filetransfer"
    else
        log "⚠️ 官方源安装失败，尝试备用方案"
        
        # 🚨 关键修复：23.05版本备用安装方案
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log "🔧 23.05版本使用备用文件传输插件方案"
            
            # 检查是否存在文件传输插件目录
            if [ -d "feeds/luci/applications/luci-app-filetransfer" ]; then
                log "✅ 找到luci-app-filetransfer目录，手动启用"
                echo "CONFIG_PACKAGE_luci-app-filetransfer=y" >> .config
            else
                log "🔧 创建临时的文件传输插件配置"
                # 即使没有插件包，也确保配置中存在
                echo "CONFIG_PACKAGE_luci-app-filetransfer=y" >> .config
            fi
        else
            # 21.02版本应该能正常安装
            log "🔧 21.02版本重新尝试安装"
            ./scripts/feeds install -p luci luci-app-filetransfer || log "⚠️ 21.02版本安装也失败"
        fi
    fi
    
    # 尝试安装中文语言包
    if ./scripts/feeds install -p luci luci-i18n-filetransfer-zh-cn 2>/dev/null; then
        log "✅ 安装luci-i18n-filetransfer-zh-cn成功"
        echo "CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y" >> .config
    else
        log "⚠️ 安装luci-i18n-filetransfer-zh-cn失败"
        echo "# CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn is not set" >> .config
    fi
    
    log "✅ 文件传输插件包安装完成"
}

# 步骤9: 编译前空间检查
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
}

# 步骤10: 智能配置生成（USB完全修复通用版）
generate_config() {
    local extra_packages=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 智能配置生成系统（USB完全修复通用版）==="
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    
    rm -f .config .config.old
    
    # 创建基础配置
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    # 🚨 关键修复：彻底禁用 passwall 和 rclone 系列插件
    log "🔧 彻底禁用 passwall 和 rclone 系列插件"
    
    echo "# ==========================================" >> .config
    echo "# 🚫 强制禁用 passwall 系列插件" >> .config
    echo "# ==========================================" >> .config
    
    PASSWALL_PLUGINS=(
        "luci-app-passwall"
        "luci-app-passwall_INCLUDE_Haproxy"
        "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client"
        "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server"
        "luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client"
        "luci-app-passwall_INCLUDE_Simple_Obfs"
        "luci-app-passwall_INCLUDE_SingBox"
        "luci-app-passwall_INCLUDE_Trojan_Plus"
        "luci-app-passwall_INCLUDE_V2ray_Geoview"
        "luci-app-passwall_INCLUDE_V2ray_Plugin"
        "luci-app-passwall_INCLUDE_Xray"
        "luci-i18n-passwall-zh-cn"
    )
    
    for plugin in "${PASSWALL_PLUGINS[@]}"; do
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done
    
    echo "# ==========================================" >> .config
    echo "# 🚫 强制禁用 rclone 系列插件" >> .config
    echo "# ==========================================" >> .config
    
    RCLONE_PLUGINS=(
        "luci-app-rclone"
        "luci-app-rclone_INCLUDE_rclone-webui"
        "luci-app-rclone_INCLUDE_rclone-ng"
        "luci-i18n-rclone-zh-cn"
        "rclone"
        "rclone-ng"
        "rclone-webui"
    )
    
    for plugin in "${RCLONE_PLUGINS[@]}"; do
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done
    
    # 基础系统组件
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
    echo "CONFIG_PACKAGE_ubusd=y" >> .config
    echo "CONFIG_PACKAGE_uci=y" >> .config
    echo "CONFIG_PACKAGE_uclient-fetch=y" >> .config
    echo "CONFIG_PACKAGE_usign=y" >> .config
    
    # DNS配置
    echo "# CONFIG_PACKAGE_dnsmasq is not set" >> .config
    echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcp=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dnssec=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_ipset=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_conntrack=y" >> .config
    
    # 无线驱动
    echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
    echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
    echo "CONFIG_PACKAGE_ath10k-firmware-qca988x=y" >> .config
    echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config
    
    # 网络工具
    echo "CONFIG_PACKAGE_iptables=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-ipopt=y" >> .config
    echo "CONFIG_PACKAGE_ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config
    
    # ============================================================================
    # 🚨 USB 完全修复通用配置 - 适用于所有平台和设备
    # ============================================================================
    log "=== 🚨 USB 完全修复通用配置 - 开始 ==="
    
    # USB核心驱动
    echo "# 🟢 USB 核心驱动 - 基础必须" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
    
    # USB主机控制器驱动
    echo "# 🟢 USB 主机控制器驱动 - 通用支持" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ehci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-uhci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
    
    # 平台专用USB控制器驱动
    echo "# 🟡 平台专用USB控制器驱动 - 按平台启用" >> .config
    
    # IPQ40xx 专用USB驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        log "🚨 关键修复：IPQ40xx 专用USB控制器驱动"
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
    fi
    
    # MT76xx/雷凌 平台USB驱动
    if [ "$TARGET" = "ramips" ]; then
        log "🚨 关键修复：MT76xx/雷凌 平台USB控制器驱动"
        echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
    fi
    
    # USB 存储驱动
    echo "# 🟢 USB 存储驱动 - 核心功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    
    # SCSI 支持
    echo "# 🟢 SCSI 支持 - 硬盘和U盘必需" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> .config
    
    # 文件系统支持
    echo "# 🟢 文件系统支持 - 完整文件系统兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-autofs4=y" >> .config
    
    # 🚨 关键修复：NTFS配置 - 避免23.05版本冲突
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本NTFS配置优化"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        # 🚨 关键：禁用所有ntfs-3g相关包，避免配置冲突
        echo "# CONFIG_PACKAGE_ntfs-3g is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g-utils is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs3-mount is not set" >> .config
    else
        log "🔧 21.02版本NTFS配置"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        echo "CONFIG_PACKAGE_ntfs3-mount=y" >> .config
    fi
    
    # 编码支持
    echo "# 🟢 编码支持 - 多语言文件名兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp437=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-iso8859-1=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp936=y" >> .config
    
    # 自动挂载工具
    echo "# 🟢 自动挂载工具 - 即插即用支持" >> .config
    echo "CONFIG_PACKAGE_block-mount=y" >> .config
    echo "CONFIG_PACKAGE_automount=y" >> .config
    
    # USB 工具和热插拔支持
    echo "# 🟢 USB 工具和热插拔支持 - 设备管理" >> .config
    echo "CONFIG_PACKAGE_usbutils=y" >> .config
    echo "CONFIG_PACKAGE_lsusb=y" >> .config
    echo "CONFIG_PACKAGE_udev=y" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 完成 ==="
    
    # 基础中文语言包
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config
    
    # 🚨 关键修复：文件传输插件配置（所有版本都启用）
    echo "CONFIG_PACKAGE_luci-app-filetransfer=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y" >> .config
    
    # 配置模式选择
    if [ "$CONFIG_MODE" = "base" ]; then
        log "🔧 使用基础模式 (最小化，用于测试编译)"
        # 基础模式明确禁用 TurboACC
        echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> .config
        echo "# CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn is not set" >> .config
    else
        log "🔧 使用正常模式 (完整功能)"
        # 正常模式插件配置
        NORMAL_PLUGINS=(
          "CONFIG_PACKAGE_luci-app-turboacc=y"
          "CONFIG_PACKAGE_kmod-shortcut-fe=y"
          "CONFIG_PACKAGE_kmod-fast-classifier=y"
          "CONFIG_PACKAGE_luci-app-upnp=y"
          "CONFIG_PACKAGE_miniupnpd=y"
          "CONFIG_PACKAGE_vsftpd=y"
          "CONFIG_PACKAGE_luci-app-vsftpd=y"
          "CONFIG_PACKAGE_luci-app-arpbind=y"
          "CONFIG_PACKAGE_luci-app-cpulimit=y"
          "CONFIG_PACKAGE_samba4-server=y"
          "CONFIG_PACKAGE_luci-app-samba4=y"
          "CONFIG_PACKAGE_luci-app-wechatpush=y"
          "CONFIG_PACKAGE_sqm-scripts=y"
          "CONFIG_PACKAGE_luci-app-sqm=y"
          "CONFIG_PACKAGE_luci-app-hd-idle=y"
          "CONFIG_PACKAGE_luci-app-diskman=y"
          "CONFIG_PACKAGE_luci-app-accesscontrol=y"
          "CONFIG_PACKAGE_vlmcsd=y"
          "CONFIG_PACKAGE_luci-app-vlmcsd=y"
          "CONFIG_PACKAGE_smartdns=y"
          "CONFIG_PACKAGE_luci-app-smartdns=y"
        )
        
        for plugin in "${NORMAL_PLUGINS[@]}"; do
            echo "$plugin" >> .config
        done
        
        # 添加中文语言包
        if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            NORMAL_I18N_PLUGINS=(
                "CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-arpbind-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-cpulimit-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-hd-idle-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-accesscontrol-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y"
                "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y"
            )
            
            for i18n_plugin in "${NORMAL_I18N_PLUGINS[@]}"; do
                echo "$i18n_plugin" >> .config
            done
        fi
    fi
    
    # 处理额外安装插件
    if [ -n "$extra_packages" ]; then
        log "🔧 处理额外安装插件: $extra_packages"
        # 将顿号替换为分号，以便后续处理
        extra_packages=$(echo "$extra_packages" | sed 's/、/;/g')
        IFS=';' read -ra EXTRA_PKGS <<< "$extra_packages"
        for pkg_cmd in "${EXTRA_PKGS[@]}"; do
            if [ -n "$pkg_cmd" ]; then
                pkg_cmd_clean=$(echo "$pkg_cmd" | xargs)
                if [[ "$pkg_cmd_clean" == +* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log "启用插件: $pkg_name"
                    echo "CONFIG_PACKAGE_${pkg_name}=y" >> .config
                elif [[ "$pkg_cmd_clean" == -* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log "禁用插件: $pkg_name"
                    echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> .config
                else
                    log "启用插件: $pkg_cmd_clean"
                    echo "CONFIG_PACKAGE_${pkg_cmd_clean}=y" >> .config
                fi
            fi
        done
    fi
    
    log "✅ 智能配置生成完成"
}

# 步骤11: 验证USB配置
verify_usb_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 详细验证USB和存储配置 ==="
    
    echo "1. 🟢 USB核心模块:"
    grep "CONFIG_PACKAGE_kmod-usb-core" .config | grep "=y" && echo "✅ USB核心" || echo "❌ 缺少USB核心"
    
    echo "2. 🟢 USB控制器:"
    grep -E "CONFIG_PACKAGE_kmod-usb2|CONFIG_PACKAGE_kmod-usb3|CONFIG_PACKAGE_kmod-usb-ehci|CONFIG_PACKAGE_kmod-usb-ohci" .config | grep "=y" || echo "❌ 缺少USB控制器"
    
    echo "3. 🚨 平台专用USB控制器:"
    grep -E "CONFIG_PACKAGE_kmod-usb-dwc3|CONFIG_PACKAGE_kmod-usb-dwc3-qcom|CONFIG_PACKAGE_kmod-phy-qcom-dwc3" .config | grep "=y" || echo "ℹ️  无平台专用USB控制器"
    
    echo "4. 🟢 USB存储:"
    grep "CONFIG_PACKAGE_kmod-usb-storage" .config | grep "=y" || echo "❌ 缺少USB存储"
    
    log "=== 🚨 USB配置验证完成 ==="
}

# 步骤12: 应用配置（增强插件状态显示）
apply_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 应用配置 ==="
    
    # 显示当前配置摘要
    log "=== 配置摘要 ==="
    log "启用的包数量: $(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)"
    log "文件传输插件状态: $(grep "CONFIG_PACKAGE_luci-app-filetransfer" .config)"
    log "USB核心驱动状态: $(grep "CONFIG_PACKAGE_kmod-usb-core" .config)"
    log "USB存储状态: $(grep "CONFIG_PACKAGE_kmod-usb-storage" .config)"
    
    # 🚨 关键修复：23.05版本需要先清理可能的配置冲突
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本配置预处理"
        # 确保ntfs-3g相关配置被正确禁用
        sed -i 's/CONFIG_PACKAGE_ntfs-3g=y/# CONFIG_PACKAGE_ntfs-3g is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs-3g-utils=y/# CONFIG_PACKAGE_ntfs-3g-utils is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs3-mount=y/# CONFIG_PACKAGE_ntfs3-mount is not set/g' .config
    fi
    
    make defconfig || handle_error "应用配置失败"
    
    # 显示应用后的配置
    log "=== 应用配置后状态 ==="
    log "最终启用的包数量: $(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)"
    
    # 🚨 增强：显示所有启用的插件状态
    log "=== ✅ 所有启用的插件列表 ==="
    grep "^CONFIG_PACKAGE_luci-app-.*=y$" .config | sed 's/CONFIG_PACKAGE_//;s/=y//' | while read plugin; do
        log "  ✅ $plugin"
    done
    
    # 显示关键插件状态
    log "=== 关键插件状态 ==="
    grep -E "CONFIG_PACKAGE_luci-app-filetransfer|CONFIG_PACKAGE_luci-app-turboacc|CONFIG_PACKAGE_luci-app-samba4" .config | head -10
    
    log "✅ 配置应用完成"
}

# 步骤13: 修复网络环境
fix_network() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 修复网络环境 ==="
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    log "✅ 网络环境修复完成"
}

# 步骤14: 下载依赖包
download_dependencies() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 下载依赖包 ==="
    make -j1 download || handle_error "下载依赖包失败"
    log "✅ 依赖包下载完成"
}

# 步骤15: 处理自定义文件（完全重写搜索逻辑）
process_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🎯 增强版自定义文件处理 ==="
    
    # 创建自定义文件目录
    mkdir -p $BUILD_DIR/custom_files_log
    CUSTOM_LOG="$BUILD_DIR/custom_files_log/custom_files.log"
    
    echo "🎯 增强版自定义文件处理报告 - $(date)" > $CUSTOM_LOG
    echo "==========================================" >> $CUSTOM_LOG
    
    # 🚨 关键修复：多层级深度搜索自定义文件目录
    log "🔍 开始深度搜索自定义文件目录..."
    
    # 定义搜索的根目录（从工作目录开始）
    SEARCH_ROOTS=(
        "."
        "./firmware-config"
        "./config"
        "./custom"
        "./files"
    )
    
    # 定义可能的目录名称模式
    SEARCH_PATTERNS=(
        "custom-files"
        "custom_files" 
        "files"
        "custom"
        "ipk"
        "scripts"
        "user"
    )
    
    CUSTOM_FILES_DIR_FOUND=""
    MAX_DEPTH=4  # 最大搜索深度
    
    # 🎯 深度优先搜索算法
    for root_dir in "${SEARCH_ROOTS[@]}"; do
        if [ ! -d "$root_dir" ]; then
            continue
        fi
        
        log "🔍 在 $root_dir 中搜索..."
        echo "搜索根目录: $root_dir" >> $CUSTOM_LOG
        
        for pattern in "${SEARCH_PATTERNS[@]}"; do
            # 使用find命令进行深度搜索
            found_dirs=$(find "$root_dir" -maxdepth $MAX_DEPTH -type d -iname "*$pattern*" 2>/dev/null | grep -v "log\|tmp\|temp\|backup")
            
            for found_dir in $found_dirs; do
                # 🚨 关键检查：目录必须包含文件（不是空目录）
                file_count=$(find "$found_dir" -maxdepth 2 -type f \( -name "*.ipk" -o -name "*.sh" \) 2>/dev/null | wc -l)
                
                if [ $file_count -gt 0 ]; then
                    CUSTOM_FILES_DIR_FOUND="$found_dir"
                    log "🎯 找到有效自定义文件目录: $CUSTOM_FILES_DIR_FOUND"
                    log "📊 目录包含文件数量: $file_count"
                    echo "✅ 找到有效目录: $CUSTOM_FILES_DIR_FOUND (包含 $file_count 个文件)" >> $CUSTOM_LOG
                    break 3  # 跳出三层循环
                else
                    log "🔍 检查目录: $found_dir (无ipk/sh文件)"
                    echo "ℹ️  检查目录: $found_dir (无ipk/sh文件)" >> $CUSTOM_LOG
                fi
            done
        done
    done
    
    if [ -n "$CUSTOM_FILES_DIR_FOUND" ]; then
        CUSTOM_FILES_DIR="$CUSTOM_FILES_DIR_FOUND"
        log "🎯 使用自定义文件目录: $CUSTOM_FILES_DIR"
        echo "最终使用目录: $CUSTOM_FILES_DIR" >> $CUSTOM_LOG
        
        # 📦 处理IPK文件
        log "📦 搜索IPK文件..."
        IPK_FILES=$(find "$CUSTOM_FILES_DIR" -name "*.ipk" -type f 2>/dev/null)
        
        if [ -n "$IPK_FILES" ]; then
            log "✅ 发现 $(echo "$IPK_FILES" | wc -l) 个IPK文件"
            echo "发现的IPK文件:" >> $CUSTOM_LOG
            echo "$IPK_FILES" >> $CUSTOM_LOG
            
            # 创建IPK存放目录
            IPK_DEST_DIR="$BUILD_DIR/packages/custom"
            mkdir -p "$IPK_DEST_DIR"
            
            # 复制IPK文件
            ipk_count=0
            for ipk_file in $IPK_FILES; do
                if [ -f "$ipk_file" ]; then
                    ipk_name=$(basename "$ipk_file")
                    log "📦 复制IPK: $ipk_name"
                    cp "$ipk_file" "$IPK_DEST_DIR/"
                    echo "✅ 复制IPK: $ipk_name 到 $IPK_DEST_DIR/" >> $CUSTOM_LOG
                    ipk_count=$((ipk_count + 1))
                fi
            done
            log "🎯 成功复制 $ipk_count 个IPK文件"
        else
            log "ℹ️ 未找到IPK文件"
            echo "未找到IPK文件" >> $CUSTOM_LOG
        fi
        
        # 📜 处理Shell脚本
        log "📜 搜索Shell脚本..."
        SH_FILES=$(find "$CUSTOM_FILES_DIR" -name "*.sh" -type f 2>/dev/null)
        
        if [ -n "$SH_FILES" ]; then
            log "✅ 发现 $(echo "$SH_FILES" | wc -l) 个Shell脚本"
            echo "发现的Shell脚本:" >> $CUSTOM_LOG
            echo "$SH_FILES" >> $CUSTOM_LOG
            
            # 创建脚本存放目录
            SCRIPT_DEST_DIR="$BUILD_DIR/files/etc/uci-defaults"
            mkdir -p "$SCRIPT_DEST_DIR"
            
            # 复制并设置执行权限
            script_count=0
            for sh_file in $SH_FILES; do
                if [ -f "$sh_file" ]; then
                    sh_name=$(basename "$sh_file")
                    log "📜 处理脚本: $sh_name"
                    cp "$sh_file" "$SCRIPT_DEST_DIR/"
                    chmod +x "$SCRIPT_DEST_DIR/$sh_name"
                    echo "✅ 复制脚本: $sh_name 到 $SCRIPT_DEST_DIR/" >> $CUSTOM_LOG
                    script_count=$((script_count + 1))
                fi
            done
            log "🎯 成功处理 $script_count 个Shell脚本"
        else
            log "ℹ️ 未找到Shell脚本"
            echo "未找到Shell脚本" >> $CUSTOM_LOG
        fi
        
        # 📁 详细文件列表
        log "📁 生成详细文件列表..."
        echo "自定义文件目录完整内容:" >> $CUSTOM_LOG
        find "$CUSTOM_FILES_DIR" -type f 2>/dev/null >> $CUSTOM_LOG
        
    else
        log "🔍 深度搜索报告:"
        echo "深度搜索报告:" >> $CUSTOM_LOG
        echo "搜索根目录: ${SEARCH_ROOTS[*]}" >> $CUSTOM_LOG
        echo "搜索模式: ${SEARCH_PATTERNS[*]}" >> $CUSTOM_LOG
        echo "最大深度: $MAX_DEPTH" >> $CUSTOM_LOG
        
        # 🎯 显示所有可能的目录
        log "所有可能的目录:"
        echo "所有发现的目录:" >> $CUSTOM_LOG
        find . -type d \( -iname "*custom*" -o -iname "*file*" -o -iname "*firmware*" -o -iname "*ipk*" -o -iname "*script*" \) 2>/dev/null | grep -v "log\|tmp\|temp\|backup" | head -20 >> $CUSTOM_LOG
        
        # 🎯 显示目录结构
        log "当前目录结构:"
        echo "当前目录结构 (前3层):" >> $CUSTOM_LOG
        find . -maxdepth 3 -type d 2>/dev/null | sort >> $CUSTOM_LOG
        
        log "❌ 未找到有效的自定义文件目录"
        echo "未找到有效的自定义文件目录" >> $CUSTOM_LOG
        echo "请确保存在包含 ipk 或 sh 文件的 custom-files 目录" >> $CUSTOM_LOG
    fi
    
    echo "==========================================" >> $CUSTOM_LOG
    echo "自定义文件处理完成 - 总计处理: IPK($ipk_count) 脚本($script_count)" >> $CUSTOM_LOG
    
    log "✅ 自定义文件处理完成"
}

# 步骤16: 编译固件
build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 编译固件 ==="
    if [ "$enable_cache" = "true" ]; then
        log "启用编译缓存"
        make -j$(nproc) V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    else
        log "普通编译模式"
        make -j$(nproc) V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    log "编译退出代码: $BUILD_EXIT_CODE"
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
        log "❌ 编译失败，退出代码: $BUILD_EXIT_CODE"
        if [ -f "build.log" ]; then
            log "=== 编译错误摘要 ==="
            grep -i "error:\|failed\|undefined" build.log | head -20
        fi
        exit $BUILD_EXIT_CODE
    fi
    log "✅ 固件编译完成"
}

# 步骤17: 编译后空间检查
post_build_space_check() {
    log "=== 编译后空间检查 ==="
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
}

# 步骤18: 固件文件检查
check_firmware_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 固件文件检查 ==="
    if [ -d "bin/targets" ]; then
        log "✅ 固件目录存在"
        find bin/targets -name "*.bin" -o -name "*.img" | while read file; do
            log "固件文件: $file ($(du -h "$file" | cut -f1))"
        done
        log "=== 生成的固件列表 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" -o -name "*.gz" \) -exec ls -la {} \;
    else
        log "❌ 固件目录不存在"
        exit 1
    fi
}

# 步骤19: 备份配置文件
backup_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 备份配置文件 ==="
    
    # 创建配置备份目录
    mkdir -p config_backup
    
    # 备份主要配置文件
    if [ -f ".config" ]; then
        cp .config config_backup/
        log "✅ 备份 .config 文件"
    else
        log "⚠️ .config 文件不存在"
    fi
    
    # 备份环境变量
    if [ -f "$ENV_FILE" ]; then
        cp $ENV_FILE config_backup/
        log "✅ 备份环境变量文件"
    fi
    
    # 创建配置摘要
    CONFIG_SUMMARY="config_backup/config_summary.txt"
    echo "OpenWrt 构建配置摘要" > $CONFIG_SUMMARY
    echo "生成时间: $(date)" >> $CONFIG_SUMMARY
    echo "==========================================" >> $CONFIG_SUMMARY
    echo "版本: $SELECTED_BRANCH" >> $CONFIG_SUMMARY
    echo "设备: $DEVICE" >> $CONFIG_SUMMARY
    echo "目标平台: $TARGET" >> $CONFIG_SUMMARY
    echo "配置模式: $CONFIG_MODE" >> $CONFIG_SUMMARY
    echo "==========================================" >> $CONFIG_SUMMARY
    
    if [ -f ".config" ]; then
        echo "启用的包数量: $(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)" >> $CONFIG_SUMMARY
        echo "✅ 启用的插件列表:" >> $CONFIG_SUMMARY
        grep "^CONFIG_PACKAGE_luci-app-.*=y$" .config | sed 's/CONFIG_PACKAGE_//;s/=y//' | while read plugin; do
            echo "  ✅ $plugin" >> $CONFIG_SUMMARY
        done
    fi
    
    log "✅ 配置文件备份完成"
}

# 步骤20: 清理目录
cleanup() {
    log "=== 清理构建目录 ==="
    sudo rm -rf $BUILD_DIR || log "⚠️ 清理构建目录失败"
    log "✅ 构建目录已清理"
}

# 主函数
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
        "add_turboacc_support")
            add_turboacc_support
            ;;
        "add_filetransfer_support")
            add_filetransfer_support
            ;;
        "configure_feeds")
            configure_feeds
            ;;
        "install_turboacc_packages")
            install_turboacc_packages
            ;;
        "install_filetransfer_packages")
            install_filetransfer_packages
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
        "apply_config")
            apply_config
            ;;
        "fix_network")
            fix_network
            ;;
        "download_dependencies")
            download_dependencies
            ;;
        "process_custom_files")
            process_custom_files
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
        "backup_config")
            backup_config
            ;;
        "cleanup")
            cleanup
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  add_turboacc_support, add_filetransfer_support, configure_feeds"
            echo "  install_turboacc_packages, install_filetransfer_packages"
            echo "  pre_build_space_check, generate_config, verify_usb_config, apply_config"
            echo "  fix_network, download_dependencies, process_custom_files, build_firmware"
            echo "  post_build_space_check, check_firmware_files, backup_config, cleanup"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
