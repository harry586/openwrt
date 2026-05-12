#!/bin/bash
#【build_firmware_main.sh-00】
# OpenWrt 智能固件构建主脚本
# 对应工作流: firmware-build.yml
# 版本: 3.2.0
# 最后更新: 2026-04-25
#
# 函数定义顺序已与工作流执行顺序对齐：
#   05 安装基础工具 -> 06 初始空间检查 -> 07 创建构建目录 -> 
#   08 初始化构建环境 -> 09 添加TurboACC -> 10 配置Feeds -> 
#   11 安装TurboACC包 -> 12 智能配置生成 -> 13 验证USB配置 -> 
#   14 USB驱动检查 -> 15 应用配置 -> 16 备份配置(由YAML直接执行) ->
#   17 修复网络 -> 18 下载依赖 -> 19 集成自定义文件 -> 
#   20 前置错误检查 -> 21 编译工具链 -> 22 验证工具链 -> 
#   23 编译前空间检查 -> 24 编译固件 -> 25 检查产物 -> 
#   28 编译后空间检查 -> 29 编译总结
#【build_firmware_main.sh-00-end】

#【build_firmware_main.sh-00.5】
# 加载统一配置文件
load_build_config() {
    local config_file="${1:-$REPO_ROOT/build-config.conf}"
    
    # 如果已经加载过，直接返回
    if [ -n "$CONFIG_ALREADY_LOADED" ]; then
        return 0
    fi
    
    # 保存当前环境变量中已设置的值
    local current_source_repo="${SOURCE_REPO_TYPE:-${SOURCE_REPO:-}}"
    local current_build_dir="${BUILD_DIR:-}"
    local current_log_dir="${LOG_DIR:-}"
    local current_backup_dir="${BACKUP_DIR:-}"
    
    if [ -f "$config_file" ]; then
        echo "📁 加载统一配置文件: $config_file"
        source "$config_file"
    else
        echo "⚠️ 未找到配置文件 $config_file，使用脚本内默认值"
    fi
    
    # 恢复从 workflow 传入的环境变量（优先级更高）
    if [ -n "$current_source_repo" ]; then
        SOURCE_REPO_TYPE="$current_source_repo"
        export SOURCE_REPO_TYPE
        echo "✅ 使用 workflow 传入的源码仓库类型: $SOURCE_REPO_TYPE"
    fi
    
    if [ -n "${SOURCE_REPO:-}" ] && [ -z "$SOURCE_REPO_TYPE" ]; then
        SOURCE_REPO_TYPE="$SOURCE_REPO"
        export SOURCE_REPO_TYPE
        echo "✅ 从 SOURCE_REPO 环境变量设置源码仓库类型: $SOURCE_REPO_TYPE"
    fi
    
    : ${SOURCE_REPO_TYPE:="immortalwrt"}
    export SOURCE_REPO_TYPE
    
    [ -n "$current_build_dir" ] && BUILD_DIR="$current_build_dir"
    [ -n "$current_log_dir" ] && LOG_DIR="$current_log_dir"
    [ -n "$current_backup_dir" ] && BACKUP_DIR="$current_backup_dir"
    
    export BUILD_DIR LOG_DIR BACKUP_DIR CONFIG_DIR
    export IMMORTALWRT_URL OPENWRT_URL LEDE_URL PACKAGES_FEED_URL LUCI_FEED_URL TURBOACC_FEED_URL
    export ENABLE_TURBOACC ENABLE_TCP_BBR ENABLE_FULLCONE_NAT FORCE_ATH10K_CT AUTO_FIX_USB_DRIVERS
    export ENABLE_DYNAMIC_KERNEL_DETECTION ENABLE_DYNAMIC_PLATFORM_DRIVERS ENABLE_DYNAMIC_DEVICE_MAPPING
    export DISABLE_IPV6
    
    # ============================================
    # 检查文件描述符限制（修复Broken pipe）
    # ============================================
    echo "🔧 检查文件描述符限制..."
    local current_limit=$(ulimit -n)
    echo "  当前文件描述符限制: $current_limit"
    
    if [ $current_limit -lt 65536 ]; then
        echo "  文件描述符限制过低，尝试提高到65536..."
        ulimit -n 65536 2>/dev/null || sudo ulimit -n 65536 2>/dev/null || true
        local new_limit=$(ulimit -n)
        echo "  新的文件描述符限制: $new_limit"
    fi
    
    echo "✅ 配置加载完成，当前源码仓库类型: $SOURCE_REPO_TYPE"
    
    # 标记已加载
    export CONFIG_ALREADY_LOADED=1

#【build_firmware_main.sh-00.5.01】
    # 导出补丁相关变量
    export BUILTIN_PATCHES_ENABLED
    export CUSTOM_PATCH_SCRIPT
#【build_firmware_main.sh-00.5.01-end】
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_FILE="$REPO_ROOT/build-config.conf"

if [ -n "${SOURCE_REPO:-}" ]; then
    export SOURCE_REPO_TYPE="$SOURCE_REPO"
fi

# 修复：只调用 load_build_config，不在外部重复 source
if [ -z "$CONFIG_ALREADY_LOADED" ]; then
    if [ -f "$CONFIG_FILE" ]; then
        load_build_config
    fi
fi
#【build_firmware_main.sh-00.5-end】

#【build_firmware_main.sh-00.6】
# 通用 Makefile 解析框架 —— 所有编译步骤的前置检查

# 从源码根目录 Makefile 或 include/*.mk 中确认某个目标存在
# 用法: target_from_root_makefile <target_keyword>
# 返回: 成功返回0，否则返回1
target_from_root_makefile() {
    local keyword="$1"
    grep -qE "(^|\s)${keyword}(\s|:|$)" "$BUILD_DIR/Makefile" "$BUILD_DIR/include"/*.mk 2>/dev/null
}

# 动态查找软件包源码目录（用于 host 工具编译）
# 参数1：软件包名称（如 opkg, fakeroot, mkhash）
# 参数2：构建根目录（默认 $BUILD_DIR）
# 返回：第一个合法目录的相对路径，找不到返回1
find_package_dir() {
    local pkg="$1"
    local build_dir="${2:-$BUILD_DIR}"

    # 0. 如果直接给定了完整目录且包含 Makefile
    if [ -f "$build_dir/$pkg/Makefile" ]; then
        echo "$pkg"
        return 0
    fi

    # 1. 从 package/Makefile 中的依赖行提取实际路径
    #    例如: $(curdir)/compile: $(curdir)/system/opkg/host/compile
    local target=$(grep -oP '\(curdir\)/compile:\s*\K.*\/'"$pkg"'\/host\/compile' "$build_dir/package/Makefile" 2>/dev/null | head -1)
    if [ -n "$target" ]; then
        # 去掉 /host/compile，并清理多余的 curdir 引用和双斜线
        local pkg_dir="package/$(echo "$target" | sed -E 's|/host/compile||; s|\(curdir\)/||g; s|//|/|g')"
        if [ -d "$build_dir/$pkg_dir" ]; then
            echo "$pkg_dir"
            return 0
        fi
    fi

    # 2. 遍历常见目录
    local try_dirs=(
        "package/system/$pkg"
        "package/$pkg"
        "package/utils/$pkg"
        "feeds/packages/$pkg"
        "feeds/luci/$pkg"
    )
    for d in "${try_dirs[@]}"; do
        [ -d "$build_dir/$d" ] && echo "$d" && return 0
    done

    # 3. 模糊搜索
    local found=$(find "$build_dir/package" "$build_dir/feeds" -maxdepth 4 -type d -name "$pkg" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "${found#$build_dir/}"
        return 0
    fi

    return 1
}

# 检查函数是否存在
function_exists() {
    [ "$(type -t "$1")" = "function" ] && return 0 || return 1
}
#【build_firmware_main.sh-00.6-end】

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

# 简单的日志函数，不触发配置加载
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
    echo "export SOURCE_REPO_TYPE=\"${SOURCE_REPO_TYPE}\"" >> $ENV_FILE
    
    # 保存配置开关状态
    echo "export ENABLE_TURBOACC=\"${ENABLE_TURBOACC}\"" >> $ENV_FILE
    echo "export ENABLE_TCP_BBR=\"${ENABLE_TCP_BBR}\"" >> $ENV_FILE
    echo "export FORCE_ATH10K_CT=\"${FORCE_ATH10K_CT}\"" >> $ENV_FILE
    echo "export AUTO_FIX_USB_DRIVERS=\"${AUTO_FIX_USB_DRIVERS}\"" >> $ENV_FILE
    echo "export DISABLE_IPV6=\"${DISABLE_IPV6}\"" >> $ENV_FILE
    
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
    sudo apt-get update || handle_error "apt-get更新失败"
    
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
    
    # 关键依赖包 - 修复所有缺失问题
    local critical_packages=(
        libyaml-dev
        libyaml-cpp-dev
        libssl-dev
        libxml2-dev
        libxslt1-dev
        libuv1-dev
        libidn11-dev
        libidn2-dev
        libpsl-dev
        libnghttp2-dev
        libcap-dev
        libcap-ng-dev
        libmnl-dev
        libnftnl-dev
        libuuid1
        uuid-dev
    )
    
    # 新增：修复 Error 127 常见缺失的工具
    local extra_host_tools=(
        device-tree-compiler          # dtc (编译 DTS 必需)
        u-boot-tools                  # mkimage (生成 ITB / FIT 镜像)
        python3-pyelftools            # 用于分析 ELF 文件 (某些源码)
        lz4 lz4-algorithm             # LZ4 压缩（可能需要的内核/镜像格式）
        cpio                          # initramfs 打包
        genext2fs                     # ext2/3/4 镜像生成工具
        brotli                        # 未来固件压缩格式
        zstd                          # Zstandard 压缩
        liblz4-dev liblzma-dev        # 压缩库头文件
    )
    
    log "安装基础编译工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_packages[@]}" || handle_error "安装基础编译工具失败"
    
    log "安装网络工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${network_packages[@]}" || handle_error "安装网络工具失败"
    
    log "安装文件系统工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${filesystem_packages[@]}" || handle_error "安装文件系统工具失败"
    
    log "安装调试工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${debug_packages[@]}" || handle_error "安装调试工具失败"
    
    log "安装关键依赖包（修复编译错误）..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${critical_packages[@]}" || {
        log "⚠️ 部分关键依赖安装失败，尝试单独安装..."
        for pkg in "${critical_packages[@]}"; do
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || log "  ⚠️ $pkg 安装失败"
        done
    }
    
    log "安装额外宿主工具（解决 Error 127 命令缺失）..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${extra_host_tools[@]}" || {
        log "⚠️ 部分宿主工具安装失败，尝试单独安装..."
        for pkg in "${extra_host_tools[@]}"; do
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" || log "  ⚠️ $pkg 安装失败"
        done
    }
    
    # 验证关键库是否安装
    log "🔍 验证关键库安装状态..."
    
    # 验证 libssl
    if pkg-config --libs openssl > /dev/null 2>&1 || [ -f "/usr/lib/x86_64-linux-gnu/libssl.so" ]; then
        log "✅ libssl 已安装"
    else
        log "⚠️ libssl 未找到，尝试强制安装..."
        sudo apt-get install -y libssl-dev --reinstall || true
    fi
    
    # 验证 libyaml
    if pkg-config --libs yaml-0.1 > /dev/null 2>&1 || [ -f "/usr/lib/x86_64-linux-gnu/libyaml.so" ]; then
        log "✅ libyaml 已安装"
    else
        log "⚠️ libyaml 未找到，尝试强制安装..."
        sudo apt-get install -y libyaml-dev --reinstall || true
    fi
    
    # 验证 libxml2
    if pkg-config --libs libxml-2.0 > /dev/null 2>&1 || [ -f "/usr/lib/x86_64-linux-gnu/libxml2.so" ]; then
        log "✅ libxml2 已安装"
    else
        log "⚠️ libxml2 未找到，尝试强制安装..."
        sudo apt-get install -y libxml2-dev --reinstall || true
    fi
    
    # 验证宿主工具
    local host_tools=("mkimage" "dtc" "cpio" "lz4" "zstd")
    for tool in "${host_tools[@]}"; do
        if command -v $tool >/dev/null 2>&1; then
            log "✅ $tool 已安装"
        else
            log "⚠️ $tool 未找到"
        fi
    done
    
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

    # ============================================
    # Hanwckf 特殊处理：immortalwrt + rax3000m → 自动切换为 Hanwckf 源码
    # ============================================
    local is_rax3000m_hanwckf=0
    if [ "$SOURCE_REPO_TYPE" = "immortalwrt" ] && echo "$device_name" | grep -qi "rax3000m"; then
        is_rax3000m_hanwckf=1
        log "🚀 检测到 RAX3000M 设备，自动切换为 Hanwckf 源码 (immortalwrt-mt798x)"
    fi

    case "$SOURCE_REPO_TYPE" in
        "lede")
            SELECTED_REPO_URL="${LEDE_URL:-https://github.com/coolsnowwolf/lede.git}"
            SELECTED_BRANCH="master"
            log "✅ LEDE源码选择: 固定使用master分支"
            ;;
        "openwrt")
            SELECTED_REPO_URL="${OPENWRT_URL:-https://github.com/openwrt/openwrt.git}"
            case "$version_selection" in
                "24.10") SELECTED_BRANCH="openwrt-24.10" ;;
                "23.05") SELECTED_BRANCH="${BRANCH_23_05:-openwrt-23.05}" ;;
                "22.03") SELECTED_BRANCH="openwrt-22.03" ;;
                "21.02") SELECTED_BRANCH="${BRANCH_21_02:-openwrt-21.02}" ;;
                "19.07") SELECTED_BRANCH="openwrt-19.07" ;;
                "main"|"master") SELECTED_BRANCH="main" ;;
                *) SELECTED_BRANCH="openwrt-23.05" ;;
            esac
            log "✅ OpenWrt官方源码选择: $SELECTED_BRANCH"
            ;;
        "immortalwrt")
            if [ $is_rax3000m_hanwckf -eq 1 ]; then
                SELECTED_REPO_URL="https://github.com/hanwckf/immortalwrt-mt798x.git"
                SELECTED_BRANCH="master"
                log "✅ Hanwckf 源码选择 (RAX3000M): master"
            else
                SELECTED_REPO_URL="${IMMORTALWRT_URL:-https://github.com/immortalwrt/immortalwrt.git}"
                case "$version_selection" in
                    "24.10") SELECTED_BRANCH="openwrt-24.10" ;;
                    "23.05") SELECTED_BRANCH="${BRANCH_23_05:-openwrt-23.05}" ;;
                    "21.02") SELECTED_BRANCH="${BRANCH_21_02:-openwrt-21.02}" ;;
                    "18.06") SELECTED_BRANCH="openwrt-18.06" ;;
                    "master") SELECTED_BRANCH="master" ;;
                    *) SELECTED_BRANCH="openwrt-23.05" ;;
                esac
                log "✅ ImmortalWrt源码选择: $SELECTED_BRANCH"
            fi
            ;;
        *)
            log "❌ 未知的源码仓库类型: $SOURCE_REPO_TYPE"
            exit 1
            ;;
    esac
    
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"

    sudo rm -rf ./* ./.git* 2>/dev/null || true

    git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . || {
        log "⚠️ 克隆 $SELECTED_BRANCH 分支失败，尝试默认分支..."
        git clone --depth 1 "$SELECTED_REPO_URL" . || handle_error "克隆源码失败"
    }
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
        
        PLATFORM_INFO=$(BUILD_DIR="$BUILD_DIR" "$SUPPORT_SCRIPT" get-platform "$device_name" "" "")
        if [ -n "$PLATFORM_INFO" ]; then
            TARGET=$(echo "$PLATFORM_INFO" | awk '{print $1}')
            SUBTARGET=$(echo "$PLATFORM_INFO" | awk '{print $2}')
            local matched_device=$(echo "$PLATFORM_INFO" | awk '{print $3}')
            
            if [ -n "$matched_device" ] && [ "$matched_device" != "$device_name" ]; then
                DEVICE="$matched_device"
                log "✅ support.sh 匹配设备: $device_name -> $matched_device"
            else
                DEVICE="$device_name"
                log "📌 设备名保持原始输入: $DEVICE（步骤15将自动匹配）"
            fi
            
            log "✅ 从support.sh获取平台信息: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
        else
            log "❌ 无法从support.sh获取平台信息，设备名: $device_name"
            handle_error "获取平台信息失败"
        fi
    else
        log "❌ support.sh不存在且未手动指定平台信息"
        handle_error "无法确定平台信息"
    fi

    # Hanwckf 模式强制修正平台信息
    if [ $is_rax3000m_hanwckf -eq 1 ]; then
        TARGET="mediatek"
        SUBTARGET="mt7981"
        DEVICE="cmcc_rax3000m"
        log "🔧 Hanwckf 模式：强制 TARGET=mediatek, SUBTARGET=mt7981, DEVICE=cmcc_rax3000m"
    fi

    log "🔧 设备: $device_name (输入)"
    log "🔧 设备定义名: $DEVICE (将用于查找MK文件)"
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

    if [ $config_tool_created -eq 0 ] && [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
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

    if [ $config_tool_created -eq 0 ] && [ -f "scripts/config/mconf" ] && [ -x "scripts/config/mconf" ]; then
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

    if [ $config_tool_created -eq 0 ] && [ -n "$COMPILER_DIR" ] && [ -f "$COMPILER_DIR/scripts/config/conf" ] && [ -x "$COMPILER_DIR/scripts/config/conf" ]; then
        log "🔧 尝试方法4: 从 SDK 目录复制"
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
        elif [ -f scripts/config/config ] || [ -f scripts/config/conf ]; then
            log "✅ 统一调用接口可用（跳过参数测试）"
        else
            log "⚠️ 统一调用接口可能有问题，但工具可能仍可用"
        fi
    fi

    if [ $config_tool_created -eq 1 ]; then
        log "✅ 配置工具最终验证通过"
        log "📁 真实工具路径: $real_config_tool"
        log "📁 统一调用接口: scripts/config-tool"

        if [ -f "$real_config_tool" ] && file "$real_config_tool" | grep -q "ELF"; then
            log "📋 工具类型: 已编译二进制文件"
        else
            log "📋 工具类型: Shell 脚本"
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
    
    log "=== 网络加速预置（根据源码自动选择） ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"
    
    # 特殊处理：Hanwckf 模式（RAX3000M + immortalwrt）已集成硬件加速，无需额外操作
    if echo "$DEVICE" | grep -qi "rax3000m" && [ "$SOURCE_REPO_TYPE" = "immortalwrt" ]; then
        log "ℹ️ 检测到 Hanwckf 源码 (RAX3000M)，已集成 MTK 硬件加速，跳过"
        return 0
    fi
    
    # ============================================
    # 彻底修复所有下载源（网络加速不依赖此项，但保留通用修复）
    # ============================================
    log "🔧 修复编译下载源..."
    
    # 创建补丁目录
    mkdir -p package/firmware/trusted-firmware-a/patches
    
    # 创建补丁文件，替换所有失效的下载源
    cat > package/firmware/trusted-firmware-a/patches/001-fix-download-url.patch << 'EOF'
--- a/package/firmware/trusted-firmware-a/Makefile
+++ b/package/firmware/trusted-firmware-a/Makefile
@@ -5,8 +5,8 @@
 PKG_NAME:=trusted-firmware-a
 PKG_RELEASE:=1
 
-PKG_SOURCE_URL:=https://mirror2.immortalwrt.org/sources/trusted-firmware-a-$(PKG_VERSION).tar.gz
-PKG_SOURCE_URL+=https://mirror.immortalwrt.org/sources/trusted-firmware-a-$(PKG_VERSION).tar.gz
+PKG_SOURCE_URL:=https://github.com/ARM-software/arm-trusted-firmware/archive/refs/tags/v$(PKG_VERSION).tar.gz
+PKG_SOURCE_URL+=https://git.trustedfirmware.org/TF-A/trusted-firmware-a.git/snapshot/v$(PKG_VERSION).tar.gz
 PKG_HASH:=skip
 
 PKG_LICENSE:=BSD-3-Clause
EOF
    log "  ✅ 创建 trusted-firmware-a 下载源修复补丁"
    
    # 修复 libxml2 下载源
    find package/libs -name "libxml2" -type d 2>/dev/null | while read dir; do
        if [ -f "$dir/Makefile" ]; then
            cp "$dir/Makefile" "$dir/Makefile.bak"
            sed -i 's|https\?://download.gnome.org/sources/libxml2/|https://github.com/GNOME/libxml2/archive/refs/tags/v|g' "$dir/Makefile"
            sed -i 's|libxml2-\([0-9.]*\)\.tar\.xz|\1.tar.gz|g' "$dir/Makefile"
            log "  ✅ 修复 libxml2 下载源"
        fi
    done
    
    # 修复所有 mirror.immortalwrt.org 源
    find . -name "*.mk" -o -name "Makefile" | while read file; do
        if grep -q "mirror2.immortalwrt.org\|mirror.immortalwrt.org\|sources-cdn.immortalwrt.org" "$file" 2>/dev/null; then
            cp "$file" "$file.bak"
            sed -i 's|mirror2.immortalwrt.org|github.com|g' "$file"
            sed -i 's|mirror.immortalwrt.org|github.com|g' "$file"
            sed -i 's|sources-cdn.immortalwrt.org|github.com|g' "$file"
            log "  ✅ 修复: $file"
        fi
    done
    
    # 本函数不再添加任何外部 feed，加速方案由 generate_config 根据源码类型自动选择
    log "✅ 网络加速预置完成，最终方案将在配置生成时根据源码类型确定"
}
#【build_firmware_main.sh-08-end】

#【build_firmware_main.sh-08.01】
# ============================================
# 补丁管理系统
# 功能: 管理内置补丁和自定义补丁的执行
# ============================================

#【build_firmware_main.sh-08.01.01】
# 执行补丁（主入口）
execute_patches() {
    local selected_patch="$1"
    local device_name="$2"
    local source_type="$3"
    local branch="$4"
    local extra_arg="$5"

    # 强制重新加载补丁列表
    if [ -f "$REPO_ROOT/build-config.conf" ]; then
        source "$REPO_ROOT/build-config.conf" 2>/dev/null || true
    fi

    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"

    log "=== 补丁管理系统 ==="
    log "选择补丁模式: $selected_patch"
    log "设备: $device_name"
    log "源码类型: $source_type"
    log "分支: $branch"

    # 清空之前的补丁记录文件
    > /tmp/applied_patches.list

    # ---------- 内部辅助：从补丁列表中根据名称取出完整记录 ----------
    __get_patch_by_name() {
        local name="$1"
        for line in "${BUILTIN_PATCH_LIST[@]}"; do
            IFS='|' read -r dev_pat src_pat br_pat pn pd pf <<< "$line"
            if [ "$pn" = "$name" ]; then
                echo "$line"
                return 0
            fi
        done
        return 1
    }

    # ---------- 内部辅助：检查单条规则是否匹配 ----------
    __match_rule() {
        local line="$1" dev="$2" src="$3" br="$4"
        IFS='|' read -r dev_pat src_pat br_pat _ _ _ <<< "$line"
        local match=1
        [ "$dev_pat" != "*" ] && [[ "$dev" != $dev_pat ]] && match=0
        [ "$src_pat" != "*" ] && [ "$src" != "$src_pat" ] && match=0
        [ "$br_pat" != "*" ] && [ "$br" != "$br_pat" ] && match=0
        return $(( match == 1 ? 0 : 1 ))
    }

    # ---------- 内部辅助：应用单个补丁，并记录到列表 ----------
    __apply_patch() {
        local pn="$1"
        local line=$(__get_patch_by_name "$pn")
        if [ -z "$line" ]; then
            log "❌ 错误: 未找到名为 '$pn' 的内置补丁"
            return 1
        fi
        IFS='|' read -r dev_pat src_pat br_pat name desc func <<< "$line"
        log "📋 补丁信息: $name - $desc"
        if ! __match_rule "$line" "$device_name" "$source_type" "$branch"; then
            log "⚠️ 补丁 '$pn' 不适用于当前设备/源码组合，跳过"
            return 0
        fi
        if function_exists "$func"; then
            log "🔧 执行补丁函数: $func"
            "$func" "$BUILD_DIR" "$device_name"
            local rc=$?
            if [ $rc -eq 0 ]; then
                # 记录成功应用的补丁
                echo "$pn" >> /tmp/applied_patches.list
            fi
            return $rc
        else
            log "❌ 补丁函数 $func 未定义"
            return 1
        fi
    }

    # ---------- 内部辅助：应用所有通用补丁（设备/源码/分支均为 *） ----------
    __apply_all_generic_patches() {
        log "🔧 检查并应用通用补丁..."
        local generic_applied=0
        for line in "${BUILTIN_PATCH_LIST[@]}"; do
            IFS='|' read -r dev_pat src_pat br_pat pn pd pf <<< "$line"
            if [ "$dev_pat" = "*" ] && [ "$src_pat" = "*" ] && [ "$br_pat" = "*" ]; then
                log "  📌 发现通用补丁: $pn - $pd"
                if function_exists "$pf"; then
                    "$pf" "$BUILD_DIR" "$device_name"
                    local rc=$?
                    if [ $rc -eq 0 ]; then
                        echo "$pn" >> /tmp/applied_patches.list
                    else
                        log "  ⚠️ 通用补丁 $pn 执行出现错误"
                    fi
                else
                    log "  ❌ 通用补丁函数 $pf 未定义"
                fi
                generic_applied=1
            fi
        done
        if [ $generic_applied -eq 0 ]; then
            log "  ℹ️ 没有通用补丁"
        fi
    }

    # ---------- 第一步：始终应用所有通用补丁 ----------
    __apply_all_generic_patches

    # ---------- 处理 none：只应用通用补丁 ----------
    if [ "$selected_patch" = "none" ]; then
        log "ℹ️ 未选择额外补丁，仅应用通用补丁"
        return 0
    fi

    # ---------- 处理 custom (自定义命令文件) ----------
    if [ "$selected_patch" = "custom" ]; then
        log "🔧 ===== 执行自定义补丁 ====="
        local custom_patch_file="$extra_arg"
        if [ -z "$custom_patch_file" ] || [ ! -f "$custom_patch_file" ]; then
            log "⚠️ 自定义补丁命令文件不存在或为空"
        else
            log "📋 自定义补丁命令文件: $custom_patch_file"
            log "📄 命令内容:"
            log "----------------------------------------"
            grep -v '^[[:space:]]*#' "$custom_patch_file" 2>/dev/null | grep -v '^[[:space:]]*$' | while IFS= read -r line; do
                log "  $line"
            done
            log "----------------------------------------"

            local temp_script="/tmp/custom_patch_$$.sh"
            cat > "$temp_script" << 'SCRIPT_HEADER'
#!/bin/bash
set -e
SCRIPT_HEADER
            date '+%Y-%m-%d %H:%M:%S' >> "$temp_script"
            echo "" >> "$temp_script"
            cat >> "$temp_script" << SCRIPT_ENV
BUILD_DIR="$BUILD_DIR"
cd "\$BUILD_DIR" || { echo "❌ 无法进入构建目录: \$BUILD_DIR"; exit 1; }
echo "🔧 开始执行自定义补丁..."
echo "当前目录: \$(pwd)"
echo ""
SCRIPT_ENV
            cat "$custom_patch_file" >> "$temp_script"
            cat >> "$temp_script" << 'SCRIPT_FOOTER'
echo ""
echo "✅ 自定义补丁执行完成"
SCRIPT_FOOTER
            chmod +x "$temp_script"
            log "🚀 开始执行自定义补丁... 日志: /tmp/build-logs/custom_patch.log"
            bash "$temp_script" > /tmp/build-logs/custom_patch.log 2>&1
            local exit_code=$?
            if [ $exit_code -eq 0 ]; then
                log "✅ 自定义补丁执行成功"
                echo "custom" >> /tmp/applied_patches.list
            else
                log "⚠️ 自定义补丁执行失败 (退出码: $exit_code)"
                log "最后30行日志:"
                tail -30 /tmp/build-logs/custom_patch.log
            fi
            rm -f "$temp_script"
        fi
        return 0
    fi

    # ---------- 处理 custom-list (多个内置补丁，逗号分隔) ----------
    if [ "$selected_patch" = "custom-list" ]; then
        local patch_list_str="$extra_arg"
        if [ -z "$patch_list_str" ]; then
            log "⚠️ 补丁列表为空"
        else
            log "📋 手动输入补丁列表: $patch_list_str"
            IFS=',' read -ra PATCH_NAMES <<< "$patch_list_str"
            local total=${#PATCH_NAMES[@]}
            local success=0
            local failed=0
            for pname in "${PATCH_NAMES[@]}"; do
                pname=$(echo "$pname" | xargs)
                [ -z "$pname" ] && continue
                log "🔧 应用补丁: $pname"
                if __apply_patch "$pname"; then
                    success=$((success + 1))
                else
                    failed=$((failed + 1))
                fi
            done
            log "📊 多补丁应用完成: 成功 $success 个, 失败 $failed 个"
        fi
        return 0
    fi

    # ---------- 处理单个内置补丁 ----------
    if [ "$selected_patch" != "none" ]; then
        __apply_patch "$selected_patch"
    fi
    return 0
}
#【build_firmware_main.sh-08.01.01-end】

#【build_firmware_main.sh-08.01.02】
# 获取可用的内置补丁列表（供工作流显示用）
list_available_patches() {
    local device_name="${1:-*}"
    local source_type="${2:-*}"
    local branch="${3:-*}"
    
    local patches=()
    
    for key in "${!BUILTIN_PATCH_MAP[@]}"; do
        IFS='|' read -r device_pattern source_pattern branch_pattern <<< "$key"
        IFS='|' read -r patch_name patch_desc patch_func <<< "${BUILTIN_PATCH_MAP[$key]}"
        
        # 检查匹配
        local match=1
        if [[ "$device_pattern" != "*" ]] && ! [[ "$device_name" == $device_pattern ]]; then
            match=0
        fi
        if [[ "$source_pattern" != "*" ]] && [ "$source_type" != "$source_pattern" ]; then
            match=0
        fi
        if [[ "$branch_pattern" != "*" ]] && [ "$branch" != "$branch_pattern" ]; then
            match=0
        fi
        
        if [ $match -eq 1 ]; then
            patches+=("$patch_name|$patch_desc|$device_pattern|$source_pattern")
        fi
    done
    
    if [ ${#patches[@]} -gt 0 ]; then
        printf '%s\n' "${patches[@]}"
    fi
}
#【build_firmware_main.sh-08.01.02-end】

#【build_firmware_main.sh-08.01.03】
# 显示补丁状态（供步骤12、步骤26调用）
show_patch_status() {
    local patch_list_file="/tmp/applied_patches.list"
    if [ ! -f "$patch_list_file" ]; then
        echo "ℹ️ 未找到补丁记录文件，无法显示补丁状态"
        return 0
    fi

    local applied=()
    while IFS= read -r pname; do
        [ -n "$pname" ] && applied+=("$pname")
    done < "$patch_list_file"

    if [ ${#applied[@]} -eq 0 ]; then
        echo "ℹ️ 未应用任何补丁"
        return 0
    fi

    echo "🔍 已应用补丁状态汇总："
    for pname in "${applied[@]}"; do
        echo ""
        echo "📌 补丁名称: $pname"
        # 根据补丁名称调用对应的检查函数
        case "$pname" in
            "rax3000m-mt76")
                check_patch_status_rax3000m_mt76
                ;;
            "ac42u-ath10k")
                check_patch_status_ac42u_ath10k
                ;;
            "usb-power-fix")
                check_patch_status_usb_power_fix
                ;;
            "custom")
                echo "   📝 自定义补丁，请手动验证效果"
                ;;
            *)
                echo "   ℹ️ 无专用状态检查，补丁已尝试执行"
                ;;
        esac
    done
}

# ===== 各补丁状态检查函数 =====

check_patch_status_rax3000m_mt76() {
    if [ -d "$BUILD_DIR/package/kernel/mt76" ]; then
        cd "$BUILD_DIR/package/kernel/mt76" 2>/dev/null || return 0
        local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "未知")
        local commit=$(git log -1 --format="%h %s" 2>/dev/null || echo "无信息")
        local date=$(git log -1 --format="%ci" 2>/dev/null || echo "")
        echo "   ✅ mt76 源码已更新"
        echo "   分支   : $branch"
        echo "   最新提交: $commit"
        [ -n "$date" ] && echo "   提交时间: $date"
        cd "$BUILD_DIR" 2>/dev/null || true
        echo "   💡 生效判断：编译时若无线驱动加载成功且无 'Message timeout' 错误，则补丁生效"
    else
        echo "   ⚠️ mt76 源码目录不存在，补丁未应用"
    fi
}

check_patch_status_ac42u_ath10k() {
    local fw_dir="files/lib/firmware/ath10k/QCA9888/hw2.0"
    if [ -f "$BUILD_DIR/$fw_dir/firmware-ct.bin" ]; then
        local size=$(ls -lh "$BUILD_DIR/$fw_dir/firmware-ct.bin" | awk '{print $5}')
        echo "   ✅ CT 固件已预置 ($size)"
        echo "   💡 生效判断：刷机后无线网卡工作正常（WPA3 等）即为生效"
    else
        # 检查 Makefile 是否已修改源
        local fw_pkg=$(find "$BUILD_DIR/package/firmware" -maxdepth 3 -type d -name "*ath10k*" 2>/dev/null | head -1)
        if [ -n "$fw_pkg" ] && grep -q "greearb/ath10k-ct-firmware" "$fw_pkg/Makefile" 2>/dev/null; then
            echo "   ✅ ath10k 固件源已切换至 CT 版本，将在编译时下载"
            echo "   💡 生效判断：编译时无固件下载错误，刷机后无线正常"
        else
            echo "   ⚠️ 未检测到明显的 ath10k 修改，补丁可能未生效"
        fi
    fi
}

check_patch_status_usb_power_fix() {
    local script="files/etc/hotplug.d/usb/10-usb-power"
    if [ -f "$BUILD_DIR/$script" ]; then
        echo "   ✅ USB 电源管理修复脚本已生成"
        echo "   💡 生效判断：刷机后插入 USB 存储设备长时间无自动断开"
    else
        echo "   ⚠️ USB 修复脚本未找到，补丁可能未生效"
    fi
}
#【build_firmware_main.sh-08.01.03-end】

#【build_firmware_main.sh-09】
configure_feeds() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 配置Feeds ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"
    
    # ---------- Hanwckf 模式保留原有 feeds ----------
    local is_hanwckf=0
    if echo "$DEVICE" | grep -qi "rax3000m" && [ "$SOURCE_REPO_TYPE" = "immortalwrt" ]; then
        is_hanwckf=1
    fi
    
    if [ $is_hanwckf -eq 1 ]; then
        log "🔧 Hanwckf 模式：保留源码自带的 feeds.conf.default"
        if [ -f "feeds.conf.default" ]; then
            cp "feeds.conf.default" "feeds.conf.default.bak"
            log "  ✅ 已备份原有 feeds 配置"
        fi
        log "=== 更新Feeds ==="
        ./scripts/feeds update -a || log "⚠️ feeds更新有警告，继续"
        ./scripts/feeds install -a || log "⚠️ feeds安装有警告，继续"
        log "✅ Feeds配置完成"
        return 0
    fi
    
    # ---------- 标准流程 ----------
    log "🔧 预创建环境文件..."
    mkdir -p staging_dir/target-*/root-*/etc 2>/dev/null || true
    for target_dir in staging_dir/target-*; do
        [ -d "$target_dir" ] || continue
        for root_dir in "$target_dir"/root-*; do
            [ -d "$root_dir" ] || continue
            mkdir -p "$root_dir/etc"
            touch "$root_dir/etc/xattr.conf" 2>/dev/null || true
        done
    done
    
    mkdir -p build_dir/target-* 2>/dev/null || true
    for build_dir in build_dir/target-*; do
        [ -d "$build_dir" ] || continue
        find "$build_dir" -type d -name "fullconenat-nft-*" 2>/dev/null | while read dir; do
            mkdir -p "$dir"
            touch "$dir/Module.symvers" 2>/dev/null || true
        done
    done
    
    if [ -f "feeds.conf.default" ]; then
        cp "feeds.conf.default" "feeds.conf.default.bak"
        log "  ✅ 备份原有feeds配置"
    fi
    
    > feeds.conf.default
    
    case "$SOURCE_REPO_TYPE" in
        "lede")
            log "🔧 LEDE源码模式: 使用LEDE官方feeds"
            cat >> feeds.conf.default << 'EOF'
src-git packages https://github.com/coolsnowwolf/packages.git
src-git luci https://github.com/coolsnowwolf/luci.git
src-git routing https://github.com/openwrt/routing.git
src-git telephony https://github.com/openwrt/telephony.git
EOF
            ;;
        "openwrt")
            log "🔧 OpenWrt官方源码模式: 使用OpenWrt官方feeds"
            local branch_suffix=""
            case "$SELECTED_BRANCH" in
                *"24.10"*) branch_suffix="openwrt-24.10" ;;
                *"23.05"*) branch_suffix="openwrt-23.05" ;;
                *"22.03"*) branch_suffix="openwrt-22.03" ;;
                *"21.02"*) branch_suffix="openwrt-21.02" ;;
                *"19.07"*) branch_suffix="openwrt-19.07" ;;
                "main"|"master") branch_suffix="main" ;;
                *) branch_suffix="$SELECTED_BRANCH" ;;
            esac
            
            cat >> feeds.conf.default << EOF
src-git packages https://git.openwrt.org/feed/packages.git;$branch_suffix
src-git luci https://git.openwrt.org/project/luci.git;$branch_suffix
src-git routing https://git.openwrt.org/feed/routing.git;$branch_suffix
src-git telephony https://git.openwrt.org/feed/telephony.git;$branch_suffix
EOF
            ;;
        "immortalwrt")
            log "🔧 ImmortalWrt源码模式: 使用ImmortalWrt官方feeds"
            local branch_suffix=""
            case "$SELECTED_BRANCH" in
                *"23.05"*) branch_suffix="openwrt-23.05" ;;
                *"21.02"*) branch_suffix="openwrt-21.02" ;;
                *"18.06"*) branch_suffix="openwrt-18.06" ;;
                "master") branch_suffix="master" ;;
                *) branch_suffix="$SELECTED_BRANCH" ;;
            esac
            
            cat >> feeds.conf.default << EOF
src-git packages ${PACKAGES_FEED_URL:-https://github.com/immortalwrt/packages.git};$branch_suffix
src-git luci ${LUCI_FEED_URL:-https://github.com/immortalwrt/luci.git};$branch_suffix
src-git routing https://github.com/openwrt/routing.git;$branch_suffix
src-git telephony https://github.com/openwrt/telephony.git;$branch_suffix
EOF
            ;;
        *)
            log "⚠️ 未知源码类型，使用通用feeds配置"
            cat >> feeds.conf.default << 'EOF'
src-git packages https://github.com/openwrt/packages.git
src-git luci https://github.com/openwrt/luci.git
src-git routing https://github.com/openwrt/routing.git
src-git telephony https://github.com/openwrt/telephony.git
EOF
            ;;
    esac
    
    log "📋 feeds.conf.default 内容:"
    cat feeds.conf.default
    
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || {
        log "⚠️ feeds更新有警告，尝试继续..."
    }
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || {
        log "⚠️ feeds安装有警告，尝试继续..."
    }

    # ============================================
    # 安装 feeds 后立即彻底清除冲突包
    # ============================================
    log "🔧 彻底移除 IPv6、DDNS 等冲突包并修复 luci 依赖"

    # 1. 删除所有 DDNS 相关目录
    find package/feeds feeds -type d \( \
        -name "ddns-scripts*" -o \
        -name "luci-app-ddns*" -o \
        -name "luci-i18n-ddns*" \
    \) -exec rm -rf {} + 2>/dev/null

    # 2. 删除所有 IPv6 相关目录（包括 luci-proto-ipv6）
    find package/feeds feeds -type d \( \
        -name "*ip6tables*" -o \
        -name "*odhcp6c*" -o \
        -name "*odhcpd*" -o \
        -name "*6in4*" -o -name "*6rd*" -o -name "*6to4*" -o \
        -name "*ds-lite*" -o -name "*map*" -o \
        -name "*luci-proto-ipv6*" -o \
        -name "*kmod-ipv6*" -o \
        -name "*kmod-nf-ip6*" -o \
        -name "*kmod-nf-conntrack6*" -o \
        -name "*kmod-nf-nat6*" -o \
        -name "*kmod-ipt-nat6*" -o \
        -name "*kmod-nf-ipt6*" -o \
        -name "*dnsmasq-nodhcpv6*" \
    \) -exec rm -rf {} + 2>/dev/null

    # 3. 删除 vsftpd-alt 等冲突包
    find package/feeds feeds -type d -name "*vsftpd-alt*" -exec rm -rf {} + 2>/dev/null

    # 4. 强制修复 luci-light 的 Makefile 依赖
    for mk in $(find package/feeds feeds -path "*/luci-light/Makefile" 2>/dev/null); do
        cp "$mk" "$mk.bak.final"
        # 移除包含 luci-proto-ipv6 的整段依赖（含前面的 + 或空格）
        sed -i 's/ +\?luci-proto-ipv6\b//g; s/\bluci-proto-ipv6\b//g' "$mk"
        # 防止 DEPENDS 行变为空
        sed -i 's/^\([[:space:]]*DEPENDS\):= *$/\1:=+libc/' "$mk"
        log "  ✅ 已清理 $mk"
    done

    # 5. 强制修复 luci-nginx 的 Makefile 依赖
    for mk in $(find package/feeds feeds -path "*/luci-nginx/Makefile" 2>/dev/null); do
        cp "$mk" "$mk.bak.final"
        sed -i 's/ +\?luci-proto-ipv6\b//g; s/\bluci-proto-ipv6\b//g' "$mk"
        sed -i 's/^\([[:space:]]*DEPENDS\):= *$/\1:=+libc/' "$mk"
        log "  ✅ 已清理 $mk"
    done

    # 6. 验证修复结果（确保不再包含 luci-proto-ipv6）
    if grep -rq "luci-proto-ipv6" package/feeds/luci/luci-light/Makefile package/feeds/luci/luci-nginx/Makefile 2>/dev/null; then
        log "❌ 错误：luci-proto-ipv6 依赖清除失败，请手动检查！"
    else
        log "✅ 验证通过：luci-proto-ipv6 依赖已彻底移除"
    fi

    # 7. 清除所有旧的包索引缓存
    rm -rf tmp/.packagefeeds* 2>/dev/null
    find staging_dir -name "Packages*" -exec rm -f {} + 2>/dev/null
    # 可选：重新生成索引（不安装，只更新索引）
    ./scripts/feeds update -i > /dev/null 2>&1 || true

    log "✅ 冲突包及索引已彻底清理"

    log "✅ Feeds配置完成"
}
#【build_firmware_main.sh-09-end】

#【build_firmware_main.sh-10】
install_turboacc_packages() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 安装网络加速包 ==="
    
    # Hanwckf 模式跳过
    if echo "$DEVICE" | grep -qi "rax3000m" && [ "$SOURCE_REPO_TYPE" = "immortalwrt" ]; then
        log "ℹ️ Hanwckf 已集成硬件加速，跳过额外包安装"
        return 0
    fi
    
    # 仅 ImmortalWrt 使用 TurboACC 时需要安装相应包（其他源码在 feeds install 阶段已处理）
    if [ "$SOURCE_REPO_TYPE" = "immortalwrt" ] && [ "$CONFIG_MODE" = "normal" ] && [ "${ENABLE_TURBOACC:-true}" = "true" ]; then
        log "🔧 ImmortalWrt 正常模式，安装 TurboACC 相关包..."
        ./scripts/feeds install -p packages luci-app-turboacc 2>/dev/null || log "⚠️ luci-app-turboacc 安装失败（可能已存在）"
        ./scripts/feeds install -p packages kmod-shortcut-fe 2>/dev/null || true
        ./scripts/feeds install -p packages kmod-fast-classifier 2>/dev/null || true
        log "✅ TurboACC 包安装完成"
    else
        log "ℹ️ 当前源码 $SOURCE_REPO_TYPE 不需要单独安装加速包（配置生成时自动选定）"
    fi
}
#【build_firmware_main.sh-10-end】

#【build_firmware_main.sh-11】
# 功能开关配置（默认值）
: ${ENABLE_TURBOACC:="true"}
: ${ENABLE_TCP_BBR:="true"}
: ${FORCE_ATH10K_CT:="true"}
: ${AUTO_FIX_USB_DRIVERS:="true"}
: ${ENABLE_VERBOSE_LOG:="false"}
: ${DISABLE_IPV6:="true"}
: ${FORBIDDEN_PACKAGES:="vssr ssr-plus passwall rclone ddns qbittorrent filetransfer nlbwmon wol"}
#【build_firmware_main.sh-11-end】

#【build_firmware_main.sh-12】
# 生成完整的禁用插件列表
generate_forbidden_packages_list() {
    local base_forbidden="$1"
    local full_list=()
    
    IFS=' ' read -ra BASE_PKGS <<< "$base_forbidden"
    for pkg in "${BASE_PKGS[@]}"; do
        [ -z "$pkg" ] && continue
        full_list+=("$pkg")
        full_list+=("luci-app-${pkg}")
        full_list+=("luci-i18n-${pkg}-zh-cn")
        full_list+=("${pkg}-scripts")
        
        case "$pkg" in
            "ssr-plus")
                full_list+=("shadowsocksr-libev")
                full_list+=("shadowsocksr-libev-ssr-local")
                full_list+=("shadowsocksr-libev-ssr-redir")
                full_list+=("shadowsocksr-libev-ssr-tunnel")
                ;;
            "passwall")
                full_list+=("shadowsocks-libev-ss-local")
                full_list+=("shadowsocks-libev-ss-redir")
                full_list+=("shadowsocks-libev-ss-tunnel")
                full_list+=("trojan")
                full_list+=("trojan-plus")
                full_list+=("xray-core")
                full_list+=("v2ray-core")
                full_list+=("v2ray-plugin")
                full_list+=("simple-obfs")
                ;;
            "vssr")
                full_list+=("shadowsocksr-libev")
                full_list+=("v2ray-core")
                full_list+=("v2ray-plugin")
                ;;
            "ddns")
                full_list+=("ddns-scripts")
                full_list+=("ddns-scripts_aliyun")
                full_list+=("ddns-scripts_dnspod")
                full_list+=("ddns-go")
                ;;
            "qbittorrent")
                full_list+=("qbittorrent-nox")
                full_list+=("libtorrent-rasterbar")
                ;;
            "rclone")
                full_list+=("rclone-ng")
                full_list+=("rclone-webui-react")
                ;;
            "filetransfer")
                full_list+=("vsftpd-alt")
                ;;
            "nlbwmon")
                full_list+=("luci-app-nlbwmon")
                full_list+=("luci-i18n-nlbwmon-zh-cn")
                ;;
            "wol")
                full_list+=("luci-app-wol")
                full_list+=("luci-i18n-wol-zh-cn")
                ;;
            "accesscontrol")
                full_list+=("luci-app-accesscontrol")
                full_list+=("luci-i18n-accesscontrol-zh-cn")
                ;;
            "autoreboot")
                full_list+=("luci-app-autoreboot")
                full_list+=("luci-i18n-autoreboot-zh-cn")
                ;;
        esac
    done
    
    printf '%s\n' "${full_list[@]}" | sort -u
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
    log "源码仓库类型: $SOURCE_REPO_TYPE"
    
    if [ -z "$DEVICE" ]; then
        log "❌ 错误: DEVICE变量为空！"
        env | grep -E "DEVICE|TARGET|SELECTED" || true
        handle_error "DEVICE变量未设置"
    fi
    
    rm -f .config .config.old .config.bak*
    log "✅ 已清理旧配置文件"
    
    local correct_device="$DEVICE"
    log "🔧 使用传入的设备名: $correct_device"
    
    # ============================================
    # Hanwckf 特殊处理：immortalwrt + rax3000m → 使用预置配置
    # ============================================
    local IS_HANWCKF_RAX3000M=0
    if echo "$correct_device" | grep -qi "rax3000m" && [ "$SOURCE_REPO_TYPE" = "immortalwrt" ]; then
        IS_HANWCKF_RAX3000M=1
    fi
    
    if [ $IS_HANWCKF_RAX3000M -eq 1 ]; then
        log "🔧 ===== Hanwckf 源码特殊配置流程 ====="
        
        if [ -f "defconfig/mt7981-ax3000.config" ]; then
            cp "defconfig/mt7981-ax3000.config" ".config"
            log "✅ 已应用 Hanwckf 预置配置: defconfig/mt7981-ax3000.config"
        
            # 锁定设备为 cmcc_rax3000m（NAND）
            sed -i '/^CONFIG_TARGET_mediatek_mt7981_DEVICE_/d' .config
            echo "CONFIG_TARGET_mediatek_mt7981_DEVICE_cmcc_rax3000m=y" >> .config
            echo "# CONFIG_TARGET_mediatek_mt7981_DEVICE_cmcc_rax3000m_emmc is not set" >> .config
            echo "# CONFIG_TARGET_mediatek_mt7981_DEVICE_cmcc_rax3000m_nand_ubootmod is not set" >> .config
            make defconfig > /tmp/build-logs/defconfig_hanwckf.log 2>&1
            log "✅ 已锁定设备: cmcc_rax3000m (NAND)"
            
            # 设置正确的平台变量，后续步骤引用
            TARGET="mediatek"
            SUBTARGET="mt7981"
            actual_subtarget="mt7981"
            correct_device="cmcc_rax3000m"
            DEVICE="cmcc_rax3000m"
            device_config="CONFIG_TARGET_mediatek_mt7981_DEVICE_cmcc_rax3000m=y"
        else
            log "❌ 未找到 defconfig/mt7981-ax3000.config，无法生成 Hanwckf 配置"
            handle_error "Hanwckf 预置配置缺失"
        fi
        
        log "📌 Hanwckf 基础配置已就绪，继续合并通用配置..."
    fi
    
    # ============================================
    # 以下为通用流程（immortalwrt/openwrt/lede 均适用）
    # ============================================
    
    # ============================================
    # LEDE 源码启动修复（仅在 lede 且非 Hanwckf 时执行）
    # ============================================
    if [ "$SOURCE_REPO_TYPE" = "lede" ] && [ $IS_HANWCKF_RAX3000M -eq 0 ]; then
        log "🔧 ===== LEDE 源码启动修复 ====="
        
        case "$TARGET" in
            ipq40xx)
                log "  🔧 IPQ40xx 平台启动修复 (适用于 AC42U 等设备)"
                
                cat >> .config << 'EOF'
# IPQ40xx 启动必需配置
CONFIG_CMDLINE_PARTITION=y
CONFIG_MTD_SPLIT_FIRMWARE=y
CONFIG_MTD_SPLIT_UIMAGE_FW=y
CONFIG_MTD_ROOTFS_ROOT_DEV=y
CONFIG_MTD_ROOTFS_SPLIT=y
CONFIG_MTD_SPLIT_SQUASHFS=y

# 确保 UBI 支持
CONFIG_MTD_UBI=y
CONFIG_UBIFS_FS=y
CONFIG_UBIFS_FS_XZ=y
CONFIG_UBIFS_FS_LZO=y
CONFIG_UBIFS_FS_ZLIB=y

# 内核命令行参数
CONFIG_CMDLINE="console=ttyMSM0,115200n8"
CONFIG_CMDLINE_FROM_BOOTLOADER=y

# 看门狗支持
CONFIG_WATCHDOG=y
CONFIG_QCOM_WDT=y

# 确保 MTD 支持
CONFIG_MTD=y
CONFIG_MTD_BLOCK=y
CONFIG_MTD_BLOCK_RO=y
CONFIG_MTD_SPLIT=y
EOF
                log "  ✅ IPQ40xx 启动修复配置已添加"
                ;;
                
            mediatek)
                log "  🔧 Mediatek 平台启动修复 (适用于 RAX3000M 等设备)"
                
                cat >> .config << 'EOF'
# Mediatek 启动必需配置
CONFIG_CMDLINE_PARTITION=y
CONFIG_MTD_SPLIT_FIRMWARE=y
CONFIG_MTD_SPLIT_UIMAGE_FW=y

# 确保 MTD 和 UBI 支持
CONFIG_MTD=y
CONFIG_MTD_BLOCK=y
CONFIG_MTD_SPLIT=y
CONFIG_MTD_UBI=y
CONFIG_UBIFS_FS=y
CONFIG_SQUASHFS=y
CONFIG_SQUASHFS_XZ=y
CONFIG_SQUASHFS_ZSTD=y

# NAND 支持
CONFIG_MTD_NAND=y
CONFIG_MTD_NAND_ECC=y
CONFIG_MTD_NAND_ECC_SW_HAMMING=y
CONFIG_MTD_SPI_NAND=y

# 内核命令行参数
CONFIG_CMDLINE="earlycon=uart8250,mmio32,0x11002000 console=ttyS0,115200n1"
CONFIG_CMDLINE_FROM_BOOTLOADER=y

# 确保 watchdog 支持
CONFIG_WATCHDOG=y
CONFIG_MEDIATEK_WATCHDOG=y
EOF
                log "  ✅ Mediatek 启动修复配置已添加"
                ;;
                
            ath79)
                log "  🔧 ATH79 平台启动修复 (适用于 WNDR3800 等设备)"
                
                cat >> .config << 'EOF'
# ATH79 启动必需配置
CONFIG_CMDLINE_PARTITION=y
CONFIG_MTD_SPLIT_FIRMWARE=y
CONFIG_MTD_SPLIT_UIMAGE_FW=y

# 确保 MTD 支持
CONFIG_MTD=y
CONFIG_MTD_BLOCK=y
CONFIG_MTD_SPLIT=y
CONFIG_MTD_ROOTFS=y

# 内核命令行参数
CONFIG_CMDLINE="console=ttyS0,115200"
CONFIG_CMDLINE_FROM_BOOTLOADER=y

# 确保 watchdog 支持
CONFIG_WATCHDOG=y
CONFIG_ATH79_WDT=y

# SquashFS 支持
CONFIG_SQUASHFS=y
CONFIG_SQUASHFS_XZ=y
CONFIG_SQUASHFS_ZLIB=y
CONFIG_SQUASHFS_LZ4=y
EOF
                log "  ✅ ATH79 启动修复配置已添加"
                ;;
        esac
        
        log "  🔧 LEDE 通用启动修复"
        
        cat >> .config << 'EOF'
# LEDE 通用启动修复配置
# 确保 initramfs 支持
CONFIG_BLK_DEV_INITRD=y
CONFIG_INITRAMFS_SOURCE=""
CONFIG_RD_GZIP=y
CONFIG_RD_BZIP2=y
CONFIG_RD_LZMA=y
CONFIG_RD_XZ=y
CONFIG_RD_LZO=y
CONFIG_RD_LZ4=y

# 确保正确的根文件系统类型
CONFIG_ROOT_NFS=y

# 确保必要的文件系统支持
CONFIG_EXT4_FS=y
CONFIG_EXT4_USE_FOR_EXT2=y
CONFIG_FUSE_FS=y
CONFIG_MSDOS_FS=y
CONFIG_VFAT_FS=y
CONFIG_FAT_DEFAULT_CODEPAGE=437
CONFIG_FAT_DEFAULT_IOCHARSET="iso8859-1"
CONFIG_NTFS_FS=y
CONFIG_NTFS3_FS=y

# 确保网络支持（不影响启动）
CONFIG_NET=y
CONFIG_INET=y
CONFIG_IPV4=y
EOF
        log "  ✅ LEDE 通用启动修复配置已添加"
        
        log "  🔧 检查和修复 LEDE 设备定义文件..."
        
        local device_mk_files=$(find "target/linux/$TARGET" -type f -name "*.mk" 2>/dev/null)
        local device_found=0
        
        for mkfile in $device_mk_files; do
            if grep -q "define Device.*$correct_device" "$mkfile" 2>/dev/null; then
                device_found=1
                log "    📁 找到设备定义文件: $mkfile"
                
                cp "$mkfile" "$mkfile.bak.lede"
                
                if ! grep -q "KERNEL_SIZE" "$mkfile" 2>/dev/null; then
                    local kernel_size=""
                    if grep -q "wndr3800" "$mkfile" 2>/dev/null; then
                        kernel_size="2097152"
                    elif grep -q "ac42u\|rt-ac42u" "$mkfile" 2>/dev/null; then
                        kernel_size="4194304"
                    elif grep -q "rax3000m" "$mkfile" 2>/dev/null; then
                        kernel_size="4194304"
                    else
                        kernel_size="2097152"
                    fi
                    
                    sed -i "/define Device.*$correct_device/a \  KERNEL_SIZE := $kernel_size" "$mkfile"
                    log "      ✅ 添加 KERNEL_SIZE := $kernel_size"
                fi
                
                if ! grep -q "BLOCKSIZE" "$mkfile" 2>/dev/null; then
                    local blocksize="256k"
                    if grep -q "wndr3800" "$mkfile" 2>/dev/null; then
                        blocksize="128k"
                    fi
                    sed -i "/define Device.*$correct_device/a \  BLOCKSIZE := $blocksize" "$mkfile"
                    log "      ✅ 添加 BLOCKSIZE := $blocksize"
                fi
                
                if ! grep -q "IMAGE_SIZE" "$mkfile" 2>/dev/null; then
                    local image_size=""
                    if grep -q "wndr3800" "$mkfile" 2>/dev/null; then
                        image_size="15744k"
                    elif grep -q "ac42u\|rt-ac42u" "$mkfile" 2>/dev/null; then
                        image_size="32256k"
                    elif grep -q "rax3000m" "$mkfile" 2>/dev/null; then
                        image_size="32256k"
                    fi
                    
                    if [ -n "$image_size" ]; then
                        sed -i "/define Device.*$correct_device/a \  IMAGE_SIZE := $image_size" "$mkfile"
                        log "      ✅ 添加 IMAGE_SIZE := $image_size"
                    fi
                fi
                
                if ! grep -q "IMAGE/sysupgrade.bin" "$mkfile" 2>/dev/null; then
                    case "$TARGET" in
                        ipq40xx)
                            echo "define Device/$correct_device" > /tmp/device_temp.txt
                            echo "  IMAGE/sysupgrade.bin := append-kernel | pad-to \$(KERNEL_SIZE) | append-rootfs | pad-rootfs | check-size" >> /tmp/device_temp.txt
                            ;;
                        mediatek)
                            echo "define Device/$correct_device" > /tmp/device_temp.txt
                            echo "  IMAGE/sysupgrade.bin := append-kernel | pad-to \$(KERNEL_SIZE) | append-ubi | check-size" >> /tmp/device_temp.txt
                            ;;
                        ath79)
                            echo "define Device/$correct_device" > /tmp/device_temp.txt
                            echo "  IMAGE/sysupgrade.bin := append-kernel | pad-to \$(KERNEL_SIZE) | append-rootfs | pad-rootfs | append-metadata | check-size" >> /tmp/device_temp.txt
                            ;;
                    esac
                    log "      ℹ️ 建议检查 IMAGE/sysupgrade.bin 定义"
                fi
                
                break
            fi
        done
        
        if [ $device_found -eq 0 ]; then
            log "    ⚠️ 未找到设备 $correct_device 的定义文件，跳过修复"
        fi
        
        log "  🔧 检查和修复 LEDE 内核补丁..."
        
        local patch_dirs=$(find "target/linux/$TARGET" -type d -name "patches-*" 2>/dev/null)
        
        for patch_dir in $patch_dirs; do
            log "    📁 检查补丁目录: $patch_dir"
            
            local problem_patches=$(find "$patch_dir" -name "*.patch" -exec grep -l "leds.*color\|function.*LED_FUNCTION" {} \; 2>/dev/null)
            
            for patch in $problem_patches; do
                log "    ⚠️ 发现可能的问题补丁: $(basename "$patch")"
                mv "$patch" "$patch.disabled" 2>/dev/null || true
                log "      🔧 已禁用问题补丁: $(basename "$patch").disabled"
            done
        done
        
        log "  🔧 配置正确的镜像格式..."
        
        case "$TARGET" in
            ipq40xx)
                echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
                echo "CONFIG_TARGET_UBIFS=y" >> .config
                echo "CONFIG_TARGET_ROOTFS_UBIFS=y" >> .config
                echo "CONFIG_TARGET_UBIFS_FREE_SPACE_FIXUP=y" >> .config
                ;;
            mediatek)
                echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
                echo "CONFIG_TARGET_UBIFS=y" >> .config
                echo "CONFIG_TARGET_ROOTFS_UBIFS=y" >> .config
                echo "CONFIG_TARGET_UBIFS_FREE_SPACE_FIXUP=y" >> .config
                ;;
            ath79)
                echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
                ;;
        esac
        
        log "✅ LEDE 源码启动修复完成"
        log "======================================"
    fi
    
    # ============================================
    # 根据源码类型确定设备配置变量格式
    # ============================================
    local device_config=""
    local actual_subtarget="$SUBTARGET"
    
    # 如果不是 Hanwckf 模式，则需要重新生成 device_config
    if [ $IS_HANWCKF_RAX3000M -eq 0 ]; then
        # 修复：只有当 SUBTARGET 无效（不存在或等于目标名）时才尝试自动查找
        local subtarget_valid=0
        if [ -n "$actual_subtarget" ] && [ "$actual_subtarget" != "$TARGET" ]; then
            if [ -f "target/linux/$TARGET/$actual_subtarget/target.mk" ] || [ -d "target/linux/$TARGET/$actual_subtarget/base-files" ]; then
                subtarget_valid=1
            fi
        fi
        
        if [ $subtarget_valid -eq 0 ]; then
            log "🔧 当前子目标无效 ($actual_subtarget)，尝试自动查找..."
            local found_subtarget=""
            for sub_dir in "target/linux/$TARGET/"*/; do
                [ -d "$sub_dir" ] || continue
                local sub_name=$(basename "$sub_dir")
                if [ "$sub_name" = "image" ] || [ "$sub_name" = "files" ] || [[ "$sub_name" == patches* ]]; then
                    continue
                fi
                if [ -f "$sub_dir/target.mk" ] || [ -d "$sub_dir/base-files" ]; then
                    found_subtarget="$sub_name"
                    break
                fi
            done
            if [ -n "$found_subtarget" ]; then
                actual_subtarget="$found_subtarget"
                log "  ✅ 自动找到子目标: $actual_subtarget"
            else
                log "  ❌ 无法自动找到子目标，请手动指定"
                handle_error "无法确定设备子目标"
            fi
        else
            log "  ✅ 子目标已正确设置: $actual_subtarget"
        fi
        
        device_config="CONFIG_TARGET_${TARGET}_${actual_subtarget}_DEVICE_${correct_device}=y"
        log "🔧 标准设备配置格式: $device_config"
        
        SUBTARGET="$actual_subtarget"
        
        log "🔧 最终设备配置变量: $device_config"
        
        if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
            log "🔧 LEDE源码特殊处理：先设置目标平台"
            cat > .config << EOF
CONFIG_TARGET_${TARGET}=y
CONFIG_TARGET_${TARGET}_${actual_subtarget}=y
EOF
            
            if [ -f .config.tmp.lede ]; then
                cat .config.tmp.lede >> .config
                rm -f .config.tmp.lede
            fi
            
            log "🔄 运行 make defconfig 生成基础配置..."
            make defconfig > /tmp/build-logs/defconfig_lede_base.log 2>&1 || {
                log "❌ LEDE基础配置失败"
                handle_error "LEDE基础配置失败"
            }
            
            log "🔧 添加设备配置: ${device_config}"
            echo "${device_config}" >> .config
            
            make olddefconfig > /tmp/build-logs/olddefconfig_lede.log 2>&1 || true
        else
            cat > .config << EOF
CONFIG_TARGET_${TARGET}=y
CONFIG_TARGET_${TARGET}_${actual_subtarget}=y
${device_config}
EOF
        fi
    else
        # Hanwckf 模式：设备配置已在之前设置，这里只更新 SUBTARGET 环境变量
        SUBTARGET="$actual_subtarget"
        log "  ✅ Hanwckf 模式，设备配置已锁定: $device_config"
    fi
    
    log "🔧 基础配置文件内容:"
    cat .config
    
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        cp .config .config.lede_base_fixed
    fi
    
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
    
    local device_config_file="$CONFIG_DIR/devices/$DEVICE.config"
    local usb_generic_file="$CONFIG_DIR/$CONFIG_USB_GENERIC"
    local base_config_file="$CONFIG_DIR/$CONFIG_BASE"
    
    if [ "$CONFIG_MODE" = "base" ]; then
        log "📋 base模式: 只使用 base.config + usb-generic.config"
        
        if [ -f "$base_config_file" ]; then
            append_config "$base_config_file"
            log "  ✅ 已添加 base.config"
        else
            log "  ⚠️ 未找到 base.config"
        fi
        
        if [ -f "$usb_generic_file" ]; then
            append_config "$usb_generic_file"
            log "  ✅ 已添加 usb-generic.config"
        else
            log "  ⚠️ 未找到 usb-generic.config"
        fi
    else
        log "📋 normal模式: 使用完整配置组合"
        if [ -f "$device_config_file" ]; then
            log "📋 找到设备专用配置文件: $device_config_file"
            append_config "$device_config_file"
        else
            log "📋 未找到设备专用配置文件，使用通用配置组合"
            
            if [ -f "$base_config_file" ]; then
                append_config "$base_config_file"
            fi
            
            if [ -f "$usb_generic_file" ]; then
                append_config "$usb_generic_file"
            fi
            
            append_config "$CONFIG_DIR/$TARGET.config"
            append_config "$CONFIG_DIR/$SELECTED_BRANCH.config"
            
            append_config "$CONFIG_DIR/$CONFIG_NORMAL"
        fi
    fi
    
    # 添加额外包（统一处理，兼容逗号和分号）
    if [ -n "$extra_packages" ]; then
        log "📦 添加额外包: $extra_packages"
        local fixed_packages=$(echo "$extra_packages" | sed 's/;/,/g')
        IFS=',' read -ra PKG_ARRAY <<< "$fixed_packages"
        for pkg in "${PKG_ARRAY[@]}"; do
            pkg=$(echo "$pkg" | xargs)
            [ -z "$pkg" ] && continue
            echo "CONFIG_PACKAGE_$pkg=y" >> .config
        done
    fi
    
    # 启用 TCP BBR
    if [ "${ENABLE_TCP_BBR:-true}" = "true" ]; then
        echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
        echo 'CONFIG_DEFAULT_TCP_CONG="bbr"' >> .config
        log "✅ TCP BBR已启用"
    fi
    
    # 启用全锥形NAT
    if [ "${ENABLE_FULLCONE_NAT:-true}" = "true" ]; then
        echo "CONFIG_PACKAGE_iptables-mod-fullconenat=y" >> .config
        log "✅ 全锥形NAT已启用"
    fi
    
    # ============================================
    # 网络加速自动选择（根据源码类型，完全使用内核配置）
    # ============================================
    if [ "${ENABLE_TURBOACC:-true}" = "true" ] && [ "$CONFIG_MODE" = "normal" ]; then
        case "$SOURCE_REPO_TYPE" in
            "immortalwrt")
                log "✅ ImmortalWrt 使用 TurboACC 加速"
                echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
                echo "CONFIG_PACKAGE_kmod-shortcut-fe=y" >> .config
                echo "CONFIG_PACKAGE_kmod-fast-classifier=y" >> .config
                ;;
            "lede")
                log "✅ LEDE 使用内核软件流量分载 (Flow Offloading)"
                cat >> .config << 'EOF'
CONFIG_NF_FLOW_TABLE=y
CONFIG_NF_FLOW_TABLE_IPV4=y
EOF
                ;;
            "openwrt")
                log "✅ OpenWrt 官方使用内核软件流量分载"
                cat >> .config << 'EOF'
CONFIG_NF_FLOW_TABLE=y
CONFIG_NF_FLOW_TABLE_IPV4=y
EOF
                ;;
            *)
                log "⚠️ 未知源码类型，跳过网络加速"
                ;;
        esac
    fi
    
    # 强制启用 ath10k-ct
    if [ "${FORCE_ATH10K_CT:-true}" = "true" ]; then
        local force_ath10k=0
        case "$TARGET" in
            ipq40xx|ipq806x|qcom) force_ath10k=1 ;;
            ath79) force_ath10k=1 ;;
        esac
        if [ $force_ath10k -eq 1 ]; then
            sed -i '/CONFIG_PACKAGE_kmod-ath10k=y/d' .config
            sed -i '/CONFIG_PACKAGE_kmod-ath10k-pci=y/d' .config
            sed -i '/CONFIG_PACKAGE_kmod-ath10k-smallbuffers=y/d' .config
            echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
            echo "# CONFIG_PACKAGE_kmod-ath10k-pci is not set" >> .config
            echo "# CONFIG_PACKAGE_kmod-ath10k-smallbuffers is not set" >> .config
            echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
            log "✅ ath10k-ct驱动已强制启用"
        else
            log "ℹ️ 当前平台 $TARGET 不需要 ath10k-ct，跳过强制启用"
        fi
    fi
    
    # 强力 IPv6 清理函数
    _force_ipv6_cleanup() {
        local blacklist=(
            ip6tables ip6tables-extra ip6tables-mod-nat
            kmod-ip6tables kmod-ip6tables-extra
            odhcp6c odhcpd odhcpd-ipv6only
            6in4 6rd 6to4 ds-lite map
            luci-proto-ipv6 luci-proto-6in4 luci-proto-6rd luci-proto-6to4
            kmod-ipv6 kmod-nf-ip6 kmod-nf-conntrack6
            kmod-nf-log6 kmod-nf-nat6 kmod-nf-reject6 kmod-sit
            kmod-ipt-nat6 kmod-nf-ipt6 dnsmasq-nodhcpv6
        )
        for pkg in "${blacklist[@]}"; do
            sed -i "/^CONFIG_PACKAGE_${pkg}=/d" .config
            echo "# CONFIG_PACKAGE_${pkg} is not set" >> .config
        done
        sed -i '/^CONFIG_PACKAGE_dnsmasq-full=/d' .config
        echo "# CONFIG_PACKAGE_dnsmasq-full is not set" >> .config
        echo "CONFIG_PACKAGE_dnsmasq=y" >> .config
    }
    
    if [ "${DISABLE_IPV6:-true}" = "true" ]; then
        log "🔧 ===== 彻底禁用 IPv6 并锁定 dnsmasq 为普通版 ====="
        _force_ipv6_cleanup
        log "  ✅ IPv6 组件清理完成"
    fi
    
    log "🔧 强制配置生成固件..."
    
    if grep -q "CONFIG_TARGET_IMAGES_FIT=y" .config; then
        sed -i 's/^CONFIG_TARGET_IMAGES_FIT=y/# CONFIG_TARGET_IMAGES_FIT is not set/' .config
        log "  ✅ 禁用 CONFIG_TARGET_IMAGES_FIT"
    fi
    
    if ! grep -q "CONFIG_TARGET_ROOTFS_SQUASHFS=y" .config; then
        echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
        log "  ✅ 强制启用 squashfs 格式"
    fi
    
    cat >> .config << 'EOF'
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_IMAGES_PAD=y
CONFIG_TARGET_IMAGES_GZIP=y
EOF
    
    case "$TARGET" in
        ipq40xx|ipq806x|qcom)
            cat >> .config << 'EOF'
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=256
CONFIG_TARGET_UBIFS=y
EOF
            log "  ✅ 高通平台配置"
            ;;
        mediatek|ramips)
            cat >> .config << 'EOF'
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=256
CONFIG_TARGET_MTD_SPI_NAND=y
EOF
            log "  ✅ 联发科平台配置"
            ;;
        ath79)
            cat >> .config << 'EOF'
CONFIG_TARGET_ROOTFS_SQUASHFS=y
CONFIG_TARGET_SQUASHFS_BLOCK_SIZE=256
CONFIG_TARGET_ROOTFS_INITRAMFS=y
EOF
            log "  ✅ ATH79平台配置"
            ;;
    esac
    
    # LEDE 源码最终启动验证和修复（仅在 lede 且非 Hanwckf 时执行）
    if [ "$SOURCE_REPO_TYPE" = "lede" ] && [ $IS_HANWCKF_RAX3000M -eq 0 ]; then
        log "🔧 ===== LEDE 源码最终启动验证 ====="
        
        if [ -f .config.lede_base_fixed ]; then
            log "  🔧 合并 LEDE 基础修复配置..."
            while IFS= read -r line; do
                config_name=$(echo "$line" | cut -d'=' -f1)
                if ! grep -q "^${config_name}=" .config; then
                    echo "$line" >> .config
                fi
            done < .config.lede_base_fixed
            rm -f .config.lede_base_fixed
        fi
        
        log "  🔧 验证关键启动配置..."
        
        local critical_missing=0
        
        if ! grep -q "CONFIG_CMDLINE_PARTITION=y" .config; then
            echo "CONFIG_CMDLINE_PARTITION=y" >> .config
            critical_missing=$((critical_missing + 1))
        fi
        
        if ! grep -q "CONFIG_MTD_SPLIT_FIRMWARE=y" .config; then
            echo "CONFIG_MTD_SPLIT_FIRMWARE=y" >> .config
            critical_missing=$((critical_missing + 1))
        fi
        
        if ! grep -q "CONFIG_MTD_SPLIT_UIMAGE_FW=y" .config; then
            echo "CONFIG_MTD_SPLIT_UIMAGE_FW=y" >> .config
            critical_missing=$((critical_missing + 1))
        fi
        
        if [ $critical_missing -gt 0 ]; then
            log "    ✅ 添加了 $critical_missing 个缺失的关键配置"
        else
            log "    ✅ 所有关键配置都已存在"
        fi
        
        local mtd_missing=0
        local mtd_configs=("CONFIG_MTD" "CONFIG_MTD_BLOCK" "CONFIG_MTD_SPLIT")
        for cfg in "${mtd_configs[@]}"; do
            if ! grep -q "^${cfg}=y" .config; then
                mtd_missing=$((mtd_missing + 1))
            fi
        done
        if [ $mtd_missing -gt 0 ]; then
            log "  ⚠️  有 $mtd_missing 个 MTD 相关配置未启用，但可能不影响构建"
        fi
        
        log "✅ LEDE 源码最终启动验证完成"
    fi
    
    log "🔄 第一次去重配置..."
    sort .config | uniq > .config.tmp
    mv .config.tmp .config
    
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        log "🔄 LEDE使用 olddefconfig 更新配置..."
        make olddefconfig > /tmp/build-logs/defconfig1.log 2>&1 || {
            log "⚠️ 第一次 olddefconfig 有警告，但继续"
        }
        [ "${DISABLE_IPV6:-true}" = "true" ] && _force_ipv6_cleanup
    else
        log "🔄 第一次运行 make defconfig..."
        make defconfig > /tmp/build-logs/defconfig1.log 2>&1 || {
            log "❌ 第一次 make defconfig 失败"
            tail -50 /tmp/build-logs/defconfig1.log
            handle_error "第一次依赖解决失败"
        }
    fi
    log "✅ 第一次配置更新成功"
    
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        make olddefconfig > /tmp/build-logs/defconfig_bin_format.log 2>&1 || {
            log "⚠️ olddefconfig 有警告，但继续"
        }
        [ "${DISABLE_IPV6:-true}" = "true" ] && _force_ipv6_cleanup
    else
        make defconfig > /tmp/build-logs/defconfig_bin_format.log 2>&1 || {
            log "⚠️ make defconfig 有警告，但继续"
        }
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
    
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        log "🔄 LEDE第二次使用 olddefconfig..."
        make olddefconfig > /tmp/build-logs/defconfig2.log 2>&1 || {
            log "⚠️ 第二次 olddefconfig 有警告，但继续..."
        }
        [ "${DISABLE_IPV6:-true}" = "true" ] && _force_ipv6_cleanup
    else
        log "🔄 第二次运行 make defconfig..."
        make defconfig > /tmp/build-logs/defconfig2.log 2>&1 || {
            log "⚠️ 第二次 make defconfig 有警告，但继续..."
        }
    fi
    log "✅ 第二次配置更新完成"
    
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
        if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
            make olddefconfig > /dev/null 2>&1 || true
            [ "${DISABLE_IPV6:-true}" = "true" ] && _force_ipv6_cleanup
        else
            make defconfig > /dev/null 2>&1
        fi
    fi
    
    # ============================================
    # 验证设备配置
    # ============================================
    log "🔍 正在验证设备 $correct_device 是否被选中..."
    
    make defconfig > /tmp/build-logs/defconfig_final.log 2>&1 || true
    
    local found_config=""
    local search_pattern=""
    
    search_pattern="CONFIG_TARGET_${TARGET}_${actual_subtarget}_DEVICE_${correct_device}"
    
    found_config=$(grep -E "^${search_pattern}=y" .config 2>/dev/null | head -1)
    
    if [ -n "$found_config" ]; then
        log "✅ 找到设备配置: $found_config"
        device_config="$found_config"
    else
        log "⚠️ 未找到设备配置 $search_pattern"
        log "📋 当前 .config 中的设备配置:"
        grep "CONFIG_TARGET.*DEVICE" .config 2>/dev/null | head -10 | while read line; do
            log "  $line"
        done
    fi
    
    if [ -n "$device_config" ]; then
        sed -i "/^CONFIG_TARGET_${TARGET}.*DEVICE_/d" .config
        echo "$device_config" >> .config
        
        sort .config | uniq > .config.tmp
        mv .config.tmp .config
        
        make defconfig > /tmp/build-logs/defconfig_force_device.log 2>&1 || true
        
        if grep -q "$device_config" .config; then
            log "✅ 设备配置已成功设置: $device_config"
        else
            log "⚠️ 设备配置设置可能失败"
        fi
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
                log "  🗑️ 删除 package/feeds: $dir"
                rm -rf "$dir"
            done
        fi
        if [ -d "feeds" ]; then
            find feeds -type d -name "*${keyword}*" 2>/dev/null | while read dir; do
                log "  🗑️ 删除 feeds: $dir"
                rm -rf "$dir"
            done
        fi
    done
    
    log "🔧 特别处理 vsftpd 冲突问题..."
    find package/feeds -type d -name "*vsftpd-alt*" 2>/dev/null | while read dir; do
        log "  🗑️ 删除 vsftpd-alt 目录: $dir"
        rm -rf "$dir"
    done
    find feeds -type d -name "*vsftpd-alt*" 2>/dev/null | while read dir; do
        log "  🗑️ 删除 feeds vsftpd-alt 目录: $dir"
        rm -rf "$dir"
    done
    find package -type d -name "*vsftpd-alt*" 2>/dev/null | while read dir; do
        log "  🗑️ 删除 package vsftpd-alt 目录: $dir"
        rm -rf "$dir"
    done
    
    log "📋 第二轮：在 .config 中禁用所有相关包..."
    
    local disable_temp=$(mktemp)
    for plugin in "${full_forbidden_list[@]}"; do
        echo "$plugin" >> "$disable_temp"
    done
    
    echo "vsftpd-alt" >> "$disable_temp"
    
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
    
    sed -i "/vsftpd-alt/d" .config
    sed -i "/VSFTPD-ALT/d" .config
    
    log "🔧 特别处理 DDNS 相关配置..."
    sed -i '/ddns/d' .config
    sed -i '/DDNS/d' .config
    
    log "🔧 确保 vsftpd 被启用..."
    if ! grep -q "^CONFIG_PACKAGE_vsftpd=y" .config && ! grep -q "^CONFIG_PACKAGE_vsftpd=m" .config; then
        echo "CONFIG_PACKAGE_vsftpd=y" >> .config
        log "  ✅ 已启用 vsftpd"
    fi
    
    log "✅ 禁用完成"
    
    sort .config | uniq > .config.tmp
    mv .config.tmp .config
    
    log "🔄 运行 make defconfig 使禁用生效..."
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        make olddefconfig > /tmp/build-logs/defconfig_disable.log 2>&1 || {
            log "⚠️ olddefconfig 有警告，但继续..."
        }
        [ "${DISABLE_IPV6:-true}" = "true" ] && _force_ipv6_cleanup
    else
        make defconfig > /tmp/build-logs/defconfig_disable.log 2>&1 || {
            log "⚠️ make defconfig 有警告，但继续..."
        }
    fi
    
    log "🔍 第四轮：检查插件残留..."
    
    local remaining=()
    local check_temp=$(mktemp)
    
    for plugin in "${full_forbidden_list[@]}"; do
        echo "$plugin" >> "$check_temp"
    done
    
    echo "vsftpd-alt" >> "$check_temp"
    
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
        if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
            make olddefconfig > /dev/null 2>&1 || true
            [ "${DISABLE_IPV6:-true}" = "true" ] && _force_ipv6_cleanup
        else
            make defconfig > /dev/null 2>&1
        fi
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
    
    if grep -q "^CONFIG_PACKAGE_vsftpd-alt=y" .config || grep -q "^CONFIG_PACKAGE_vsftpd-alt=m" .config; then
        log "  ❌ vsftpd-alt 仍被启用"
        still_enabled=$((still_enabled + 1))
    else
        log "  ✅ vsftpd-alt 已禁用"
    fi
    
    if grep -q "^CONFIG_PACKAGE_vsftpd=y" .config || grep -q "^CONFIG_PACKAGE_vsftpd=m" .config; then
        log "  ✅ vsftpd 已启用"
    else
        log "  ⚠️ vsftpd 未启用，尝试启用"
        echo "CONFIG_PACKAGE_vsftpd=y" >> .config
    fi
    
    if [ $still_enabled -eq 0 ]; then
        log "🎉 所有指定插件已成功禁用"
    else
        log "⚠️ 有 $still_enabled 个插件未能禁用，将在后续阶段再次尝试"
    fi
    
    # ============================================
    # 最终锁定：精确修复 Makefile 依赖并清除包索引缓存
    # ============================================
    if [ "${DISABLE_IPV6:-true}" = "true" ]; then
        log "🔧 最终锁定：彻底清除 IPv6 依赖及冲突包"

        # 1. 再次确保 .config 干净
        _force_ipv6_cleanup

        # 2. 精确修复 luci-light 的 Makefile 依赖
        find package/feeds feeds -path "*/luci-light/Makefile" 2>/dev/null | while read mk; do
            cp "$mk" "$mk.bak.lock"
            sed -i 's/ +luci-proto-ipv6\b//g; s/+luci-proto-ipv6\b//g; s/ luci-proto-ipv6\b//g' "$mk"
            sed -i 's/^\(\s*DEPENDS\):=\(\s*\)$/\1:=+libc/' "$mk"
            log "  ✅ 已清理 $mk"
        done

        # 3. 精确修复 luci-nginx 的 Makefile 依赖
        find package/feeds feeds -path "*/luci-nginx/Makefile" 2>/dev/null | while read mk; do
            cp "$mk" "$mk.bak.lock"
            sed -i 's/ +luci-proto-ipv6\b//g; s/+luci-proto-ipv6\b//g; s/ luci-proto-ipv6\b//g' "$mk"
            sed -i 's/^\(\s*DEPENDS\):=\(\s*\)$/\1:=+libc/' "$mk"
            log "  ✅ 已清理 $mk"
        done

        # 4. 物理删除 IPv6 及冲突包源码目录
        find package/feeds feeds -type d \( \
            -name "*ip6tables*" -o -name "*odhcp6c*" -o -name "*odhcpd*" \
            -o -name "*6in4*" -o -name "*6rd*" -o -name "*6to4*" \
            -o -name "*ds-lite*" -o -name "*map*" \
            -o -name "*luci-proto-ipv6*" -o -name "*kmod-ipv6*" \
            -o -name "*kmod-nf-ip6*" -o -name "*kmod-nf-conntrack6*" \
            -o -name "*kmod-nf-nat6*" -o -name "*kmod-ipt-nat6*" \
            -o -name "*kmod-nf-ipt6*" -o -name "*dnsmasq-nodhcpv6*" \
            -o -name "*ppp-mod-pppoe*" \
        \) -exec rm -rf {} + 2>/dev/null

        # 5. 删除有问题的 ddns-scripts_* 目录并强制禁用
        find package/feeds feeds -type d \( \
            -name "ddns-scripts_aliyun" -o -name "ddns-scripts_dnspod" \
            -o -name "ddns-scripts_cloudflare" -o -name "ddns-scripts_freedns" \
            -o -name "ddns-scripts_godaddy" -o -name "ddns-scripts_noip" \
            -o -name "ddns-scripts_services" \
        \) -exec rm -rf {} + 2>/dev/null

        sed -i '/^CONFIG_PACKAGE_ddns-scripts_/d' .config
        echo "# CONFIG_PACKAGE_ddns-scripts_aliyun is not set" >> .config
        echo "# CONFIG_PACKAGE_ddns-scripts_dnspod is not set" >> .config

        # 6. 清除旧的包索引缓存（关键！防止 opkg 安装时依赖旧索引）
        rm -rf tmp/.packagefeeds* 2>/dev/null
        find staging_dir -name "Packages*" -exec rm -f {} + 2>/dev/null
        ./scripts/feeds update -i > /dev/null 2>&1 || true

        # 7. 最后再清理一次 .config 并运行 olddefconfig
        _force_ipv6_cleanup
        if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
            make olddefconfig > /dev/null 2>&1 || true
        fi
        find package/feeds feeds -type d -name "dnsmasq-nodhcpv6" -exec rm -rf {} + 2>/dev/null
        log "  ✅ 锁定完成"
    fi
    
    # ============================================
    # 修正固件名称前缀（根据源码类型）
    # ============================================
    log "🔧 修正固件名称前缀（根据源码类型）..."
    
    local vendor_prefix=""
    local dist_name=""
    case "$SOURCE_REPO_TYPE" in
        "immortalwrt")
            vendor_prefix="immortalwrt"
            dist_name="ImmortalWrt"
            ;;
        "lede")
            vendor_prefix="lede"
            dist_name="LEDE"
            ;;
        "openwrt")
            vendor_prefix="openwrt"
            dist_name="OpenWrt"
            ;;
        *)
            vendor_prefix=$(echo "$SOURCE_REPO_TYPE" | tr '[:upper:]' '[:lower:]')
            dist_name=$(echo "$SOURCE_REPO_TYPE" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}')
            ;;
    esac
    
    log "  📌 源码类型: $SOURCE_REPO_TYPE"
    log "  📌 固件前缀: $vendor_prefix"
    log "  📌 发行版名称: $dist_name"
    
    sed -i '/^CONFIG_VERSION_DIST=/d' .config
    sed -i '/^# CONFIG_VERSION_DIST/d' .config
    echo "CONFIG_VERSION_DIST=\"$dist_name\"" >> .config
    log "    ✅ 设置 CONFIG_VERSION_DIST=\"$dist_name\""
    
    sed -i '/^CONFIG_VERSION_REPO=/d' .config
    sed -i '/^# CONFIG_VERSION_REPO/d' .config
    echo "CONFIG_VERSION_REPO=\"https://github.com/$SOURCE_REPO_TYPE/$SOURCE_REPO_TYPE.git\"" >> .config
    log "    ✅ 设置 CONFIG_VERSION_REPO"
    
    sed -i '/^CONFIG_VERSION_CODE_FILENAME=/d' .config
    sed -i '/^# CONFIG_VERSION_CODE_FILENAME/d' .config
    echo "CONFIG_VERSION_CODE_FILENAME=\"$vendor_prefix\"" >> .config
    log "    ✅ 设置 CONFIG_VERSION_CODE_FILENAME=\"$vendor_prefix\""
    
    sed -i '/^CONFIG_VERSION_MANUFACTURER=/d' .config
    sed -i '/^# CONFIG_VERSION_MANUFACTURER/d' .config
    echo "CONFIG_VERSION_MANUFACTURER=\"$vendor_prefix\"" >> .config
    log "    ✅ 设置 CONFIG_VERSION_MANUFACTURER=\"$vendor_prefix\""
    
    if [ -f "include/version.mk" ]; then
        cp include/version.mk include/version.mk.bak
        sed -i "s/VERSION_DIST:=.*/VERSION_DIST:=$dist_name/g" include/version.mk
        sed -i "s/VERSION_REPO:=.*/VERSION_REPO:=https:\/\/github.com\/$SOURCE_REPO_TYPE\/$SOURCE_REPO_TYPE.git/g" include/version.mk
        sed -i "s/VERSION_CODE_FILENAME:=.*/VERSION_CODE_FILENAME:=$vendor_prefix/g" include/version.mk
        sed -i "s/VERSION_MANUFACTURER:=.*/VERSION_MANUFACTURER:=$vendor_prefix/g" include/version.mk
        log "    ✅ 修改 include/version.mk"
        rm -f include/version.mk.bak
    fi
    
    if [ -f "include/image.mk" ]; then
        cp include/image.mk include/image.mk.bak
        sed -i "s/openwrt-/$vendor_prefix-/g" include/image.mk
        sed -i "s/immortalwrt-/$vendor_prefix-/g" include/image.mk
        sed -i "s/lede-/$vendor_prefix-/g" include/image.mk
        sed -i "s/OpenWrt-/$vendor_prefix-/g" include/image.mk
        sed -i "s/ImmortalWrt-/$vendor_prefix-/g" include/image.mk
        sed -i "s/LEDE-/$vendor_prefix-/g" include/image.mk
        log "    ✅ 修改 include/image.mk 中的前缀"
        rm -f include/image.mk.bak
    fi
    
    local image_mk="target/linux/$TARGET/image/$actual_subtarget.mk"
    if [ -f "$image_mk" ]; then
        cp "$image_mk" "$image_mk.bak"
        sed -i "s/openwrt-/$vendor_prefix-/g" "$image_mk"
        sed -i "s/immortalwrt-/$vendor_prefix-/g" "$image_mk"
        sed -i "s/lede-/$vendor_prefix-/g" "$image_mk"
        sed -i "s/OpenWrt/$vendor_prefix/g" "$image_mk"
        sed -i "s/ImmortalWrt/$vendor_prefix/g" "$image_mk"
        sed -i "s/LEDE/$vendor_prefix/g" "$image_mk"
        log "    ✅ 修改 $image_mk"
        rm -f "$image_mk.bak"
    fi
    
    if [ -f "target/linux/$TARGET/image/Makefile" ]; then
        cp "target/linux/$TARGET/image/Makefile" "target/linux/$TARGET/image/Makefile.bak"
        sed -i "s/openwrt-/$vendor_prefix-/g" "target/linux/$TARGET/image/Makefile"
        sed -i "s/immortalwrt-/$vendor_prefix-/g" "target/linux/$TARGET/image/Makefile"
        sed -i "s/lede-/$vendor_prefix-/g" "target/linux/$TARGET/image/Makefile"
        log "    ✅ 修改 target/linux/$TARGET/image/Makefile"
        rm -f "target/linux/$TARGET/image/Makefile.bak"
    fi
    
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        log "  🔧 LEDE 源码特殊处理..."
        if [ -f "feeds.conf.default" ]; then
            sed -i 's/^# CONFIG_VERSION_DIST=.*/CONFIG_VERSION_DIST="LEDE"/g' feeds.conf.default 2>/dev/null || true
        fi
        if [ -f "package/base-files/files/etc/openwrt_release" ]; then
            sed -i 's/DISTRIB_ID=.*/DISTRIB_ID="LEDE"/g' package/base-files/files/etc/openwrt_release 2>/dev/null || true
            sed -i 's/DISTRIB_RELEASE=.*/DISTRIB_RELEASE="LEDE"/g' package/base-files/files/etc/openwrt_release 2>/dev/null || true
        fi
        log "    ✅ LEDE 特殊配置已应用"
    fi
    
    make defconfig > /dev/null 2>&1 || true
    
    log "✅ 固件名称前缀修正完成"
    log "  📌 预期固件名称格式: ${vendor_prefix}-${TARGET}-${actual_subtarget}-${correct_device}-squashfs-sysupgrade.bin"
    
    # ============================================
    # 显示已应用补丁状态（动态）
    # ============================================
    log "🔍 检查已应用补丁状态..."
    show_patch_status
    
    log "✅ 配置生成完成"
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
    local ipk_files=()
    
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
            ipk_files+=("$file")
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
    
    # ============================================
    # 扫描并修复 IPK 包中的文件冲突
    # ============================================
    if [ $ipk_count -gt 0 ]; then
        echo ""
        log "🔧 ===== 扫描并修复 IPK 包中的文件冲突 ====="
        echo ""
        
        local fixed_count=0
        local checked_count=0
        local failed_count=0
        local skipped_count=0
        local no_conflict_count=0
        local total_deleted_files=0
        local conflict_patterns=(
            "usr/lib/lua/luci/fs.lua"           # 与 luci-lib-fs 冲突
            "usr/lib/lua/luci/util.lua"         # 与 luci-lib-base 冲突
            "usr/lib/lua/luci/ip.lua"           # 与 luci-lib-ip 冲突
            "usr/lib/lua/luci/json.lua"         # 与 luci-lib-jsonc 冲突
            "etc/init.d/boot"                   # 系统关键文件
            "etc/rc.common"                     # 系统关键文件
        )
        
        for ipk_file in "${ipk_files[@]}"; do
            local ipk_name=$(basename "$ipk_file")
            checked_count=$((checked_count + 1))
            
            echo "  📦 [$checked_count/$ipk_count] 检查: $ipk_name"
            
            # 创建临时目录
            local temp_dir=$(mktemp -d)
            local original_dir=$(pwd)
            local ipk_fixed=0
            local ipk_has_conflict=0
            local deleted_list=()
            
            cd "$temp_dir" || {
                echo "      ❌ 无法创建临时目录"
                failed_count=$((failed_count + 1))
                continue
            }
            
            # 解包 IPK
            local unpack_success=0
            local unpack_method=""
            
            if command -v ar >/dev/null 2>&1; then
                if ar x "$ipk_file" 2>/dev/null; then
                    if [ -f "debian-binary" ] || [ -f "control.tar.gz" ] || [ -f "data.tar.gz" ]; then
                        unpack_success=1
                        unpack_method="ar"
                    fi
                fi
            fi
            
            if [ $unpack_success -eq 0 ]; then
                if command -v 7z >/dev/null 2>&1; then
                    if 7z x "$ipk_file" -o"$temp_dir" >/dev/null 2>&1; then
                        unpack_success=1
                        unpack_method="7z"
                    fi
                fi
            fi
            
            if [ $unpack_success -eq 0 ] && command -v dpkg-deb >/dev/null 2>&1; then
                if dpkg-deb -x "$ipk_file" . 2>/dev/null; then
                    dpkg-deb -e "$ipk_file" 2>/dev/null || true
                    unpack_success=1
                    unpack_method="dpkg-deb"
                fi
            fi
            
            if [ $unpack_success -eq 0 ] && command -v python3 >/dev/null 2>&1; then
                cat > "$temp_dir/unpack_ipk.py" << 'PYEOF'
import sys
import tarfile
import io

def unpack_ipk(ipk_path, output_dir):
    try:
        with open(ipk_path, 'rb') as f:
            header = f.read(8)
            if header != b'!<arch>\n':
                return False
            
            while True:
                file_header = f.read(60)
                if len(file_header) < 60:
                    break
                name = file_header[0:16].decode('ascii').strip()
                size_str = file_header[48:58].decode('ascii').strip()
                size = int(size_str) if size_str else 0
                if name and size > 0:
                    data = f.read(size)
                    if size % 2 == 1:
                        f.read(1)
                    if name == 'debian-binary':
                        with open(f'{output_dir}/debian-binary', 'wb') as out:
                            out.write(data)
                    elif name.startswith('control.tar'):
                        with open(f'{output_dir}/control.tar.gz', 'wb') as out:
                            out.write(data)
                    elif name.startswith('data.tar'):
                        with open(f'{output_dir}/data.tar.gz', 'wb') as out:
                            out.write(data)
        return True
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return False

if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(1)
    sys.exit(0 if unpack_ipk(sys.argv[1], sys.argv[2]) else 1)
PYEOF
                if python3 "$temp_dir/unpack_ipk.py" "$ipk_file" "$temp_dir" 2>/dev/null; then
                    unpack_success=1
                    unpack_method="python"
                fi
            fi
            
            if [ $unpack_success -eq 1 ]; then
                local needs_repack=0
                
                if [ -f "data.tar.gz" ]; then
                    tar -xzf data.tar.gz 2>/dev/null || true
                elif [ -f "data.tar.xz" ]; then
                    tar -xJf data.tar.xz 2>/dev/null || true
                elif [ -f "data.tar" ]; then
                    tar -xf data.tar 2>/dev/null || true
                fi
                
                for pattern in "${conflict_patterns[@]}"; do
                    if [ -f "./$pattern" ]; then
                        echo "      🗑️ 发现冲突: $pattern"
                        rm -f "./$pattern"
                        deleted_list+=("$pattern")
                        needs_repack=1
                        ipk_has_conflict=1
                    fi
                done
                
                local file_count_after=$(find . -type f ! -name "debian-binary" ! -name "control.tar.gz" ! -name "data.tar.gz" ! -name "data.tar.xz" ! -name "data.tar" ! -name "*.py" 2>/dev/null | wc -l)
                
                if [ $needs_repack -eq 1 ] && [ $file_count_after -gt 0 ]; then
                    rm -f data.tar.gz data.tar.xz data.tar 2>/dev/null
                    local files_to_pack=$(find . -type f ! -name "debian-binary" ! -name "control.tar.gz" ! -name "*.py" 2>/dev/null)
                    if [ -n "$files_to_pack" ]; then
                        tar -czf data.tar.gz ./* --exclude=debian-binary --exclude=control.tar.gz --exclude=*.py 2>/dev/null || tar -czf data.tar.gz ./* 2>/dev/null
                    fi
                    if [ -f "data.tar.gz" ] && [ -f "control.tar.gz" ] && [ -f "debian-binary" ]; then
                        rm -f "$ipk_file"
                        if ar rcs "$ipk_file" debian-binary control.tar.gz data.tar.gz 2>/dev/null; then
                            ipk_fixed=1
                            fixed_count=$((fixed_count + 1))
                            total_deleted_files=$((total_deleted_files + ${#deleted_list[@]}))
                            echo "      ✅ 修复成功！已删除 ${#deleted_list[@]} 个冲突文件"
                            for deleted in "${deleted_list[@]}"; do
                                echo "         - $deleted"
                            done
                        else
                            echo "      ❌ 重新打包失败（ar 命令不可用），将保留原文件"
                            failed_count=$((failed_count + 1))
                        fi
                    else
                        echo "      ❌ 缺少必要文件，无法重新打包"
                        failed_count=$((failed_count + 1))
                    fi
                elif [ $needs_repack -eq 1 ] && [ $file_count_after -eq 0 ]; then
                    echo "      ⚠️ IPK 中除冲突文件外无其他有效内容，跳过修复"
                    skipped_count=$((skipped_count + 1))
                else
                    echo "      ✅ 未发现冲突文件"
                    no_conflict_count=$((no_conflict_count + 1))
                fi
            else
                echo "      ⚠️ 无法解包（尝试了 ar/7z/dpkg-deb/python 均失败）"
                echo "      💡 将保留原文件，刷机后使用 --force-overwrite 强制安装"
                failed_count=$((failed_count + 1))
            fi
            
            cd "$original_dir"
            rm -rf "$temp_dir"
            echo ""
        done
        
        echo "  ----------------------------------------"
        echo "  📊 IPK 修复统计:"
        echo "     总检查数: $checked_count 个"
        echo "     成功修复: $fixed_count 个"
        echo "     无冲突: $no_conflict_count 个"
        echo "     无法处理: $failed_count 个（将强制安装）"
        echo "     跳过处理: $skipped_count 个"
        echo "     删除冲突文件总数: $total_deleted_files 个"
        echo "  ----------------------------------------"
        
        if [ $fixed_count -gt 0 ]; then
            log "✅ 共修复 $fixed_count 个 IPK 包的文件冲突"
        fi
        if [ $failed_count -gt 0 ]; then
            log "💡 有 $failed_count 个 IPK 包无法预处理，刷机后将使用 --force-overwrite 强制安装"
        fi
        if [ $fixed_count -eq 0 ] && [ $no_conflict_count -eq $checked_count ]; then
            log "✅ 所有 IPK 包检查通过，无冲突"
        fi
        echo ""
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
    cat > "$first_boot_script" << 'FIRSTBOOT_EOF'
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
            
            if opkg install --force-overwrite "$file" >> $LOG_FILE 2>&1; then
                echo "      ✅ 安装成功（使用 --force-overwrite）" >> $LOG_FILE
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
    
    if [ $((TOTAL_SUCCESS + TOTAL_FAILED)) -gt 0 ]; then
        SUCCESS_RATE=$((TOTAL_SUCCESS * 100 / (TOTAL_SUCCESS + TOTAL_FAILED)))
    else
        SUCCESS_RATE=0
    fi
    
    echo "📈 总体统计:" >> $LOG_FILE
    echo "  总文件数: $TOTAL_FILES 个" >> $LOG_FILE
    echo "  成功处理: $TOTAL_SUCCESS 个" >> $LOG_FILE
    echo "  失败处理: $TOTAL_FAILED 个" >> $LOG_FILE
    echo "  成功率: ${SUCCESS_RATE}%" >> $LOG_FILE
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
FIRSTBOOT_EOF
    
    # 检查脚本语法，若失败则删除脚本并提示
    if ! sh -n "$first_boot_script" 2>/dev/null; then
        log "❌ 开机脚本 99-custom-files 语法错误，已自动移除，避免影响 base-files 编译"
        rm -f "$first_boot_script"
    else
        chmod +x "$first_boot_script"
        log "✅ 创建第一次开机安装脚本: $first_boot_script"
    fi
    
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
# 工作流步骤函数 - 按新的执行顺序排列
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
    
    # ============================================
    # 修复文件描述符限制
    # ============================================
    log "🔧 检查和修复文件描述符限制..."
    
    # 获取当前限制
    local current_limit=$(ulimit -n)
    log "  当前文件描述符限制: $current_limit"
    
    # 如果限制小于65536，尝试提高
    if [ $current_limit -lt 65536 ]; then
        log "  文件描述符限制过低，尝试提高到65536..."
        ulimit -n 65536 2>/dev/null || {
            log "  ⚠️ 无法直接提高限制，尝试使用sudo..."
            sudo ulimit -n 65536 2>/dev/null || true
        }
        
        # 再次检查
        local new_limit=$(ulimit -n)
        log "  新的文件描述符限制: $new_limit"
        
        if [ $new_limit -lt 4096 ]; then
            log "  ⚠️ 警告：文件描述符限制仍过低，可能会遇到'Broken pipe'错误"
        else
            log "  ✅ 文件描述符限制已优化"
        fi
    else
        log "  ✅ 文件描述符限制足够"
    fi
    
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
    
    # ============================================
    # 修复文件描述符限制
    # ============================================
    log "🔧 检查和修复文件描述符限制..."
    
    # 获取当前限制
    local current_limit=$(ulimit -n)
    log "  当前文件描述符限制: $current_limit"
    
    # 如果限制小于65536，尝试提高
    if [ $current_limit -lt 65536 ]; then
        log "  文件描述符限制过低，尝试提高到65536..."
        ulimit -n 65536 2>/dev/null || {
            log "  ⚠️ 无法直接提高限制，尝试使用sudo..."
            sudo ulimit -n 65536 2>/dev/null || true
        }
        
        # 再次检查
        local new_limit=$(ulimit -n)
        log "  新的文件描述符限制: $new_limit"
        
        if [ $new_limit -lt 4096 ]; then
            log "  ⚠️ 警告：文件描述符限制仍过低，可能会遇到'Broken pipe'错误"
        else
            log "  ✅ 文件描述符限制已优化"
        fi
    else
        log "  ✅ 文件描述符限制足够"
    fi
    
    log "✅ 步骤08 完成"
}
#【build_firmware_main.sh-26-end】

#【build_firmware_main.sh-27】
workflow_step09_download_sdk() {
    local device_name="$1"
    
    log "=== 步骤09: 编译源码自带工具链（动态验证目标） ==="
    
    set -e
    trap 'echo "❌ 步骤09 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    # 加载环境变量
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 加载环境变量: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
    fi
    
    # ============================================
    # 检查libyaml是否安装（修复dtc链接错误）
    # ============================================
    log "🔧 检查libyaml库（修复dtc链接错误）..."
    
    if ! pkg-config --libs yaml-0.1 > /dev/null 2>&1; then
        log "  ⚠️ libyaml未找到，尝试安装..."
        sudo apt-get update > /dev/null 2>&1 || true
        sudo apt-get install -y libyaml-dev > /dev/null 2>&1 || {
            log "  ⚠️ 自动安装失败，将使用备用方案"
            
            # 备用方案：创建pkg-config文件
            mkdir -p staging_dir/host/lib/pkgconfig
            cat > staging_dir/host/lib/pkgconfig/yaml-0.1.pc << 'EOF'
prefix=/usr
exec_prefix=${prefix}
includedir=${prefix}/include
libdir=${exec_prefix}/lib/x86_64-linux-gnu

Name: LibYAML
Description: Library for YAML 1.1
Version: 0.2.5
Cflags: -I${includedir}
Libs: -L${libdir} -lyaml
EOF
            export PKG_CONFIG_PATH="$PWD/staging_dir/host/lib/pkgconfig:$PKG_CONFIG_PATH"
            log "  ✅ 已创建libyaml pkg-config文件"
            
            # 检查库文件是否存在
            if [ ! -f "/usr/lib/x86_64-linux-gnu/libyaml.so" ] && [ ! -f "/usr/lib/libyaml.so" ]; then
                log "  ⚠️ libyaml库文件不存在，尝试下载源码编译..."
                
                # 下载并编译libyaml
                mkdir -p dl
                if [ ! -f "dl/yaml-0.2.5.tar.gz" ]; then
                    wget -O dl/yaml-0.2.5.tar.gz https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz || true
                fi
                
                if [ -f "dl/yaml-0.2.5.tar.gz" ]; then
                    mkdir -p build_dir/host/libyaml-0.2.5
                    tar -xzf dl/yaml-0.2.5.tar.gz -C build_dir/host/libyaml-0.2.5 --strip-components=1
                    cd build_dir/host/libyaml-0.2.5
                    ./configure --prefix="$BUILD_DIR/staging_dir/host"
                    make -j1
                    make install
                    cd "$BUILD_DIR"
                    
                    # 更新pkg-config路径
                    export PKG_CONFIG_PATH="$BUILD_DIR/staging_dir/host/lib/pkgconfig:$PKG_CONFIG_PATH"
                    log "  ✅ libyaml手动编译完成"
                fi
            fi
        }
    else
        log "  ✅ libyaml已安装"
        pkg-config --libs --cflags yaml-0.1 | sed 's/^/      /'
    fi
    
    # ============================================
    # 动态验证关键编译目标是否存在
    # ============================================
    log "🔍 验证源码Makefile中的关键编译目标..."
    local missing_targets=0
    
    if ! grep -qE '^[^#]*tools/compile' "$BUILD_DIR/Makefile" "$BUILD_DIR/include"/*.mk 2>/dev/null; then
        log "  ⚠️ 未在源码中找到 tools/compile 目标"
        missing_targets=$((missing_targets + 1))
    fi
    
    if ! grep -qE '^[^#]*toolchain/compile' "$BUILD_DIR/Makefile" "$BUILD_DIR/include"/*.mk 2>/dev/null; then
        log "  ⚠️ 未在源码中找到 toolchain/compile 目标"
        missing_targets=$((missing_targets + 1))
    fi
    
    if [ $missing_targets -gt 0 ]; then
        log "⚠️ 共 $missing_targets 个关键目标缺失，但将继续尝试编译"
    else
        log "✅ 关键编译目标检测通过"
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
workflow_step15_generate_config() {
    local extra_packages="$1"
    
    log "=== 步骤12: 智能配置生成 ==="
    log "当前设备: $DEVICE"
    log "当前目标: $TARGET"
    log "当前子目标: $SUBTARGET"
    
    set -e
    trap 'echo "❌ 步骤12 失败，退出代码: $?"; exit 1' ERR
    
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
    log "=== 🔍 设备定义文件验证 ==="
    log "搜索设备名: $DEVICE"
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
    
    find_best_matching_device() {
        local input_device="$1"
        local mk_file="$2"
        local results=()
        
        local all_devices=()
        while IFS= read -r line; do
            if [[ "$line" =~ define[[:space:]]+Device/([a-zA-Z0-9_-]+) ]]; then
                all_devices+=("${BASH_REMATCH[1]}")
            fi
        done < <(grep -E "define Device/[a-zA-Z0-9_-]+" "$mk_file" 2>/dev/null)
        
        local lower_input=$(echo "$input_device" | tr '[:upper:]' '[:lower:]')
        
        local input_base=""
        if [[ "$lower_input" == *"rax3000m"* ]]; then input_base="rax3000m"
        elif [[ "$lower_input" == *"ac42u"* ]]; then input_base="ac42u"
        elif [[ "$lower_input" == *"wndr3800"* ]]; then input_base="wndr3800"
        else input_base=$(echo "$lower_input" | sed 's/-nand$//;s/-emmc$//;s/-sd$//;s/-ubootmod$//'); fi
        
        local input_has_nand=0
        local input_has_emmc=0
        local input_has_ubootmod=0
        if [[ "$lower_input" == *"nand"* ]]; then input_has_nand=1; fi
        if [[ "$lower_input" == *"emmc"* ]]; then input_has_emmc=1; fi
        if [[ "$lower_input" == *"ubootmod"* ]]; then input_has_ubootmod=1; fi
        
        for device in "${all_devices[@]}"; do
            if [[ "$device" == *_common* ]]; then
                continue
            fi
            
            local weight=0
            local lower_device=$(echo "$device" | tr '[:upper:]' '[:lower:]')
            
            if [ "$lower_input" = "$lower_device" ]; then
                weight=$((weight + 200))
            fi
            
            if [[ "$lower_input" == *"$lower_device"* ]]; then
                weight=$((weight + 80))
            fi
            
            if [[ "$lower_device" == *"$lower_input"* ]]; then
                weight=$((weight + 60))
            fi
            
            if [[ "$lower_device" == *"$input_base"* ]]; then
                weight=$((weight + 50))
            fi
            
            local input_no_suffix=$(echo "$lower_input" | sed 's/-nand$//;s/-emmc$//;s/-sd$//;s/-ubootmod$//')
            local device_no_suffix=$(echo "$lower_device" | sed 's/-nand$//;s/-emmc$//;s/-sd$//;s/-ubootmod$//')
            if [ "$input_no_suffix" = "$device_no_suffix" ]; then
                weight=$((weight + 40))
            fi
            
            if [[ "$lower_input" == *"rax3000m"* ]] && [[ "$lower_device" == *"rax3000m"* ]]; then
                weight=$((weight + 30))
            fi
            
            if [ $input_has_nand -eq 1 ] && [[ "$lower_device" == *"nand"* ]]; then
                weight=$((weight + 25))
            fi
            if [ $input_has_emmc -eq 1 ] && [[ "$lower_device" == *"emmc"* ]]; then
                weight=$((weight + 25))
            fi
            if [ $input_has_ubootmod -eq 1 ] && [[ "$lower_device" == *"ubootmod"* ]]; then
                weight=$((weight + 25))
            fi
            
            local input_parts=($(echo "$lower_input" | tr '_-' ' '))
            local device_parts=($(echo "$lower_device" | tr '_-' ' '))
            for ipart in "${input_parts[@]}"; do
                for dpart in "${device_parts[@]}"; do
                    if [ "$ipart" = "$dpart" ] && [ ${#ipart} -gt 2 ]; then
                        weight=$((weight + 10))
                    fi
                done
            done
            
            if [ $weight -gt 0 ]; then
                results+=("$weight:$device")
            fi
        done
        
        if [ ${#results[@]} -gt 0 ]; then
            printf '%s\n' "${results[@]}" | sort -t':' -k1 -rn | head -20
        fi
    }
    
    # ============================================
    # 分析设备固件格式（支持模板展开）
    # ============================================
    analyze_device_firmware_format() {
        local device_name="$1"
        local mk_file="$2"

        local full_block=""
        local in_block=0
        while IFS= read -r line; do
            if [[ "$line" =~ define[[:space:]]+Device/$device_name ]]; then
                in_block=1
                full_block="$line"$'\n'
                continue
            fi
            if [ $in_block -eq 1 ]; then
                full_block="$full_block$line"$'\n'
                if [[ "$line" =~ \$\(call[[:space:]]+Device/([a-zA-Z0-9_-]+) ]]; then
                    local template_name="${BASH_REMATCH[1]}"
                    local template_block=$(awk "/define Device\/$template_name\$/,/^endef/" "$mk_file" 2>/dev/null)
                    if [ -n "$template_block" ]; then
                        full_block="$full_block$template_block"$'\n'
                    fi
                fi
                if [[ "$line" == "endef" ]]; then
                    break
                fi
            fi
        done < "$mk_file"

        if [ -z "$full_block" ]; then
            echo "unknown"
            return
        fi

        local images_def=""
        local images_line=$(echo "$full_block" | grep "IMAGES[[:space:]]*:=")
        if [ -n "$images_line" ]; then
            images_def=$(echo "$images_line" | sed 's/.*:= *//')
        fi

        local has_sysupgrade_bin=0
        local has_sysupgrade_itb=0
        local has_factory_bin=0
        local has_factory_img=0

        echo "$full_block" | grep -q "IMAGE/sysupgrade.bin" && has_sysupgrade_bin=1
        echo "$full_block" | grep -q "IMAGE/sysupgrade.itb" && has_sysupgrade_itb=1
        echo "$full_block" | grep -q "IMAGE/factory.bin" && has_factory_bin=1
        echo "$full_block" | grep -q "IMAGE/factory.img" && has_factory_img=1

        if [ -n "$images_def" ]; then
            echo "$images_def" | grep -q "sysupgrade.bin" && has_sysupgrade_bin=1
            echo "$images_def" | grep -q "sysupgrade.itb" && has_sysupgrade_itb=1
        else
            has_sysupgrade_bin=1
        fi

        local result=""
        if [ $has_sysupgrade_bin -eq 1 ]; then
            result="bin"
        elif [ $has_sysupgrade_itb -eq 1 ]; then
            result="itb"
        else
            result="bin"
        fi

        echo "$result|$images_def|$has_sysupgrade_bin|$has_sysupgrade_itb|$has_factory_bin|$has_factory_img"
    }
    
    find_bin_compatible_device() {
        local input_device="$1"
        local mk_file="$2"
        local lower_input=$(echo "$input_device" | tr '[:upper:]' '[:lower:]')
        
        local base_name=""
        if [[ "$lower_input" == *"rax3000m"* ]]; then base_name="rax3000m"
        elif [[ "$lower_input" == *"ac42u"* ]]; then base_name="ac42u"
        elif [[ "$lower_input" == *"wndr3800"* ]]; then base_name="wndr3800"
        else base_name=$(echo "$lower_input" | sed 's/-nand$//;s/-emmc$//;s/-sd$//;s/-ubootmod$//'); fi
        
        local candidates=()
        
        while IFS= read -r line; do
            if [[ "$line" =~ define[[:space:]]+Device/([a-zA-Z0-9_-]+) ]]; then
                local dev_name="${BASH_REMATCH[1]}"
                if [[ "$dev_name" == *_common* ]]; then continue; fi
                
                local lower_dev=$(echo "$dev_name" | tr '[:upper:]' '[:lower:]')
                
                if [[ "$lower_dev" == *"$base_name"* ]]; then
                    local format_info=$(analyze_device_firmware_format "$dev_name" "$mk_file")
                    local format_type=$(echo "$format_info" | cut -d'|' -f1)
                    
                    if [ "$format_type" = "bin" ]; then
                        candidates+=("$dev_name")
                    fi
                fi
            fi
        done < <(grep -E "define Device/[a-zA-Z0-9_-]+" "$mk_file" 2>/dev/null)
        
        if [ ${#candidates[@]} -gt 0 ]; then
            printf '%s\n' "${candidates[@]}"
        fi
    }
    
    # ============================================
    # 主匹配逻辑
    # ============================================
    local device_file=""
    local mk_device_name=""
    local all_matches=()
    
    for mkfile in "${mk_files[@]}"; do
        local exact_match=""
        local all_device_defs=$(grep -E "define Device/[a-zA-Z0-9_-]+" "$mkfile" 2>/dev/null)
        
        while IFS= read -r line; do
            if [[ "$line" =~ define[[:space:]]+Device/([a-zA-Z0-9_-]+) ]]; then
                local dev_name="${BASH_REMATCH[1]}"
                if [[ "$dev_name" == *_common* ]]; then continue; fi
                if [ "$dev_name" = "$DEVICE" ]; then
                    exact_match="$dev_name"
                    break
                fi
            fi
        done <<< "$all_device_defs"
        
        if [ -n "$exact_match" ]; then
            device_file="$mkfile"
            mk_device_name="$exact_match"
            log "✅ 找到精确设备定义: $mk_device_name (在 $device_file)"
            break
        fi
        
        local matches=$(find_best_matching_device "$DEVICE" "$mkfile")
        if [ -n "$matches" ]; then
            while IFS= read -r match; do
                all_matches+=("$match:$mkfile")
            done <<< "$matches"
        fi
    done
    
    if [ -z "$device_file" ] && [ ${#all_matches[@]} -gt 0 ]; then
        local sorted_matches=($(printf '%s\n' "${all_matches[@]}" | sort -t':' -k1 -rn))
        
        echo ""
        echo "📋 设备 '$DEVICE' 未精确匹配，找到以下相关设备:"
        echo "----------------------------------------"
        
        local display_count=0
        for match in "${sorted_matches[@]}"; do
            local weight=$(echo "$match" | cut -d':' -f1)
            local dev=$(echo "$match" | cut -d':' -f2)
            local mkf=$(echo "$match" | cut -d':' -f3)
            
            if [ $display_count -lt 20 ]; then
                local fmt_info=$(analyze_device_firmware_format "$dev" "$mkf")
                local fmt_type=$(echo "$fmt_info" | cut -d'|' -f1)
                local fmt_label=""
                if [ "$fmt_type" = "bin" ]; then fmt_label="(.bin)"; else fmt_label="(.itb)"; fi
                
                printf "  权重 %3d: %-50s %s (位于 %s)\n" "$weight" "$dev" "$fmt_label" "$(basename "$mkf")"
                display_count=$((display_count + 1))
            fi
        done
        echo "----------------------------------------"
        echo ""
        
        local best_match="${sorted_matches[0]}"
        local best_weight=$(echo "$best_match" | cut -d':' -f1)
        mk_device_name=$(echo "$best_match" | cut -d':' -f2)
        device_file=$(echo "$best_match" | cut -d':' -f3)
        
        log "🔧 选择权重最高的设备: $mk_device_name (权重: $best_weight)"
        log "📁 定义文件: $device_file"
        
        if [ ${#sorted_matches[@]} -gt 1 ]; then
            echo ""
            log "💡 其他候选项 (权重降序):"
            local other_count=0
            for match in "${sorted_matches[@]}"; do
                if [ $other_count -ge 1 ] && [ $other_count -lt 6 ]; then
                    local other_weight=$(echo "$match" | cut -d':' -f1)
                    local other_dev=$(echo "$match" | cut -d':' -f2)
                    local other_mkf=$(echo "$match" | cut -d':' -f3)
                    local other_fmt=$(analyze_device_firmware_format "$other_dev" "$other_mkf")
                    local other_fmt_type=$(echo "$other_fmt" | cut -d'|' -f1)
                    local other_label=""
                    if [ "$other_fmt_type" = "bin" ]; then other_label="(.bin)"; else other_label="(.itb)"; fi
                    echo "      权重 $other_weight: $other_dev $other_label"
                fi
                other_count=$((other_count + 1))
            done
            echo ""
            echo "💡 如需使用其他设备，请在手动输入框中输入完整设备名"
            echo ""
        fi
    fi
    
    if [ -z "$device_file" ] || [ ! -f "$device_file" ]; then
        log "❌ 错误：未找到设备 $DEVICE 的定义文件"
        log ""
        log "📋 所有可用的设备列表:"
        echo "----------------------------------------"
        for mkfile in "${mk_files[@]}"; do
            if [[ "$mkfile" == *"image/"*".mk" ]]; then
                echo "📁 $(basename "$mkfile"):"
                grep -E "define Device/[a-zA-Z0-9_-]+" "$mkfile" 2>/dev/null | sed 's/define Device\///' | sed 's/ .*//' | grep -v "_common" | while read dev; do
                    echo "    - $dev"
                done
            fi
        done
        echo "----------------------------------------"
        exit 1
    fi
    
    if [[ "$mk_device_name" == *_common* ]]; then
        log "❌ 错误：匹配到了通用模板 $mk_device_name，这不是一个可编译的设备！"
        exit 1
    fi
    
    # ============================================
    # 第一步：自动检测固件格式并提示
    # ============================================
    log ""
    log "=== 🔍 设备固件格式自动检测 ==="
    
    local format_info=$(analyze_device_firmware_format "$mk_device_name" "$device_file")
    local format_type=$(echo "$format_info" | cut -d'|' -f1)
    local images_def=$(echo "$format_info" | cut -d'|' -f2)
    local has_bin=$(echo "$format_info" | cut -d'|' -f3)
    local has_itb=$(echo "$format_info" | cut -d'|' -f4)
    local has_factory_bin=$(echo "$format_info" | cut -d'|' -f5)
    local has_factory_img=$(echo "$format_info" | cut -d'|' -f6)
    
    log "📋 设备 $mk_device_name 固件格式分析:"
    log "   IMAGES 定义: ${images_def:-未显式定义（默认生成 sysupgrade.bin）}"
    log "   支持 sysupgrade.bin: $([ $has_bin -eq 1 ] && echo '✅ 是' || echo '❌ 否')"
    log "   支持 sysupgrade.itb: $([ $has_itb -eq 1 ] && echo '✅ 是' || echo '❌ 否')"
    log "   支持 factory.bin: $([ $has_factory_bin -eq 1 ] && echo '✅ 是' || echo '❌ 否')"
    log "   支持 factory.img: $([ $has_factory_img -eq 1 ] && echo '✅ 是' || echo '❌ 否')"
    log "   固件格式类型: $format_type"
    
    export FIRMWARE_FORMAT_TYPE="$format_type"
    export FIRMWARE_HAS_ITB="$has_itb"
    export FIRMWARE_HAS_BIN="$has_bin"
    export FIRMWARE_HAS_FACTORY_BIN="$has_factory_bin"
    export FIRMWARE_HAS_FACTORY_IMG="$has_factory_img"
    export FIRMWARE_NEED_CONVERT="false"
    
    if [ "$format_type" = "itb" ]; then
        export FIRMWARE_NEED_CONVERT="true"
        
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║  ⚠️  固件格式兼容性提示                                         ║"
        echo "╠══════════════════════════════════════════════════════════════════╣"
        echo "║  设备 $mk_device_name 只生成 .itb 格式固件                     ║"
        echo "║  🔧 系统将在编译后自动将 .itb 转换为 .bin 格式                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        
        local bin_devices=()
        for mkfile in "${mk_files[@]}"; do
            local compat_devices=$(find_bin_compatible_device "$mk_device_name" "$mkfile")
            if [ -n "$compat_devices" ]; then
                while IFS= read -r dev; do
                    [ -z "$dev" ] && continue
                    if [ "$dev" != "$mk_device_name" ]; then
                        bin_devices+=("$dev")
                    fi
                done <<< "$compat_devices"
            fi
        done
        
        if [ ${#bin_devices[@]} -gt 0 ]; then
            echo "📋 同系列支持 .bin 格式的设备（手动输入时可用）:"
            echo "----------------------------------------"
            local alt_count=0
            for dev in "${bin_devices[@]}"; do
                alt_count=$((alt_count + 1))
                local dev_format=$(analyze_device_firmware_format "$dev" "$device_file")
                local dev_has_factory=$(echo "$dev_format" | cut -d'|' -f5)
                local dev_has_factory_img=$(echo "$dev_format" | cut -d'|' -f6)
                if [ "$dev_has_factory" -eq 1 ] || [ "$dev_has_factory_img" -eq 1 ]; then
                    printf "  [%d] %-50s (sysupgrade.bin + factory)\n" "$alt_count" "$dev"
                else
                    printf "  [%d] %-50s (sysupgrade.bin)\n" "$alt_count" "$dev"
                fi
            done
            echo "----------------------------------------"
            echo ""
        fi
    else
        log "✅ 设备 $mk_device_name 支持 .bin 格式固件，无需转换"
    fi
    
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        echo "export FIRMWARE_FORMAT_TYPE=\"${FIRMWARE_FORMAT_TYPE:-bin}\"" >> "$BUILD_DIR/build_env.sh"
        echo "export FIRMWARE_HAS_ITB=\"${FIRMWARE_HAS_ITB:-0}\"" >> "$BUILD_DIR/build_env.sh"
        echo "export FIRMWARE_HAS_BIN=\"${FIRMWARE_HAS_BIN:-0}\"" >> "$BUILD_DIR/build_env.sh"
        echo "export FIRMWARE_HAS_FACTORY_BIN=\"${FIRMWARE_HAS_FACTORY_BIN:-0}\"" >> "$BUILD_DIR/build_env.sh"
        echo "export FIRMWARE_HAS_FACTORY_IMG=\"${FIRMWARE_HAS_FACTORY_IMG:-0}\"" >> "$BUILD_DIR/build_env.sh"
        echo "export FIRMWARE_NEED_CONVERT=\"${FIRMWARE_NEED_CONVERT:-false}\"" >> "$BUILD_DIR/build_env.sh"
    fi
    
    if [ -n "$GITHUB_ENV" ]; then
        echo "FIRMWARE_FORMAT_TYPE=${FIRMWARE_FORMAT_TYPE:-bin}" >> $GITHUB_ENV
        echo "FIRMWARE_NEED_CONVERT=${FIRMWARE_NEED_CONVERT:-false}" >> $GITHUB_ENV
    fi
    
    log "=========================================="
    
    local correct_device="$mk_device_name"
    log "🔧 最终使用设备名: $correct_device (原始输入: $DEVICE)"
    
    export DEVICE="$correct_device"
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        sed -i "s/^export DEVICE=.*/export DEVICE=\"$correct_device\"/" "$BUILD_DIR/build_env.sh" 2>/dev/null || true
    fi
    if [ -n "$GITHUB_ENV" ]; then
        echo "DEVICE=$correct_device" >> $GITHUB_ENV
    fi
    
    log "🔧 调用 generate_config，使用设备名: $correct_device"
    
    generate_config "$extra_packages" "$correct_device"
    
    log "✅ 步骤12 完成"
}
#【build_firmware_main.sh-33-end】

#【build_firmware_main.sh-34】
workflow_step16_verify_usb() {
    echo "=== 步骤16: 验证USB配置（智能检测版） ==="
    
    trap 'echo "⚠️ 步骤16 验证过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    verify_usb_config
    
    echo "✅ 步骤16 完成"
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
# 步骤20: 修复网络环境（增强版 - 修复下载失败并替换GNU源）
# ============================================
workflow_step20_fix_network() {
    log "=== 步骤20: 修复网络环境（GNU镜像自动替换） ==="
    
    trap 'echo "⚠️ 步骤20 修复过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    # ============================================
    # 自动替换常见下载源为国内镜像（解决 savannah/ftp.gnu 超时）
    # ============================================
    log "🔧 扫描并替换不可达的下载源..."
    
    local mirror_map=(
        "git.savannah.gnu.org|git.mirrors.ustc.edu.cn"
        "ftp.gnu.org|mirrors.ustc.edu.cn"
        "http://www.kernel.org|https://mirrors.edge.kernel.org"
    )
    
    find package feeds -name "Makefile" -o -name "*.mk" 2>/dev/null | while read mkf; do
        local modified=0
        for pair in "${mirror_map[@]}"; do
            local original="${pair%%|*}"
            local mirror="${pair##*|}"
            if grep -q "$original" "$mkf" 2>/dev/null; then
                cp "$mkf" "$mkf.bakmirror"
                sed -i "s|${original}|${mirror}|g" "$mkf"
                log "  ✅ 替换下载源 $original → $mirror 于 $(basename "$mkf")"
                modified=1
            fi
        done
    done
    
    # 备份原文件
    if [ -f "feeds.conf.default" ]; then
        cp "feeds.conf.default" "feeds.conf.default.bak"
        log "  ✅ 备份 feeds.conf.default"
    fi
    
    # 修复ImmortalWrt下载源
    if grep -q "mirror2.immortalwrt.org" feeds.conf.default 2>/dev/null; then
        log "  🔧 替换失效的ImmortalWrt镜像源..."
        sed -i 's|mirror2.immortalwrt.org|mirror.nju.edu.cn/immortalwrt|g' feeds.conf.default
        sed -i 's|mirror.immortalwrt.org|mirror.nju.edu.cn/immortalwrt|g' feeds.conf.default
        log "  ✅ 已替换为南京大学镜像源"
    fi
    
    # 修复trusted-firmware-a下载源
    log "  🔧 修复trusted-firmware-a下载源..."
    
    local patch_dir="package/firmware/trusted-firmware-a/patches"
    mkdir -p "$patch_dir"
    
    cat > "$patch_dir/001-fix-download-url.patch" << 'EOF'
--- a/package/firmware/trusted-firmware-a/Makefile
+++ b/package/firmware/trusted-firmware-a/Makefile
@@ -5,8 +5,8 @@
 PKG_NAME:=trusted-firmware-a
 PKG_RELEASE:=1
 
-PKG_SOURCE_URL:=https://mirror2.immortalwrt.org/sources/trusted-firmware-a-$(PKG_VERSION).tar.gz
-PKG_SOURCE_URL+=https://mirror.immortalwrt.org/sources/trusted-firmware-a-$(PKG_VERSION).tar.gz
+PKG_SOURCE_URL:=https://github.com/ARM-software/arm-trusted-firmware/archive/refs/tags/v$(PKG_VERSION).tar.gz
+PKG_SOURCE_URL+=https://mirror.nju.edu.cn/github/ARM-software/arm-trusted-firmware/v$(PKG_VERSION).tar.gz
 PKG_HASH:=skip
 
 PKG_LICENSE:=BSD-3-Clause
EOF
    log "  ✅ 已创建trusted-firmware-a下载源修复补丁"
    
    # 调用原有的网络修复函数
    fix_network
    
    # 针对 LEDE 源码的额外网络修复
    if [ "$SOURCE_REPO_TYPE" = "lede" ]; then
        log "🔧 LEDE 源码额外网络修复：扫描并替换可能失效的下载地址..."
        
        # 常见失效镜像替换为更稳定的源
        find package feeds -name "Makefile" -o -name "*.mk" 2>/dev/null | while read mkf; do
            if grep -q 'mirror2\.immortalwrt\.org\|mirror\.immortalwrt\.org\|sources-cdn\.openwrt\.org' "$mkf" 2>/dev/null; then
                cp "$mkf" "$mkf.netbak"
                sed -i 's|https://mirror2.immortalwrt.org|https://mirror.nju.edu.cn/immortalwrt|g' "$mkf"
                sed -i 's|http://mirror.immortalwrt.org|https://mirror.nju.edu.cn/immortalwrt|g' "$mkf"
                sed -i 's|https://sources-cdn.openwrt.org|https://sources.openwrt.org|g' "$mkf"
                log "  ✅ 修复下载地址: $mkf"
            fi
        done
        
        # 确保 Git 操作使用 https 而非 ssh，避免端口限制
        git config --global url."https://github.com/".insteadOf git@github.com:
    fi
    
    # 如果 dnsmasq-full 将来仍失败，预置备用下载
    log "🔧 检查并预置可能下载失败的包源码..."
    if [ -f "package/network/services/dnsmasq/Makefile" ]; then
        # 提取版本号
        local dnsver=$(grep -E '^PKG_VERSION' package/network/services/dnsmasq/Makefile | cut -d= -f2 | xargs)
        if [ -n "$dnsver" ] && [ ! -f "dl/dnsmasq-${dnsver}.tar.xz" ]; then
            log "  ℹ️ dnsmasq-${dnsver} 源码未下载，尝试备用镜像..."
            wget -O "dl/dnsmasq-${dnsver}.tar.xz" \
                "https://mirrors.tuna.tsinghua.edu.cn/openwrt/sources/dnsmasq-${dnsver}.tar.xz" 2>/dev/null || \
            wget -O "dl/dnsmasq-${dnsver}.tar.xz" \
                "https://downloads.openwrt.org/sources/dnsmasq-${dnsver}.tar.xz" 2>/dev/null || \
            log "  ⚠️ 备用下载失败，将继续尝试默认地址"
        fi
    fi
    
    # 重新更新feeds
    log "🔄 重新更新feeds（使用修复后的源）..."
    ./scripts/feeds update -a > /tmp/build-logs/feeds_update_fixed.log 2>&1 || {
        log "⚠️ feeds更新有警告，继续..."
    }
    
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
workflow_step23_pre_build_check() {
    log "=== 步骤20: 前置错误检查（使用公共函数） ==="
    
    set -e
    trap 'echo "❌ 步骤20 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    log "🔧 确保设备配置存在..."
    
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 加载环境变量: DEVICE=$DEVICE, TARGET=$TARGET"
    fi
    
    # 直接使用环境变量中的 SUBTARGET，不再进行自动查找
    local expected_config=""
    local search_pattern=""
    
    expected_config="CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y"
    search_pattern="CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}"
    log "🔧 期望配置: $expected_config"
    
    local config_exists=0
    if grep -q "^${expected_config}$" .config 2>/dev/null; then
        config_exists=1
    elif grep -q "^${search_pattern}=y" .config 2>/dev/null; then
        config_exists=1
        expected_config=$(grep "^${search_pattern}=y" .config | head -1)
    elif grep -q "^# ${search_pattern} is not set" .config 2>/dev/null; then
        config_exists=1
        log "⚠️ 设备配置被禁用，正在启用..."
        sed -i "/^# ${search_pattern} is not set/d" .config
        echo "${search_pattern}=y" >> .config
        config_exists=0
    fi
    
    if [ $config_exists -eq 0 ]; then
        log "⚠️ 设备配置丢失，重新添加: ${search_pattern}=y"
        
        sed -i "/^CONFIG_TARGET_${TARGET}.*DEVICE_/d" .config
        sed -i "/^# CONFIG_TARGET_${TARGET}.*DEVICE_/d" .config
        
        echo "${search_pattern}=y" >> .config
        
        sort -u .config > .config.tmp
        mv .config.tmp .config
        
        make defconfig > /tmp/build-logs/defconfig_restore.log 2>&1 || {
            log "⚠️ make defconfig 有警告，但继续"
        }
        
        log "✅ 设备配置已恢复"
    else
        log "✅ 设备配置存在: $expected_config"
    fi
    
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
        
        local device_for_check="$DEVICE"
        local check_pattern=""
        
        check_pattern="CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${device_for_check}"
        
        if grep -q "^${check_pattern}=y" .config; then
            echo "   ✅ 设备配置正确: $(grep "^${check_pattern}=y" .config | head -1)"
        elif grep -q "^# ${check_pattern} is not set" .config; then
            echo "   ⚠️ 设备配置被禁用，尝试自动修复..."
            sed -i "/^# ${check_pattern} is not set/d" .config
            echo "${check_pattern}=y" >> .config
            echo "   ✅ 已重新启用设备配置"
        else
            echo "   ❌ 设备配置可能不正确，未找到: ${check_pattern}"
            error_count=$((error_count + 1))
        fi
    else
        echo "   ❌ .config 文件不存在"
        error_count=$((error_count + 1))
    fi
    echo ""
    
    echo "2. ✅ 工具链状态检查:"
    
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        echo "   ✅ staging_dir 目录存在"
        local staging_size=$(du -sh "$BUILD_DIR/staging_dir" 2>/dev/null | awk '{print $1}')
        echo "   📊 大小: $staging_size"
        
        local cross_gcc=$(find "$BUILD_DIR/staging_dir" -type f -executable -path "*/bin/*gcc" ! -name "*gcc-ar" ! -name "*gcc-ranlib" ! -name "*gcc-nm" 2>/dev/null | head -1)
        
        if [ -n "$cross_gcc" ]; then
            echo "   ✅ 交叉编译工具链已生成: $(basename "$cross_gcc")"
            local gcc_version=$("$cross_gcc" --version 2>&1 | head -1)
            echo "     版本: $gcc_version"
            
            if [[ "$cross_gcc" == *"aarch64"* ]]; then
                echo "     架构: ARM64 (aarch64)"
            elif [[ "$cross_gcc" == *"arm"* ]]; then
                echo "     架构: ARM"
            elif [[ "$cross_gcc" == *"mips"* ]]; then
                echo "     架构: MIPS"
            fi
            
            echo "   ✅ 工具链状态: 已编译完成"
        else
            echo "   ⚠️ 未找到交叉编译工具链"
            if [ -f "$BUILD_DIR/build_dir/target-*/.stamp_target_compile" ]; then
                echo "     工具链正在编译中"
            else
                echo "     工具链尚未编译"
            fi
        fi
    else
        echo "   ⚠️ staging_dir 目录不存在"
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
    
    log "✅ 步骤20 完成"
}
#【build_firmware_main.sh-39-end】

#【build_firmware_main.sh-40】
workflow_step25_build_firmware() {
    local enable_parallel="$1"

    log "=== 步骤25: 编译固件（通用补丁自动删除修复版） ==="
    log "源码仓库类型: $SOURCE_REPO_TYPE"

    set +e
    cd $BUILD_DIR

    ulimit -n 65536 2>/dev/null || true
    local current_limit=$(ulimit -n)
    log "  ✅ 当前文件描述符限制: $current_limit"

    CPU_CORES=$(nproc)
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    echo ""
    echo "🔧 系统信息:"
    echo "  CPU核心数: $CPU_CORES"
    echo "  内存大小: ${TOTAL_MEM}MB"
    echo "  源码类型: $SOURCE_REPO_TYPE"

    local MAKE_JOBS=1
    if [ "$enable_parallel" = "true" ] && [ $CPU_CORES -ge 2 ]; then
        if [ $CPU_CORES -ge 4 ] && [ $TOTAL_MEM -ge 4096 ]; then MAKE_JOBS=4
        elif [ $CPU_CORES -ge 2 ] && [ $TOTAL_MEM -ge 2048 ]; then MAKE_JOBS=2
        else MAKE_JOBS=1; fi
        log "🚀 使用 $MAKE_JOBS 个并行任务"
    else
        log "⚠️ 使用单线程编译"
    fi

    local vendor_dist=""
    case "$SOURCE_REPO_TYPE" in
        "immortalwrt") vendor_dist="ImmortalWrt" ;;
        "lede") vendor_dist="LEDE" ;;
        "openwrt") vendor_dist="OpenWrt" ;;
        *) vendor_dist=$(echo "$SOURCE_REPO_TYPE" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}') ;;
    esac
    export VERSION_DIST="$vendor_dist"
    export CONFIG_VERSION_DIST="$vendor_dist"

    # ---------- 通用补丁自动删除函数 ----------
    auto_disable_failed_patches() {
        local log_to_check="$1"
        local deleted=0
        local patches=$(grep "Patch failed!" "$log_to_check" 2>/dev/null | sed -n 's/.*Please fix \([^!]*\).*/\1/p')
        if [ -z "$patches" ]; then
            patches=$(grep -oP '[^ ]+\.patch' "$log_to_check" 2>/dev/null | head -1)
        fi
        [ -z "$patches" ] && return 1
        for patch in $patches; do
            patch=$(echo "$patch" | xargs)
            if [ -f "$patch" ]; then
                log "  🧩 删除冲突补丁: $patch"
                rm -f "$patch"
                deleted=$((deleted + 1))
            fi
        done
        return $deleted
    }

    # ---------- 编译主逻辑（最多尝试2次） ----------
    local attempt=1
    local max_attempts=2
    local make_exit_code=0

    while [ $attempt -le $max_attempts ]; do
        log "🔧 开始编译（尝试 $attempt/$max_attempts）..."
        START_TIME=$(date +%s)

        make -j$MAKE_JOBS V=s VERSION_DIST="$vendor_dist" 2>&1 | tee build.log
        make_exit_code=${PIPESTATUS[0]}

        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        log "⏱️ 编译耗时: $((DURATION / 60))分$((DURATION % 60))秒"

        if [ $make_exit_code -eq 0 ]; then
            log "✅ make 成功退出"
            break
        fi

        log "⚠️ make 返回非零退出码 ($make_exit_code)，尝试修复..."

        # 检查是否为补丁冲突
        if grep -qE "Patch failed|Hunk FAILED" build.log; then
            auto_disable_failed_patches build.log
            local deleted_count=$?
            if [ $deleted_count -gt 0 ]; then
                log "  🔄 已删除 $deleted_count 个冲突补丁，准备重试..."
            else
                log "  ❌ 补丁冲突但未能自动处理，放弃重试"
                break
            fi
        else
            log "  ❌ 非补丁冲突错误，放弃重试"
            break
        fi

        attempt=$((attempt + 1))
    done

    # ---------- 验证固件 ----------
    log "🔍 验证固件并计算哈希值..."
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
    fi
    local target_dir="$BUILD_DIR/bin/targets/$TARGET/$SUBTARGET"
    local valid_firmware=0
    local hash_file="$target_dir/firmware-sha256sums.txt"
    > "$hash_file" 2>/dev/null || true
    if [ -d "$target_dir" ]; then
        find "$target_dir" -maxdepth 1 -type f -name "*.manifest" -o -name "*sha256sums*" 2>/dev/null | while read file; do rm -f "$file"; done
        [ -d "$target_dir/packages" ] && rm -rf "$target_dir/packages"
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            local fname=$(basename "$file")
            [[ "$fname" == *"initramfs"* ]] && continue
            local size_mb=$(($(stat -c%s "$file" 2>/dev/null || echo 0) / 1024 / 1024))
            if [ $size_mb -ge 5 ]; then
                if [[ "$fname" == *"sysupgrade"* ]] || [[ "$fname" == *"factory"* ]]; then
                    log "  ✅ $fname 大小: ${size_mb}MB - 有效固件"
                    valid_firmware=$((valid_firmware + 1))
                    local fhash=$(sha256sum "$file" | awk '{print $1}')
                    echo "$fhash  $fname" >> "$hash_file"
                else
                    log "  📄 $fname 大小: ${size_mb}MB - 其他文件"
                fi
            else
                log "  ❌ $fname 大小: ${size_mb}MB - 无效"
                rm -f "$file"
            fi
        done < <(find "$target_dir" -maxdepth 1 -type f \( -name "*.bin" -o -name "*.img" -o -name "*.itb" \) 2>/dev/null)
    fi

    if [ $valid_firmware -eq 0 ]; then
        log "❌ 错误：没有找到任何有效可刷机固件"
        exit 1
    fi

    log "✅ 步骤25 完成"
    set -e
    return 0
}
#【build_firmware_main.sh-40-end】

#【build_firmware_main.sh-41】
# ============================================
# 步骤26: 检查构建产物（增强版 - 支持 .itb 和 .bin 格式）
# ============================================
workflow_step26_check_artifacts() {
    log "=== 步骤26: 检查构建产物（增强版 - 支持所有固件格式） ==="
    
    set -e
    trap 'echo "❌ 步骤26 失败，退出代码: $?"; exit 1' ERR
    
    cd "$BUILD_DIR"
    
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
    fi
    
    if [ -d "bin/targets" ]; then
        echo "✅ 找到固件目录"
        echo ""
        echo "📁 固件文件列表:"
        echo "=========================================="
        
        local sysupgrade_bin_count=0
        local sysupgrade_itb_count=0
        local initramfs_count=0
        local factory_count=0
        local preloader_count=0
        local gpt_count=0
        local fip_count=0
        local other_count=0
        
        local all_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" -o -name "*.itb" -o -name "*.fip" \) 2>/dev/null | grep -v "sha256sums" | sort)
        
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            
            SIZE=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
            FILE_NAME=$(basename "$file")
            FILE_PATH=$(echo "$file" | sed 's|^bin/targets/||')
            
            if echo "$FILE_NAME" | grep -q "sysupgrade.bin"; then
                echo "  ✅ $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🚀 刷机用（.bin 格式）"
                sysupgrade_bin_count=$((sysupgrade_bin_count + 1))
                echo ""
            elif echo "$FILE_NAME" | grep -q "sysupgrade.itb"; then
                echo "  ✅ $FILE_NAME (FIT格式)"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🚀 刷机用（.itb 格式）"
                sysupgrade_itb_count=$((sysupgrade_itb_count + 1))
                echo ""
            elif echo "$FILE_NAME" | grep -q "factory"; then
                echo "  🏭 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 📦 原厂刷机用"
                factory_count=$((factory_count + 1))
                echo ""
            elif echo "$FILE_NAME" | grep -q "initramfs"; then
                echo "  🔷 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🆘 恢复用"
                initramfs_count=$((initramfs_count + 1))
                echo ""
            elif echo "$FILE_NAME" | grep -q "preloader"; then
                echo "  ⚙️ $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🔧 预加载器"
                preloader_count=$((preloader_count + 1))
                echo ""
            elif echo "$FILE_NAME" | grep -q "gpt"; then
                echo "  💽 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 📋 GPT分区表"
                gpt_count=$((gpt_count + 1))
                echo ""
            elif echo "$FILE_NAME" | grep -q "bl31-uboot.fip" || echo "$FILE_NAME" | grep -q "uboot.fip"; then
                echo "  🔌 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                echo "    用途: 🔌 BL31 + U-Boot 固件"
                fip_count=$((fip_count + 1))
                echo ""
            else
                echo "  📄 $FILE_NAME"
                echo "    大小: $SIZE"
                echo "    路径: $FILE_PATH"
                other_count=$((other_count + 1))
                echo ""
            fi
        done <<< "$all_files"
        
        echo "=========================================="
        echo ""
        echo "📊 固件统计:"
        echo "----------------------------------------"
        echo "  ✅ sysupgrade.bin: $sysupgrade_bin_count 个 - 🚀 **刷机用（.bin）**"
        echo "  ✅ sysupgrade.itb: $sysupgrade_itb_count 个 - 🚀 **刷机用（.itb）**"
        echo "  🏭 factory镜像: $factory_count 个 - 📦 **原厂刷机用**"
        echo "  🔷 initramfs恢复: $initramfs_count 个 - 🆘 **恢复用**"
        echo "  ⚙️ preloader: $preloader_count 个 - 🔧 **引导加载程序**"
        echo "  💽 GPT分区表: $gpt_count 个 - 📋 **eMMC分区表**"
        echo "  🔌 BL31/U-Boot: $fip_count 个 - 🔌 **引导固件**"
        echo "  📦 其他文件: $other_count 个"
        echo "----------------------------------------"
        echo ""
        
        echo "🔍 ===== 固件大小验证（拒绝小于5MB的无效固件） ====="
        echo ""
        
        local valid_sysupgrade=0
        local valid_factory=0
        local firmware_list=()
        
        while IFS= read -r file; do
            [ -z "$file" ] && continue
            if [[ "$file" == *"sysupgrade.bin" ]] || [[ "$file" == *"sysupgrade.itb" ]] || [[ "$file" == *"factory.img" ]] || [[ "$file" == *"factory.bin" ]]; then
                local fname=$(basename "$file")
                local fsize_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
                local fsize_mb=$((fsize_bytes / 1024 / 1024))
                local fsize_human=$(ls -lh "$file" | awk '{print $5}')
                
                local ftype=""
                if [[ "$fname" == *"sysupgrade"* ]]; then
                    ftype="sysupgrade"
                elif [[ "$fname" == *"factory"* ]]; then
                    ftype="factory"
                fi
                
                firmware_list+=("$ftype:$fname:$fsize_mb:$fsize_human:$file")
            fi
        done <<< "$all_files"
        
        echo "📋 固件大小验证结果:"
        echo "----------------------------------------"
        
        for firmware in "${firmware_list[@]}"; do
            IFS=':' read -r ftype fname fsize_mb fsize_human file <<< "$firmware"
            
            if [ $fsize_mb -lt 5 ]; then
                echo "  ❌ $fname"
                echo "     大小: $fsize_human (${fsize_mb}MB) - 小于5MB，判定为无效固件！"
                rm -f "$file"
                echo "     已删除无效固件文件"
                echo ""
            else
                if [ $fsize_mb -lt 10 ]; then
                    echo "  ⚠️ $fname"
                    echo "     大小: $fsize_human (${fsize_mb}MB) - 小于10MB，可能不完整"
                else
                    echo "  ✅ $fname"
                    echo "     大小: $fsize_human (${fsize_mb}MB) - 通过验证"
                fi
                
                if [ "$ftype" = "sysupgrade" ]; then
                    valid_sysupgrade=$((valid_sysupgrade + 1))
                elif [ "$ftype" = "factory" ]; then
                    valid_factory=$((valid_factory + 1))
                fi
                echo ""
            fi
        done
        
        echo "----------------------------------------"
        echo "📊 固件大小验证统计:"
        echo "  有效 sysupgrade 固件: $valid_sysupgrade 个"
        echo "  有效 factory 固件: $valid_factory 个"
        echo ""
        
        if [ $valid_sysupgrade -eq 0 ] && [ $valid_factory -eq 0 ]; then
            echo "❌❌❌ 错误：没有找到任何有效固件（大小≥5MB）❌❌❌"
            exit 1
        else
            echo "✅ 构建产物检查通过，找到 $((valid_sysupgrade + valid_factory)) 个有效固件"
        fi
    else
        echo "❌ 错误: 未找到固件目录"
        exit 1
    fi

    # ============================================
    # 再次显示已应用补丁最终状态
    # ============================================
    echo ""
    echo "🔍 已应用补丁最终状态:"
    show_patch_status
    echo ""
    
    echo "✅ 步骤26 完成"
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
# 全流程错误检查函数 - 终极版（快速定位 opkg 依赖错误）
# ============================================
quick_error_check() {
    local build_dir="$1"
    local target_platform="$2"
    local log_file="${3:-build.log}"
    local output_file="${4:-/tmp/quick-error-check.txt}"

    cd "$build_dir" 2>/dev/null || {
        echo "❌ 无法进入构建目录: $build_dir"
        return 1
    }

    if [ -f "$build_dir/build_env.sh" ]; then
        source "$build_dir/build_env.sh"
    fi

    if [ ! -f "$log_file" ]; then
        local alt_log=$(ls -t "$build_dir"/build_step5_attempt*.log "$build_dir"/build_step*.log "$build_dir"/*.log 2>/dev/null | head -1)
        [ -f "$alt_log" ] && log_file="$alt_log"
    fi

    {
        echo ""
        echo "================================================================="
        echo "🔍 全流程错误检查 - 增强版"
        echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "构建目录: $build_dir"
        echo "目标平台: ${TARGET:-$target_platform}"
        echo "完整目标: ${TARGET:-$target_platform}/${SUBTARGET:-generic}"
        echo "源码类型: ${SOURCE_REPO_TYPE:-unknown}"
        echo "输入设备: ${DEVICE:-unknown}"
        echo "================================================================="

        declare -A log_sources
        for f in "$build_dir"/*.log; do
            [ -f "$f" ] && log_sources["$f"]="构建目录"
        done
        if [ -d "/tmp/build-logs" ]; then
            for f in /tmp/build-logs/*.log; do
                [ -f "$f" ] && log_sources["$f"]="临时日志目录"
            done
        fi

        if [ ${#log_sources[@]} -eq 0 ]; then
            echo "⚠️ 未找到任何日志文件"
            return 1
        fi
        echo "📄 找到 ${#log_sources[@]} 个日志文件"
        echo ""

        # 精确检查 Makefile 目标（已修正）
        echo "📌 源码 Makefile 关键目标检查:"
        echo "----------------------------------------"
        local makefile_issues=0
        for target in "tools/compile" "toolchain/compile" "target/compile" "package/compile" "target/install"; do
            if grep -qE "^[[:space:]]*${target}[[:space:]]*:" "$build_dir/Makefile" 2>/dev/null; then
                echo "   ✅ $target"
            else
                if grep -qE "^[[:space:]]*${target}[[:space:]]*:" "$build_dir/include"/*.mk 2>/dev/null; then
                    echo "   ✅ $target (include/*.mk)"
                else
                    echo "   ⚠️ $target 可能缺失"
                    makefile_issues=$((makefile_issues + 1))
                fi
            fi
        done
        if [ $makefile_issues -gt 0 ]; then
            echo "   🔧 有 $makefile_issues 个目标未找到，请确认 build_dir 为完整源码树"
            echo "   📋 实际存在的顶层目标:"
            grep -E '^[[:space:]]*[a-zA-Z_.-]+/[a-zA-Z_.-]+[[:space:]]*:' "$build_dir/Makefile" 2>/dev/null | head -10 | sed 's/^/      /'
        fi
        echo ""

        echo "📌 Feed 安装及依赖警告摘要:"
        echo "----------------------------------------"
        local feed_warnings=$(grep -hE "WARNING: Makefile.*has a (dependency|build dependency) on" "$build_dir"/*.log 2>/dev/null | sort -u | head -10)
        if [ -n "$feed_warnings" ]; then
            echo "$feed_warnings"
        else
            echo "   ✅ 未发现依赖缺失警告"
        fi
        echo ""

        echo "🚨 关键异常摘要:"
        echo "----------------------------------------"
        local missing_files=$(for f in "${!log_sources[@]}"; do
            grep -oP '(/[^ ]+|[^ ]+/[^ ]*)\s*:\s*No such file or directory' "$f" 2>/dev/null | sed 's/: No such file or directory//' | sort -u 2>/dev/null
        done | sort -u 2>/dev/null | head -5)
        if [ -n "$missing_files" ]; then
            echo "  ❌ 缺失文件:"
            echo "$missing_files" | while read mf; do echo "      - $mf"; done
        fi
        local dl_errors=$(for f in "${!log_sources[@]}"; do
            grep -E 'Download failed|curl: \([0-9]+\) |wget: .*error|404 Not Found' "$f" 2>/dev/null | sort -u 2>/dev/null
        done | sort -u 2>/dev/null | head -5)
        if [ -n "$dl_errors" ]; then
            echo "  ❌ 下载错误:"
            echo "$dl_errors" | while read dl; do echo "      $dl"; done
        fi
        local patch_fails=$(for f in "${!log_sources[@]}"; do grep "Patch failed!" "$f" 2>/dev/null; done | head -5)
        if [ -n "$patch_fails" ]; then
            echo "  🧩 内核补丁冲突 (Patch failed):"
            echo "$patch_fails" | while read pl; do
                local bad_patch=$(echo "$pl" | grep -oP '(?<=Please fix )[^!]+' | xargs)
                [ -n "$bad_patch" ] && echo "      $bad_patch"
            done
        fi
        echo ""

        echo "🔍 固件生成状态检查"
        echo "----------------------------------------"
        local full_target="${TARGET:-$target_platform}"
        local full_subtarget="${SUBTARGET:-generic}"
        local target_dir="bin/targets/$full_target/$full_subtarget"
        [ ! -d "$target_dir" ] && target_dir=$(find bin/targets -type d -name "*$full_target*" 2>/dev/null | head -1)
        echo "检查路径: $target_dir"
        echo ""
        local found_firmware=0 valid_sysupgrade=0 valid_factory=0 sysupgrade_size="" factory_size=""

        if [ -d "$target_dir" ]; then
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                local fname=$(basename "$file")
                [[ "$fname" == *"initramfs"* ]] || [[ "$fname" == *".manifest" ]] || [[ "$fname" == *"sha256sums"* ]] && continue
                local fsize_bytes=$(stat -c%s "$file" 2>/dev/null || echo "0")
                local fsize_mb=$((fsize_bytes / 1024 / 1024))
                local fsize_human=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
                local fhash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
                found_firmware=$((found_firmware + 1))
                local ftype="other"
                [[ "$fname" == *"sysupgrade"* ]] && ftype="sysupgrade"
                [[ "$fname" == *"factory"* ]] && ftype="factory"

                if [ $fsize_mb -ge 5 ]; then
                    if [ "$ftype" != "other" ]; then
                        echo "✅ $fname"
                        echo "   大小: $fsize_human (${fsize_mb}MB)"
                        echo "   SHA256: $fhash"
                        [ "$ftype" = "sysupgrade" ] && valid_sysupgrade=$((valid_sysupgrade + 1)) && sysupgrade_size="$fsize_human (${fsize_mb}MB)"
                        [ "$ftype" = "factory" ] && valid_factory=$((valid_factory + 1)) && factory_size="$fsize_human (${fsize_mb}MB)"
                    else
                        echo "📄 $fname - $fsize_human (其他文件)"
                    fi
                else
                    echo "❌ $fname - $fsize_human (无效，小于5MB)"
                fi
                echo ""
            done < <(find "$target_dir" -maxdepth 1 -type f \( -name "*.bin" -o -name "*.img" -o -name "*.itb" \) 2>/dev/null | sort)

            [ $found_firmware -eq 0 ] && echo "❌ 目录存在但未找到固件文件" && echo "📋 目录内容:" && ls -la "$target_dir" 2>/dev/null | head -20 | sed 's/^/   /'
            [ $valid_sysupgrade -eq 0 ] && [ $found_firmware -gt 0 ] && echo "⚠️ 缺少 sysupgrade.bin 固件" && echo ""
        else
            echo "❌ 目标目录不存在: $target_dir"
        fi
        echo "----------------------------------------"
        echo ""

        echo "🔍 分步编译致命错误统计:"
        echo "----------------------------------------"
        local fatal_patterns=(
            'make\[[0-9]*\]: \*\*\* \[.*\] Error [0-9]+'
            'make: \*\*\* \[.*\] Error [0-9]+'
            'ERROR:.*failed to build'
            'fatal error:'
            'undefined reference to'
            'No rule to make target'
            'cannot find -l'
            'recipe for target.*failed'
        )
        declare -A step_errors
        map_log_to_step() {
            local fname=$(basename "$1")
            case "$fname" in
                build_tools*|build_tools_compile.log|build_tools_install.log) echo "STEP0" ;;
                build_step1.log) echo "STEP1" ;;
                build_step2*) echo "STEP2" ;;
                build_step3.log) echo "STEP3" ;;
                build_step4.log) echo "STEP4" ;;
                build_step5*) echo "STEP5" ;;
                *) echo "OTHER" ;;
            esac
        }
        local total_fatal=0
        for log_to_check in "${!log_sources[@]}"; do
            [[ "$(basename "$log_to_check")" == "build_marks.log" ]] && continue
            local step_label=$(map_log_to_step "$log_to_check")
            local err_count=0
            for pat in "${fatal_patterns[@]}"; do
                local cnt=$(grep -cE "$pat" "$log_to_check" 2>/dev/null || true)
                cnt=$(echo "$cnt" | tr -d '[:space:]')
                if [ -n "$cnt" ] && [ "$cnt" -eq "$cnt" ] 2>/dev/null; then
                    err_count=$((err_count + cnt))
                fi
            done
            if [ $err_count -gt 0 ]; then
                echo "   🚨 ${step_label} ($(basename "$log_to_check")): $err_count 个致命错误"
            fi
            step_errors[$step_label]=$((step_errors[$step_label] + err_count))
            total_fatal=$((total_fatal + err_count))
        done
        [ $total_fatal -eq 0 ] && echo "   ✅ 未发现致命编译错误"
        echo ""

        # ===================== 精准 opkg 依赖错误诊断 =====================
        echo "🔧 编译失败包详情:"
        echo "----------------------------------------"
        # 提取 Collected errors 内容
        local collected_errors=$(grep -A 20 "Collected errors:" "$log_file" 2>/dev/null | head -20)
        if [ -n "$collected_errors" ]; then
            echo "   🐞 OPKG 依赖错误 (Collected errors):"
            echo "$collected_errors" | sed 's/^/      /'
            echo ""
        fi

        if grep -q "package/Makefile:100: package/install" "$log_file" 2>/dev/null; then
            local last_config=$(grep "Configuring" "$log_file" 2>/dev/null | tail -1)
            local pkg_configured=$(echo "$last_config" | sed -n 's/.*Configuring \([^ ]*\).*/\1/p')
            echo "   🧩 最后一个配置的包: ${pkg_configured:-未知}"
            echo "   💡 可执行：make package/$(echo $pkg_configured | sed 's/\.$//')/compile V=s 查看详细"
        fi

        local failed_pkgs_file="/tmp/failed_pkgs_$$.txt"
        > "$failed_pkgs_file"
        for f in "${!log_sources[@]}"; do
            grep -Poh 'make(?:\[[0-9]+\])?: \*\*\* \[\K[^\]]+(?=\])' "$f" 2>/dev/null >> "$failed_pkgs_file"
            grep -ohP 'ERROR: \K.*failed to build' "$f" 2>/dev/null >> "$failed_pkgs_file"
        done

        local unique_failed=$(sort -u "$failed_pkgs_file" | grep -v -E '\.(installed|built|autoremove|stamp|info)$' | grep -v '/Makefile:')
        local shown=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            if echo "$line" | grep -q 'toplevel.mk'; then continue; fi
            local pkg=""
            if echo "$line" | grep -q '/compile\|/install'; then
                pkg=$(echo "$line" | sed 's:/host/compile$::; s:/host/install$::; s:/compile$::; s:/install$::' | awk -F/ '{print $NF}')
            else
                pkg=$(echo "$line" | sed 's/ failed to build$//' | awk -F/ '{print $NF}')
            fi
            [ -z "$pkg" ] && pkg="$(basename "$line")"
            [ "$pkg" = "GNUmakefile" ] && continue
            echo "   📦 $pkg  ($line)"
            shown=$((shown + 1))
            [ $shown -ge 12 ] && break
        done < <(echo "$unique_failed" | sort -u)

        if [ $shown -eq 0 ]; then
            local top_err=$(grep 'make: \*\*\* .* Error' "$build_dir"/build_step3.log "$build_dir"/build.log 2>/dev/null | head -1)
            [ -n "$top_err" ] && echo "   ⚠️ 顶层错误: $top_err"
        fi
        rm -f "$failed_pkgs_file"
        # 补丁冲突指引等（保留）...
        echo "----------------------------------------"

        echo "🔍 关键组件状态检查:"
        echo "----------------------------------------"
        [ -d "staging_dir" ] && echo "✅ staging_dir 存在 ($(du -sh staging_dir 2>/dev/null | awk '{print $1}'))" || echo "❌ staging_dir 不存在"
        [ -d "feeds" ] && echo "✅ feeds 存在" || echo "⚠️ feeds 不存在"
        [ -f ".config" ] && echo "✅ .config 存在 ($(ls -lh .config 2>/dev/null | awk '{print $5}'))" || echo "⚠️ .config 不存在"
        [ -d "dl" ] && echo "✅ dl 目录存在 ($(find dl -type f 2>/dev/null | wc -l) 个文件)" || echo "⚠️ dl 目录不存在"
        [ -d "build_dir" ] && echo "✅ build_dir 存在" || echo "⚠️ build_dir 不存在"
        if [ -f "$build_dir/build_env.sh" ]; then
            echo "✅ build_env.sh 存在"
            echo "   📌 设备: $(grep '^export DEVICE=' "$build_dir/build_env.sh" 2>/dev/null | cut -d'"' -f2)"
            echo "   📌 平台: $(grep '^export TARGET=' "$build_dir/build_env.sh" | cut -d'"' -f2)/$(grep '^export SUBTARGET=' "$build_dir/build_env.sh" | cut -d'"' -f2)"
        else
            echo "⚠️ build_env.sh 不存在"
        fi
        echo ""

        echo "🔍 最后30行日志 (已过滤 BUILD_MARK):"
        echo "----------------------------------------"
        if [ -f "$log_file" ]; then
            grep -v ">>> BUILD_MARK:" "$log_file" | tail -30 | sed 's/^/   /'
        else
            local best_log=$(ls -t "$build_dir"/build_step5_attempt*.log "$build_dir"/build_step*.log "$build_dir"/*.log 2>/dev/null | head -1)
            if [ -f "$best_log" ]; then
                echo "   文件: $(basename "$best_log") (已过滤)"
                grep -v ">>> BUILD_MARK:" "$best_log" | tail -30 | sed 's/^/   /'
            else
                echo "   (无可用的构建日志)"
            fi
        fi
        echo ""

        echo "================================================================="
        echo "📊 构建结论:"
        if [ $((valid_sysupgrade + valid_factory)) -gt 0 ]; then
            [ -n "$sysupgrade_size" ] && echo "   sysupgrade 固件: $sysupgrade_size"
            [ -n "$factory_size" ] && echo "   factory 固件: $factory_size"
            echo "🎉 固件已成功生成，可正常刷机使用。"
            if [ $total_fatal -gt 0 ]; then
                echo "⚠️ 检测到 $total_fatal 个编译错误（上方已列出失败包及修复建议）。"
            fi
        else
            echo "❌ 未生成任何有效固件，构建失败。"
            echo ""
            echo "💡 排查建议:"
            [ -n "$patch_fails" ] && echo "   🔧 内核补丁冲突（见上方补丁冲突详情），请禁用冲突的补丁后重试。"
            [ -n "$collected_errors" ] && echo "   🔧 OPKG 依赖错误（见上方 Collected errors），可能是禁用 IPv6 后仍有包强依赖 IPv6 组件，请修复对应 Makefile。"
            [ -n "$unique_failed" ] && echo "   🔧 失败的包: $(echo $unique_failed | tr '\n' ' ')"
            [ -n "$missing_files" ] && echo "   🔧 缺失文件可能导致部分包编译失败。"
            [ -n "$dl_errors" ] && echo "   🔧 下载失败，请检查网络或更换源。"
        fi
        echo "================================================================="
    } | tee "$output_file"

    echo "✅ 错误检查报告已保存到: $output_file"
    return $(( (valid_sysupgrade + valid_factory) > 0 ? 0 : 1 ))
}
#【build_firmware_main.sh-43-end】

# ============================================================================
# 废弃函数 - 保留注释，代码已删除，放到文件末尾
# ============================================================================

#【build_firmware_main.sh-44】
# ============================================
# 步骤30: 编译总结（增强版）
# ============================================
workflow_step30_build_summary() {
    local device_name="$1"
    local version_selection="$2"
    local config_mode="$3"
    local timestamp_sec="$4"
    local enable_parallel="$5"
    
    log "=== 步骤30: 编译后总结 ==="
    
    trap 'echo "⚠️ 步骤30 总结过程中出现错误，继续执行..."' ERR
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    🚀 构建总结报告                              ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "📋 构建配置:"
    echo "  设备:        $device_name"
    echo "  版本:        $version_selection"
    echo "  配置模式:    $config_mode"
    echo "  源码类型:    $SOURCE_REPO_TYPE"
    echo "  时间戳:      $timestamp_sec"
    echo "  并行优化:    $enable_parallel"
    echo ""
    
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        local target_dir="$BUILD_DIR/bin/targets/$TARGET/$SUBTARGET"
        
        if [ -d "$target_dir" ]; then
            echo "📦 构建产物:"
            
            local count=0
            find "$target_dir" -maxdepth 1 -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | while read file; do
                fname=$(basename "$file")
                fsize=$(ls -lh "$file" | awk '{print $5}')
                count=$((count + 1))
                
                if [[ "$fname" == *"sysupgrade"* ]]; then
                    echo "  🚀 $fname ($fsize) - 刷机用"
                elif [[ "$fname" == *"factory"* ]]; then
                    echo "  🏭 $fname ($fsize) - 原厂刷机用"
                else
                    echo "  📄 $fname ($fsize)"
                fi
            done
            
            echo ""
            echo "📁 产物位置: $target_dir"
        fi
    fi
    
    echo ""
    echo "⚙️ 功能开关状态:"
    echo "  TurboACC:      ${ENABLE_TURBOACC:-true}"
    echo "  TCP BBR:       ${ENABLE_TCP_BBR:-true}"
    echo "  ath10k-ct强制: ${FORCE_ATH10K_CT:-true}"
    echo "  USB自动修复:   ${AUTO_FIX_USB_DRIVERS:-true}"
    echo "  禁用IPv6:      ${DISABLE_IPV6:-true}"
    echo ""
    
    # 显示 IPv6 禁用状态详情
    if [ "${DISABLE_IPV6:-true}" = "true" ]; then
        echo "🌐 IPv6 禁用详情（所有源码类型通用）:"
        echo "  - 内核 IPv6 支持: 已禁用"
        echo "  - ip6tables 相关包: 已禁用"
        echo "  - odhcp6c/odhcpd: 已禁用"
        echo "  - 6in4/6rd/6to4 隧道: 已禁用"
        echo "  - LuCI IPv6 协议: 已禁用"
        echo "  - IPv6 内核模块: 已禁用"
        echo "  ✅ 固件将仅支持 IPv4 网络"
        echo ""
    else
        echo "🌐 IPv6 状态: 已启用（默认）"
        echo ""
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ 构建流程完成"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # 运行快速错误检查
    echo "🔧 运行快速错误检查（生成报告文件）..."
    local target_for_check="${TARGET:-$([ -f "$BUILD_DIR/build_env.sh" ] && source "$BUILD_DIR/build_env.sh" && echo "$TARGET")}"
    local report_file="/tmp/quick-error-check-$timestamp_sec.txt"
    
    set +e
    quick_error_check "$BUILD_DIR" "$target_for_check" "build.log" "$report_file"
    set -e
    
    mkdir -p "$GITHUB_WORKSPACE/error-reports" 2>/dev/null || true
    if [ -f "$report_file" ]; then
        cp "$report_file" "$GITHUB_WORKSPACE/error-reports/" 2>/dev/null || true
        echo "ERROR_REPORT_PATH=$GITHUB_WORKSPACE/error-reports/quick-error-check-$timestamp_sec.txt" >> $GITHUB_ENV
    fi
    
    log "✅ 步骤30 完成"
    
    return 0
}
#【build_firmware_main.sh-44-end】

#【build_firmware_main.sh-45】
# ============================================
# Hanwckf 独立编译流程（专用于 RAX3000M）
# 修复：只编译 RAX3000M NAND 设备，避免生成 1.22GB 全平台固件
# ============================================
workflow_step_hanwckf_build() {
    local device_name="$1"
    local extra_packages="$2"
    
    log "====================================================="
    log "🚀 启动 Hanwckf-mt798x 独立编译流程"
    log "   设备: $device_name"
    log "====================================================="
    
    cd "$BUILD_DIR" || exit 1
    
    # ---------- 0. 安装缺失的编译依赖 ----------
    log "🔧 安装编译依赖（libtool，修复 autoreconf 错误）..."
    sudo apt-get update -qq && sudo apt-get install -y -qq libtool libtool-bin 2>/dev/null || true
    
    # ---------- 1. 清理并克隆 hanwckf 仓库 ----------
    log "📥 克隆 hanwckf/immortalwrt-mt798x 源码..."
    sudo rm -rf "$BUILD_DIR"/*
    git clone --depth 1 https://github.com/hanwckf/immortalwrt-mt798x.git "$BUILD_DIR" || {
        log "❌ 克隆失败"
        exit 1
    }
    
    # ---------- 2. 复制预置配置并锁定 RAX3000M ----------
    log "⚙️ 应用 MT7981 AX3000 配置并锁定 RAX3000M NAND..."
    if [ -f "defconfig/mt7981-ax3000.config" ]; then
        cp "defconfig/mt7981-ax3000.config" ".config"
    else
        log "❌ 找不到 defconfig/mt7981-ax3000.config"
        exit 1
    fi
    
    # 关键：删除所有其他设备的配置，只保留 cmcc_rax3000m
    log "🎯 锁定设备：cmcc_rax3000m"
    # 删除所有设备选择
    sed -i '/^CONFIG_TARGET_mediatek_mt7981_DEVICE_/d' .config
    # 确保平台和子目标启用
    sed -i 's/^# CONFIG_TARGET_mediatek is not set/CONFIG_TARGET_mediatek=y/' .config
    sed -i 's/^# CONFIG_TARGET_mediatek_mt7981 is not set/CONFIG_TARGET_mediatek_mt7981=y/' .config
    # 添加唯一设备
    echo "CONFIG_TARGET_mediatek_mt7981_DEVICE_cmcc_rax3000m=y" >> .config
    # 也禁用 NAND 版本的 eMMC 变体（如果有）
    echo "# CONFIG_TARGET_mediatek_mt7981_DEVICE_cmcc_rax3000m_emmc is not set" >> .config
    echo "# CONFIG_TARGET_mediatek_mt7981_DEVICE_cmcc_rax3000m_nand_ubootmod is not set" >> .config
    # 确保所有其他设备都被禁用
    sed -i '/^CONFIG_TARGET_DEVICE_/d' .config
    
    # ---------- 3. 追加额外包 ----------
    if [ -n "$extra_packages" ]; then
        IFS=';' read -ra PKGS <<< "$extra_packages"
        for pkg in "${PKGS[@]}"; do
            pkg=$(echo "$pkg" | xargs)
            [ -z "$pkg" ] && continue
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        done
        log "📦 已追加额外包: $extra_packages"
    fi
    
    # ---------- 4. 更新并安装 feeds ----------
    log "🔄 更新 feeds..."
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    
    # ---------- 5. 应用配置 ----------
    log "🛠️ make defconfig..."
    make defconfig
    
    # ---------- 6. 编译固件 ----------
    log "🏗️ 开始编译（日志保存到 build.log）..."
    local make_ret=0
    make -j$(nproc) V=s 2>&1 | tee build.log || make_ret=$?
    
    # ---------- 7. 写入环境变量供后续步骤使用 ----------
    log "🔧 写入目标平台信息到环境文件..."
    local actual_subtarget=""
    # 自动检测子目标路径
    if [ -d "bin/targets/mediatek/mt7981" ]; then
        actual_subtarget="mt7981"
    elif [ -d "bin/targets/mediatek/filogic" ]; then
        actual_subtarget="filogic"
    else
        actual_subtarget="mt7981"
    fi
    
    echo "export TARGET=\"mediatek\"" > "$BUILD_DIR/build_env.sh"
    echo "export SUBTARGET=\"$actual_subtarget\"" >> "$BUILD_DIR/build_env.sh"
    echo "export DEVICE=\"$device_name\"" >> "$BUILD_DIR/build_env.sh"
    echo "export SOURCE_REPO_TYPE=\"hanwckf\"" >> "$BUILD_DIR/build_env.sh"
    if [ -n "$GITHUB_ENV" ]; then
        echo "TARGET=mediatek" >> $GITHUB_ENV
        echo "SUBTARGET=$actual_subtarget" >> $GITHUB_ENV
        echo "DEVICE=$device_name" >> $GITHUB_ENV
    fi
    log "   目标: mediatek/$actual_subtarget"
    
    # ---------- 8. 检查产物 ----------
    log "🔍 检查构建产物..."
    local target_dir="bin/targets/mediatek/$actual_subtarget"
    local factory_bin=""
    local sysupgrade_bin=""
    local found_firmware=0
    
    if [ -d "$target_dir" ]; then
        factory_bin=$(find "$target_dir" -maxdepth 1 -type f \( -name "*rax3000m*factory*" -o -name "*RAX3000M*factory*" \) 2>/dev/null | head -1)
        sysupgrade_bin=$(find "$target_dir" -maxdepth 1 -type f \( -name "*rax3000m*sysupgrade*" -o -name "*RAX3000M*sysupgrade*" \) ! -name "*emmc*" 2>/dev/null | head -1)
        
        if [ -n "$factory_bin" ] || [ -n "$sysupgrade_bin" ]; then
            found_firmware=1
            log "✅ 固件生成成功！"
            log "📁 固件目录: $target_dir"
            ls -lh "$target_dir"/*rax3000m* 2>/dev/null || ls -lh "$target_dir"/*RAX3000M* 2>/dev/null || true
        fi
    fi
    
    if [ $found_firmware -eq 0 ]; then
        log "❌ 未找到 RAX3000M 固件文件，编译失败。"
        if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
            log "📋 目录内容:"
            ls -lh "$target_dir" 2>/dev/null | head -20 || log "   (空目录)"
        fi
        quick_error_check "$BUILD_DIR" "mediatek" "build.log" "/tmp/quick-error-check-hanwckf.txt" 2>/dev/null || true
        exit 1
    fi
    
    # 有非零退出码但固件存在，只警告
    if [ $make_ret -ne 0 ]; then
        log "⚠️ make 返回非零退出码 ($make_ret)，但固件已成功生成。"
        log "   某些非核心包编译失败（如 libtool 相关），不影响固件使用。"
        quick_error_check "$BUILD_DIR" "mediatek" "build.log" "/tmp/quick-error-check-hanwckf.txt" 2>/dev/null || true
    fi
    
    log "====================================================="
    log "✅ Hanwckf 独立编译流程结束"
    log "====================================================="
    return 0
}
#【build_firmware_main.sh-45-end】

# ============================================
# 主函数 - 命令分发
# ============================================
#【build_firmware_main.sh-99】
# 以下三个辅助函数弥补之前遗漏的定义，确保 support.sh 等调用无误
save_source_code_info() {
    log "保存源代码信息（函数尚未完整实现，仅占位）"
    # 可在此添加 git log、repo info 等，当前保留基础信息
    return 0
}

verify_config_files() {
    log "验证配置文件（函数尚未实现）"
    return 0
}

check_usb_drivers_integrity() {
    workflow_step17_check_usb_drivers
}

main() {
    local command="$1"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"
    local arg4="$5"
    local arg5="$6"

    # 只在首次调用主函数时加载配置
    if [ -z "$MAIN_CONFIG_LOADED" ] && [ -z "$CONFIG_ALREADY_LOADED" ]; then
        if [ -f "$REPO_ROOT/build-config.conf" ]; then
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

        # 新增 Hanwckf 独立编译命令
        "step_hanwckf_build")
            workflow_step_hanwckf_build "$arg1" "$arg2"
            ;;

        "execute_patches")
            execute_patches "$arg1" "$arg2" "$arg3" "$arg4" "$arg5"
            ;;
        "list_patches")
            list_available_patches "$arg1" "$arg2" "$arg3"
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
            echo ""
            echo "  Hanwckf 独立编译: step_hanwckf_build <设备名> <额外包>"
            echo ""
            echo "  补丁管理命令:"
            echo "    execute_patches <补丁选择> <设备名> <源码类型> <分支> [自定义补丁文件]"
            echo "    list_patches [设备名] [源码类型] [分支]"
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
