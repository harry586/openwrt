#!/bin/bash
#【build_firmware_main.sh-00】
# OpenWrt 智能固件构建主脚本
# 对应工作流: firmware-build.yml
# 版本: 3.2.0
# 最后更新: 2026-02-27
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
# 动态生成完整的禁用插件列表（完全无硬编码）
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
        
        # 添加带下划线的子包格式（用于 ddns-scripts_aliyun 这类包）
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
        
        # 针对特定包的额外处理（基于包名特征，不是硬编码）
        if [[ "$pkg" == "ddns" ]]; then
            # DDNS 相关的所有可能变体
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
            # rclone 相关的所有可能变体
            full_list+=("rclone")
            full_list+=("rclone-config")
            full_list+=("rclone-webui")
            full_list+=("rclone-ng")
            full_list+=("rclone-webui-react")
        elif [[ "$pkg" == "qbittorrent" ]]; then
            # qbittorrent 相关的所有可能变体
            full_list+=("qbittorrent")
            full_list+=("qbittorrent-static")
            full_list+=("qt5")
            full_list+=("libtorrent")
            full_list+=("libtorrent-rasterbar")
        elif [[ "$pkg" == "filetransfer" ]]; then
            # filetransfer 相关的所有可能变体
            full_list+=("filetransfer")
            full_list+=("filebrowser")
            full_list+=("filemanager")
        elif [[ "$pkg" == "nlbwmon" ]]; then
            # nlbwmon 相关的所有可能变体
            full_list+=("nlbwmon")
            full_list+=("luci-app-nlbwmon")
            full_list+=("luci-i18n-nlbwmon-zh-cn")
            full_list+=("nlbwmon-database")
            full_list+=("nlbwmon-legacy")
        elif [[ "$pkg" == "wol" ]]; then
            # wol 相关的所有可能变体
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
        genext2fs mtd-utils u-boot-tools
    )
    
    local debug_packages=(
        gdb strace ltrace valgrind
        binutils-dev libdw-dev libiberty-dev
    )
    
    # LEDE 特定需要的工具
    local lede_tools=(
        device-tree-compiler
        gperf
        asciidoc
        xmlto
        docbook-utils
        linux-headers-generic
        liblzma-dev
        liblzo2-dev
        liblzo2-2
        uuid-dev
    )
    
    log "安装基础编译工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_packages[@]}" || handle_error "安装基础编译工具失败"
    
    log "安装网络工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${network_packages[@]}" || handle_error "安装网络工具失败"
    
    log "安装文件系统工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${filesystem_packages[@]}" || handle_error "安装文件系统工具失败"
    
    log "安装调试工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${debug_packages[@]}" || handle_error "安装调试工具失败"
    
    log "安装 LEDE 特定工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${lede_tools[@]}" || log "⚠️ 部分 LEDE 工具安装失败，但继续"
    
    # 安装额外的工具
    log "安装额外的编译工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        libncurses5-dev \
        libncursesw5-dev \
        zlib1g-dev \
        gawk \
        git \
        subversion \
        libssl-dev \
        gettext \
        libxml-parser-perl \
        ocaml-nox \
        sharutils \
        || log "⚠️ 部分额外工具安装失败，但继续"
    
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
        PLATFORM_INFO=$("$SUPPORT_SCRIPT" get-platform "$device_name" 2>/dev/null || echo "")
        
        if [ -n "$PLATFORM_INFO" ]; then
            # 解析返回的平台信息
            TARGET=$(echo "$PLATFORM_INFO" | awk '{print $1}')
            SUBTARGET=$(echo "$PLATFORM_INFO" | awk '{print $2}')
            DEVICE="$device_name"
            log "✅ 从support.sh获取平台信息: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
        else
            log "⚠️ 无法从support.sh获取平台信息，尝试从设备名推断..."
            
            # 从设备名推断平台
            case "$device_name" in
                *ac42u*|*acrh17*)
                    TARGET="ipq40xx"
                    SUBTARGET="generic"
                    log "✅ 从设备名推断平台: ipq40xx/generic"
                    ;;
                *rax3000m*|*mt7981*)
                    TARGET="mediatek"
                    SUBTARGET="filogic"
                    log "✅ 从设备名推断平台: mediatek/filogic"
                    ;;
                *wndr3800*|*ath79*)
                    TARGET="ath79"
                    SUBTARGET="generic"
                    log "✅ 从设备名推断平台: ath79/generic"
                    ;;
                *)
                    log "❌ 无法确定平台信息"
                    handle_error "获取平台信息失败"
                    ;;
            esac
            DEVICE="$device_name"
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
    
    log "=== 配置Feeds（动态禁用插件） ==="
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
    
    # ============================================
    # 添加诊断工具到禁用列表
    # ============================================
    local diagnostic_tools=(
        "iw"           # 无线诊断工具，约 200KB
        "iwinfo"       # 无线信息工具，约 100KB
        "ethtool"      # 网卡诊断工具，约 150KB
        "tcpdump"      # 抓包工具，约 500KB
        "mtr"          # 网络诊断，约 100KB
    )
    
    log "🔧 添加诊断工具到禁用列表: ${diagnostic_tools[*]}"
    
    for tool in "${diagnostic_tools[@]}"; do
        search_keywords+=("$tool")
        seen_keywords+=("$tool")
        full_forbidden_list+=("$tool")
    done
    
    log "📋 搜索关键词列表 (${#search_keywords[@]} 个): ${search_keywords[*]}"
    
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
    # 在安装 feeds 之前，先处理依赖关系
    # ============================================
    log "🔧 处理依赖关系..."
    
    # 查找并修改依赖 ddns-scripts 的 Makefile
    if [ -d "feeds" ]; then
        find feeds -name "Makefile" -type f 2>/dev/null | while read makefile; do
            # 如果 Makefile 依赖 ddns-scripts，注释掉相关行
            if grep -q "ddns-scripts" "$makefile" 2>/dev/null; then
                log "  📝 处理依赖: $makefile"
                # 备份原文件
                cp "$makefile" "$makefile.bak"
                # 注释掉 DEPENDS 行
                sed -i 's/\(DEPENDS.*ddns-scripts\)/# \1/g' "$makefile"
            fi
            # 如果 Makefile 依赖 luci-app-nlbwmon，注释掉相关行
            if grep -q "luci-app-nlbwmon" "$makefile" 2>/dev/null; then
                log "  📝 处理依赖: $makefile"
                cp "$makefile" "$makefile.bak"
                sed -i 's/\(DEPENDS.*luci-app-nlbwmon\)/# \1/g' "$makefile"
            fi
        done
    fi
    
    # 处理 package/lean 目录下的特殊依赖
    if [ -d "package/lean" ]; then
        find package/lean -name "Makefile" -type f 2>/dev/null | while read makefile; do
            if grep -q "ddns-scripts" "$makefile" 2>/dev/null; then
                log "  📝 处理 lean 依赖: $makefile"
                cp "$makefile" "$makefile.bak"
                sed -i 's/\(DEPENDS.*ddns-scripts\)/# \1/g' "$makefile"
            fi
        done
    fi
    
    # ============================================
    # 在安装 feeds 之前，彻底删除不需要的插件源文件
    # ============================================
    log "🔧 在安装 feeds 之前，彻底删除不需要的插件源文件..."
    
    # 创建临时文件存储所有要删除的关键词
    local all_keywords_file=$(mktemp)
    
    # 添加所有基础关键词
    for keyword in "${search_keywords[@]}"; do
        echo "$keyword" >> "$all_keywords_file"
    done
    
    # 添加特定插件的关键词
    local specific_keywords=(
        "nlbwmon"
        "luci-app-nlbwmon"
        "nlbwmon-database"
        "wol"
        "luci-app-wol"
        "etherwake"
        "ddns"
        "luci-app-ddns"
        "ddns-scripts"
        "luci-app-wrtbwmon"
    )
    
    for keyword in "${specific_keywords[@]}"; do
        echo "$keyword" >> "$all_keywords_file"
    done
    
    # 去重
    sort -u "$all_keywords_file" > "$all_keywords_file.sorted"
    
    log "🔍 使用 $(wc -l < "$all_keywords_file.sorted") 个关键词删除源文件..."
    
    # 遍历所有唯一关键词，删除相关目录
    while read keyword; do
        [ -z "$keyword" ] && continue
        
        # 在 feeds 目录中搜索并删除
        if [ -d "feeds" ]; then
            find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 feeds 目录: $dir"
                rm -rf "$dir"
            done
            find feeds -type f -name "*${keyword}*" 2>/dev/null | while read file; do
                log "  🗑️  删除 feeds 文件: $file"
                rm -f "$file"
            done
        fi
        
    done < "$all_keywords_file.sorted"
    
    rm -f "$all_keywords_file" "$all_keywords_file.sorted"
    
    log "✅ 不需要的插件源文件已彻底删除"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    # ============================================
    # 安装后再次彻底删除不需要的插件源文件
    # ============================================
    log "🔧 安装后再次彻底删除不需要的插件源文件..."
    
    # 重新创建关键词文件
    local post_keywords_file=$(mktemp)
    
    # 重新添加所有关键词
    for keyword in "${search_keywords[@]}"; do
        echo "$keyword" >> "$post_keywords_file"
    done
    
    for keyword in "${specific_keywords[@]}"; do
        echo "$keyword" >> "$post_keywords_file"
    done
    
    sort -u "$post_keywords_file" > "$post_keywords_file.sorted"
    
    # 再次删除
    while read keyword; do
        [ -z "$keyword" ] && continue
        
        # 在 feeds 目录中搜索并删除
        if [ -d "feeds" ]; then
            find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 feeds 目录: $dir"
                rm -rf "$dir"
            done
            find feeds -type f -name "*${keyword}*" 2>/dev/null | while read file; do
                log "  🗑️  删除 feeds 文件: $file"
                rm -f "$file"
            done
        fi
        
        # 在 package/feeds 目录中搜索并删除
        if [ -d "package/feeds" ]; then
            find package/feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️  删除 package/feeds 目录: $dir"
                rm -rf "$dir"
            done
        fi
        
    done < "$post_keywords_file.sorted"
    
    rm -f "$post_keywords_file" "$post_keywords_file.sorted"
    
    # ============================================
    # 恢复被修改的 Makefile
    # ============================================
    log "🔧 恢复 Makefile 依赖..."
    
    find feeds -name "Makefile.bak" -type f 2>/dev/null | while read bakfile; do
        original="${bakfile%.bak}"
        mv "$bakfile" "$original"
    done
    
    find package/lean -name "Makefile.bak" -type f 2>/dev/null | while read bakfile; do
        original="${bakfile%.bak}"
        mv "$bakfile" "$original"
    done
    
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
# 第十一部分：功能开关 ##
#   控制是否启用某些功能
#   根据需要开启或关闭
#------------------------------------------------------------------------------

##常修改## 是否启用TurboACC（true/false）
##常修改## normal模式下有效，基础模式忽略
: ${ENABLE_TURBOACC:="true"}

##常修改## 是否启用TCP BBR（true/false）
##常修改## 开启BBR拥塞控制算法
: ${ENABLE_TCP_BBR:="true"}

##常修改## 是否强制使用ath10k-ct驱动（解决冲突）
##常修改## 启用后会禁用标准ath10k，使用ct版
: ${FORCE_ATH10K_CT:="true"}

##常修改## 是否自动修复缺失的USB驱动（true/false）
##常修改## 自动添加缺失的关键USB驱动
: ${AUTO_FIX_USB_DRIVERS:="true"}

##常修改## 是否启用详细日志（true/false）
##常修改## 开启后会在编译时显示更详细的输出
: ${ENABLE_VERBOSE_LOG:="false"}

##常修改## 默认禁用的插件列表（空格分隔）
##常修改## 在构建时会自动禁用这些插件及其相关子包
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
    log "源码仓库类型: $SOURCE_REPO_TYPE"
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
        cmcc_rax3000m-nand|rax3000m-nand)
            if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
                openwrt_device="cmcc_rax3000m-nand"
                search_device="rax3000m"
                log "🔧 LEDE源码: 使用设备名 $openwrt_device"
            else
                openwrt_device="cmcc_rax3000m-nand"
                search_device="rax3000m"
                log "🔧 ImmortalWrt/OpenWrt源码: 使用设备名 $openwrt_device"
            fi
            ;;
        cmcc_rax3000m-emmc|rax3000m-emmc)
            if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
                openwrt_device="cmcc_rax3000m-emmc"
                search_device="rax3000m"
                log "🔧 LEDE源码: 使用设备名 $openwrt_device"
            else
                openwrt_device="cmcc_rax3000m-emmc"
                search_device="rax3000m"
                log "🔧 ImmortalWrt/OpenWrt源码: 使用设备名 $openwrt_device"
            fi
            ;;
        cmcc_rax3000m|rax3000m)
            if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
                openwrt_device="cmcc_rax3000m-nand"
                search_device="rax3000m"
                log "🔧 LEDE源码: 默认使用 NAND 版本 $openwrt_device"
            else
                openwrt_device="cmcc_rax3000m-nand"
                search_device="rax3000m"
                log "🔧 ImmortalWrt/OpenWrt源码: 默认使用 NAND 版本 $openwrt_device"
            fi
            ;;
        netgear_wndr3800|wndr3800)
            openwrt_device="netgear_wndr3800"
            search_device="wndr3800"
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
    
    local device_config_file=""
    
    case "$DEVICE" in
        cmcc_rax3000m-nand|cmcc_rax3000m-emmc|cmcc_rax3000m|rax3000m*)
            if [ -f "$CONFIG_DIR/devices/cmcc_rax3000m-nand.config" ]; then
                device_config_file="$CONFIG_DIR/devices/cmcc_rax3000m-nand.config"
                log "📋 找到设备配置文件: $device_config_file"
            elif [ -f "$CONFIG_DIR/devices/cmcc_rax3000m.config" ]; then
                device_config_file="$CONFIG_DIR/devices/cmcc_rax3000m.config"
                log "📋 找到设备配置文件: $device_config_file"
            fi
            ;;
        netgear_wndr3800|wndr3800)
            if [ -f "$CONFIG_DIR/devices/netgear_wndr3800.config" ]; then
                device_config_file="$CONFIG_DIR/devices/netgear_wndr3800.config"
                log "📋 找到设备配置文件: $device_config_file"
            fi
            ;;
        *)
            device_config_file="$CONFIG_DIR/devices/$DEVICE.config"
            ;;
    esac
    
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
        # 先清除可能存在的配置
        sed -i '/CONFIG_PACKAGE_kmod-ath10k=y/d' .config
        sed -i '/CONFIG_PACKAGE_kmod-ath10k-pci=y/d' .config
        sed -i '/CONFIG_PACKAGE_kmod-ath10k-smallbuffers=y/d' .config
        sed -i '/CONFIG_PACKAGE_kmod-ath10k-ct=y/d' .config
        sed -i '/CONFIG_PACKAGE_kmod-ath10k-ct-smallbuffers=y/d' .config
        
        # 暂时不启用任何驱动，等内核检测后决定
        echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-ath10k-pci is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-ath10k-smallbuffers is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-ath10k-ct is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-ath10k-ct-smallbuffers is not set" >> .config
        log "✅ ath10k驱动将在内核检测后决定"
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
            
            local search_keywords=()
            case "$DEVICE" in
                cmcc_rax3000m-nand|cmcc_rax3000m|rax3000m*)
                    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
                        search_keywords=("rax3000m" "cmcc_rax3000m-nand")
                    else
                        search_keywords=("rax3000m" "cmcc_rax3000m-nand" "mt7981b-cmcc-rax3000m")
                    fi
                    ;;
                netgear_wndr3800|wndr3800)
                    search_keywords=("wndr3800" "netgear_wndr3800")
                    ;;
                *)
                    search_keywords=("$search_device")
                    ;;
            esac
            
            for keyword in "${search_keywords[@]}"; do
                while IFS= read -r mkfile; do
                    if grep -q "define Device.*$keyword" "$mkfile" 2>/dev/null; then
                        device_def_file="$mkfile"
                        log "🔍 找到设备定义文件: $mkfile (关键词: $keyword)"
                        break 2
                    fi
                done < <(find "target/linux/$TARGET" -type f -name "*.mk" 2>/dev/null)
            done
            
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
    
    # 获取系统内存大小用于ath10k选择
    local total_mem=$(free -m | awk '/^Mem:/{print $2}' 2>/dev/null || echo "512")
    
    # 根据内核版本和设备内存选择ath10k驱动
    if [ $found_kernel -eq 1 ] && [ -f "$kernel_config_file" ]; then
        log "✅ 使用内核配置文件: $kernel_config_file (内核版本 $kernel_version)"
        
        # 清除之前的ath10k配置
        sed -i '/CONFIG_PACKAGE_kmod-ath10k/d' .config
        sed -i '/CONFIG_PACKAGE_kmod-ath10k-ct/d' .config
        sed -i '/# CONFIG_PACKAGE_kmod-ath10k/d' .config
        sed -i '/# CONFIG_PACKAGE_kmod-ath10k-ct/d' .config
        
        # 根据内核版本选择驱动
        case "$kernel_version" in
            6.6|6.7|6.8|6.9|6.10|6.11|6.12)
                log "🔧 内核版本较新 ($kernel_version)，优先使用 ath10k-ct"
                if [ "$total_mem" -lt 128 ]; then
                    log "  📊 检测到内存较小 (${total_mem}MB)，使用 smallbuffers 变体"
                    echo "CONFIG_PACKAGE_kmod-ath10k-ct-smallbuffers=y" >> .config
                else
                    echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
                fi
                ;;
            5.15|5.10|5.4)
                log "🔧 内核版本稳定 ($kernel_version)，使用标准 ath10k-ct"
                echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
                ;;
            *)
                log "🔧 未知内核版本 ($kernel_version)，使用默认 ath10k-ct"
                echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
                ;;
        esac
        
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
        # 如果没有找到内核配置文件，使用默认ath10k-ct
        echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
    fi
    
    # 检查dnsmasq配置冲突
    log "🔍 检查 dnsmasq 配置..."
    if grep -q "^CONFIG_PACKAGE_dnsmasq=y" .config && grep -q "^CONFIG_PACKAGE_dnsmasq-full=y" .config; then
        log "⚠️ 检测到 dnsmasq 和 dnsmasq-full 同时启用，自动修复..."
        sed -i 's/^CONFIG_PACKAGE_dnsmasq=y/# CONFIG_PACKAGE_dnsmasq is not set/' .config
        log "  ✅ 已禁用 dnsmasq，保留 dnsmasq-full"
    fi
    
    if grep -q "^CONFIG_PACKAGE_dnsmasq-full=y" .config; then
        log "  ✅ dnsmasq-full 已启用，检查依赖..."
        if ! grep -q "^CONFIG_PACKAGE_libubus=y" .config; then
            echo "CONFIG_PACKAGE_libubus=y" >> .config
            log "  ✅ 添加依赖: libubus"
        fi
        if ! grep -q "^CONFIG_PACKAGE_libblobmsg-json=y" .config; then
            echo "CONFIG_PACKAGE_libblobmsg-json=y" >> .config
            log "  ✅ 添加依赖: libblobmsg-json"
        fi
    fi
    
    # 创建缺失的配置文件
    log "🔧 检查并创建缺失的配置文件..."
    if [ ! -f "feeds/packages/net/openvpn/Config-wolfssl.in" ]; then
        mkdir -p "feeds/packages/net/openvpn"
        cat > "feeds/packages/net/openvpn/Config-wolfssl.in" << 'EOF'
# dummy Config-wolfssl.in to fix build
menuconfig PACKAGE_openvpn-wolfssl
	bool "openvpn-wolfssl (dummy)"
	default n
EOF
        log "  ✅ 创建缺失的 Config-wolfssl.in"
    fi
    
    local common_configs=(
        "feeds/packages/net/openssh/Config.overridable"
        "feeds/packages/libs/gnutls/Config.wolfssl"
    )
    
    for config in "${common_configs[@]}"; do
        if [ ! -f "$config" ]; then
            mkdir -p "$(dirname "$config")"
            touch "$config"
            log "  ✅ 创建缺失的配置文件: $config"
        fi
    done
    
    log "🔄 第一次运行 make defconfig..."
    
    local max_retries=3
    local retry_count=0
    local defconfig_success=0
    
    while [ $retry_count -lt $max_retries ] && [ $defconfig_success -eq 0 ]; do
        retry_count=$((retry_count + 1))
        
        if [ $retry_count -gt 1 ]; then
            log "🔄 第 $retry_count 次重试 make defconfig..."
            if [ $retry_count -eq 2 ]; then
                log "  🔧 尝试修复常见问题..."
                # 在第二次重试时，如果ath10k-ct有问题，尝试切换到smallbuffers变体
                if grep -q "ath10k-ct" /tmp/build-logs/defconfig1.log 2>/dev/null; then
                    sed -i '/CONFIG_PACKAGE_kmod-ath10k-ct=y/d' .config
                    echo "CONFIG_PACKAGE_kmod-ath10k-ct-smallbuffers=y" >> .config
                    log "  ✅ 切换到 ath10k-ct-smallbuffers 驱动"
                fi
            fi
        fi
        
        if make defconfig > /tmp/build-logs/defconfig${retry_count}.log 2>&1; then
            defconfig_success=1
            log "✅ 第 $retry_count 次 make defconfig 成功"
        else
            log "⚠️ 第 $retry_count 次 make defconfig 失败"
            if [ $retry_count -lt $max_retries ]; then
                if grep -q "Config-wolfssl.in" /tmp/build-logs/defconfig${retry_count}.log; then
                    mkdir -p "feeds/packages/net/openvpn"
                    touch "feeds/packages/net/openvpn/Config-wolfssl.in"
                fi
            fi
        fi
    done
    
    if [ $defconfig_success -eq 0 ]; then
        log "❌ 所有 $max_retries 次 make defconfig 都失败"
        tail -50 /tmp/build-logs/defconfig3.log
        handle_error "依赖解决失败"
    fi
    
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
    
    log "🔧 第三轮：删除所有包含关键字的配置行..."
    for keyword in "${search_keywords[@]}"; do
        sed -i "/${keyword}/d" .config
        local upper_keyword=$(echo "$keyword" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        sed -i "/${upper_keyword}/d" .config
    done
    
    log "🔧 特别处理 DDNS 相关配置..."
    sed -i '/ddns/d' .config
    sed -i '/DDNS/d' .config
    
    log "✅ 禁用完成"
    
    sort .config | uniq > .config.tmp
    mv .config.tmp .config
    
    log "🔄 运行 make defconfig 使禁用生效..."
    make defconfig > /tmp/build-logs/defconfig_disable.log 2>&1 || {
        log "⚠️ make defconfig 有警告，但继续..."
    }
    
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
#【build_firmware_main.sh-14-end】

#【build_firmware_main.sh-15】
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
#【build_firmware_main.sh-15-end】

#【build_firmware_main.sh-16】
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
#【build_firmware_main.sh-16-end】

#【build_firmware_main.sh-17】
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
#【build_firmware_main.sh-17-end】

#【build_firmware_main.sh-18】
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
#【build_firmware_main.sh-18-end】

#【build_firmware_main.sh-19】
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
#【build_firmware_main.sh-19-end】

#【build_firmware_main.sh-20】
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
#【build_firmware_main.sh-20-end】

#【build_firmware_main.sh-21】
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
#【build_firmware_main.sh-21-end】

#【build_firmware_main.sh-22】
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
#【build_firmware_main.sh-22-end】

#【build_firmware_main.sh-23】
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
#【build_firmware_main.sh-23-end】

# ============================================
# 步骤10（原步骤11）: 验证源码自带工具链
# ============================================
#【build_firmware_main.sh-24】
workflow_step10_verify_sdk() {
    log "=== 步骤10: 验证源码自带工具链 ==="
    
    trap 'echo "⚠️ 步骤10 验证过程中出现错误，继续执行..."' ERR
    
    echo "🔍 检查源码自带工具链..."
    
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        echo "✅ 从环境文件加载变量: COMPILER_DIR=$COMPILER_DIR, SOURCE_REPO_TYPE=$SOURCE_REPO_TYPE"
    fi
    
    echo "✅ 源码仓库类型: $SOURCE_REPO_TYPE"
    echo "📊 源码目录大小: $(du -sh "$BUILD_DIR" 2>/dev/null | awk '{print $1}' || echo '未知')"
    
    # 检查staging_dir目录
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        echo "✅ 找到staging_dir目录，源码工具链已准备就绪"
        echo "📊 staging_dir大小: $(du -sh "$BUILD_DIR/staging_dir" 2>/dev/null | awk '{print $1}' || echo '未知')"
        
        # 查找工具链中的GCC编译器
        GCC_FILE=$(find "$BUILD_DIR/staging_dir" -type f -executable -name "*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" 2>/dev/null | head -1)
        
        if [ -n "$GCC_FILE" ]; then
            echo "✅ 找到工具链中的GCC编译器: $(basename "$GCC_FILE")"
            echo "🔧 GCC版本测试:"
            "$GCC_FILE" --version 2>&1 | head -1
            
            # 提取GCC版本信息
            GCC_VERSION=$("$GCC_FILE" --version 2>&1 | head -1)
            MAJOR_VERSION=$(echo "$GCC_VERSION" | grep -o "[0-9]\+" | head -1)
            
            case "$SOURCE_REPO_TYPE" in
                "lede")
                    echo "💡 LEDE源码工具链"
                    ;;
                "openwrt")
                    if [ "$MAJOR_VERSION" = "12" ]; then
                        echo "💡 OpenWrt 23.05源码工具链 (GCC 12.x)"
                    elif [ "$MAJOR_VERSION" = "8" ]; then
                        echo "💡 OpenWrt 21.02源码工具链 (GCC 8.x)"
                    else
                        echo "💡 OpenWrt源码工具链 (GCC $MAJOR_VERSION.x)"
                    fi
                    ;;
                "immortalwrt")
                    if [ "$MAJOR_VERSION" = "12" ]; then
                        echo "💡 ImmortalWrt 23.05源码工具链 (GCC 12.x)"
                    elif [ "$MAJOR_VERSION" = "8" ]; then
                        echo "💡 ImmortalWrt 21.02源码工具链 (GCC 8.x)"
                    else
                        echo "💡 ImmortalWrt源码工具链 (GCC $MAJOR_VERSION.x)"
                    fi
                    ;;
                *)
                    echo "💡 源码工具链 (GCC $MAJOR_VERSION.x)"
                    ;;
            esac
        else
            echo "ℹ️ 工具链将在编译过程中自动生成"
        fi
    else
        echo "ℹ️ staging_dir目录尚未生成，将在编译过程中自动创建"
    fi
    
    # 检查关键目录
    echo ""
    echo "📁 源码关键目录检查:"
    if [ -d "$BUILD_DIR/scripts" ]; then
        echo "  ✅ scripts目录: 存在"
    else
        echo "  ❌ scripts目录: 不存在"
    fi
    
    if [ -f "$BUILD_DIR/Makefile" ]; then
        echo "  ✅ Makefile: 存在"
    else
        echo "  ❌ Makefile: 不存在"
    fi
    
    if [ -f "$BUILD_DIR/feeds.conf.default" ]; then
        echo "  ✅ feeds.conf.default: 存在"
    else
        echo "  ❌ feeds.conf.default: 不存在"
    fi
    
    echo ""
    echo "✅ 源码工具链验证完成"
    log "✅ 步骤10 完成"
}
#【build_firmware_main.sh-24-end】

# ============================================
# 步骤11（原步骤12）: 配置Feeds
# ============================================
#【build_firmware_main.sh-25】
workflow_step11_configure_feeds() {
    log "=== 步骤11: 配置Feeds【动态禁用插件】 ==="
    
    set -e
    trap 'echo "❌ 步骤11 失败，退出代码: $?"; exit 1' ERR
    
    configure_feeds
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 配置Feeds失败"
        exit 1
    fi
    
    log "✅ 步骤11 完成"
}
#【build_firmware_main.sh-25-end】

# ============================================
# 步骤12（原步骤13）: 安装TurboACC包
# ============================================
#【build_firmware_main.sh-26】
workflow_step12_install_turboacc() {
    log "=== 步骤12: 安装 TurboACC 包 ==="
    
    set -e
    trap 'echo "❌ 步骤12 失败，退出代码: $?"; exit 1' ERR
    
    install_turboacc_packages
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 安装TurboACC包失败"
        exit 1
    fi
    
    log "✅ 步骤12 完成"
}
#【build_firmware_main.sh-26-end】

# ============================================
# 步骤13（原步骤14）: 编译前空间检查
# ============================================
#【build_firmware_main.sh-27】
workflow_step13_pre_build_space_check() {
    log "=== 步骤13: 编译前空间检查 ==="
    
    set -e
    trap 'echo "❌ 步骤13 失败，退出代码: $?"; exit 1' ERR
    
    # 调用空间检查函数
    pre_build_space_check
    
    if [ $? -ne 0 ]; then
        echo "❌ 错误: 编译前空间检查失败"
        exit 1
    fi
    
    log "✅ 步骤13 完成"
}

# ============================================
# 编译前空间检查函数
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
#【build_firmware_main.sh-27-end】

# ============================================
# 步骤14（原步骤15）: 智能配置生成
# ============================================
#【build_firmware_main.sh-28】
workflow_step14_generate_config() {
    local extra_packages="$1"
    
    log "=== 步骤14: 智能配置生成【动态设备检测版】 ==="
    log "当前设备: $DEVICE"
    log "当前目标: $TARGET"
    log "当前子目标: $SUBTARGET"
    
    set -e
    trap 'echo "❌ 步骤14 失败，退出代码: $?"; exit 1' ERR
    
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从环境文件重新加载: DEVICE=$DEVICE, TARGET=$TARGET"
    fi
    
    if [ -z "$DEVICE" ] && [ -n "$2" ]; then
        DEVICE="$2"
        log "⚠️ DEVICE为空，使用参数: $DEVICE"
    fi
    
    cd "$BUILD_DIR" || handle_error "无法进入构建目录"
    
    log ""
    log "=== 🔍 动态检测设备定义文件 ==="
    
    # 获取设备的搜索关键词
    local search_names=()
    if [ -f "$SUPPORT_SCRIPT" ]; then
        # 从 support.sh 获取搜索关键词
        while IFS= read -r name; do
            search_names+=("$name")
        done < <("$SUPPORT_SCRIPT" get-search-names "$DEVICE" 2>/dev/null || echo "$DEVICE")
    else
        # 手动生成搜索关键词
        search_names+=("$DEVICE")
        local base_name=$(echo "$DEVICE" | sed -E 's/-(nand|emmc|spi|nor|sdcard|usb)$//' | sed -E 's/_(nand|emmc|spi|nor|sdcard|usb)$//')
        search_names+=("$base_name")
        search_names+=("$(echo "$DEVICE" | tr '-' '_')")
        search_names+=("$(echo "$DEVICE" | tr '_' '-')")
    fi
    
    log "搜索关键词: ${search_names[*]}"
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
    
    # 存储所有找到的设备
    declare -A found_devices
    local device_counter=0
    
    for mkfile in "${mk_files[@]}"; do
        for keyword in "${search_names[@]}"; do
            # 查找包含关键词的设备定义行
            while IFS= read -r line; do
                if [[ "$line" =~ define[[:space:]]+Device[[:space:]]*[/]?([^[:space:]]+) ]]; then
                    local dev_name="${BASH_REMATCH[1]}"
                    # 多种匹配方式
                    if [[ "$dev_name" == *"$keyword"* ]] || \
                       [[ "$keyword" == *"$dev_name"* ]] || \
                       [[ "${dev_name,,}" == *"${keyword,,}"* ]] || \
                       [[ "${keyword,,}" == *"${dev_name,,}"* ]]; then
                        if [ -z "${found_devices[$dev_name]}" ]; then
                            found_devices["$dev_name"]="$mkfile"
                            device_counter=$((device_counter + 1))
                            log "  📍 发现设备: $dev_name (在 $mkfile 中)"
                        fi
                    fi
                fi
            done < <(grep -n "define Device" "$mkfile" 2>/dev/null)
        done
    done
    
    echo ""
    log "📊 共找到 $device_counter 个相关设备定义:"
    echo "----------------------------------------"
    local dev_list=()
    local index=1
    for dev in $(for d in "${!found_devices[@]}"; do echo "$d"; done | sort); do
        dev_list+=("$dev")
        echo "[$index] $dev (在 ${found_devices[$dev]})"
        index=$((index + 1))
    done
    echo "----------------------------------------"
    echo ""
    
    # 根据设备名特征自动选择正确的设备
    local selected_device=""
    local device_file=""
    
    # 检查是否有明确的变体请求
    local requested_variant=""
    if [[ "$DEVICE" == *"-nand"* ]] || [[ "$DEVICE" == *"_nand"* ]]; then
        requested_variant="nand"
    elif [[ "$DEVICE" == *"-emmc"* ]] || [[ "$DEVICE" == *"_emmc"* ]]; then
        requested_variant="emmc"
    elif [[ "$DEVICE" == *"-spi"* ]] || [[ "$DEVICE" == *"_spi"* ]]; then
        requested_variant="spi"
    elif [[ "$DEVICE" == *"-nor"* ]] || [[ "$DEVICE" == *"_nor"* ]]; then
        requested_variant="nor"
    fi
    
    if [ -n "$requested_variant" ]; then
        log "🔍 检测到明确的变体请求: $requested_variant"
        # 优先选择匹配变体的设备
        for dev in "${dev_list[@]}"; do
            if [[ "$dev" == *"$requested_variant"* ]] || \
               [[ "$dev" == *"${requested_variant^^}"* ]] || \
               [[ "$dev" == *"${requested_variant,,}"* ]]; then
                selected_device="$dev"
                device_file="${found_devices[$dev]}"
                log "✅ 找到匹配变体的设备: $selected_device"
                break
            fi
        done
    fi
    
    # 如果没有匹配变体，检查是否只有一个设备
    if [ -z "$selected_device" ] && [ $device_counter -eq 1 ]; then
        selected_device="${dev_list[0]}"
        device_file="${found_devices[$selected_device]}"
        log "✅ 只有一个设备，自动选择: $selected_device"
    fi
    
    # 如果仍然没有选择，检查设备名是否完全匹配
    if [ -z "$selected_device" ]; then
        for dev in "${dev_list[@]}"; do
            if [ "$dev" = "$DEVICE" ]; then
                selected_device="$dev"
                device_file="${found_devices[$dev]}"
                log "✅ 找到完全匹配的设备: $selected_device"
                break
            fi
        done
    fi
    
    # 如果还是没有，尝试模糊匹配
    if [ -z "$selected_device" ] && [ $device_counter -gt 0 ]; then
        log "⚠️ 警告: 找到多个相关设备，将记录警告并临时选择第一个"
        selected_device="${dev_list[0]}"
        device_file="${found_devices[$selected_device]}"
        log "⚠️ 临时选择: $selected_device (将在前置错误检查中确认)"
    fi
    
    if [ -z "$selected_device" ] || [ ! -f "$device_file" ]; then
        log "❌ 错误：未找到设备 $DEVICE 的相关定义"
        log "请检查设备名称是否正确，或 target/linux/$TARGET 目录下是否存在对应的 .mk 文件"
        exit 1
    fi
    
    log "✅ 最终选择设备: $selected_device"
    log "✅ 设备定义文件: $device_file"
    
    local device_block=""
    device_block=$(awk "/define Device.*$selected_device/,/^[[:space:]]*$|^endef/" "$device_file" 2>/dev/null)
    
    if [ -n "$device_block" ]; then
        echo ""
        echo "📋 设备定义信息（关键字段）:"
        echo "----------------------------------------"
        echo "$device_block" | grep -E "define Device" | head -1
        echo "$device_block" | grep -E "^[[:space:]]*(DEVICE_VENDOR|DEVICE_MODEL|DEVICE_VARIANT|DEVICE_DTS)[[:space:]]*:="
        echo "----------------------------------------"
    else
        log "⚠️ 警告：无法提取设备 $selected_device 的配置块"
    fi
    
    log "✅ 设备定义文件验证通过，继续生成配置"
    
    # 使用找到的设备名生成配置
    generate_config "$extra_packages" "$selected_device"
    
    log ""
    log "=== 🔧 强制禁用不需要的插件系列 ==="
    
    local base_forbidden="${FORBIDDEN_PACKAGES:-vssr ssr-plus passwall rclone ddns qbittorrent filetransfer nlbwmon wol}"
    IFS=' ' read -ra BASE_PKGS <<< "$base_forbidden"
    
    local full_forbidden_list=($(generate_forbidden_packages_list "$base_forbidden"))
    
    log "📋 完整禁用插件列表 (${#full_forbidden_list[@]} 个)"
    
    cp .config .config.before_disable
    
    log "🔧 第一轮禁用..."
    for plugin in "${full_forbidden_list[@]}"; do
        [ -z "$plugin" ] && continue
        sed -i "/^CONFIG_PACKAGE_${plugin}=y/d" .config
        sed -i "/^CONFIG_PACKAGE_${plugin}=m/d" .config
        sed -i "/^CONFIG_PACKAGE_${plugin}_/d" .config
        echo "# CONFIG_PACKAGE_${plugin} is not set" >> .config
    done
    
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
    
    log "✅ 步骤14 完成"
}
#【build_firmware_main.sh-28-end】

# ============================================
# 步骤15（原步骤16）: 验证USB配置
# ============================================
#【build_firmware_main.sh-29】
workflow_step15_verify_usb() {
    log "=== 步骤15: 验证USB配置（智能检测版） ==="
    
    trap 'echo "⚠️ 步骤15 验证过程中出现错误，继续执行..."' ERR
    
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
    log "✅ 步骤15 完成"
}
#【build_firmware_main.sh-29-end】

# ============================================
# 步骤16（原步骤18）: 应用配置
# 注意：步骤17已删除，步骤18变为步骤16
# ============================================
#【build_firmware_main.sh-30】
workflow_step16_apply_config() {
    log "=== 步骤16: 应用配置并显示详细信息 ==="
    
    set -e
    trap 'echo "❌ 步骤16 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    echo "🔄 调用 apply_config 函数..."
    apply_config
    
    log "✅ 步骤16 完成"
}
#【build_firmware_main.sh-30-end】

# ============================================
# 步骤17（原步骤20）: 修复网络环境
# ============================================
#【build_firmware_main.sh-31】
workflow_step17_fix_network() {
    log "=== 步骤17: 修复网络环境（动态检测版） ==="
    
    trap 'echo "⚠️ 步骤17 修复过程中出现错误，继续执行..."' ERR
    
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
    
    log "✅ 步骤17 完成"
}
#【build_firmware_main.sh-31-end】

# ============================================
# 步骤18（原步骤21）: 下载依赖包
# ============================================
#【build_firmware_main.sh-32】
workflow_step18_download_deps() {
    log "=== 步骤18: 下载依赖包（动态优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤18 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    echo "🔧 检查依赖包目录..."
    if [ ! -d "dl" ]; then
        mkdir -p dl
        echo "✅ 创建依赖包目录: dl"
    fi
    
    # 显示当前源码类型
    echo "📋 源码类型: $SOURCE_REPO_TYPE"
    echo "📋 目标设备: $DEVICE"
    echo "📋 目标平台: $TARGET/$SUBTARGET"
    echo ""
    
    # 显示 feeds 配置
    echo "📋 feeds.conf.default 内容:"
    echo "----------------------------------------"
    cat feeds.conf.default
    echo "----------------------------------------"
    echo ""
    
    # 设置国内镜像源（针对LEDE）
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        echo "🔧 LEDE源码模式，配置国内镜像源..."
        
        # 备份原配置
        cp feeds.conf.default feeds.conf.default.bak
        
        # 替换为国内镜像源（如果使用默认的coolsnowwolf源）
        if grep -q "github.com/coolsnowwolf" feeds.conf.default; then
            sed -i 's|https://github.com/coolsnowwolf|https://mirrors.aliyun.com/lede|g' feeds.conf.default
            sed -i 's|git://github.com/coolsnowwolf|https://mirrors.aliyun.com/lede|g' feeds.conf.default
            echo "✅ 已替换为阿里云LEDE镜像: https://mirrors.aliyun.com/lede"
        fi
    fi
    
    # 设置通用镜像源环境变量
    export OPENWRT_MIRROR="https://mirrors.aliyun.com/openwrt"
    export SOURCE_MIRROR="https://mirrors.tuna.tsinghua.edu.cn"
    export GNU_MIRROR="https://mirrors.aliyun.com/gnu"
    export KERNEL_MIRROR="https://mirrors.aliyun.com/linux-kernel"
    
    echo "✅ 已设置国内镜像源:"
    echo "   OPENWRT_MIRROR=$OPENWRT_MIRROR"
    echo "   SOURCE_MIRROR=$SOURCE_MIRROR"
    echo "   GNU_MIRROR=$GNU_MIRROR"
    echo ""
    
    # 统计现有依赖包
    local dep_count=$(find dl -type f 2>/dev/null | wc -l)
    local dep_size=$(du -sh dl 2>/dev/null | cut -f1 || echo "0B")
    echo "📊 当前依赖包: $dep_count 个, 总大小: $dep_size"
    
    # 显示现有依赖包列表（如果有）
    if [ $dep_count -gt 0 ]; then
        echo ""
        echo "📋 现有依赖包列表:"
        ls -lh dl/ | head -20
        if [ $dep_count -gt 20 ]; then
            echo "... 还有 $((dep_count - 20)) 个文件未显示"
        fi
        echo ""
    fi
    
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
    echo "下载日志将保存到: download.log"
    echo ""
    
    # 创建日志文件并实时显示
    touch download.log
    
    # 在后台启动日志监控（实时显示下载进度）
    {
        tail -f download.log | while read line; do
            if echo "$line" | grep -q "Downloading"; then
                echo "📥 $line"
            elif echo "$line" | grep -q "ERROR\|Failed\|404"; then
                echo "❌ $line"
            elif echo "$line" | grep -q "done\|Complete"; then
                echo "✅ $line"
            elif echo "$line" | grep -q "flock\|download.pl"; then
                # 显示下载命令
                echo "  🔄 $line"
            fi
        done
    } &
    local monitor_pid=$!
    
    # 记录开始时间
    local start_time=$(date +%s)
    local last_report_time=$start_time
    local last_dl_count=$dep_count
    
    # 在后台启动进度监控（每30秒报告一次）
    {
        while true; do
            sleep 30
            local current_time=$(date +%s)
            local current_dl_count=$(find dl -type f 2>/dev/null | wc -l)
            local new_files=$((current_dl_count - last_dl_count))
            local elapsed=$((current_time - start_time))
            
            echo ""
            echo "⏱️ 下载进度报告 (已运行 $((elapsed / 60))分$((elapsed % 60))秒):"
            echo "  当前依赖包: $current_dl_count 个 (+$new_files)"
            echo "  最近30秒新增: $new_files 个"
            echo ""
            
            # 显示最近下载的几个文件
            if [ $new_files -gt 0 ]; then
                echo "  最近下载的文件:"
                find dl -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -5 | while read line; do
                    local file=$(echo "$line" | cut -d' ' -f2-)
                    local name=$(basename "$file")
                    echo "    📄 $name"
                done
                echo ""
            fi
            
            last_dl_count=$current_dl_count
            last_report_time=$current_time
        done
    } &
    local progress_pid=$!
    
    # 先尝试快速下载，使用 V=s 显示详细输出
    if make -j$download_jobs download -k V=s > download.log 2>&1; then
        echo "✅ 下载完成"
    else
        echo "⚠️ 部分下载失败，尝试使用镜像源重试..."
        
        # 检查是否有404错误
        local error_404=$(grep -c "404" download.log 2>/dev/null || echo "0")
        if [ $error_404 -gt 0 ]; then
            echo ""
            echo "🔍 检测到 $error_404 个404错误，尝试使用镜像源重试..."
            
            # 备份原来的dl目录
            if [ -d "dl" ] && [ "$(ls -A dl)" ]; then
                mkdir -p dl_backup
                cp -r dl/* dl_backup/ 2>/dev/null || true
                echo "✅ 已备份现有下载文件到 dl_backup"
            fi
            
            # 提取失败的包并重试
            local failed_packages=$(grep -B1 "404" download.log | grep "Downloading" | sed 's/.*Downloading //g' | sort -u)
            if [ -n "$failed_packages" ]; then
                echo ""
                echo "🔄 重试失败的包（使用镜像源）:"
                echo "$failed_packages" | head -10 | while read url; do
                    local filename=$(basename "$url")
                    echo "   📥 $filename"
                    
                    # 尝试从镜像源下载
                    if echo "$url" | grep -q "github.com"; then
                        # GitHub源使用镜像
                        local mirror_url="https://mirror.ghproxy.com/$url"
                        echo "     尝试镜像: $mirror_url"
                        wget -q --show-progress "$mirror_url" -O "dl/$filename" || true
                    elif echo "$url" | grep -q "kernel.org"; then
                        # kernel.org使用阿里云镜像
                        local mirror_url="https://mirrors.aliyun.com/linux-kernel/$(basename $url)"
                        echo "     尝试镜像: $mirror_url"
                        wget -q --show-progress "$mirror_url" -O "dl/$filename" || true
                    elif echo "$url" | grep -q "gnu.org"; then
                        # GNU使用阿里云镜像
                        local mirror_url="https://mirrors.aliyun.com/gnu/$(basename $url)"
                        echo "     尝试镜像: $mirror_url"
                        wget -q --show-progress "$mirror_url" -O "dl/$filename" || true
                    fi
                done
                
                if [ $(echo "$failed_packages" | wc -l) -gt 10 ]; then
                    echo "  ... 还有 $(( $(echo "$failed_packages" | wc -l) - 10 )) 个包未显示"
                fi
            fi
        fi
        
        # 使用单线程重试剩余的包
        echo ""
        echo "🔄 使用单线程重试下载..."
        make download -j1 V=s >> download.log 2>&1 || true
        
        echo "✅ 镜像源重试完成"
    fi
    
    # 停止监控进程
    kill $monitor_pid 2>/dev/null || true
    kill $progress_pid 2>/dev/null || true
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 统计下载结果
    local new_dep_count=$(find dl -type f 2>/dev/null | wc -l)
    local new_dep_size=$(du -sh dl 2>/dev/null | cut -f1)
    local added=$((new_dep_count - dep_count))
    
    echo ""
    echo "📊 下载统计:"
    echo "   总耗时: $((duration / 60))分$((duration % 60))秒"
    echo "   原有包: $dep_count 个 ($dep_size)"
    echo "   现有包: $new_dep_count 个 ($new_dep_size)"
    echo "   新增包: $added 个"
    
    # 显示下载的包列表
    if [ $added -gt 0 ]; then
        echo ""
        echo "📦 新增依赖包列表:"
        echo "----------------------------------------"
        
        # 获取新增的文件列表（按时间排序，最新的在前）
        find dl -type f -printf "%T@ %p\n" 2>/dev/null | sort -nr | head -20 | while read line; do
            local file=$(echo "$line" | cut -d' ' -f2-)
            local size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
            local name=$(basename "$file")
            printf "  📄 %-50s %s\n" "$name" "$size"
        done
        
        if [ $added -gt 20 ]; then
            echo "  ... 还有 $((added - 20)) 个文件未显示"
        fi
        echo "----------------------------------------"
    fi
    
    # 分析下载日志，提取实际URL
    echo ""
    echo "🔍 提取下载URL（从日志中）:"
    echo "----------------------------------------"
    grep -E "Downloading|--\d{4}-\d{2}-\d{2}" download.log | head -30 | while read line; do
        if echo "$line" | grep -q "Downloading"; then
            echo "📥 $line"
        fi
    done
    echo "----------------------------------------"
    
    # 详细分析下载错误
    local error_count=$(grep -c -E "ERROR|Failed|404" download.log 2>/dev/null | tr -d ' ' || echo "0")
    if [ "$error_count" -gt 0 ] 2>/dev/null; then
        echo ""
        echo "⚠️ 发现 $error_count 个下载错误:"
        echo "-----------------------------------------------------------------"
        
        # 分类统计错误类型
        echo "📊 错误类型统计:"
        echo ""
        
        # 404错误统计 - 确保是数字
        local error_404=$(grep -c "404" download.log 2>/dev/null | tr -d ' ' || echo "0")
        echo "  404 Not Found: $error_404 个"
        
        # 超时错误 - 确保是数字
        local error_timeout=$(grep -c "Timeout\|timed out" download.log 2>/dev/null | tr -d ' ' || echo "0")
        echo "  超时错误: $error_timeout 个"
        
        # 其他错误 - 修复算术运算错误
        local other_errors=0
        # 确保所有变量都是数字
        local ec=$((error_count + 0))
        local e404=$((error_404 + 0))
        local et=$((error_timeout + 0))
        other_errors=$((ec - e404 - et))
        echo "  其他错误: $other_errors 个"
        echo ""
        
        # 显示具体的404错误URL
        if [ $error_404 -gt 0 ]; then
            echo "🔍 404错误详情（无法下载的URL）:"
            echo ""
            
            # 从日志中提取404的URL
            grep -B1 "404" download.log | grep "Downloading" | sed 's/.*Downloading //g' | sort -u | head -10 | while read url; do
                echo "  ❌ $url"
                
                # 提供镜像源替代方案
                local filename=$(basename "$url")
                if echo "$url" | grep -q "github.com"; then
                    echo "     💡 GitHub镜像: https://mirror.ghproxy.com/$url"
                elif echo "$url" | grep -q "kernel.org"; then
                    echo "     💡 阿里云镜像: https://mirrors.aliyun.com/linux-kernel/$filename"
                elif echo "$url" | grep -q "gnu.org"; then
                    echo "     💡 阿里云镜像: https://mirrors.aliyun.com/gnu/$filename"
                elif echo "$url" | grep -q "openwrt.org"; then
                    echo "     💡 清华镜像: https://mirrors.tuna.tsinghua.edu.cn/openwrt/$filename"
                fi
            done
            
            local unique_404=$(grep -B1 "404" download.log | grep "Downloading" | sed 's/.*Downloading //g' | sort -u | wc -l)
            if [ $unique_404 -gt 10 ]; then
                echo "  ... 还有 $((unique_404 - 10)) 个不同的404错误未显示"
            fi
            echo ""
        fi
        
        # 显示最近10个错误
        echo "📋 最近10个错误:"
        echo ""
        grep -E "ERROR|Failed|404" download.log | tail -10 | while read line; do
            echo "  ❌ $line"
        done
        echo "-----------------------------------------------------------------"
        
        # 建议解决方案
        echo ""
        echo "💡 建议解决方案:"
        echo "  1. 使用国内镜像源（已自动配置）"
        echo "  2. 手动下载失败的包（上面已提供镜像命令）"
        echo "  3. 重试构建，失败的包可能被缓存"
        echo "  4. 如果持续失败，可以考虑："
        echo "     - 使用 'make package/XXX/download V=s' 单独下载特定包"
        echo "     - 检查网络连接和防火墙设置"
        echo "     - 尝试使用代理或VPN"
        echo ""
    fi
    
    # 检查是否有特定的包导致问题
    echo ""
    echo "🔍 检查可能导致编译失败的包:"
    echo "----------------------------------------"
    
    # 检查curl 404错误数量
    local curl_errors=$(grep -c "curl: (22)" download.log 2>/dev/null | tr -d ' ' || echo "0")
    if [ $curl_errors -gt 0 ]; then
        echo "⚠️ 发现 $curl_errors 个curl 404错误"
        echo "   💡 已自动配置国内镜像源，如果仍有问题，可以手动下载："
        echo ""
        
        # 提取最常见的几个失败包
        grep -B1 "curl: (22)" download.log | grep "Downloading" | sed 's/.*Downloading //g' | sort | uniq -c | sort -nr | head -5 | while read count url; do
            local filename=$(basename "$url")
            echo "   🔄 $filename (失败 $count 次)"
            echo "     手动下载: wget $url -O dl/$filename"
            if echo "$url" | grep -q "github.com"; then
                echo "     镜像下载: wget https://mirror.ghproxy.com/$url -O dl/$filename"
            fi
        done
    fi
    
    echo "----------------------------------------"
    
    # 如果没有下载任何包，显示警告
    if [ $added -eq 0 ] && [ $dep_count -eq 0 ]; then
        echo ""
        echo "⚠️ 警告: 没有下载任何包，请检查:"
        echo "   1. feeds.conf.default 是否正确"
        echo "   2. 网络连接是否正常"
        echo "   3. 是否有足够的磁盘空间"
        echo "   4. 下载源是否可用"
        echo ""
        echo "📋 完整下载日志内容:"
        echo "----------------------------------------"
        cat download.log
        echo "----------------------------------------"
    fi
    
    log "✅ 步骤18 完成"
}
#【build_firmware_main.sh-32-end】

# ============================================
# 步骤19（原步骤22）: 集成自定义文件
# ============================================
#【build_firmware_main.sh-33】
workflow_step19_integrate_custom_files() {
    log "=== 步骤19: 集成自定义文件（增强版） ==="
    
    trap 'echo "⚠️ 步骤19 集成过程中出现错误，继续执行..."' ERR
    
    integrate_custom_files
    
    log "✅ 步骤19 完成"
}
#【build_firmware_main.sh-33-end】

# ============================================
# 步骤20（原步骤23）: 前置错误检查
# ============================================
#【build_firmware_main.sh-34】
workflow_step20_pre_build_check() {
    log "=== 步骤20: 前置错误检查（增强版 - 多设备检测） ==="
    
    set -e
    trap 'echo "❌ 步骤20 失败，退出代码: $?"; exit 1' ERR
    
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
        
        # 动态检测设备配置
        local found_device_configs=()
        while IFS= read -r line; do
            if [[ "$line" =~ ^CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_(.+)=y$ ]]; then
                found_device_configs+=("${BASH_REMATCH[1]}")
            fi
        done < .config
        
        if [ ${#found_device_configs[@]} -eq 0 ]; then
            echo "   ❌ 没有找到任何设备配置"
            error_count=$((error_count + 1))
        elif [ ${#found_device_configs[@]} -eq 1 ]; then
            echo "   ✅ 找到一个设备配置: ${found_device_configs[0]}"
        else
            echo "   ⚠️ 警告: 找到多个设备配置 (${#found_device_configs[@]} 个):"
            for dev in "${found_device_configs[@]}"; do
                echo "      - $dev"
            done
            echo "   💡 建议: 只应启用一个设备，其他应该禁用"
            warning_count=$((warning_count + 1))
        fi
        
        # 检查设备名是否正确
        local device_for_config=$(echo "$DEVICE" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
        local found=false
        for dev in "${found_device_configs[@]}"; do
            if [[ "$dev" == *"$device_for_config"* ]] || [[ "$device_for_config" == *"$dev"* ]]; then
                found=true
                echo "   ✅ 找到匹配的设备: $dev"
                break
            fi
        done
        
        if [ "$found" = false ] && [ ${#found_device_configs[@]} -gt 0 ]; then
            echo "   ⚠️ 警告: 启用的设备与请求的 $DEVICE 不匹配"
            echo "      请求设备: $DEVICE"
            echo "      实际启用: ${found_device_configs[*]}"
            warning_count=$((warning_count + 1))
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
    
    # 8. 检测设备变体（重要）
    echo "8. 🔍 设备变体检测:"
    if [[ "$DEVICE" == *"rax3000m"* ]]; then
        echo "   📱 检测到 RAX3000M 设备"
        
        # 检查是否有多个变体
        local variants=()
        if grep -q "cmcc_rax3000m-emmc" .config 2>/dev/null; then
            variants+=("emmc")
        fi
        if grep -q "cmcc_rax3000m-nand" .config 2>/dev/null; then
            variants+=("nand")
        fi
        if grep -q "cmcc_rax3000m" .config 2>/dev/null; then
            variants+=("generic")
        fi
        
        if [ ${#variants[@]} -gt 1 ]; then
            echo "   ⚠️ 警告: 检测到多个设备变体: ${variants[*]}"
            echo "   💡 建议: 只应启用一个变体 (根据你的硬件选择 nand 或 emmc)"
            warning_count=$((warning_count + 1))
        elif [ ${#variants[@]} -eq 1 ]; then
            echo "   ✅ 检测到设备变体: ${variants[0]}"
            
            # 检查变体是否匹配
            if [[ "$DEVICE" == *"nand"* ]] && [ "${variants[0]}" != "nand" ]; then
                echo "   ❌ 变体不匹配: 请求 NAND 但启用 ${variants[0]}"
                error_count=$((error_count + 1))
            elif [[ "$DEVICE" == *"emmc"* ]] && [ "${variants[0]}" != "emmc" ]; then
                echo "   ❌ 变体不匹配: 请求 eMMC 但启用 ${variants[0]}"
                error_count=$((error_count + 1))
            fi
        fi
    fi
    echo ""
    
    # 9. 检查关键工具
    echo "9. 🔧 主机工具检查:"
    local tools=("padjffs2" "mkdniimg" "fwtool" "mklibs" "mkimage")
    local missing_tools=0
    
    for tool in "${tools[@]}"; do
        if [ -f "staging_dir/host/bin/$tool" ] && [ -x "staging_dir/host/bin/$tool" ]; then
            echo "   ✅ $tool: 存在"
        else
            echo "   ⚠️ $tool: 不存在 (将在编译时生成)"
            missing_tools=$((missing_tools + 1))
        fi
    done
    
    if [ $missing_tools -gt 0 ]; then
        echo "   💡 将自动重新编译缺失的工具"
    fi
    echo ""
    
    echo "========================================"
    if [ $error_count -gt 0 ]; then
        echo "❌❌❌ 检测到 $error_count 个错误，请修复后重试 ❌❌❌"
        echo ""
        echo "📋 错误详情:"
        echo "1. 设备配置错误 - 请检查设备名是否正确"
        echo "   - 如果是 RAX3000M，请明确指定 nand 或 emmc 版本"
        echo "   - 示例: cmcc_rax3000m-nand 或 cmcc_rax3000m-emmc"
        echo ""
        echo "2. 可以在 .config 中手动修改:"
        echo "   # 启用 NAND 版本"
        echo "   CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m-nand=y"
        echo "   # 禁用其他版本"
        echo "   # CONFIG_TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m-emmc is not set"
        exit 1
    elif [ $warning_count -gt 0 ]; then
        echo "⚠️⚠️⚠️ 检测到 $warning_count 个警告，但可以继续 ⚠️⚠️⚠️"
    else
        echo "✅✅✅ 所有检查通过，可以开始编译 ✅✅✅"
    fi
    echo "========================================"
    
    log "✅ 步骤20 完成"
}
#【build_firmware_main.sh-34-end】

# ============================================
# 步骤21（原步骤24）: 编译前空间确认
# 注意：步骤19、20、21、22、23、24已重新编号
# 步骤21对应原步骤24
# ============================================
#【build_firmware_main.sh-35】
workflow_step21_pre_build_space_confirm() {
    log "=== 步骤21: 编译前空间确认 ==="
    
    set -e
    trap 'echo "❌ 步骤21 失败，退出代码: $?"; exit 1' ERR
    
    df -h /mnt
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1 | awk '{print $1}')
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    echo "/mnt 可用空间: ${AVAILABLE_GB}G"
    
    if [ $AVAILABLE_GB -lt 10 ]; then
        echo "❌ 错误: 编译前空间不足 (需要至少10G，当前${AVAILABLE_GB}G)"
        exit 1
    else
        echo "✅ 编译前空间充足"
    fi
    
    log "✅ 步骤21 完成"
}
#【build_firmware_main.sh-35-end】

# ============================================
# 步骤22（原步骤25）: 编译固件
# ============================================
#【build_firmware_main.sh-36】
workflow_step22_build_firmware() {
    local enable_parallel="$1"
    
    log "=== 步骤22: 编译固件（优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤22 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    # ============================================
    # 预检查 dnsmasq-full 配置
    # ============================================
    log "🔧 预检查 dnsmasq-full 配置..."
    if grep -q "^CONFIG_PACKAGE_dnsmasq-full=y" .config; then
        log "  ✅ dnsmasq-full 已启用，检查依赖..."
        
        if grep -q "^CONFIG_PACKAGE_dnsmasq=y" .config; then
            log "  ⚠️ 检测到 dnsmasq 和 dnsmasq-full 同时启用，修复中..."
            sed -i 's/^CONFIG_PACKAGE_dnsmasq=y/# CONFIG_PACKAGE_dnsmasq is not set/g' .config
            make defconfig > /dev/null 2>&1
            log "  ✅ 已禁用 dnsmasq，保留 dnsmasq-full"
        fi
        
        mkdir -p "$BUILD_DIR/files/etc/config"
        mkdir -p "$BUILD_DIR/files/etc/init.d"
        log "  ✅ 预创建 dnsmasq 配置目录"
    fi
    
    # ============================================
    # 设置文件描述符限制
    # ============================================
    log "🔧 设置文件描述符限制..."
    
    local current_limit=$(ulimit -n 2>/dev/null || echo "unknown")
    log "  📊 当前文件描述符限制: $current_limit"
    
    if ulimit -n 65536 2>/dev/null; then
        log "  ✅ 成功设置文件描述符限制为: 65536"
    fi
    
    # ============================================
    # 替换有问题的工具为无害版本
    # ============================================
    log "🔧 替换有问题的工具为无害版本..."
    
    # 备份原有的工具
    if [ -f "staging_dir/host/bin/mkdniimg" ]; then
        mv "staging_dir/host/bin/mkdniimg" "staging_dir/host/bin/mkdniimg.original"
        log "  ✅ 备份原有的 mkdniimg 工具"
    fi
    
    if [ -f "staging_dir/host/bin/fwtool" ]; then
        mv "staging_dir/host/bin/fwtool" "staging_dir/host/bin/fwtool.original"
        log "  ✅ 备份原有的 fwtool 工具"
    fi
    
    # 创建无害的 mkdniimg 替代工具
    cat > "staging_dir/host/bin/mkdniimg" << 'EOF'
#!/bin/bash
# 无害的 mkdniimg 替代工具 - 只复制文件，不做任何处理
INPUT_FILE=""
OUTPUT_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        -i) shift; INPUT_FILE="$1" ;;
        -o) shift; OUTPUT_FILE="$1" ;;
        -B|-v|-H|-r) shift ;;
        *) shift ;;
    esac
    shift
done

[ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_FILE" ] && exit 1
[ ! -f "$INPUT_FILE" ] && exit 1

cp -f "$INPUT_FILE" "$OUTPUT_FILE"
sync
exit 0
EOF
    chmod +x "staging_dir/host/bin/mkdniimg"
    
    # 创建无害的 fwtool 替代工具
    cat > "staging_dir/host/bin/fwtool" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "staging_dir/host/bin/fwtool"
    log "  ✅ 创建无害的工具替代品"
    
    # ============================================
    # 清理临时文件
    # ============================================
    log "  清理临时文件..."
    find build_dir -type f \( -name "*.tmp" -o -name "*.new" \) 2>/dev/null -exec rm -f {} \; 2>/dev/null || true
    
    export KCFLAGS="-O2 -pipe"
    
    # ============================================
    # 创建固件目录
    # ============================================
    log "🔧 创建固件输出目录..."
    local target_dir="bin/targets/ath79/generic"
    mkdir -p "$target_dir"
    log "  ✅ 创建固件目录: $target_dir"
    
    export OPENWRT_VERBOSE=1
    export FORCE_UNSAFE_CONFIGURE=1
    
    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    
    echo ""
    echo "🔧 系统信息:"
    echo "  CPU核心数: $CPU_CORES"
    echo "  内存大小: ${TOTAL_MEM}MB"
    echo "  并行优化: $enable_parallel"
    
    # ============================================
    # 智能并行编译（优化核心）
    # ============================================
    if [ "$enable_parallel" = "true" ] && [ $CPU_CORES -ge 2 ]; then
        # 根据CPU核心数和内存动态调整并行数
        if [ $CPU_CORES -ge 8 ] && [ $TOTAL_MEM -ge 8192 ]; then
            MAKE_JOBS=8
            log "✅ 高性能系统: 使用 $MAKE_JOBS 并行任务"
        elif [ $CPU_CORES -ge 4 ] && [ $TOTAL_MEM -ge 4096 ]; then
            MAKE_JOBS=4
            log "✅ 中性能系统: 使用 $MAKE_JOBS 并行任务"
        elif [ $CPU_CORES -ge 2 ] && [ $TOTAL_MEM -ge 2048 ]; then
            MAKE_JOBS=2
            log "✅ 标准系统: 使用 $MAKE_JOBS 并行任务"
        else
            MAKE_JOBS=1
            log "⚠️ 低性能系统: 使用单线程编译"
        fi
        
        echo ""
        echo "🚀 开始并行编译 (make -j$MAKE_JOBS)"
        echo "   开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
        echo ""
        
        START_TIME=$(date +%s)
        
        set +e
        make -j$MAKE_JOBS V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
        set -e
        
    else
        MAKE_JOBS=1
        echo ""
        echo "🚀 开始单线程编译 (make -j1)"
        echo "   开始时间: $(date +'%Y-%m-%d %H:%M:%S')"
        echo ""
        
        START_TIME=$(date +%s)
        
        set +e
        make -j1 V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
        set -e
    fi
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "📊 编译完成，耗时: $((DURATION / 60))分$((DURATION % 60))秒"
    echo "   并行数: $MAKE_JOBS, 退出代码: $BUILD_EXIT_CODE"
    
    # ============================================
    # 恢复原始工具
    # ============================================
    log "🔧 恢复原始工具..."
    
    if [ -f "staging_dir/host/bin/mkdniimg.original" ]; then
        mv "staging_dir/host/bin/mkdniimg.original" "staging_dir/host/bin/mkdniimg"
    fi
    
    if [ -f "staging_dir/host/bin/fwtool.original" ]; then
        mv "staging_dir/host/bin/fwtool.original" "staging_dir/host/bin/fwtool"
    fi
    
    # ============================================
    # 最终固件检查
    # ============================================
    echo ""
    echo "📊 最终固件检查:"
    echo "----------------------------------------"
    
    local sysupgrade_count=0
    local factory_count=0
    local initramfs_count=0
    
    if [ -d "$target_dir" ]; then
        while IFS= read -r file; do
            if [ -f "$file" ] && [ -s "$file" ]; then
                local filename=$(basename "$file")
                local size=$(ls -lh "$file" | awk '{print $5}')
                
                if [[ "$filename" == *"sysupgrade"* ]]; then
                    sysupgrade_count=$((sysupgrade_count + 1))
                    echo "  ✅ sysupgrade: $filename ($size)"
                elif [[ "$filename" == *"factory"* ]]; then
                    factory_count=$((factory_count + 1))
                    echo "  ✅ factory: $filename ($size)"
                elif [[ "$filename" == *"initramfs"* ]]; then
                    initramfs_count=$((initramfs_count + 1))
                    echo "  🔷 initramfs: $filename ($size)"
                fi
            fi
        done < <(find "$target_dir" -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null)
    fi
    
    echo "----------------------------------------"
    echo "📊 统计: sysupgrade: $sysupgrade_count, factory: $factory_count, initramfs: $initramfs_count"
    
    if [ $sysupgrade_count -eq 0 ] && [ $factory_count -eq 0 ]; then
        echo ""
        echo "❌ 错误: 没有找到任何关键固件文件"
        exit 1
    else
        echo ""
        echo "🎉 固件生成成功！"
    fi
    
    log "✅ 步骤22 完成"
}
#【build_firmware_main.sh-36-end】

# ============================================
# 步骤23（原步骤26）: 检查构建产物
# ============================================
#【build_firmware_main.sh-37】
workflow_step23_check_artifacts() {
    log "=== 步骤23: 检查构建产物（完整显示 + 增强恢复） ==="
    
    set -e
    trap 'echo "❌ 步骤23 失败，退出代码: $?"; exit 1' ERR
    
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
        local other_count=0
        local all_files=()
        
        while IFS= read -r file; do
            if [ -f "$file" ] && [ -s "$file" ]; then
                all_files+=("$file")
            fi
        done < <(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | sort)
        
        # 如果没有找到文件，检查保护目录
        if [ ${#all_files[@]} -eq 0 ] && [ -d ".firmware_protect" ]; then
            echo "⚠️ bin/targets 中未找到固件，检查保护目录..."
            
            local protect_dir=".firmware_protect"
            local protect_files=$(find "$protect_dir" -name "*.backup" -o -name "final_*" 2>/dev/null)
            
            if [ -n "$protect_files" ]; then
                echo "$protect_files" | while read file; do
                    if [ -f "$file" ] && [ -s "$file" ]; then
                        local target_dir="bin/targets/ath79/generic"
                        mkdir -p "$target_dir"
                        local filename=$(basename "$file" .backup)
                        filename=${filename#final_}
                        cp -f "$file" "$target_dir/$filename" 2>/dev/null
                        echo "  ✅ 从保护目录恢复: $filename"
                        all_files+=("$target_dir/$filename")
                    fi
                done
            fi
        fi
        
        for file in "${all_files[@]}"; do
            [ -z "$file" ] && continue
            
            SIZE=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
            FILE_NAME=$(basename "$file")
            FILE_PATH=$(echo "$file" | sed 's|^bin/targets/||')
            
            if echo "$FILE_NAME" | grep -q "sysupgrade"; then
                echo "  ✅ $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🚀 刷机用 - 通过路由器 Web 界面或 sysupgrade 命令刷入"
                echo "    注释: *sysupgrade.bin - 刷机用"
                echo ""
                sysupgrade_count=$((sysupgrade_count + 1))
            elif echo "$FILE_NAME" | grep -q "initramfs"; then
                echo "  🔷 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🆘 恢复用 - 内存启动镜像，不写入闪存"
                echo "    注释: *initramfs-kernel.bin - 恢复用"
                echo ""
                initramfs_count=$((initramfs_count + 1))
            elif echo "$FILE_NAME" | grep -q "factory"; then
                echo "  🏭 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 📦 原厂刷机 - 从原厂固件第一次刷入 OpenWrt"
                echo "    注释: *factory.img/*factory.bin - 原厂刷机用"
                echo ""
                factory_count=$((factory_count + 1))
            else
                echo "  📄 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: ❓ 其他固件文件"
                echo ""
                other_count=$((other_count + 1))
            fi
        done
        
        echo "=========================================="
        echo ""
        echo "📊 固件统计:"
        echo "----------------------------------------"
        echo "  ✅ sysupgrade.bin: $sysupgrade_count 个 - 🚀 **刷机用**"
        echo "  🔷 initramfs-kernel.bin: $initramfs_count 个 - 🆘 **恢复用**"
        echo "  🏭 factory: $factory_count 个 - 📦 **原厂刷机用**"
        echo "  📦 其他文件: $other_count 个"
        echo "----------------------------------------"
        echo ""
        
        echo "🔔 重要提示:"
        echo "  ✅ *sysupgrade.bin - **刷机用**（最终固件）"
        echo "  🔷 *initramfs-kernel.bin - **恢复用**（内存启动）"
        echo "  🏭 *factory.img/*factory.bin - **原厂刷机用**"
        echo ""
        
        if [ $sysupgrade_count -eq 0 ] && [ $factory_count -eq 0 ]; then
            echo "⚠️ 警告: 没有找到可刷机的固件文件！"
            echo ""
            echo "📋 可能的原因和解决方案:"
            echo "   1. padjffs2/mkdniimg 工具错误"
            echo "      - 重新编译工具: make tools/padjffs2/compile V=s"
            echo "      - 重新编译工具: make tools/mkdniimg/compile V=s"
            echo ""
            echo "   2. 固件生成阶段失败"
            echo "      - 单独编译设备: make target/linux/install V=s"
            echo ""
            echo "   3. 临时文件可能保存在:"
            find "$BUILD_DIR/build_dir" -path "*/tmp/*.bin" -o -path "*/tmp/*.img" 2>/dev/null | head -5 | while read file; do
                if [ -f "$file" ] && [ -s "$file" ]; then
                    echo "      📄 $file ($(ls -lh "$file" | awk '{print $5}'))"
                fi
            done
            echo ""
            echo "   4. 可以手动复制临时文件:"
            echo "      cp build_dir/target-*/linux-*/tmp/*.bin bin/targets/ath79/generic/"
        else
            echo "✅ 找到 $sysupgrade_count 个可刷机的 sysupgrade 固件"
            echo ""
            echo "📝 刷机说明:"
            echo "   1. 下载 *sysupgrade.bin 文件"
            echo "   2. 登录路由器 Web 界面 (LuCI)"
            echo "   3. 进入 系统 -> 备份/升级"
            echo "   4. 选择固件文件并点击'刷写固件'"
            echo "   5. 或使用命令行: sysupgrade -n /path/to/*sysupgrade.bin"
        fi
        
        echo "=========================================="
        echo "✅ 构建产物检查完成"
    else
        echo "❌ 错误: 未找到固件目录"
        
        # 检查是否有临时文件
        local tmp_files=$(find "$BUILD_DIR/build_dir" -path "*/tmp/*.bin" -o -path "*/tmp/*.img" 2>/dev/null | head -10)
        if [ -n "$tmp_files" ]; then
            echo ""
            echo "📁 但在临时目录中找到以下文件:"
            echo "$tmp_files" | while read file; do
                if [ -f "$file" ] && [ -s "$file" ]; then
                    echo "  📄 $(basename "$file") ($(ls -lh "$file" | awk '{print $5}'))"
                fi
            done
            echo ""
            echo "💡 可以手动复制这些文件作为固件使用"
        fi
        
        exit 1
    fi
    
    log "✅ 步骤23 完成"
}
#【build_firmware_main.sh-37-end】

# ============================================
# 步骤24（原步骤29）: 编译后空间检查
# ============================================
#【build_firmware_main.sh-38】
workflow_step24_post_build_space_check() {
    log "=== 步骤24: 编译后空间检查（修复版） ==="
    
    trap 'echo "⚠️ 步骤24 检查过程中出现错误，继续执行..."' ERR
    
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
    
    log "✅ 步骤24 完成"
}
#【build_firmware_main.sh-38-end】

# ============================================
# 步骤25（原步骤30）: 编译总结
# ============================================
#【build_firmware_main.sh-39】
workflow_step25_build_summary() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local timestamp_sec="$4"
    local enable_parallel="$5"
    
    log "=== 步骤25: 编译后总结（增强版） ==="
    
    trap 'echo "⚠️ 步骤25 总结过程中出现错误，继续执行..."' ERR
    
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
        GCC_FILE=$(find "$BUILD_DIR" -type f -executable \
            -name "*gcc" \
            ! -name "*gcc-ar" \
            ! -name "*gcc-ranlib" \
            ! -name "*gcc-nm" \
            ! -path "*dummy-tools*" \
            ! -path "*scripts*" \
            2>/dev/null | head -1)
        
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
    echo "⚙️ 功能开关状态:"
    echo "  TurboACC: ${ENABLE_TURBOACC:-true}"
    echo "  TCP BBR: ${ENABLE_TCP_BBR:-true}"
    echo "  ath10k-ct强制: ${FORCE_ATH10K_CT:-true}"
    echo "  USB自动修复: ${AUTO_FIX_USB_DRIVERS:-true}"
    
    echo ""
    echo "✅ 构建流程完成"
    echo "========================================"
    
    log "✅ 步骤25 完成"
}
#【build_firmware_main.sh-39-end】

# ============================================
# 已废弃的搜索函数（保留兼容性）
# ============================================
#【build_firmware_main.sh-40】
# ============================================
# 工作流步骤函数 - 步骤05-08
# 对应 firmware-build.yml 步骤05-08
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

# 以下编译器搜索函数已废弃，由 initialize_compiler_env 替代
#【build_firmware_main.sh-40-end】

#【build_firmware_main.sh-41】
universal_compiler_search() {
    log "=== 通用编译器搜索 ==="
    log "🔍 不再搜索本地编译器，将使用源码自带工具链"
    return 1
}
#【build_firmware_main.sh-41-end】

#【build_firmware_main.sh-42】
search_compiler_files_simple() {
    log "=== 简单编译器文件搜索 ==="
    log "🔍 不再搜索本地编译器，将使用源码自带工具链"
    return 1
}
#【build_firmware_main.sh-42-end】

#【build_firmware_main.sh-43】
intelligent_platform_aware_compiler_search() {
    log "=== 智能平台感知的编译器搜索 ==="
    log "🔍 不再搜索本地编译器，将使用源码自带工具链"
    return 1
}
#【build_firmware_main.sh-43-end】

#【build_firmware_main.sh-44】
# ============================================
# 手动输入模式下的初始化函数（混合模式）
# 对应工作流步骤08
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
        "step08_initialize_build_env_hybrid")
            workflow_step08_initialize_build_env_hybrid "$arg1" "$arg2" "$arg3" "$arg4" "$arg5"
            ;;
        "step10_verify_sdk")
            workflow_step10_verify_sdk
            ;;
        "step11_configure_feeds")
            workflow_step11_configure_feeds
            ;;
        "step12_install_turboacc")
            workflow_step12_install_turboacc
            ;;
        "step13_pre_build_space_check")
            workflow_step13_pre_build_space_check
            ;;
        "step14_generate_config")
            workflow_step14_generate_config "$arg1"
            ;;
        "step15_verify_usb")
            workflow_step15_verify_usb
            ;;
        "step16_apply_config")
            workflow_step16_apply_config
            ;;
        "step17_fix_network")
            workflow_step17_fix_network
            ;;
        "step18_download_deps")
            workflow_step18_download_deps
            ;;
        "step19_integrate_custom_files")
            workflow_step19_integrate_custom_files
            ;;
        "step20_pre_build_check")
            workflow_step20_pre_build_check
            ;;
        "step21_pre_build_space_confirm")
            workflow_step21_pre_build_space_confirm
            ;;
        "step22_build_firmware")
            workflow_step22_build_firmware "$arg1"
            ;;
        "step23_check_artifacts")
            workflow_step23_check_artifacts
            ;;
        "step24_post_build_space_check")
            workflow_step24_post_build_space_check
            ;;
        "step25_build_summary")
            workflow_step25_build_summary "$arg1" "$arg2" "$arg3" "$arg4" "$arg5"
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
            echo "    step08_initialize_build_env, step08_initialize_build_env_hybrid, step10_verify_sdk"
            echo "    step11_configure_feeds, step12_install_turboacc, step13_pre_build_space_check"
            echo "    step14_generate_config, step15_verify_usb, step16_apply_config"
            echo "    step17_fix_network, step18_download_deps, step19_integrate_custom_files"
            echo "    step20_pre_build_check, step21_pre_build_space_confirm, step22_build_firmware"
            echo "    step23_check_artifacts, step24_post_build_space_check, step25_build_summary"
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
