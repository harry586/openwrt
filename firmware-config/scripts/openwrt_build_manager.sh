#!/bin/bash

# OpenWrt 智能构建管理器 - 整合所有核心功能
# 功能：版本检测、设备检测、插件检查、配置管理、自定义文件集成

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 显示使用说明
show_usage() {
    echo "OpenWrt 智能构建管理器"
    echo "用法: $0 <功能> [参数...]"
    echo ""
    echo "可用功能:"
    echo "  version_detect    - 版本检测 <设备> [版本] [是否老旧设备]"
    echo "  device_detect     - 设备检测 <设备名称>"
    echo "  plugin_check      - 插件兼容性检查 <分支>"
    echo "  feeds_config      - Feeds配置 <分支>"
    echo "  config_load       - 配置加载 <类型> <平台> <设备> <分支> <原始设备> <额外包> <禁用包>"
    echo "  custom_integrate  - 自定义文件集成 <工作空间目录>"
    echo "  package_check     - 包可用性检查 [构建目录]"
    echo "  error_analyze     - 错误分析 [构建目录]"
    echo "  pre_download      - 预下载依赖包"
    echo "  all               - 执行完整构建流程"
    echo ""
    echo "示例:"
    echo "  $0 version_detect ac42u auto false"
    echo "  $0 device_detect ac42u"
    echo "  $0 plugin_check openwrt-23.05"
}

# 版本检测功能
version_detect() {
    local device_name="$1"
    local user_version="$2"
    local old_device="${3:-false}"
    
    log_info "=== 版本检测 ==="
    echo "设备: $device_name"
    echo "用户版本: ${user_version:-自动}"
    echo "老旧设备: $old_device"
    
    # 设备平台映射
    declare -A DEVICE_PLATFORM_MAP=(
        ["ac42u"]="ipq40xx"
        ["acrh17"]="ipq40xx"
        ["rt-acrh17"]="ipq40xx"
        ["ac58u"]="ipq40xx"
        ["acrh13"]="ipq40xx"
        ["rt-ac58u"]="ipq40xx"
        ["rt-acrh13"]="ipq40xx"
        ["xiaomi_redmi-ax6s"]="mediatek"
        ["wr841n"]="ar71xx"
        ["mi3g"]="ramips"
    )
    
    # 版本检测顺序
    local immortalwrt_versions=("openwrt-23.05" "openwrt-22.03" "openwrt-21.02" "openwrt-19.07" "openwrt-18.06" "master")
    local lede_versions=("17.01" "reborn" "master")
    local openwrt_versions=("openwrt-23.05" "openwrt-22.03" "openwrt-21.02" "openwrt-19.07" "openwrt-18.06" "master")
    
    # 如果用户指定了版本，直接使用
    if [ -n "$user_version" ] && [ "$user_version" != "auto" ]; then
        log_info "使用用户指定版本: $user_version"
        
        # 解析版本规格
        if [[ "$user_version" == *":"* ]]; then
            IFS=':' read -r repo branch <<< "$user_version"
        else
            repo="immortalwrt"
            branch="$user_version"
        fi
        
        # 自动添加前缀
        if [[ "$branch" =~ ^[0-9]+\.[0-9]+$ ]]; then
            branch="openwrt-$branch"
            log_info "自动添加分支前缀: $branch"
        fi
        
        # 设置仓库URL
        case "$repo" in
            "immortalwrt")
                SELECTED_REPO="immortalwrt"
                SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
                ;;
            "openwrt")
                SELECTED_REPO="openwrt"
                SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
                ;;
            "lede")
                SELECTED_REPO="lede"
                SELECTED_REPO_URL="https://github.com/coolsnowwolf/lede.git"
                ;;
            *)
                log_error "未知仓库: $repo"
                return 1
                ;;
        esac
        
        # 检查分支是否存在
        if git ls-remote --heads "$SELECTED_REPO_URL" "$branch" 2>/dev/null | grep -q "$branch"; then
            SELECTED_BRANCH="$branch"
            log_success "使用版本: $SELECTED_REPO:$SELECTED_BRANCH"
        else
            log_error "分支 $branch 不存在"
            return 1
        fi
    else
        # 自动版本检测逻辑
        log_info "开始自动版本检测..."
        
        # 根据设备类型选择默认版本
        case "$device_name" in
            "wr841n"|"wr842n"|"wr941n"|"mr3420"|"ar71xx"*)
                SELECTED_REPO="openwrt"
                SELECTED_BRANCH="openwrt-19.07"
                SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
                log_success "老旧设备，选择 OpenWrt 19.07"
                ;;
            *)
                SELECTED_REPO="immortalwrt"
                SELECTED_BRANCH="openwrt-23.05"
                SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
                log_success "现代设备，选择 ImmortalWrt 23.05"
                ;;
        esac
    fi
    
    # 输出环境变量
    echo "SELECTED_REPO=$SELECTED_REPO"
    echo "SELECTED_BRANCH=$SELECTED_BRANCH"
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL"
    
    log_success "版本检测完成"
}

# 设备检测功能
device_detect() {
    local device_input="$1"
    
    log_info "=== 设备检测 ==="
    echo "输入设备: $device_input"
    
    # 检查是否在 OpenWrt 源码目录
    if [ ! -d "target/linux" ]; then
        log_error "错误: 请在 OpenWrt 源码根目录中运行设备检测"
        return 1
    fi
    
    # 设备映射
    declare -A DEVICE_MAPPING=(
        ["ac42u"]="asus_rt-ac42u"
        ["acrh17"]="asus_rt-ac42u" 
        ["rt-acrh17"]="asus_rt-ac42u"
        ["ac58u"]="asus_rt-ac58u"
        ["acrh13"]="asus_rt-ac58u"
        ["rt-ac58u"]="asus_rt-ac58u"
        ["rt-acrh13"]="asus_rt-ac58u"
        ["mi4a"]="xiaomi_mi-router-4a-gigabit"
        ["r4a"]="xiaomi_mi-router-4a-gigabit"
        ["mi3g"]="xiaomi_mi-router-3g"
        ["r3g"]="xiaomi_mi-router-3g"
        ["mi4"]="xiaomi_mi-router-4"
        ["r4"]="xiaomi_mi-router-4"
        ["wr841n"]="tl-wr841n-v11"
        ["wr842n"]="tl-wr842n-v4"
        ["wr941n"]="tl-wr941nd-v6"
    )
    
    # 首先尝试已知映射
    if [ -n "${DEVICE_MAPPING[$device_input]}" ]; then
        local device_short_name="${DEVICE_MAPPING[$device_input]}"
        local platform=""
        
        # 推断平台
        case "$device_short_name" in
            *ipq40xx*|*asus_rt-ac*)
                platform="ipq40xx"
                ;;
            *ar71xx*|*tl-wr*)
                platform="ar71xx"
                ;;
            *ramips*|*xiaomi_mi*)
                platform="ramips"
                ;;
            *mediatek*|*redmi-ax6s*)
                platform="mediatek"
                ;;
            *)
                platform="ipq40xx"
                ;;
        esac
        
        log_success "使用已知映射: $device_input -> $device_short_name"
        echo "PLATFORM=$platform"
        echo "DEVICE_SHORT_NAME=$device_short_name"
        echo "DEVICE_FULL_NAME=$device_input"
        return 0
    fi
    
    # 搜索设备树文件
    log_info "搜索设备树文件..."
    local dts_files=$(find target/linux -name "*.dts" -type f 2>/dev/null | grep -i "$device_input" | head -3)
    
    if [ -n "$dts_files" ]; then
        log_success "找到设备树文件"
        local platform=$(echo "$dts_files" | head -1 | cut -d'/' -f3)
        local device_name=$(basename "$dts_files" | head -1 | sed 's/\.dts.*//')
        
        echo "PLATFORM=$platform"
        echo "DEVICE_SHORT_NAME=$device_name"
        echo "DEVICE_FULL_NAME=$device_input"
        echo "DTS_FILES=$dts_files"
    else
        log_warning "未找到设备树文件，使用输入名称"
        echo "PLATFORM=generic"
        echo "DEVICE_SHORT_NAME=$device_input"
        echo "DEVICE_FULL_NAME=$device_input"
    fi
    
    log_success "设备检测完成"
}

# 插件兼容性检查
plugin_check() {
    local branch="$1"
    
    log_info "=== 插件兼容性检查 ==="
    echo "目标版本: $branch"
    
    # 插件兼容性数据库
    declare -A PLUGIN_COMPATIBILITY=(
        ["turboacc"]="22.03 23.05"
        ["luci-app-turboacc"]="22.03 23.05"
        ["kmod-nft-fullcone"]="22.03 23.05"
        ["kmod-shortcut-fe"]="22.03 23.05"
    )
    
    check_plugin() {
        local branch="$1"
        local plugin="$2"
        
        local version=$(echo "$branch" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        
        if [ -z "$version" ]; then
            if [[ "$branch" =~ master|main ]]; then
                log_warning "⚠️  $plugin: 开发版分支，兼容性未知"
                return 1
            else
                log_warning "⚠️  $plugin: 无法识别版本号"
                return 1
            fi
        fi
        
        local compatible_versions="${PLUGIN_COMPATIBILITY[$plugin]}"
        
        if [ -z "$compatible_versions" ]; then
            log_info "ℹ️  $plugin: 兼容性信息未知"
            return 0
        fi
        
        if echo "$compatible_versions" | grep -q "$version"; then
            log_success "✅ $plugin: 兼容版本 $version"
            return 0
        else
            log_error "❌ $plugin: 不兼容版本 $version (仅支持: $compatible_versions)"
            return 1
        fi
    }
    
    echo "=== 网络加速插件兼容性 ==="
    check_plugin "$branch" "turboacc"
    check_plugin "$branch" "luci-app-turboacc"
    check_plugin "$branch" "kmod-nft-fullcone"
    check_plugin "$branch" "kmod-shortcut-fe"
    
    echo ""
    echo "=== 兼容性说明 ==="
    echo "🔹 22.03/23.05 - 完全支持 TurboAcc 加速"
    echo "🔹 21.02       - 基础网络优化支持"
    echo "🔹 19.07及以下 - 仅基础网络功能"
    echo "🔹 master      - 开发版，兼容性不确定"
}

# Feeds配置
feeds_config() {
    local branch="$1"
    
    log_info "=== Feeds 配置 ==="
    echo "分支: $branch"
    
    local feeds_branch="$branch"
    if echo "$branch" | grep -q "openwrt-23.05"; then
        feeds_branch="openwrt-23.05"
    elif echo "$branch" | grep -q "openwrt-22.03"; then
        feeds_branch="openwrt-22.03"
    elif echo "$branch" | grep -q "openwrt-21.02"; then
        feeds_branch="openwrt-21.02"
    elif echo "$branch" | grep -q "openwrt-19.07"; then
        feeds_branch="openwrt-19.07"
    else
        log_warning "未知版本分支，使用默认分支: master"
        feeds_branch="master"
    fi
    
    echo "使用的feeds分支: $feeds_branch"
    
    # 配置feeds
    echo "src-git packages https://github.com/immortalwrt/packages.git;$feeds_branch" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$feeds_branch" >> feeds.conf.default
    echo "src-git routing https://github.com/openwrt/routing.git;$feeds_branch" >> feeds.conf.default
    echo "src-git telephony https://github.com/openwrt/telephony.git;$feeds_branch" >> feeds.conf.default
    
    log_success "Feeds 配置完成"
    echo "Feeds配置内容:"
    cat feeds.conf.default
}

# 配置加载
config_load() {
    local config_type="$1"
    local platform="$2"
    local device_short_name="$3"
    local selected_branch="$4"
    local device_name="$5"
    local extra_packages="$6"
    local disabled_plugins="$7"
    
    log_info "=== 配置加载 ==="
    echo "配置类型: $config_type"
    echo "平台: $platform"
    echo "设备: $device_short_name"
    echo "分支: $selected_branch"
    
    export MAKE_JOBS=1
    
    # 选择配置文件
    local config_file=""
    if [ "$config_type" = "minimal" ]; then
        config_file="config-templates/minimal.config"
    elif [ "$config_type" = "normal" ] || [ "$config_type" = "custom" ]; then
        local is_old_version=0
        
        case "$device_name" in
            "wr841n"|"wr842n"|"wr941n"|"mr3420"|"ar71xx"*)
                is_old_version=1
                echo "✅ 自动判断为老旧设备: $device_name"
                ;;
        esac
        
        if echo "$selected_branch" | grep -q -E "19\.07|21\.02|17\.01|lede"; then
            is_old_version=1
            echo "✅ 自动判断为老旧版本: $selected_branch"
        fi
        
        if [ "$is_old_version" -eq 1 ]; then
            config_file="config-templates/normal-old.config"
        else
            config_file="config-templates/normal-new.config"
        fi
    else
        log_error "未知的配置类型: $config_type"
        return 1
    fi
    
    echo "=== 选择的配置文件: $config_file ==="
    if [ ! -f "$config_file" ]; then
        log_error "错误: 找不到配置文件 $config_file"
        return 1
    fi
    
    # 创建基础配置
    echo "=== 创建基础配置 ==="
    echo "# 设备基础配置" > .config
    echo "CONFIG_TARGET_${platform}=y" >> .config
    echo "CONFIG_TARGET_${platform}_generic=y" >> .config
    echo "CONFIG_TARGET_${platform}_generic_DEVICE_${device_short_name}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    echo "CONFIG_TARGET_IMAGES_PAD=y" >> .config
    
    # 追加模板配置
    echo "=== 追加模板配置 ==="
    grep -v -E "^CONFIG_TARGET_(ROOTFS_SQUASHFS|IMAGES_GZIP|IMAGES_PAD)=" "$config_file" > /tmp/filtered_config
    cat /tmp/filtered_config >> .config
    rm -f /tmp/filtered_config
    
    # 配置网络加速方案
    echo "=== 配置网络加速方案 ==="
    if echo "$selected_branch" | grep -q -E "23\.05|22\.03"; then
        echo "✅ 版本 $selected_branch 支持完整网络加速"
        echo "CONFIG_PACKAGE_kmod-nft-fullcone=y" >> .config
        echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
    elif echo "$selected_branch" | grep -q -E "21\.02|master"; then
        echo "⚠️ 版本 $selected_branch 支持基础网络优化"
        echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
    else
        echo "ℹ️ 版本 $selected_branch 使用最小网络配置"
    fi
    
    # 处理用户自定义包
    if [ -n "$extra_packages" ]; then
        echo "=== 添加额外插件 ==="
        for pkg in $extra_packages; do
            echo "添加插件: $pkg"
            sed -i "/# CONFIG_PACKAGE_${pkg} is not set/d" .config
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        done
    fi
    
    if [ -n "$disabled_plugins" ]; then
        echo "=== 禁用指定插件 ==="
        for pkg in $disabled_plugins; do
            echo "禁用插件: $pkg"
            sed -i "/CONFIG_PACKAGE_${pkg}=y/d" .config
            echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
        done
    fi
    
    # 清理重复的配置项
    echo "=== 清理重复配置项 ==="
    sort .config | uniq > .config.tmp
    mv .config.tmp .config
    
    echo "=== 当前启用的luci插件 ==="
    grep "^CONFIG_PACKAGE_luci-app" .config | sed 's/CONFIG_PACKAGE_//' | sed 's/=y//' | sort | uniq || echo "无luci插件"
    
    # 运行 defconfig
    echo "=== 运行单线程 defconfig ==="
    make -j1 defconfig
    
    log_success "配置加载完成"
}

# 自定义文件集成
custom_integrate() {
    local workspace_dir="$1"
    
    log_info "=== 自定义文件集成 ==="
    
    # 创建自定义文件目录
    mkdir -p files/root/custom-install
    
    # 复制IPK文件
    local ipk_files=$(find "$workspace_dir/firmware-config/custom-files" -name "*.ipk" -type f 2>/dev/null || true)
    if [ -n "$ipk_files" ]; then
        echo "✅ 找到IPK文件:"
        for ipk in $ipk_files; do
            cp "$ipk" files/root/custom-install/
            echo "✅ 复制IPK: $(basename "$ipk")"
        done
    fi
    
    # 复制脚本文件
    local script_files=$(find "$workspace_dir/firmware-config/custom-files" -name "*.sh" -type f 2>/dev/null | grep -v "detector\|analysis" || true)
    if [ -n "$script_files" ]; then
        echo "✅ 找到脚本文件:"
        for script in $script_files; do
            cp "$script" files/root/custom-install/
            chmod +x files/root/custom-install/$(basename "$script")
            echo "✅ 复制脚本: $(basename "$script")"
        done
    fi
    
    # 创建构建时安装脚本
    cat > files/root/custom-install/build-time-install.sh << 'EOF'
#!/bin/sh
echo "=== 开始构建时自定义安装 ==="

if ls /root/custom-install/*.ipk >/dev/null 2>&1; then
    echo "构建时安装IPK文件..."
    for ipk in /root/custom-install/*.ipk; do
        echo "安装: $(basename $ipk)"
        opkg install "$ipk" --force-depends || echo "安装失败: $(basename $ipk)"
    done
else
    echo "未找到IPK文件"
fi

if ls /root/custom-install/*.sh >/dev/null 2>&1; then
    echo "执行构建时脚本..."
    for script in /root/custom-install/*.sh; do
        if [ "$(basename $script)" != "build-time-install.sh" ]; then
            echo "执行: $(basename $script)"
            sh "$script" || echo "执行失败: $(basename $script)"
        fi
    done
else
    echo "未找到脚本文件"
fi

rm -rf /root/custom-install
echo "=== 构建时自定义安装完成 ==="
EOF

    chmod +x files/root/custom-install/build-time-install.sh
    
    # 创建rc.local启动脚本
    mkdir -p files/etc
    cat > files/etc/rc.local << 'EOF'
#!/bin/sh
[ -f /root/custom-install/build-time-install.sh ] && {
    /root/custom-install/build-time-install.sh >/tmp/build-time-install.log 2>&1 &
}
exit 0
EOF

    chmod +x files/etc/rc.local
    log_success "自定义文件集成完成"
}

# 包可用性检查
package_check() {
    local build_dir="${1:-.}"
    cd "$build_dir"
    
    log_info "=== 包可用性检查 ==="
    
    # 更新feeds
    echo "更新feeds..."
    ./scripts/feeds update -a > /dev/null 2>&1
    
    # 读取配置文件
    CONFIG_FILE="config-templates/normal-new.config"
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "错误: 配置文件 $CONFIG_FILE 不存在"
        return 1
    fi
    
    # 提取所有启用的包
    PACKAGES=$(grep "^CONFIG_PACKAGE_" "$CONFIG_FILE" | grep "=y$" | sed 's/CONFIG_PACKAGE_//;s/=y//')
    
    echo "在 $CONFIG_FILE 中启用的包数量: $(echo "$PACKAGES" | wc -l)"
    
    # 包名映射函数
    map_package() {
        local pkg="$1"
        case "$pkg" in
            # 内核模块映射
            kmod-usb-storage) echo "kmod-usb-storage" ;;
            kmod-usb-storage-uas) echo "kmod-usb-storage-uas" ;;
            kmod-usb2) echo "kmod-usb2" ;;
            kmod-usb3) echo "kmod-usb3" ;;
            kmod-fs-ext4) echo "kmod-fs-ext4" ;;
            kmod-fs-vfat) echo "kmod-fs-vfat" ;;
            kmod-fs-ntfs) echo "kmod-fs-ntfs" ;;
            kmod-fs-exfat) echo "kmod-fs-exfat" ;;
            kmod-ip6tables) echo "kmod-ipt6" ;;
            kmod-nf-ipt6) echo "kmod-ipt6" ;;
            kmod-ipt-extra) echo "kmod-ipt-extra" ;;
            kmod-ipt-offload) echo "kmod-ipt-offload" ;;
            kmod-nf-nathelper) echo "kmod-nf-nathelper" ;;
            kmod-nf-nathelper-extra) echo "kmod-nf-nathelper-extra" ;;
            
            # 基础工具映射
            fdisk) echo "fdisk" ;;
            lsblk) echo "lsblk" ;;
            blkid) echo "blkid" ;;
            block-mount) echo "block-mount" ;;
            e2fsprogs) echo "e2fsprogs" ;;
            
            # 核心服务映射
            firewall) echo "firewall" ;;
            dnsmasq) echo "dnsmasq" ;;
            dnsmasq-dhcpv6) echo "dnsmasq-full" ;;
            odhcpd) echo "odhcpd" ;;
            odhcp6c) echo "odhcp6c" ;;
            ipv6helper) echo "ipv6helper" ;;
            
            # 网络相关映射
            wpad-openssl) echo "wpad-basic" ;;
            hostapd-common) echo "hostapd" ;;
            hostapd-utils) echo "hostapd-utils" ;;
            
            # 库文件映射
            libstdcpp) echo "libstdcpp" ;;
            libpthread) echo "libpthread" ;;
            librt) echo "librt" ;;
            libatomic) echo "libatomic" ;;
            libopenssl) echo "libopenssl" ;;
            
            # Luci应用映射
            luci-app-turboacc) echo "luci-app-turboacc" ;;
            luci-i18n-turboacc-zh-cn) echo "luci-i18n-turboacc-zh-cn" ;;
            luci-app-accesscontrol) echo "luci-app-accesscontrol" ;;
            luci-i18n-accesscontrol-zh-cn) echo "luci-i18n-accesscontrol-zh-cn" ;;
            
            # 默认情况
            *) echo "$pkg" ;;
        esac
    }
    
    # 检查每个包是否在feeds中
    MISSING_PACKAGES=()
    AVAILABLE_PACKAGES=()
    ALTERNATIVE_PACKAGES=()
    
    # 预加载feeds列表到内存，避免重复调用
    local feeds_list=$(./scripts/feeds list 2>/dev/null)
    
    check_package_availability() {
        local original_pkg="$1"
        local pkg_to_check="$2"
        
        # 使用缓存的feeds列表进行检查
        if echo "$feeds_list" | grep -q "^$pkg_to_check"; then
            AVAILABLE_PACKAGES+=("$original_pkg→$pkg_to_check")
            echo "✅ $original_pkg → $pkg_to_check"
            return 0
        else
            # 尝试常见变体
            local variants=()
            
            # 内核模块变体
            if [[ "$pkg_to_check" == kmod-* ]]; then
                variants=("$pkg_to_check" "${pkg_to_check//kmod-/}" "kmod-${pkg_to_check//kmod-/}")
            fi
            
            # Luci应用变体
            if [[ "$pkg_to_check" == luci-* ]]; then
                variants=("$pkg_to_check" "${pkg_to_check//luci-/}" "${pkg_to_check//app-/}")
            fi
            
            # 检查所有变体
            for variant in "${variants[@]}"; do
                if echo "$feeds_list" | grep -q "^$variant"; then
                    ALTERNATIVE_PACKAGES+=("$original_pkg→$variant")
                    echo "🔄 $original_pkg → $variant (替代包)"
                    return 0
                fi
            done
            
            # 如果都没有找到，标记为缺失
            MISSING_PACKAGES+=("$original_pkg")
            echo "❌ $original_pkg"
            return 1
        fi
    }
    
    echo "=== 开始检查包可用性 ==="
    
    # 使用临时文件来避免管道问题
    local temp_file=$(mktemp)
    for pkg in $PACKAGES; do
        # 使用映射函数查找对应的包名
        mapped_pkg=$(map_package "$pkg")
        check_package_availability "$pkg" "$mapped_pkg" >> "$temp_file" 2>&1
    done
    
    # 输出结果，使用cat避免管道问题
    cat "$temp_file"
    rm -f "$temp_file"
    
    echo ""
    echo "=== 检查结果 ==="
    echo "可用的包数量: ${#AVAILABLE_PACKAGES[@]}"
    echo "找到替代的包数量: ${#ALTERNATIVE_PACKAGES[@]}"
    echo "缺失的包数量: ${#MISSING_PACKAGES[@]}"
    
    if [ ${#ALTERNATIVE_PACKAGES[@]} -gt 0 ]; then
        echo ""
        echo "=== 找到的替代包 ==="
        for pkg in "${ALTERNATIVE_PACKAGES[@]}"; do
            echo "  $pkg"
        done
    fi
    
    if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
        echo ""
        echo "=== 缺失的包 ==="
        for pkg in "${MISSING_PACKAGES[@]}"; do
            echo "  $pkg"
        done
        
        echo ""
        echo "=== 建议的解决方案 ==="
        echo "1. 运行以下命令查看所有可用的包:"
        echo "   ./scripts/feeds list | grep -i '缺失包名关键词'"
        echo ""
        echo "2. 手动更新 feeds:"
        echo "   ./scripts/feeds update -a"
        echo "   ./scripts/feeds install -a"
        echo ""
        echo "3. 使用 make menuconfig 查看可用的包"
        
        # 非关键性包缺失，只警告不退出
        CRITICAL_PACKAGES=("firewall" "dnsmasq" "kmod-usb-storage" "block-mount")
        critical_missing=0
        
        for critical in "${CRITICAL_PACKAGES[@]}"; do
            for missing in "${MISSING_PACKAGES[@]}"; do
                if [ "$missing" = "$critical" ]; then
                    echo "❌ 关键包缺失: $critical"
                    critical_missing=1
                fi
            done
        done
        
        if [ $critical_missing -eq 1 ]; then
            echo "❌ 有关键包缺失，构建可能失败"
            return 1
        else
            echo "⚠️ 有非关键包缺失，但构建可以继续"
            # 即使有非关键包缺失，也返回成功，让构建继续
            return 0
        fi
    else
        echo "✅ 所有包都在feeds中可用或有替代包。"
        return 0
    fi
}

# 错误分析
error_analyze() {
    local build_dir="${1:-/mnt/openwrt-build}"
    cd "$build_dir"
    
    log_info "=== 错误分析 ==="
    
    echo "=== 固件构建错误分析报告 ===" > error_analysis.log
    echo "生成时间: $(date)" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "=== 构建结果摘要 ===" >> error_analysis.log
    if [ -d "bin/targets" ]; then
        echo "✅ 构建状态: 成功" >> error_analysis.log
        echo "✅ 生成的固件文件: $(find bin/targets -name '*.bin' -o -name '*.img' | wc -l)" >> error_analysis.log
        find bin/targets -name "*.bin" -o -name "*.img" | head -5 >> error_analysis.log
    else
        echo "❌ 构建状态: 失败" >> error_analysis.log
    fi
    echo "" >> error_analysis.log
    
    echo "=== 关键错误检查 ===" >> error_analysis.log
    if [ -f "build_detailed.log" ]; then
        echo "检查日志文件: build_detailed.log" >> error_analysis.log
        
        # 编译错误
        echo "❌ 发现编译错误:" >> error_analysis.log
        grep -E "Error [0-9]|error:" build_detailed.log | head -10 >> error_analysis.log || echo "无关键编译错误" >> error_analysis.log
        
        # Makefile错误
        echo "" >> error_analysis.log
        echo "❌ Makefile执行错误:" >> error_analysis.log
        grep "make.*Error" build_detailed.log | head -10 >> error_analysis.log || echo "无Makefile错误" >> error_analysis.log
        
        # 被忽略的错误
        echo "" >> error_analysis.log
        echo "⚠️ 被忽略的错误:" >> error_analysis.log
        grep "Error.*ignored" build_detailed.log >> error_analysis.log || echo "无被忽略错误" >> error_analysis.log
        
        # 文件缺失错误
        echo "" >> error_analysis.log
        echo "❌ 文件缺失错误:" >> error_analysis.log
        grep -E "No such file|file not found" build_detailed.log | head -5 >> error_analysis.log || echo "无文件缺失错误" >> error_analysis.log
    else
        echo "未找到构建日志文件" >> error_analysis.log
    fi
    echo "" >> error_analysis.log
    
    echo "=== 错误原因分析和建议 ===" >> error_analysis.log
    echo "⚠️  文件缺失错误" >> error_analysis.log
    echo "💡 可能原因: 源码不完整或下载失败" >> error_analysis.log
    echo "" >> error_analysis.log
    echo "⚠️  管道错误" >> error_analysis.log
    echo "💡 这是并行编译的正常现象，不影响最终结果" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "=== 详细错误分类 ===" >> error_analysis.log
    echo "开始收集和分析错误日志..." >> error_analysis.log
    echo "使用日志文件: build_detailed.log" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "1. 严重错误 (Failed):" >> error_analysis.log
    grep -i "failed" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "2. 编译错误 (error:):" >> error_analysis.log
    grep "error:" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "3. 退出错误 (error 1/error 2):" >> error_analysis.log
    grep -E "error 1|error 2" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "4. 文件缺失错误:" >> error_analysis.log
    grep -E "No such file|file not found" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "5. 管道错误:" >> error_analysis.log
    grep "Broken pipe" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "6. 缺失依赖错误:" >> error_analysis.log
    grep "depends on" build_detailed.log | head -5 >> error_analysis.log || echo "无" >> error_analysis.log
    echo "" >> error_analysis.log
    
    echo "错误分析完成" >> error_analysis.log
    
    # 输出到控制台
    cat error_analysis.log
}

# 预下载依赖包
pre_download() {
    log_info "=== 预下载依赖包 ==="
    
    DOWNLOAD_DIR="dl"
    mkdir -p "$DOWNLOAD_DIR"
    
    # 常见依赖包URL
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
}

# 完整构建流程
build_all() {
    log_info "=== 执行完整构建流程 ==="
    # 这里可以按顺序调用所有功能
    # 实际工作流中会在不同步骤调用具体功能
    echo "请在 GitHub Actions 工作流中查看完整构建流程"
}

# 主函数
main() {
    local command="$1"
    shift
    
    case "$command" in
        "version_detect")
            version_detect "$@"
            ;;
        "device_detect")
            device_detect "$@"
            ;;
        "plugin_check")
            plugin_check "$@"
            ;;
        "feeds_config")
            feeds_config "$@"
            ;;
        "config_load")
            config_load "$@"
            ;;
        "custom_integrate")
            custom_integrate "$@"
            ;;
        "package_check")
            package_check "$@"
            ;;
        "error_analyze")
            error_analyze "$@"
            ;;
        "pre_download")
            pre_download "$@"
            ;;
        "all")
            build_all "$@"
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
}

# 如果直接运行脚本，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    main "$@"
fi
