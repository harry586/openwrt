#!/bin/bash
set -e

# 全局变量
BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
TOOLCHAIN_DIR="/home/runner/work/firmware-config/Toolchain"
CUSTOM_FILES_DIR="/home/runner/work/firmware-config/custom-files"

# 日志函数 - 修复：检查目录是否存在
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    if [ -d "$BUILD_DIR" ]; then
        echo "【$timestamp】$1" | tee -a "$BUILD_DIR/build.log"
    else
        echo "【$timestamp】$1"
    fi
}

# 错误处理函数
handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 保存环境变量到文件
save_env() {
    mkdir -p $BUILD_DIR
    cat > $ENV_FILE << EOF
#!/bin/bash
export SELECTED_REPO_URL="$SELECTED_REPO_URL"
export SELECTED_BRANCH="$SELECTED_BRANCH"
export TARGET="$TARGET"
export SUBTARGET="$SUBTARGET"
export DEVICE="$DEVICE"
export CONFIG_MODE="$CONFIG_MODE"
EOF
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
    
    # 创建构建目录以便记录日志
    if [ ! -d "$BUILD_DIR" ]; then
        sudo mkdir -p $BUILD_DIR
        sudo chown -R $USER:$USER $BUILD_DIR
        sudo chmod -R 755 $BUILD_DIR
    fi
    
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

# 步骤3: 初始化构建环境
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
    if [ -n "$GITHUB_ENV" ]; then
        echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
        echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
        echo "TARGET=$TARGET" >> $GITHUB_ENV
        echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
        echo "DEVICE=$DEVICE" >> $GITHUB_ENV
        echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    fi
    
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

# 步骤5: 配置Feeds
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

# 步骤6: 编译前空间检查
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
}

# 步骤7: 智能配置生成
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
    # 🚨 USB 完全修复通用配置
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
    
    # 🚨 关键修复：NTFS配置
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本NTFS配置优化"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
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
    
    # 配置模式选择
    if [ "$CONFIG_MODE" = "base" ]; then
        log "🔧 使用基础模式 (最小化，用于测试编译)"
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
            echo "CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-arpbind-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-cpulimit-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-hd-idle-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-accesscontrol-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y" >> .config
        fi
    fi
    
    # 处理额外安装插件
    if [ -n "$extra_packages" ]; then
        log "🔧 处理额外安装插件: $extra_packages"
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

# 步骤8: 验证USB配置
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

# 步骤9: 前置错误检查（增强版）
pre_build_check() {
    local build_dir=${1:-$BUILD_DIR}
    log "=== 前置错误检查（增强版）==="
    
    cd $build_dir || handle_error "进入构建目录失败"
    
    # 检查目录结构
    if [ ! -d "$build_dir" ]; then
        log "❌ 构建目录不存在: $build_dir"
        return 1
    fi
    
    # 检查关键文件
    local critical_files=(".config" "feeds.conf.default" "Makefile")
    local missing_files=0
    
    log "检查关键文件:"
    for file in "${critical_files[@]}"; do
        if [ ! -f "$build_dir/$file" ]; then
            log "❌ 关键文件缺失: $file"
            missing_files=$((missing_files + 1))
        else
            log "✅ $file 存在"
            
            # 检查文件内容
            if [ "$file" = ".config" ]; then
                file_size=$(wc -l < "$build_dir/$file" 2>/dev/null || echo "0")
                if [ "$file_size" -lt 100 ]; then
                    log "⚠️  $file 可能不完整，只有 $file_size 行"
                else
                    log "  📄 $file 有 $file_size 行配置"
                fi
            fi
        fi
    done
    
    if [ $missing_files -gt 0 ]; then
        log "❌ 缺少 $missing_files 个关键文件"
        return 1
    fi
    
    # 检查环境变量
    load_env
    local required_vars=("SELECTED_BRANCH" "TARGET" "SUBTARGET" "DEVICE" "CONFIG_MODE")
    local missing_vars=0
    
    log "检查环境变量:"
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            log "❌ 环境变量未设置: $var"
            missing_vars=$((missing_vars + 1))
        else
            log "✅ $var: ${!var}"
        fi
    done
    
    if [ $missing_vars -gt 0 ]; then
        log "❌ 缺少 $missing_vars 个环境变量"
        return 1
    fi
    
    # 检查 feeds 状态
    log "检查Feeds状态:"
    if [ ! -d "$build_dir/feeds" ]; then
        log "❌ Feeds 目录不存在"
        return 1
    else
        feed_dirs=$(find "$build_dir/feeds" -maxdepth 1 -type d | wc -l)
        feed_dirs=$((feed_dirs - 1))
        log "✅ Feeds 目录存在，包含 $feed_dirs 个feed"
        
        # 检查关键feed
        local required_feeds=("packages" "luci")
        for feed in "${required_feeds[@]}"; do
            if [ -d "$build_dir/feeds/$feed" ]; then
                log "✅ feed '$feed' 存在"
            else
                log "❌ feed '$feed' 不存在"
                return 1
            fi
        done
    fi
    
    # 检查系统资源
    local available_space=$(df -h $build_dir | tail -1 | awk '{print $4}')
    local mem_free=$(free -m | awk 'NR==2{print $4}')
    local cpu_cores=$(nproc)
    
    log "系统资源检查:"
    log "  磁盘空间: $available_space"
    log "  可用内存: ${mem_free}MB"
    log "  CPU核心: $cpu_cores"
    
    if [ $mem_free -lt 2048 ]; then
        log "⚠️  警告: 可用内存低于 2GB，可能导致编译失败"
    fi
    
    if [ $cpu_cores -lt 2 ]; then
        log "⚠️  警告: CPU核心少于2个，编译速度可能较慢"
    fi
    
    # 检查编译工具
    local required_tools=("make" "gcc" "git" "g++" "flex" "bison" "python3")
    local missing_tools=0
    
    log "检查编译工具:"
    for tool in "${required_tools[@]}"; do
        if ! command -v $tool >/dev/null 2>&1; then
            log "❌ 编译工具缺失: $tool"
            missing_tools=$((missing_tools + 1))
        else
            log "✅ $tool: $(which $tool)"
        fi
    done
    
    if [ $missing_tools -gt 0 ]; then
        log "❌ 缺少 $missing_tools 个编译工具"
        return 1
    fi
    
    # 新增：详细配置检查
    log "=== 详细配置检查 ==="
    
    # 1. 检查配置冲突
    log "1. 配置冲突检查:"
    
    # 检查重复配置
    DUPLICATES=$(grep "^CONFIG_PACKAGE_" .config | sort | uniq -d)
    if [ -n "$DUPLICATES" ]; then
        log "❌ 发现重复配置:"
        echo "$DUPLICATES" | while read dup; do
            log "  - $dup"
        done
        return 1
    else
        log "✅ 无重复配置"
    fi
    
    # 检查同时启用的冲突包
    if grep -q "CONFIG_PACKAGE_kmod-fs-ntfs=y" .config && \
       grep -q "CONFIG_PACKAGE_kmod-fs-ntfs3=y" .config; then
        log "⚠️  NTFS驱动冲突: kmod-fs-ntfs 和 kmod-fs-ntfs3 同时启用"
    fi
    
    # 检查USB驱动配置
    log "2. USB驱动检查:"
    USB_CONFIGS=(
        "kmod-usb-core" "kmod-usb2" "kmod-usb-storage"
    )
    
    local usb_errors=0
    for config in "${USB_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            log "✅ $config: 已启用"
        else
            log "❌ $config: 未启用"
            usb_errors=$((usb_errors + 1))
        fi
    done
    
    if [ $usb_errors -gt 0 ]; then
        log "❌ 发现 $usb_errors 个USB配置问题"
        return 1
    fi
    
    # 检查目标配置
    log "3. 目标配置检查:"
    TARGET_CONFIGS=(
        "CONFIG_TARGET_${TARGET}=y"
        "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y"
        "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y"
    )
    
    local target_errors=0
    for config in "${TARGET_CONFIGS[@]}"; do
        if grep -q "^${config}$" .config; then
            log "✅ $(echo $config | cut -d'=' -f1)"
        else
            log "❌ $(echo $config | cut -d'=' -f1)"
            target_errors=$((target_errors + 1))
        fi
    done
    
    if [ $target_errors -gt 0 ]; then
        log "❌ 发现 $target_errors 个目标配置问题"
        return 1
    fi
    
    # 检查配置完整性
    log "4. 配置完整性:"
    CONFIG_ENABLED=$(grep -c "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null || echo "0")
    CONFIG_DISABLED=$(grep -c "^# CONFIG_PACKAGE_.* is not set$" .config 2>/dev/null || echo "0")
    CONFIG_TOTAL=$((CONFIG_ENABLED + CONFIG_DISABLED))
    
    log "  已启用包: $CONFIG_ENABLED"
    log "  已禁用包: $CONFIG_DISABLED"
    log "  总配置项: $CONFIG_TOTAL"
    
    if [ $CONFIG_ENABLED -lt 50 ]; then
        log "⚠️  已启用包数量较少，可能配置不完整"
    fi
    
    # 检查下载的包
    log "5. 下载包检查:"
    if [ -d "dl" ]; then
        DL_COUNT=$(find dl -type f -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" | wc -l)
        log "  已下载包数量: $DL_COUNT"
        
        if [ $DL_COUNT -lt 10 ]; then
            log "⚠️  下载包数量可能不足"
        fi
        
        # 检查下载文件大小
        dl_total_size=$(du -sh dl 2>/dev/null | cut -f1)
        log "  下载目录大小: $dl_total_size"
    else
        log "⚠️  dl目录不存在，可能尚未下载依赖包"
    fi
    
    # 检查文件系统支持
    log "6. 文件系统支持检查:"
    FS_CONFIGS=(
        "kmod-fs-ext4" "kmod-fs-vfat" "kmod-fs-exfat"
    )
    
    local fs_errors=0
    for config in "${FS_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            log "✅ $config: 已启用"
        else
            log "❌ $config: 未启用"
            fs_errors=$((fs_errors + 1))
        fi
    done
    
    if [ $fs_errors -gt 0 ]; then
        log "❌ 发现 $fs_errors 个文件系统配置问题"
        return 1
    fi
    
    # 检查网络工具
    log "7. 网络工具检查:"
    NET_CONFIGS=(
        "iptables" "ip6tables" "dnsmasq-full"
    )
    
    local net_errors=0
    for config in "${NET_CONFIGS[@]}"; do
        if grep -q "CONFIG_PACKAGE_${config}=y" .config; then
            log "✅ $config: 已启用"
        else
            log "❌ $config: 未启用"
            net_errors=$((net_errors + 1))
        fi
    done
    
    if [ $net_errors -gt 0 ]; then
        log "❌ 发现 $net_errors 个网络工具配置问题"
        return 1
    fi
    
    # 检查语言包
    log "8. 语言包检查:"
    if grep -q "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" .config; then
        log "✅ 中文语言包已启用"
    else
        log "⚠️  中文语言包未启用"
    fi
    
    log "=== 检查完成 ==="
    
    local total_errors=$((missing_files + missing_vars + missing_tools + usb_errors + target_errors + fs_errors + net_errors))
    
    if [ $total_errors -eq 0 ]; then
        log "✅ 前置检查通过，未发现严重问题"
        return 0
    else
        log "❌ 前置检查发现 $total_errors 个问题"
        return 1
    fi
}

# 步骤10: 工具链管理（修复版）
toolchain_manager() {
    local build_dir=${1:-$BUILD_DIR}
    local action=${2:-"check"}
    
    log "=== 工具链管理 ==="
    log "操作: $action"
    
    load_env
    
    if [ -z "$SELECTED_BRANCH" ] || [ -z "$TARGET" ] || [ -z "$SUBTARGET" ]; then
        log "❌ 环境变量不完整，无法管理工具链"
        return 1
    fi
    
    # 获取工作空间路径
    local workspace_dir="/home/runner/work/firmware-config"
    
    # 如果不在GitHub Actions环境，使用当前目录
    if [ ! -d "$workspace_dir" ]; then
        workspace_dir="$(pwd)"
    fi
    
    # 工具链目录结构
    local toolchain_dir="$workspace_dir/Toolchain"
    local toolchain_common="$toolchain_dir/common"
    local toolchain_version="$toolchain_dir/$SELECTED_BRANCH"
    local toolchain_specific="$toolchain_version/${TARGET}_${SUBTARGET}"
    
    mkdir -p "$toolchain_common" "$toolchain_version" "$toolchain_specific"
    
    # 生成工具链标识
    local toolchain_id="${SELECTED_BRANCH}_${TARGET}_${SUBTARGET}"
    local toolchain_file="$toolchain_specific/toolchain.tar.gz"
    local toolchain_marker="$toolchain_specific/toolchain.marker"
    
    log "工具链目录: $toolchain_dir"
    log "版本目录: $toolchain_version"
    log "平台目录: $toolchain_specific"
    log "工具链文件: $toolchain_file"
    
    case $action in
        "check")
            # 检查是否存在工具链
            if [ -f "$toolchain_file" ] && [ -f "$toolchain_marker" ]; then
                log "✅ 找到工具链: $toolchain_id"
                log "文件大小: $(du -h "$toolchain_file" 2>/dev/null | cut -f1 || echo "未知")"
                
                # 检查工具链是否可用
                if tar -tzf "$toolchain_file" >/dev/null 2>&1; then
                    # 清理旧的 staging_dir
                    if [ -d "$build_dir/staging_dir" ]; then
                        log "清理旧的 staging_dir"
                        rm -rf "$build_dir/staging_dir"
                    fi
                    
                    # 提取工具链
                    log "正在提取工具链..."
                    tar -xzf "$toolchain_file" -C "$build_dir"
                    
                    if [ -d "$build_dir/staging_dir" ]; then
                        log "✅ 工具链恢复成功"
                        export STAGING_DIR="$build_dir/staging_dir"
                        
                        # 检查工具链文件
                        if find "$build_dir/staging_dir" -name "*gcc" -type f | grep -q .; then
                            log "✅ 工具链编译器存在"
                        else
                            log "❌ 工具链编译器缺失"
                            return 1
                        fi
                        
                        return 0
                    else
                        log "❌ 工具链提取失败"
                        return 1
                    fi
                else
                    log "❌ 工具链文件损坏"
                    rm -f "$toolchain_file" "$toolchain_marker"
                    return 1
                fi
            else
                log "ℹ️ 未找到现有工具链"
                if [ ! -f "$toolchain_file" ]; then
                    log "  文件不存在: $toolchain_file"
                fi
                if [ ! -f "$toolchain_marker" ]; then
                    log "  标记文件不存在: $toolchain_marker"
                fi
                return 2
            fi
            ;;
            
        "save")
            # 保存工具链
            if [ ! -d "$build_dir/staging_dir" ]; then
                log "❌ staging_dir 不存在，无法保存工具链"
                log "当前目录内容:"
                ls -la "$build_dir/" 2>/dev/null | head -10 || true
                return 1
            fi
            
            log "正在保存工具链..."
            log "源目录: $build_dir/staging_dir"
            log "目标文件: $toolchain_file"
            
            # 检查 staging_dir 内容
            log "staging_dir 内容预览:"
            find "$build_dir/staging_dir" -maxdepth 2 -type d 2>/dev/null | head -10 || true
            
            # 压缩保存
            log "正在压缩工具链..."
            if tar -czf "$toolchain_file" \
                --exclude="*.o" \
                --exclude="*.a" \
                --exclude="*.lo" \
                --exclude="*.la" \
                --exclude="*.so" \
                -C "$build_dir" staging_dir 2>&1; then
                
                # 创建标记文件
                cat > "$toolchain_marker" << EOF
TOOLCHAIN_ID=$toolchain_id
CREATED=$(date)
BRANCH=$SELECTED_BRANCH
TARGET=$TARGET
SUBTARGET=$SUBTARGET
SIZE=$(du -h "$toolchain_file" | cut -f1)
EOF
                
                log "✅ 工具链保存成功"
                log "文件大小: $(du -h "$toolchain_file" | cut -f1)"
                log "保存位置: $toolchain_file"
                
                # 验证保存的文件
                log "验证保存的文件..."
                if tar -tzf "$toolchain_file" >/dev/null 2>&1; then
                    log "✅ 工具链文件验证通过"
                    
                    # 列出工具链目录内容
                    log "工具链目录内容:"
                    ls -la "$toolchain_specific/" 2>/dev/null || true
                else
                    log "❌ 工具链文件验证失败"
                    return 1
                fi
            else
                log "❌ 工具链保存失败"
                return 1
            fi
            ;;
            
        "update")
            # 更新工具链
            if [ -f "$toolchain_marker" ] && [ -d "$build_dir/staging_dir" ]; then
                local old_time=$(grep "CREATED=" "$toolchain_marker" | cut -d'=' -f2)
                local new_time=$(date)
                
                log "检查工具链更新..."
                log "旧版本: $old_time"
                log "新版本: $new_time"
                
                # 总是更新到最新
                if tar -czf "$toolchain_file" \
                    --exclude="*.o" \
                    --exclude="*.a" \
                    --exclude="*.lo" \
                    --exclude="*.la" \
                    --exclude="*.so" \
                    -C "$build_dir" staging_dir 2>&1; then
                    
                    sed -i "s|CREATED=.*|CREATED=$new_time|" "$toolchain_marker"
                    sed -i "s|SIZE=.*|SIZE=$(du -h "$toolchain_file" | cut -f1)|" "$toolchain_marker"
                    log "✅ 工具链已更新"
                fi
            fi
            ;;
            
        *)
            log "❌ 未知操作: $action"
            return 1
            ;;
    esac
    
    return 0
}

# 步骤11: 集成自定义文件
integrate_custom_files() {
    local build_dir=${1:-$BUILD_DIR}
    log "=== 自定义文件集成 ==="
    
    if [ ! -d "$CUSTOM_FILES_DIR" ]; then
        log "ℹ️ 自定义文件目录不存在，跳过集成"
        return 0
    fi
    
    # 创建 files 目录
    local files_dir="$build_dir/files"
    mkdir -p "$files_dir"
    
    # 1. 处理 IPK 文件
    if find "$CUSTOM_FILES_DIR" -name "*.ipk" -type f | grep -q .; then
        local ipk_dir="$files_dir/root/ipk"
        mkdir -p "$ipk_dir"
        
        find "$CUSTOM_FILES_DIR" -name "*.ipk" -type f | while read -r ipk; do
            local filename=$(basename "$ipk")
            log "添加 IPK: $filename"
            cp "$ipk" "$ipk_dir/"
        done
        
        # 创建自动安装脚本
        local install_script="$files_dir/etc/uci-defaults/99-custom-ipk-install"
        mkdir -p "$(dirname "$install_script")"
        
        cat > "$install_script" << 'EOF'
#!/bin/sh
IPK_DIR="/root/ipk"
if [ -d "$IPK_DIR" ]; then
    cd "$IPK_DIR"
    for ipk in *.ipk; do
        if [ -f "$ipk" ]; then
            opkg install "$ipk" 2>/dev/null
        fi
    done
    rm -f *.ipk
fi
exit 0
EOF
        chmod +x "$install_script"
    fi
    
    # 2. 处理脚本文件
    if find "$CUSTOM_FILES_DIR" -name "*.sh" -type f | grep -q .; then
        local scripts_dir="$files_dir/usr/bin/custom"
        mkdir -p "$scripts_dir"
        
        find "$CUSTOM_FILES_DIR" -name "*.sh" -type f | while read -r script; do
            local filename=$(basename "$script")
            log "添加脚本: $filename"
            cp "$script" "$scripts_dir/"
            chmod +x "$scripts_dir/$filename"
        done
    fi
    
    # 3. 复制其他文件（保持目录结构）
    find "$CUSTOM_FILES_DIR" -type f \( ! -name "*.ipk" ! -name "*.sh" \) | while read -r file; do
        local relative_path=$(echo "$file" | sed "s|$CUSTOM_FILES_DIR/||")
        local target_file="$files_dir/$relative_path"
        local target_dir=$(dirname "$target_file")
        
        mkdir -p "$target_dir"
        cp "$file" "$target_file"
        
        log "复制: $relative_path"
    done
    
    log "✅ 自定义文件集成完成"
    return 0
}

# 步骤12: 应用配置（增强版）
apply_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 应用配置（详细版）==="
    
    # 显示当前配置摘要
    log "🔧 配置摘要:"
    if [ -f ".config" ]; then
        CONFIG_ENABLED=$(grep -c "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null || echo "0")
        CONFIG_DISABLED=$(grep -c "^# CONFIG_PACKAGE_.* is not set$" .config 2>/dev/null || echo "0")
        CONFIG_TOTAL=$((CONFIG_ENABLED + CONFIG_DISABLED))
        
        log "  已启用包: $CONFIG_ENABLED"
        log "  已禁用包: $CONFIG_DISABLED"
        log "  总配置项: $CONFIG_TOTAL"
        
        # 检查关键配置
        log "🔍 关键配置检查:"
        KEY_CONFIGS=(
            "CONFIG_TARGET_${TARGET}=y"
            "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y"
            "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y"
            "CONFIG_PACKAGE_kmod-usb-core=y"
            "CONFIG_PACKAGE_kmod-usb-storage=y"
            "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y"
        )
        
        for config in "${KEY_CONFIGS[@]}"; do
            if grep -q "^${config}$" .config; then
                log "  ✅ $(echo $config | cut -d'=' -f1)"
            else
                log "  ❌ $(echo $config | cut -d'=' -f1)"
            fi
        done
        
        # 显示前20个启用的包
        log "📦 已启用包示例（前20个）:"
        grep "^CONFIG_PACKAGE_.*=y$" .config | head -20 | while read line; do
            pkg_name=$(echo "$line" | sed 's/CONFIG_PACKAGE_//' | sed 's/=y//')
            log "  - $pkg_name"
        done
    else
        log "❌ 配置文件不存在"
    fi
    
    # 🚨 关键修复：23.05版本需要先清理可能的配置冲突
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本配置预处理"
        # 确保ntfs-3g相关配置被正确禁用
        sed -i 's/CONFIG_PACKAGE_ntfs-3g=y/# CONFIG_PACKAGE_ntfs-3g is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs-3g-utils=y/# CONFIG_PACKAGE_ntfs-3g-utils is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs3-mount=y/# CONFIG_PACKAGE_ntfs3-mount is not set/g' .config
    fi
    
    # 保存一份原始配置副本（用于后续上传）
    if [ -f ".config" ]; then
        cp .config .config.backup
        log "✅ 配置文件已备份"
    fi
    
    log "正在应用配置 (make defconfig)..."
    make defconfig || handle_error "应用配置失败"
    
    # 比较配置变化
    if [ -f ".config.old" ]; then
        CONFIG_CHANGES=$(diff -u .config.old .config | grep -E "^[-+]" | grep -v "^\-\-\-" | grep -v "^\+\+\+" | wc -l)
        log "配置变化数量: $CONFIG_CHANGES"
        
        if [ $CONFIG_CHANGES -gt 0 ]; then
            log "🔄 配置已更新"
            # 显示重要变化
            log "重要配置变化:"
            diff -u .config.old .config | grep -E "^[-+]CONFIG_PACKAGE_" | head -10 | while read line; do
                if [[ $line == +* ]]; then
                    log "  ➕ 新增: $(echo $line | sed 's/+//' | cut -d'=' -f1)"
                elif [[ $line == -* ]]; then
                    log "  ➖ 移除: $(echo $line | sed 's/-//' | cut -d'=' -f1)"
                fi
            done
        else
            log "✅ 配置无变化"
        fi
    fi
    
    # 显示最终配置统计
    if [ -f ".config" ]; then
        FINAL_ENABLED=$(grep -c "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null || echo "0")
        log "最终已启用包数量: $FINAL_ENABLED"
    fi
    
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

# 步骤15: 编译固件
build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 编译固件 ==="
    
    # 创建独立的编译日志文件
    if [ "$enable_cache" = "true" ]; then
        log "启用编译缓存"
        make -j$(nproc) V=s 2>&1 | tee "$BUILD_DIR/compile.log"
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    else
        log "普通编译模式"
        make -j$(nproc) V=s 2>&1 | tee "$BUILD_DIR/compile.log"
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    # 将编译日志追加到主日志
    if [ -f "$BUILD_DIR/compile.log" ]; then
        cat "$BUILD_DIR/compile.log" >> "$BUILD_DIR/build.log"
    fi
    
    log "编译退出代码: $BUILD_EXIT_CODE"
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
        log "❌ 编译失败，退出代码: $BUILD_EXIT_CODE"
        if [ -f "$BUILD_DIR/compile.log" ]; then
            log "=== 编译错误摘要 ==="
            grep -i "error:\|failed\|undefined" "$BUILD_DIR/compile.log" | head -20
        fi
        exit $BUILD_EXIT_CODE
    fi
    log "✅ 固件编译完成"
}

# 步骤16: 编译后空间检查
post_build_space_check() {
    log "=== 编译后空间检查 ==="
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
}

# 步骤17: 固件文件检查
check_firmware_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 固件文件检查 ==="
    if [ -d "bin/targets" ]; then
        log "✅ 固件目录存在"
        
        # 统计固件文件
        local bin_count=$(find bin/targets -name "*.bin" -o -name "*.img" | wc -l)
        log "固件文件数量: $bin_count"
        
        find bin/targets -name "*.bin" -o -name "*.img" | while read file; do
            log "固件文件: $file ($(du -h "$file" | cut -f1))"
        done
        
        log "=== 生成的固件列表 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" -o -name "*.gz" \) -exec ls -la {} \;
        
        # 检查固件大小
        local total_size=$(du -sh bin/targets | cut -f1)
        log "固件总大小: $total_size"
    else
        log "❌ 固件目录不存在"
        log "当前目录内容:"
        ls -la 2>/dev/null || true
        exit 1
    fi
}

# 步骤18: 清理目录
cleanup() {
    log "=== 清理构建目录 ==="
    
    # 先检查重要文件是否存在
    if [ -f "$BUILD_DIR/.config" ]; then
        log "✅ 配置文件存在，大小: $(du -h "$BUILD_DIR/.config" | cut -f1)"
    fi
    
    if [ -f "$BUILD_DIR/build.log" ]; then
        log "✅ 构建日志存在，大小: $(du -h "$BUILD_DIR/build.log" | cut -f1)"
    fi
    
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        log "✅ 固件目录存在"
    fi
    
    # 不删除重要文件，只清理临时文件
    if [ -d "$BUILD_DIR/tmp" ]; then
        rm -rf "$BUILD_DIR/tmp"
        log "✅ 清理tmp目录"
    fi
    
    if [ -d "$BUILD_DIR/build_dir" ]; then
        rm -rf "$BUILD_DIR/build_dir"
        log "✅ 清理build_dir目录"
    fi
    
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        rm -rf "$BUILD_DIR/staging_dir"
        log "✅ 清理staging_dir目录"
    fi
    
    # 保留重要文件，工作流会自己上传和清理
    log "ℹ️  重要文件保留，工作流结束后自动清理"
    log "✅ 临时文件清理完成"
}

# 主函数
main() {
    case $1 in
        # 原有的函数
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
        "apply_config")
            apply_config
            ;;
        "fix_network")
            fix_network
            ;;
        "download_dependencies")
            download_dependencies
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
        
        # 新增的函数
        "pre_build_check")
            pre_build_check "$BUILD_DIR"
            ;;
        "toolchain_manager")
            toolchain_manager "$BUILD_DIR" "$2"
            ;;
        "integrate_custom_files")
            integrate_custom_files "$BUILD_DIR"
            ;;
            
        *)
            echo "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  前置检查: pre_build_check"
            echo "  工具链管理: toolchain_manager [check|save|update]"
            echo "  自定义文件: integrate_custom_files"
            echo "  环境设置: setup_environment, create_build_dir, initialize_build_env"
            echo "  配置相关: add_turboacc_support, configure_feeds, generate_config"
            echo "  验证配置: verify_usb_config, apply_config"
            echo "  网络相关: fix_network, download_dependencies"
            echo "  编译相关: build_firmware"
            echo "  后置检查: post_build_space_check, check_firmware_files"
            echo "  清理: cleanup"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
