#!/bin/bash
#【build_firmware_main.sh-00】
# OpenWrt 智能固件构建主脚本
# 对应工作流: firmware-build.yml
# 版本: 3.1.0
# 最后更新: 2026-03-14
#【build_firmware_main.sh-00-end】

#【build_firmware_main.sh-00.5】
# 加载统一配置文件
load_build_config() {
    local config_file="${1:-$REPO_ROOT/build-config.conf}"
    
    # 保存当前环境变量中已设置的值
    local current_source_repo="${SOURCE_REPO_TYPE:-${SOURCE_REPO:-}}"
    local current_build_dir="${BUILD_DIR:-}"
    local current_log_dir="${LOG_DIR:-}"
    local current_backup_dir="${BACKUP_DIR:-}"
    
    if [ -f "$config_file" ]; then
        log "📁 加载统一配置文件: $config_file"
        source "$config_file"
    else
        log "⚠️ 未找到配置文件 $config_file，使用脚本内默认值"
    fi
    
    # 恢复从 workflow 传入的环境变量（优先级更高）
    if [ -n "$current_source_repo" ]; then
        SOURCE_REPO_TYPE="$current_source_repo"
        export SOURCE_REPO_TYPE
        log "✅ 使用 workflow 传入的源码仓库类型: $SOURCE_REPO_TYPE"
    fi
    
    if [ -n "${SOURCE_REPO:-}" ] && [ -z "$SOURCE_REPO_TYPE" ]; then
        SOURCE_REPO_TYPE="$SOURCE_REPO"
        export SOURCE_REPO_TYPE
        log "✅ 从 SOURCE_REPO 环境变量设置源码仓库类型: $SOURCE_REPO_TYPE"
    fi
    
    : ${SOURCE_REPO_TYPE:="immortalwrt"}
    export SOURCE_REPO_TYPE
    
    [ -n "$current_build_dir" ] && BUILD_DIR="$current_build_dir"
    [ -n "$current_log_dir" ] && LOG_DIR="$current_log_dir"
    [ -n "$current_backup_dir" ] && BACKUP_DIR="$current_backup_dir"
    
    export BUILD_DIR LOG_DIR BACKUP_DIR CONFIG_DIR
    export IMMORTALWRT_URL OPENWRT_URL LEDE_URL PACKAGES_FEED_URL LUCI_FEED_URL TURBOACC_FEED_URL
    export ENABLE_TURBOACC ENABLE_TCP_BBR FORCE_ATH10K_CT AUTO_FIX_USB_DRIVERS
    export ENABLE_DYNAMIC_KERNEL_DETECTION ENABLE_DYNAMIC_PLATFORM_DRIVERS ENABLE_DYNAMIC_DEVICE_MAPPING
    
    log "✅ 配置加载完成，当前源码仓库类型: $SOURCE_REPO_TYPE"
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="$REPO_ROOT/build-config.conf"

if [ -n "${SOURCE_REPO:-}" ]; then
    export SOURCE_REPO_TYPE="$SOURCE_REPO"
fi

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

# ============================================
# 动态生成完整的禁用插件列表
# ============================================
generate_forbidden_packages_list() {
    local base_list="$1"
    local full_list=()
    
    # 将空格分隔的字符串转换为数组
    IFS=' ' read -ra BASE_PKGS <<< "$base_list"
    
    for pkg in "${BASE_PKGS[@]}"; do
        # 添加主包（原始名称）
        full_list+=("$pkg")
        
        # 添加 luci-app- 前缀版本（Web界面）
        full_list+=("luci-app-${pkg}")
        
        # 添加 luci-i18n- 国际化版本（中文语言包）
        full_list+=("luci-i18n-${pkg}-zh-cn")
        
        # 添加常见后缀变体
        full_list+=("${pkg}-extra")
        full_list+=("${pkg}-config")
        full_list+=("${pkg}-scripts")
        full_list+=("${pkg}-core")
        full_list+=("${pkg}-lite")
        full_list+=("${pkg}-full")
        full_list+=("${pkg}-static")
        full_list+=("${pkg}-dynamic")
        
        # 添加带下划线的子包格式
        full_list+=("${pkg}_aliyun")
        full_list+=("${pkg}_dnspod")
        full_list+=("${pkg}_cloudflare")
        full_list+=("${pkg}_digitalocean")
        full_list+=("${pkg}_dynv6")
        full_list+=("${pkg}_godaddy")
        full_list+=("${pkg}_no-ip")
        full_list+=("${pkg}_nsupdate")
        full_list+=("${pkg}_route53")
        
        # 添加 INCLUDE 子选项格式
        full_list+=("luci-app-${pkg}_INCLUDE_${pkg}-ng")
        full_list+=("luci-app-${pkg}_INCLUDE_${pkg}-webui")
        full_list+=("luci-app-${pkg}_INCLUDE_${pkg}-extra")
        
        # 添加带连字符的子包格式
        full_list+=("${pkg}-ng")
        full_list+=("${pkg}-webui")
        full_list+=("${pkg}-client")
        full_list+=("${pkg}-server")
        full_list+=("${pkg}-utils")
        full_list+=("${pkg}-tools")
        
        # 添加大写版本（用于配置文件中的宏）
        local upper_pkg=$(echo "$pkg" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        full_list+=("${upper_pkg}")
        full_list+=("PACKAGE_${upper_pkg}")
        full_list+=("LUCI_APP_${upper_pkg}")
        
        # 针对特定包的额外处理
        if [[ "$pkg" == "ddns" ]]; then
            full_list+=("ddns-scripts")
            full_list+=("ddns-scripts_aliyun")
            full_list+=("ddns-scripts_dnspod")
            full_list+=("ddns-scripts_cloudflare.com-v4")
            full_list+=("ddns-scripts_digitalocean")
            full_list+=("ddns-scripts_dynv6")
            full_list+=("ddns-scripts_godaddy")
            full_list+=("ddns-scripts_no-ip_com")
            full_list+=("ddns-scripts_nsupdate")
            full_list+=("ddns-scripts_route53")
            full_list+=("ddns-scripts_duckdns.org")
            full_list+=("ddns-scripts_gandi.net")
            full_list+=("ddns-scripts_inwx.com")
            full_list+=("ddns-scripts_linode.com")
            full_list+=("ddns-scripts_namecheap.com")
        elif [[ "$pkg" == "rclone" ]]; then
            full_list+=("rclone")
            full_list+=("rclone-config")
            full_list+=("rclone-webui")
            full_list+=("rclone-ng")
            full_list+=("rclone-webui-react")
        elif [[ "$pkg" == "qbittorrent" ]]; then
            full_list+=("qbittorrent")
            full_list+=("qbittorrent-static")
            full_list+=("qt5")
            full_list+=("libtorrent")
            full_list+=("libtorrent-rasterbar")
        elif [[ "$pkg" == "filetransfer" ]]; then
            full_list+=("filetransfer")
            full_list+=("filebrowser")
            full_list+=("filemanager")
        elif [[ "$pkg" == "nlbwmon" ]]; then
            full_list+=("nlbwmon")
            full_list+=("luci-app-nlbwmon")
            full_list+=("luci-i18n-nlbwmon-zh-cn")
            full_list+=("nlbwmon-database")
            full_list+=("nlbwmon-legacy")
        elif [[ "$pkg" == "wol" ]]; then
            full_list+=("wol")
            full_list+=("luci-app-wol")
            full_list+=("luci-i18n-wol-zh-cn")
            full_list+=("etherwake")
            full_list+=("wol-utils")
        fi
    done
    
    # 去重并输出，每行一个
    printf '%s\n' "${full_list[@]}" | sort -u
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
    local manual_target=$4
    local manual_subtarget=$5

    cd $BUILD_DIR || handle_error "进入构建目录失败"

    log "=== 版本选择 ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"
    
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        SELECTED_REPO_URL="${LEDE_URL:-https://github.com/coolsnowwolf/lede.git}"
        SELECTED_BRANCH="master"
        log "✅ LEDE源码选择: 固定使用master分支"
    elif [ "$SOURCE_REPO_TYPE" = "openwrt" ]; then
        SELECTED_REPO_URL="${OPENWRT_URL:-https://github.com/openwrt/openwrt.git}"
        if [ "$version_selection" = "23.05" ]; then
            SELECTED_BRANCH="${BRANCH_23_05:-openwrt-23.05}"
        else
            SELECTED_BRANCH="${BRANCH_21_02:-openwrt-21.02}"
        fi
        log "✅ OpenWrt官方源码选择: $SELECTED_BRANCH"
    else
        SELECTED_REPO_URL="${IMMORTALWRT_URL:-https://github.com/immortalwrt/immortalwrt.git}"
        if [ "$version_selection" = "23.05" ]; then
            SELECTED_BRANCH="${BRANCH_23_05:-openwrt-23.05}"
        else
            SELECTED_BRANCH="${BRANCH_21_02:-openwrt-21.02}"
        fi
        log "✅ ImmortalWrt源码选择: $SELECTED_BRANCH"
    fi
    
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
    if [ -n "$manual_target" ] && [ -n "$manual_subtarget" ]; then
        TARGET="$manual_target"
        SUBTARGET="$manual_subtarget"
        DEVICE="$device_name"
        log "✅ 使用手动指定的平台信息: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
    elif [ -f "$SUPPORT_SCRIPT" ]; then
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
        log "❌ support.sh不存在且未手动指定平台信息"
        handle_error "无法确定平台信息"
    fi

    log "🔧 设备: $device_name"
    log "🔧 目标平台: $TARGET/$SUBTARGET"

    CONFIG_MODE="$config_mode"

    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"

    log "=== 编译配置工具 ==="

    local config_tool_created=0
    local real_config_tool=""

    if [ -d "scripts/config" ]; then
        cd scripts/config
        make
        cd $BUILD_DIR

        if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
            log "✅ 方法1成功: 编译生成 conf 工具"

            mkdir -p scripts/config
            cat > scripts/config/config << 'EOF'
#!/bin/sh
CONF_TOOL="$(dirname "$0")/conf"

if [ ! -x "$CONF_TOOL" ]; then
    echo "Error: conf tool not found" >&2
    exit 1
fi

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

    if [ $config_tool_created -eq 0 ]; then
        if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
            log "✅ 方法2成功: 直接使用 conf 工具"
            mkdir -p scripts/config
            cat > scripts/config/config << 'EOF'
#!/bin/sh
exec "$(dirname "$0")/conf" "$@"
EOF
            chmod +x scripts/config/config
            real_config_tool="scripts/config/config"
            config_tool_created=1
        fi
    fi

    if [ $config_tool_created -eq 0 ]; then
        if [ -f "scripts/config/mconf" ] && [ -x "scripts/config/mconf" ]; then
            log "✅ 方法3成功: 使用 mconf 工具"
            mkdir -p scripts/config
            cat > scripts/config/config << 'EOF'
#!/bin/sh
exec "$(dirname "$0")/mconf" "$@"
EOF
            chmod +x scripts/config/config
            real_config_tool="scripts/config/config"
            config_tool_created=1
        fi
    fi

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

    if [ $config_tool_created -eq 0 ]; then
        log "🔧 方法5: 创建功能完整的简易 config 工具"
        mkdir -p scripts/config
        cat > scripts/config/config << 'EOF'
#!/bin/bash
CONFIG_FILE=".config"

show_help() {
    echo "Usage: config [options]"
    echo "  --enable <symbol>    Enable a configuration option"
    echo "  --disable <symbol>   Disable a configuration option"
    echo "  --module <symbol>    Set a configuration option as module"
    echo "  --set-str <name> <value> Set a string configuration option"
}

if [ ! -f "$CONFIG_FILE" ]; then
    touch "$CONFIG_FILE"
fi

case "$1" in
    --enable)
        shift
        symbol="$1"
        symbol="${symbol#CONFIG_}"
        symbol="${symbol#PACKAGE_}"

        sed -i "/^CONFIG_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^CONFIG_PACKAGE_${symbol}=/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_${symbol} is not set/d" "$CONFIG_FILE"
        sed -i "/^# CONFIG_PACKAGE_${symbol} is not set/d" "$CONFIG_FILE"

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

    if [ $config_tool_created -eq 1 ]; then
        log "🔧 创建统一调用接口..."

        echo "$real_config_tool" > scripts/.config_tool_path

        if [ ! -f "scripts/config" ]; then
            if [ -f "scripts/config/config" ]; then
                ln -sf config scripts/config 2>/dev/null || cp scripts/config/config scripts/config 2>/dev/null || true
                log "✅ 创建 scripts/config 链接/副本"
            fi
        fi

        cat > scripts/config-tool << 'EOF'
#!/bin/sh
CONFIG_TOOL_PATH="$(dirname "$0")/.config_tool_path"

if [ -f "$CONFIG_TOOL_PATH" ]; then
    CONFIG_TOOL="$(cat "$CONFIG_TOOL_PATH" 2>/dev/null)"
    if [ -n "$CONFIG_TOOL" ] && [ -f "$CONFIG_TOOL" ] && [ -x "$CONFIG_TOOL" ]; then
        exec "$CONFIG_TOOL" "$@"
    fi
fi

if [ -f "scripts/config/config" ] && [ -x "scripts/config/config" ]; then
    echo "scripts/config/config" > "$CONFIG_TOOL_PATH"
    exec scripts/config/config "$@"
fi

if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
    echo "scripts/config/conf" > "$CONFIG_TOOL_PATH"
    exec scripts/config/conf "$@"
fi

if [ -f "scripts/config/mconf" ] && [ -x "scripts/config/mconf" ]; then
    echo "scripts/config/mconf" > "$CONFIG_TOOL_PATH"
    exec scripts/config/mconf "$@"
fi

echo "Error: config tool not found" >&2
exit 1
EOF
        chmod +x scripts/config-tool
        log "✅ 统一调用接口创建成功: scripts/config-tool"

        if scripts/config-tool --version > /dev/null 2>&1 || scripts/config-tool -h > /dev/null 2>&1; then
            log "✅ 统一调用接口测试通过"
        else
            if [ -f scripts/config/config ] || [ -f scripts/config/conf ]; then
                log "✅ 统一调用接口可用（跳过参数测试）"
            else
                log "⚠️ 统一调用接口可能有问题，但工具可能仍可用"
            fi
        fi
    fi

    if [ $config_tool_created -eq 1 ]; then
        log "✅ 配置工具最终验证通过"
        log "📁 真实工具路径: $real_config_tool"
        log "📁 统一调用接口: scripts/config-tool"

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
initialize_compiler_env() {
    local device_name="$1"
    log "=== 初始化编译器环境（所有源码类型均使用源码自带工具链）==="
    
    # 加载环境变量
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从 $BUILD_DIR/build_env.sh 加载环境变量"
    fi
    
    # 所有源码类型都使用源码自带工具链
    log "✅ 所有源码类型均使用源码自带工具链，无需下载SDK"
    
    # 设置编译器目录为源码目录
    COMPILER_DIR="$BUILD_DIR"
    save_env
    
    # 检查是否有基本的工具链目录
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        log "✅ 找到staging_dir目录，源码工具链已准备就绪"
        
        # 查找工具链中的GCC编译器
        local gcc_files=$(find "$BUILD_DIR/staging_dir" -maxdepth 5 -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" 2>/dev/null | head -1)
        
        if [ -n "$gcc_files" ]; then
            log "✅ 找到工具链中的GCC编译器: $(basename "$gcc_files")"
            log "  🔧 GCC版本: $("$gcc_files" --version 2>&1 | head -1)"
        else
            log "ℹ️ 工具链将在编译过程中自动生成"
        fi
    else
        log "ℹ️ staging_dir目录将在编译过程中自动生成"
    fi
    
    log "✅ 编译器环境初始化完成"
    return 0
}
#【build_firmware_main.sh-07-end】

#【build_firmware_main.sh-08】
add_turboacc_support() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 添加 TurboACC 支持 ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"
    
    # 使用配置文件中的开关
    if [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
        log "🔧 为正常模式添加 TurboACC 支持"
        
        # 检查feeds.conf.default是否存在
        if [ ! -f "feeds.conf.default" ]; then
            touch feeds.conf.default
        fi
        
        # 检查是否已经添加了turboacc feed
        if ! grep -q "turboacc" feeds.conf.default; then
            echo "src-git turboacc ${TURBOACC_FEED_URL:-https://github.com/chenmozhijin/turboacc}" >> feeds.conf.default
            log "✅ TurboACC feed 添加完成"
        else
            log "ℹ️ TurboACC feed 已存在"
        fi
    else
        if [ "$CONFIG_MODE" = "normal" ]; then
            log "ℹ️ TurboACC 已被配置禁用"
        else
            log "ℹ️ 基础模式不添加 TurboACC 支持"
        fi
    fi
}
#【build_firmware_main.sh-08-end】

#【build_firmware_main.sh-09】
configure_feeds() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 配置Feeds ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"
    
    # ============================================
    # 获取需要禁用的插件列表
    # ============================================
    local base_forbidden="${FORBIDDEN_PACKAGES:-vssr ssr-plus passwall rclone ddns qbittorrent filetransfer nlbwmon wol}"
    log "🔧 基础禁用插件: $base_forbidden"
    
    # 生成完整的禁用插件列表（包括子包）
    local full_forbidden_list=($(generate_forbidden_packages_list "$base_forbidden"))
    log "📋 完整禁用插件列表 (${#full_forbidden_list[@]} 个)"
    
    # 从完整列表中提取基础关键词用于目录搜索（去重）
    local search_keywords=()
    local seen_keywords=()
    IFS=' ' read -ra BASE_PKGS <<< "$base_forbidden"
    for pkg in "${BASE_PKGS[@]}"; do
        # 检查是否已添加
        local skip=0
        for seen in "${seen_keywords[@]}"; do
            if [ "$seen" = "$pkg" ]; then
                skip=1
                break
            fi
        done
        if [ $skip -eq 0 ]; then
            search_keywords+=("$pkg")
            seen_keywords+=("$pkg")
        fi
        
        # 添加luci-app-前缀版本
        local luci_pkg="luci-app-${pkg}"
        skip=0
        for seen in "${seen_keywords[@]}"; do
            if [ "$seen" = "$luci_pkg" ]; then
                skip=1
                break
            fi
        done
        if [ $skip -eq 0 ]; then
            search_keywords+=("$luci_pkg")
            seen_keywords+=("$luci_pkg")
        fi
        
        # 添加常见变体
        local variants=("${pkg}-scripts" "${pkg}-extra" "${pkg}-core" "${pkg}-ng" "${pkg}-webui")
        for variant in "${variants[@]}"; do
            skip=0
            for seen in "${seen_keywords[@]}"; do
                if [ "$seen" = "$variant" ]; then
                    skip=1
                    break
                fi
            done
            if [ $skip -eq 0 ]; then
                search_keywords+=("$variant")
                seen_keywords+=("$variant")
            fi
        done
        
        # 特别处理 ddns-scripts
        if [[ "$pkg" == "ddns" ]]; then
            local ddns_variants=("ddns-scripts" "ddns-scripts_aliyun" "ddns-scripts_dnspod" "ddns-scripts_cloudflare" "ddns-scripts_no-ip" "ddns-scripts_route53")
            for variant in "${ddns_variants[@]}"; do
                skip=0
                for seen in "${seen_keywords[@]}"; do
                    if [ "$seen" = "$variant" ]; then
                        skip=1
                        break
                    fi
                done
                if [ $skip -eq 0 ]; then
                    search_keywords+=("$variant")
                    seen_keywords+=("$variant")
                fi
            done
        fi
    done
    
    log "📋 搜索关键词列表 (${#search_keywords[@]} 个): ${search_keywords[*]}"
    
    # ============================================
    # 在配置 feeds 之前，先删除不需要的插件包
    # ============================================
    log "🔧 在配置 feeds 之前，删除不需要的插件包..."
    
    # 查找并删除 package/feeds 中的相关目录
    if [ -d "package/feeds" ]; then
        for keyword in "${search_keywords[@]}"; do
            find package/feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除包目录: $dir"
                rm -rf "$dir"
            done
        done
    fi
    
    # 查找并删除 feeds 目录中的相关目录（如果存在）
    if [ -d "feeds" ]; then
        for keyword in "${search_keywords[@]}"; do
            find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 feeds 目录: $dir"
                rm -rf "$dir"
            done
        done
    fi
    
    log "✅ 不需要的插件包已删除"
    
    # ============================================
    # 根据源码类型设置feeds
    # ============================================
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        log "🔧 LEDE源码模式: 使用LEDE官方feeds"
        
        cat > feeds.conf.default << 'EOF'
src-git packages https://github.com/coolsnowwolf/packages.git
src-git luci https://github.com/coolsnowwolf/luci.git
src-git routing https://github.com/coolsnowwolf/routing.git
src-git telephony https://github.com/coolsnowwolf/telephony.git
EOF
        
        if [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
            echo "src-git turboacc ${TURBOACC_FEED_URL:-https://github.com/chenmozhijin/turboacc}" >> feeds.conf.default
            log "✅ 添加TurboACC feed"
        fi
        
    elif [ "$SOURCE_REPO_TYPE" = "openwrt" ]; then
        log "🔧 OpenWrt官方源码模式: 使用OpenWrt官方feeds"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            FEEDS_BRANCH="openwrt-23.05"
        else
            FEEDS_BRANCH="openwrt-21.02"
        fi
        
        cat > feeds.conf.default << EOF
src-git packages https://github.com/openwrt/packages.git;$FEEDS_BRANCH
src-git luci https://github.com/openwrt/luci.git;$FEEDS_BRANCH
src-git routing https://github.com/openwrt/routing.git;$FEEDS_BRANCH
src-git telephony https://github.com/openwrt/telephony.git;$FEEDS_BRANCH
EOF
        
        if [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
            echo "src-git turboacc ${TURBOACC_FEED_URL:-https://github.com/chenmozhijin/turboacc}" >> feeds.conf.default
            log "✅ 添加TurboACC feed"
        fi
        
    else
        log "🔧 ImmortalWrt源码模式: 使用ImmortalWrt官方feeds"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            FEEDS_BRANCH="openwrt-23.05"
        else
            FEEDS_BRANCH="openwrt-21.02"
        fi
        
        cat > feeds.conf.default << EOF
src-git packages ${PACKAGES_FEED_URL:-https://github.com/immortalwrt/packages.git};$FEEDS_BRANCH
src-git luci ${LUCI_FEED_URL:-https://github.com/immortalwrt/luci.git};$FEEDS_BRANCH
EOF
        
        if [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
            echo "src-git turboacc ${TURBOACC_FEED_URL:-https://github.com/chenmozhijin/turboacc}" >> feeds.conf.default
            log "✅ 添加TurboACC feed"
        fi
    fi
    
    log "📋 feeds.conf.default 内容:"
    cat feeds.conf.default
    
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    # ============================================
    # 在安装 feeds 之前，再次删除不需要的插件
    # ============================================
    log "🔧 在安装 feeds 之前，再次删除不需要的插件包..."
    
    sleep 2
    
    for keyword in "${search_keywords[@]}"; do
        find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
            log "  🗑️  删除 feeds 目录: $dir"
            rm -rf "$dir"
        done
        
        if [ -d "package/feeds" ]; then
            find package/feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 package/feeds 目录: $dir"
                rm -rf "$dir"
            done
        fi
    done
    
    log "✅ 不需要的插件包已删除"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    # ============================================
    # 安装后彻底删除不需要的插件源文件（动态删除）
    # ============================================
    log "🔧 安装后彻底删除不需要的插件源文件（动态删除）..."
    
    # 再次删除所有相关目录
    for keyword in "${search_keywords[@]}"; do
        find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
            log "  🗑️  删除 feeds 目录: $dir"
            rm -rf "$dir"
        done
        
        if [ -d "package/feeds" ]; then
            find package/feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 package/feeds 目录: $dir"
                rm -rf "$dir"
            done
        fi
    done
    
    # 特别处理：根据禁用列表删除所有相关目录（使用完整列表）
    log "🔧 根据完整禁用列表删除所有相关目录..."
    
    # 创建临时文件存储唯一的关键词
    local unique_keywords_file=$(mktemp)
    
    # 从完整禁用列表中提取所有可能的关键词
    for plugin in "${full_forbidden_list[@]}"; do
        # 提取基础包名（去除前缀和后缀）
        local base_name=$(echo "$plugin" | sed 's/^luci-app-//' | sed 's/^luci-i18n-//' | sed 's/-zh-cn$//' | sed 's/_INCLUDE_.*//' | sed 's/-[^-]*$//')
        echo "$base_name" >> "$unique_keywords_file"
        
        # 添加原始名称
        echo "$plugin" >> "$unique_keywords_file"
        
        # 提取核心名称（去除所有后缀）
        local core_name=$(echo "$plugin" | sed 's/^luci-app-//' | sed 's/^luci-i18n-//' | sed 's/-zh-cn$//' | sed 's/_INCLUDE_.*//' | sed 's/-scripts$//' | sed 's/-extra$//' | sed 's/-core$//' | sed 's/-ng$//' | sed 's/-webui$//')
        echo "$core_name" >> "$unique_keywords_file"
    done
    
    # 去重
    sort -u "$unique_keywords_file" > "$unique_keywords_file.sorted"
    
    log "🔍 使用 $(wc -l < "$unique_keywords_file.sorted") 个唯一关键词搜索目录..."
    
    # 遍历所有唯一关键词
    while read keyword; do
        [ -z "$keyword" ] && continue
        
        # 跳过太短的词
        if [ ${#keyword} -lt 3 ]; then
            continue
        fi
        
        # 在 feeds 目录中搜索
        find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
            log "  🗑️  删除 feeds 目录: $dir"
            rm -rf "$dir"
        done
        
        # 在 package/feeds 目录中搜索
        if [ -d "package/feeds" ]; then
            find package/feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 package/feeds 目录: $dir"
                rm -rf "$dir"
            done
        fi
        
        # 在 package 目录中搜索
        find package -maxdepth 2 -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
            # 跳过核心目录
            if [[ "$dir" != "package/feeds" && "$dir" != "package/kernel" && "$dir" != "package/libs" && "$dir" != "package/network" && "$dir" != "package/system" && "$dir" != "package/utils" ]]; then
                log "  🗑️  删除 package 目录: $dir"
                rm -rf "$dir"
            fi
        done
    done < "$unique_keywords_file.sorted"
    
    rm -f "$unique_keywords_file" "$unique_keywords_file.sorted"
    
    log "✅ 所有不需要的插件源文件已彻底删除"
    
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
#【build_firmware_main.sh-09-end】

#【build_firmware_main.sh-10】
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
#【build_firmware_main.sh-10-end】

#【build_firmware_main.sh-11】
#------------------------------------------------------------------------------
# 功能开关配置
#------------------------------------------------------------------------------
: ${ENABLE_TURBOACC:="true"}
: ${ENABLE_TCP_BBR:="true"}
: ${FORCE_ATH10K_CT:="true"}
: ${AUTO_FIX_USB_DRIVERS:="true"}
: ${ENABLE_VERBOSE_LOG:="false"}
: ${FORBIDDEN_PACKAGES:="vssr ssr-plus passwall rclone ddns qbittorrent filetransfer nlbwmon wol"}
#【build_firmware_main.sh-11-end】

#【build_firmware_main.sh-12】
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
    
    local device_config_file="$CONFIG_DIR/devices/$DEVICE.config"
    local usb_generic_file="$CONFIG_DIR/$CONFIG_USB_GENERIC"
    local has_device_config=false
    
    if [ -f "$device_config_file" ]; then
        has_device_config=true
        log "📋 找到设备专用配置文件: $device_config_file"
        log "📋 根据规则: 设备.config + usb-generic.config"
        
        append_config "$device_config_file"
        
        if [ -f "$usb_generic_file" ]; then
            log "📋 添加USB通用配置作为补充: $usb_generic_file"
            append_config "$usb_generic_file"
        fi
        
        log "📋 有设备专用配置，跳过 normal.config 和 $TARGET.config 等通用配置"
    else
        log "📋 未找到设备专用配置文件，使用通用配置组合"
        
        if [ -f "$usb_generic_file" ]; then
            append_config "$usb_generic_file"
        fi
        
        append_config "$CONFIG_DIR/$TARGET.config"
        append_config "$CONFIG_DIR/$SELECTED_BRANCH.config"
        
        if [ "$CONFIG_MODE" = "normal" ]; then
            log "📋 normal模式: 添加 $CONFIG_NORMAL"
            append_config "$CONFIG_DIR/$CONFIG_NORMAL"
        fi
    fi
    
    if [ -n "$extra_packages" ]; then
        log "📦 添加额外包: $extra_packages"
        
        IFS=',' read -ra PKG_ARRAY <<< "$extra_packages"
        for pkg in "${PKG_ARRAY[@]}"; do
            pkg=$(echo "$pkg" | xargs)
            [ -z "$pkg" ] && continue
            echo "CONFIG_PACKAGE_$pkg=y" >> .config
        done
    fi
    
    if [ "${ENABLE_TCP_BBR:-true}" = "true" ]; then
        echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
        echo 'CONFIG_DEFAULT_TCP_CONG="bbr"' >> .config
        log "✅ TCP BBR已启用"
    fi
    
    if [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
        log "✅ TurboACC已启用（全局启用）"
        echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
        echo "CONFIG_PACKAGE_kmod-shortcut-fe=y" >> .config
        echo "CONFIG_PACKAGE_kmod-fast-classifier=y" >> .config
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
    
    local kernel_config_file=""
    local kernel_version=""
    local found_kernel=0
    
    if [ "${ENABLE_DYNAMIC_KERNEL_DETECTION:-true}" = "true" ]; then
        if [ -n "$TARGET" ] && [ -d "target/linux/$TARGET" ]; then
            local device_def_file=""
            while IFS= read -r mkfile; do
                if grep -q "define Device.*$search_device" "$mkfile" 2>/dev/null; then
                    device_def_file="$mkfile"
                    break
                fi
            done < <(find "target/linux/$TARGET" -type f -name "*.mk" 2>/dev/null)
            
            if [ -n "$device_def_file" ] && [ -f "$device_def_file" ]; then
                kernel_version=$(awk -F':=' '/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*:=/ {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}' "$device_def_file")
                if [ -n "$kernel_version" ]; then
                    kernel_config_file="target/linux/$TARGET/config-$kernel_version"
                fi
            fi
        fi
        
        if [ -z "$kernel_config_file" ] || [ ! -f "$kernel_config_file" ]; then
            for ver in ${KERNEL_VERSION_PRIORITY:-6.6 6.1 5.15 5.10 5.4}; do
                kernel_config_file="target/linux/$TARGET/config-$ver"
                if [ -f "$kernel_config_file" ]; then
                    kernel_version="$ver"
                    found_kernel=1
                    break
                fi
            done
        else
            found_kernel=1
        fi
    fi
    
    if [ $found_kernel -eq 1 ] && [ -f "$kernel_config_file" ]; then
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
    else
        if [ "${DEBUG:-false}" = "true" ]; then
            log "ℹ️ 未找到目标平台 $TARGET 的内核配置文件，跳过内核配置添加"
        fi
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
    done < <(printf "%s\n" "${base_usb_packages[@]}" "${extended_usb_packages[@]}" "${fs_support_packages[@]}" | sort -u)
    
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
    
    # ============================================
    # 全面禁用不需要的插件（多轮禁用）
    # ============================================
    log "🔧 ===== 全面禁用不需要的插件 ===== "
    
    local base_forbidden="${FORBIDDEN_PACKAGES:-vssr ssr-plus passwall rclone ddns qbittorrent filetransfer}"
    log "📋 基础禁用插件: $base_forbidden"
    
    local full_forbidden_list=($(generate_forbidden_packages_list "$base_forbidden"))
    log "📋 完整禁用插件列表 (${#full_forbidden_list[@]} 个)"
    
    local search_keywords=()
    IFS=' ' read -ra BASE_PKGS <<< "$base_forbidden"
    for pkg in "${BASE_PKGS[@]}"; do
        search_keywords+=("$pkg")
        search_keywords+=("luci-app-${pkg}")
        search_keywords+=("${pkg}-scripts")
    done
    
    # 第一轮：彻底删除源文件
    log "🔧 第一轮：彻底删除源文件..."
    for keyword in "${search_keywords[@]}"; do
        if [ -d "package/feeds" ]; then
            find package/feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 package/feeds 源目录: $dir"
                rm -rf "$dir"
            done
        fi
        if [ -d "feeds" ]; then
            find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 feeds 源目录: $dir"
                rm -rf "$dir"
            done
        fi
    done
    
    # 第二轮：在 .config 中禁用所有相关包
    log "📋 第二轮：在 .config 中禁用所有相关包..."
    
    local disable_temp=$(mktemp)
    
    for plugin in "${full_forbidden_list[@]}"; do
        echo "$plugin" >> "$disable_temp"
    done
    
    sort -u "$disable_temp" > "$disable_temp.sorted"
    
    while read plugin; do
        [ -z "$plugin" ] && continue
        sed -i "/^CONFIG_PACKAGE_${plugin}=y/d" .config
        sed -i "/^CONFIG_PACKAGE_${plugin}=m/d" .config
        sed -i "/CONFIG_PACKAGE_.*${plugin}/d" .config
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done < "$disable_temp.sorted"
    
    rm -f "$disable_temp" "$disable_temp.sorted"
    
    # 第三轮：删除所有包含关键字的配置行
    log "🔧 第三轮：删除所有包含关键字的配置行..."
    for keyword in "${search_keywords[@]}"; do
        sed -i "/${keyword}/d" .config
        local upper_keyword=$(echo "$keyword" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        sed -i "/${upper_keyword}/d" .config
    done
    
    # 特别处理 DDNS（无论是否在禁用列表中）
    log "🔧 特别处理 DDNS 相关配置..."
    sed -i '/ddns/d' .config
    sed -i '/DDNS/d' .config
    
    log "✅ 禁用完成"
    
    # 去重
    sort .config | uniq > .config.tmp
    mv .config.tmp .config
    
    # 运行 make defconfig 使禁用生效
    log "🔄 运行 make defconfig 使禁用生效..."
    make defconfig > /tmp/build-logs/defconfig_disable.log 2>&1 || {
        log "⚠️ make defconfig 有警告，但继续..."
    }
    
    # 第四轮：检查残留并再次禁用
    log "🔍 第四轮：检查插件残留..."
    
    local remaining=()
    local check_temp=$(mktemp)
    
    for plugin in "${full_forbidden_list[@]}"; do
        echo "$plugin" >> "$check_temp"
    done
    
    sort -u "$check_temp" > "$check_temp.sorted"
    
    while read plugin; do
        [ -z "$plugin" ] && continue
        if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config || grep -q "^CONFIG_PACKAGE_${plugin}=m" .config; then
            remaining+=("$plugin")
        fi
    done < "$check_temp.sorted"
    
    rm -f "$check_temp" "$check_temp.sorted"
    
    if [ ${#remaining[@]} -gt 0 ]; then
        log "⚠️ 发现 ${#remaining[@]} 个插件残留，第四轮禁用..."
        
        for plugin in "${remaining[@]}"; do
            sed -i "/^CONFIG_PACKAGE_${plugin}=y/d" .config
            sed -i "/^CONFIG_PACKAGE_${plugin}=m/d" .config
            sed -i "/^CONFIG_PACKAGE_${plugin}_/d" .config
            echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
            log "  ✅ 再次禁用: $plugin"
        done
        
        sort .config | uniq > .config.tmp
        mv .config.tmp .config
        make defconfig > /dev/null 2>&1
    fi
    
    # 最终验证
    log "📊 最终插件状态验证:"
    local still_enabled=0
    
    for plugin in "${BASE_PKGS[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config || grep -q "^CONFIG_PACKAGE_luci-app-${plugin}=y" .config; then
            log "  ❌ $plugin 相关包仍被启用"
            still_enabled=$((still_enabled + 1))
        elif grep -q "^CONFIG_PACKAGE_${plugin}=m" .config || grep -q "^CONFIG_PACKAGE_luci-app-${plugin}=m" .config; then
            log "  ❌ $plugin 相关包仍被模块化"
            still_enabled=$((still_enabled + 1))
        else
            log "  ✅ $plugin 已禁用"
        fi
    done
    
    if [ $still_enabled -eq 0 ]; then
        log "🎉 所有指定插件已成功禁用"
    else
        log "⚠️ 有 $still_enabled 个插件未能禁用，将在后续阶段再次尝试"
    fi
    
    log "✅ 配置生成完成"
}
#【build_firmware_main.sh-12-end】

#【build_firmware_main.sh-13】
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
#【build_firmware_main.sh-13-end】

#【build_firmware_main.sh-14】
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
#【build_firmware_main.sh-14-end】

#【build_firmware_main.sh-15】
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
    echo "=== 📦 插件配置状态（从最终.config检测） ==="
    echo "----------------------------------------"
    
    # 获取所有启用的插件（排除INCLUDE子选项）
    local plugins=$(grep "^CONFIG_PACKAGE_luci-app" .config | grep -E "=y|=m" | grep -v "INCLUDE" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local plugin_count=0
    local plugin_list=""
    
    if [ -n "$plugins" ]; then
        echo "📱 Luci应用插件:"
        echo ""
        
        # 基础系统类
        local base_plugins=$(echo "$plugins" | grep -E "firewall|base|admin|statistics" | sort)
        if [ -n "$base_plugins" ]; then
            echo "  🔧 基础系统:"
            while read plugin; do
                [ -z "$plugin" ] && continue
                plugin_count=$((plugin_count + 1))
                plugin_list="$plugin_list $plugin"
                local val=$(grep "^CONFIG_PACKAGE_${plugin}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "    ✅ %s\n" "$plugin"
                else
                    printf "    📦 %s\n" "$plugin"
                fi
            done <<< "$base_plugins"
            echo ""
        fi
        
        # 网络应用类
        local network_plugins=$(echo "$plugins" | grep -E "upnp|ddns|samba|vsftpd|ftp|nfs|aria2|qbittorrent|transmission" | sort)
        if [ -n "$network_plugins" ]; then
            echo "  🌐 网络应用:"
            while read plugin; do
                [ -z "$plugin" ] && continue
                plugin_count=$((plugin_count + 1))
                plugin_list="$plugin_list $plugin"
                local val=$(grep "^CONFIG_PACKAGE_${plugin}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "    ✅ %s\n" "$plugin"
                else
                    printf "    📦 %s\n" "$plugin"
                fi
            done <<< "$network_plugins"
            echo ""
        fi
        
        # 安全工具类
        local security_plugins=$(echo "$plugins" | grep -E "openvpn|wireguard|ipsec|vpn|arpbind" | sort)
        if [ -n "$security_plugins" ]; then
            echo "  🔒 安全工具:"
            while read plugin; do
                [ -z "$plugin" ] && continue
                plugin_count=$((plugin_count + 1))
                plugin_list="$plugin_list $plugin"
                local val=$(grep "^CONFIG_PACKAGE_${plugin}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "    ✅ %s\n" "$plugin"
                else
                    printf "    📦 %s\n" "$plugin"
                fi
            done <<< "$security_plugins"
            echo ""
        fi
        
        # 系统工具类
        local system_plugins=$(echo "$plugins" | grep -E "diskman|hd-idle|automount|autoreboot|wol|nlbwmon|sqm|accesscontrol" | sort)
        if [ -n "$system_plugins" ]; then
            echo "  ⚙️ 系统工具:"
            while read plugin; do
                [ -z "$plugin" ] && continue
                plugin_count=$((plugin_count + 1))
                plugin_list="$plugin_list $plugin"
                local val=$(grep "^CONFIG_PACKAGE_${plugin}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "    ✅ %s\n" "$plugin"
                else
                    printf "    📦 %s\n" "$plugin"
                fi
            done <<< "$system_plugins"
            echo ""
        fi
        
        # 其他插件
        local other_plugins=$(echo "$plugins" | grep -v -E "firewall|base|admin|statistics|upnp|ddns|samba|vsftpd|ftp|nfs|aria2|qbittorrent|transmission|openvpn|wireguard|ipsec|vpn|arpbind|diskman|hd-idle|automount|autoreboot|wol|nlbwmon|sqm|accesscontrol" | sort)
        if [ -n "$other_plugins" ]; then
            echo "  📦 其他插件:"
            while read plugin; do
                [ -z "$plugin" ] && continue
                plugin_count=$((plugin_count + 1))
                plugin_list="$plugin_list $plugin"
                local val=$(grep "^CONFIG_PACKAGE_${plugin}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "    ✅ %s\n" "$plugin"
                else
                    printf "    📦 %s\n" "$plugin"
                fi
            done <<< "$other_plugins"
            echo ""
        fi
        
        echo "📊 插件总数: $plugin_count 个"
    else
        echo "❌ 未找到任何Luci插件"
    fi
    
    echo ""
    echo "=== 📦 插件子选项状态 ==="
    echo "----------------------------------------"
    
    # 获取所有INCLUDE子选项
    local includes=$(grep "^CONFIG_PACKAGE_luci-app.*INCLUDE" .config | grep -E "=y|=m" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local include_count=0
    
    if [ -n "$includes" ]; then
        while read include; do
            [ -z "$include" ] && continue
            include_count=$((include_count + 1))
            local val=$(grep "^CONFIG_PACKAGE_${include}=" .config | cut -d'=' -f2)
            if [ "$val" = "y" ]; then
                printf "  ✅ %s\n" "$include"
            else
                printf "  📦 %s\n" "$include"
            fi
        done <<< "$includes"
        echo ""
        echo "📊 子选项总数: $include_count 个"
    else
        echo "❌ 未找到任何插件子选项"
    fi
    
    echo ""
    echo "=== 📦 内核模块配置状态 ==="
    echo "----------------------------------------"

    local kernel_modules=$(grep "^CONFIG_PACKAGE_kmod-" .config | grep -E "=y|=m" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local module_count=0

    if [ -n "$kernel_modules" ]; then
        # USB相关模块
        local usb_modules=$(echo "$kernel_modules" | grep "usb" | sort)
        if [ -n "$usb_modules" ]; then
            echo "🔌 USB模块:"
            while read module; do
                [ -z "$module" ] && continue
                module_count=$((module_count + 1))
                local val=$(grep "^CONFIG_PACKAGE_${module}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "  ✅ %s\n" "$module"
                else
                    printf "  📦 %s\n" "$module"
                fi
            done <<< "$usb_modules"
            echo ""
        fi
        
        # 文件系统模块
        local fs_modules=$(echo "$kernel_modules" | grep "fs-" | sort)
        if [ -n "$fs_modules" ]; then
            echo "💾 文件系统模块:"
            while read module; do
                [ -z "$module" ] && continue
                module_count=$((module_count + 1))
                local val=$(grep "^CONFIG_PACKAGE_${module}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "  ✅ %s\n" "$module"
                else
                    printf "  📦 %s\n" "$module"
                fi
            done <<< "$fs_modules"
            echo ""
        fi
        
        # 网络模块
        local net_modules=$(echo "$kernel_modules" | grep -E "net|ipt|nf-|tcp" | sort)
        if [ -n "$net_modules" ]; then
            echo "🌐 网络模块:"
            while read module; do
                [ -z "$module" ] && continue
                module_count=$((module_count + 1))
                local val=$(grep "^CONFIG_PACKAGE_${module}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "  ✅ %s\n" "$module"
                else
                    printf "  📦 %s\n" "$module"
                fi
            done <<< "$net_modules"
            echo ""
        fi
        
        # 其他内核模块
        local other_modules=$(echo "$kernel_modules" | grep -v "usb\|fs-\|net\|ipt\|nf-\|tcp" | sort)
        if [ -n "$other_modules" ]; then
            echo "🔧 其他内核模块:"
            while read module; do
                [ -z "$module" ] && continue
                module_count=$((module_count + 1))
                local val=$(grep "^CONFIG_PACKAGE_${module}=" .config | cut -d'=' -f2)
                if [ "$val" = "y" ]; then
                    printf "  ✅ %s\n" "$module"
                else
                    printf "  📦 %s\n" "$module"
                fi
            done <<< "$other_modules"
            echo ""
        fi
        
        echo "📊 内核模块总数: $module_count 个"
    else
        echo "未找到内核模块"
    fi

    echo ""
    echo "=== 📦 网络工具配置状态 ==="
    echo "----------------------------------------"

    local net_tools=$(grep "^CONFIG_PACKAGE_" .config | grep -E "=y|=m" | grep -E "iptables|nftables|firewall|qos|sfe|shortcut|acceler|tc|fullcone" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local net_count=0

    if [ -n "$net_tools" ]; then
        while read tool; do
            [ -z "$tool" ] && continue
            net_count=$((net_count + 1))
            if grep -q "^CONFIG_PACKAGE_${tool}=y" .config; then
                printf "  ✅ %s\n" "$tool"
            elif grep -q "^CONFIG_PACKAGE_${tool}=m" .config; then
                printf "  📦 %s\n" "$tool"
            fi
        done <<< "$net_tools"
        echo ""
        echo "📊 网络工具总数: $net_count 个"
    else
        echo "未找到网络工具"
    fi

    echo ""
    echo "=== 📦 文件系统支持 ==="
    echo "----------------------------------------"

    local fs_support=$(grep "^CONFIG_PACKAGE_kmod-fs-" .config | grep -E "=y|=m" | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    local fs_count=0

    if [ -n "$fs_support" ]; then
        while read fs; do
            [ -z "$fs" ] && continue
            fs_count=$((fs_count + 1))
            if grep -q "^CONFIG_PACKAGE_${fs}=y" .config; then
                printf "  ✅ %s\n" "$fs"
            elif grep -q "^CONFIG_PACKAGE_${fs}=m" .config; then
                printf "  📦 %s\n" "$fs"
            fi
        done <<< "$fs_support"
        echo ""
        echo "📊 文件系统总数: $fs_count 个"
    else
        echo "未找到文件系统支持"
    fi

    echo ""
    echo "=== 📊 配置统计 ==="
    echo "----------------------------------------"

    local enabled_packages=$(grep -c "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null || echo "0")
    local module_packages=$(grep -c "^CONFIG_PACKAGE_.*=m$" .config 2>/dev/null || echo "0")
    local disabled_packages=$(grep -c "^# CONFIG_PACKAGE_.* is not set$" .config 2>/dev/null || echo "0")
    local kernel_configs=$(grep -c "^CONFIG_[A-Z].*=y$" .config | grep -v "PACKAGE" | wc -l)

    echo "  ✅ 已启用软件包: $enabled_packages 个"
    echo "  📦 模块化软件包: $module_packages 个"
    echo "  ❌ 已禁用软件包: $disabled_packages 个"
    echo "  ⚙️ 内核配置: $kernel_configs 个"
    echo "  📝 总配置行数: $(wc -l < .config) 行"
    echo ""
    
    # ============================================
    # 最终强制禁用不需要的插件
    # ============================================
    log ""
    log "🔧 ===== 最终强制禁用不需要的插件 ===== "
    
    local final_forbidden=(
        "luci-app-filetransfer"
        "luci-i18n-filetransfer-zh-cn"
        "luci-app-rclone_INCLUDE_rclone-ng"
        "luci-app-rclone_INCLUDE_rclone-webui"
        "luci-app-qbittorrent_dynamic"
        "luci-app-qbittorrent"
        "luci-app-rclone"
        "luci-app-vssr"
        "luci-app-ssr-plus"
        "luci-app-passwall"
        "luci-app-autoreboot"
        "luci-app-ddns"
        "luci-app-nlbwmon"
        "luci-app-wol"
        "luci-app-accesscontrol"
    )
    
    local disabled_count=0
    for plugin in "${final_forbidden[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config || grep -q "^CONFIG_PACKAGE_${plugin}=m" .config; then
            sed -i "/^CONFIG_PACKAGE_${plugin}=y/d" .config
            sed -i "/^CONFIG_PACKAGE_${plugin}=m/d" .config
            sed -i "/^CONFIG_PACKAGE_${plugin}_/d" .config
            echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
            log "  ✅ 强制禁用: $plugin"
            disabled_count=$((disabled_count + 1))
        fi
    done
    
    if [ $disabled_count -gt 0 ]; then
        log "✅ 已强制禁用 $disabled_count 个插件"
        # 重新运行 defconfig 使更改生效
        make defconfig > /dev/null 2>&1
    fi
    
    log "✅ 插件最终禁用完成"
    echo "========================================"

    log "✅ 配置应用完成"
    log "最终配置文件: .config"
    log "最终配置大小: $(ls -lh .config | awk '{print $5}')"
    log "最终配置行数: $(wc -l < .config)"
}
#【build_firmware_main.sh-15-end】

#【build_firmware_main.sh-16】
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
#【build_firmware_main.sh-16-end】

#【build_firmware_main.sh-17】
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
}
#【build_firmware_main.sh-17-end】

#【build_firmware_main.sh-18】
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
#【build_firmware_main.sh-18-end】

#【build_firmware_main.sh-19】
verify_compiler_files() {
    log "=== 验证源码自带工具链 ==="
    
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
    
    log "✅ 所有源码类型均使用源码自带工具链"
    log "📊 源码目录大小: $(du -sh "$BUILD_DIR" 2>/dev/null | awk '{print $1}' || echo '未知')"
    
    # 检查staging_dir
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        log "✅ staging_dir目录存在"
        log "📊 staging_dir大小: $(du -sh "$BUILD_DIR/staging_dir" 2>/dev/null | awk '{print $1}' || echo '未知')"
        
        # 查找工具链中的GCC编译器
        local gcc_file=$(find "$BUILD_DIR/staging_dir" -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" 2>/dev/null | head -1)
        
        if [ -n "$gcc_file" ]; then
            log "✅ 找到工具链中的GCC编译器: $(basename "$gcc_file")"
            log "  🔧 完整路径: $gcc_file"
            log "  📋 版本信息: $("$gcc_file" --version 2>&1 | head -1)"
        else
            log "ℹ️ 工具链将在编译过程中生成"
        fi
    else
        log "ℹ️ staging_dir目录将在编译过程中生成"
    fi
    
    log "✅ 源码工具链验证完成"
}
#【build_firmware_main.sh-19-end】

#【build_firmware_main.sh-20】
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
#【build_firmware_main.sh-20-end】

#【build_firmware_main.sh-21】
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
#【build_firmware_main.sh-21-end】

# ============================================================================
# 工作流步骤函数 - 按顺序排列
# ============================================================================

#【build_firmware_main.sh-22】
# ============================================
# 步骤05: 安装基础工具
# 对应 firmware-build.yml 步骤05
# ============================================
workflow_step05_install_basic_tools() {
    log "=== 步骤05: 安装基础工具（优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤05 失败，退出代码: $?"; exit 1' ERR
    
    setup_environment
    
    log "✅ 步骤05 完成"
}
#【build_firmware_main.sh-22-end】

#【build_firmware_main.sh-23】
# ============================================
# 步骤06: 初始空间检查
# 对应 firmware-build.yml 步骤06
# ============================================
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
#【build_firmware_main.sh-23-end】

#【build_firmware_main.sh-24】
# ============================================
# 步骤07: 创建构建目录
# 对应 firmware-build.yml 步骤07
# ============================================
workflow_step07_create_build_dir() {
    log "=== 步骤07: 创建构建目录 ==="
    
    set -e
    trap 'echo "❌ 步骤07 失败，退出代码: $?"; exit 1' ERR
    
    create_build_dir
    
    log "✅ 步骤07 完成"
}
#【build_firmware_main.sh-24-end】

#【build_firmware_main.sh-25】
# ============================================
# 步骤08: 初始化构建环境
# 对应 firmware-build.yml 步骤08
# ============================================
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
#【build_firmware_main.sh-25-end】

#【build_firmware_main.sh-26】
# ============================================
# 步骤08混合模式: 初始化构建环境（混合模式）
# 对应 firmware-build.yml 步骤08混合模式
# ============================================
workflow_step08_initialize_build_env_hybrid() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local manual_target="$4"
    local manual_subtarget="$5"

    log "=== 步骤08: 初始化构建环境（混合模式：优先使用手动输入） ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"

    set -e
    trap 'echo "❌ 步骤08 失败，退出代码: $?"; exit 1' ERR

    initialize_build_env "$device_name" "$version_selection" "$config_mode" "$manual_target" "$manual_subtarget"

    log "✅ 步骤08 完成"
}
#【build_firmware_main.sh-26-end】

#【build_firmware_main.sh-27】
# ============================================
# 步骤09: 编译源码自带工具链
# 对应 firmware-build.yml 步骤09
# ============================================
workflow_step09_download_sdk() {
    local device_name="$1"
    
    log "=== 步骤09: 编译源码自带工具链 ==="
    
    set -e
    trap 'echo "❌ 步骤09 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    # 加载环境变量
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 加载环境变量: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
    fi
    
    log "📌 开始编译工具链..."
    log "   源码类型: $SOURCE_REPO_TYPE"
    log "   目标平台: $TARGET/$SUBTARGET"
    log "   设备: $device_name"
    
    # 检查是否已经编译过工具链
    if [ -d "staging_dir" ] && [ -f "staging_dir/host/bin/gcc" ]; then
        log "  ✅ 工具链已存在，跳过编译"
        COMPILER_DIR="$BUILD_DIR"
        save_env
        log "✅ 步骤09 完成"
        return 0
    fi
    
    # 步骤1: 更新feeds
    log ""
    log "🔄 步骤1: 更新feeds..."
    ./scripts/feeds update -a > /tmp/build-logs/feeds_update.log 2>&1 || {
        log "⚠️ feeds更新有警告，继续..."
    }
    
    # 步骤2: 安装基础feed
    log ""
    log "🔄 步骤2: 安装基础feed..."
    ./scripts/feeds install base > /tmp/build-logs/base_install.log 2>&1 || true
    
    # 步骤3: 准备编译工具链
    log ""
    log "🔄 步骤3: 配置工具链..."
    
    # 获取目标平台和子平台
    local target="${TARGET:-ipq40xx}"
    local subtarget="${SUBTARGET:-generic}"
    
    # 创建最小配置（只编译工具链）
    cat > .config.toolchain << EOF
CONFIG_TARGET_${target}=y
CONFIG_TARGET_${target}_${subtarget}=y
# 只编译工具链，不编译固件
CONFIG_DEVEL=y
CONFIG_TOOLCHAINOPTS=y
# 禁用所有固件相关的配置
CONFIG_TARGET_ROOTFS_INITRAMFS=n
CONFIG_TARGET_ROOTFS_SQUASHFS=n
CONFIG_TARGET_ROOTFS_EXT4FS=n
CONFIG_TARGET_ROOTFS_JFFS2=n
# 禁用内核编译（只编译工具链）
CONFIG_KERNEL_NONE=y
EOF
    
    # 使用最小配置
    cp .config.toolchain .config
    
    # 运行defconfig
    log "  运行 make defconfig..."
    make defconfig > /tmp/build-logs/toolchain_defconfig.log 2>&1
    
    # 步骤4: 编译工具链
    log ""
    log "🔄 步骤4: 编译工具链..."
    log "   开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
    log ""
    
    START_TIME=$(date +%s)
    
    # 先编译tools（基础工具）
    log "  编译 tools (基础工具)..."
    if make tools/compile -j$(nproc) V=s > /tmp/build-logs/tools_compile.log 2>&1; then
        log "  ✅ tools编译完成"
    else
        log "  ⚠️ tools编译有警告，检查日志..."
        tail -50 /tmp/build-logs/tools_compile.log | grep -E "error|Error|ERROR|fail|Fail|FAIL" || true
    fi
    
    # 再编译toolchain（交叉编译工具链）
    log "  编译 toolchain (交叉工具链)..."
    if make toolchain/compile -j$(nproc) V=s > /tmp/build-logs/toolchain_compile.log 2>&1; then
        log "  ✅ toolchain编译完成"
    else
        log "  ⚠️ toolchain编译有警告，检查日志..."
        tail -50 /tmp/build-logs/toolchain_compile.log | grep -E "error|Error|ERROR|fail|Fail|FAIL" || true
    fi
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    log ""
    log "✅ 工具链编译完成，耗时: $((DURATION / 60))分$((DURATION % 60))秒"
    
    # 验证工具链
    log ""
    log "🔍 验证工具链..."
    
    if [ -d "staging_dir" ]; then
        log "  ✅ staging_dir目录存在"
        
        # 查找GCC编译器
        GCC_FILE=$(find staging_dir -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" 2>/dev/null | head -1)
        
        if [ -n "$GCC_FILE" ]; then
            log "  ✅ GCC编译器已生成: $(basename "$GCC_FILE")"
            GCC_VERSION=$("$GCC_FILE" --version 2>&1 | head -1)
            log "     版本: $GCC_VERSION"
        else
            log "  ⚠️ GCC编译器未找到，但可能正在生成中"
        fi
        
        # 统计工具链大小
        TOOLCHAIN_SIZE=$(du -sh staging_dir 2>/dev/null | awk '{print $1}')
        log "  📊 工具链大小: $TOOLCHAIN_SIZE"
    else
        log "  ❌ staging_dir目录不存在，工具链编译可能失败"
        exit 1
    fi
    
    # 保存工具链信息到环境变量
    COMPILER_DIR="$BUILD_DIR"
    save_env
    
    log "✅ 步骤09 完成"
}
#【build_firmware_main.sh-27-end】

#【build_firmware_main.sh-28】
# ============================================
# 步骤10: 验证工具链编译结果
# 对应 firmware-build.yml 步骤10
# ============================================
workflow_step10_verify_sdk() {
    log "=== 步骤10: 验证工具链编译结果 ==="
    
    set -e
    trap 'echo "❌ 步骤10 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    # 加载环境变量
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 加载环境变量: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
    fi
    
    log "🔍 检查工具链编译结果..."
    
    # 检查关键目录
    log ""
    log "📁 检查关键目录:"
    
    local missing_items=0
    local warning_items=0
    
    # 检查staging_dir
    if [ -d "staging_dir" ]; then
        log "  ✅ staging_dir: 存在"
        
        # 检查host目录
        if [ -d "staging_dir/host" ]; then
            log "    ✅ host工具: 存在"
            HOST_BIN_COUNT=$(find staging_dir/host/bin -type f 2>/dev/null | wc -l)
            log "       host工具数量: $HOST_BIN_COUNT"
            
            # 列出关键host工具 - 使用更宽松的检查方式
            local host_tools="make sed awk grep patch tar gzip bzip2"
            for tool in $host_tools; do
                # 查找所有可能的路径
                TOOL_PATH=$(find staging_dir/host -type f -name "$tool" -o -name "$tool.exe" -o -name "*$tool*" 2>/dev/null | head -1)
                if [ -n "$TOOL_PATH" ]; then
                    log "      ✅ $tool: 存在 ($(basename "$TOOL_PATH"))"
                else
                    # 检查系统路径
                    if command -v $tool >/dev/null 2>&1; then
                        log "      ✅ $tool: 使用系统工具 ($(which $tool))"
                    else
                        log "      ⚠️ $tool: 未找到"
                        warning_items=$((warning_items + 1))
                    fi
                fi
            done
        else
            log "    ❌ host工具: 不存在"
            missing_items=$((missing_items + 1))
        fi
        
        # 检查target目录
        TARGET_DIRS=$(find staging_dir -maxdepth 1 -type d -name "target-*" 2>/dev/null)
        if [ -n "$TARGET_DIRS" ]; then
            log "    ✅ target工具链: 存在"
            for target_dir in $TARGET_DIRS; do
                log "       📁 $(basename "$target_dir")"
                
                # 检查bin目录
                if [ -d "$target_dir/bin" ]; then
                    BIN_COUNT=$(find "$target_dir/bin" -type f 2>/dev/null | wc -l)
                    log "         工具数量: $BIN_COUNT"
                    
                    # 检查关键编译工具
                    local compile_tools="gcc g++ ar as ld objcopy strip"
                    for tool in $compile_tools; do
                        TOOL_PATH=$(find "$target_dir/bin" -type f -name "*$tool*" ! -name "*-gcc-ar" ! -name "*-gcc-ranlib" ! -name "*-gcc-nm" 2>/dev/null | head -1)
                        if [ -n "$TOOL_PATH" ]; then
                            log "          ✅ $tool: 存在 ($(basename "$TOOL_PATH"))"
                        fi
                    done
                fi
            done
        else
            log "    ❌ target工具链: 不存在"
            missing_items=$((missing_items + 1))
        fi
    else
        log "  ❌ staging_dir: 不存在"
        missing_items=$((missing_items + 1))
    fi
    
    # 检查工具链GCC
    log ""
    log "🔧 检查GCC编译器:"
    
    GCC_FILES=$(find staging_dir -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" 2>/dev/null)
    GCC_COUNT=$(echo "$GCC_FILES" | wc -l)
    
    if [ $GCC_COUNT -gt 0 ]; then
        log "  ✅ 找到 $GCC_COUNT 个GCC编译器"
        
        # 显示第一个GCC的信息
        FIRST_GCC=$(echo "$GCC_FILES" | head -1)
        log "  📌 示例: $(basename "$FIRST_GCC")"
        log "     路径: $FIRST_GCC"
        
        # 检查GCC版本
        if [ -x "$FIRST_GCC" ]; then
            GCC_VERSION=$("$FIRST_GCC" --version 2>&1 | head -1)
            log "     版本: $GCC_VERSION"
            
            # 检查是否为目标平台编译器
            if [[ "$FIRST_GCC" == *"$TARGET"* ]] || [[ "$FIRST_GCC" == *"openwrt"* ]]; then
                log "     ✅ 是目标平台交叉编译器"
            fi
        fi
    else
        log "  ❌ 未找到GCC编译器"
        missing_items=$((missing_items + 1))
    fi
    
    # 检查关键头文件
    log ""
    log "📋 检查关键头文件:"
    
    KERNEL_HEADERS=$(find staging_dir -name "linux" -type d 2>/dev/null | grep -E "include/linux$" | head -1)
    if [ -n "$KERNEL_HEADERS" ]; then
        log "  ✅ 内核头文件: 存在"
        log "     📁 $KERNEL_HEADERS"
        
        # 检查几个关键头文件
        local headers="kernel.h types.h fs.h"
        for header in $headers; do
            if [ -f "$KERNEL_HEADERS/$header" ]; then
                log "      ✅ $header: 存在"
            fi
        done
    else
        log "  ⚠️ 内核头文件: 未找到（可能正在生成）"
        warning_items=$((warning_items + 1))
    fi
    
    # 检查库文件
    log ""
    log "📚 检查基础库文件:"
    
    LIBS=$(find staging_dir -name "libc.so" -o -name "libgcc_s.so" -o -name "libstdc++.so" 2>/dev/null | head -5)
    if [ -n "$LIBS" ]; then
        log "  ✅ 基础库文件: 存在"
        echo "$LIBS" | while read lib; do
            log "     📄 $(basename "$lib")"
        done
    else
        log "  ⚠️ 基础库文件: 未找到"
        warning_items=$((warning_items + 1))
    fi
    
    # 统计工具链大小
    log ""
    log "📊 工具链统计:"
    if [ -d "staging_dir" ]; then
        TOTAL_SIZE=$(du -sh staging_dir 2>/dev/null | awk '{print $1}')
        log "  总大小: $TOTAL_SIZE"
        
        HOST_SIZE=$(du -sh staging_dir/host 2>/dev/null | awk '{print $1}' || echo "0B")
        log "  host工具: $HOST_SIZE"
        
        TARGET_SIZE=$(du -sh staging_dir/target-* 2>/dev/null | awk '{print $1}' || echo "0B")
        log "  target工具链: $TARGET_SIZE"
    fi
    
    # 检查GCC是否可用
    log ""
    log "🔧 测试GCC编译器可用性:"
    if [ -n "$FIRST_GCC" ] && [ -x "$FIRST_GCC" ]; then
        # 创建一个简单的测试程序
        echo 'int main(){return 0;}' > /tmp/test.c
        if $FIRST_GCC -o /tmp/test /tmp/test.c 2>/dev/null; then
            log "  ✅ GCC编译器可用（能编译简单程序）"
            rm -f /tmp/test /tmp/test.c
        else
            log "  ⚠️ GCC编译器可能有问题（不能编译简单程序）"
            warning_items=$((warning_items + 1))
        fi
    fi
    
    # 根据检查结果决定是否继续
    log ""
    if [ $missing_items -eq 0 ]; then
        if [ $warning_items -eq 0 ]; then
            log "✅✅✅ 工具链验证完全通过，所有组件都存在 ✅✅✅"
        else
            log "✅ 工具链验证通过，但有 $warning_items 个警告（不影响编译）"
            log "   警告说明:"
            log "   - make/gzip 可能以其他名称存在或使用系统工具"
            log "   - 不影响后续编译"
        fi
        return 0
    else
        log "❌ 工具链验证失败，缺少 $missing_items 个关键组件"
        log "   请检查工具链编译日志: /tmp/build-logs/tools_compile.log 和 /tmp/build-logs/toolchain_compile.log"
        exit 1
    fi
    
    log "✅ 步骤10 完成"
}
#【build_firmware_main.sh-28-end】

#【build_firmware_main.sh-29】
# ============================================
# 步骤11: 添加TurboACC支持
# 对应 firmware-build.yml 步骤11
# ============================================
workflow_step11_add_turboacc() {
    log "=== 步骤11: 添加 TurboACC 支持 ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"
    
    set -e
    trap 'echo "❌ 步骤11 失败，退出代码: $?"; exit 1' ERR
    
    add_turboacc_support
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 添加TurboACC支持失败"
        exit 1
    fi
    
    log "✅ 步骤11 完成"
}
#【build_firmware_main.sh-29-end】

#【build_firmware_main.sh-30】
# ============================================
# 步骤12: 配置Feeds
# 对应 firmware-build.yml 步骤12
# ============================================
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
#【build_firmware_main.sh-30-end】

#【build_firmware_main.sh-31】
# ============================================
# 步骤13: 安装TurboACC包
# 对应 firmware-build.yml 步骤13
# ============================================
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
#【build_firmware_main.sh-31-end】

#【build_firmware_main.sh-32】
# ============================================
# 步骤14: 编译前空间检查
# 对应 firmware-build.yml 步骤14
# ============================================
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | awk '{print $1}') || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    local available_space=$(df /mnt --output=avail 2>/dev/null | tail -1 || df / --output=avail | tail -1)
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

workflow_step14_pre_build_space_check() {
    log "=== 步骤14: 编译前空间检查 ==="
    
    set -e
    trap 'echo "❌ 步骤14 失败，退出代码: $?"; exit 1' ERR
    
    # 调用空间检查函数
    pre_build_space_check
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 编译前空间检查失败"
        exit 1
    fi
    
    log "✅ 步骤14 完成"
}
#【build_firmware_main.sh-32-end】

#【build_firmware_main.sh-33】
# ============================================
# 步骤15: 智能配置生成
# 对应 firmware-build.yml 步骤15
# ============================================
workflow_step15_generate_config() {
    local extra_packages="$1"
    
    log "=== 步骤15: 智能配置生成【优化版 - 最多2次尝试】 ==="
    log "当前设备: $DEVICE"
    log "当前目标: $TARGET"
    log "当前子目标: $SUBTARGET"
    
    set -e
    trap 'echo "❌ 步骤15 失败，退出代码: $?"; exit 1' ERR
    
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从环境文件重新加载: DEVICE=$DEVICE, TARGET=$TARGET"
    fi
    
    if [ -z "$DEVICE" ] && [ -n "$2" ]; then
        DEVICE="$2"
        log "⚠️ DEVICE为空，使用参数: $DEVICE"
    fi
    
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
            device_for_config=$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
            ;;
    esac
    
    cd "$BUILD_DIR" || handle_error "无法进入构建目录"
    
    log ""
    log "=== 🔍 设备定义文件验证（前置检查） ==="
    
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
    
    log "搜索设备名: $search_device"
    log "搜索路径: target/linux/$TARGET"
    
    echo ""
    echo "📁 所有子平台 .mk 文件列表:"
    local mk_files=()
    while IFS= read -r file; do
        mk_files+=("$file")
    done < <(find "target/linux/$TARGET" -type f -name "*.mk" 2>/dev/null | sort)
    
    if [ ${#mk_files[@]} -gt 0 ]; then
        echo "----------------------------------------"
        for i in "${!mk_files[@]}"; do
            printf "[%2d] %s\n" $((i+1)) "${mk_files[$i]}"
        done
        echo "----------------------------------------"
        echo "📊 共找到 ${#mk_files[@]} 个 .mk 文件"
    else
        echo "   未找到 .mk 文件"
    fi
    echo ""
    
    local device_file=""
    for mkfile in "${mk_files[@]}"; do
        if grep -q "define Device.*$search_device" "$mkfile" 2>/dev/null; then
            device_file="$mkfile"
            break
        fi
    done
    
    if [ -z "$device_file" ] || [ ! -f "$device_file" ]; then
        log "❌ 错误：未找到设备 $DEVICE (搜索名: $search_device) 的定义文件"
        log "请检查设备名称是否正确，或 target/linux/$TARGET 目录下是否存在对应的 .mk 文件"
        exit 1
    fi
    
    log "✅ 找到设备定义文件: $device_file"
    
    local device_block=""
    device_block=$(awk "/define Device.*$search_device/,/^[[:space:]]*$|^endef/" "$device_file" 2>/dev/null)
    
    if [ -n "$device_block" ]; then
        echo ""
        echo "📋 设备定义信息（关键字段）:"
        echo "----------------------------------------"
        echo "$device_block" | grep -E "define Device" | head -1
        echo "$device_block" | grep -E "^[[:space:]]*(DEVICE_VENDOR|DEVICE_MODEL|DEVICE_VARIANT|DEVICE_DTS)[[:space:]]*:="
        echo "----------------------------------------"
    else
        log "⚠️ 警告：无法提取设备 $search_device 的配置块"
    fi
    
    # 调用 generate_config 函数
    generate_config "$extra_packages" "$device_for_config"
    
    log ""
    log "=== 🔧 强制禁用不需要的插件系列（优化版 - 最多2次尝试） ==="
    
    # 获取基础禁用列表
    local base_forbidden="${FORBIDDEN_PACKAGES:-vssr ssr-plus passwall rclone ddns qbittorrent filetransfer nlbwmon wol}"
    IFS=' ' read -ra BASE_PKGS <<< "$base_forbidden"
    
    # 生成完整禁用列表
    local full_forbidden_list=($(generate_forbidden_packages_list "$base_forbidden"))
    
    log "📋 完整禁用插件列表 (${#full_forbidden_list[@]} 个)"
    
    cp .config .config.before_disable
    
    # 第一轮：禁用所有主包和子包
    log "🔧 第一轮禁用..."
    for plugin in "${full_forbidden_list[@]}"; do
        [ -z "$plugin" ] && continue
        sed -i "/^CONFIG_PACKAGE_${plugin}=y/d" .config
        sed -i "/^CONFIG_PACKAGE_${plugin}=m/d" .config
        sed -i "/^CONFIG_PACKAGE_${plugin}_/d" .config
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done
    
    # 特别处理 nlbwmon 和 wol（确保彻底禁用）
    log "🔧 特别处理 nlbwmon 和 wol..."
    local special_plugins=(
        "nlbwmon"
        "luci-app-nlbwmon"
        "luci-i18n-nlbwmon-zh-cn"
        "nlbwmon-database"
        "wol"
        "luci-app-wol"
        "luci-i18n-wol-zh-cn"
        "etherwake"
    )
    
    for plugin in "${special_plugins[@]}"; do
        sed -i "/^CONFIG_PACKAGE_${plugin}=y/d" .config
        sed -i "/^CONFIG_PACKAGE_${plugin}=m/d" .config
        sed -i "/^CONFIG_PACKAGE_${plugin}_/d" .config
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done
    
    # 删除所有 INCLUDE 子选项
    sed -i '/CONFIG_PACKAGE_luci-app-.*_INCLUDE_/d' .config
    
    sort -u .config > .config.tmp && mv .config.tmp .config
    
    local max_attempts=2
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log "尝试 $attempt/$max_attempts: 运行 make defconfig..."
        make defconfig > /tmp/build-logs/defconfig_disable_attempt${attempt}.log 2>&1 || {
            log "⚠️ make defconfig 警告，但继续"
        }
        
        local still_enabled=0
        # 检查基础包
        for plugin in "${BASE_PKGS[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config || grep -q "^CONFIG_PACKAGE_luci-app-${plugin}=y" .config; then
                still_enabled=$((still_enabled + 1))
                log "  ⚠️ 发现残留: $plugin"
            fi
        done
        
        if [ $still_enabled -eq 0 ]; then
            log "✅ 第 $attempt 次尝试后所有主插件已成功禁用"
            break
        else
            if [ $attempt -lt $max_attempts ]; then
                log "⚠️ 第 $attempt 次尝试后仍有 $still_enabled 个插件残留，再次强制禁用..."
                for plugin in "${BASE_PKGS[@]}"; do
                    sed -i "/^CONFIG_PACKAGE_${plugin}=y/d" .config
                    sed -i "/^CONFIG_PACKAGE_${plugin}=m/d" .config
                    sed -i "/^CONFIG_PACKAGE_luci-app-${plugin}=y/d" .config
                    sed -i "/^CONFIG_PACKAGE_luci-app-${plugin}=m/d" .config
                    echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
                    echo "# CONFIG_PACKAGE_luci-app-${plugin} is not set" >> .config
                done
                sort -u .config > .config.tmp && mv .config.tmp .config
            fi
        fi
        attempt=$((attempt + 1))
    done
    
    log ""
    log "📊 最终插件状态验证:"
    local still_enabled_final=0
    
    # 检查所有需要禁用的插件
    for plugin in "${BASE_PKGS[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config; then
            log "  ❌ $plugin 仍然被启用"
            still_enabled_final=$((still_enabled_final + 1))
        elif grep -q "^CONFIG_PACKAGE_${plugin}=m" .config; then
            log "  ❌ $plugin 仍然被模块化"
            still_enabled_final=$((still_enabled_final + 1))
        elif grep -q "^CONFIG_PACKAGE_luci-app-${plugin}=y" .config; then
            log "  ❌ luci-app-$plugin 仍然被启用"
            still_enabled_final=$((still_enabled_final + 1))
        elif grep -q "^CONFIG_PACKAGE_luci-app-${plugin}=m" .config; then
            log "  ❌ luci-app-$plugin 仍然被模块化"
            still_enabled_final=$((still_enabled_final + 1))
        else
            log "  ✅ $plugin 已正确禁用"
        fi
    done
    
    if [ $still_enabled_final -eq 0 ]; then
        log "🎉 所有指定插件已成功禁用"
    else
        log "⚠️ 有 $still_enabled_final 个插件未能禁用，请检查 feeds 或依赖"
        
        # 最终强力禁用
        log "🔧 执行最终强力禁用..."
        for plugin in "${BASE_PKGS[@]}"; do
            sed -i "/${plugin}/d" .config
            sed -i "/$(echo $plugin | tr '[:lower:]' '[:upper:]')/d" .config
        done
        make defconfig > /dev/null 2>&1
    fi
    
    log ""
    log "📊 配置统计（禁用后）:"
    log "  总配置行数: $(wc -l < .config)"
    log "  启用软件包: $(grep -c "^CONFIG_PACKAGE_.*=y$" .config)"
    log "  模块化软件包: $(grep -c "^CONFIG_PACKAGE_.*=m$" .config)"
    
    log "✅ 步骤15 完成"
}
#【build_firmware_main.sh-33-end】

#【build_firmware_main.sh-34】
# ============================================
# 步骤16: 验证USB配置
# 对应 firmware-build.yml 步骤16
# ============================================
workflow_step16_verify_usb() {
    log "=== 步骤16: 验证USB配置（智能检测版） ==="
    
    trap 'echo "⚠️ 步骤16 验证过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    # 调用 verify_usb_config 函数
    verify_usb_config
    
    log "✅ 步骤16 完成"
}
#【build_firmware_main.sh-34-end】

#【build_firmware_main.sh-35】
# ============================================
# 步骤17: USB驱动完整性检查
# 对应 firmware-build.yml 步骤17
# ============================================
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
    fi
    
    echo ""
    echo "🔍 检查所有实际启用的USB驱动:"
    echo "----------------------------------------"
    
    # 获取所有启用的USB驱动
    local all_enabled=$(grep "^CONFIG_PACKAGE_kmod-usb.*=y" .config | sed 's/CONFIG_PACKAGE_//g' | cut -d'=' -f1 | sort)
    
    if [ -n "$all_enabled" ]; then
        echo "✅ 已启用驱动 ($(echo "$all_enabled" | wc -l) 个):"
        echo "$all_enabled" | head -10 | while read driver; do
            echo "   ✅ $driver"
        done
        if [ $(echo "$all_enabled" | wc -l) -gt 10 ]; then
            echo "   ... 还有 $(( $(echo "$all_enabled" | wc -l) - 10 )) 个未显示"
        fi
    fi
    
    echo "----------------------------------------"
    log "✅ 步骤17 完成"
}
#【build_firmware_main.sh-35-end】

#【build_firmware_main.sh-36】
# ============================================
# 步骤20: 修复网络环境
# 对应 firmware-build.yml 步骤20
# ============================================
workflow_step20_fix_network() {
    log "=== 步骤20: 修复网络环境（动态检测版） ==="
    
    trap 'echo "⚠️ 步骤20 修复过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    fix_network
    
    log "✅ 步骤20 完成"
}
#【build_firmware_main.sh-36-end】

#【build_firmware_main.sh-37】
# ============================================
# 步骤21: 下载依赖包
# 对应 firmware-build.yml 步骤21
# ============================================
workflow_step21_download_deps() {
    log "=== 步骤21: 下载依赖包（动态优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤21 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    download_dependencies
    
    log "✅ 步骤21 完成"
}
#【build_firmware_main.sh-37-end】

#【build_firmware_main.sh-38】
# ============================================
# 步骤22: 集成自定义文件
# 对应 firmware-build.yml 步骤22
# ============================================
workflow_step22_integrate_custom_files() {
    log "=== 步骤22: 集成自定义文件（增强版） ==="
    
    trap 'echo "⚠️ 步骤22 集成过程中出现错误，继续执行..."' ERR
    
    integrate_custom_files
    
    log "✅ 步骤22 完成"
}
#【build_firmware_main.sh-38-end】

#【build_firmware_main.sh-39】
# ============================================
# 步骤23: 前置错误检查
# 对应 firmware-build.yml 步骤23
# ============================================
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
        echo "   SOURCE_REPO_TYPE=$SOURCE_REPO_TYPE"
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
    
    echo "1. ✅ 配置文件检查:"
    if [ -f ".config" ]; then
        local config_size=$(ls -lh .config | awk '{print $5}')
        local config_lines=$(wc -l < .config)
        echo "   ✅ .config 文件存在"
        echo "   📊 大小: $config_size, 行数: $config_lines"
        
        local device_for_config=$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
        local expected_config="CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_for_config}=y"
        
        if grep -q "^${expected_config}$" .config; then
            echo "   ✅ 设备配置正确: $expected_config"
        else
            if grep -q "CONFIG_TARGET_.*DEVICE.*${device_for_config}=y" .config; then
                echo "   ✅ 设备配置正确 (模糊匹配)"
            else
                echo "   ❌ 设备配置可能不正确，未找到: $expected_config"
                error_count=$((error_count + 1))
            fi
        fi
    else
        echo "   ❌ .config 文件不存在"
        error_count=$((error_count + 1))
    fi
    echo ""
    
    echo "2. ✅ 源码工具链检查:"
    echo "   ✅ 源码类型: $SOURCE_REPO_TYPE，使用源码自带工具链"
    
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        echo "   ✅ staging_dir目录存在"
        local staging_size=$(du -sh "$BUILD_DIR/staging_dir" 2>/dev/null | awk '{print $1}')
        echo "   📊 大小: $staging_size"
        
        local gcc_file=$(find "$BUILD_DIR/staging_dir" -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" 2>/dev/null | head -1)
        if [ -n "$gcc_file" ]; then
            echo "   ✅ 找到GCC编译器: $(basename "$gcc_file")"
        else
            echo "   ℹ️ 工具链将在编译过程中生成"
        fi
    else
        echo "   ℹ️ staging_dir将在编译过程中生成"
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
#【build_firmware_main.sh-39-end】

#【build_firmware_main.sh-40】
# ============================================
# 步骤25: 编译固件
# 对应 firmware-build.yml 步骤25
# ============================================
workflow_step25_build_firmware() {
    local enable_parallel="$1"
    
    log "=== 步骤25: 编译固件（补丁自动跳过+编译失败检测机制） ==="
    
    set -e
    trap 'echo "❌ 步骤25 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    # ============================================
    # 编译前检查：查看是否有失败的补丁
    # ============================================
    log "🔧 检查可能失败的补丁..."
    
    # 查找所有内核构建目录中是否有.rej文件
    local rej_files=$(find build_dir -name "*.rej" 2>/dev/null)
    if [ -n "$rej_files" ]; then
        log "  ⚠️ 发现补丁失败，将在编译前处理"
        
        # 显示失败的补丁
        echo "$rej_files" | while read rej_file; do
            log "    ❌ 补丁失败: $(basename "$rej_file" .rej).patch"
        done
        
        # 清理所有内核构建目录
        log "  🔧 清理内核构建目录..."
        rm -rf build_dir/linux-*
        rm -rf staging_dir/target-*/.stamp_target_*
        
        log "  ✅ 已清理，将重新编译"
    fi
    
    # ============================================
    # 设置文件描述符限制
    # ============================================
    ulimit -n 65536 2>/dev/null || true
    local current_limit=$(ulimit -n)
    log "  ✅ 当前文件描述符限制: $current_limit"
    
    # ============================================
    # 创建双固件保护脚本
    # ============================================
    log "🔧 创建双固件保护脚本..."
    local protect_dir="$BUILD_DIR/.firmware_protect"
    mkdir -p "$protect_dir"
    
    local protect_script="$protect_dir/protect.sh"
    cat > "$protect_script" << 'EOF'
#!/bin/bash
# 双固件保护脚本 - 实时监控并备份sysupgrade和factory固件
PROTECT_DIR="$1"
BUILD_DIR="$2"
LOG_FILE="$PROTECT_DIR/protect.log"

echo "=== 双固件保护启动于 $(date) ===" > "$LOG_FILE"

# 监控循环
while true; do
    # 1. 监控临时目录中的文件
    TMP_DIRS=$(find "$BUILD_DIR/build_dir" -name "tmp" -type d 2>/dev/null)
    
    for tmp_dir in $TMP_DIRS; do
        # 查找sysupgrade文件
        find "$tmp_dir" -name "*sysupgrade*.bin" 2>/dev/null | while read file; do
            if [ -f "$file" ]; then
                backup="$PROTECT_DIR/$(basename "$file").backup"
                cp -f "$file" "$backup" 2>/dev/null
                echo "$(date): 备份 sysupgrade: $(basename "$file")" >> "$LOG_FILE"
            fi
        done
        
        # 查找factory文件
        find "$tmp_dir" -name "*factory*.img" -o -name "*factory*.bin" 2>/dev/null | while read file; do
            if [ -f "$file" ]; then
                backup="$PROTECT_DIR/$(basename "$file").backup"
                cp -f "$file" "$backup" 2>/dev/null
                echo "$(date): 备份 factory: $(basename "$file")" >> "$LOG_FILE"
            fi
        done
        
        # 查找.itb文件
        find "$tmp_dir" -name "*.itb" 2>/dev/null | while read file; do
            if [ -f "$file" ]; then
                backup="$PROTECT_DIR/$(basename "$file").backup"
                cp -f "$file" "$backup" 2>/dev/null
                echo "$(date): 备份 itb: $(basename "$file")" >> "$LOG_FILE"
            fi
        done
    done
    
    # 2. 每5秒检查一次
    sleep 5
done
EOF
    chmod +x "$protect_script"
    
    # 启动保护脚本
    "$protect_script" "$protect_dir" "$BUILD_DIR" &
    local protect_pid=$!
    log "  ✅ 双固件保护已启动 (PID: $protect_pid)"
    
    # ============================================
    # 创建强制恢复脚本（动态版本，无硬编码）
    # ============================================
    local recover_script="$protect_dir/recover.sh"
    cat > "$recover_script" << 'EOF'
#!/bin/bash
# 强制恢复脚本 - 动态查找并恢复固件
PROTECT_DIR="$1"
BUILD_DIR="$2"

# 动态获取目标平台和子平台
if [ -f "$BUILD_DIR/build_env.sh" ]; then
    source "$BUILD_DIR/build_env.sh"
fi

TARGET="${TARGET:-ipq40xx}"
SUBTARGET="${SUBTARGET:-generic}"
TARGET_DIR="$BUILD_DIR/bin/targets/$TARGET/$SUBTARGET"

mkdir -p "$TARGET_DIR"

echo "=== 强制恢复开始于 $(date) ==="
echo "目标平台: $TARGET/$SUBTARGET"
echo "目标目录: $TARGET_DIR"

# 计数器
RECOVERED=0
SYSUPGRADE_FOUND=0
FACTORY_FOUND=0
ITB_FOUND=0
SYSUPGRADE_FILE=""
FACTORY_FILE=""
ITB_FILE=""

# 1. 从保护目录恢复
echo "📁 检查保护目录: $PROTECT_DIR"
find "$PROTECT_DIR" -name "*.backup" 2>/dev/null | while read backup; do
    filename=$(basename "$backup" .backup)
    
    # 判断文件类型
    if [[ "$filename" == *"sysupgrade"* ]] && [[ "$filename" == *".bin" ]]; then
        if [ ! -f "$TARGET_DIR/$filename" ]; then
            echo "  ✅ 恢复 sysupgrade: $filename"
            cp -f "$backup" "$TARGET_DIR/$filename"
            RECOVERED=$((RECOVERED + 1))
            SYSUPGRADE_FOUND=1
            SYSUPGRADE_FILE="$TARGET_DIR/$filename"
        fi
    elif [[ "$filename" == *"factory"* ]] && [[ "$filename" == *".img" || "$filename" == *".bin" ]]; then
        if [ ! -f "$TARGET_DIR/$filename" ]; then
            echo "  ✅ 恢复 factory: $filename"
            cp -f "$backup" "$TARGET_DIR/$filename"
            RECOVERED=$((RECOVERED + 1))
            FACTORY_FOUND=1
            FACTORY_FILE="$TARGET_DIR/$filename"
        fi
    elif [[ "$filename" == *".itb" ]]; then
        if [ ! -f "$TARGET_DIR/$filename" ]; then
            echo "  ✅ 恢复 itb: $filename"
            cp -f "$backup" "$TARGET_DIR/$filename"
            RECOVERED=$((RECOVERED + 1))
            ITB_FOUND=1
            ITB_FILE="$TARGET_DIR/$filename"
        fi
    fi
done

# 2. 从临时目录搜索
echo "🔍 搜索临时目录..."
TMP_DIRS=$(find "$BUILD_DIR/build_dir" -name "tmp" -type d 2>/dev/null)

for tmp_dir in $TMP_DIRS; do
    # 查找sysupgrade
    if [ $SYSUPGRADE_FOUND -eq 0 ]; then
        find "$tmp_dir" -name "*sysupgrade*.bin" 2>/dev/null | head -1 | while read file; do
            filename=$(basename "$file")
            echo "  ✅ 从临时目录恢复 sysupgrade: $filename"
            cp -f "$file" "$TARGET_DIR/$filename"
            RECOVERED=$((RECOVERED + 1))
            SYSUPGRADE_FOUND=1
            SYSUPGRADE_FILE="$TARGET_DIR/$filename"
        done
    fi
    
    # 查找factory
    if [ $FACTORY_FOUND -eq 0 ]; then
        find "$tmp_dir" -name "*factory*.img" -o -name "*factory*.bin" 2>/dev/null | head -1 | while read file; do
            filename=$(basename "$file")
            echo "  ✅ 从临时目录恢复 factory: $filename"
            cp -f "$file" "$TARGET_DIR/$filename"
            RECOVERED=$((RECOVERED + 1))
            FACTORY_FOUND=1
            FACTORY_FILE="$TARGET_DIR/$filename"
        done
    fi
    
    # 查找itb
    if [ $ITB_FOUND -eq 0 ]; then
        find "$tmp_dir" -name "*.itb" 2>/dev/null | head -1 | while read file; do
            filename=$(basename "$file")
            echo "  ✅ 从临时目录恢复 itb: $filename"
            cp -f "$file" "$TARGET_DIR/$filename"
            RECOVERED=$((RECOVERED + 1))
            ITB_FOUND=1
            ITB_FILE="$TARGET_DIR/$filename"
        done
    fi
done

# 3. 创建sha256sum
if [ -n "$SYSUPGRADE_FILE" ] && [ -f "$SYSUPGRADE_FILE" ]; then
    (cd "$TARGET_DIR" && sha256sum "$(basename "$SYSUPGRADE_FILE")" > "$(basename "$SYSUPGRADE_FILE").sha256sum")
    echo "  ✅ 创建 sha256sum"
fi

# 4. 最终检查
echo ""
echo "📊 最终检查:"
if [ -f "$SYSUPGRADE_FILE" ]; then
    size=$(ls -lh "$SYSUPGRADE_FILE" 2>/dev/null | awk '{print $5}')
    echo "  ✅ sysupgrade.bin: 存在 ($size)"
else
    echo "  ❌ sysupgrade.bin: 不存在"
fi

if [ -f "$FACTORY_FILE" ]; then
    size=$(ls -lh "$FACTORY_FILE" 2>/dev/null | awk '{print $5}')
    echo "  ✅ factory.img: 存在 ($size)"
else
    echo "  ❌ factory.img: 不存在"
fi

if [ -f "$ITB_FILE" ]; then
    size=$(ls -lh "$ITB_FILE" 2>/dev/null | awk '{print $5}')
    echo "  ✅ itb镜像: 存在 ($size)"
fi

echo "  📊 恢复文件数: $RECOVERED"
echo "=== 强制恢复结束于 $(date) ==="
EOF
    chmod +x "$recover_script"
    
    # ============================================
    # 备份关键文件
    # ============================================
    log "🔧 创建固件备份目录..."
    local backup_dir="$BUILD_DIR/firmware_backup_$(date +%s)"
    mkdir -p "$backup_dir"
    log "  ✅ 备份目录: $backup_dir"
    
    # ============================================
    # 导出环境变量
    # ============================================
    export OPENWRT_VERBOSE=1
    export FORCE_UNSAFE_CONFIGURE=1
    
    # ============================================
    # 智能判断最佳并行任务数
    # ============================================
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    
    echo ""
    echo "🔧 系统信息:"
    echo "  CPU核心数: $CPU_CORES"
    echo "  内存大小: ${TOTAL_MEM}MB"
    echo "  文件描述符限制: $(ulimit -n)"
    echo "  并行优化: $enable_parallel"
    echo "  源码类型: $SOURCE_REPO_TYPE"
    
    if [ "$enable_parallel" = "true" ] && [ $CPU_CORES -ge 2 ]; then
        echo ""
        echo "🧠 智能判断最佳并行任务数..."
        
        if [ $CPU_CORES -ge 4 ] && [ $TOTAL_MEM -ge 4096 ]; then
            MAKE_JOBS=4
            echo "✅ 高性能系统: 使用 $MAKE_JOBS 个并行任务"
        elif [ $CPU_CORES -ge 2 ] && [ $TOTAL_MEM -ge 2048 ]; then
            MAKE_JOBS=2
            echo "✅ 标准系统: 使用 $MAKE_JOBS 个并行任务"
        else
            MAKE_JOBS=1
            echo "⚠️ 低性能系统: 使用 $MAKE_JOBS 个并行任务"
        fi
        
        # ============================================
        # 第一阶段：并行编译
        # ============================================
        echo ""
        echo "🚀 第一阶段：并行编译内核和模块 (make -j$MAKE_JOBS)"
        echo "   开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
        echo ""
        
        START_TIME=$(date +%s)
        
        # 编译第一阶段 - 捕获退出码
        set +e  # 临时关闭errexit，以便捕获退出码
        make -j$MAKE_JOBS V=s 2>&1 | tee build_phase1.log
        PHASE1_EXIT_CODE=${PIPESTATUS[0]}
        set -e  # 重新开启errexit
        
        PHASE1_END=$(date +%s)
        PHASE1_DURATION=$((PHASE1_END - START_TIME))
        
        echo ""
        echo "✅ 第一阶段完成，耗时: $((PHASE1_DURATION / 60))分$((PHASE1_DURATION % 60))秒"
        echo "   退出代码: $PHASE1_EXIT_CODE"
        
        # ============================================
        # 检查第一阶段是否失败
        # ============================================
        if [ $PHASE1_EXIT_CODE -ne 0 ]; then
            echo ""
            echo "❌❌❌ 第一阶段编译失败 (退出码: $PHASE1_EXIT_CODE) ❌❌❌"
            echo ""
            echo "🔍 最后50行错误日志:"
            tail -50 build_phase1.log | grep -E "error|Error|ERROR|failed|Failed|FAILED" -A 5 -B 5 || cat build_phase1.log | tail -50
            
            # 停止保护脚本
            kill $protect_pid 2>/dev/null || true
            
            # 执行强制恢复，看看有没有部分生成的固件
            echo ""
            echo "🔧 尝试恢复可能的部分固件..."
            bash "$recover_script" "$protect_dir" "$BUILD_DIR"
            
            # 清理
            rm -rf "$protect_dir" 2>/dev/null || true
            
            log "❌ 编译失败，退出"
            exit $PHASE1_EXIT_CODE
        fi
        
        # ============================================
        # 第二阶段前：备份所有临时固件文件
        # ============================================
        echo ""
        echo "🔧 第二阶段前：备份所有临时固件文件..."
        
        # 查找并备份所有可能的固件文件
        local temp_files=$(find "$BUILD_DIR/build_dir" -path "*/tmp/*.bin" -o -path "*/tmp/*.img" -o -path "*/tmp/*.itb" -o -name "*.new" 2>/dev/null)
        local backup_count=0
        
        if [ -n "$temp_files" ]; then
            echo "$temp_files" | while read file; do
                if [ -f "$file" ]; then
                    cp -v "$file" "$backup_dir/" 2>/dev/null
                    backup_count=$((backup_count + 1))
                fi
            done
            echo "  ✅ 已备份 $backup_count 个临时固件文件到: $backup_dir"
        else
            echo "  ⚠️ 未找到临时固件文件"
        fi
        
        # ============================================
        # 第二阶段：单线程生成最终固件
        # ============================================
        echo ""
        echo "🚀 第二阶段：单线程生成最终固件 (make -j1)"
        echo "   开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
        echo ""
        
        PHASE2_START=$(date +%s)
        
        # 第二阶段强制单线程 - 捕获退出码
        set +e
        make -j1 V=s 2>&1 | tee -a build_phase2.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
        set -e
        
        PHASE2_END=$(date +%s)
        PHASE2_DURATION=$((PHASE2_END - PHASE2_START))
        TOTAL_DURATION=$((PHASE2_END - START_TIME))
        
        echo ""
        echo "✅ 第二阶段完成，耗时: $((PHASE2_DURATION / 60))分$((PHASE2_DURATION % 60))秒"
        echo "📊 总编译时间: $((TOTAL_DURATION / 60))分$((TOTAL_DURATION % 60))秒"
        
        # 合并日志
        cat build_phase1.log build_phase2.log > build.log
        
    else
        # 单线程编译
        MAKE_JOBS=1
        echo ""
        echo "⚠️ 禁用并行优化，使用单线程编译"
        echo "   开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
        echo ""
        
        START_TIME=$(date +%s)
        
        # 单线程编译 - 捕获退出码
        set +e
        make -j1 V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
        set -e
        
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        
        echo ""
        echo "📊 编译完成，耗时: $((DURATION / 60))分$((DURATION % 60))秒"
        echo "   退出代码: $BUILD_EXIT_CODE"
    fi
    
    # ============================================
    # 停止保护脚本
    # ============================================
    kill $protect_pid 2>/dev/null || true
    log "🔧 双固件保护已停止"
    
    # ============================================
    # 检查编译结果
    # ============================================
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
        echo ""
        echo "❌ 编译失败，退出代码: $BUILD_EXIT_CODE"
        echo ""
        echo "🔍 最后50行错误日志:"
        tail -50 build.log | grep -E "error|Error|ERROR|failed|Failed|FAILED" -A 5 -B 5 || tail -50 build.log
    fi
    
    # 执行强制恢复
    echo ""
    echo "🔧 执行强制恢复，查找固件..."
    bash "$recover_script" "$protect_dir" "$BUILD_DIR"
    
    # ============================================
    # 最终检查
    # ============================================
    local target_dir="$BUILD_DIR/bin/targets/$TARGET/$SUBTARGET"
    local sysupgrade_files=$(find "$target_dir" -name "*sysupgrade*.bin" 2>/dev/null | wc -l)
    local factory_files=$(find "$target_dir" -name "*factory*.img" -o -name "*factory*.bin" 2>/dev/null | wc -l)
    local itb_files=$(find "$target_dir" -name "*.itb" 2>/dev/null | wc -l)
    
    echo ""
    echo "📊 最终固件状态:"
    echo "----------------------------------------"
    
    if [ $sysupgrade_files -gt 0 ]; then
        find "$target_dir" -name "*sysupgrade*.bin" 2>/dev/null | head -1 | while read file; do
            local size=$(ls -lh "$file" | awk '{print $5}')
            echo "  ✅ sysupgrade.bin: 存在 ($size) - $(basename "$file")"
        done
    else
        echo "  ❌ sysupgrade.bin: 不存在"
    fi
    
    if [ $factory_files -gt 0 ]; then
        find "$target_dir" -name "*factory*.img" -o -name "*factory*.bin" 2>/dev/null | head -1 | while read file; do
            local size=$(ls -lh "$file" | awk '{print $5}')
            echo "  ✅ factory.img: 存在 ($size) - $(basename "$file")"
        done
    else
        echo "  ❌ factory.img: 不存在"
    fi
    
    if [ $itb_files -gt 0 ]; then
        find "$target_dir" -name "*.itb" 2>/dev/null | head -1 | while read file; do
            local size=$(ls -lh "$file" | awk '{print $5}')
            echo "  🔷 FIT镜像: 存在 ($size) - $(basename "$file") [可用于恢复]"
        done
    fi
    
    echo "----------------------------------------"
    
    # 根据编译结果给出总结
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        if [ $sysupgrade_files -gt 0 ] && [ $factory_files -gt 0 ]; then
            echo "🎉 编译成功！双固件都已生成"
        elif [ $sysupgrade_files -gt 0 ]; then
            echo "⚠️ 编译完成，但只有sysupgrade固件"
        elif [ $factory_files -gt 0 ]; then
            echo "⚠️ 编译完成，但只有factory固件"
        else
            echo "❌ 编译完成但没有找到任何固件"
        fi
    else
        echo "❌ 编译失败，退出码: $BUILD_EXIT_CODE"
        if [ $sysupgrade_files -gt 0 ] || [ $factory_files -gt 0 ] || [ $itb_files -gt 0 ]; then
            echo "   ⚠️ 但有部分固件生成，可能可用"
        fi
    fi
    
    # 清理
    rm -rf "$protect_dir" 2>/dev/null || true
    
    log "✅ 步骤25 完成"
    
    # 如果编译失败，退出
    if [ $BUILD_EXIT_CODE -ne 0 ]; then
        exit $BUILD_EXIT_CODE
    fi
}
#【build_firmware_main.sh-40-end】

#【build_firmware_main.sh-41】
# ============================================
# 步骤26: 检查构建产物
# 对应 firmware-build.yml 步骤26
# ============================================
workflow_step26_check_artifacts() {
    log "=== 步骤26: 检查构建产物（完整显示） ==="
    
    set -e
    trap 'echo "❌ 步骤26 失败，退出代码: $?"; exit 1' ERR
    
    cd "$BUILD_DIR"
    
    if [ -d "bin/targets" ]; then
        echo "✅ 找到固件目录"
        
        # 查找所有固件文件
        echo ""
        echo "📁 固件文件列表:"
        echo "=========================================="
        
        local sysupgrade_count=0
        local initramfs_count=0
        local factory_count=0
        local itb_count=0
        local other_count=0
        
        # 先收集所有文件，避免管道中的子shell问题
        local all_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" -o -name "*.itb" -o -name "*.tar" -o -name "*.gz" \) 2>/dev/null | grep -v "sha256sums" | sort)
        
        # 遍历所有文件
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            
            SIZE=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
            FILE_NAME=$(basename "$file")
            FILE_PATH=$(echo "$file" | sed 's|^bin/targets/||')
            
            # 判断文件类型并添加注释
            if echo "$FILE_NAME" | grep -q "sysupgrade"; then
                echo "  ✅ $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🚀 刷机用 - 通过路由器 Web 界面或 sysupgrade 命令刷入"
                echo "    注释: *sysupgrade.bin - 刷机用"
                echo ""
                sysupgrade_count=$((sysupgrade_count + 1))
            elif echo "$FILE_NAME" | grep -q "factory"; then
                echo "  🏭 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 📦 原厂刷机 - 用于从原厂固件第一次刷入 OpenWrt"
                echo "    注释: *factory.img/*factory.bin - 原厂刷机用"
                echo ""
                factory_count=$((factory_count + 1))
            elif echo "$FILE_NAME" | grep -q "initramfs"; then
                if echo "$FILE_NAME" | grep -q "\.itb$"; then
                    echo "  🔷 $FILE_NAME (FIT格式)"
                    echo "    大小: $SIZE"
                    echo "    路径: $FILE_PATH"
                    echo "    用途: 🆘 FIT格式恢复镜像 - 用于支持FIT的引导加载程序"
                    echo "    注释: *initramfs-fit-uImage.itb - 恢复用"
                    itb_count=$((itb_count + 1))
                else
                    echo "  🔷 $FILE_NAME"
                    echo "    大小: $SIZE"
                    echo "    路径: $FILE_PATH"
                    echo "    用途: 🆘 恢复用 - 内存启动镜像，不写入闪存"
                    echo "    注释: *initramfs-kernel.bin - 恢复用"
                    initramfs_count=$((initramfs_count + 1))
                fi
                echo ""
            elif echo "$FILE_NAME" | grep -q "kernel"; then
                echo "  🔶 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🧩 内核镜像 - 仅包含内核，不包含根文件系统"
                echo ""
                other_count=$((other_count + 1))
            elif echo "$FILE_NAME" | grep -q "rootfs"; then
                echo "  📦 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🗄️ 根文件系统 - 仅包含根文件系统，不包含内核"
                echo ""
                other_count=$((other_count + 1))
            elif echo "$FILE_NAME" | grep -q "sha256sums"; then
                # 跳过校验和文件
                continue
            elif echo "$FILE_NAME" | grep -q "Packages\.gz"; then
                # 跳过软件包索引文件
                continue
            else
                echo "  📄 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: ❓ 其他文件"
                echo ""
                other_count=$((other_count + 1))
            fi
        done <<< "$all_files"
        
        echo "=========================================="
        echo ""
        echo "📊 固件统计:"
        echo "----------------------------------------"
        echo "  ✅ sysupgrade.bin: $sysupgrade_count 个 - 🚀 **刷机用**"
        echo "  🔷 initramfs-kernel.bin: $initramfs_count 个 - 🆘 **恢复用**"
        echo "  🔷 FIT恢复镜像: $itb_count 个 - 🆘 **FIT格式恢复用**"
        echo "  🏭 factory镜像: $factory_count 个 - 📦 **原厂刷机用**"
        echo "  📦 其他文件: $other_count 个"
        echo "----------------------------------------"
        echo ""
        
        # 重要提示
        echo "🔔 固件类型说明:"
        echo "  ✅ *sysupgrade.bin      - **刷机用** (已安装OpenWrt时升级)"
        echo "  🔷 *initramfs-*.bin     - **恢复用** (内存启动，用于恢复)"
        echo "  🔷 *initramfs-*.itb     - **FIT格式恢复** (适用于支持FIT的引导程序)"
        echo "  🏭 *factory.img/*.bin   - **原厂刷机用** (从原厂固件第一次刷入)"
        echo ""
        
        # 检测缺少的固件类型
        local missing_types=""
        if [ $sysupgrade_count -eq 0 ]; then
            missing_types="$missing_types sysupgrade"
        fi
        if [ $factory_count -eq 0 ] && [ $initramfs_count -eq 0 ] && [ $itb_count -eq 0 ]; then
            missing_types="$missing_types 恢复镜像"
        fi
        
        if [ -n "$missing_types" ]; then
            echo "⚠️ 警告: 缺少以下固件类型 -$missing_types"
            echo "   编译可能不完整，但可用的固件文件如下:"
        fi
        
        # 显示实际找到的可刷机固件文件
        local flashable_count=0
        echo ""
        echo "📋 可刷机的固件文件:"
        echo "----------------------------------------"
        
        # 显示所有可刷机的固件
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            if [[ "$file" == *"sysupgrade.bin" ]] || [[ "$file" == *"factory.img" ]] || [[ "$file" == *"factory.bin" ]]; then
                local fname=$(basename "$file")
                local fsize=$(ls -lh "$file" | awk '{print $5}')
                local ftype=""
                if [[ "$fname" == *"sysupgrade"* ]]; then
                    ftype="[刷机用]"
                elif [[ "$fname" == *"factory"* ]]; then
                    ftype="[原厂刷机]"
                fi
                printf "  📌 %-60s %s %s\n" "$fname" "$fsize" "$ftype"
                flashable_count=$((flashable_count + 1))
            fi
        done <<< "$all_files" | head -10
        
        if [ $flashable_count -eq 0 ]; then
            echo "  ⚠️ 没有找到可刷机的固件文件"
            
            # 尝试查找initramfs作为替代
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                if [[ "$file" == *"initramfs"* ]]; then
                    local fname=$(basename "$file")
                    local fsize=$(ls -lh "$file" | awk '{print $5}')
                    printf "  🔷 %-60s %s [恢复用]\n" "$fname" "$fsize"
                fi
            done <<< "$all_files" | head -5
        fi
        
        echo "----------------------------------------"
        echo ""
        
        # 提供刷机建议
        if [ $sysupgrade_count -gt 0 ]; then
            echo "📝 刷机建议:"
            echo "   如果您已经安装了OpenWrt，请使用 sysupgrade.bin 文件"
            echo "   命令: sysupgrade -n /path/to/*sysupgrade.bin"
        elif [ $factory_count -gt 0 ]; then
            echo "📝 刷机建议:"
            echo "   如果您是从原厂固件第一次刷入，请使用 factory.img 文件"
            echo "   通过路由器原厂Web界面刷入"
        elif [ $initramfs_count -gt 0 ] || [ $itb_count -gt 0 ]; then
            echo "📝 刷机建议:"
            echo "   没有找到sysupgrade或factory固件，但找到了initramfs恢复镜像"
            echo "   initramfs是内存启动镜像，可用于恢复系统，但不能永久刷入"
            echo "   如需永久刷入，需要先启动initramfs，然后在系统中刷入sysupgrade"
        fi
        
        echo "=========================================="
        echo "✅ 构建产物检查完成"
    else
        echo "❌ 错误: 未找到固件目录"
        exit 1
    fi
    
    log "✅ 步骤26 完成"
}
#【build_firmware_main.sh-41-end】

#【build_firmware_main.sh-42】
# ============================================
# 步骤29: 编译后空间检查
# 对应 firmware-build.yml 步骤29
# ============================================
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
#【build_firmware_main.sh-42-end】

#【build_firmware_main.sh-43】
# ============================================
# 步骤30: 编译总结
# 对应 firmware-build.yml 步骤30
# ============================================
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
        GCC_FILE=$(find "$BUILD_DIR" -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" ! -path "*dummy-tools*" ! -path "*scripts*" 2>/dev/null | head -1)
        
        if [ -n "$GCC_FILE" ] && [ -x "$GCC_FILE" ]; then
            SDK_VERSION=$("$GCC_FILE" --version 2>&1 | head -1)
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
#【build_firmware_main.sh-43-end】

# ============================================================================
# 废弃函数 - 保留注释，代码已删除，放到文件末尾
# ============================================================================

#【build_firmware_main.sh-44】
# 以下函数已废弃，不再使用
# - download_openwrt_sdk (原 #07)
# - verify_sdk_files (原 #07)
# - verify_sdk_directory (原 #22)
# - 公共函数库中的设备定义查找函数 (原 #23)
# - universal_compiler_search (原 #43)
# - search_compiler_files_simple (原 #44)
# - intelligent_platform_aware_compiler_search (原 #45)
#【build_firmware_main.sh-44-end】

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
            echo "⚠️ verify_sdk_directory 已废弃"
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
        "step08_initialize_build_env_hybrid")
            workflow_step08_initialize_build_env_hybrid "$arg1" "$arg2" "$arg3" "$arg4" "$arg5"
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

        "search_compiler_files"|"universal_compiler_search"|"search_compiler_files_simple"|"intelligent_platform_aware_compiler_search")
            echo "⚠️ 编译器搜索命令已废弃，使用步骤09编译工具链"
            ;;

        *)
            log "❌ 未知命令: $command"
            echo "可用命令:"
            echo "  基础函数: setup_environment, create_build_dir, initialize_build_env, etc."
            echo ""
            echo "  工作流步骤命令:"
            echo "    step05_install_basic_tools, step06_initial_space_check, step07_create_build_dir"
            echo "    step08_initialize_build_env, step08_initialize_build_env_hybrid, step09_download_sdk, step10_verify_sdk"
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
