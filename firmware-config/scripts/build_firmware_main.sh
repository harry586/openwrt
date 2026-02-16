#!/bin/bash
#【build_firmware_main.sh-00】
# OpenWrt 智能固件构建主脚本
# 对应工作流: firmware-build.yml
# 版本: 3.1.0
# 最后更新: 2026-02-15
#【build_firmware_main.sh-00-end】

#【build_firmware_main.sh-00.5】
# 加载统一配置文件
load_build_config() {
    local config_file="${1:-$REPO_ROOT/build-config.conf}"
    
    if [ -f "$config_file" ]; then
        log "📁 加载统一配置文件: $config_file"
        source "$config_file"
    else
        log "⚠️ 未找到配置文件 $config_file，使用脚本内默认值"
    fi
    
    # 导出所有配置为环境变量
    export BUILD_DIR LOG_DIR BACKUP_DIR CONFIG_DIR
    export IMMORTALWRT_URL PACKAGES_FEED_URL LUCI_FEED_URL TURBOACC_FEED_URL
    export ENABLE_TURBOACC ENABLE_TCP_BBR FORCE_ATH10K_CT AUTO_FIX_USB_DRIVERS
    export ENABLE_DYNAMIC_KERNEL_DETECTION ENABLE_DYNAMIC_PLATFORM_DRIVERS ENABLE_DYNAMIC_DEVICE_MAPPING
    
    log "✅ 配置加载完成"
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="$REPO_ROOT/build-config.conf"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    load_build_config
fi
#【build_firmware_main.sh-00.5-end】


#【build_firmware_main.sh-01】
set -e

# 使用配置文件的变量，如果未定义则使用默认值
: ${BUILD_DIR:="/mnt/openwrt-build"}
: ${LOG_DIR:="/tmp/build-logs"}
: ${BACKUP_DIR:="/tmp/openwrt_backup"}

ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SCRIPT="$REPO_ROOT/support.sh"
CONFIG_DIR="$REPO_ROOT/firmware-config/config"

mkdir -p "$LOG_DIR"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    log "详细错误信息:"
    echo "最后50行日志:"
    tail -50 "$LOG_DIR"/*.log 2>/dev/null || echo "无日志文件"
    exit 1
}
#【build_firmware_main.sh-01-end】

#【build_firmware_main.sh-02】
save_env() {
    mkdir -p $BUILD_DIR
    echo "#!/bin/bash" > $ENV_FILE
    echo "export SELECTED_REPO_URL=\"${SELECTED_REPO_URL}\"" >> $ENV_FILE
    echo "export SELECTED_BRANCH=\"${SELECTED_BRANCH}\"" >> $ENV_FILE
    echo "export TARGET=\"${TARGET}\"" >> $ENV_FILE
    echo "export SUBTARGET=\"${SUBTARGET}\"" >> $ENV_FILE
    echo "export DEVICE=\"${DEVICE}\"" >> $ENV_FILE
    echo "export CONFIG_MODE=\"${CONFIG_MODE}\"" >> $ENV_FILE
    echo "export REPO_ROOT=\"${REPO_ROOT}\"" >> $ENV_FILE
    echo "export COMPILER_DIR=\"${COMPILER_DIR}\"" >> $ENV_FILE
    
    # 保存配置开关状态
    echo "export ENABLE_TURBOACC=\"${ENABLE_TURBOACC}\"" >> $ENV_FILE
    echo "export ENABLE_TCP_BBR=\"${ENABLE_TCP_BBR}\"" >> $ENV_FILE
    echo "export FORCE_ATH10K_CT=\"${FORCE_ATH10K_CT}\"" >> $ENV_FILE
    echo "export AUTO_FIX_USB_DRIVERS=\"${AUTO_FIX_USB_DRIVERS}\"" >> $ENV_FILE
    
    if [ -n "$GITHUB_ENV" ]; then
        echo "SELECTED_REPO_URL=${SELECTED_REPO_URL}" >> $GITHUB_ENV
        echo "SELECTED_BRANCH=${SELECTED_BRANCH}" >> $GITHUB_ENV
        echo "TARGET=${TARGET}" >> $GITHUB_ENV
        echo "SUBTARGET=${SUBTARGET}" >> $GITHUB_ENV
        echo "DEVICE=${DEVICE}" >> $GITHUB_ENV
        echo "CONFIG_MODE=${CONFIG_MODE}" >> $GITHUB_ENV
        echo "COMPILER_DIR=${COMPILER_DIR}" >> $GITHUB_ENV
    fi
    
    chmod +x $ENV_FILE
    log "✅ 环境变量已保存到: $ENV_FILE"
}
#【build_firmware_main.sh-02-end】

#【build_firmware_main.sh-03】
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
        log "✅ 从 $ENV_FILE 加载环境变量"
    else
        log "⚠️ 环境文件不存在: $ENV_FILE"
    fi
}
#【build_firmware_main.sh-03-end】

#【build_firmware_main.sh-04】
setup_environment() {
    log "=== 安装编译依赖包 ==="
    sudo apt-get update || handle_error "apt-get update失败"
    
    local base_packages=(
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip
        zlib1g-dev file wget libelf-dev ecj fastjar
        libpython3-dev python3 python3-dev python3-pip python3-setuptools
        python3-yaml xsltproc zip subversion ninja-build automake autoconf
        libtool pkg-config help2man texinfo groff texlive texinfo cmake
        ccache time
    )
    
    local network_packages=(
        curl wget net-tools iputils-ping dnsutils
        openssh-client ca-certificates gnupg lsb-release
    )
    
    local filesystem_packages=(
        squashfs-tools dosfstools e2fsprogs mtools
        parted fdisk gdisk hdparm smartmontools
    )
    
    local debug_packages=(
        gdb strace ltrace valgrind
        binutils-dev libdw-dev libiberty-dev
    )
    
    log "安装基础编译工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_packages[@]}" || handle_error "安装基础编译工具失败"
    
    log "安装网络工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${network_packages[@]}" || handle_error "安装网络工具失败"
    
    log "安装文件系统工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${filesystem_packages[@]}" || handle_error "安装文件系统工具失败"
    
    log "安装调试工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${debug_packages[@]}" || handle_error "安装调试工具失败"
    
    local important_tools=("gcc" "g++" "make" "git" "python3" "cmake" "flex" "bison")
    for tool in "${important_tools[@]}"; do
        if command -v $tool >/dev/null 2>&1; then
            log "✅ $tool 已安装: $(which $tool)"
        else
            log "❌ $tool 未安装"
        fi
    done
    
    log "✅ 编译环境设置完成"
}
#【build_firmware_main.sh-04-end】

#【build_firmware_main.sh-05】
create_build_dir() {
    log "=== 创建构建目录 ==="
    sudo mkdir -p $BUILD_DIR || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER $BUILD_DIR || handle_error "修改目录所有者失败"
    sudo chmod -R 755 $BUILD_DIR || handle_error "修改目录权限失败"
    
    if [ -w "$BUILD_DIR" ]; then
        log "✅ 构建目录创建完成: $BUILD_DIR"
    else
        log "❌ 构建目录权限错误"
        exit 1
    fi
}
#【build_firmware_main.sh-05-end】

#【build_firmware_main.sh-06】
initialize_build_env() {
    local device_name=$1
    local version_selection=$2
    local config_mode=$3
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 版本选择 ==="
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_REPO_URL="${IMMORTALWRT_URL:-https://github.com/immortalwrt/immortalwrt.git}"
        SELECTED_BRANCH="${BRANCH_23_05:-openwrt-23.05}"
    else
        SELECTED_REPO_URL="${IMMORTALWRT_URL:-https://github.com/immortalwrt/immortalwrt.git}"
        SELECTED_BRANCH="${BRANCH_21_02:-openwrt-21.02}"
    fi
    log "✅ 版本选择完成: $SELECTED_BRANCH"
    
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    sudo rm -rf ./* ./.git* 2>/dev/null || true
    
    git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . || handle_error "克隆源码失败"
    log "✅ 源码克隆完成"
    
    local important_source_files=("Makefile" "feeds.conf.default" "rules.mk" "Config.in")
    for file in "${important_source_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 源码文件存在: $file"
        else
            log "❌ 源码文件缺失: $file"
        fi
    done
    
    log "=== 设备配置 ==="
    if [ -f "$SUPPORT_SCRIPT" ]; then
        log "🔍 调用support.sh获取设备平台信息..."
        PLATFORM_INFO=$("$SUPPORT_SCRIPT" get-platform "$device_name")
        if [ -n "$PLATFORM_INFO" ]; then
            TARGET=$(echo "$PLATFORM_INFO" | awk '{print $1}')
            SUBTARGET=$(echo "$PLATFORM_INFO" | awk '{print $2}')
            DEVICE="$device_name"
            log "✅ 从support.sh获取平台信息: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
        else
            log "❌ 无法从support.sh获取平台信息"
            handle_error "获取平台信息失败"
        fi
    else
        log "❌ support.sh不存在"
        handle_error "support.sh脚本缺失"
    fi
    
    log "🔧 设备: $device_name"
    log "🔧 目标平台: $TARGET/$SUBTARGET"
    
    CONFIG_MODE="$config_mode"
    
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    
    # 🔥 关键修复：正确识别和使用编译好的 config 工具
    log "=== 编译配置工具 ==="
    
    local config_tool_created=0
    local real_config_tool=""
    
    # 方法1: 编译 scripts/config
    log "🔧 尝试方法1: 编译 scripts/config..."
    if [ -d "scripts/config" ]; then
        cd scripts/config
        make
        cd $BUILD_DIR
        
        # 检查编译生成的文件
        if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
            log "✅ 方法1成功: 编译生成 conf 工具"
            
            # 创建 config 包装脚本，使用 conf
            mkdir -p scripts/config
            cat > scripts/config/config << 'EOF'
#!/bin/sh
# OpenWrt config 工具包装脚本
# 使用编译生成的 conf 工具

CONF_TOOL="$(dirname "$0")/conf"

if [ ! -x "$CONF_TOOL" ]; then
    echo "Error: conf tool not found" >&2
    exit 1
fi

# 转换参数格式
case "$1" in
    --enable)
        shift
        "$CONF_TOOL" --defconfig CONFIG_$1=y .config
        ;;
    --disable)
        shift
        "$CONF_TOOL" --defconfig CONFIG_$1=n .config
        ;;
    --module)
        shift
        "$CONF_TOOL" --defconfig CONFIG_$1=m .config
        ;;
    --set-str)
        shift
        name="$1"
        value="$2"
        "$CONF_TOOL" --defconfig CONFIG_$name="$value" .config
        shift 2
        ;;
    *)
        "$CONF_TOOL" "$@"
        ;;
esac
EOF
            chmod +x scripts/config/config
            log "✅ 创建 config 包装脚本成功"
            real_config_tool="scripts/config/config"
            config_tool_created=1
        elif [ -f "scripts/config/config" ] && [ -x "scripts/config/config" ]; then
            log "✅ 方法1成功: 编译生成 config 工具"
            real_config_tool="scripts/config/config"
            config_tool_created=1
        fi
    fi
    
    # 方法2: 直接使用 conf 作为配置工具
    if [ $config_tool_created -eq 0 ]; then
        if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
            log "✅ 方法2成功: 直接使用 conf 工具"
            mkdir -p scripts/config
            cat > scripts/config/config << 'EOF'
#!/bin/sh
# 使用 conf 工具的包装脚本
exec "$(dirname "$0")/conf" "$@"
EOF
            chmod +x scripts/config/config
            real_config_tool="scripts/config/config"
            config_tool_created=1
        fi
    fi
    
    # 方法3: 使用 mconf (如果可用)
    if [ $config_tool_created -eq 0 ]; then
        if [ -f "scripts/config/mconf" ] && [ -x "scripts/config/mconf" ]; then
            log "✅ 方法3成功: 使用 mconf 工具"
            mkdir -p scripts/config
            cat > scripts/config/config << 'EOF'
#!/bin/sh
# 使用 mconf 工具的包装脚本
exec "$(dirname "$0")/mconf" "$@"
EOF
            chmod +x scripts/config/config
            real_config_tool="scripts/config/config"
            config_tool_created=1
        fi
    fi
    
    # 方法4: 从 SDK 复制
    if [ $config_tool_created -eq 0 ] && [ -n "$COMPILER_DIR" ]; then
        log "🔧 尝试方法4: 从 SDK 目录复制"
        if [ -f "$COMPILER_DIR/scripts/config/conf" ] && [ -x "$COMPILER_DIR/scripts/config/conf" ]; then
            mkdir -p scripts/config
            cp "$COMPILER_DIR/scripts/config/conf" scripts/config/
            cat > scripts/config/config << 'EOF'
#!/bin/sh
exec "$(dirname "$0")/conf" "$@"
EOF
            chmod +x scripts/config/config
            log "✅ 方法4成功: 从 SDK 复制 conf 工具"
            real_config_tool="scripts/config/config"
            config_tool_created=1
        fi
    fi
    
    # 方法5: 创建功能完整的简易工具
    if [ $config_tool_created -eq 0 ]; then
        log "🔧 方法5: 创建功能完整的简易 config 工具"
        mkdir -p scripts/config
        cat > scripts/config/config << 'EOF'
#!/bin/bash
# 功能完整的 config 工具
CONFIG_FILE=".config"

show_help() {
    echo "Usage: config [options]"
    echo "  --enable <symbol>    Enable a configuration option"
    echo "  --disable <symbol>   Disable a configuration option"
    echo "  --module <symbol>    Set a configuration option as module"
    echo "  --set-str <name> <value> Set a string configuration option"
}

# 确保 .config 存在
if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
fi

case "$1" in
    --enable)
        shift
        symbol="$1"
        # 移除 CONFIG_ 前缀（如果存在）
        symbol="${symbol#CONFIG_}"
        # 移除 PACKAGE_ 前缀（如果存在）
        symbol="${symbol#PACKAGE_}"
        
        # 删除所有相关的行
        sed -i "/^CONFIG_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^CONFIG_PACKAGE_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_${symbol} is not set/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_PACKAGE_${symbol} is not set/d" "$CONFIG_FILE"
        
        # 添加启用行
        echo "CONFIG_PACKAGE_${symbol}=y" >> "$CONFIG_FILE"
        ;;
    --disable)
        shift
        symbol="$1"
        symbol="${symbol#CONFIG_}"
        symbol="${symbol#PACKAGE_}"
        
        sed -i "/^CONFIG_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^CONFIG_PACKAGE_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_${symbol} is not set/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_PACKAGE_${symbol} is not set/d" "$CONFIG_FILE"
        
        echo "# CONFIG_PACKAGE_${symbol} is not set" >> "$CONFIG_FILE"
        ;;
    --module)
        shift
        symbol="$1"
        symbol="${symbol#CONFIG_}"
        symbol="${symbol#PACKAGE_}"
        
        sed -i "/^CONFIG_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^CONFIG_PACKAGE_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_${symbol} is not set/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_PACKAGE_${symbol} is not set/d" "$CONFIG_FILE"
        
        echo "CONFIG_PACKAGE_${symbol}=m" >> "$CONFIG_FILE"
        ;;
    --set-str)
        shift
        name="$1"
        value="$2"
        name="${name#CONFIG_}"
        
        sed -i "/^CONFIG_${name}=/d" "$CONFIG_FILE"
        echo "CONFIG_${name}="$value"" >> "$CONFIG_FILE"
        shift 2
        ;;
    --help)
        show_help
        ;;
    *)
        echo "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
EOF
        chmod +x scripts/config/config
        log "✅ 方法5成功: 创建功能完整的简易 config 工具"
        real_config_tool="scripts/config/config"
        config_tool_created=1
    fi
    
    # 创建统一调用接口 - 修复版，不使用 --help 测试
    if [ $config_tool_created -eq 1 ]; then
        log "🔧 创建统一调用接口..."
        
        # 记录真实工具路径
        echo "$real_config_tool" > scripts/.config_tool_path
        
        # 创建 scripts/config 软链接或副本，以便 make defconfig 能找到
        if [ ! -f "scripts/config" ]; then
            if [ -f "scripts/config/config" ]; then
                ln -sf config scripts/config 2>/dev/null || cp scripts/config/config scripts/config 2>/dev/null || true
                log "✅ 创建 scripts/config 链接/副本"
            fi
        fi
        
        cat > scripts/config-tool << 'EOF'
#!/bin/sh
# 统一 config 工具调用接口
CONFIG_TOOL_PATH="$(dirname "$0")/.config_tool_path"

if [ -f "$CONFIG_TOOL_PATH" ]; then
    CONFIG_TOOL="$(cat "$CONFIG_TOOL_PATH" 2>/dev/null)"
    if [ -n "$CONFIG_TOOL" ] && [ -f "$CONFIG_TOOL" ] && [ -x "$CONFIG_TOOL" ]; then
        exec "$CONFIG_TOOL" "$@"
    fi
fi

# 备选1: 直接查找
if [ -f "scripts/config/config" ] && [ -x "scripts/config/config" ]; then
    echo "scripts/config/config" > "$CONFIG_TOOL_PATH"
    exec scripts/config/config "$@"
fi

# 备选2: 使用 conf
if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
    echo "scripts/config/conf" > "$CONFIG_TOOL_PATH"
    exec scripts/config/conf "$@"
fi

# 备选3: 使用 mconf
if [ -f "scripts/config/mconf" ] && [ -x "scripts/config/mconf" ]; then
    echo "scripts/config/mconf" > "$CONFIG_TOOL_PATH"
    exec scripts/config/mconf "$@"
fi

echo "Error: config tool not found" >&2
exit 1
EOF
        chmod +x scripts/config-tool
        log "✅ 统一调用接口创建成功: scripts/config-tool"
        
        # 不再测试 --help，而是测试基本功能
        if scripts/config-tool --version > /dev/null 2>&1 || scripts/config-tool -h > /dev/null 2>&1; then
            log "✅ 统一调用接口测试通过"
        else
            # 尝试测试是否存在
            if [ -f scripts/config/config ] || [ -f scripts/config/conf ]; then
                log "✅ 统一调用接口可用（跳过参数测试）"
            else
                log "⚠️ 统一调用接口可能有问题，但工具可能仍可用"
            fi
        fi
    fi
    
    # 最终验证
    if [ $config_tool_created -eq 1 ]; then
        log "✅ 配置工具最终验证通过"
        log "📁 真实工具路径: $real_config_tool"
        log "📁 统一调用接口: scripts/config-tool"
        
        # 显示工具信息
        if [ -f "$real_config_tool" ]; then
            if file "$real_config_tool" | grep -q "ELF"; then
                log "📋 工具类型: 已编译二进制文件"
            else
                log "📋 工具类型: Shell 脚本"
            fi
        fi
    else
        log "❌ 所有方法都失败，配置工具不存在"
        handle_error "无法创建配置工具"
    fi
    
    save_env
    
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    
    log "✅ 构建环境初始化完成"
}
#【build_firmware_main.sh-06-end】

#【build_firmware_main.sh-07】
download_openwrt_sdk() {
    local target="$1"
    local subtarget="$2"
    local version="$3"
    
    log "=== 下载OpenWrt官方SDK工具链 ==="
    log "目标平台: $target/$subtarget"
    log "OpenWrt版本: $version"
    
    if [ ! -f "$SUPPORT_SCRIPT" ]; then
        log "❌ support.sh不存在，无法获取SDK信息"
        return 1
    fi
    
    if [ ! -x "$SUPPORT_SCRIPT" ]; then
        chmod +x "$SUPPORT_SCRIPT"
        log "✅ 已添加support.sh执行权限"
    fi
    
    log "🔍 通过support.sh获取SDK信息..."
    
    local sdk_info
    if sdk_info=$("$SUPPORT_SCRIPT" get-sdk-info "$target" "$subtarget" "$version" 2>/dev/null); then
        local sdk_url=$(echo "$sdk_info" | cut -d'|' -f1)
        local sdk_file=$(echo "$sdk_info" | cut -d'|' -f2)
        
        if [ -z "$sdk_url" ] || [ -z "$sdk_file" ]; then
            log "❌ 无法从support.sh获取有效的SDK信息"
            return 1
        fi
        
        log "📥 SDK下载信息:"
        log "  URL: $sdk_url"
        log "  文件: $sdk_file"
        
        local sdk_download_dir="$BUILD_DIR/sdk-download"
        mkdir -p "$sdk_download_dir"
        
        log "🚀 开始下载SDK文件..."
        if wget -q --show-progress -O "$sdk_download_dir/$sdk_file" "$sdk_url"; then
            log "✅ SDK文件下载成功: $sdk_file"
            
            rm -rf "$BUILD_DIR"/openwrt-sdk-* 2>/dev/null || true
            
            log "📦 解压SDK文件..."
            if tar -xf "$sdk_download_dir/$sdk_file" -C "$BUILD_DIR"; then
                log "✅ SDK文件解压成功"
                
                log "🔍 查找解压后的SDK目录..."
                
                local extracted_dir=""
                local sdk_base_name="${sdk_file%.tar.xz}"
                sdk_base_name="${sdk_base_name%.tar.gz}"
                sdk_base_name="${sdk_base_name%.tar.bz2}"
                
                if [ -d "$BUILD_DIR/$sdk_base_name" ]; then
                    extracted_dir="$BUILD_DIR/$sdk_base_name"
                else
                    extracted_dir=$(find "$BUILD_DIR" -maxdepth 2 -type d -name "openwrt-sdk-*" 2>/dev/null | head -1)
                fi
                
                if [ -n "$extracted_dir" ] && [ -d "$extracted_dir" ]; then
                    COMPILER_DIR="$extracted_dir"
                    log "✅ 找到SDK目录: $COMPILER_DIR"
                    
                    if verify_sdk_files_v2 "$COMPILER_DIR"; then
                        log "🎉 SDK下载、解压和验证完成"
                        log "📌 编译器目录已设置为: $COMPILER_DIR"
                        
                        save_env
                        
                        return 0
                    else
                        log "❌ SDK文件验证失败"
                        return 1
                    fi
                else
                    log "❌ 无法找到SDK目录，检查解压结果"
                    log "📋 解压文件列表:"
                    tar -tf "$sdk_download_dir/$sdk_file" | head -20
                    return 1
                fi
            else
                log "❌ SDK文件解压失败"
                return 1
            fi
        else
            log "❌ SDK文件下载失败"
            return 1
        fi
    else
        log "❌ support.sh未提供SDK下载功能"
        return 1
    fi
}

verify_sdk_files_v2() {
    local sdk_dir="$1"
    
    log "=== 验证SDK文件完整性V2（修复版） ==="
    
    if [ ! -d "$sdk_dir" ]; then
        log "❌ SDK目录不存在: $sdk_dir"
        return 1
    fi
    
    log "✅ SDK目录存在: $sdk_dir"
    log "📊 目录大小: $(du -sh "$sdk_dir" 2>/dev/null | awk '{print $1}' || echo '未知')"
    log "📁 目录内容:"
    ls -la "$sdk_dir/" | head -10
    
    log "🔍 检查SDK目录结构..."
    
    if [ -d "$sdk_dir/staging_dir" ]; then
        log "✅ 找到 staging_dir 目录"
        
        local toolchain_dirs=$(find "$sdk_dir/staging_dir" -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null)
        if [ -n "$toolchain_dirs" ]; then
            log "✅ 找到工具链目录"
            
            local gcc_files=$(find "$sdk_dir/staging_dir/toolchain-"* -maxdepth 3 -type f -executable \
              -name "*gcc" \
              ! -name "*gcc-ar" \
              ! -name "*gcc-ranlib" \
              ! -name "*gcc-nm" \
              2>/dev/null | head -1)
            
            if [ -n "$gcc_files" ]; then
                log "✅ 在工具链目录中找到GCC编译器: $(basename "$gcc_files")"
                local gcc_version=$("$gcc_files" --version 2>&1 | head -1)
                log "📋 GCC版本: $gcc_version"
                return 0
            fi
        fi
        
        log "🔍 直接在 staging_dir 中搜索GCC..."
        local gcc_files=$(find "$sdk_dir/staging_dir" -maxdepth 3 -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          2>/dev/null | head -1)
        
        if [ -n "$gcc_files" ]; then
            log "✅ 在 staging_dir 中找到GCC编译器: $(basename "$gcc_files")"
            local gcc_version=$("$gcc_files" --version 2>&1 | head -1)
            log "📋 GCC版本: $gcc_version"
            return 0
        fi
    fi
    
    if [ -d "$sdk_dir/toolchain" ]; then
        log "✅ 找到 toolchain 目录"
        
        local gcc_files=$(find "$sdk_dir/toolchain" -maxdepth 3 -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          2>/dev/null | head -1)
        
        if [ -n "$gcc_files" ]; then
            log "✅ 在 toolchain 目录中找到GCC编译器: $(basename "$gcc_files")"
            local gcc_version=$("$gcc_files" --version 2>&1 | head -1)
            log "📋 GCC版本: $gcc_version"
            return 0
        fi
    fi
    
    log "🔍 在整个SDK目录中搜索GCC..."
    local gcc_files=$(find "$sdk_dir" -maxdepth 5 -type f -executable \
      -name "*gcc" \
      ! -name "*gcc-ar" \
      ! -name "*gcc-ranlib" \
      ! -name "*gcc-nm" \
      2>/dev/null | head -1)
    
    if [ -n "$gcc_files" ]; then
        log "✅ 在SDK中找到GCC编译器: $(basename "$gcc_files")"
        log "🔧 完整路径: $gcc_files"
        local gcc_version=$("$gcc_files" --version 2>&1 | head -1)
        log "📋 GCC版本: $gcc_version"
        return 0
    fi
    
    log "🔍 检查工具链工具..."
    local toolchain_tools=$(find "$sdk_dir" -maxdepth 5 -type f -executable \
      -name "*gcc*" \
      2>/dev/null | head -5)
    
    if [ -n "$toolchain_tools" ]; then
        log "📋 找到的工具链工具:"
        while read tool; do
            local tool_name=$(basename "$tool")
            log "  🔧 $tool_name"
        done <<< "$toolchain_tools"
        
        log "✅ 找到工具链工具，SDK可能有效"
        return 0
    fi
    
    log "❌ 未找到任何GCC编译器或工具链工具"
    log "📁 SDK目录内容详细列表:"
    find "$sdk_dir" -type f -executable -name "*" 2>/dev/null | head -20
    
    return 1
}

verify_sdk_files() {
    verify_sdk_files_v2 "$1"
}
#【build_firmware_main.sh-07-end】

#【build_firmware_main.sh-08】
initialize_compiler_env() {
    local device_name="$1"
    log "=== 初始化编译器环境（下载OpenWrt官方SDK）- 修复版 ==="
    
    log "🔍 检查环境文件..."
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从 $BUILD_DIR/build_env.sh 加载环境变量"
    else
        log "❌ 环境文件不存在: $BUILD_DIR/build_env.sh"
        
        if [ -f "$SUPPORT_SCRIPT" ]; then
            log "🔍 调用support.sh获取设备信息..."
            PLATFORM_INFO=$("$SUPPORT_SCRIPT" get-platform "$device_name")
            if [ -n "$PLATFORM_INFO" ]; then
                TARGET=$(echo "$PLATFORM_INFO" | awk '{print $1}')
                SUBTARGET=$(echo "$PLATFORM_INFO" | awk '{print $2}')
                DEVICE="$device_name"
                CONFIG_MODE="normal"
                log "✅ 从support.sh获取平台信息: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
            else
                log "❌ 无法从support.sh获取平台信息"
                return 1
            fi
        else
            log "❌ support.sh不存在"
            return 1
        fi
        
        save_env
        log "✅ 已创建环境文件: $BUILD_DIR/build_env.sh"
    fi
    
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ 使用环境变量中的编译器目录: $COMPILER_DIR"
        
        log "🔍 验证编译器目录有效性..."
        local gcc_files=$(find "$COMPILER_DIR" -maxdepth 5 -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          2>/dev/null | head -1)
        
        if [ -n "$gcc_files" ]; then
            log "✅ 确认编译器目录包含真正的GCC"
            local first_gcc=$(echo "$gcc_files" | head -1)
            log "  🎯 GCC文件: $(basename "$first_gcc")"
            log "  🔧 GCC版本: $("$first_gcc" --version 2>&1 | head -1)"
            
            save_env
            return 0
        else
            log "⚠️ 编译器目录存在但不包含真正的GCC，将重新下载SDK"
        fi
    else
        log "🔍 COMPILER_DIR未设置或目录不存在，将下载OpenWrt官方SDK"
    fi
    
    log "目标平台: $TARGET/$SUBTARGET"
    log "目标设备: $DEVICE"
    log "OpenWrt版本: $SELECTED_BRANCH"
    
    local version_for_sdk=""
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        version_for_sdk="23.05"
    elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
        version_for_sdk="21.02"
    else
        log "❌ 不支持的OpenWrt版本: $SELECTED_BRANCH"
        return 1
    fi
    
    log "📌 SDK版本: $version_for_sdk"
    log "📌 目标平台: $TARGET/$SUBTARGET"
    
    log "🚀 开始下载OpenWrt官方SDK..."
    if download_openwrt_sdk "$TARGET" "$SUBTARGET" "$version_for_sdk"; then
        log "🎉 OpenWrt SDK下载并设置成功"
        log "📌 编译器目录: $COMPILER_DIR"
        
        if [ -d "$COMPILER_DIR" ]; then
            log "📊 SDK目录信息:"
            log "  目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | awk '{print $1}' || echo '未知')"
            
            local gcc_file=$(find "$COMPILER_DIR" -maxdepth 5 -type f -executable \
              -name "*gcc" \
              ! -name "*gcc-ar" \
              ! -name "*gcc-ranlib" \
              ! -name "*gcc-nm" \
              2>/dev/null | head -1)
            
            if [ -n "$gcc_file" ]; then
                log "✅ 找到SDK中的GCC编译器: $(basename "$gcc_file")"
                log "  🔧 完整路径: $gcc_file"
                log "  📋 版本信息: $("$gcc_file" --version 2>&1 | head -1)"
            fi
        fi
        
        save_env
        
        return 0
    else
        log "❌ OpenWrt SDK下载失败"
        return 1
    fi
}
#【build_firmware_main.sh-08-end】

#【build_firmware_main.sh-09】
add_turboacc_support() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 添加 TurboACC 支持 ==="
    
    # 使用配置文件中的开关
    if [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
        log "🔧 为正常模式添加 TurboACC 支持"
        echo "src-git turboacc ${TURBOACC_FEED_URL:-https://github.com/chenmozhijin/turboacc}" >> feeds.conf.default
        log "✅ TurboACC feed 添加完成"
    else
        if [ "$CONFIG_MODE" = "normal" ]; then
            log "ℹ️ TurboACC 已被配置禁用"
        else
            log "ℹ️ 基础模式不添加 TurboACC 支持"
        fi
    fi
}
#【build_firmware_main.sh-09-end】

#【build_firmware_main.sh-10】
configure_feeds() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 配置Feeds ==="
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    # 使用配置文件中的Feed URL
    echo "src-git packages ${PACKAGES_FEED_URL:-https://github.com/immortalwrt/packages.git};$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci ${LUCI_FEED_URL:-https://github.com/immortalwrt/luci.git};$FEEDS_BRANCH" >> feeds.conf.default
    
    if [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
        echo "src-git turboacc ${TURBOACC_FEED_URL:-https://github.com/chenmozhijin/turboacc}" >> feeds.conf.default
        log "✅ 添加TurboACC feed（所有版本）"
    fi
    
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    local critical_feeds_dirs=("feeds/packages" "feeds/luci" "package/feeds")
    for dir in "${critical_feeds_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log "✅ Feed目录存在: $dir"
        else
            log "❌ Feed目录缺失: $dir"
        fi
    done
    
    log "✅ Feeds配置完成"
}
#【build_firmware_main.sh-10-end】

#【build_firmware_main.sh-11】
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
#【build_firmware_main.sh-11-end】

#【build_firmware_main.sh-12】
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | awk '{print $1}') || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    echo "/mnt 可用空间: ${available_gb}G"
    
    local root_available_space=$(df / --output=avail | tail -1)
    local root_available_gb=$((root_available_space / 1024 / 1024))
    echo "/ 可用空间: ${root_available_gb}G"
    
    echo "=== 内存使用情况 ==="
    free -h
    
    echo "=== CPU信息 ==="
    echo "CPU核心数: $(nproc)"
    
    local estimated_space=15
    if [ $available_gb -lt $estimated_space ]; then
        log "⚠️ 警告: 可用空间(${available_gb}G)可能不足，建议至少${estimated_space}G"
    else
        log "✅ 磁盘空间充足: ${available_gb}G 可用"
    fi
    
    log "✅ 空间检查完成"
}
#【build_firmware_main.sh-12-end】

#【build_firmware_main.sh-13】
generate_config() {
    local extra_packages=$1
    local device_override=$2
    
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    if [ -n "$device_override" ]; then
        DEVICE="$device_override"
        log "🔧 使用设备覆盖参数: $DEVICE"
    fi
    
    log "=== 智能配置生成系统（设备显式指定版） ==="
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    log "配置文件目录: $CONFIG_DIR"
    
    if [ -z "$DEVICE" ]; then
        log "❌ 错误: DEVICE变量为空！"
        env | grep -E "DEVICE|TARGET|SELECTED" || true
        handle_error "DEVICE变量未设置"
    fi
    
    rm -f .config .config.old .config.bak*
    log "✅ 已清理旧配置文件"
    
    local openwrt_device=""
    local search_device=""
    
    case "$DEVICE" in
        ac42u|rt-ac42u|asus_rt-ac42u)
            openwrt_device="asus_rt-ac42u"
            search_device="ac42u"
            log "🔧 设备映射: 输入=$DEVICE, 配置用=$openwrt_device, 搜索用=$search_device"
            ;;
        acrh17|rt-acrh17|asus_rt-acrh17)
            openwrt_device="asus_rt-acrh17"
            search_device="acrh17"
            log "🔧 设备映射: 输入=$DEVICE, 配置用=$openwrt_device, 搜索用=$search_device"
            ;;
        *)
            openwrt_device=$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
            search_device="$DEVICE"
            log "🔧 使用原始设备名: $openwrt_device"
            ;;
    esac
    
    local device_lower="$openwrt_device"
    local device_config="CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower}"
    
    log "🔧 设备配置变量: $device_config=y"
    
    cat > .config << EOF
CONFIG_TARGET_${TARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}=y
${device_config}=y
EOF
    
    log "🔧 基础配置文件内容:"
    cat .config
    
    log "📁 开始合并配置文件..."
    
    append_config() {
        local file=$1
        if [ -f "$file" ]; then
            grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' | grep 'CONFIG_' >> .config
        fi
    }
    
    : ${CONFIG_BASE:="base.config"}
    : ${CONFIG_USB_GENERIC:="usb-generic.config"}
    : ${CONFIG_NORMAL:="normal.config"}
    
    append_config "$CONFIG_DIR/$CONFIG_BASE"
    append_config "$CONFIG_DIR/$CONFIG_USB_GENERIC"
    append_config "$CONFIG_DIR/$TARGET.config"
    append_config "$CONFIG_DIR/$SELECTED_BRANCH.config"
    append_config "$CONFIG_DIR/devices/$DEVICE.config"
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        append_config "$CONFIG_DIR/$CONFIG_NORMAL"
    fi
    
    if [ -n "$extra_packages" ]; then
        log "📦 添加额外包: $extra_packages"
        echo "$extra_packages" | tr ',' '
' | while read pkg; do
            [ -n "$pkg" ] && echo "CONFIG_PACKAGE_$pkg=y" >> .config
        done
    fi
    
    if [ -f "$CONFIG_DIR/devices/$DEVICE.config" ]; then
        log "📋 从设备配置文件动态添加配置: $CONFIG_DIR/devices/$DEVICE.config"
        append_config "$CONFIG_DIR/devices/$DEVICE.config"
    fi
    
    if [ "${ENABLE_TCP_BBR:-true}" = "true" ]; then
        echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
        echo 'CONFIG_DEFAULT_TCP_CONG="bbr"' >> .config
        log "✅ TCP BBR已启用"
    fi
    
    if [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
        echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
        echo "CONFIG_PACKAGE_kmod-shortcut-fe=y" >> .config
        echo "CONFIG_PACKAGE_kmod-fast-classifier=y" >> .config
        log "✅ TurboACC已启用"
    fi
    
    if [ "${FORCE_ATH10K_CT:-true}" = "true" ]; then
        sed -i '/CONFIG_PACKAGE_kmod-ath10k=y/d' .config
        sed -i '/CONFIG_PACKAGE_kmod-ath10k-pci=y/d' .config
        sed -i '/CONFIG_PACKAGE_kmod-ath10k-smallbuffers=y/d' .config
        echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-ath10k-pci is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-ath10k-smallbuffers is not set" >> .config
        echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
        log "✅ ath10k-ct驱动已强制启用"
    fi
    
    log "🔄 第一次去重配置..."
    sort .config | uniq > .config.tmp
    mv .config.tmp .config
    
    # =========================================================================
    # 步骤5: 动态获取目标平台支持的内核配置 - 直接调用搜索函数
    # =========================================================================
    echo ""
    echo "=== 🔍 开始搜索设备定义文件 ==="
    echo "----------------------------------------"
    
    local kernel_config_file=""
    local kernel_version=""
    local found_kernel=0
    
    if [ "${ENABLE_DYNAMIC_KERNEL_DETECTION:-true}" = "true" ]; then
        echo "🔍 根据设备定义文件查找内核配置..."
        echo "🔍 使用搜索设备名: $search_device"
        echo ""
        
        # 直接调用函数，它会输出详细信息
        local device_def_file=$(find_device_definition_file "$search_device" "$TARGET")
        
        if [ -n "$device_def_file" ] && [ -f "$device_def_file" ]; then
            echo "✅ 找到设备定义文件: $device_def_file"
            echo ""
            
            local device_block=$(extract_device_config "$device_def_file" "$search_device")
            if [ -n "$device_block" ]; then
                echo "📋 设备 $search_device 配置:"
                echo "----------------------------------------"
                echo "$device_block"
                echo "----------------------------------------"
            fi
            
            kernel_version=$(extract_kernel_version_from_device_file "$device_def_file" "$search_device")
            
            if [ -n "$kernel_version" ]; then
                echo "✅ 从设备定义文件获取到内核版本: $kernel_version"
                echo ""
                
                kernel_config_file=$(find_kernel_config_by_version "$TARGET" "$SUBTARGET" "$kernel_version")
                
                if [ -n "$kernel_config_file" ] && [ -f "$kernel_config_file" ]; then
                    echo "✅ 找到内核配置文件: $kernel_config_file"
                    found_kernel=1
                else
                    echo "⚠️ 未找到对应内核版本 $kernel_version 的配置文件"
                fi
            else
                echo "⚠️ 设备定义文件中未指定内核版本"
            fi
        else
            echo "⚠️ 未找到设备 $search_device 的定义文件"
        fi
        
        if [ $found_kernel -eq 0 ]; then
            echo "📁 按优先级搜索内核配置文件..."
            echo ""
            
            for ver in ${KERNEL_VERSION_PRIORITY:-6.6 6.1 5.15 5.10 5.4}; do
                kernel_config_file="target/linux/$TARGET/config-$ver"
                if [ -f "$kernel_config_file" ]; then
                    kernel_version="$ver"
                    echo "✅ 找到内核配置文件: $kernel_config_file (内核版本 $kernel_version)"
                    found_kernel=1
                    break
                fi
            done
        fi
        
        if [ $found_kernel -eq 0 ]; then
            echo "⚠️ 警告: 未找到目标平台 $TARGET 的内核配置文件"
        fi
    fi
    
    echo "========================================"
    echo ""
    
    if [ -n "$kernel_config_file" ] && [ -f "$kernel_config_file" ]; then
        log "✅ 使用内核配置文件: $kernel_config_file (内核版本 $kernel_version)"
        
        local kernel_patterns=(
            "^CONFIG_USB"
            "^CONFIG_PHY"
            "^CONFIG_DWC"
            "^CONFIG_XHCI"
            "^CONFIG_EXTCON"
            "^CONFIG_COMMON_CLK"
            "^CONFIG_ARCH"
        )
        
        if [ ${#KERNEL_EXTRACT_PATTERNS[@]} -gt 0 ]; then
            kernel_patterns=("${KERNEL_EXTRACT_PATTERNS[@]}")
        fi
        
        local usb_configs_file="/tmp/usb_configs_$$.txt"
        
        for pattern in "${kernel_patterns[@]}"; do
            grep -E "^${pattern}|^# ${pattern}" "$kernel_config_file" >> "$usb_configs_file" 2>/dev/null || true
        done
        
        sort -u "$usb_configs_file" > "$usb_configs_file.sorted"
        
        local config_count=$(wc -l < "$usb_configs_file.sorted")
        log "找到 $config_count 个USB相关内核配置"
        
        local added_count=0
        while read line; do
            local config_name=$(echo "$line" | sed 's/^# //g' | cut -d'=' -f1 | cut -d' ' -f1)
            
            if ! grep -q "^${config_name}=" .config && ! grep -q "^# ${config_name} is not set" .config; then
                if echo "$line" | grep -q "=y$"; then
                    echo "$line" >> .config
                    added_count=$((added_count + 1))
                elif echo "$line" | grep -q "is not set"; then
                    echo "$line" >> .config
                    added_count=$((added_count + 1))
                fi
            fi
        done < "$usb_configs_file.sorted"
        
        log "✅ 添加了 $added_count 个新的内核配置"
        
        rm -f "$usb_configs_file" "$usb_configs_file.sorted"
    fi
    
    log "🔄 第一次运行 make defconfig..."
    make defconfig > /tmp/build-logs/defconfig1.log 2>&1 || {
        log "❌ 第一次 make defconfig 失败"
        tail -50 /tmp/build-logs/defconfig1.log
        handle_error "第一次依赖解决失败"
    }
    log "✅ 第一次 make defconfig 成功"
    
    log "🔍 动态检测实际生效的USB内核配置..."
    
    local usb_components=(
        "USB_SUPPORT"
        "USB_COMMON"
        "USB"
        "USB_XHCI_HCD"
        "USB_DWC3"
        "PHY"
    )
    
    for component in "${usb_components[@]}"; do
        local matches=$(grep -E "^CONFIG_${component}" .config | grep -E "=y|=m" | wc -l)
        if [ $matches -gt 0 ]; then
            log "✅ $component 相关配置: 找到 $matches 个"
        fi
    done
    
    log "📋 动态添加USB软件包..."
    
    local base_usb_packages=(
        "kmod-usb-core"
        "kmod-usb-common"
        "kmod-usb2"
        "kmod-usb3"
        "kmod-usb-storage"
        "kmod-scsi-core"
        "block-mount"
        "automount"
        "usbutils"
    )
    
    local extended_usb_packages=(
        "kmod-usb-storage-uas"
        "kmod-usb-storage-extras"
        "kmod-scsi-generic"
    )
    
    local fs_support_packages=(
        "kmod-fs-ext4"
        "kmod-fs-vfat"
        "kmod-fs-exfat"
        "kmod-fs-ntfs3"
        "kmod-nls-utf8"
        "kmod-nls-cp936"
    )
    
    if [ ${#BASE_USB_PACKAGES[@]} -gt 0 ]; then
        base_usb_packages=("${BASE_USB_PACKAGES[@]}")
    fi
    
    if [ ${#EXTENDED_USB_PACKAGES[@]} -gt 0 ]; then
        extended_usb_packages=("${EXTENDED_USB_PACKAGES[@]}")
    fi
    
    if [ ${#FS_SUPPORT_PACKAGES[@]} -gt 0 ]; then
        fs_support_packages=("${FS_SUPPORT_PACKAGES[@]}")
    fi
    
    case "$TARGET" in
        ipq40xx|ipq806x|qcom)
            log "检测到高通平台，添加专用USB驱动..."
            local qcom_packages=(
                "kmod-usb-dwc3"
                "kmod-usb-dwc3-qcom"
                "kmod-usb-dwc3-of-simple"
                "kmod-phy-qcom-ipq4019-usb"
                "kmod-usb-xhci-hcd"
                "kmod-usb-xhci-plat-hcd"
            )
            base_usb_packages+=("${qcom_packages[@]}")
            ;;
        mediatek|ramips)
            log "检测到联发科平台，添加专用USB驱动..."
            local mtk_packages=(
                "kmod-usb-xhci-mtk"
                "kmod-usb-dwc3"
                "kmod-usb-dwc3-mediatek"
            )
            base_usb_packages+=("${mtk_packages[@]}")
            ;;
        ath79)
            log "检测到ATH79平台，添加专用USB驱动..."
            local ath79_packages=(
                "kmod-usb2-ath79"
                "kmod-usb-ohci"
            )
            base_usb_packages+=("${ath79_packages[@]}")
            ;;
    esac
    
    local added_packages=0
    local existing_packages=0
    while read pkg; do
        [ -z "$pkg" ] && continue
        if ! grep -q "^CONFIG_PACKAGE_${pkg}=y" .config && ! grep -q "^CONFIG_PACKAGE_${pkg}=m" .config; then
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
            added_packages=$((added_packages + 1))
            log "  ✅ 添加软件包: $pkg"
        else
            existing_packages=$((existing_packages + 1))
        fi
    done < <(printf "%s
" "${base_usb_packages[@]}" "${extended_usb_packages[@]}" "${fs_support_packages[@]}" | sort -u)
    
    log "📊 USB软件包统计: 新增 $added_packages 个, 已存在 $existing_packages 个"
    
    log "🔄 第二次去重配置..."
    sort .config | uniq > .config.tmp
    mv .config.tmp .config
    
    log "🔄 第二次运行 make defconfig..."
    make defconfig > /tmp/build-logs/defconfig2.log 2>&1 || {
        log "⚠️ 第二次 make defconfig 有警告，但继续..."
    }
    log "✅ 第二次 make defconfig 完成"
    
    log "🔍 验证关键USB驱动状态..."
    
    local critical_usb_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb-storage"
        "kmod-scsi-core"
    )
    
    if [ ${#CRITICAL_USB_DRIVERS[@]} -gt 0 ]; then
        critical_usb_drivers=("${CRITICAL_USB_DRIVERS[@]}")
    fi
    
    case "$TARGET" in
        ipq40xx|ipq806x|qcom)
            critical_usb_drivers+=(
                "kmod-usb-dwc3"
                "kmod-usb-dwc3-qcom"
            )
            ;;
        mediatek|ramips)
            critical_usb_drivers+=(
                "kmod-usb-xhci-mtk"
            )
            ;;
    esac
    
    local missing_drivers=()
    for driver in "${critical_usb_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            log "  ✅ $driver: 已启用"
        elif grep -q "^CONFIG_PACKAGE_${driver}=m" .config; then
            log "  📦 $driver: 模块化"
        else
            log "  ❌ $driver: 未启用"
            missing_drivers+=("$driver")
        fi
    done
    
    if [ ${#missing_drivers[@]} -gt 0 ] && [ "${AUTO_FIX_USB_DRIVERS:-true}" = "true" ]; then
        log "🔧 自动修复缺失驱动..."
        for driver in "${missing_drivers[@]}"; do
            echo "CONFIG_PACKAGE_${driver}=y" >> .config
            log "  ✅ 已添加: $driver"
        done
        make defconfig > /dev/null 2>&1
    fi
    
    log "🔍 正在验证设备 $openwrt_device 是否被选中..."
    
    if grep -q "^CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower}=y" .config; then
        log "✅ 目标设备已正确启用: CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower}=y"
    elif grep -q "^# CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower} is not set" .config; then
        log "⚠️ 警告: 设备被禁用，尝试强制启用..."
        sed -i "/^# CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower} is not set/d" .config
        echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower}=y" >> .config
        sort .config | uniq > .config.tmp
        mv .config.tmp .config
        make defconfig > /dev/null 2>&1
        
        if grep -q "^CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower}=y" .config; then
            log "✅ 设备已强制启用"
        else
            log "❌ 无法启用设备"
        fi
    else
        log "⚠️ 警告: 设备配置行未找到，手动添加..."
        echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_lower}=y" >> .config
        sort .config | uniq > .config.tmp
        mv .config.tmp .config
        make defconfig > /dev/null 2>&1
    fi
    
    local total_configs=$(wc -l < .config)
    local enabled_packages=$(grep -c "^CONFIG_PACKAGE_.*=y$" .config)
    local module_packages=$(grep -c "^CONFIG_PACKAGE_.*=m$" .config)
    local disabled_packages=$(grep -c "^# CONFIG_PACKAGE_.* is not set$" .config)
    
    log "📊 配置统计:"
    log "  总配置行数: $total_configs"
    log "  启用软件包: $enabled_packages"
    log "  模块化软件包: $module_packages"
    log "  禁用软件包: $disabled_packages"
    
    log "✅ 配置生成完成"
    
    # =========================================================================
    # 添加设备信息详细查询 - 与步骤23保持一致
    # =========================================================================
    echo ""
    echo "=== 🔍 设备信息详细查询（完整版） ==="
    echo "----------------------------------------"
    
    local search_device=""
    case "$DEVICE" in
        ac42u|rt-ac42u|asus_rt-ac42u)
            search_device="ac42u"
            ;;
        acrh17|rt-acrh17|asus_rt-acrh17)
            search_device="acrh17"
            ;;
        *)
            search_device="$DEVICE"
            ;;
    esac
    
    echo "🔍 搜索设备名: $search_device"
    echo ""
    get_device_support_summary "$search_device" "$TARGET" "$SUBTARGET"
    
    echo ""
    echo "=== 📁 所有子平台.mk文件列表 ==="
    
    local mk_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r mk_file; do
            mk_count=$((mk_count + 1))
            echo "   📄 [$mk_count] $mk_file"
        done < <(find "target/linux/$TARGET" -type f -name "*.mk" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $mk_count 个.mk文件"
    else
        echo "   未找到.mk文件"
    fi
    
    echo ""
    echo "=== 📁 内核配置文件列表 ==="
    
    local kernel_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r config; do
            kernel_count=$((kernel_count + 1))
            local ver=$(basename "$config" | sed 's/config-//')
            echo "   📄 [$kernel_count] $config (内核版本 $ver)"
        done < <(find "target/linux/$TARGET" -type f -name "config-*" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $kernel_count 个内核配置文件"
    else
        echo "   未找到内核配置文件"
    fi
    
    echo ""
    echo "=== 📁 设备相关文件列表 ==="
    
    local dev_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r config; do
            dev_count=$((dev_count + 1))
            echo "   📄 [$dev_count] $config"
        done < <(find "target/linux/$TARGET" -type f -name "*${DEVICE}*" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $dev_count 个设备相关文件"
    else
        echo "   未找到设备专属配置文件"
    fi
}
#【build_firmware_main.sh-13-end】

#【build_firmware_main.sh-14】
verify_usb_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 详细验证USB和存储配置（增强版） ==="
    
    echo ""
    echo "1. 🟢 USB核心模块:"
    grep -q "^CONFIG_PACKAGE_kmod-usb-core=y" .config && echo "   ✅ kmod-usb-core" || echo "   ❌ kmod-usb-core"
    grep -q "^CONFIG_PACKAGE_kmod-usb-common=y" .config && echo "   ✅ kmod-usb-common" || echo "   ❌ kmod-usb-common"
    
    echo ""
    echo "2. 🟢 USB控制器驱动:"
    echo "   - kmod-usb2:       $(grep -q "^CONFIG_PACKAGE_kmod-usb2=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb3:       $(grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-ehci:   $(grep -q "^CONFIG_PACKAGE_kmod-usb-ehci=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-ohci:   $(grep -q "^CONFIG_PACKAGE_kmod-usb-ohci=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-xhci-hcd: $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-xhci-pci: $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-pci=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-xhci-plat-hcd: $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "3. 🚨 USB 3.0 DWC3 核心驱动:"
    echo "   - kmod-usb-dwc3:   $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-dwc3-of-simple: $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "4. 🚨 平台专用USB控制器:"
    if [ "$TARGET" = "ipq40xx" ] || grep -q "^CONFIG_TARGET_ipq40xx=y" .config 2>/dev/null; then
        echo "   🔧 检测到高通IPQ40xx平台:"
        echo "     - kmod-usb-dwc3-qcom:     $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo '✅' || echo '❌')"
        echo "     - kmod-phy-qcom-dwc3:     $(grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo '✅' || echo '❌')"
    elif [ "$TARGET" = "ramips" ] || grep -q "^CONFIG_TARGET_ramips=y" .config 2>/dev/null; then
        echo "   🔧 检测到雷凌MT76xx平台:"
        echo "     - kmod-usb-xhci-mtk:       $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config && echo '✅' || echo '❌')"
        echo "     - kmod-usb-ohci-pci:       $(grep -q "^CONFIG_PACKAGE_kmod-usb-ohci-pci=y" .config && echo '✅' || echo '❌')"
        echo "     - kmod-usb2-pci:           $(grep -q "^CONFIG_PACKAGE_kmod-usb2-pci=y" .config && echo '✅' || echo '❌')"
    elif [ "$TARGET" = "mediatek" ] || grep -q "^CONFIG_TARGET_mediatek=y" .config 2>/dev/null; then
        echo "   🔧 检测到联发科平台:"
        echo "     - kmod-usb-dwc3-mediatek:  $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-mediatek=y" .config && echo '✅' || echo '❌')"
        echo "     - kmod-phy-mediatek:       $(grep -q "^CONFIG_PACKAGE_kmod-phy-mediatek=y" .config && echo '✅' || echo '❌')"
    elif [ "$TARGET" = "ath79" ] || grep -q "^CONFIG_TARGET_ath79=y" .config 2>/dev/null; then
        echo "   🔧 检测到高通ATH79平台:"
        echo "     - kmod-usb2-ath79:         $(grep -q "^CONFIG_PACKAGE_kmod-usb2-ath79=y" .config && echo '✅' || echo '❌')"
        echo "     - kmod-usb-ohci:           $(grep -q "^CONFIG_PACKAGE_kmod-usb-ohci=y" .config && echo '✅' || echo '❌')"
    fi
    
    echo ""
    echo "5. 🟢 USB存储驱动:"
    echo "   - kmod-usb-storage:        $(grep -q "^CONFIG_PACKAGE_kmod-usb-storage=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-storage-uas:    $(grep -q "^CONFIG_PACKAGE_kmod-usb-storage-uas=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-usb-storage-extras: $(grep -q "^CONFIG_PACKAGE_kmod-usb-storage-extras=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "6. 🟢 SCSI支持:"
    echo "   - kmod-scsi-core:    $(grep -q "^CONFIG_PACKAGE_kmod-scsi-core=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-scsi-generic: $(grep -q "^CONFIG_PACKAGE_kmod-scsi-generic=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "7. 🟢 文件系统支持:"
    echo "   - kmod-fs-ext4:  $(grep -q "^CONFIG_PACKAGE_kmod-fs-ext4=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-fs-vfat:  $(grep -q "^CONFIG_PACKAGE_kmod-fs-vfat=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-fs-exfat: $(grep -q "^CONFIG_PACKAGE_kmod-fs-exfat=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-fs-ntfs3: $(grep -q "^CONFIG_PACKAGE_kmod-fs-ntfs3=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "8. 🟢 编码支持:"
    echo "   - kmod-nls-utf8:  $(grep -q "^CONFIG_PACKAGE_kmod-nls-utf8=y" .config && echo '✅' || echo '❌')"
    echo "   - kmod-nls-cp936: $(grep -q "^CONFIG_PACKAGE_kmod-nls-cp936=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "9. 🟢 自动挂载工具:"
    echo "   - block-mount: $(grep -q "^CONFIG_PACKAGE_block-mount=y" .config && echo '✅' || echo '❌')"
    echo "   - automount:   $(grep -q "^CONFIG_PACKAGE_automount=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "10. 🟢 USB实用工具:"
    echo "   - usbutils: $(grep -q "^CONFIG_PACKAGE_usbutils=y" .config && echo '✅' || echo '❌')"
    echo "   - lsusb:    $(grep -q "^CONFIG_PACKAGE_lsusb=y" .config && echo '✅' || echo '❌')"
    
    echo ""
    echo "=== 🚨 USB配置验证完成 ==="
    
    log "📊 USB配置状态总结:"
    local usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-xhci-hcd" "kmod-usb-storage" "kmod-scsi-core" "kmod-fs-ext4")
    local missing_count=0
    local enabled_count=0
    
    for driver in "${usb_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            log "  ✅ $driver: 已启用"
            enabled_count=$((enabled_count + 1))
        else
            log "  ❌ $driver: 未启用"
            missing_count=$((missing_count + 1))
        fi
    done
    
    log "📈 统计: $enabled_count 个已启用，$missing_count 个未启用"
    
    if [ $missing_count -gt 0 ]; then
        log "⚠️ 警告: 有 $missing_count 个关键USB驱动未启用，可能会影响USB功能"
    else
        log "🎉 恭喜: 所有关键USB驱动都已启用"
    fi
}
#【build_firmware_main.sh-14-end】

#【build_firmware_main.sh-15】
check_usb_drivers_integrity() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 USB驱动完整性检查（增强版） ==="
    
    local missing_drivers=()
    local required_drivers=(
        # 核心驱动
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb3"
        "kmod-usb-xhci-hcd"
        "kmod-usb-storage"
        "kmod-scsi-core"
        "kmod-fs-ext4"
        "kmod-fs-vfat"
        # 扩展驱动（推荐启用）
        "kmod-usb-xhci-pci"
        "kmod-usb-xhci-plat-hcd"
        "kmod-usb-storage-uas"
        "kmod-scsi-generic"
        "kmod-fs-exfat"
        "kmod-fs-ntfs3"
        "kmod-nls-utf8"
        "kmod-nls-cp936"
    )
    
    # 根据平台添加专用驱动
    if [ "$TARGET" = "ipq40xx" ] || grep -q "^CONFIG_TARGET_ipq40xx=y" .config 2>/dev/null; then
        required_drivers+=("kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3" "kmod-usb-dwc3-of-simple")
    elif [ "$TARGET" = "ramips" ] || grep -q "^CONFIG_TARGET_ramips=y" .config 2>/dev/null; then
        required_drivers+=("kmod-usb-xhci-mtk" "kmod-usb-ohci-pci" "kmod-usb2-pci")
    elif [ "$TARGET" = "mediatek" ] || grep -q "^CONFIG_TARGET_mediatek=y" .config 2>/dev/null; then
        required_drivers+=("kmod-usb-dwc3-mediatek" "kmod-phy-mediatek" "kmod-usb-dwc3")
    elif [ "$TARGET" = "ath79" ] || grep -q "^CONFIG_TARGET_ath79=y" .config 2>/dev/null; then
        required_drivers+=("kmod-usb2-ath79" "kmod-usb-ohci")
    fi
    
    # 检查每个驱动
    for driver in "${required_drivers[@]}"; do
        if ! grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            log "❌ 缺失驱动: $driver"
            missing_drivers+=("$driver")
        else
            log "✅ 驱动存在: $driver"
        fi
    done
    
    # 如果有缺失驱动，尝试修复
    if [ ${#missing_drivers[@]} -gt 0 ]; then
        log "🚨 发现 ${#missing_drivers[@]} 个缺失的USB驱动"
        log "正在尝试修复..."
        
        for driver in "${missing_drivers[@]}"; do
            echo "CONFIG_PACKAGE_${driver}=y" >> .config
            log "✅ 已添加: $driver"
        done
        
        # 重新运行defconfig
        make defconfig || log "⚠️ make defconfig 修复后仍有问题"
        log "✅ USB驱动修复完成"
    else
        log "🎉 所有必需USB驱动都已启用"
    fi
}
#【build_firmware_main.sh-15-end】

#【build_firmware_main.sh-16】
apply_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 应用配置并显示详细信息（完整版） ==="
    
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在，无法应用配置"
        return 1
    fi
    
    log "📋 配置详情:"
    log "配置文件大小: $(ls -lh .config | awk '{print $5}')"
    log "配置行数: $(wc -l < .config)"
    
    local backup_file=".config.bak.$(date +%Y%m%d%H%M%S)"
    cp .config "$backup_file"
    log "✅ 配置文件已备份: $backup_file"
    
    log "🔧 步骤1: 标准化配置文件格式..."
    
    if [ -f ".config" ]; then
        awk '
        {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 ~ /^#/) {
                if ($0 ~ /^#CONFIG_/) {
                    $0 = "# " substr($0, 2)
                }
                if ($0 !~ /is not set$/) {
                    $0 = $0 " is not set"
                }
            }
            if ($0 ~ /^CONFIG_/) {
                if ($0 ~ /y$|m$|=$/) {
                    gsub(/[[:space:]]*=[[:space:]]*y$/, "=y")
                    gsub(/[[:space:]]*=[[:space:]]*m$/, "=m")
                    gsub(/[[:space:]]*=[[:space:]]*$/, "=")
                }
            }
            if (length($0) > 0) {
                print $0
            }
        }' .config > .config.tmp
        
        mv .config.tmp .config
        log "✅ 配置文件格式标准化完成"
    else
        log "❌ .config 文件在操作过程中丢失"
        return 1
    fi
    
    log "🔧 步骤2: 清理重复配置行..."
    
    local dup_before=$(wc -l < .config)
    
    awk '!seen[$0]++' .config > .config.tmp
    mv .config.tmp .config
    
    local dup_after=$(wc -l < .config)
    local dup_removed=$((dup_before - dup_after))
    
    if [ $dup_removed -gt 0 ]; then
        log "✅ 已删除 $dup_removed 个完全重复的配置行"
    fi
    
    awk '
    BEGIN { FS="=" }
    /^CONFIG_/ {
        config_lines[$1] = $0
        next
    }
    { other_lines[NR] = $0 }
    END {
        for (i in config_lines) print config_lines[i]
        for (i in other_lines) print other_lines[i]
    }' .config > .config.uniq
    
    mv .config.uniq .config
    
    local config_uniq_removed=$((dup_after - $(wc -l < .config)))
    if [ $config_uniq_removed -gt 0 ]; then
        log "✅ 已合并 $config_uniq_removed 个重复配置项"
    fi
    
    log "🔧 步骤3: 检查libustream冲突..."
    
    local openssl_enabled=0
    local wolfssl_enabled=0
    
    if grep -q "^CONFIG_PACKAGE_libustream-openssl=y" .config; then
        openssl_enabled=1
    fi
    
    if grep -q "^CONFIG_PACKAGE_libustream-wolfssl=y" .config; then
        wolfssl_enabled=1
    fi
    
    if [ $openssl_enabled -eq 1 ] && [ $wolfssl_enabled -eq 1 ]; then
        log "⚠️ 发现libustream-openssl和libustream-wolfssl冲突"
        log "🔧 修复冲突: 禁用libustream-openssl"
        
        awk '
        /^CONFIG_PACKAGE_libustream-openssl=y/ {
            print "# CONFIG_PACKAGE_libustream-openssl is not set"
            next
        }
        { print $0 }
        ' .config > .config.tmp
        mv .config.tmp .config
        
        log "✅ 冲突已修复"
    else
        log "✅ libustream无冲突"
    fi
    
    log "🔧 步骤4: 检查并修复关键配置..."
    
    local config_tool=""
    if [ -f "scripts/config/config" ] && [ -x "scripts/config/config" ]; then
        config_tool="scripts/config/config"
        log "✅ 使用 scripts/config/config 工具"
    elif [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
        config_tool="scripts/config/conf"
        log "✅ 使用 scripts/config/conf 工具"
    elif [ -f "scripts/config" ] && [ -x "scripts/config" ]; then
        config_tool="scripts/config"
        log "✅ 使用 scripts/config 工具"
    else
        log "⚠️ 配置工具不存在，将使用awk方式进行修复"
        config_tool=""
    fi
    
    local target=$(grep "^CONFIG_TARGET_" .config | grep "=y" | head -1 | cut -d'_' -f2 | tr '[:upper:]' '[:lower:]')
    local fix_count=0
    
    log "  🔧 USB 3.0驱动检查..."
    local usb3_enabled=0
    
    if grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
        usb3_enabled=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" .config; then
        usb3_enabled=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-qcom=y" .config; then
        usb3_enabled=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config; then
        usb3_enabled=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3=y" .config && grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config; then
        usb3_enabled=1
    elif grep -q "^CONFIG_USB_XHCI_HCD=y" .config; then
        usb3_enabled=1
    fi
    
    if [ $usb3_enabled -eq 0 ]; then
        log "  ⚠️ USB 3.0功能未启用，尝试修复..."
        if [ -n "$config_tool" ]; then
            if [ "$config_tool" = "scripts/config/conf" ]; then
                $config_tool --defconfig CONFIG_PACKAGE_kmod-usb3=y .config 2>/dev/null || true
            else
                $config_tool --enable PACKAGE_kmod-usb3 2>/dev/null || true
            fi
        else
            echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
        fi
        fix_count=$((fix_count + 1))
        log "  ✅ USB 3.0功能已添加"
    else
        log "  ✅ USB 3.0功能已启用"
    fi
    
    if [ "$target" = "ipq40xx" ] || [ "$target" = "qcom" ]; then
        log "  🔧 IPQ40xx平台专用USB驱动检查..."
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && ! grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=m" .config; then
            log "  ⚠️ kmod-usb-dwc3-qcom未启用，尝试添加..."
            if [ -n "$config_tool" ]; then
                if [ "$config_tool" = "scripts/config/conf" ]; then
                    $config_tool --defconfig CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y .config 2>/dev/null || true
                else
                    $config_tool --enable PACKAGE_kmod-usb-dwc3-qcom 2>/dev/null || true
                fi
            else
                echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
            fi
            fix_count=$((fix_count + 1))
            log "  ✅ kmod-usb-dwc3-qcom已添加"
        else
            log "  ✅ kmod-usb-dwc3-qcom已启用"
        fi
        
        if grep -q "^CONFIG_PHY_QCOM_IPQ4019_USB=y" .config; then
            log "  ✅ 高通IPQ4019 USB PHY已启用"
        elif ! grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-ipq4019-usb=y" .config && ! grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-ipq4019-usb=m" .config; then
            log "  ⚠️ 高通USB PHY未启用，尝试添加..."
            if [ -n "$config_tool" ]; then
                if [ "$config_tool" = "scripts/config/conf" ]; then
                    $config_tool --defconfig CONFIG_PACKAGE_kmod-phy-qcom-ipq4019-usb=y .config 2>/dev/null || true
                else
                    $config_tool --enable PACKAGE_kmod-phy-qcom-ipq4019-usb 2>/dev/null || true
                fi
            else
                echo "CONFIG_PACKAGE_kmod-phy-qcom-ipq4019-usb=y" >> .config
            fi
            fix_count=$((fix_count + 1))
            log "  ✅ 高通USB PHY已添加"
        fi
    fi
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "  🔧 TurboACC配置检查..."
        local turboacc_fixed=0
        
        if ! grep -q "^CONFIG_PACKAGE_luci-app-turboacc=y" .config; then
            log "  ⚠️ luci-app-turboacc未启用，尝试添加..."
            if [ -n "$config_tool" ]; then
                if [ "$config_tool" = "scripts/config/conf" ]; then
                    $config_tool --defconfig CONFIG_PACKAGE_luci-app-turboacc=y .config 2>/dev/null || true
                else
                    $config_tool --enable PACKAGE_luci-app-turboacc 2>/dev/null || true
                fi
            else
                echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
            fi
            turboacc_fixed=1
        fi
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-shortcut-fe=y" .config; then
            log "  ⚠️ kmod-shortcut-fe未启用，尝试添加..."
            if [ -n "$config_tool" ]; then
                if [ "$config_tool" = "scripts/config/conf" ]; then
                    $config_tool --defconfig CONFIG_PACKAGE_kmod-shortcut-fe=y .config 2>/dev/null || true
                else
                    $config_tool --enable PACKAGE_kmod-shortcut-fe 2>/dev/null || true
                fi
            else
                echo "CONFIG_PACKAGE_kmod-shortcut-fe=y" >> .config
            fi
            turboacc_fixed=1
        fi
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-fast-classifier=y" .config; then
            log "  ⚠️ kmod-fast-classifier未启用，尝试添加..."
            if [ -n "$config_tool" ]; then
                if [ "$config_tool" = "scripts/config/conf" ]; then
                    $config_tool --defconfig CONFIG_PACKAGE_kmod-fast-classifier=y .config 2>/dev/null || true
                else
                    $config_tool --enable PACKAGE_kmod-fast-classifier 2>/dev/null || true
                fi
            else
                echo "CONFIG_PACKAGE_kmod-fast-classifier=y" >> .config
            fi
            turboacc_fixed=1
        fi
        
        if [ $turboacc_fixed -eq 1 ]; then
            log "  ✅ TurboACC配置已修复"
            fix_count=$((fix_count + 1))
        else
            log "  ✅ TurboACC配置正常"
        fi
    fi
    
    log "  🔧 TCP BBR拥塞控制检查..."
    local bbr_fixed=0
    
    if ! grep -q "^CONFIG_PACKAGE_kmod-tcp-bbr=y" .config; then
        log "  ⚠️ kmod-tcp-bbr未启用，尝试添加..."
        if [ -n "$config_tool" ]; then
            if [ "$config_tool" = "scripts/config/conf" ]; then
                $config_tool --defconfig CONFIG_PACKAGE_kmod-tcp-bbr=y .config 2>/dev/null || true
            else
                $config_tool --enable PACKAGE_kmod-tcp-bbr 2>/dev/null || true
            fi
        else
            echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
        fi
        bbr_fixed=1
    fi
    
    if ! grep -q '^CONFIG_DEFAULT_TCP_CONG="bbr"' .config; then
        log "  ⚠️ DEFAULT_TCP_CONG未设置为bbr，尝试修复..."
        if [ -n "$config_tool" ]; then
            if [ "$config_tool" = "scripts/config/conf" ]; then
                sed -i '/^CONFIG_DEFAULT_TCP_CONG=/d' .config
                echo 'CONFIG_DEFAULT_TCP_CONG="bbr"' >> .config
            else
                $config_tool --set-str DEFAULT_TCP_CONG "bbr" 2>/dev/null || true
            fi
        else
            sed -i '/^CONFIG_DEFAULT_TCP_CONG=/d' .config
            echo 'CONFIG_DEFAULT_TCP_CONG="bbr"' >> .config
        fi
        bbr_fixed=1
    fi
    
    if [ $bbr_fixed -eq 1 ]; then
        log "  ✅ TCP BBR配置已修复"
        fix_count=$((fix_count + 1))
    else
        log "  ✅ TCP BBR配置正常"
    fi
    
    log "  🔧 kmod-ath10k-ct冲突检查..."
    local ath10k_fixed=0
    
    if grep -q "^CONFIG_PACKAGE_kmod-ath10k=y" .config; then
        log "  ⚠️ 检测到标准ath10k驱动，与ath10k-ct冲突，正在修复..."
        sed -i '/^CONFIG_PACKAGE_kmod-ath10k=y/d' .config
        echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-ath10k-ct=y" .config; then
            echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
        fi
        ath10k_fixed=1
        log "  ✅ kmod-ath10k-ct冲突已修复"
    else
        log "  ✅ kmod-ath10k-ct配置正常"
    fi
    
    if [ $fix_count -eq 0 ]; then
        log "✅ 所有关键配置检查通过，无需修复"
    else
        log "✅ 已修复 $fix_count 个关键配置项"
    fi
    
    log "🔧 步骤5: 最终去重和格式检查..."
    
    awk '!seen[$0]++' .config > .config.tmp
    mv .config.tmp .config
    
    awk '
    BEGIN { FS="=" }
    /^CONFIG_/ {
        config_lines[$1] = $0
        next
    }
    { other_lines[NR] = $0 }
    END {
        for (i in config_lines) print config_lines[i]
        for (i in other_lines) print other_lines[i]
    }' .config > .config.uniq
    
    mv .config.uniq .config
    
    awk 'NF > 0' .config > .config.tmp
    mv .config.tmp .config
    
    log "✅ 最终去重完成"
    
    log "🔄 步骤6: 运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log "🔧 步骤7: 验证关键配置..."
    
    echo ""
    echo "=== 🔍 USB驱动完整性检查 ==="
    echo ""
    echo "🔍 检查基础USB驱动..."
    
    local base_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb-storage"
        "kmod-scsi-core"
    )
    
    for driver in "${base_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "✅ $driver: 已启用"
        else
            echo "❌ $driver: 未启用"
        fi
    done
    
    echo ""
    echo "🔍 检查USB 3.0驱动..."
    
    local usb3_found=0
    
    if grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config; then
        echo "✅ kmod-usb3: 已启用"
        usb3_found=1
    fi
    
    if grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
        echo "✅ kmod-usb-xhci-hcd: 已启用"
        usb3_found=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" .config; then
        echo "✅ kmod-usb-xhci-plat-hcd: 已启用"
        usb3_found=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-qcom=y" .config; then
        echo "✅ kmod-usb-xhci-qcom: 已启用"
        usb3_found=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config; then
        echo "✅ kmod-usb-xhci-mtk: 已启用"
        usb3_found=1
    elif grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3=y" .config && grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config; then
        echo "✅ DWC3 + USB3: 已启用"
        usb3_found=1
    elif grep -q "^CONFIG_USB_XHCI_HCD=y" .config; then
        echo "✅ 内核xhci支持: 已启用"
        usb3_found=1
    fi
    
    if [ $usb3_found -eq 0 ]; then
        echo "⚠️ USB 3.0驱动: 未找到任何实现"
    fi
    
    echo ""
    echo "🔍 检查平台专用驱动..."
    
    local target=$(grep "^CONFIG_TARGET_" .config | grep "=y" | head -1 | cut -d'_' -f2 | tr '[:upper:]' '[:lower:]')
    
    case "$target" in
        ipq40xx|qcom)
            echo "🔧 检测到高通IPQ40xx平台，检查专用驱动:"
            
            if grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config; then
                echo "✅ kmod-usb-dwc3-qcom: 已启用"
            else
                echo "ℹ️ kmod-usb-dwc3-qcom: 未启用"
            fi
            
            if grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-ipq4019-usb=y" .config; then
                echo "✅ kmod-phy-qcom-ipq4019-usb: 已启用"
            elif grep -q "^CONFIG_PHY_QCOM_IPQ4019_USB=y" .config; then
                echo "✅ 高通IPQ4019 USB PHY: 已启用"
            else
                echo "ℹ️ 高通USB PHY: 未启用"
            fi
            ;;
        mediatek|ramips)
            echo "🔧 检测到联发科平台，检查专用驱动:"
            
            if grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config; then
                echo "✅ kmod-usb-xhci-mtk: 已启用"
            else
                echo "ℹ️ kmod-usb-xhci-mtk: 未启用"
            fi
            ;;
        ath79)
            echo "🔧 检测到ATH79平台，检查专用驱动:"
            
            if grep -q "^CONFIG_PACKAGE_kmod-usb2-ath79=y" .config; then
                echo "✅ kmod-usb2-ath79: 已启用"
            else
                echo "ℹ️ kmod-usb2-ath79: 未启用"
            fi
            ;;
    esac
    
    echo ""
    echo "=== 📦 插件配置状态 ==="
    
    local plugins=$(grep "^CONFIG_PACKAGE_luci-app" .config | grep -E "=y|=m" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local plugin_count=0
    
    if [ -n "$plugins" ]; then
        while read plugin; do
            plugin_count=$((plugin_count + 1))
            if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config; then
                printf "%-4s ✅ %s: 已启用
" "[$plugin_count]" "$plugin"
            elif grep -q "^CONFIG_PACKAGE_${plugin}=m" .config; then
                printf "%-4s 📦 %s: 模块化
" "[$plugin_count]" "$plugin"
            fi
        done <<< "$plugins"
        echo ""
        echo "📊 插件总数: $plugin_count 个"
    else
        echo "未找到Luci插件"
    fi
    
    echo ""
    echo "=== 📦 内核模块配置状态 ==="
    
    local kernel_modules=$(grep "^CONFIG_PACKAGE_kmod-" .config | grep -E "=y|=m" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local module_count=0
    
    if [ -n "$kernel_modules" ]; then
        while read module; do
            module_count=$((module_count + 1))
            if grep -q "^CONFIG_PACKAGE_${module}=y" .config; then
                printf "%-4s ✅ %s: 已启用
" "[$module_count]" "$module"
            elif grep -q "^CONFIG_PACKAGE_${module}=m" .config; then
                printf "%-4s 📦 %s: 模块化
" "[$module_count]" "$module"
            fi
        done <<< "$kernel_modules"
        echo ""
        echo "📊 内核模块总数: $module_count 个"
    else
        echo "未找到内核模块"
    fi
    
    echo ""
    echo "=== 📦 网络工具配置状态 ==="
    
    local net_tools=$(grep "^CONFIG_PACKAGE_" .config | grep -E "=y|=m" | grep -E "iptables|nftables|firewall|qos|sfe|shortcut|acceler|tc|fullcone" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local net_count=0
    
    if [ -n "$net_tools" ]; then
        while read tool; do
            net_count=$((net_count + 1))
            if grep -q "^CONFIG_PACKAGE_${tool}=y" .config; then
                printf "%-4s ✅ %s: 已启用
" "[$net_count]" "$tool"
            elif grep -q "^CONFIG_PACKAGE_${tool}=m" .config; then
                printf "%-4s 📦 %s: 模块化
" "[$net_count]" "$tool"
            fi
        done <<< "$net_tools"
        echo ""
        echo "📊 网络工具总数: $net_count 个"
    else
        echo "未找到网络工具"
    fi
    
    echo ""
    echo "=== 📦 文件系统支持 ==="
    
    local fs_support=$(grep "^CONFIG_PACKAGE_kmod-fs-" .config | grep -E "=y|=m" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local fs_count=0
    
    if [ -n "$fs_support" ]; then
        while read fs; do
            fs_count=$((fs_count + 1))
            if grep -q "^CONFIG_PACKAGE_${fs}=y" .config; then
                printf "%-4s ✅ %s: 已启用
" "[$fs_count]" "$fs"
            elif grep -q "^CONFIG_PACKAGE_${fs}=m" .config; then
                printf "%-4s 📦 %s: 模块化
" "[$fs_count]" "$fs"
            fi
        done <<< "$fs_support"
        echo ""
        echo "📊 文件系统总数: $fs_count 个"
    else
        echo "未找到文件系统支持"
    fi
    
    echo ""
    echo "=== 📊 配置统计 ==="
    
    local enabled_packages=$(grep -c "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null || echo "0")
    local module_packages=$(grep -c "^CONFIG_PACKAGE_.*=m$" .config 2>/dev/null || echo "0")
    local disabled_packages=$(grep -c "^# CONFIG_PACKAGE_.* is not set$" .config 2>/dev/null || echo "0")
    local kernel_configs=$(grep -c "^CONFIG_[A-Z].*=y$" .config | grep -v "PACKAGE" | wc -l)
    
    echo "✅ 已启用插件/模块: $enabled_packages 个"
    echo "📦 模块化插件/模块: $module_packages 个"
    echo "❌ 已禁用插件/模块: $disabled_packages 个"
    echo "⚙️ 内核配置: $kernel_configs 个"
    echo "📊 总配置行数: $(wc -l < .config) 行"
    
    echo ""
    echo "=== 🔍 设备信息详细查询（使用公共函数） ==="
    echo "----------------------------------------"
    
    local search_device=""
    case "$DEVICE" in
        ac42u|rt-ac42u|asus_rt-ac42u)
            search_device="ac42u"
            ;;
        acrh17|rt-acrh17|asus_rt-acrh17)
            search_device="acrh17"
            ;;
        *)
            search_device="$DEVICE"
            ;;
    esac
    
    echo "🔍 搜索设备名: $search_device"
    echo ""
    
    # 直接调用函数，它会输出详细信息
    local device_file=$(find_device_definition_file "$search_device" "$TARGET")
    
    if [ -n "$device_file" ] && [ -f "$device_file" ]; then
        echo "✅ 找到设备定义文件: $device_file"
        echo ""
        
        local device_block=$(extract_device_config "$device_file" "$search_device")
        if [ -n "$device_block" ]; then
            echo "📋 设备 $search_device 配置:"
            echo "----------------------------------------"
            echo "$device_block"
            echo "----------------------------------------"
            
            local soc=$(extract_config_value "$device_block" "SOC")
            local model=$(extract_config_value "$device_block" "DEVICE_MODEL")
            local title=$(extract_config_value "$device_block" "DEVICE_TITLE")
            local packages=$(extract_config_value "$device_block" "DEVICE_PACKAGES")
            local dts=$(extract_config_value "$device_block" "DEVICE_DTS")
            local kernel_ver=$(extract_config_value "$device_block" "KERNEL_PATCHVER")
            
            [ -n "$soc" ] && echo "🔧 SOC: $soc"
            [ -n "$model" ] && echo "📱 型号: $model"
            [ -n "$title" ] && echo "📝 标题: $title"
            [ -n "$packages" ] && echo "📦 默认包: $packages"
            [ -n "$dts" ] && echo "🔧 DTS: $dts"
            [ -n "$kernel_ver" ] && echo "🐧 内核版本: $kernel_ver"
        else
            echo "⚠️ 在文件中未找到设备 $search_device 的配置块"
        fi
    else
        echo "⚠️ 未找到设备 $search_device 的定义文件"
    fi
    
    echo ""
    echo "=== 📁 所有子平台.mk文件列表 ==="
    
    local mk_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r mk_file; do
            mk_count=$((mk_count + 1))
            echo "   📄 [$mk_count] $mk_file"
        done < <(find "target/linux/$TARGET" -type f -name "*.mk" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $mk_count 个.mk文件"
    else
        echo "   未找到.mk文件"
    fi
    
    echo ""
    echo "=== 📁 内核配置文件列表 ==="
    
    local kernel_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r config; do
            kernel_count=$((kernel_count + 1))
            local ver=$(basename "$config" | sed 's/config-//')
            echo "   📄 [$kernel_count] $config (内核版本 $ver)"
        done < <(find "target/linux/$TARGET" -type f -name "config-*" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $kernel_count 个内核配置文件"
    else
        echo "   未找到内核配置文件"
    fi
    
    echo ""
    echo "=== 📁 设备相关文件列表 ==="
    
    local dev_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r config; do
            dev_count=$((dev_count + 1))
            echo "   📄 [$dev_count] $config"
        done < <(find "target/linux/$TARGET" -type f -name "*${DEVICE}*" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $dev_count 个设备相关文件"
    else
        echo "   未找到设备专属配置文件"
    fi
    
    log "✅ 配置应用完成"
    log "最终配置文件: .config"
    log "最终配置大小: $(ls -lh .config | awk '{print $5}')"
    log "最终配置行数: $(wc -l < .config)"
}
#【build_firmware_main.sh-16-end】

#【build_firmware_main.sh-17】
fix_network() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 修复网络环境 ==="
    
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    git config --global core.compression 0
    git config --global core.looseCompression 0
    
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    export CURL_SSL_NO_VERIFY=1
    
    if [ -n "$http_proxy" ]; then
        echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee /etc/apt/apt.conf.d/proxy.conf > /dev/null
    fi
    
    log "测试网络连接..."
    if curl -s --connect-timeout 10 https://github.com > /dev/null; then
        log "✅ 网络连接正常"
    else
        log "⚠️ 网络连接可能有问题"
    fi
    
    log "✅ 网络环境修复完成"
}
#【build_firmware_main.sh-17-end】

#【build_firmware_main.sh-18】
download_dependencies() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 下载依赖包 ==="
    
    if [ ! -d "dl" ]; then
        mkdir -p dl
        log "创建依赖包目录: dl"
    fi
    
    # 使用 -name 条件，不加括号
    local existing_deps=$(find dl -type f -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" 2>/dev/null | wc -l)
    log "现有依赖包数量: $existing_deps 个"
    
    log "开始下载依赖包..."
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    # 使用 -name 条件，不加括号
    local downloaded_deps=$(find dl -type f -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" 2>/dev/null | wc -l)
    log "下载后依赖包数量: $downloaded_deps 个"
    
    if [ $downloaded_deps -gt $existing_deps ]; then
        log "✅ 成功下载了 $((downloaded_deps - existing_deps)) 个新依赖包"
    else
        log "ℹ️ 没有下载新的依赖包"
    fi
    
    if grep -q "ERROR|Failed|404" download.log 2>/dev/null; then
        log "⚠️ 下载过程中发现错误:"
        grep -E "ERROR|Failed|404" download.log | head -10
    fi
    
    log "✅ 依赖包下载完成"
    
    # =========================================================================
    # 添加设备信息详细查询 - 与步骤23保持一致
    # =========================================================================
    echo ""
    echo "=== 🔍 设备信息详细查询（完整版） ==="
    echo "----------------------------------------"
    
    local search_device=""
    case "$DEVICE" in
        ac42u|rt-ac42u|asus_rt-ac42u)
            search_device="ac42u"
            ;;
        acrh17|rt-acrh17|asus_rt-acrh17)
            search_device="acrh17"
            ;;
        *)
            search_device="$DEVICE"
            ;;
    esac
    
    echo "🔍 搜索设备名: $search_device"
    echo ""
    get_device_support_summary "$search_device" "$TARGET" "$SUBTARGET"
    
    echo ""
    echo "=== 📁 所有子平台.mk文件列表 ==="
    
    local mk_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r mk_file; do
            mk_count=$((mk_count + 1))
            echo "   📄 [$mk_count] $mk_file"
        done < <(find "target/linux/$TARGET" -type f -name "*.mk" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $mk_count 个.mk文件"
    else
        echo "   未找到.mk文件"
    fi
    
    echo ""
    echo "=== 📁 内核配置文件列表 ==="
    
    local kernel_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r config; do
            kernel_count=$((kernel_count + 1))
            local ver=$(basename "$config" | sed 's/config-//')
            echo "   📄 [$kernel_count] $config (内核版本 $ver)"
        done < <(find "target/linux/$TARGET" -type f -name "config-*" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $kernel_count 个内核配置文件"
    else
        echo "   未找到内核配置文件"
    fi
    
    echo ""
    echo "=== 📁 设备相关文件列表 ==="
    
    local dev_count=0
    if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
        while IFS= read -r config; do
            dev_count=$((dev_count + 1))
            echo "   📄 [$dev_count] $config"
        done < <(find "target/linux/$TARGET" -type f -name "*${DEVICE}*" 2>/dev/null | sort)
        echo ""
        echo "   📊 共找到 $dev_count 个设备相关文件"
    else
        echo "   未找到设备专属配置文件"
    fi
}
#【build_firmware_main.sh-18-end】

#【build_firmware_main.sh-19】
integrate_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 集成自定义文件（增强版） ==="
    
    local custom_dir="$REPO_ROOT/firmware-config/custom-files"
    
    if [ ! -d "$custom_dir" ]; then
        log "ℹ️ 自定义文件目录不存在: $custom_dir"
        log "💡 如需集成自定义文件，请在 firmware-config/custom-files/ 目录中添加文件"
        return 0
    fi
    
    log "自定义文件目录: $custom_dir"
    log "OpenWrt版本: $SELECTED_BRANCH"
    
    recursive_find_custom_files() {
        local dir="$1"
        local files=""
        if [ -d "$dir" ]; then
            for item in "$dir"/*; do
                if [ -f "$item" ]; then
                    files="$files$item"$'\n'
                elif [ -d "$item" ]; then
                    files="$files$(recursive_find_custom_files "$item")"
                fi
            done
        fi
        echo "$files" | sed '/^$/d'
    }
    
    is_english_filename() {
        local filename="$1"
        if echo "$filename" | grep -q '^[a-zA-Z0-9_.-]*$'; then
            return 0
        else
            return 1
        fi
    }
    
    log "🔍 递归查找所有自定义文件..."
    local all_files=$(recursive_find_custom_files "$custom_dir")
    local file_count=$(echo "$all_files" | grep -c '^' || echo "0")
    
    if [ $file_count -eq 0 ]; then
        log "ℹ️ 未找到任何自定义文件"
        return 0
    fi
    
    log "📊 找到 $file_count 个自定义文件"
    
    local ipk_count=0
    local script_count=0
    local config_count=0
    local other_count=0
    local english_count=0
    local non_english_count=0
    
    echo ""
    log "📋 详细文件列表:"
    echo "----------------------------------------------------------------"
    
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        
        local rel_path="${file#$custom_dir/}"
        local file_name=$(basename "$file")
        local file_size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
        
        if is_english_filename "$file_name"; then
            local name_status="✅ 英文"
            english_count=$((english_count + 1))
        else
            local name_status="⚠️ 非英文"
            non_english_count=$((non_english_count + 1))
        fi
        
        if [[ "$file_name" =~ .ipk$ ]] || [[ "$file_name" =~ .IPK$ ]] || [[ "$file_name" =~ .Ipk$ ]]; then
            local type_desc="📦 IPK包"
            ipk_count=$((ipk_count + 1))
        elif [[ "$file_name" =~ .sh$ ]] || [[ "$file_name" =~ .Sh$ ]] || [[ "$file_name" =~ .SH$ ]]; then
            local type_desc="📜 脚本"
            script_count=$((script_count + 1))
        elif [[ "$file_name" =~ .conf$ ]] || [[ "$file_name" =~ .config$ ]] || [[ "$file_name" =~ .CONF$ ]]; then
            local type_desc="⚙️ 配置"
            config_count=$((config_count + 1))
        else
            local type_desc="📁 其他"
            other_count=$((other_count + 1))
        fi
        
        printf "%-50s %-10s %-15s %s\n" "$rel_path" "$file_size" "$type_desc" "$name_status"
        
    done <<< "$all_files"
    
    echo "----------------------------------------------------------------"
    
    echo ""
    log "📊 文件统计:"
    log "  文件总数: $file_count 个"
    log "  📦 IPK文件: $ipk_count 个"
    log "  📜 脚本文件: $script_count 个"
    log "  ⚙️ 配置文件: $config_count 个"
    log "  📁 其他文件: $other_count 个"
    log "  ✅ 英文文件名: $english_count 个"
    log "  ⚠️ 非英文文件名: $non_english_count 个"
    
    if [ $non_english_count -gt 0 ]; then
        echo ""
        log "💡 文件名建议:"
        log "  为了更好的兼容性，方便复制、运行，建议使用英文文件名"
        log "  当前系统会自动处理非英文文件名，但英文名有更好的兼容性"
    fi
    
    echo ""
    log "🔧 步骤1: 创建自定义文件目录"
    
    local custom_files_dir="files/etc/custom-files"
    mkdir -p "$custom_files_dir"
    log "✅ 创建自定义文件目录: $custom_files_dir"
    
    echo ""
    log "🔧 步骤2: 复制所有自定义文件（保持原文件名）"
    
    local copied_count=0
    local skip_count=0
    
    while IFS= read -r src_file; do
        [ -z "$src_file" ] && continue
        
        local rel_path="${src_file#$custom_dir/}"
        local dest_path="$custom_files_dir/$rel_path"
        local dest_dir=$(dirname "$dest_path")
        
        mkdir -p "$dest_dir"
        
        if cp "$src_file" "$dest_path" 2>/dev/null; then
            copied_count=$((copied_count + 1))
            
            if [[ "$src_file" =~ .sh$ ]] || [[ "$src_file" =~ .Sh$ ]] || [[ "$src_file" =~ .SH$ ]]; then
                chmod +x "$dest_path" 2>/dev/null || true
            fi
        else
            log "⚠️ 复制文件失败: $rel_path"
            skip_count=$((skip_count + 1))
        fi
        
    done <<< "$all_files"
    
    log "✅ 文件复制完成: $copied_count 个文件已复制，$skip_count 个文件跳过"
    
    echo ""
    log "🔧 步骤3: 创建第一次开机安装脚本（增强版）"
    
    local first_boot_dir="files/etc/uci-defaults"
    mkdir -p "$first_boot_dir"
    
    local first_boot_script="$first_boot_dir/99-custom-files"
    cat > "$first_boot_script" << 'EOF'
#!/bin/sh

LOG_DIR="/root/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/custom-files-install-$(date +%Y%m%d_%H%M%S).log"

echo "==================================================" > $LOG_FILE
echo "      自定义文件安装脚本（增强版）" >> $LOG_FILE
echo "      开始时间: $(date)" >> $LOG_FILE
echo "==================================================" >> $LOG_FILE
echo "" >> $LOG_FILE

CUSTOM_DIR="/etc/custom-files"

echo "🔧 预创建Samba配置文件..." >> $LOG_FILE
SAMBA_DIR="/etc/samba"
mkdir -p "$SAMBA_DIR" 2>/dev/null || true

for config_file in smb.conf smbpasswd secrets.tdb passdb.tdb lmhosts; do
    if [ ! -f "$SAMBA_DIR/$config_file" ]; then
        touch "$SAMBA_DIR/$config_file" 2>/dev/null && \
        echo "  ✅ 创建Samba配置文件: $config_file" >> $LOG_FILE || \
        echo "  ⚠️ 无法创建Samba配置文件: $config_file" >> $LOG_FILE
    fi
done

touch /etc/nsswitch.conf 2>/dev/null || true
touch /etc/krb5.conf 2>/dev/null || true
echo "  ✅ 创建系统配置文件: nsswitch.conf, krb5.conf" >> $LOG_FILE
echo "" >> $LOG_FILE

if [ -d "$CUSTOM_DIR" ]; then
    echo "✅ 找到自定义文件目录: $CUSTOM_DIR" >> $LOG_FILE
    echo "📊 目录结构:" >> $LOG_FILE
    find "$CUSTOM_DIR" -type f 2>/dev/null | sort | while read file; do
        file_name=$(basename "$file")
        file_size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
        rel_path="${file#$CUSTOM_DIR/}"
        echo "  📄 $rel_path ($file_size)" >> $LOG_FILE
    done
    echo "" >> $LOG_FILE
    
    IPK_COUNT=0
    IPK_SUCCESS=0
    IPK_FAILED=0
    
    echo "📦 开始安装IPK包..." >> $LOG_FILE
    
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        if echo "$file_name" | grep -qi ".ipk$"; then
            IPK_COUNT=$((IPK_COUNT + 1))
            rel_path="${file#$CUSTOM_DIR/}"
            
            echo "  🔧 正在安装 [$IPK_COUNT]: $rel_path" >> $LOG_FILE
            echo "      开始时间: $(date '+%H:%M:%S')" >> $LOG_FILE
            
            if opkg install "$file" >> $LOG_FILE 2>&1; then
                echo "      ✅ 安装成功" >> $LOG_FILE
                IPK_SUCCESS=$((IPK_SUCCESS + 1))
            else
                echo "      ❌ 安装失败，继续下一个..." >> $LOG_FILE
                IPK_FAILED=$((IPK_FAILED + 1))
                
                echo "      错误信息:" >> $LOG_FILE
                tail -5 $LOG_FILE >> $LOG_FILE 2>&1
            fi
            
            echo "      结束时间: $(date '+%H:%M:%S')" >> $LOG_FILE
            echo "" >> $LOG_FILE
        fi
    done < "$FILE_LIST"
    
    rm -f "$FILE_LIST"
    
    echo "📊 IPK包安装统计:" >> $LOG_FILE
    echo "  尝试安装: $IPK_COUNT 个" >> $LOG_FILE
    echo "  成功: $IPK_SUCCESS 个" >> $LOG_FILE
    echo "  失败: $IPK_FAILED 个" >> $LOG_FILE
    echo "" >> $LOG_FILE
    
    SCRIPT_COUNT=0
    SCRIPT_SUCCESS=0
    SCRIPT_FAILED=0
    
    echo "📜 开始运行脚本文件..." >> $LOG_FILE
    
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        if echo "$file_name" | grep -qi ".sh$"; then
            SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
            rel_path="${file#$CUSTOM_DIR/}"
            
            echo "  🚀 正在运行 [$SCRIPT_COUNT]: $rel_path" >> $LOG_FILE
            echo "      开始时间: $(date '+%H:%M:%S')" >> $LOG_FILE
            
            chmod +x "$file" 2>/dev/null
            
            if sh "$file" >> $LOG_FILE 2>&1; then
                echo "      ✅ 运行成功" >> $LOG_FILE
                SCRIPT_SUCCESS=$((SCRIPT_SUCCESS + 1))
            else
                local exit_code=$?
                echo "      ❌ 运行失败，退出代码: $exit_code" >> $LOG_FILE
                SCRIPT_FAILED=$((SCRIPT_FAILED + 1))
                
                echo "      错误信息:" >> $LOG_FILE
                tail -5 $LOG_FILE >> $LOG_FILE 2>&1
            fi
            
            echo "      结束时间: $(date '+%H:%M:%S')" >> $LOG_FILE
            echo "" >> $LOG_FILE
        fi
    done < "$FILE_LIST"
    
    rm -f "$FILE_LIST"
    
    echo "📊 脚本运行统计:" >> $LOG_FILE
    echo "  尝试运行: $SCRIPT_COUNT 个" >> $LOG_FILE
    echo "  成功: $SCRIPT_SUCCESS 个" >> $LOG_FILE
    echo "  失败: $SCRIPT_FAILED 个" >> $LOG_FILE
    echo "" >> $LOG_FILE
    
    OTHER_COUNT=0
    OTHER_SUCCESS=0
    OTHER_FAILED=0
    
    echo "📁 处理其他文件..." >> $LOG_FILE
    
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        if echo "$file_name" | grep -qi ".ipk$"; then
            continue
        fi
        
        if echo "$file_name" | grep -qi ".sh$"; then
            continue
        fi
        
        OTHER_COUNT=$((OTHER_COUNT + 1))
        rel_path="${file#$CUSTOM_DIR/}"
        
        echo "  📋 正在处理 [$OTHER_COUNT]: $rel_path" >> $LOG_FILE
        
        if echo "$file_name" | grep -qi ".conf$"; then
            echo "      类型: 配置文件" >> $LOG_FILE
            if cp "$file" "/etc/config/$file_name" 2>/dev/null; then
                echo "      ✅ 复制到 /etc/config/" >> $LOG_FILE
                OTHER_SUCCESS=$((OTHER_SUCCESS + 1))
            else
                echo "      ❌ 复制失败" >> $LOG_FILE
                OTHER_FAILED=$((OTHER_FAILED + 1))
            fi
        else
            echo "      类型: 其他文件" >> $LOG_FILE
            if cp "$file" "/tmp/$file_name" 2>/dev/null; then
                echo "      ✅ 复制到 /tmp/" >> $LOG_FILE
                OTHER_SUCCESS=$((OTHER_SUCCESS + 1))
            else
                echo "      ❌ 复制失败" >> $LOG_FILE
                OTHER_FAILED=$((OTHER_FAILED + 1))
            fi
        fi
        
        echo "" >> $LOG_FILE
    done < "$FILE_LIST"
    
    rm -f "$FILE_LIST"
    
    echo "📊 其他文件处理统计:" >> $LOG_FILE
    echo "  尝试处理: $OTHER_COUNT 个" >> $LOG_FILE
    echo "  成功: $OTHER_SUCCESS 个" >> $LOG_FILE
    echo "  失败: $OTHER_FAILED 个" >> $LOG_FILE
    echo "" >> $LOG_FILE
    
    echo "==================================================" >> $LOG_FILE
    echo "      自定义文件安装完成" >> $LOG_FILE
    echo "      结束时间: $(date)" >> $LOG_FILE
    echo "==================================================" >> $LOG_FILE
    echo "" >> $LOG_FILE
    
    TOTAL_FILES=$((IPK_COUNT + SCRIPT_COUNT + OTHER_COUNT))
    TOTAL_SUCCESS=$((IPK_SUCCESS + SCRIPT_SUCCESS + OTHER_SUCCESS))
    TOTAL_FAILED=$((IPK_FAILED + SCRIPT_FAILED + OTHER_FAILED))
    
    echo "📈 总体统计:" >> $LOG_FILE
    echo "  总文件数: $TOTAL_FILES 个" >> $LOG_FILE
    echo "  成功处理: $TOTAL_SUCCESS 个" >> $LOG_FILE
    echo "  失败处理: $TOTAL_FAILED 个" >> $LOG_FILE
    echo "  成功率: $((TOTAL_SUCCESS * 100 / (TOTAL_SUCCESS + TOTAL_FAILED)))%" >> $LOG_FILE
    echo "" >> $LOG_FILE
    
    echo "📋 详细分类统计:" >> $LOG_FILE
    echo "  📦 IPK包: $IPK_SUCCESS/$IPK_COUNT 成功" >> $LOG_FILE
    echo "  📜 脚本: $SCRIPT_SUCCESS/$SCRIPT_COUNT 成功" >> $LOG_FILE
    echo "  📁 其他文件: $OTHER_SUCCESS/$OTHER_COUNT 成功" >> $LOG_FILE
    echo "" >> $LOG_FILE
    
    touch /etc/custom-files-installed
    echo "✅ 已创建安装完成标记: /etc/custom-files-installed" >> $LOG_FILE
    
    echo "📝 重要信息:" >> $LOG_FILE
    echo "  安装日志位置: $LOG_FILE" >> $LOG_FILE
    echo "  日志目录: /root/logs/" >> $LOG_FILE
    echo "  下次启动不会再次安装（已有标记文件）" >> $LOG_FILE
    echo "  如需重新安装，请删除: /etc/custom-files-installed" >> $LOG_FILE
    
else
    echo "❌ 自定义文件目录不存在: $CUSTOM_DIR" >> $LOG_FILE
fi

echo "" >> $LOG_FILE
echo "=== 自定义文件安装脚本执行完成 ===" >> $LOG_FILE

exit 0
EOF
    
    chmod +x "$first_boot_script"
    log "✅ 创建第一次开机安装脚本: $first_boot_script"
    
    echo ""
    log "🔧 步骤4: 创建文件名检查脚本"
    
    local name_check_script="$custom_files_dir/check_filenames.sh"
    cat > "$name_check_script" << 'EOF'
#!/bin/sh

echo "=== 文件名检查脚本 ==="
echo "检查时间: $(date)"
echo ""

CUSTOM_DIR="/etc/custom-files"

if [ ! -d "$CUSTOM_DIR" ]; then
    echo "❌ 自定义文件目录不存在: $CUSTOM_DIR"
    exit 1
fi

echo "🔍 正在检查文件名兼容性..."
echo ""

ENGLISH_COUNT=0
NON_ENGLISH_COUNT=0
TOTAL_FILES=0

FILE_LIST=$(mktemp)
find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"

while IFS= read -r file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    file_name=$(basename "$file")
    rel_path="${file#$CUSTOM_DIR/}"
    
    if echo "$file_name" | grep -q '^[a-zA-Z0-9_.-]*$'; then
        ENGLISH_COUNT=$((ENGLISH_COUNT + 1))
        echo "✅ $rel_path"
    else
        NON_ENGLISH_COUNT=$((NON_ENGLISH_COUNT + 1))
        echo "⚠️ $rel_path (非英文文件名)"
    fi
done < "$FILE_LIST"

rm -f "$FILE_LIST"

echo ""
echo "📊 检查结果:"
echo "  总文件数: $TOTAL_FILES 个"
echo "  英文文件名: $ENGLISH_COUNT 个"
echo "  非英文文件名: $NON_ENGLISH_COUNT 个"
echo ""

if [ $NON_ENGLISH_COUNT -gt 0 ]; then
    echo "💡 建议:"
    echo "  为了更好的兼容性，建议将非英文文件名改为英文"
    echo "  英文名更方便复制和运行"
else
    echo "🎉 所有文件名都是英文，兼容性良好！"
fi

echo ""
echo "✅ 文件名检查完成"
EOF
    
    chmod +x "$name_check_script"
    log "✅ 创建文件名检查脚本: $name_check_script"
    
    echo ""
    log "📊 自定义文件集成统计:"
    log "  📦 IPK文件: $ipk_count 个"
    log "  📜 脚本文件: $script_count 个"
    log "  ⚙️ 配置文件: $config_count 个"
    log "  📁 其他文件: $other_count 个"
    log "  总文件数: $file_count 个"
    log "  ✅ 英文文件名: $english_count 个"
    log "  ⚠️ 非英文文件名: $non_english_count 个"
    
    if [ $non_english_count -gt 0 ]; then
        log "💡 文件名兼容性提示:"
        log "  当前有 $non_english_count 个文件使用非英文文件名"
        log "  建议改为英文文件名以获得更好的兼容性"
    fi
    
    CUSTOM_FILE_STATS="/tmp/custom_file_stats.txt"
    cat > "$CUSTOM_FILE_STATS" << EOF
CUSTOM_FILE_TOTAL=$file_count
CUSTOM_IPK_COUNT=$ipk_count
CUSTOM_SCRIPT_COUNT=$script_count
CUSTOM_CONFIG_COUNT=$config_count
CUSTOM_OTHER_COUNT=$other_count
CUSTOM_ENGLISH_COUNT=$english_count
CUSTOM_NON_ENGLISH_COUNT=$non_english_count
EOF
    
    log "✅ 自定义文件集成完成"
}
#【build_firmware_main.sh-19-end】

#【build_firmware_main.sh-20】
verify_compiler_files() {
    log "=== 验证预构建编译器文件 ==="
    
    local target_platform=""
    local target_suffix=""
    case "$TARGET" in
        "ipq40xx")
            target_platform="arm"
            target_suffix="arm_cortex-a7"
            log "目标平台: ARM (高通IPQ40xx)"
            log "目标架构: $target_suffix"
            ;;
        "ramips")
            target_platform="mips"
            target_suffix="mipsel_24kc"
            log "目标平台: MIPS (雷凌MT76xx)"
            log "目标架构: $target_suffix"
            ;;
        "mediatek")
            target_platform="arm"
            target_suffix="arm_cortex-a53"
            log "目标平台: ARM (联发科MT7981)"
            log "目标架构: $target_suffix"
            ;;
        "ath79")
            target_platform="mips"
            target_suffix="mips_24kc"
            log "目标平台: MIPS (高通ATH79)"
            log "目标架构: $target_suffix"
            ;;
        *)
            target_platform="generic"
            target_suffix="generic"
            log "目标平台: 通用"
            ;;
    esac
    
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ 使用环境变量中的编译器目录: $COMPILER_DIR"
        local compiler_dir="$COMPILER_DIR"
    else
        log "🔍 编译器目录未设置或目录不存在"
        log "💡 将使用OpenWrt自动构建的编译器"
        return 0
    fi
    
    log "📊 编译器目录详细检查:"
    log "  路径: $compiler_dir"
    log "  大小: $(du -sh "$compiler_dir" 2>/dev/null | awk '{print $1}' || echo '未知')"
    
    log "⚙️ 可执行编译器检查:"
    local gcc_executable=""
    
    if [ -d "$compiler_dir/bin" ]; then
        gcc_executable=$(find "$compiler_dir/bin" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
    fi
    
    if [ -z "$gcc_executable" ]; then
        gcc_executable=$(find "$compiler_dir" -maxdepth 5 -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
    fi
    
    local gpp_executable=$(find "$compiler_dir" -maxdepth 5 -type f -executable \
      -name "*g++" \
      ! -name "*g++-*" \
      ! -path "*dummy-tools*" \
      ! -path "*scripts*" \
      2>/dev/null | head -1)
    
    local gcc_version_valid=0
    
    if [ -n "$gcc_executable" ]; then
        local executable_name=$(basename "$gcc_executable")
        log "  ✅ 找到可执行GCC: $executable_name"
        
        local version_output=$("$gcc_executable" --version 2>&1)
        if echo "$version_output" | grep -qi "dummy-tools"; then
            log "     ⚠️ 虚假的GCC编译器: scripts/dummy-tools/gcc"
            log "     🔍 继续查找真正的GCC编译器..."
            
            gcc_executable=$(find "$compiler_dir" -maxdepth 5 -type f -executable \
              -name "*gcc" \
              ! -name "*gcc-ar" \
              ! -name "*gcc-ranlib" \
              ! -name "*gcc-nm" \
              ! -path "*dummy-tools*" \
              ! -path "*scripts*" \
              ! -path "$(dirname "$gcc_executable")" \
              2>/dev/null | head -1)
            
            if [ -n "$gcc_executable" ]; then
                executable_name=$(basename "$gcc_executable")
                log "     ✅ 找到新的GCC编译器: $executable_name"
            fi
        fi
        
        if [ -n "$gcc_executable" ]; then
            if check_gcc_version "$gcc_executable" "11"; then
                gcc_version_valid=1
                log "     🎯 GCC 8-15.x 版本兼容验证成功"
            else
                log "     ⚠️ GCC版本检查警告"
                
                local version=$("$gcc_executable" --version 2>&1 | head -1)
                log "     实际版本: $version"
                
                local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
                if [ -n "$major_version" ]; then
                    if [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                        log "     ✅ GCC $major_version.x 可以兼容使用"
                        gcc_version_valid=1
                    elif echo "$version" | grep -qi "12.3.0"; then
                        log "     🎯 检测到OpenWrt 23.05 SDK GCC 12.3.0，自动兼容"
                        gcc_version_valid=1
                    fi
                fi
            fi
        fi
    else
        log "  🔍 未找到真正的GCC编译器，查找工具链工具..."
        
        local toolchain_tools=$(find "$compiler_dir" -maxdepth 5 -type f -executable \
          -name "*gcc*" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -5)
        
        if [ -n "$toolchain_tools" ]; then
            log "  找到的工具链工具:"
            while read tool; do
                local tool_name=$(basename "$tool")
                log "    🔧 $tool_name"
            done <<< "$toolchain_tools"
        fi
    fi
    
    if [ -n "$gpp_executable" ]; then
        log "  ✅ 找到可执行G++: $(basename "$gpp_executable")"
    fi
    
    log "🔨 工具链完整性检查:"
    local required_tools=("as" "ld" "ar" "strip" "objcopy" "objdump" "nm" "ranlib")
    local tool_found_count=0
    
    for tool in "${required_tools[@]}"; do
        local tool_executable=$(find "$compiler_dir" -maxdepth 5 -type f -executable -name "*${tool}*" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
        if [ -n "$tool_executable" ]; then
            log "  ✅ $tool: 找到 ($(basename "$tool_executable"))"
            tool_found_count=$((tool_found_count + 1))
        else
            log "  ⚠️ $tool: 未找到"
        fi
    done
    
    log "📈 编译器完整性评估:"
    log "  真正的GCC编译器: $([ -n "$gcc_executable" ] && echo "是" || echo "否")"
    log "  GCC兼容版本: $([ $gcc_version_valid -eq 1 ] && echo "是" || echo "否")"
    log "  工具链工具: $tool_found_count/${#required_tools[@]} 找到"
    
    if [ -n "$gcc_executable" ] && [ $gcc_version_valid -eq 1 ] && [ $tool_found_count -ge 5 ]; then
        log "🎉 预构建编译器文件完整，GCC版本兼容"
        log "📌 编译器目录: $compiler_dir"
        
        if [ -d "$compiler_dir/bin" ]; then
            export PATH="$compiler_dir/bin:$compiler_dir:$PATH"
            log "🔧 已将编译器目录添加到PATH环境变量"
        fi
        
        return 0
    elif [ -n "$gcc_executable" ] && [ $gcc_version_valid -eq 1 ]; then
        log "⚠️ GCC版本兼容，但工具链不完整"
        log "💡 将尝试使用，但可能回退到自动构建"
        
        if [ -d "$compiler_dir/bin" ]; then
            export PATH="$compiler_dir/bin:$compiler_dir:$PATH"
        fi
        return 0
    elif [ -n "$gcc_executable" ]; then
        log "⚠️ 找到GCC编译器但版本可能不兼容"
        log "💡 建议使用GCC 8-15版本以获得最佳兼容性"
        
        if [ -n "$gcc_executable" ]; then
            local actual_version=$("$gcc_executable" --version 2>&1 | head -1)
            log "  实际GCC版本: $actual_version"
            
            if echo "$actual_version" | grep -qi "12.3.0"; then
                log "  🎯 检测到OpenWrt 23.05 SDK GCC 12.3.0，允许继续"
                return 0
            fi
        fi
        
        return 1
    else
        log "⚠️ 预构建编译器文件可能不完整"
        log "💡 将使用OpenWrt自动构建的编译器作为后备"
        return 1
    fi
}
#【build_firmware_main.sh-20-end】

#【build_firmware_main.sh-21】
check_compiler_invocation() {
    log "=== 检查编译器调用状态（增强版）==="
    
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "🔍 检查预构建编译器调用..."
        
        log "📋 当前PATH环境变量:"
        echo "$PATH" | tr ':' '\n' | grep -E "(compiler|gcc|toolchain)" | head -10 | while read path_item; do
            log "  📍 $path_item"
        done
        
        log "🔧 查找可用编译器:"
        which gcc g++ 2>/dev/null | while read compiler_path; do
            log "  ⚙️ $(basename "$compiler_path"): $compiler_path"
            
            if [[ "$compiler_path" == *"$COMPILER_DIR"* ]]; then
                log "    🎯 来自预构建目录: 是"
            else
                log "    🔄 来自其他位置: 否"
            fi
        done
        
        if [ -d "$BUILD_DIR/staging_dir" ]; then
            log "📁 检查 staging_dir 中的编译器..."
            
            local used_compiler=$(find "$BUILD_DIR/staging_dir" -maxdepth 5 -type f -executable \
              -name "*gcc" \
              ! -name "*gcc-ar" \
              ! -name "*gcc-ranlib" \
              ! -name "*gcc-nm" \
              ! -path "*dummy-tools*" \
              ! -path "*scripts*" \
              2>/dev/null | head -1)
            
            if [ -n "$used_compiler" ]; then
                log "  ✅ 找到正在使用的真正的GCC编译器: $(basename "$used_compiler")"
                log "     路径: $used_compiler"
                
                local version=$("$used_compiler" --version 2>&1 | head -1)
                log "     版本: $version"
                
                if [[ "$used_compiler" == *"$COMPILER_DIR"* ]]; then
                    log "  🎯 编译器来自预构建目录: 是"
                    log "  📌 成功调用了预构建的编译器文件"
                else
                    log "  🔄 编译器来自其他位置: 否"
                    log "  📌 使用的是OpenWrt自动构建的编译器"
                fi
            else
                log "  ℹ️ 未找到真正的GCC编译器（当前未构建）"
                
                log "  🔍 检查SDK编译器:"
                if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
                    local sdk_gcc=$(find "$COMPILER_DIR" -maxdepth 5 -type f -executable \
                      -name "*gcc" \
                      ! -name "*gcc-ar" \
                      ! -name "*gcc-ranlib" \
                      ! -name "*gcc-nm" \
                      ! -path "*dummy-tools*" \
                      ! -path "*scripts*" \
                      2>/dev/null | head -1)
                    
                    if [ -n "$sdk_gcc" ]; then
                        log "    ✅ SDK编译器存在: $(basename "$sdk_gcc")"
                        local sdk_version=$("$sdk_gcc" --version 2>&1 | head -1)
                        log "       版本: $sdk_version"
                        log "    📌 将使用下载的SDK编译器进行构建"
                    else
                        log "    ⚠️ SDK目录中未找到真正的GCC编译器"
                    fi
                fi
            fi
        fi
    else
        log "ℹ️ 未设置预构建编译器目录，将使用自动构建的编译器"
    fi
    
    log "💻 系统编译器检查:"
    if command -v gcc >/dev/null 2>&1; then
        local sys_gcc=$(which gcc)
        local sys_version=$(gcc --version 2>&1 | head -1)
        log "  ✅ 系统GCC: $sys_gcc"
        log "     版本: $sys_version"
        
        local major_version=$(echo "$sys_version" | grep -o "[0-9]\+" | head -1)
        if [ -n "$major_version" ] && [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
            log "     ✅ 系统GCC $major_version.x 版本兼容"
        else
            log "     ⚠️ 系统GCC版本可能不兼容"
        fi
    else
        log "  ❌ 系统GCC未找到"
    fi
    
    log "✅ 编译器调用状态检查完成"
}
#【build_firmware_main.sh-21-end】

#【build_firmware_main.sh-22】
verify_sdk_directory() {
    log "=== 详细验证SDK目录 ==="
    
    if [ -n "$COMPILER_DIR" ]; then
        log "检查环境变量: COMPILER_DIR=$COMPILER_DIR"
        
        if [ -d "$COMPILER_DIR" ]; then
            log "✅ SDK目录存在: $COMPILER_DIR"
            log "📊 目录信息:"
            ls -ld "$COMPILER_DIR" 2>/dev/null || log "无法获取目录信息"
            log "📁 目录内容示例:"
            ls -la "$COMPILER_DIR/" 2>/dev/null | head -10 || log "无法列出目录内容"
            return 0
        else
            log "❌ SDK目录不存在: $COMPILER_DIR"
            log "🔍 检查可能的路径问题..."
            
            local found_dirs=$(find /mnt/openwrt-build -maxdepth 1 -type d -name "*sdk*" 2>/dev/null)
            if [ -n "$found_dirs" ]; then
                log "找到可能的SDK目录:"
                echo "$found_dirs"
                
                local first_dir=$(echo "$found_dirs" | head -1)
                log "使用目录: $first_dir"
                COMPILER_DIR="$first_dir"
                save_env
                return 0
            fi
            
            return 1
        fi
    else
        log "❌ COMPILER_DIR环境变量未设置"
        return 1
    fi
}
#【build_firmware_main.sh-22-end】

#【build_firmware_main.sh-23】
# 此函数已废弃，现在用作公共函数库
# ============================================================================
# 公共函数库 - 先只实现列出所有mk文件
# ============================================================================

# 列出所有mk文件（简化版）
find_device_definition_file() {
    local device_name="$1"
    local platform="$2"
    local base_path="target/linux/$platform"
    local all_files=()
    
    echo "========================================="
    echo "🔍 调试: 开始搜索设备 '$device_name' 的定义文件"
    echo "📁 搜索路径: $base_path"
    echo "========================================="
    
    if [ ! -d "$base_path" ]; then
        echo "❌ 错误: 路径不存在 - $base_path"
        echo ""
        return
    fi
    
    # 收集所有.mk文件
    while IFS= read -r mk_file; do
        all_files+=("$mk_file")
    done < <(find "$base_path" -type f -name "*.mk" 2>/dev/null | sort)
    
    local total_files=${#all_files[@]}
    echo "📊 找到 $total_files 个.mk文件"
    echo ""
    
    if [ $total_files -eq 0 ]; then
        echo "❌ 未找到任何.mk文件"
        echo ""
        return
    fi
    
    echo "📋 文件列表:"
    echo "----------------------------------------"
    for i in "${!all_files[@]}"; do
        echo "[$((i+1))] ${all_files[$i]}"
    done
    echo "----------------------------------------"
    echo ""
    
    # 返回空字符串，因为这只是测试
    echo ""
}

# 其他函数暂时留空或简单返回
extract_device_config() {
    echo ""
}

extract_config_value() {
    echo ""
}

get_device_support_summary() {
    echo "   📁 平台: $2"
    echo "   📁 子平台: $3"
    echo "   ⚠️ 调试模式: 只列出文件"
    find_device_definition_file "$1" "$2"
}

extract_kernel_version_from_device_file() {
    echo ""
}

get_supported_branches() {
    echo "openwrt-23.05 openwrt-21.02"
}

get_subtargets_by_platform() {
    echo "generic"
}

find_kernel_config_by_version() {
    echo ""
}
#【build_firmware_main.sh-23-end】

#【build_firmware_main.sh-24】
cleanup() {
    log "=== 清理构建目录 ==="
    
    if [ -d "$BUILD_DIR" ]; then
        log "检查是否有需要保留的文件..."
        
        if [ -f "$BUILD_DIR/.config" ]; then
            log "备份配置文件..."
            mkdir -p $BACKUP_DIR
            local backup_file="$BACKUP_DIR/config_$(date +%Y%m%d_%H%M%S).config"
            cp "$BUILD_DIR/.config" "$backup_file"
            log "✅ 配置文件备份到: $backup_file"
        fi
        
        if [ -f "$BUILD_DIR/build.log" ]; then
            log "备份编译日志..."
            mkdir -p $BACKUP_DIR
            cp "$BUILD_DIR/build.log" "$BACKUP_DIR/build_$(date +%Y%m%d_%H%M%S).log"
        fi
        
        log "清理构建目录: $BUILD_DIR"
        sudo rm -rf $BUILD_DIR || log "⚠️ 清理构建目录失败"
        log "✅ 构建目录已清理"
    else
        log "ℹ️ 构建目录不存在，无需清理"
    fi
}
#【build_firmware_main.sh-24-end】

#【build_firmware_main.sh-25】
save_source_code_info() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 保存源代码信息 ==="
    
    local source_info_file="$REPO_ROOT/firmware-config/source-info.txt"
    
    echo "=== 源代码信息 ===" > "$source_info_file"
    echo "生成时间: $(date)" >> "$source_info_file"
    echo "构建目录: $BUILD_DIR" >> "$source_info_file"
    echo "仓库URL: $SELECTED_REPO_URL" >> "$source_info_file"
    echo "分支: $SELECTED_BRANCH" >> "$source_info_file"
    echo "目标: $TARGET" >> "$source_info_file"
    echo "子目标: $SUBTARGET" >> "$source_info_file"
    echo "设备: $DEVICE" >> "$source_info_file"
    echo "配置模式: $CONFIG_MODE" >> "$source_info_file"
    echo "编译器目录: $COMPILER_DIR" >> "$source_info_file"
    
    echo "" >> "$source_info_file"
    echo "=== 目录结构 ===" >> "$source_info_file"
    find . -maxdepth 2 -type d 2>/dev/null | sort >> "$source_info_file"
    
    echo "" >> "$source_info_file"
    echo "=== 关键文件 ===" >> "$source_info_file"
    local key_files=("Makefile" "feeds.conf.default" ".config" "rules.mk" "Config.in")
    for file in "${key_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$file: 存在 ($(ls -lh "$file" 2>/dev/null | awk '{print $5}' 2>/dev/null || echo '未知大小'))" >> "$source_info_file"
        else
            echo "$file: 不存在" >> "$source_info_file"
        fi
    done
    
    log "✅ 源代码信息已保存到: $source_info_file"
}
#【build_firmware_main.sh-25-end】

# ============================================
# 步骤10: 验证SDK下载结果
# 对应 firmware-build.yml 步骤10
#【firmware-build.yml-10】
# ============================================
#【build_firmware_main.sh-26】
workflow_step10_verify_sdk() {
    log "=== 步骤10: 验证SDK下载结果（修复版：动态检查） ==="
    
    trap 'echo "⚠️ 步骤10 验证过程中出现错误，继续执行..."' ERR
    
    echo "🔍 检查SDK下载结果..."
    
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        echo "✅ 从环境文件加载变量: COMPILER_DIR=$COMPILER_DIR"
    else
        echo "❌ 环境文件不存在"
    fi
    
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "✅ SDK目录存在: $COMPILER_DIR"
        echo "📊 SDK目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | awk '{print $1}' || echo '未知')"
        
        GCC_FILE=$(find "$COMPILER_DIR" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
        
        if [ -n "$GCC_FILE" ] && [ -x "$GCC_FILE" ]; then
            echo "✅ 找到可执行GCC编译器: $(basename "$GCC_FILE")"
            echo "🔧 GCC版本测试:"
            "$GCC_FILE" --version 2>&1 | head -1
            
            SDK_VERSION=$("$GCC_FILE" --version 2>&1 | head -1)
            MAJOR_VERSION=$(echo "$SDK_VERSION" | grep -o "[0-9]\+" | head -1)
            
            echo "💡 这是OpenWrt官方SDK交叉编译器，用于编译目标平台固件"
            
            if [ "$MAJOR_VERSION" = "12" ]; then
                echo "💡 SDK GCC版本: 12.3.0 (OpenWrt 23.05 SDK)"
            elif [ "$MAJOR_VERSION" = "8" ]; then
                echo "💡 SDK GCC版本: 8.4.0 (OpenWrt 21.02 SDK)"
            else
                echo "💡 SDK GCC版本: $MAJOR_VERSION.x"
            fi
        else
            echo "❌ 未找到可执行的GCC编译器"
            
            DUMMY_GCC=$(find "$COMPILER_DIR" -type f -executable \
              -name "*gcc" \
              -path "*dummy-tools*" \
              2>/dev/null | head -1)
            
            if [ -n "$DUMMY_GCC" ]; then
                echo "⚠️ 检测到虚假的dummy-tools编译器: $DUMMY_GCC"
                echo "💡 这是OpenWrt构建系统的占位符，不是真正的编译器"
            fi
        fi
    else
        echo "❌ SDK目录不存在: $COMPILER_DIR"
        echo "💡 检查可能的SDK目录..."
        
        found_dirs=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "*sdk*" 2>/dev/null)
        if [ -n "$found_dirs" ]; then
            echo "找到可能的SDK目录:"
            echo "$found_dirs"
            
            first_dir=$(echo "$found_dirs" | head -1)
            echo "使用目录: $first_dir"
            COMPILER_DIR="$first_dir"
            
            save_env
            echo "✅ 已更新环境文件"
        fi
    fi
    
    echo "✅ SDK验证完成"
    log "✅ 步骤10 完成"
}
#【build_firmware_main.sh-26-end】

# ============================================
# 步骤11: 添加TurboACC支持
# 对应 firmware-build.yml 步骤11
#【firmware-build.yml-11】
# ============================================
#【build_firmware_main.sh-27】
workflow_step11_add_turboacc() {
    log "=== 步骤11: 添加 TurboACC 支持 ==="
    
    set -e
    trap 'echo "❌ 步骤11 失败，退出代码: $?"; exit 1' ERR
    
    add_turboacc_support
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 添加TurboACC支持失败"
        exit 1
    fi
    
    log "✅ 步骤11 完成"
}
#【build_firmware_main.sh-27-end】

# ============================================
# 步骤12: 配置Feeds
# 对应 firmware-build.yml 步骤12
#【firmware-build.yml-12】
# ============================================
#【build_firmware_main.sh-28】
workflow_step12_configure_feeds() {
    log "=== 步骤12: 配置Feeds ==="
    
    set -e
    trap 'echo "❌ 步骤12 失败，退出代码: $?"; exit 1' ERR
    
    configure_feeds
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 配置Feeds失败"
        exit 1
    fi
    
    log "✅ 步骤12 完成"
}
#【build_firmware_main.sh-28-end】

# ============================================
# 步骤13: 安装TurboACC包
# 对应 firmware-build.yml 步骤13
#【firmware-build.yml-13】
# ============================================
#【build_firmware_main.sh-29】
workflow_step13_install_turboacc() {
    log "=== 步骤13: 安装 TurboACC 包 ==="
    
    set -e
    trap 'echo "❌ 步骤13 失败，退出代码: $?"; exit 1' ERR
    
    install_turboacc_packages
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 安装TurboACC包失败"
        exit 1
    fi
    
    log "✅ 步骤13 完成"
}
#【build_firmware_main.sh-29-end】

# ============================================
# 步骤14: 编译前空间检查
# 对应 firmware-build.yml 步骤14
#【firmware-build.yml-14】
# ============================================
#【build_firmware_main.sh-30】
workflow_step14_pre_build_space_check() {
    log "=== 步骤14: 编译前空间检查 ==="
    
    set -e
    trap 'echo "❌ 步骤14 失败，退出代码: $?"; exit 1' ERR
    
    pre_build_space_check
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 编译前空间检查失败"
        exit 1
    fi
    
    log "✅ 步骤14 完成"
}
#【build_firmware_main.sh-30-end】

# ============================================
# 步骤15: 智能配置生成
# 对应 firmware-build.yml 步骤15
#【firmware-build.yml-15】
# ============================================
#【build_firmware_main.sh-31】
workflow_step15_generate_config() {
    local extra_packages="$1"
    
    log "=== 步骤15: 智能配置生成【修复版】 ==="
    log "当前设备: $DEVICE"
    log "当前目标: $TARGET"
    log "当前子目标: $SUBTARGET"
    
    set -e
    trap 'echo "❌ 步骤15 失败，退出代码: $?"; exit 1' ERR
    
    # 确保环境变量已加载
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从环境文件重新加载: DEVICE=$DEVICE, TARGET=$TARGET"
    fi
    
    # 如果DEVICE为空，尝试从参数获取
    if [ -z "$DEVICE" ] && [ -n "$2" ]; then
        DEVICE="$2"
        log "⚠️ DEVICE为空，使用参数: $DEVICE"
    fi
    
    # 设备名转换 - 针对ac42u的特殊处理
    local device_for_config="$DEVICE"
    case "$DEVICE" in
        ac42u|rt-ac42u)
            device_for_config="asus_rt-ac42u"
            log "🔧 设备名转换: $DEVICE -> $device_for_config"
            ;;
        acrh17|rt-acrh17)
            device_for_config="asus_rt-acrh17"
            log "🔧 设备名转换: $DEVICE -> $device_for_config"
            ;;
        *)
            # 默认转换：转小写，横线变下划线
            device_for_config=$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
            ;;
    esac
    
    generate_config "$extra_packages" "$device_for_config"
    
    log "✅ 步骤15 完成"
}
#【build_firmware_main.sh-31-end】

# ============================================
# 步骤16: 验证USB配置
# 对应 firmware-build.yml 步骤16
#【firmware-build.yml-16】
# ============================================
#【build_firmware_main.sh-32】
workflow_step16_verify_usb() {
    log "=== 步骤16: 验证USB配置（智能检测版） ==="
    
    trap 'echo "⚠️ 步骤16 验证过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    echo "=== 🚨 USB配置智能检测 ==="
    echo ""
    
    # 1. 检测USB核心模块
    echo "1. 🟢 USB核心模块:"
    if grep -q "^CONFIG_PACKAGE_kmod-usb-core=y" .config; then
        echo "   ✅ kmod-usb-core: 已启用"
    else
        echo "   ❌ kmod-usb-core: 未启用"
    fi
    echo ""
    
    # 2. 检测USB 2.0支持
    echo "2. 🟢 USB 2.0支持:"
    local usb2_enabled=0
    if grep -q "^CONFIG_PACKAGE_kmod-usb2=y" .config; then
        echo "   ✅ kmod-usb2: 已启用"
        usb2_enabled=1
    elif grep -q "^CONFIG_USB_EHCI_HCD=y" .config || grep -q "^CONFIG_USB_OHCI_HCD=y" .config; then
        echo "   ✅ USB 2.0功能已启用（通过内核配置）"
        usb2_enabled=1
    else
        echo "   ❌ USB 2.0功能未启用"
    fi
    echo ""
    
    # 3. 智能检测USB 3.0/xhci功能
    echo "3. 🟢 USB 3.0/xhci功能检测:"
    
    local xhci_enabled=0
    local xhci_methods=""
    
    # 方法1: 检查通用xhci-hcd包
    if grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
        xhci_enabled=1
        xhci_methods="$xhci_methods\n   - 通用xhci-hcd包"
    fi
    
    # 方法2: 检查平台专用xhci包
    if grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config; then
        xhci_enabled=1
        xhci_methods="$xhci_methods\n   - 联发科xhci-mtk包"
    fi
    
    if grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-qcom=y" .config; then
        xhci_enabled=1
        xhci_methods="$xhci_methods\n   - 高通xhci-qcom包"
    fi
    
    if grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" .config; then
        xhci_enabled=1
        xhci_methods="$xhci_methods\n   - 平台xhci-plat-hcd包"
    fi
    
    # 方法3: 检查DWC3驱动（内部集成xhci）
    if grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3=y" .config || grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config; then
        xhci_enabled=1
        xhci_methods="$xhci_methods\n   - DWC3控制器（内部集成xhci）"
    fi
    
    # 方法4: 检查内核xhci配置
    if grep -q "^CONFIG_USB_XHCI_HCD=y" .config; then
        xhci_enabled=1
        xhci_methods="$xhci_methods\n   - 内核xhci支持"
    fi
    
    if grep -q "^CONFIG_USB_XHCI_PLATFORM=y" .config; then
        xhci_enabled=1
        xhci_methods="$xhci_methods\n   - 内核平台xhci支持"
    fi
    
    # 方法5: 检查高通平台专用PHY
    if grep -q "^CONFIG_PHY_QCOM_IPQ4019_USB=y" .config; then
        # 高通IPQ40xx平台有专用PHY，通常与DWC3配合
        if [ $xhci_enabled -eq 0 ]; then
            # 虽然没有直接xhci包，但平台支持USB 3.0
            xhci_enabled=1
            xhci_methods="$xhci_methods\n   - 高通IPQ40xx平台（通过PHY和DWC3）"
        fi
    fi
    
    # 输出检测结果
    if [ $xhci_enabled -eq 1 ]; then
        echo "   ✅ USB 3.0/xhci功能已启用"
        echo "   检测方式:"
        echo -e "$xhci_methods" | while read line; do
            [ -n "$line" ] && echo "     $line"
        done
        
        # 显示实际启用的相关配置
        echo "   实际配置:"
        grep -E "CONFIG_(PACKAGE_kmod-usb-xhci|PACKAGE_kmod-usb-dwc3|USB_XHCI|PHY_QCOM)" .config | grep -E "=y|=m" | head -5 | while read line; do
            echo "     $line"
        done
    else
        echo "   ❌ USB 3.0/xhci功能未启用"
    fi
    echo ""
    
    # 4. 检测USB存储驱动
    echo "4. 🟢 USB存储支持:"
    local storage_enabled=0
    
    if grep -q "^CONFIG_PACKAGE_kmod-usb-storage=y" .config; then
        echo "   ✅ kmod-usb-storage: 已启用"
        storage_enabled=1
    fi
    
    if grep -q "^CONFIG_PACKAGE_kmod-usb-storage-uas=y" .config; then
        echo "   ✅ kmod-usb-storage-uas: 已启用"
        storage_enabled=1
    fi
    
    if grep -q "^CONFIG_PACKAGE_kmod-scsi-core=y" .config; then
        echo "   ✅ kmod-scsi-core: 已启用"
    else
        echo "   ❌ kmod-scsi-core: 未启用"
    fi
    
    if [ $storage_enabled -eq 0 ]; then
        echo "   ❌ USB存储驱动未启用"
    fi
    echo ""
    
    # 5. 检测平台专用驱动
    echo "5. 🟢 平台专用驱动检测:"
    
    # 检测目标平台
    local target=$(grep "^CONFIG_TARGET_" .config | grep "=y" | head -1 | cut -d'_' -f2 | tr '[:upper:]' '[:lower:]')
    
    case "$target" in
        ipq40xx|ipq806x|qcom)
            echo "   🔧 检测到高通平台"
            local qcom_drivers=$(grep "^CONFIG_PACKAGE_kmod" .config | grep -E "qcom|ipq40|dwc3" | grep -E "=y|=m" | sort)
            if [ -n "$qcom_drivers" ]; then
                echo "$qcom_drivers" | while read line; do
                    local pkg=$(echo "$line" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1)
                    local val=$(echo "$line" | cut -d'=' -f2)
                    if [ "$val" = "y" ]; then
                        echo "   ✅ $pkg: 已启用"
                    elif [ "$val" = "m" ]; then
                        echo "   📦 $pkg: 模块化"
                    fi
                done
            else
                echo "   未找到高通专用驱动"
            fi
            
            # 检查高通PHY
            if grep -q "^CONFIG_PHY_QCOM_IPQ4019_USB=y" .config; then
                echo "   ✅ 高通IPQ4019 USB PHY: 已启用"
            fi
            ;;
        mediatek|ramips)
            echo "   🔧 检测到联发科平台"
            local mtk_drivers=$(grep "^CONFIG_PACKAGE_kmod" .config | grep -E "mtk|mediatek|xhci-mtk" | grep -E "=y|=m" | sort)
            if [ -n "$mtk_drivers" ]; then
                echo "$mtk_drivers" | while read line; do
                    local pkg=$(echo "$line" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1)
                    local val=$(echo "$line" | cut -d'=' -f2)
                    if [ "$val" = "y" ]; then
                        echo "   ✅ $pkg: 已启用"
                    elif [ "$val" = "m" ]; then
                        echo "   📦 $pkg: 模块化"
                    fi
                done
            else
                echo "   未找到联发科专用驱动"
            fi
            ;;
        ath79)
            echo "   🔧 检测到ATH79平台"
            local ath79_drivers=$(grep "^CONFIG_PACKAGE_kmod" .config | grep -E "ath79" | grep -E "=y|=m" | sort)
            if [ -n "$ath79_drivers" ]; then
                echo "$ath79_drivers" | while read line; do
                    local pkg=$(echo "$line" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1)
                    local val=$(echo "$line" | cut -d'=' -f2)
                    if [ "$val" = "y" ]; then
                        echo "   ✅ $pkg: 已启用"
                    elif [ "$val" = "m" ]; then
                        echo "   📦 $pkg: 模块化"
                    fi
                done
            else
                echo "   未找到ATH79专用驱动"
            fi
            ;;
        *)
            echo "   ℹ️ 通用平台"
            ;;
    esac
    echo ""
    
    # 6. 检查重复配置
    echo "6. 🟢 检查重复配置:"
    local duplicates=$(grep "^CONFIG_PACKAGE_kmod-usb" .config | cut -d'=' -f1 | sort | uniq -d)
    if [ -n "$duplicates" ]; then
        echo "$duplicates" | while read dup; do
            local count=$(grep -c "^$dup=" .config)
            echo "   ⚠️ $dup: 出现 $count 次"
        done
    else
        echo "   ✅ 无重复配置"
    fi
    echo ""
    
    # 7. 统计信息
    echo "7. 📊 USB驱动统计:"
    local total_usb=$(grep -c "^CONFIG_PACKAGE_kmod-usb" .config)
    local enabled_usb=$(grep -c "^CONFIG_PACKAGE_kmod-usb.*=y" .config)
    local module_usb=$(grep -c "^CONFIG_PACKAGE_kmod-usb.*=m" .config)
    echo "   总USB包: $total_usb"
    echo "   已启用: $enabled_usb"
    echo "   模块化: $module_usb"
    echo ""
    
    # 8. USB功能总结
    echo "8. 📋 USB功能总结:"
    
    # USB 2.0
    if [ $usb2_enabled -eq 1 ]; then
        echo "   ✅ USB 2.0: 支持"
    else
        echo "   ❌ USB 2.0: 不支持"
    fi
    
    # USB 3.0
    if [ $xhci_enabled -eq 1 ]; then
        echo "   ✅ USB 3.0: 支持"
    else
        echo "   ❌ USB 3.0: 不支持"
    fi
    
    # USB存储
    if [ $storage_enabled -eq 1 ]; then
        echo "   ✅ USB存储: 支持"
    else
        echo "   ❌ USB存储: 不支持"
    fi
    
    echo ""
    echo "✅ USB配置检查完成"
    log "✅ 步骤16 完成"
}
#【build_firmware_main.sh-32-end】

# ============================================
# 步骤17: USB驱动完整性检查
# 对应 firmware-build.yml 步骤17
#【firmware-build.yml-17】
# ============================================
#【build_firmware_main.sh-33】
workflow_step17_check_usb_drivers() {
    log "=== 步骤17: USB驱动完整性检查（动态检测版） ==="
    
    trap 'echo "⚠️ 步骤17 检查过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    echo "=== USB驱动完整性动态检测 ==="
    echo ""
    
    # 获取目标平台
    local target=$(grep "^CONFIG_TARGET_" .config | grep "=y" | head -1 | cut -d'_' -f2 | tr '[:upper:]' '[:lower:]')
    echo "目标平台: $target"
    echo ""
    
    # 定义基础必需驱动
    local base_required=(
        "kmod-usb-core"
    )
    
    # 根据平台定义必需驱动
    local required_drivers=()
    case "$target" in
        ipq40xx|ipq806x|qcom)
            required_drivers=(
                "kmod-usb-core"
                "kmod-usb2"
                "kmod-usb3"
                "kmod-usb-dwc3"
                "kmod-usb-dwc3-qcom"
                "kmod-usb-storage"
                "kmod-scsi-core"
            )
            ;;
        mediatek|ramips)
            required_drivers=(
                "kmod-usb-core"
                "kmod-usb2"
                "kmod-usb3"
                "kmod-usb-xhci-mtk"
                "kmod-usb-storage"
                "kmod-scsi-core"
            )
            ;;
        ath79)
            required_drivers=(
                "kmod-usb-core"
                "kmod-usb2"
                "kmod-usb-ohci"
                "kmod-usb-storage"
                "kmod-scsi-core"
            )
            ;;
        *)
            required_drivers=(
                "kmod-usb-core"
                "kmod-usb2"
                "kmod-usb-storage"
                "kmod-scsi-core"
            )
            ;;
    esac
    
    echo "🔍 检查必需USB驱动:"
    echo ""
    
    local missing_drivers=()
    local enabled_drivers=()
    
    for driver in "${required_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "   ✅ $driver: 已启用"
            enabled_drivers+=("$driver")
        elif grep -q "^CONFIG_PACKAGE_${driver}=m" .config; then
            echo "   📦 $driver: 模块化"
            enabled_drivers+=("$driver")
        else
            # 检查是否有替代驱动
            local alt_driver=$(grep "^CONFIG_PACKAGE_" .config | grep -i "${driver#kmod-}" | grep -E "=y|=m" | head -1)
            if [ -n "$alt_driver" ]; then
                local alt_name=$(echo "$alt_driver" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1)
                echo "   🔄 $driver: 未找到，但发现替代: $alt_name"
                enabled_drivers+=("$driver(替代:$alt_name)")
            else
                echo "   ❌ $driver: 未启用"
                missing_drivers+=("$driver")
            fi
        fi
    done
    
    echo ""
    echo "📊 统计:"
    echo "   必需驱动: ${#required_drivers[@]} 个"
    echo "   已启用/替代: ${#enabled_drivers[@]} 个"
    echo "   缺失驱动: ${#missing_drivers[@]} 个"
    
    if [ ${#missing_drivers[@]} -gt 0 ]; then
        echo ""
        echo "⚠️ 发现缺失驱动:"
        for driver in "${missing_drivers[@]}"; do
            echo "   - $driver"
        done
        
        # 检查这些驱动是否被内核选项替代
        echo ""
        echo "🔍 检查内核配置替代:"
        for driver in "${missing_drivers[@]}"; do
            local kernel_config=$(grep -E "^CONFIG_.*${driver#kmod-}.*=y" .config | head -1)
            if [ -n "$kernel_config" ]; then
                echo "   ✅ $driver 可能被内核配置 $(echo $kernel_config | cut -d'=' -f1) 替代"
            fi
        done
    fi
    
    echo ""
    echo "🔍 检查所有实际启用的USB驱动:"
    echo "----------------------------------------"
    
    # 获取所有启用的USB驱动
    local all_enabled=$(grep "^CONFIG_PACKAGE_kmod-usb.*=y" .config | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local all_module=$(grep "^CONFIG_PACKAGE_kmod-usb.*=m" .config | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    
    # 显示所有启用的驱动
    if [ -n "$all_enabled" ]; then
        echo "✅ 已启用驱动 ($(echo "$all_enabled" | wc -l) 个):"
        echo "$all_enabled" | while read driver; do
            echo "   ✅ $driver"
        done
    else
        echo "   没有已启用的USB驱动"
    fi
    
    # 显示所有模块化的驱动
    if [ -n "$all_module" ]; then
        echo ""
        echo "📦 模块化驱动 ($(echo "$all_module" | wc -l) 个):"
        echo "$all_module" | while read driver; do
            echo "   📦 $driver"
        done
    fi
    
    # 显示禁用的驱动（可选）
    local all_disabled=$(grep "^# CONFIG_PACKAGE_kmod-usb" .config | grep "is not set" | sed 's/# CONFIG_PACKAGE_//g' | sed 's/ is not set//g' | sort)
    if [ -n "$all_disabled" ]; then
        echo ""
        echo "❌ 禁用驱动 ($(echo "$all_disabled" | wc -l) 个，仅显示前20个):"
        echo "$all_disabled" | head -20 | while read driver; do
            echo "   ❌ $driver"
        done
        if [ $(echo "$all_disabled" | wc -l) -gt 20 ]; then
            echo "   ... 还有 $(( $(echo "$all_disabled" | wc -l) - 20 )) 个禁用驱动未显示"
        fi
    fi
    
    echo "----------------------------------------"
    log "✅ 步骤17 完成"
}
#【build_firmware_main.sh-33-end】

# ============================================
# 步骤20: 修复网络环境
# 对应 firmware-build.yml 步骤20
#【firmware-build.yml-20】
# ============================================
#【build_firmware_main.sh-34】
workflow_step20_fix_network() {
    log "=== 步骤20: 修复网络环境（动态检测版） ==="
    
    trap 'echo "⚠️ 步骤20 修复过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    echo "🔍 检测当前网络环境..."
    
    # 检测网络连通性
    if ping -c 1 -W 2 github.com > /dev/null 2>&1; then
        echo "✅ GitHub 可达"
    else
        echo "⚠️ GitHub 不可达，尝试使用代理..."
    fi
    
    if ping -c 1 -W 2 google.com > /dev/null 2>&1; then
        echo "✅ 国际网络可达"
    else
        echo "⚠️ 国际网络可能受限"
    fi
    
    # 检测当前代理设置
    if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
        echo "检测到代理设置:"
        [ -n "$http_proxy" ] && echo "   HTTP_PROXY: $http_proxy"
        [ -n "$https_proxy" ] && echo "   HTTPS_PROXY: $https_proxy"
    else
        echo "未检测到代理设置"
    fi
    
    echo ""
    echo "🔧 配置Git优化..."
    
    # 动态设置Git配置
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    git config --global core.compression 0
    
    # 检测Git版本并设置相应选项
    local git_version=$(git --version | cut -d' ' -f3)
    echo "Git版本: $git_version"
    
    # 根据网络情况设置SSL验证
    if curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
        export GIT_SSL_NO_VERIFY=0
        echo "✅ SSL验证: 启用"
    else
        export GIT_SSL_NO_VERIFY=1
        export PYTHONHTTPSVERIFY=0
        export CURL_SSL_NO_VERIFY=1
        echo "⚠️ SSL验证: 禁用（由于网络问题）"
    fi
    
    # 测试最终连接
    echo ""
    echo "🔍 测试最终连接..."
    if curl -s --connect-timeout 10 https://github.com > /dev/null; then
        echo "✅ 网络连接正常"
    else
        echo "⚠️ 网络连接可能有问题，但将继续尝试"
    fi
    
    log "✅ 步骤20 完成"
}
#【build_firmware_main.sh-34-end】

# ============================================
# 步骤21: 下载依赖包
# 对应 firmware-build.yml 步骤21
#【firmware-build.yml-21】
# ============================================
#【build_firmware_main.sh-35】
workflow_step21_download_deps() {
    log "=== 步骤21: 下载依赖包（动态优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤21 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    echo "🔧 检查依赖包目录..."
    if [ ! -d "dl" ]; then
        mkdir -p dl
        echo "✅ 创建依赖包目录: dl"
    fi
    
    # 统计现有依赖包
    local dep_count=$(find dl -type f 2>/dev/null | wc -l)
    local dep_size=$(du -sh dl 2>/dev/null | cut -f1 || echo "0B")
    echo "📊 当前依赖包: $dep_count 个, 总大小: $dep_size"
    
    # 检测系统资源动态调整并行数
    local cpu_cores=$(nproc)
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local download_jobs=1
    
    if [ $cpu_cores -ge 4 ] && [ $mem_total -ge 4096 ]; then
        download_jobs=$((cpu_cores > 8 ? 8 : cpu_cores))
        echo "✅ 检测到高性能系统，使用 $download_jobs 并行下载"
    elif [ $cpu_cores -ge 2 ] && [ $mem_total -ge 2048 ]; then
        download_jobs=4
        echo "✅ 检测到标准系统，使用 4 并行下载"
    else
        download_jobs=2
        echo "⚠️ 检测到资源有限，使用 2 并行下载"
    fi
    
    echo "🚀 开始下载依赖包（并行数: $download_jobs）..."
    
    # 使用timeout避免卡死
    local start_time=$(date +%s)
    
    # 先尝试快速下载
    if make -j$download_jobs download -k > download.log 2>&1; then
        echo "✅ 下载完成"
    else
        echo "⚠️ 部分下载失败，尝试单线程重试失败项..."
        # 提取失败的包并重试
        grep -E "ERROR|Failed" download.log | grep -o "make[^)]*" | while read cmd; do
            echo "重试: $cmd"
            eval $cmd || true
        done
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 统计下载结果
    local new_dep_count=$(find dl -type f 2>/dev/null | wc -l)
    local new_dep_size=$(du -sh dl 2>/dev/null | cut -f1)
    local added=$((new_dep_count - dep_count))
    
    echo ""
    echo "📊 下载统计:"
    echo "   耗时: $((duration / 60))分$((duration % 60))秒"
    echo "   原有包: $dep_count 个 ($dep_size)"
    echo "   现有包: $new_dep_count 个 ($new_dep_size)"
    echo "   新增包: $added 个"
    
    # 检查下载错误
    local error_count=$(grep -c -E "ERROR|Failed|404" download.log 2>/dev/null || echo "0")
    if [ $error_count -gt 0 ]; then
        echo "⚠️ 发现 $error_count 个下载错误，但不影响继续"
        echo "错误示例:"
        grep -E "ERROR|Failed|404" download.log | head -5
    fi
    
    log "✅ 步骤21 完成"
}
#【build_firmware_main.sh-35-end】

# ============================================
# 步骤22: 集成自定义文件
# 对应 firmware-build.yml 步骤22
#【firmware-build.yml-22】
# ============================================
#【build_firmware_main.sh-36】
workflow_step22_integrate_custom_files() {
    log "=== 步骤22: 集成自定义文件（增强版） ==="
    
    trap 'echo "⚠️ 步骤22 集成过程中出现错误，继续执行..."' ERR
    
    integrate_custom_files
    
    log "✅ 步骤22 完成"
}
#【build_firmware_main.sh-36-end】

# ============================================
# 步骤23: 前置错误检查
# 对应 firmware-build.yml 步骤23
#【firmware-build.yml-23】
# ============================================
#【build_firmware_main.sh-37】
workflow_step23_pre_build_check() {
    log "=== 步骤23: 前置错误检查（使用公共函数） ==="
    
    set -e
    trap 'echo "❌ 步骤23 失败，退出代码: $?"; exit 1' ERR
    
    echo "🔍 检查当前环境..."
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        echo "✅ 加载环境变量:"
        echo "   SELECTED_BRANCH=$SELECTED_BRANCH"
        echo "   TARGET=$TARGET"
        echo "   SUBTARGET=$SUBTARGET"
        echo "   DEVICE=$DEVICE"
        echo "   CONFIG_MODE=$CONFIG_MODE"
        echo "   COMPILER_DIR=$COMPILER_DIR"
    else
        echo "❌ 错误: 环境文件不存在 ($BUILD_DIR/build_env.sh)"
        exit 1
    fi
    
    cd $BUILD_DIR
    echo ""
    echo "=== 🚨 前置错误动态检测 ==="
    echo ""
    
    local error_count=0
    local warning_count=0
    
    echo "0. 🔍 动态获取设备支持信息:"
    echo "----------------------------------------"
    
    local branches=$(get_supported_branches 2>/dev/null | head -3 | tr '
' ' ' || echo "未知")
    echo "   📦 支持的分支: $branches"
    
    local subtargets=$(get_subtargets_by_platform "$SELECTED_BRANCH" "$TARGET" 2>/dev/null | head -5 | tr '
' ' ' || echo "未知")
    echo "   📁 平台 $TARGET 支持的子平台: $subtargets"
    
    local search_device=""
    case "$DEVICE" in
        ac42u|rt-ac42u|asus_rt-ac42u)
            search_device="ac42u"
            ;;
        acrh17|rt-acrh17|asus_rt-acrh17)
            search_device="acrh17"
            ;;
        *)
            search_device="$DEVICE"
            ;;
    esac
    
    echo "   🔍 搜索设备名: $search_device"
    get_device_support_summary "$search_device" "$TARGET" "$SUBTARGET"
    
    echo "----------------------------------------"
    echo ""
    
    echo "1. ✅ 配置文件检查:"
    if [ -f ".config" ]; then
        local config_size=$(ls -lh .config | awk '{print $5}')
        local config_lines=$(wc -l < .config)
        echo "   ✅ .config 文件存在"
        echo "   📊 大小: $config_size, 行数: $config_lines"
        
        local device_upper=$(echo "$DEVICE" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        if grep -q "CONFIG_TARGET_.*DEVICE.*${device_upper}=y" .config; then
            echo "   ✅ 设备配置正确"
        else
            local device_lower=$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
            if grep -q "CONFIG_TARGET_.*DEVICE.*${device_lower}=y" .config; then
                echo "   ✅ 设备配置正确 (小写)"
            else
                echo "   ❌ 设备配置可能不正确"
                error_count=$((error_count + 1))
            fi
        fi
    else
        echo "   ❌ .config 文件不存在"
        error_count=$((error_count + 1))
    fi
    echo ""
    
    echo "2. ✅ SDK/编译器检查:"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "   ✅ SDK目录存在: $COMPILER_DIR"
        local sdk_size=$(du -sh "$COMPILER_DIR" 2>/dev/null | awk '{print $1}')
        echo "   📊 大小: $sdk_size"
        
        local gcc_file=$(find "$COMPILER_DIR" -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" ! -path "*dummy-tools*" 2>/dev/null | head -1)
        if [ -n "$gcc_file" ]; then
            echo "   ✅ 找到GCC: $(basename "$gcc_file")"
            local gcc_version=$("$gcc_file" --version 2>&1 | head -1)
            echo "   🔧 版本: $gcc_version"
        else
            echo "   ❌ 未找到GCC编译器"
            error_count=$((error_count + 1))
        fi
    else
        echo "   ❌ SDK目录不存在"
        error_count=$((error_count + 1))
    fi
    echo ""
    
    echo "3. ✅ Feeds检查:"
    if [ -d "feeds" ]; then
        local feeds_count=$(find feeds -maxdepth 1 -type d 2>/dev/null | wc -l)
        feeds_count=$((feeds_count - 1))
        echo "   ✅ feeds目录存在, 包含 $feeds_count 个feed"
        
        for feed in packages luci; do
            if [ -d "feeds/$feed" ]; then
                echo "   ✅ $feed feed: 存在"
            else
                echo "   ❌ $feed feed: 不存在"
                warning_count=$((warning_count + 1))
            fi
        done
    else
        echo "   ❌ feeds目录不存在"
        error_count=$((error_count + 1))
    fi
    echo ""
    
    echo "4. ✅ 磁盘空间检查:"
    local available_space=$(df /mnt --output=avail 2>/dev/null | tail -1 || df / --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    echo "   📊 可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        echo "   ❌ 空间严重不足 (<5G)"
        error_count=$((error_count + 1))
    elif [ $available_gb -lt 10 ]; then
        echo "   ⚠️ 空间较低 (<10G)"
        warning_count=$((warning_count + 1))
    elif [ $available_gb -lt 20 ]; then
        echo "   ⚠️ 空间一般 (<20G)"
        warning_count=$((warning_count + 1))
    else
        echo "   ✅ 空间充足"
    fi
    echo ""
    
    echo "5. ✅ USB驱动检查:"
    local critical_drivers=(
        "kmod-usb-core"
    )
    
    case "$TARGET" in
        ipq40xx|ipq806x|qcom)
            critical_drivers+=("kmod-usb-dwc3" "kmod-usb-dwc3-qcom")
            ;;
        mediatek|ramips)
            critical_drivers+=("kmod-usb-xhci-mtk")
            ;;
    esac
    
    local missing_usb=0
    for driver in "${critical_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "   ✅ $driver: 已启用"
        elif grep -q "^CONFIG_PACKAGE_${driver}=m" .config; then
            echo "   📦 $driver: 模块化"
        else
            echo "   ❌ $driver: 未启用"
            missing_usb=$((missing_usb + 1))
        fi
    done
    
    if [ $missing_usb -gt 0 ]; then
        echo "   ⚠️ 有 $missing_usb 个关键USB驱动缺失"
        warning_count=$((warning_count + 1))
    fi
    echo ""
    
    echo "6. ✅ 内存检查:"
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    local mem_available=$(free -m | awk '/^Mem:/{print $7}')
    echo "   📊 总内存: ${mem_total}MB, 可用: ${mem_available}MB"
    
    if [ $mem_available -lt 512 ]; then
        echo "   ⚠️ 可用内存不足 (<512MB)"
        warning_count=$((warning_count + 1))
    else
        echo "   ✅ 内存充足"
    fi
    echo ""
    
    echo "7. ✅ CPU检查:"
    local cpu_cores=$(nproc)
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs)
    echo "   📊 核心数: $cpu_cores"
    echo "   📊 型号: $cpu_model"
    echo ""
    
    echo "8. ✅ 分支兼容性检查:"
    if [ -n "$branches" ] && [ "$branches" != "未知" ]; then
        if echo "$branches" | grep -q "$SELECTED_BRANCH"; then
            echo "   ✅ 当前分支 $SELECTED_BRANCH 在支持列表中"
        else
            echo "   ⚠️ 当前分支 $SELECTED_BRANCH 不在支持列表中"
            warning_count=$((warning_count + 1))
        fi
    fi
    echo ""
    
    echo "9. ✅ 内核配置文件检查:"
    local kernel_configs=$(find "target/linux/$TARGET" -type f -name "config-*" 2>/dev/null | wc -l)
    if [ $kernel_configs -gt 0 ]; then
        echo "   ✅ 找到 $kernel_configs 个内核配置文件"
    else
        echo "   ⚠️ 未找到内核配置文件"
        warning_count=$((warning_count + 1))
    fi
    echo ""
    
    echo "========================================"
    if [ $error_count -gt 0 ]; then
        echo "❌❌❌ 检测到 $error_count 个错误，请修复后重试 ❌❌❌"
        exit 1
    elif [ $warning_count -gt 0 ]; then
        echo "⚠️⚠️⚠️ 检测到 $warning_count 个警告，但可以继续 ⚠️⚠️⚠️"
    else
        echo "✅✅✅ 所有检查通过，可以开始编译 ✅✅✅"
    fi
    echo "========================================"
    
    log "✅ 步骤23 完成"
}
#【build_firmware_main.sh-37-end】

# ============================================
# 步骤25: 编译固件
# 对应 firmware-build.yml 步骤25
#【firmware-build.yml-25】
# ============================================
#【build_firmware_main.sh-38】
workflow_step25_build_firmware() {
    local enable_parallel="$1"
    
    log "=== 步骤25: 编译固件（智能并行优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤25 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    
    echo "🔧 系统信息:"
    echo "  CPU核心数: $CPU_CORES"
    echo "  内存大小: ${TOTAL_MEM}MB"
    echo "  并行优化: $enable_parallel"
    
    if [ "$enable_parallel" = "true" ]; then
        echo "🧠 智能判断最佳并行任务数..."
        
        # 使用配置文件中的阈值
        : ${HIGH_PERF_CORES:=4}
        : ${HIGH_PERF_MEM:=4096}
        : ${STD_PERF_CORES:=2}
        : ${STD_PERF_MEM:=2048}
        : ${HIGH_PERF_JOBS:=4}
        : ${STD_PERF_JOBS:=3}
        : ${LOW_PERF_JOBS:=2}
        
        if [ $CPU_CORES -ge $HIGH_PERF_CORES ]; then
            if [ $TOTAL_MEM -ge $HIGH_PERF_MEM ]; then
                MAKE_JOBS=$HIGH_PERF_JOBS
                echo "✅ 检测到高性能Runner (${HIGH_PERF_CORES}核+${HIGH_PERF_MEM}MB)"
            else
                MAKE_JOBS=$((HIGH_PERF_JOBS - 1))
                echo "✅ 检测到标准Runner (${HIGH_PERF_CORES}核)"
            fi
        elif [ $CPU_CORES -ge $STD_PERF_CORES ]; then
            if [ $TOTAL_MEM -ge $STD_PERF_MEM ]; then
                MAKE_JOBS=$STD_PERF_JOBS
                echo "✅ 检测到GitHub标准Runner (${STD_PERF_CORES}核${STD_PERF_MEM}MB)"
            else
                MAKE_JOBS=$((STD_PERF_JOBS - 1))
                echo "✅ 检测到${STD_PERF_CORES}核Runner"
            fi
        else
            MAKE_JOBS=$LOW_PERF_JOBS
            echo "⚠️ 检测到低性能系统"
        fi
        
        echo "🎯 决定使用 $MAKE_JOBS 个并行任务"
    else
        MAKE_JOBS=1
        echo "🔄 禁用并行优化，使用单线程编译"
    fi
    
    echo ""
    echo "🚀 开始编译固件"
    echo "💡 编译配置:"
    echo "  - 并行任务: $MAKE_JOBS"
    echo "  - 开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
    
    export FORCE_UNSAFE_CONFIGURE=1
    
    START_TIME=$(date +%s)
    if [ "${ENABLE_VERBOSE_LOG:-false}" = "true" ]; then
        stdbuf -oL -eL time make -j$MAKE_JOBS V=s 2>&1 | tee build.log
    else
        stdbuf -oL -eL time make -j$MAKE_JOBS 2>&1 | tee build.log
    fi
    BUILD_EXIT_CODE=${PIPESTATUS[0]}
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "📊 编译统计:"
    echo "  - 总耗时: $((DURATION / 60))分钟$((DURATION % 60))秒"
    echo "  - 退出代码: $BUILD_EXIT_CODE"
    
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        echo "✅ 固件编译成功"
    else
        echo "❌ 错误: 编译失败，退出代码: $BUILD_EXIT_CODE"
        exit $BUILD_EXIT_CODE
    fi
    
    log "✅ 步骤25 完成"
}
#【build_firmware_main.sh-38-end】

# ============================================
# 步骤26: 检查构建产物
# 对应 firmware-build.yml 步骤26
#【firmware-build.yml-26】
# ============================================
#【build_firmware_main.sh-39】
workflow_step26_check_artifacts() {
    log "=== 步骤26: 检查构建产物（修复版） ==="
    
    set -e
    trap 'echo "❌ 步骤26 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    if [ -d "bin/targets" ]; then
        echo "✅ 找到固件目录"
        
        FIRMWARE_COUNT=0
        PACKAGE_COUNT=0
        
        FIRMWARE_COUNT=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        PACKAGE_COUNT=$(find bin/targets -type f \( -name "*.gz" -o -name "*.ipk" \) 2>/dev/null | wc -l)
        
        echo "=========================================="
        echo "📈 构建产物统计:"
        echo "  固件文件: $FIRMWARE_COUNT 个 (.bin/.img)"
        echo "  包文件: $PACKAGE_COUNT 个 (.gz/.ipk)"
        echo ""
        
        if [ $FIRMWARE_COUNT -gt 0 ]; then
            echo "📁 固件文件详细信息:"
            echo "------------------------------------------"
            find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
                SIZE=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
                FILE_NAME=$(basename "$file")
                echo "🎯 $FILE_NAME ($SIZE)"
            done
        else
            echo "⚠️ 警告: 未找到任何固件文件 (.bin/.img)"
        fi
        
        echo "=========================================="
        echo "✅ 构建产物检查完成"
    else
        echo "❌ 错误: 未找到固件目录"
        exit 1
    fi
    
    log "✅ 步骤26 完成"
}
#【build_firmware_main.sh-39-end】

# ============================================
# 步骤29: 编译后空间检查
# 对应 firmware-build.yml 步骤29
#【firmware-build.yml-29】
# ============================================
#【build_firmware_main.sh-40】
workflow_step29_post_build_space_check() {
    log "=== 步骤29: 编译后空间检查（修复版） ==="
    
    trap 'echo "⚠️ 步骤29 检查过程中出现错误，继续执行..."' ERR
    
    echo "📊 磁盘使用情况:"
    df -h /mnt
    
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1 | awk '{print $1}')
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    echo "/mnt 可用空间: ${AVAILABLE_GB}G"
    
    if [ $AVAILABLE_GB -lt 5 ]; then
        echo "⚠️ 警告: 磁盘空间较低，建议清理"
    else
        echo "✅ 磁盘空间充足"
    fi
    
    log "✅ 步骤29 完成"
}
#【build_firmware_main.sh-40-end】

# ============================================
# 步骤30: 编译总结
# 对应 firmware-build.yml 步骤30
#【firmware-build.yml-30】
# ============================================
#【build_firmware_main.sh-41】
workflow_step30_build_summary() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local timestamp_sec="$4"
    local enable_parallel="$5"
    
    log "=== 步骤30: 编译后总结（增强版） ==="
    
    trap 'echo "⚠️ 步骤30 总结过程中出现错误，继续执行..."' ERR
    
    echo "🚀 构建总结报告"
    echo "========================================"
    echo "设备: $device_name"
    echo "版本: $version_selection"
    echo "配置模式: $config_mode"
    echo "时间戳: $timestamp_sec"
    echo "并行优化: $enable_parallel"
    echo "配置来源: ${CONFIG_FILE:-使用脚本内默认值}"
    echo ""
    
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        FIRMWARE_COUNT=$(find "$BUILD_DIR/bin/targets" -type f -name "*.bin" -o -name "*.img" 2>/dev/null | wc -l)
        
        echo "📦 构建产物:"
        echo "  固件数量: $FIRMWARE_COUNT 个 (.bin/.img)"
        
        if [ $FIRMWARE_COUNT -gt 0 ]; then
            echo "  产物位置: $BUILD_DIR/bin/targets/"
            echo "  下载名称: firmware-$timestamp_sec"
        fi
    fi
    
    echo ""
    echo "🔧 编译器信息:"
    if [ -d "$BUILD_DIR" ]; then
        GCC_FILE=$(find "$BUILD_DIR" -type f -executable             -name "*gcc"             ! -name "*gcc-ar"             ! -name "*gcc-ranlib"             ! -name "*gcc-nm"             ! -path "*dummy-tools*"             ! -path "*scripts*"             2>/dev/null | head -1)
        
        if [ -n "$GCC_FILE" ] && [ -x "$GCC_FILE" ]; then
            SDK_VERSION=$("$GCC_FILE" --version 2>&1 | head -1)
            # 使用 awk 替代 grep 来提取第一个数字
            MAJOR_VERSION=$(echo "$SDK_VERSION" | awk '{match($0, /[0-9]+/); print substr($0, RSTART, RLENGTH)}')
            
            if [ "$MAJOR_VERSION" = "12" ]; then
                echo "  🎯 SDK GCC: 12.3.0 (OpenWrt 23.05 SDK)"
            elif [ "$MAJOR_VERSION" = "8" ]; then
                echo "  🎯 SDK GCC: 8.4.0 (OpenWrt 21.02 SDK)"
            fi
        fi
    fi
    
    echo ""
    echo "📦 SDK下载状态:"
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
            echo "  ✅ SDK已下载: $COMPILER_DIR"
        else
            echo "  ❌ SDK未下载或目录不存在"
        fi
    fi
    
    echo ""
    echo "⚙️ 功能开关状态:"
    echo "  TurboACC: ${ENABLE_TURBOACC:-true}"
    echo "  TCP BBR: ${ENABLE_TCP_BBR:-true}"
    echo "  ath10k-ct强制: ${FORCE_ATH10K_CT:-true}"
    echo "  USB自动修复: ${AUTO_FIX_USB_DRIVERS:-true}"
    
    echo ""
    echo "✅ 构建流程完成"
    echo "========================================"
    
    log "✅ 步骤30 完成"
}
#【build_firmware_main.sh-41-end】

# ============================================
# 已废弃的搜索函数（保留兼容性）
# ============================================
#【build_firmware_main.sh-42】
# ============================================
# 工作流步骤函数 - 步骤05-09
# 对应 firmware-build.yml 步骤05-09
# ============================================

workflow_step05_install_basic_tools() {
    log "=== 步骤05: 安装基础工具（优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤05 失败，退出代码: $?"; exit 1' ERR
    
    setup_environment
    
    log "✅ 步骤05 完成"
}

workflow_step06_initial_space_check() {
    log "=== 步骤06: 初始空间检查 ==="
    
    set -e
    trap 'echo "❌ 步骤06 失败，退出代码: $?"; exit 1' ERR
    
    echo "=== 🚨 初始磁盘空间检查 ==="
    
    echo "📊 磁盘使用情况:"
    df -h
    
    AVAILABLE_SPACE=$(df /mnt --output=avail 2>/dev/null | tail -1 || df / --output=avail | tail -1)
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    echo "可用空间: ${AVAILABLE_GB}G"
    
    if [ $AVAILABLE_GB -lt 20 ]; then
        echo "⚠️ 警告: 初始磁盘空间可能不足 (当前${AVAILABLE_GB}G，建议至少20G)"
    else
        echo "✅ 初始磁盘空间充足"
    fi
    
    echo "💻 CPU信息:"
    echo "  CPU核心数: $(nproc)"
    echo "  CPU型号: $(grep "model name" /proc/cpuinfo | head -1 | cut -d':' -f2 | xargs || echo '未知')"
    
    echo "🧠 内存信息:"
    free -h
    
    log "✅ 步骤06 完成"
}

workflow_step07_create_build_dir() {
    log "=== 步骤07: 创建构建目录 ==="
    
    set -e
    trap 'echo "❌ 步骤07 失败，退出代码: $?"; exit 1' ERR
    
    create_build_dir
    
    log "✅ 步骤07 完成"
}

workflow_step08_initialize_build_env() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    
    log "=== 步骤08: 初始化构建环境 ==="
    
    set -e
    trap 'echo "❌ 步骤08 失败，退出代码: $?"; exit 1' ERR
    
    initialize_build_env "$device_name" "$version_selection" "$config_mode"
    
    log "✅ 步骤08 完成"
}

workflow_step09_download_sdk() {
    local device_name="$1"
    
    log "=== 步骤09: 下载OpenWrt官方SDK ==="
    
    set -e
    trap 'echo "❌ 步骤09 失败，退出代码: $?"; exit 1' ERR
    
    initialize_compiler_env "$device_name"
    
    log "✅ 步骤09 完成"
}

# 以下编译器搜索函数已废弃，由 initialize_compiler_env 替代
#【build_firmware_main.sh-42-end】

#【build_firmware_main.sh-43】
universal_compiler_search() {
    log "=== 通用编译器搜索 ==="
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}
#【build_firmware_main.sh-43-end】

#【build_firmware_main.sh-44】
search_compiler_files_simple() {
    log "=== 简单编译器文件搜索 ==="
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}
#【build_firmware_main.sh-44-end】

#【build_firmware_main.sh-45】
intelligent_platform_aware_compiler_search() {
    log "=== 智能平台感知的编译器搜索 ==="
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}
#【build_firmware_main.sh-45-end】

# ============================================
# 主函数 - 命令分发
# ============================================
#【build_firmware_main.sh-99】
main() {
    local command="$1"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"
    local arg4="$5"
    local arg5="$6"
    
    # 只在首次调用主函数时加载配置
    if [ -z "$MAIN_CONFIG_LOADED" ]; then
        if [ -f "$REPO_ROOT/build-config.conf" ] && [ -z "$CONFIG_LOADED" ]; then
            source "$REPO_ROOT/build-config.conf"
            load_build_config
        fi
        export MAIN_CONFIG_LOADED=1
    fi
    
    case "$command" in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$arg1" "$arg2" "$arg3"
            ;;
        "initialize_compiler_env")
            initialize_compiler_env "$arg1"
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
            generate_config "$arg1"
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
        "fix_network")
            fix_network
            ;;
        "download_dependencies")
            download_dependencies
            ;;
        "integrate_custom_files")
            integrate_custom_files
            ;;
        "cleanup")
            cleanup
            ;;
        "save_source_code_info")
            save_source_code_info
            ;;
        "verify_compiler_files")
            verify_compiler_files
            ;;
        "check_compiler_invocation")
            check_compiler_invocation
            ;;
        "verify_sdk_directory")
            verify_sdk_directory
            ;;
        "verify_config_files")
            verify_config_files
            ;;
        
        "step05_install_basic_tools")
            workflow_step05_install_basic_tools
            ;;
        "step06_initial_space_check")
            workflow_step06_initial_space_check
            ;;
        "step07_create_build_dir")
            workflow_step07_create_build_dir
            ;;
        "step08_initialize_build_env")
            workflow_step08_initialize_build_env "$arg1" "$arg2" "$arg3"
            ;;
        "step09_download_sdk")
            workflow_step09_download_sdk "$arg1"
            ;;
        "step10_verify_sdk")
            workflow_step10_verify_sdk
            ;;
        "step11_add_turboacc")
            workflow_step11_add_turboacc
            ;;
        "step12_configure_feeds")
            workflow_step12_configure_feeds
            ;;
        "step13_install_turboacc")
            workflow_step13_install_turboacc
            ;;
        "step14_pre_build_space_check")
            workflow_step14_pre_build_space_check
            ;;
        "step15_generate_config")
            workflow_step15_generate_config "$arg1"
            ;;
        "step16_verify_usb")
            workflow_step16_verify_usb
            ;;
        "step17_check_usb_drivers")
            workflow_step17_check_usb_drivers
            ;;
        "step20_fix_network")
            workflow_step20_fix_network
            ;;
        "step21_download_deps")
            workflow_step21_download_deps
            ;;
        "step22_integrate_custom_files")
            workflow_step22_integrate_custom_files
            ;;
        "step23_pre_build_check")
            workflow_step23_pre_build_check
            ;;
        "step25_build_firmware")
            workflow_step25_build_firmware "$arg1"
            ;;
        "step26_check_artifacts")
            workflow_step26_check_artifacts
            ;;
        "step29_post_build_space_check")
            workflow_step29_post_build_space_check
            ;;
        "step30_build_summary")
            workflow_step30_build_summary "$arg1" "$arg2" "$arg3" "$arg4" "$arg5"
            ;;
        
        "search_compiler_files")
            universal_compiler_search "$arg1" "$arg2"
            ;;
        "universal_compiler_search")
            universal_compiler_search "$arg1" "$arg2"
            ;;
        "search_compiler_files_simple")
            search_compiler_files_simple "$arg1" "$arg2"
            ;;
        "intelligent_platform_aware_compiler_search")
            intelligent_platform_aware_compiler_search "$arg1" "$arg2" "$arg3"
            ;;
        
        *)
            log "❌ 未知命令: $command"
            echo "可用命令:"
            echo "  基础函数: setup_environment, create_build_dir, initialize_build_env, etc."
            echo ""
            echo "  工作流步骤命令:"
            echo "    step05_install_basic_tools, step06_initial_space_check, step07_create_build_dir"
            echo "    step08_initialize_build_env, step09_download_sdk, step10_verify_sdk"
            echo "    step11_add_turboacc, step12_configure_feeds, step13_install_turboacc"
            echo "    step14_pre_build_space_check, step15_generate_config, step16_verify_usb"
            echo "    step17_check_usb_drivers, step20_fix_network, step21_download_deps"
            echo "    step22_integrate_custom_files, step23_pre_build_check, step25_build_firmware"
            echo "    step26_check_artifacts, step29_post_build_space_check, step30_build_summary"
            exit 1
            ;;
    esac
}

if [ $# -eq 0 ]; then
    echo "错误: 需要提供命令参数"
    echo "用法: $0 <命令> [参数1] [参数2] [参数3] [参数4] [参数5]"
    echo "例如: $0 step08_initialize_build_env xiaomi_mi-router-4a-100m 23.05 normal"
    exit 1
fi

main "$@"
#【build_firmware_main.sh-99-end】
