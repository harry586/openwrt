#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"

# 调试输出函数
debug_log() {
    if [ "$DEBUG_MODE" = "true" ]; then
        echo "🔍 $(date '+%Y-%m-%d %H:%M:%S')】$1"
    fi
}

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    echo "错误详情:"
    echo "当前目录: $(pwd)"
    echo "目录内容:"
    ls -la
    echo "环境变量:"
    env | grep -E "SELECTED|TARGET|SUBTARGET|DEVICE" || true
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
    log "✅ 环境变量已保存到 $ENV_FILE"
    
    # 调试输出
    debug_log "保存的环境变量:"
    debug_log "  SELECTED_REPO_URL=$SELECTED_REPO_URL"
    debug_log "  SELECTED_BRANCH=$SELECTED_BRANCH"
    debug_log "  TARGET=$TARGET"
    debug_log "  SUBTARGET=$SUBTARGET"
    debug_log "  DEVICE=$DEVICE"
    debug_log "  CONFIG_MODE=$CONFIG_MODE"
}

initialize_build_env() {
    local device_name=$1
    local version_selection=$2
    local config_mode=$3
    
    log "=== 初始化构建环境 ==="
    echo "设备: $device_name"
    echo "版本: $version_selection"
    echo "配置模式: $config_mode"
    
    # 确保在构建目录
    mkdir -p $BUILD_DIR
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
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
    
    # 克隆源码（修复目录已存在的问题）
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    debug_log "检查是否已有源码..."
    
    # 如果已经有源码，跳过克隆
    if [ -d ".git" ]; then
        log "源码已存在，跳过克隆"
        debug_log "更新源码..."
        git fetch --depth 1 origin "$SELECTED_BRANCH" || git pull origin "$SELECTED_BRANCH"
    else
        log "克隆源码..."
        
        # 检查目录是否为空（除了脚本文件）
        debug_log "清理构建目录..."
        # 备份脚本文件
        if [ -f "build_firmware_main.sh" ]; then
            cp build_firmware_main.sh /tmp/build_firmware_main.sh.bak
        fi
        
        # 清理目录（保留必要的）
        rm -rf ./* 2>/dev/null || true
        rm -rf .git 2>/dev/null || true
        
        # 恢复脚本
        if [ -f "/tmp/build_firmware_main.sh.bak" ]; then
            cp /tmp/build_firmware_main.sh.bak build_firmware_main.sh
            chmod +x build_firmware_main.sh
        fi
        
        debug_log "开始克隆..."
        git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . || handle_error "克隆源码失败"
        log "✅ 源码克隆完成"
        
        debug_log "源码克隆完成，目录内容:"
        ls -la
    fi
    
    # 输出到GitHub环境变量
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    
    # 输出到步骤输出
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_OUTPUT
    echo "TARGET=$TARGET" >> $GITHUB_OUTPUT
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_OUTPUT
    echo "DEVICE=$DEVICE" >> $GITHUB_OUTPUT
    
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

# 后续函数保持不变...
# 这里只展示修改的部分，其他函数保持原样

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
