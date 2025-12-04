#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"

debug_log() {
    if [ "${DEBUG_MODE}" = "true" ]; then
        echo "🔍 $(date '+%Y-%m-%d %H:%M:%S')】$1"
    fi
}

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

save_env() {
    mkdir -p $BUILD_DIR
    cat > $ENV_FILE << EOF
SELECTED_REPO_URL="$SELECTED_REPO_URL"
SELECTED_BRANCH="$SELECTED_BRANCH"
TARGET="$TARGET"
SUBTARGET="$SUBTARGET"
DEVICE="$DEVICE"
CONFIG_MODE="$CONFIG_MODE"
EOF
    chmod +x $ENV_FILE
    log "✅ 环境变量已保存"
}

initialize_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    
    log "=== 初始化构建环境 ==="
    
    # 确保在构建目录
    cd "$BUILD_DIR" || handle_error "进入构建目录失败"
    
    debug_log "当前目录: $(pwd)"
    debug_log "目录内容:"
    ls -la
    
    # 版本选择
    log "=== 版本选择 ==="
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-23.05"
    else
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-21.02"
    fi
    log "版本: $SELECTED_BRANCH"
    
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
    
    # 克隆源码
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    # 检查是否已经有源码
    if [ -d ".git" ]; then
        log "源码已存在，跳过克隆"
    else
        log "克隆源码..."
        
        # 确保目录为空
        debug_log "清理目录..."
        rm -rf ./* ./.git* 2>/dev/null || true
        
        debug_log "开始克隆..."
        git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . || handle_error "克隆源码失败"
        log "✅ 源码克隆完成"
        
        debug_log "源码克隆完成，目录内容:"
        ls -la
    fi
    
    log "✅ 构建环境初始化完成"
}

configure_feeds() {
    log "=== 配置Feeds ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
    
    debug_log "当前分支: $SELECTED_BRANCH"
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    cat > feeds.conf.default << EOF
src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH
src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH
EOF
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
        if ! grep -q "turboacc" feeds.conf.default; then
            echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
            debug_log "添加TurboACC feed"
        fi
    fi
    
    debug_log "feeds.conf.default内容:"
    cat feeds.conf.default
    
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    log "✅ Feeds配置完成"
}

add_turboacc_support() {
    log "=== 添加 TurboACC 支持 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
    
    if [ "$CONFIG_MODE" = "normal" ] && [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "为 23.05 添加 TurboACC 支持"
    else
        log "不需要添加 TurboACC 支持"
    fi
}

install_filetransfer_packages() {
    log "=== 安装文件传输插件包 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    ./scripts/feeds update luci || handle_error "更新luci feed失败"
    
    if ./scripts/feeds install -p luci luci-app-filetransfer 2>/dev/null; then
        log "✅ 安装luci-app-filetransfer成功"
    else
        log "⚠️ 安装luci-app-filetransfer失败"
    fi
    
    log "✅ 文件传输插件包安装完成"
}

generate_config() {
    local extra_packages=$1
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
    
    log "=== 智能配置生成 ==="
    rm -f .config .config.old
    
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    log "彻底禁用 passwall 和 rclone 系列插件"
    echo "# ==========================================" >> .config
    echo "# 🚫 强制禁用 passwall 系列插件" >> .config
    echo "# ==========================================" >> .config
    
    PASSWALL_PLUGINS=("luci-app-passwall" "luci-app-passwall_INCLUDE_Haproxy" "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Client" "luci-app-passwall_INCLUDE_Shadowsocks_Libev_Server" "luci-app-passwall_INCLUDE_ShadowsocksR_Libev_Client" "luci-app-passwall_INCLUDE_Simple_Obfs" "luci-app-passwall_INCLUDE_SingBox" "luci-app-passwall_INCLUDE_Trojan_Plus" "luci-app-passwall_INCLUDE_V2ray_Geoview" "luci-app-passwall_INCLUDE_V2ray_Plugin" "luci-app-passwall_INCLUDE_Xray" "luci-i18n-passwall-zh-cn")
    
    for plugin in "${PASSWALL_PLUGINS[@]}"; do
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done
    
    echo "# ==========================================" >> .config
    echo "# 🚫 强制禁用 rclone 系列插件" >> .config
    echo "# ==========================================" >> .config
    
    RCLONE_PLUGINS=("luci-app-rclone" "luci-app-rclone_INCLUDE_rclone-webui" "luci-app-rclone_INCLUDE_rclone-ng" "luci-i18n-rclone-zh-cn" "rclone" "rclone-ng" "rclone-webui")
    
    for plugin in "${RCLONE_PLUGINS[@]}"; do
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done
    
    log "添加基础配置"
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
    
    log "添加USB配置"
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
    else
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
    fi
    
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config
    echo "CONFIG_PACKAGE_luci-app-filetransfer=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-filetransfer-zh-cn=y" >> .config
    
    if [ "$CONFIG_MODE" = "base" ]; then
        log "使用基础模式"
        echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
    else
        log "使用正常模式"
        
        NORMAL_PLUGINS=("CONFIG_PACKAGE_luci-app-turboacc=y" "CONFIG_PACKAGE_kmod-shortcut-fe=y" "CONFIG_PACKAGE_kmod-fast-classifier=y" "CONFIG_PACKAGE_luci-app-upnp=y" "CONFIG_PACKAGE_miniupnpd=y" "CONFIG_PACKAGE_vsftpd=y" "CONFIG_PACKAGE_luci-app-vsftpd=y" "CONFIG_PACKAGE_luci-app-arpbind=y" "CONFIG_PACKAGE_luci-app-cpulimit=y" "CONFIG_PACKAGE_samba4-server=y" "CONFIG_PACKAGE_luci-app-samba4=y" "CONFIG_PACKAGE_luci-app-wechatpush=y" "CONFIG_PACKAGE_sqm-scripts=y" "CONFIG_PACKAGE_luci-app-sqm=y" "CONFIG_PACKAGE_luci-app-hd-idle=y" "CONFIG_PACKAGE_luci-app-diskman=y" "CONFIG_PACKAGE_luci-app-accesscontrol=y" "CONFIG_PACKAGE_vlmcsd=y" "CONFIG_PACKAGE_luci-app-vlmcsd=y" "CONFIG_PACKAGE_smartdns=y" "CONFIG_PACKAGE_luci-app-smartdns=y")
        
        for plugin in "${NORMAL_PLUGINS[@]}"; do
            echo "$plugin" >> .config
        done
        
        if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            NORMAL_I18N_PLUGINS=("CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-arpbind-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-cpulimit-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-hd-idle-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-accesscontrol-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y" "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y")
            
            for i18n_plugin in "${NORMAL_I18N_PLUGINS[@]}"; do
                echo "$i18n_plugin" >> .config
            done
        fi
    fi
    
    if [ -n "$extra_packages" ]; then
        log "处理额外插件: $extra_packages"
        extra_packages=$(echo "$extra_packages" | sed 's/、/;/g')
        IFS=';' read -ra EXTRA_PKGS <<< "$extra_packages"
        
        for pkg_cmd in "${EXTRA_PKGS[@]}"; do
            pkg_cmd_clean=$(echo "$pkg_cmd" | xargs)
            if [[ "$pkg_cmd_clean" == +* ]]; then
                pkg_name="${pkg_cmd_clean:1}"
                log "启用插件: $pkg_name"
                echo "CONFIG_PACKAGE_${pkg_name}=y" >> .config
            elif [[ "$pkg_cmd_clean" == -* ]]; then
                pkg_name="${pkg_cmd_clean:1}"
                log "禁用插件: $pkg_name"
                echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> .config
            elif [ -n "$pkg_cmd_clean" ]; then
                log "启用插件: $pkg_cmd_clean"
                echo "CONFIG_PACKAGE_${pkg_cmd_clean}=y" >> .config
            fi
        done
    fi
    
    log "✅ 智能配置生成完成"
}

verify_usb_config() {
    log "=== 验证USB配置 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    echo "1. USB核心模块:"
    grep "CONFIG_PACKAGE_kmod-usb-core" .config | grep "=y" && echo "✅ USB核心" || echo "❌ 缺少USB核心"
    
    echo "2. USB控制器:"
    grep -E "CONFIG_PACKAGE_kmod-usb2|CONFIG_PACKAGE_kmod-usb3" .config | grep "=y" || echo "❌ 缺少USB控制器"
    
    log "✅ USB配置验证完成"
}

apply_config() {
    log "=== 应用配置 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    make defconfig || handle_error "应用配置失败"
    
    log "✅ 配置应用完成"
}

fix_network() {
    log "=== 修复网络环境 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    
    log "✅ 网络环境修复完成"
}

download_dependencies() {
    log "=== 下载依赖包 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    for i in {1..3}; do
        log "第 $i 次尝试下载依赖包..."
        if make -j1 download V=s; then
            log "✅ 依赖包下载完成"
            return 0
        else
            log "⚠️ 第 $i 次下载失败，等待10秒后重试..."
            sleep 10
        fi
    done
    
    log "❌ 依赖包下载失败，但继续编译"
    return 0
}

process_custom_files() {
    log "=== 处理自定义文件 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    mkdir -p $BUILD_DIR/custom_files_log
    CUSTOM_LOG="$BUILD_DIR/custom_files_log/custom_files.log"
    
    echo "自定义文件处理报告 - $(date)" > $CUSTOM_LOG
    
    CUSTOM_DIRS=("/home/runner/work/$(basename $(pwd))/$(basename $(pwd))/firmware-config/custom-files" "$(pwd)/../firmware-config/custom-files" "$(pwd)/firmware-config/custom-files" "./firmware-config/custom-files" "../firmware-config/custom-files" "../../firmware-config/custom-files")
    
    CUSTOM_FILES_DIR_FOUND=""
    
    log "搜索自定义文件目录..."
    
    for dir in "${CUSTOM_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            CUSTOM_FILES_DIR_FOUND="$dir"
            log "✅ 找到自定义文件目录: $CUSTOM_FILES_DIR_FOUND"
            break
        fi
    done
    
    if [ -n "$CUSTOM_FILES_DIR_FOUND" ]; then
        CUSTOM_FILES_DIR="$CUSTOM_FILES_DIR_FOUND"
        log "处理目录: $CUSTOM_FILES_DIR"
        
        IPK_FILES=$(find "$CUSTOM_FILES_DIR" -name "*.ipk" -type f 2>/dev/null)
        
        if [ -n "$IPK_FILES" ]; then
            log "发现 $(echo "$IPK_FILES" | wc -l) 个IPK文件"
            IPK_DEST_DIR="$BUILD_DIR/packages/custom"
            mkdir -p "$IPK_DEST_DIR"
            
            for ipk_file in $IPK_FILES; do
                if [ -f "$ipk_file" ]; then
                    ipk_name=$(basename "$ipk_file")
                    log "复制IPK: $ipk_name"
                    cp "$ipk_file" "$IPK_DEST_DIR/"
                fi
            done
        else
            log "未找到IPK文件"
        fi
        
        SH_FILES=$(find "$CUSTOM_FILES_DIR" -name "*.sh" -type f 2>/dev/null)
        
        if [ -n "$SH_FILES" ]; then
            log "发现 $(echo "$SH_FILES" | wc -l) 个Shell脚本"
            SCRIPT_DEST_DIR="$BUILD_DIR/files/etc/uci-defaults"
            mkdir -p "$SCRIPT_DEST_DIR"
            
            for sh_file in $SH_FILES; do
                if [ -f "$sh_file" ]; then
                    sh_name=$(basename "$sh_file")
                    log "处理脚本: $sh_name"
                    cp "$sh_file" "$SCRIPT_DEST_DIR/"
                    chmod +x "$SCRIPT_DEST_DIR/$sh_name"
                fi
            done
        else
            log "未找到Shell脚本"
        fi
    else
        log "未找到有效的自定义文件目录"
    fi
    
    log "✅ 自定义文件处理完成"
}

build_firmware() {
    local enable_cache=$1
    log "=== 编译固件 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    touch build.log
    
    local num_cores=$(nproc)
    local build_jobs=$((num_cores))
    
    if [ "$enable_cache" = "true" ]; then
        log "启用编译缓存 (使用 $build_jobs 线程)"
        export CCACHE_DIR="/tmp/ccache_openwrt"
        export CCACHE_MAXSIZE="10G"
        mkdir -p $CCACHE_DIR
        
        make -j$build_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    else
        log "普通编译模式 (使用 $build_jobs 线程)"
        make -j$build_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    log "编译退出代码: $BUILD_EXIT_CODE"
    
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        log "✅ 固件编译完成"
        return 0
    else
        log "⚠️ 编译过程出现错误"
        return 1
    fi
}

check_firmware_files() {
    log "=== 固件文件检查 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    if [ -d "bin/targets" ]; then
        log "✅ 固件目录存在"
        FIRMWARE_FILES=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" -o -name "*.gz" \) 2>/dev/null)
        if [ -n "$FIRMWARE_FILES" ]; then
            log "生成的固件文件:"
            for file in $FIRMWARE_FILES; do
                size=$(du -h "$file" | cut -f1)
                log "  📄 $(basename "$file") ($size)"
            done
        else
            log "❌ 未找到固件文件"
        fi
    else
        log "❌ 固件目录不存在"
        return 1
    fi
}

backup_config() {
    log "=== 备份配置文件 ==="
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    mkdir -p config_backup
    
    if [ -f ".config" ]; then
        cp .config config_backup/
        log "✅ 备份 .config 文件"
    fi
    
    if [ -f "$ENV_FILE" ]; then
        cp $ENV_FILE config_backup/
        log "✅ 备份环境变量文件"
    fi
    
    if [ -f "build.log" ]; then
        cp build.log config_backup/ 2>/dev/null || true
        log "✅ 备份编译日志"
    fi
    
    log "✅ 配置文件备份完成"
}

main() {
    case $1 in
        "initialize_build_env")
            initialize_build_env "$2" "$3" "$4"
            ;;
        "configure_feeds")
            configure_feeds
            ;;
        "add_turboacc_support")
            add_turboacc_support
            ;;
        "install_filetransfer_packages")
            install_filetransfer_packages
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
        "check_firmware_files")
            check_firmware_files
            ;;
        "backup_config")
            backup_config
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  initialize_build_env, configure_feeds, add_turboacc_support"
            echo "  install_filetransfer_packages, generate_config, verify_usb_config"
            echo "  apply_config, fix_network, download_dependencies, process_custom_files"
            echo "  build_firmware, check_firmware_files, backup_config"
            exit 1
            ;;
    esac
}

# 设置DEBUG_MODE
DEBUG_MODE="${DEBUG_MODE:-false}"
if [ "$DEBUG_MODE" = "true" ]; then
    log "🔧 调试模式已启用"
fi

main "$@"
