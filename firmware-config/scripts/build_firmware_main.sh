#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLCHAIN_DIR="$REPO_ROOT/firmware-config/Toolchain"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

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

load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
}

get_toolchain_path() {
    load_env
    echo "$TOOLCHAIN_DIR/$SELECTED_BRANCH/$TARGET/$SUBTARGET"
}

get_common_toolchain_path() {
    echo "$TOOLCHAIN_DIR/common"
}

save_toolchain() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 保存工具链到仓库 ==="
    
    local toolchain_path=$(get_toolchain_path)
    local common_path=$(get_common_toolchain_path)
    
    mkdir -p "$toolchain_path" "$common_path"
    
    local staging_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -z "$staging_toolchain" ]; then
        log "⚠️  未找到工具链目录，跳过保存"
        return 0
    fi
    
    log "找到工具链: $staging_toolchain"
    
    log "保存版本特定工具链到: $toolchain_path"
    # 使用cp替代rsync，避免符号链接问题
    cp -rL "$staging_toolchain" "$toolchain_path/$(basename "$staging_toolchain")" 2>/dev/null || \
    cp -r "$staging_toolchain" "$toolchain_path/$(basename "$staging_toolchain")" 2>/dev/null || \
    log "⚠️  工具链复制失败"
    
    log "保存通用工具链到: $common_path"
    
    local tools=("ar" "as" "gcc" "g++" "ld" "nm" "objcopy" "objdump" "ranlib" "strip")
    mkdir -p "$common_path/bin"
    for tool in "${tools[@]}"; do
        find "$staging_toolchain/bin" -name "*$tool*" -type f -exec cp -v {} "$common_path/bin/" \; 2>/dev/null || true
    done
    
    mkdir -p "$common_path/include" "$common_path/lib"
    find "$staging_toolchain/include" -name "*.h" -type f -exec cp -v {} "$common_path/include/" \; 2>/dev/null || true
    find "$staging_toolchain/lib" \( -name "*.a" -o -name "*.so" \) -type f | head -20 | xargs -I {} cp -v {} "$common_path/lib/" 2>/dev/null || true
    
    log "✅ 工具链保存完成"
    log "特定版本工具链: $toolchain_path"
    log "通用工具链: $common_path"
    
    # 清理可能的多余符号链接
    find "$TOOLCHAIN_DIR" -type l -delete 2>/dev/null || true
}

load_toolchain() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 加载工具链 ==="
    
    local toolchain_path=$(get_toolchain_path)
    local common_path=$(get_common_toolchain_path)
    
    if [ ! -d "$toolchain_path" ] && [ ! -d "$common_path" ]; then
        log "ℹ️  仓库中未找到工具链，将使用默认工具链"
        return 0
    fi
    
    mkdir -p staging_dir
    
    if [ -d "$toolchain_path" ]; then
        log "🔧 加载版本特定工具链: $toolchain_path"
        
        # 查找现有的工具链目录
        local existing_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
        
        if [ -n "$existing_toolchain" ]; then
            log "已存在工具链: $existing_toolchain，跳过加载"
            return 0
        fi
        
        # 从仓库复制工具链
        local toolchain_version=$(ls "$toolchain_path" 2>/dev/null | head -1)
        if [ -n "$toolchain_version" ]; then
            cp -r "$toolchain_path/$toolchain_version" "staging_dir/"
            log "✅ 版本特定工具链加载完成: staging_dir/$toolchain_version"
        fi
    fi
    
    if [ -d "$common_path" ]; then
        log "🔧 加载通用工具链组件"
        
        mkdir -p staging_dir/host
        
        if [ -d "$common_path/bin" ] && [ "$(ls -A "$common_path/bin" 2>/dev/null)" ]; then
            mkdir -p staging_dir/host/bin
            cp -r "$common_path/bin"/* staging_dir/host/bin/ 2>/dev/null || true
            log "✅ 通用工具链组件加载完成"
        fi
    fi
    
    log "=== 验证工具链 ==="
    if [ -d "staging_dir" ]; then
        find staging_dir -name "*gcc*" -type f | head -3 | while read compiler; do
            log "编译器: $compiler"
        done
    fi
}

integrate_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 集成自定义文件 ==="
    
    local custom_dir="$REPO_ROOT/firmware-config/custom-files"
    
    if [ ! -d "$custom_dir" ]; then
        log "ℹ️  自定义文件目录不存在: $custom_dir"
        return 0
    fi
    
    log "自定义文件目录: $custom_dir"
    
    local ipk_count=0
    local script_count=0
    local other_count=0
    
    # 1. 集成IPK文件到package目录
    if find "$custom_dir" -name "*.ipk" -type f | read -r; then
        mkdir -p package/custom
        log "🔧 集成IPK文件到package目录"
        
        while read -r ipk; do
            if [ -f "$ipk" ]; then
                local ipk_name=$(basename "$ipk")
                log "复制: $ipk_name"
                cp "$ipk" "package/custom/"
                ipk_count=$((ipk_count + 1))
            fi
        done < <(find "$custom_dir" -name "*.ipk" -type f)
        
        if [ $ipk_count -gt 0 ]; then
            cat > package/custom/Makefile << 'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=custom-packages
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Custom Build
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/custom-packages
  SECTION:=custom
  CATEGORY:=Custom
  TITLE:=Custom Packages Collection
  DEPENDS:=
endef

define Package/custom-packages/description
  This package contains custom IPK files.
endef

define Build/Compile
  true
endef

define Package/custom-packages/install
  true
endef

$(eval $(call BuildPackage,custom-packages))
EOF
            log "✅ 创建自定义包Makefile"
        fi
    fi
    
    # 2. 集成脚本文件到files目录
    if find "$custom_dir" -name "*.sh" -type f | read -r; then
        mkdir -p files/usr/share/custom
        log "🔧 集成脚本文件到files目录"
        
        while read -r script; do
            if [ -f "$script" ]; then
                local script_name=$(basename "$script")
                log "复制: $script_name"
                cp "$script" "files/usr/share/custom/"
                chmod +x "files/usr/share/custom/$script_name"
                script_count=$((script_count + 1))
            fi
        done < <(find "$custom_dir" -name "*.sh" -type f)
        
        if [ $script_count -gt 0 ]; then
            mkdir -p files/etc/init.d
            cat > files/etc/init.d/custom-scripts << 'EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

start() {
    echo "Starting custom scripts..."
    for script in /usr/share/custom/*.sh; do
        if [ -x "$script" ]; then
            echo "Running: $(basename "$script")"
            sh "$script" &
        fi
    done
}

stop() {
    echo "Stopping custom scripts..."
    pkill -f "sh /usr/share/custom/"
}
EOF
            chmod +x files/etc/init.d/custom-scripts
            log "✅ 创建自定义脚本启动服务"
        fi
    fi
    
    # 3. 集成其他配置文件
    while read -r file; do
        if [ -f "$file" ]; then
            local file_name=$(basename "$file")
            local relative_path=$(echo "$file" | sed "s|^$custom_dir/||")
            local target_dir="files/$(dirname "$relative_path")"
            
            mkdir -p "$target_dir"
            cp "$file" "$target_dir/"
            log "复制配置文件: $relative_path"
            other_count=$((other_count + 1))
        fi
    done < <(find "$custom_dir" -type f \( -name "*.conf" -o -name "*.config" -o -name "*.json" -o -name "*.txt" \) 2>/dev/null)
    
    log "✅ 自定义文件集成完成"
    log "  IPK文件: $ipk_count 个"
    log "  脚本文件: $script_count 个"
    log "  配置文件: $other_count 个"
}

pre_build_error_check() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 前置错误检查 ==="
    
    local error_count=0
    
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        error_count=$((error_count + 1))
    else
        log "✅ .config 文件存在"
        
        local critical_configs=(
            "CONFIG_TARGET_${TARGET}=y"
            "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y"
            "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y"
        )
        
        for config in "${critical_configs[@]}"; do
            if ! grep -q "^$config" .config; then
                log "❌ 错误: 缺少关键配置 $config"
                error_count=$((error_count + 1))
            else
                log "✅ 配置正常: $config"
            fi
        done
    fi
    
    if [ ! -d "feeds" ]; then
        log "❌ 错误: feeds 目录不存在"
        error_count=$((error_count + 1))
    else
        log "✅ feeds 目录存在"
        
        local critical_feeds=("packages" "luci")
        for feed in "${critical_feeds[@]}"; do
            if [ ! -d "feeds/$feed" ]; then
                log "❌ 错误: $feed feed 未安装"
                error_count=$((error_count + 1))
            else
                log "✅ feed 正常: $feed"
            fi
        done
    fi
    
    if [ ! -d "dl" ]; then
        log "⚠️  警告: dl 目录不存在，可能需要下载依赖"
    else
        local dl_count=$(find dl -type f -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" 2>/dev/null | wc -l)
        log "✅ 依赖包数量: $dl_count 个"
        
        if [ $dl_count -lt 10 ]; then
            log "⚠️  警告: 依赖包数量较少，可能下载不完整"
        fi
    fi
    
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log "磁盘可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        log "❌ 错误: 磁盘空间不足 (需要至少5G，当前${available_gb}G)"
        error_count=$((error_count + 1))
    fi
    
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    log "系统内存: ${total_mem}MB"
    
    if [ $total_mem -lt 1024 ]; then
        log "⚠️  警告: 内存较低 (建议至少1GB)"
    fi
    
    if [ -d "staging_dir" ]; then
        local toolchain_count=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | wc -l)
        if [ $toolchain_count -eq 0 ]; then
            log "⚠️  警告: 未找到工具链，将自动下载"
        else
            log "✅ 工具链存在: $toolchain_count 个"
        fi
    fi
    
    if [ $error_count -eq 0 ]; then
        log "✅ 前置检查通过，可以开始编译"
        return 0
    else
        log "❌ 前置检查发现 $error_count 个错误，请修复后再编译"
        return 1
    fi
}

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

create_build_dir() {
    log "=== 创建构建目录 ==="
    sudo mkdir -p $BUILD_DIR || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER $BUILD_DIR || handle_error "修改目录所有者失败"
    sudo chmod -R 755 $BUILD_DIR || handle_error "修改目录权限失败"
    log "✅ 构建目录创建完成"
}

initialize_build_env() {
    local device_name=$1
    local version_selection=$2
    local config_mode=$3
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 版本选择 ==="
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-23.05"
    else
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-21.02"
    fi
    log "✅ 版本选择完成: $SELECTED_BRANCH"
    
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
    
    save_env
    
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    sudo rm -rf ./* ./.git* 2>/dev/null || true
    
    git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . || handle_error "克隆源码失败"
    log "✅ 源码克隆完成"
}

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

configure_feeds() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 配置Feeds ==="
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
    fi
    
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log "✅ Feeds配置完成"
}

install_turboacc_packages() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 安装 TurboACC 包 ==="
    
    ./scripts/feeds update turboacc || handle_error "更新turboacc feed失败"
    
    ./scripts/feeds install -p turboacc luci-app-turboacc || handle_error "安装luci-app-turboacc失败"
    ./scripts/feeds install -p turboacc kmod-shortcut-fe || handle_error "安装kmod-shortcut-fe失败"
    ./scripts/feeds install -p turboacc kmod-fast-classifier || handle_error "安装kmod-fast-classifier失败"
    
    log "✅ TurboACC 包安装完成"
}

pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
}

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
    
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
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
    
    echo "# CONFIG_PACKAGE_dnsmasq is not set" >> .config
    echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcp=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dnssec=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_ipset=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_conntrack=y" >> .config
    
    echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
    echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
    echo "CONFIG_PACKAGE_ath10k-firmware-qca988x=y" >> .config
    echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config
    
    echo "CONFIG_PACKAGE_iptables=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-ipopt=y" >> .config
    echo "CONFIG_PACKAGE_ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 开始 ==="
    
    echo "# 🟢 USB 核心驱动 - 基础必须" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
    
    echo "# 🟢 USB 主机控制器驱动 - 通用支持" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ehci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-uhci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
    
    echo "# 🟡 平台专用USB控制器驱动 - 按平台启用" >> .config
    
    if [ "$TARGET" = "ipq40xx" ]; then
        log "🚨 关键修复：IPQ40xx 专用USB控制器驱动"
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
    fi
    
    if [ "$TARGET" = "ramips" ]; then
        log "🚨 关键修复：MT76xx/雷凌 平台USB控制器驱动"
        echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
    fi
    
    echo "# 🟢 USB 存储驱动 - 核心功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    
    echo "# 🟢 SCSI 支持 - 硬盘和U盘必需" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> .config
    
    echo "# 🟢 文件系统支持 - 完整文件系统兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-autofs4=y" >> .config
    
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
    
    echo "# 🟢 编码支持 - 多语言文件名兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp437=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-iso8859-1=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp936=y" >> .config
    
    echo "# 🟢 自动挂载工具 - 即插即用支持" >> .config
    echo "CONFIG_PACKAGE_block-mount=y" >> .config
    echo "CONFIG_PACKAGE_automount=y" >> .config
    
    echo "# 🟢 USB 工具和热插拔支持 - 设备管理" >> .config
    echo "CONFIG_PACKAGE_usbutils=y" >> .config
    echo "CONFIG_PACKAGE_lsusb=y" >> .config
    echo "CONFIG_PACKAGE_udev=y" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 完成 ==="
    
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config
    
    if [ "$CONFIG_MODE" = "base" ]; then
        log "🔧 使用基础模式 (最小化，用于测试编译)"
        echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> .config
        echo "# CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn is not set" >> .config
    else
        log "🔧 使用正常模式 (完整功能)"
        
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

apply_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 应用配置 ==="
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本配置预处理"
        sed -i 's/CONFIG_PACKAGE_ntfs-3g=y/# CONFIG_PACKAGE_ntfs-3g is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs-3g-utils=y/# CONFIG_PACKAGE_ntfs-3g-utils is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs3-mount=y/# CONFIG_PACKAGE_ntfs3-mount is not set/g' .config
    fi
    
    make defconfig || handle_error "应用配置失败"
    log "✅ 配置应用完成"
}

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

download_dependencies() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 下载依赖包 ==="
    make -j1 download || handle_error "下载依赖包失败"
    log "✅ 依赖包下载完成"
}

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

post_build_space_check() {
    log "=== 编译后空间检查 ==="
    df -h
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log "/mnt 可用空间: ${AVAILABLE_GB}G"
}

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

cleanup() {
    log "=== 清理构建目录 ==="
    sudo rm -rf $BUILD_DIR || log "⚠️ 清理构建目录失败"
    log "✅ 构建目录已清理"
}

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
        "configure_feeds")
            configure_feeds
            ;;
        "install_turboacc_packages")
            install_turboacc_packages
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
        "save_toolchain")
            save_toolchain
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
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  add_turboacc_support, configure_feeds, install_turboacc_packages"
            echo "  pre_build_space_check, generate_config, verify_usb_config, apply_config"
            echo "  fix_network, download_dependencies, load_toolchain, integrate_custom_files"
            echo "  pre_build_error_check, build_firmware, save_toolchain, post_build_space_check"
            echo "  check_firmware_files, cleanup"
            exit 1
            ;;
    esac
}

main "$@"
