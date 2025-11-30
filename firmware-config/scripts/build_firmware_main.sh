#!/bin/bash
set -e

# 全局变量
BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
CUSTOM_FILES_DIR="./firmware-config/custom-files"

# 步骤10: 智能配置生成（彻底禁用Passwall和Rclone）
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
    
    # 🚨 关键修复：在配置最开始就彻底禁用 passwall 和 rclone 系列插件
    log "🔧 彻底禁用 passwall 和 rclone 系列插件"
    
    # 定义所有需要禁用的插件（包括所有变体和依赖）
    DISABLED_PLUGINS=(
        # Passwall 主包和所有变体
        "luci-app-passwall"
        "luci-app-passwall_INCLUDE_Haproxy"
        "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client"
        "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server"
        "luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client"
        "luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Server"
        "luci-app-passwall_INCLUDE_Simple_Obfs"
        "luci-app-passwall_INCLUDE_SingBox"
        "luci-app-passwall_INCLUDE_Trojan"
        "luci-app-passwall_INCLUDE_Trojan_Plus"
        "luci-app-passwall_INCLUDE_Trojan_GO"
        "luci-app-passwall_INCLUDE_V2ray"
        "luci-app-passwall_INCLUDE_V2ray_Geoview"
        "luci-app-passwall_INCLUDE_V2ray_Plugin"
        "luci-app-passwall_INCLUDE_Xray"
        "luci-i18n-passwall-zh-cn"
        
        # Passwall 依赖包
        "haproxy"
        "shadowsocks-libev-ss-local"
        "shadowsocks-libev-ss-redir"
        "shadowsocks-libev-ss-server"
        "shadowsocksr-libev-ssr-local"
        "shadowsocksr-libev-ssr-redir"
        "shadowsocksr-libev-ssr-server"
        "simple-obfs"
        "sing-box"
        "trojan"
        "trojan-plus"
        "trojan-go"
        "v2ray"
        "v2ray-geoip"
        "v2ray-geosite"
        "v2ray-plugin"
        "xray"
        
        # Rclone 主包和所有变体
        "luci-app-rclone"
        "luci-app-rclone_INCLUDE_rclone-webui"
        "luci-app-rclone_INCLUDE_rclone-ng"
        "luci-i18n-rclone-zh-cn"
        
        # Rclone 依赖包
        "rclone"
        "rclone-ng"
        "rclone-webui"
        
        # 其他可能相关的包
        "luci-app-ssr-plus"
        "luci-app-vssr"
        "luci-app-openclash"
    )

    # 在配置最开始就禁用所有相关插件
    for disabled_plugin in "${DISABLED_PLUGINS[@]}"; do
        echo "# CONFIG_PACKAGE_${disabled_plugin} is not set" >> .config
    done

    # 创建基础配置
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    # 🚨 关键修复：在配置早期就启用文件传输插件
    echo "CONFIG_PACKAGE_luci-app-filetransfer=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y" >> .config
    
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

# 步骤12: 应用配置（强制禁用Passwall和Rclone）
apply_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 应用配置 ==="
    
    # 🚨 关键修复：强制禁用 passwall 和 rclone 插件
    log "🚨 强制禁用 passwall 和 rclone 插件"
    
    # 定义所有需要禁用的插件
    DISABLED_PLUGINS=(
        "luci-app-passwall"
        "luci-app-passwall_INCLUDE_Haproxy"
        "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client"
        "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server"
        "luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client"
        "luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Server"
        "luci-app-passwall_INCLUDE_Simple_Obfs"
        "luci-app-passwall_INCLUDE_SingBox"
        "luci-app-passwall_INCLUDE_Trojan"
        "luci-app-passwall_INCLUDE_Trojan_Plus"
        "luci-app-passwall_INCLUDE_Trojan_GO"
        "luci-app-passwall_INCLUDE_V2ray"
        "luci-app-passwall_INCLUDE_V2ray_Geoview"
        "luci-app-passwall_INCLUDE_V2ray_Plugin"
        "luci-app-passwall_INCLUDE_Xray"
        "luci-i18n-passwall-zh-cn"
        "luci-app-rclone"
        "luci-app-rclone_INCLUDE_rclone-webui"
        "luci-app-rclone_INCLUDE_rclone-ng"
        "luci-i18n-rclone-zh-cn"
    )

    # 使用sed强制删除任何已启用的配置
    for disabled_plugin in "${DISABLED_PLUGINS[@]}"; do
        # 删除任何已启用的配置
        sed -i "/CONFIG_PACKAGE_${disabled_plugin}=y/d" .config
        # 确保禁用配置存在
        echo "# CONFIG_PACKAGE_${disabled_plugin} is not set" >> .config
    done
    
    # 🚨 关键修复：23.05版本需要先清理可能的配置冲突
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本配置预处理"
        # 确保ntfs-3g相关配置被正确禁用
        sed -i 's/CONFIG_PACKAGE_ntfs-3g=y/# CONFIG_PACKAGE_ntfs-3g is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs-3g-utils=y/# CONFIG_PACKAGE_ntfs-3g-utils is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs3-mount=y/# CONFIG_PACKAGE_ntfs3-mount is not set/g' .config
        
        # 🚨 关键修复：23.05版本强制启用文件传输插件
        log "🚨 23.05版本强制启用文件传输插件"
        sed -i '/CONFIG_PACKAGE_luci-app-filetransfer/d' .config
        sed -i '/CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn/d' .config
        echo "CONFIG_PACKAGE_luci-app-filetransfer=y" >> .config
        echo "CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y" >> .config
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
    
    # 检查关键插件状态
    log "=== 关键插件状态验证 ==="
    if grep -q "CONFIG_PACKAGE_luci-app-filetransfer=y" .config; then
        log "✅ 文件传输插件: 已启用"
    else
        log "❌ 文件传输插件: 未启用"
    fi
    
    # 检查Passwall和Rclone是否被禁用
    PASSWALL_ENABLED=$(grep -c "^CONFIG_PACKAGE_luci-app-passwall.*=y$" .config || true)
    RCLONE_ENABLED=$(grep -c "^CONFIG_PACKAGE_luci-app-rclone.*=y$" .config || true)
    
    if [ "$PASSWALL_ENABLED" -eq 0 ]; then
        log "✅ 所有Passwall插件: 已正确禁用"
    else
        log "❌ 发现 $PASSWALL_ENABLED 个Passwall插件仍被启用"
        grep "^CONFIG_PACKAGE_luci-app-passwall.*=y$" .config | while read line; do
            log "  ❌ $line"
        done
    fi
    
    if [ "$RCLONE_ENABLED" -eq 0 ]; then
        log "✅ 所有Rclone插件: 已正确禁用"
    else
        log "❌ 发现 $RCLONE_ENABLED 个Rclone插件仍被启用"
        grep "^CONFIG_PACKAGE_luci-app-rclone.*=y$" .config | while read line; do
            log "  ❌ $line"
        done
    fi
    
    log "✅ 配置应用完成"
}

# 步骤15: 处理自定义文件（终极搜索方案）
process_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 处理自定义文件 ==="
    
    # 创建自定义文件目录
    mkdir -p $BUILD_DIR/custom_files_log
    CUSTOM_LOG="$BUILD_DIR/custom_files_log/custom_files.log"
    
    echo "自定义文件处理报告 - $(date)" > $CUSTOM_LOG
    echo "==========================================" >> $CUSTOM_LOG
    
    # 🚨 终极搜索方案：多种方法结合
    log "🔍 开始终极搜索自定义文件目录..."
    
    CUSTOM_FILES_DIR_FOUND=""
    
    # 方法1：检查绝对路径
    ABSOLUTE_PATHS=(
        "./firmware-config/custom-files"
        "./custom-files"
        "./files"
        "../firmware-config/custom-files"
        "../../firmware-config/custom-files"
        "../../../firmware-config/custom-files"
        "./firmware-config/files"
        "../firmware-config/files"
    )
    
    for path in "${ABSOLUTE_PATHS[@]}"; do
        if [ -d "$path" ]; then
            log "✅ 找到目录: $path"
            # 检查是否包含ipk或sh文件
            if find "$path" -maxdepth 2 -type f \( -name "*.ipk" -o -name "*.sh" \) | head -1 | grep -q "."; then
                CUSTOM_FILES_DIR_FOUND="$path"
                log "🎯 确认有效目录（包含IPK/SH文件）: $CUSTOM_FILES_DIR_FOUND"
                break
            else
                log "ℹ️ 目录存在但无IPK/SH文件: $path"
            fi
        fi
    done
    
    # 方法2：如果没找到，搜索整个项目
    if [ -z "$CUSTOM_FILES_DIR_FOUND" ]; then
        log "🔍 搜索整个项目中的IPK和SH文件..."
        
        # 搜索IPK文件
        IPK_PATHS=$(find . -name "*.ipk" -type f | head -10)
        if [ -n "$IPK_PATHS" ]; then
            log "📦 发现IPK文件，分析目录结构..."
            echo "$IPK_PATHS" | while read ipk_file; do
                ipk_dir=$(dirname "$ipk_file")
                log "  📍 IPK文件: $ipk_file (目录: $ipk_dir)"
                # 如果这个目录看起来像自定义文件目录
                if [[ "$ipk_dir" =~ (custom|files|firmware) ]] && [[ ! "$ipk_dir" =~ (feeds|build_dir|staging_dir|tmp|log) ]]; then
                    CUSTOM_FILES_DIR_FOUND="$ipk_dir"
                    log "🎯 通过IPK文件确定目录: $CUSTOM_FILES_DIR_FOUND"
                    break
                fi
            done
        fi
        
        # 如果还没找到，搜索SH文件
        if [ -z "$CUSTOM_FILES_DIR_FOUND" ]; then
            SH_PATHS=$(find . -name "*.sh" -type f | head -10)
            if [ -n "$SH_PATHS" ]; then
                log "📜 发现SH文件，分析目录结构..."
                echo "$SH_PATHS" | while read sh_file; do
                    sh_dir=$(dirname "$sh_file")
                    log "  📍 SH文件: $sh_file (目录: $sh_dir)"
                    # 如果这个目录看起来像自定义文件目录
                    if [[ "$sh_dir" =~ (custom|files|firmware) ]] && [[ ! "$sh_dir" =~ (feeds|build_dir|staging_dir|tmp|log) ]]; then
                        CUSTOM_FILES_DIR_FOUND="$sh_dir"
                        log "🎯 通过SH文件确定目录: $CUSTOM_FILES_DIR_FOUND"
                        break
                    fi
                done
            fi
        fi
    fi
    
    # 方法3：如果还是没找到，创建测试目录
    if [ -z "$CUSTOM_FILES_DIR_FOUND" ]; then
        log "⚠️ 未找到自定义文件目录，创建测试目录..."
        TEST_DIR="./firmware-config/custom-files"
        mkdir -p "$TEST_DIR"
        echo "# 测试文件" > "$TEST_DIR/test.sh"
        chmod +x "$TEST_DIR/test.sh"
        CUSTOM_FILES_DIR_FOUND="$TEST_DIR"
        log "📁 已创建测试目录: $CUSTOM_FILES_DIR_FOUND"
    fi
    
    if [ -n "$CUSTOM_FILES_DIR_FOUND" ] && [ -d "$CUSTOM_FILES_DIR_FOUND" ]; then
        CUSTOM_FILES_DIR="$CUSTOM_FILES_DIR_FOUND"
        log "🔧 使用自定义文件目录: $CUSTOM_FILES_DIR"
        echo "发现自定义文件目录: $CUSTOM_FILES_DIR" >> $CUSTOM_LOG
        
        # 显示目录完整内容
        log "📁 目录完整内容:"
        ls -la "$CUSTOM_FILES_DIR"/
        echo "目录完整内容:" >> $CUSTOM_LOG
        ls -la "$CUSTOM_FILES_DIR"/ >> $CUSTOM_LOG
        
        # 处理IPK文件
        IPK_FILES=$(find "$CUSTOM_FILES_DIR" -name "*.ipk" -type f)
        if [ -n "$IPK_FILES" ]; then
            IPK_COUNT=$(echo "$IPK_FILES" | wc -l)
            log "📦 发现 $IPK_COUNT 个IPK文件"
            echo "发现的IPK文件 ($IPK_COUNT 个):" >> $CUSTOM_LOG
            echo "$IPK_FILES" >> $CUSTOM_LOG
            
            # 创建IPK存放目录
            IPK_DEST_DIR="$BUILD_DIR/packages/custom"
            mkdir -p "$IPK_DEST_DIR"
            
            # 复制IPK文件
            for ipk_file in $IPK_FILES; do
                ipk_name=$(basename "$ipk_file")
                log "复制IPK: $ipk_name"
                cp "$ipk_file" "$IPK_DEST_DIR/"
                echo "✅ 复制IPK: $ipk_name 到 $IPK_DEST_DIR/" >> $CUSTOM_LOG
            done
        else
            log "❌ 未找到IPK文件"
            echo "未找到IPK文件" >> $CUSTOM_LOG
        fi
        
        # 处理Shell脚本
        SH_FILES=$(find "$CUSTOM_FILES_DIR" -name "*.sh" -type f)
        if [ -n "$SH_FILES" ]; then
            SH_COUNT=$(echo "$SH_FILES" | wc -l)
            log "📜 发现 $SH_COUNT 个Shell脚本"
            echo "发现的Shell脚本 ($SH_COUNT 个):" >> $CUSTOM_LOG
            echo "$SH_FILES" >> $CUSTOM_LOG
            
            # 创建脚本存放目录
            SCRIPT_DEST_DIR="$BUILD_DIR/files/etc/uci-defaults"
            mkdir -p "$SCRIPT_DEST_DIR"
            
            # 复制并设置执行权限
            for sh_file in $SH_FILES; do
                sh_name=$(basename "$sh_file")
                log "处理脚本: $sh_name"
                cp "$sh_file" "$SCRIPT_DEST_DIR/"
                chmod +x "$SCRIPT_DEST_DIR/$sh_name"
                echo "✅ 复制脚本: $sh_name 到 $SCRIPT_DEST_DIR/" >> $CUSTOM_LOG
            done
        else
            log "❌ 未找到Shell脚本"
            echo "未找到Shell脚本" >> $CUSTOM_LOG
        fi
        
    else
        log "❌ 未找到有效的自定义文件目录"
        echo "未找到有效的自定义文件目录" >> $CUSTOM_LOG
        
        # 提供详细的调试信息
        log "🔍 项目根目录内容:"
        ls -la ./
        echo "项目根目录内容:" >> $CUSTOM_LOG
        ls -la ./ >> $CUSTOM_LOG
        
        log "🔍 查找所有可能的目录:"
        find . -type d \( -name "*custom*" -o -name "*file*" -o -name "*firmware*" \) | head -20
    fi
    
    echo "==========================================" >> $CUSTOM_LOG
    echo "自定义文件处理完成" >> $CUSTOM_LOG
    
    log "✅ 自定义文件处理完成"
}
