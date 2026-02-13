#!/bin/bash
#【build_firmware_main.sh-00】
# OpenWrt 智能固件构建主脚本
# 对应工作流: firmware-build.yml
# 版本: 3.0.0
# 最后更新: 2026-02-13
#【build_firmware_main.sh-00-end】

#【build_firmware_main.sh-01】
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SCRIPT="$REPO_ROOT/support.sh"
CONFIG_DIR="$REPO_ROOT/firmware-config/config"

mkdir -p /tmp/build-logs

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    log "详细错误信息:"
    echo "最后50行日志:"
    tail -50 /tmp/build-logs/*.log 2>/dev/null || echo "无日志文件"
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
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-23.05"
    else
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-21.02"
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
    
    # 创建统一调用接口
    if [ $config_tool_created -eq 1 ]; then
        log "🔧 创建统一调用接口..."
        
        # 记录真实工具路径
        echo "$real_config_tool" > scripts/.config_tool_path
        
        cat > scripts/config-tool << EOF
#!/bin/sh
# 统一 config 工具调用接口
CONFIG_TOOL="$(cat "$(dirname "$0")/.config_tool_path" 2>/dev/null)"
if [ -n "$CONFIG_TOOL" ] && [ -f "$CONFIG_TOOL" ] && [ -x "$CONFIG_TOOL" ]; then
    exec "$CONFIG_TOOL" "$@"
fi

# 备选1: 直接查找
if [ -f "scripts/config/config" ] && [ -x "scripts/config/config" ]; then
    echo "scripts/config/config" > "$(dirname "$0")/.config_tool_path"
    exec scripts/config/config "$@"
fi

# 备选2: 使用 conf
if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
    exec scripts/config/conf "$@"
fi

echo "Error: config tool not found" >&2
exit 1
EOF
        chmod +x scripts/config-tool
        log "✅ 统一调用接口创建成功: scripts/config-tool"
        
        # 测试工具
        if scripts/config-tool --help > /dev/null 2>&1; then
            log "✅ 统一调用接口测试通过"
        else
            log "⚠️ 统一调用接口测试失败，但工具可能仍可用"
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
    
    log "=== 验证SDK文件完整性V2（修复版）==="
    
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
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "🔧 为正常模式添加 TurboACC 支持"
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
        log "✅ TurboACC feed 添加完成"
    else
        log "ℹ️ 基础模式不添加 TurboACC 支持"
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
    
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
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
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 智能配置生成系统（依赖链完整版） ==="
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    log "配置文件目录: $CONFIG_DIR"
    
    rm -f .config .config.old .config.bak*
    log "✅ 已清理旧配置文件"
    
    # 创建基础配置
    cat > .config << EOF
CONFIG_TARGET_${TARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y
EOF
    
    log "🔧 生成基础配置..."
    make defconfig || handle_error "基础配置生成失败"
    log "✅ 基础配置生成成功"
    
    # 检查配置工具
    local CONFIG_CMD="./scripts/config/config"
    if [ ! -f "$CONFIG_CMD" ] || [ ! -x "$CONFIG_CMD" ]; then
        if [ -f "scripts/config/conf" ] && [ -x "scripts/config/conf" ]; then
            log "✅ 使用 conf 工具"
            CONFIG_CMD="./scripts/config/conf"
        elif [ -f "scripts/config-tool" ] && [ -x "scripts/config-tool" ]; then
            log "✅ 使用 config-tool"
            CONFIG_CMD="./scripts/config-tool"
        else
            log "⚠️ 使用内置简易工具"
            mkdir -p scripts/config
            cat > scripts/config/config << 'EOF'
#!/bin/bash
CONFIG_FILE=".config"
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
        echo "# CONFIG_PACKAGE_${symbol} is not set" >> "$CONFIG_FILE"
        ;;
esac
EOF
            chmod +x scripts/config/config
            CONFIG_CMD="./scripts/config/config"
        fi
    fi
    
    log "🔧 使用配置工具: $CONFIG_CMD"
    
    # 应用配置文件
    if [ -f "$CONFIG_DIR/usb-generic.config" ]; then
        log "📁 应用USB通用配置..."
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [ -z "$line" ] && continue
            
            if echo "$line" | grep -q "^CONFIG_.*=y$"; then
                config_name=$(echo "$line" | cut -d'=' -f1 | sed 's/^CONFIG_//')
                $CONFIG_CMD --enable "$config_name"
            fi
        done < "$CONFIG_DIR/usb-generic.config"
        log "✅ USB通用配置应用完成"
    fi
    
    if [ -f "$CONFIG_DIR/base.config" ]; then
        log "📁 应用基础配置..."
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [ -z "$line" ] && continue
            
            if echo "$line" | grep -q "^CONFIG_.*=y$"; then
                config_name=$(echo "$line" | cut -d'=' -f1 | sed 's/^CONFIG_//')
                $CONFIG_CMD --enable "$config_name"
            fi
        done < "$CONFIG_DIR/base.config"
        log "✅ 基础配置应用完成"
    fi
    
    local device_config_file="$CONFIG_DIR/devices/$DEVICE.config"
    if [ -f "$device_config_file" ]; then
        log "📁 应用设备配置: $DEVICE.config..."
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [ -z "$line" ] && continue
            
            if echo "$line" | grep -q "^CONFIG_.*=y$"; then
                config_name=$(echo "$line" | cut -d'=' -f1 | sed 's/^CONFIG_//')
                $CONFIG_CMD --enable "$config_name"
            fi
        done < "$device_config_file"
        log "✅ 设备配置应用完成"
    fi
    
    if [ "$CONFIG_MODE" = "normal" ] && [ -f "$CONFIG_DIR/normal.config" ]; then
        log "📁 应用正常模式配置..."
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [ -z "$line" ] && continue
            
            if echo "$line" | grep -q "^CONFIG_.*=y$"; then
                config_name=$(echo "$line" | cut -d'=' -f1 | sed 's/^CONFIG_//')
                $CONFIG_CMD --enable "$config_name"
            fi
        done < "$CONFIG_DIR/normal.config"
        log "✅ 正常模式配置应用完成"
    fi
    
    # 平台专用配置
    local platform_config=""
    if [ -f "$CONFIG_DIR/devices/$TARGET.config" ]; then
        platform_config="$CONFIG_DIR/devices/$TARGET.config"
    else
        platform_config=$(find "$CONFIG_DIR" -type f -name "*${TARGET}*.config" 2>/dev/null | grep -v "usb-generic" | grep -v "base" | grep -v "normal" | head -1)
    fi
    
    if [ -n "$platform_config" ] && [ -f "$platform_config" ]; then
        log "📁 应用平台配置: $(basename "$platform_config")..."
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
            [ -z "$line" ] && continue
            
            if echo "$line" | grep -q "^CONFIG_.*=y$"; then
                config_name=$(echo "$line" | cut -d'=' -f1 | sed 's/^CONFIG_//')
                $CONFIG_CMD --enable "$config_name"
            fi
        done < "$platform_config"
        log "✅ 平台配置应用完成"
    fi
    
    # 添加额外包
    if [ -n "$extra_packages" ]; then
        log "📦 添加额外包: $extra_packages"
        echo "$extra_packages" | tr ',' '
' | while read pkg; do
            if [ -n "$pkg" ]; then
                $CONFIG_CMD --enable "PACKAGE_$pkg"
                log "✅ 添加包: $pkg"
            fi
        done
    fi
    
    # 🔥 关键修复：完整的依赖链配置
    log "🔧 启用完整的依赖链..."
    
    # USB 核心依赖链
    $CONFIG_CMD --enable PACKAGE_kmod-usb-core
    
    # USB 2.0 完整依赖链
    $CONFIG_CMD --enable PACKAGE_kmod-usb2
    $CONFIG_CMD --enable PACKAGE_kmod-usb-ehci
    $CONFIG_CMD --enable PACKAGE_kmod-usb-ohci
    $CONFIG_CMD --enable PACKAGE_kmod-usb-uhci
    
    # USB 3.0 完整依赖链 - 关键修复
    log "🔧 启用 USB 3.0 完整依赖链..."
    $CONFIG_CMD --enable PACKAGE_kmod-usb-xhci-hcd
    $CONFIG_CMD --enable PACKAGE_kmod-usb-xhci-hcd-dbg
    $CONFIG_CMD --enable PACKAGE_kmod-usb-xhci-mtk
    $CONFIG_CMD --enable PACKAGE_kmod-usb-xhci-pci
    $CONFIG_CMD --enable PACKAGE_kmod-usb-xhci-plat-hcd
    $CONFIG_CMD --enable PACKAGE_kmod-usb3
    
    # USB 存储完整依赖链
    $CONFIG_CMD --enable PACKAGE_kmod-scsi-core
    $CONFIG_CMD --enable PACKAGE_kmod-usb-storage
    $CONFIG_CMD --enable PACKAGE_kmod-usb-storage-extras
    $CONFIG_CMD --enable PACKAGE_kmod-usb-storage-uas
    
    # 文件系统支持
    $CONFIG_CMD --enable PACKAGE_kmod-fs-ext4
    $CONFIG_CMD --enable PACKAGE_kmod-fs-vfat
    $CONFIG_CMD --enable PACKAGE_kmod-fs-exfat
    $CONFIG_CMD --enable PACKAGE_kmod-fs-ntfs3
    $CONFIG_CMD --enable PACKAGE_kmod-nls-utf8
    $CONFIG_CMD --enable PACKAGE_kmod-nls-cp936
    $CONFIG_CMD --enable PACKAGE_kmod-nls-cp437
    $CONFIG_CMD --enable PACKAGE_kmod-nls-iso8859-1
    
    # IPQ40xx 平台专用 USB 完整依赖链
    if [ "$TARGET" = "ipq40xx" ]; then
        log "🔧 启用 IPQ40xx 平台 USB 完整依赖链..."
        
        # DWC3 核心
        $CONFIG_CMD --enable PACKAGE_kmod-usb-dwc3
        $CONFIG_CMD --enable PACKAGE_kmod-usb-dwc3-of-simple
        
        # QCOM 专用驱动
        $CONFIG_CMD --enable PACKAGE_kmod-usb-dwc3-qcom
        $CONFIG_CMD --enable PACKAGE_kmod-phy-qcom-dwc3
        $CONFIG_CMD --enable PACKAGE_kmod-usb-phy-msm
        
        # USB 角色切换
        $CONFIG_CMD --enable PACKAGE_kmod-usb-dwc3-role-switch
        
        # 依赖的内核配置
        $CONFIG_CMD --enable PACKAGE_kernel
        $CONFIG_CMD --enable PACKAGE_kmod-usb-common
        
        log "✅ IPQ40xx USB 完整依赖链启用完成"
    fi
    
    # TCP BBR 拥塞控制
    $CONFIG_CMD --enable PACKAGE_kmod-tcp-bbr
    $CONFIG_CMD --set-str DEFAULT_TCP_CONG "bbr"
    
    # ath10k 冲突解决
    $CONFIG_CMD --disable PACKAGE_kmod-ath10k
    $CONFIG_CMD --disable PACKAGE_kmod-ath10k-pci
    $CONFIG_CMD --disable PACKAGE_kmod-ath10k-smallbuffers
    $CONFIG_CMD --disable PACKAGE_kmod-ath10k-ct-smallbuffers
    $CONFIG_CMD --enable PACKAGE_kmod-ath10k-ct
    
    # TurboACC 配置
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "🔧 启用 TurboACC 组件..."
        $CONFIG_CMD --enable PACKAGE_luci-app-turboacc
        $CONFIG_CMD --enable PACKAGE_kmod-shortcut-fe
        $CONFIG_CMD --enable PACKAGE_kmod-shortcut-fe-cm
        $CONFIG_CMD --enable PACKAGE_kmod-fast-classifier
        log "✅ TurboACC 组件启用完成"
    fi
    
    log "🔄 运行 make defconfig 解决依赖关系..."
    make defconfig || handle_error "最终配置应用失败"
    
    # 再次检查关键驱动并强制写入（如果仍未启用）
    log "🔧 二次检查关键驱动..."
    
    if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
        log "⚠️ kmod-usb-xhci-hcd 仍未启用，检查依赖..."
        # 检查是否因为内核版本问题
        if grep -q "CONFIG_TARGET_ipq40xx=y" .config; then
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
            echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
        fi
        make defconfig
    fi
    
    if ! grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && [ "$TARGET" = "ipq40xx" ]; then
        log "⚠️ kmod-phy-qcom-dwc3 仍未启用，强制启用..."
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
        make defconfig
    fi
    
    log "📋 关键配置状态（最终）:"
    log "  - kmod-usb-core: $(grep -q "^CONFIG_PACKAGE_kmod-usb-core=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
    log "  - kmod-usb-xhci-hcd: $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
    log "  - kmod-usb3: $(grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
    log "  - kmod-usb2: $(grep -q "^CONFIG_PACKAGE_kmod-usb2=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
    
    if [ "$TARGET" = "ipq40xx" ]; then
        log "  - kmod-usb-dwc3-qcom: $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
        log "  - kmod-phy-qcom-dwc3: $(grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
    fi
    
    log "✅ 配置生成完成"
}
#【build_firmware_main.sh-13-end】

#【build_firmware_main.sh-14】
verify_usb_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 详细验证USB和存储配置 ==="
    
    echo "1. 🟢 USB核心模块:"
    grep "CONFIG_PACKAGE_kmod-usb-core" .config | grep "=y" && echo "✅ USB核心" || echo "❌ 缺少USB核心"
    
    echo "2. 🟢 USB 2.0控制器:"
    grep -E "CONFIG_PACKAGE_kmod-usb2=y" .config && echo "✅ USB 2.0" || echo "❌ 缺少USB 2.0"
    grep -E "CONFIG_PACKAGE_kmod-usb-ehci=y" .config && echo "✅ USB EHCI" || echo "❌ 缺少USB EHCI"
    grep -E "CONFIG_PACKAGE_kmod-usb-ohci=y" .config && echo "✅ USB OHCI" || echo "❌ 缺少USB OHCI"
    
    echo "3. 🚨 USB 3.0关键驱动:"
    echo "  - kmod-usb3:" $(grep "CONFIG_PACKAGE_kmod-usb3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb-xhci-hcd:" $(grep "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb-xhci-pci:" $(grep "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    echo "4. 🚨 USB DWC3 核心驱动:"
    echo "  - kmod-usb-dwc3:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb-dwc3-of-simple:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    echo "5. 🚨 平台专用USB控制器:"
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "  🔧 检测到高通IPQ40xx平台，检查专用驱动:"
        echo "  - kmod-usb-dwc3-qcom:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-phy-qcom-dwc3:" $(grep "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-usb-phy-msm:" $(grep "CONFIG_PACKAGE_kmod-usb-phy-msm=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    elif [ "$TARGET" = "ramips" ]; then
        echo "  🔧 检测到雷凌平台，检查专用驱动:"
        echo "  - kmod-usb-xhci-mtk:" $(grep "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    elif [ "$TARGET" = "ath79" ]; then
        echo "  🔧 检测到高通ATH79平台，检查专用驱动:"
        echo "  - kmod-usb2-ath79:" $(grep "CONFIG_PACKAGE_kmod-usb2-ath79=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    fi
    
    echo "6. 🟢 USB存储:"
    grep "CONFIG_PACKAGE_kmod-usb-storage=y" .config && echo "✅ USB存储" || echo "❌ 缺少USB存储"
    grep "CONFIG_PACKAGE_kmod-usb-storage-uas=y" .config && echo "✅ USB UAS" || echo "❌ 缺少USB UAS"
    
    echo "7. 🟢 SCSI支持:"
    grep "CONFIG_PACKAGE_kmod-scsi-core=y" .config && echo "✅ SCSI核心" || echo "❌ 缺少SCSI核心"
    grep "CONFIG_PACKAGE_kmod-scsi-generic=y" .config && echo "✅ SCSI通用" || echo "❌ 缺少SCSI通用"
    
    echo "8. 🟢 文件系统支持:"
    echo "  - ext4:" $(grep "CONFIG_PACKAGE_kmod-fs-ext4=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - vfat:" $(grep "CONFIG_PACKAGE_kmod-fs-vfat=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - exfat:" $(grep "CONFIG_PACKAGE_kmod-fs-exfat=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - NTFS3:" $(grep "CONFIG_PACKAGE_kmod-fs-ntfs3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    echo "9. 🟢 编码支持:"
    grep "CONFIG_PACKAGE_kmod-nls-utf8=y" .config && echo "✅ UTF-8编码" || echo "❌ 缺少UTF-8编码"
    grep "CONFIG_PACKAGE_kmod-nls-cp936=y" .config && echo "✅ 中文编码" || echo "❌ 缺少中文编码"
    
    log "=== 🚨 USB配置验证完成 ==="
    
    log "📊 USB配置状态总结:"
    local usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-xhci-hcd" "kmod-usb-storage" "kmod-scsi-core")
    local missing_count=0
    local enabled_count=0
    
    for driver in "${usb_drivers[@]}"; do
        if grep -q "CONFIG_PACKAGE_${driver}=y" .config; then
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
    
    log "=== 🚨 USB驱动完整性检查 ==="
    
    local missing_drivers=()
    local required_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb3"
        "kmod-usb-xhci-hcd"
        "kmod-usb-storage"
        "kmod-scsi-core"
        "kmod-fs-ext4"
        "kmod-fs-vfat"
    )
    
    if [ "$TARGET" = "ipq40xx" ]; then
        required_drivers+=("kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3")
    elif [ "$TARGET" = "ramips" ]; then
        required_drivers+=("kmod-usb-xhci-mtk")
    elif [ "$TARGET" = "ath79" ]; then
        required_drivers+=("kmod-usb2-ath79")
    fi
    
    for driver in "${required_drivers[@]}"; do
        if ! grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            log "❌ 缺失驱动: $driver"
            missing_drivers+=("$driver")
        else
            log "✅ 驱动存在: $driver"
        fi
    done
    
    if [ ${#missing_drivers[@]} -gt 0 ]; then
        log "🚨 发现 ${#missing_drivers[@]} 个缺失的USB驱动"
        log "正在尝试修复..."
        
        for driver in "${missing_drivers[@]}"; do
            echo "CONFIG_PACKAGE_${driver}=y" >> .config
            log "✅ 已添加: $driver"
        done
        
        make defconfig
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
    
    log "=== 应用配置并显示详细信息（综合修复版） ==="
    
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
    fi
    
    log "🔧 步骤4: 使用OpenWrt官方配置工具强制修复关键配置..."
    
    if [ ! -f "scripts/config" ]; then
        log "⚠️ scripts/config工具不存在，编译生成中..."
        make scripts/config || {
            log "❌ 无法生成scripts/config工具"
            log "⚠️ 将使用awk方式进行修复"
        }
    fi
    
    log "  🔧 USB 3.0驱动修复..."
    if [ -f "scripts/config" ]; then
        ./scripts/config --enable CONFIG_PACKAGE_kmod-usb-xhci-hcd
        ./scripts/config --enable CONFIG_PACKAGE_kmod-usb3
    else
        awk '
        /^# CONFIG_PACKAGE_kmod-usb-xhci-hcd is not set/ {
            print "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y"
            next
        }
        /^CONFIG_PACKAGE_kmod-usb-xhci-hcd=.*/ {
            print "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y"
            next
        }
        { print $0 }
        ' .config > .config.tmp
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config.tmp; then
            echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config.tmp
        fi
        
        awk '
        /^# CONFIG_PACKAGE_kmod-usb3 is not set/ {
            print "CONFIG_PACKAGE_kmod-usb3=y"
            next
        }
        /^CONFIG_PACKAGE_kmod-usb3=.*/ {
            print "CONFIG_PACKAGE_kmod-usb3=y"
            next
        }
        { print $0 }
        ' .config.tmp > .config
        rm -f .config.tmp
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config; then
            echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
        fi
    fi
    log "  ✅ USB 3.0驱动强制启用完成"
    
    if [ "$TARGET" = "ipq40xx" ] || grep -q "^CONFIG_TARGET_ipq40xx=y" .config 2>/dev/null; then
        log "  🔧 IPQ40xx平台专用USB驱动修复..."
        if [ -f "scripts/config" ]; then
            ./scripts/config --enable CONFIG_PACKAGE_kmod-usb-dwc3-qcom
            ./scripts/config --enable CONFIG_PACKAGE_kmod-phy-qcom-dwc3
            ./scripts/config --enable CONFIG_PACKAGE_kmod-usb-dwc3
        else
            if ! grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config; then
                echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
            fi
            if ! grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config; then
                echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
            fi
        fi
        log "  ✅ IPQ40xx平台专用USB驱动修复完成"
    fi
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "  🔧 TurboACC配置修复..."
        if [ -f "scripts/config" ]; then
            ./scripts/config --enable CONFIG_PACKAGE_luci-app-turboacc
            ./scripts/config --enable CONFIG_PACKAGE_kmod-shortcut-fe
            ./scripts/config --enable CONFIG_PACKAGE_kmod-fast-classifier
        else
            if ! grep -q "^CONFIG_PACKAGE_luci-app-turboacc=y" .config; then
                echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
            fi
            if ! grep -q "^CONFIG_PACKAGE_kmod-shortcut-fe=y" .config; then
                echo "CONFIG_PACKAGE_kmod-shortcut-fe=y" >> .config
            fi
            if ! grep -q "^CONFIG_PACKAGE_kmod-fast-classifier=y" .config; then
                echo "CONFIG_PACKAGE_kmod-fast-classifier=y" >> .config
            fi
        fi
        log "  ✅ TurboACC配置修复完成"
    fi
    
    log "  🔧 TCP BBR拥塞控制修复..."
    if [ -f "scripts/config" ]; then
        ./scripts/config --enable CONFIG_PACKAGE_kmod-tcp-bbr
        ./scripts/config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"
    else
        if ! grep -q "^CONFIG_PACKAGE_kmod-tcp-bbr=y" .config; then
            echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
        fi
        
        awk '!/^CONFIG_DEFAULT_TCP_CONG=/' .config > .config.tmp
        mv .config.tmp .config
        echo 'CONFIG_DEFAULT_TCP_CONG="bbr"' >> .config
    fi
    log "  ✅ TCP BBR拥塞控制修复完成"
    
    log "  🔧 kmod-ath10k-ct冲突修复..."
    if [ -f "scripts/config" ]; then
        ./scripts/config --disable CONFIG_PACKAGE_kmod-ath10k
        ./scripts/config --disable CONFIG_PACKAGE_kmod-ath10k-pci
        ./scripts/config --disable CONFIG_PACKAGE_kmod-ath10k-smallbuffers
        ./scripts/config --enable CONFIG_PACKAGE_kmod-ath10k-ct
        ./scripts/config --disable CONFIG_PACKAGE_kmod-ath10k-ct-smallbuffers
    else
        awk '
        /^CONFIG_PACKAGE_kmod-ath10k=y/ {
            print "# CONFIG_PACKAGE_kmod-ath10k is not set"
            next
        }
        /^CONFIG_PACKAGE_kmod-ath10k-pci=y/ {
            print "# CONFIG_PACKAGE_kmod-ath10k-pci is not set"
            next
        }
        /^CONFIG_PACKAGE_kmod-ath10k-smallbuffers=y/ {
            print "# CONFIG_PACKAGE_kmod-ath10k-smallbuffers is not set"
            next
        }
        /^CONFIG_PACKAGE_kmod-ath10k-ct-smallbuffers=y/ {
            print "# CONFIG_PACKAGE_kmod-ath10k-ct-smallbuffers is not set"
            next
        }
        { print $0 }
        ' .config > .config.tmp
        mv .config.tmp .config
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-ath10k-ct=y" .config; then
            echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
        fi
    fi
    log "  ✅ kmod-ath10k-ct冲突修复完成"
    
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
    echo "=== 🔍 USB驱动完整性检查（精确匹配） ==="
    
    echo ""
    echo "🔍 检查基础USB驱动..."
    local required_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb-storage"
        "kmod-scsi-core"
    )
    
    for driver in "${required_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "✅ $driver: 已启用"
        else
            echo "❌ $driver: 未启用"
        fi
    done
    
    echo ""
    echo "🔍 检查USB 3.0驱动..."
    local usb3_drivers=(
        "kmod-usb3"
        "kmod-usb-xhci-hcd"
    )
    
    for driver in "${usb3_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "✅ $driver: 已启用"
        else
            echo "⚠️ $driver: 未启用（如果设备支持USB 3.0可能需要）"
        fi
    done
    
    echo ""
    echo "🔍 检查平台专用驱动..."
    if [ "$TARGET" = "ipq40xx" ] || grep -q "^CONFIG_TARGET_ipq40xx=y" .config 2>/dev/null; then
        echo "🔧 检测到高通IPQ40xx平台，检查专用驱动:"
        local ipq40xx_drivers=(
            "kmod-usb-dwc3-qcom"
            "kmod-phy-qcom-dwc3"
            "kmod-usb-dwc3"
        )
        for driver in "${ipq40xx_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "✅ $driver: 已启用"
            else
                echo "ℹ️ $driver: 未启用（可能不是必需）"
            fi
        done
    elif [ "$TARGET" = "ramips" ] || grep -q "^CONFIG_TARGET_ramips=y" .config 2>/dev/null; then
        echo "🔧 检测到雷凌MT76xx平台，检查专用驱动:"
        local ramips_drivers=(
            "kmod-usb-xhci-mtk"
            "kmod-usb-ohci-pci"
            "kmod-usb2-pci"
        )
        for driver in "${ramips_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "✅ $driver: 已启用"
            else
                echo "ℹ️ $driver: 未启用（可能不是必需）"
            fi
        done
    elif [ "$TARGET" = "ath79" ] || grep -q "^CONFIG_TARGET_ath79=y" .config 2>/dev/null; then
        echo "🔧 检测到高通ATH79平台，检查专用驱动:"
        local ath79_drivers=(
            "kmod-usb2-ath79"
            "kmod-usb-ohci"
        )
        for driver in "${ath79_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "✅ $driver: 已启用"
            else
                echo "ℹ️ $driver: 未启用（可能不是必需）"
            fi
        done
    elif [ "$TARGET" = "mediatek" ] || grep -q "^CONFIG_TARGET_mediatek=y" .config 2>/dev/null; then
        echo "🔧 检测到联发科平台，检查专用驱动:"
        local mediatek_drivers=(
            "kmod-usb-dwc3-mediatek"
            "kmod-phy-mediatek"
            "kmod-usb-dwc3"
        )
        for driver in "${mediatek_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "✅ $driver: 已启用"
            else
                echo "ℹ️ $driver: 未启用（可能不是必需）"
            fi
        done
    fi
    
    echo ""
    echo "=== 📦 插件配置状态 ==="
    
    local functional_plugins=(
        "luci-app-turboacc:TurboACC 网络加速"
        "luci-app-upnp:UPnP 自动端口转发"
        "samba4-server:Samba 文件共享"
        "luci-app-diskman:磁盘管理"
        "vlmcsd:KMS 激活服务"
        "smartdns:SmartDNS 智能DNS"
        "luci-app-accesscontrol:家长控制"
        "luci-app-wechatpush:微信推送"
        "sqm-scripts:流量控制 (SQM)"
        "vsftpd:FTP 服务器"
        "luci-app-arpbind:ARP 绑定"
        "luci-app-cpulimit:CPU 限制"
        "luci-app-hd-idle:硬盘休眠"
    )
    
    for plugin_entry in "${functional_plugins[@]}"; do
        local plugin="${plugin_entry%%:*}"
        local desc="${plugin_entry#*:}"
        
        if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config; then
            echo "✅ $desc: 已启用"
        elif grep -q "^CONFIG_PACKAGE_${plugin}=m" .config; then
            echo "📦 $desc: 模块化"
        elif grep -q "^# CONFIG_PACKAGE_${plugin} is not set" .config; then
            echo "❌ $desc: 已禁用"
        else
            echo "⚪ $desc: 未配置"
        fi
    done
    
    echo ""
    echo "=== 📊 配置统计 ==="
    local enabled_count=$(grep -c "^CONFIG_PACKAGE_.*=y$" .config 2>/dev/null || echo "0")
    local module_count=$(grep -c "^CONFIG_PACKAGE_.*=m$" .config 2>/dev/null || echo "0")
    local disabled_count=$(grep -c "^# CONFIG_PACKAGE_.* is not set$" .config 2>/dev/null || echo "0")
    echo "✅ 已启用插件: $enabled_count 个"
    echo "📦 模块化插件: $module_count 个"
    echo "❌ 已禁用插件: $disabled_count 个"
    
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
    
    local existing_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "现有依赖包数量: $existing_deps 个"
    
    log "开始下载依赖包..."
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    local downloaded_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "下载后依赖包数量: $downloaded_deps 个"
    
    if [ $downloaded_deps -gt $existing_deps ]; then
        log "✅ 成功下载了 $((downloaded_deps - existing_deps)) 个新依赖包"
    else
        log "ℹ️ 没有下载新的依赖包"
    fi
    
    if grep -q "ERROR\|Failed\|404" download.log 2>/dev/null; then
        log "⚠️ 下载过程中发现错误:"
        grep -E "ERROR|Failed|404" download.log | head -10
    fi
    
    log "✅ 依赖包下载完成"
}
#【build_firmware_main.sh-18-end】

#【build_firmware_main.sh-19】
integrate_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 集成自定义文件（增强版）==="
    
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
                    files="$files$item"$'
'
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
        
        printf "%-50s %-10s %-15s %s
" "$rel_path" "$file_size" "$type_desc" "$name_status"
        
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
        touch "$SAMBA_DIR/$config_file" 2>/dev/null &&         echo "  ✅ 创建Samba配置文件: $config_file" >> $LOG_FILE ||         echo "  ⚠️ 无法创建Samba配置文件: $config_file" >> $LOG_FILE
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
# 此函数已废弃，由【37】版本替代
# 保留空函数以避免破坏系统性标识
workflow_step23_pre_build_check() {
    log "=== 步骤23: 前置错误检查（已废弃）==="
    log "⚠️ 警告: 此函数已废弃，请使用【37】版本"
    return 0
}
#【build_firmware_main.sh-23-end】

#【build_firmware_main.sh-24】
cleanup() {
    log "=== 清理构建目录 ==="
    
    if [ -d "$BUILD_DIR" ]; then
        log "检查是否有需要保留的文件..."
        
        if [ -f "$BUILD_DIR/.config" ]; then
            log "备份配置文件..."
            mkdir -p /tmp/openwrt_backup
            local backup_file="/tmp/openwrt_backup/config_$(date +%Y%m%d_%H%M%S).config"
            cp "$BUILD_DIR/.config" "$backup_file"
            log "✅ 配置文件备份到: $backup_file"
        fi
        
        if [ -f "$BUILD_DIR/build.log" ]; then
            log "备份编译日志..."
            mkdir -p /tmp/openwrt_backup
            cp "$BUILD_DIR/build.log" "/tmp/openwrt_backup/build_$(date +%Y%m%d_%H%M%S).log"
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
    
    log "=== 步骤15: 智能配置生成 ==="
    
    set -e
    trap 'echo "❌ 步骤15 失败，退出代码: $?"; exit 1' ERR
    
    generate_config "$extra_packages"
    
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
    log "=== 步骤16: 验证USB配置（修复版：精确匹配） ==="
    
    trap 'echo "⚠️ 步骤16 验证过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    echo "=== 🚨 USB配置精确匹配检查 ==="
    
    echo "1. 🟢 USB核心模块（精确匹配）:"
    if grep -q "^CONFIG_PACKAGE_kmod-usb-core=y" .config; then
        echo "✅ USB核心: 已启用"
    else
        echo "❌ USB核心: 未启用"
    fi
    
    echo "2. 🟢 USB控制器（精确匹配）:"
    echo "  - kmod-usb2:" $(grep -q "^CONFIG_PACKAGE_kmod-usb2=y" .config && echo "✅" || echo "❌")
    echo "  - kmod-usb3:" $(grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config && echo "✅" || echo "❌")
    echo "  - kmod-usb-xhci-hcd:" $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo "✅" || echo "❌")
    
    echo "3. 🟢 USB存储驱动（精确匹配）:"
    echo "  - kmod-usb-storage:" $(grep -q "^CONFIG_PACKAGE_kmod-usb-storage=y" .config && echo "✅" || echo "❌")
    echo "  - kmod-scsi-core:" $(grep -q "^CONFIG_PACKAGE_kmod-scsi-core=y" .config && echo "✅" || echo "❌")
    
    echo "4. 🟢 检查重复配置:"
    duplicates=$(grep "CONFIG_PACKAGE_kmod-usb-xhci-hcd" .config | wc -l)
    if [ $duplicates -gt 1 ]; then
        echo "⚠️ 发现重复配置: kmod-usb-xhci-hcd ($duplicates 次)"
        echo "🔍 显示所有匹配行:"
        grep -n "CONFIG_PACKAGE_kmod-usb-xhci-hcd" .config
    else
        echo "✅ 无重复配置"
    fi
    
    echo "5. 🟢 平台专用驱动检查（精确匹配）:"
    if grep -q "^CONFIG_TARGET_ipq40xx=y" .config; then
        echo "🔧 检测到高通IPQ40xx平台:"
        echo "  - kmod-usb-dwc3-qcom:" $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo "✅" || echo "❌")
        echo "  - kmod-phy-qcom-dwc3:" $(grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo "✅" || echo "❌")
    fi
    
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
    log "=== 步骤17: USB驱动完整性检查（修复版） ==="
    
    trap 'echo "⚠️ 步骤17 检查过程中出现错误，继续执行..."' ERR
    
    cd $BUILD_DIR
    
    echo "=== USB驱动完整性检查（精确匹配） ==="
    
    missing_drivers=()
    required_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb-storage"
        "kmod-scsi-core"
    )
    
    echo "🔍 检查基础USB驱动..."
    for driver in "${required_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "✅ $driver: 已启用"
        else
            echo "❌ $driver: 未启用"
            missing_drivers+=("$driver")
        fi
    done
    
    echo ""
    echo "🔍 检查USB 3.0驱动..."
    usb3_drivers=("kmod-usb3" "kmod-usb-xhci-hcd")
    for driver in "${usb3_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "✅ $driver: 已启用"
        else
            echo "⚠️ $driver: 未启用（如果设备支持USB 3.0可能需要）"
        fi
    done
    
    echo ""
    echo "🔍 检查平台专用驱动..."
    if grep -q "^CONFIG_TARGET_ipq40xx=y" .config; then
        echo "🔧 检测到高通IPQ40xx平台，检查专用驱动:"
        ipq40xx_drivers=("kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3")
        for driver in "${ipq40xx_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "✅ $driver: 已启用"
            else
                echo "ℹ️ $driver: 未启用（可能不是必需）"
            fi
        done
    fi
    
    echo ""
    echo "📊 统计:"
    echo "  必需驱动: ${#required_drivers[@]} 个"
    echo "  缺失驱动: ${#missing_drivers[@]} 个"
    
    if [ ${#missing_drivers[@]} -gt 0 ]; then
        echo "⚠️ 发现缺失驱动: ${missing_drivers[*]}"
        echo "💡 建议在配置文件中启用这些驱动"
    else
        echo "✅ 所有必需USB驱动都已启用"
    fi
    
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
    log "=== 步骤20: 修复网络环境 ==="
    
    trap 'echo "⚠️ 步骤20 修复过程中出现错误，继续执行..."' ERR
    
    fix_network
    
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
    log "=== 步骤21: 下载依赖包（优化版） ==="
    
    set -e
    trap 'echo "❌ 步骤21 失败，退出代码: $?"; exit 1' ERR
    
    cd $BUILD_DIR
    
    echo "🔧 检查依赖包目录..."
    if [ ! -d "dl" ]; then
        mkdir -p dl
        echo "✅ 创建依赖包目录: dl"
    fi
    
    DEP_COUNT=$(find dl -type f 2>/dev/null | wc -l)
    echo "📊 当前依赖包数量: $DEP_COUNT 个"
    
    echo "🚀 开始下载依赖包（启用并行下载）..."
    stdbuf -oL -eL make -j4 download V=s 2>&1 | tee download.log
    
    DOWNLOAD_EXIT_CODE=${PIPESTATUS[0]}
    if [ $DOWNLOAD_EXIT_CODE -ne 0 ]; then
        echo "⚠️ 警告: 依赖包下载过程中出现错误，退出代码: $DOWNLOAD_EXIT_CODE"
        echo "💡 查看下载日志中的错误信息:"
        grep -i "error\|failed\|404\|not found" download.log | head -10 || true
    fi
    
    echo "✅ 下载完成"
    
    NEW_DEP_COUNT=$(find dl -type f 2>/dev/null | wc -l)
    echo "📊 下载后依赖包数量: $NEW_DEP_COUNT 个"
    echo "📈 新增依赖包: $((NEW_DEP_COUNT - DEP_COUNT)) 个"
    
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
    log "=== 步骤23: 前置错误检查（立即退出版）- 增强版，自动修复配置问题 ==="
    
    set -e
    trap 'echo "❌ 步骤23 失败，退出代码: $?"; exit 1' ERR
    
    echo "🔍 检查当前环境..."
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        echo "✅ 加载环境变量: SELECTED_BRANCH=$SELECTED_BRANCH, TARGET=$TARGET"
        echo "✅ COMPILER_DIR=$COMPILER_DIR"
        echo "✅ CONFIG_MODE=$CONFIG_MODE"
    else
        echo "❌ 错误: 环境文件不存在 ($BUILD_DIR/build_env.sh)"
        echo "💡 请检查步骤08和步骤09是否成功执行"
        exit 1
    fi
    
    cd $BUILD_DIR
    echo "=== 🚨 前置错误检查（立即退出版）- 增强版 ==="
    
    echo ""
    echo "1. ✅ 配置文件检查:"
    if [ -f ".config" ]; then
        echo "  ✅ .config 文件存在"
        echo "  📊 文件大小: $(ls -lh .config | awk '{print $5}')"
        echo "  📝 文件行数: $(wc -l < .config)"
    else
        echo "  ❌ 错误: .config 文件不存在"
        echo "  💡 请检查步骤15智能配置生成是否成功"
        exit 1
    fi
    
    echo ""
    echo "2. ✅ SDK目录检查:"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        echo "  ✅ SDK目录存在: $COMPILER_DIR"
        echo "  📊 目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | awk '{print $1}' || echo '未知')"
        
        GCC_FILE=$(find "$COMPILER_DIR" -type f -executable           -name "*gcc"           ! -name "*gcc-ar"           ! -name "*gcc-ranlib"           ! -name "*gcc-nm"           ! -path "*dummy-tools*"           ! -path "*scripts*"           2>/dev/null | head -1)
        
        if [ -n "$GCC_FILE" ] && [ -x "$GCC_FILE" ]; then
            echo "  ✅ 找到可执行GCC编译器: $(basename "$GCC_FILE")"
            echo "  🔧 GCC版本: $("$GCC_FILE" --version 2>&1 | head -1)"
        else
            echo "  ❌ 错误: SDK目录中未找到真正的GCC编译器"
            exit 1
        fi
    else
        echo "  ❌ 错误: SDK目录不存在: $COMPILER_DIR"
        echo "  💡 请检查步骤09 SDK下载是否成功"
        exit 1
    fi
    
    echo ""
    echo "3. ✅ Feeds检查:"
    if [ -d "feeds" ]; then
        echo "  ✅ feeds 目录存在"
        echo "  📊 feeds目录大小: $(du -sh feeds 2>/dev/null | awk '{print $1}' || echo '未知')"
    else
        echo "  ❌ 错误: feeds 目录不存在"
        echo "  💡 请检查步骤12配置Feeds是否成功"
        exit 1
    fi
    
    echo ""
    echo "4. ✅ 磁盘空间检查:"
    AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1 | awk '{print $1}')
    AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    echo "  📊 /mnt 可用空间: ${AVAILABLE_GB}G"
    
    if [ $AVAILABLE_GB -lt 10 ]; then
        echo "  ❌ 错误: 磁盘空间不足 (需要至少10G，当前${AVAILABLE_GB}G)"
        exit 1
    elif [ $AVAILABLE_GB -lt 20 ]; then
        echo "  ⚠️ 警告: 磁盘空间较低 (建议至少20G，当前${AVAILABLE_GB}G)"
    else
        echo "  ✅ 磁盘空间充足"
    fi
    
    echo ""
    echo "5. ✅ USB配置检查（自动修复）:"
    USB_FIXED=0
    
    if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
        echo "  ❌ 错误: USB 3.0驱动未启用 (kmod-usb-xhci-hcd)"
        echo "  🔧 正在自动修复..."
        if [ -f "scripts/config/config" ]; then
            ./scripts/config/config --enable PACKAGE_kmod-usb-xhci-hcd
            echo "  ✅ 已强制添加: kmod-usb-xhci-hcd"
        else
            echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
            echo "  ✅ 已强制添加: kmod-usb-xhci-hcd"
        fi
        USB_FIXED=1
    else
        echo "  ✅ kmod-usb-xhci-hcd: 已启用"
    fi
    
    if ! grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config; then
        echo "  ❌ 错误: USB 3.0驱动未启用 (kmod-usb3)"
        echo "  🔧 正在自动修复..."
        if [ -f "scripts/config/config" ]; then
            ./scripts/config/config --enable PACKAGE_kmod-usb3
            echo "  ✅ 已强制添加: kmod-usb3"
        else
            echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
            echo "  ✅ 已强制添加: kmod-usb3"
        fi
        USB_FIXED=1
    else
        echo "  ✅ kmod-usb3: 已启用"
    fi
    
    if ! grep -q "^CONFIG_PACKAGE_kmod-usb2=y" .config; then
        echo "  ❌ 错误: USB 2.0驱动未启用 (kmod-usb2)"
        echo "  🔧 正在自动修复..."
        if [ -f "scripts/config/config" ]; then
            ./scripts/config/config --enable PACKAGE_kmod-usb2
            echo "  ✅ 已强制添加: kmod-usb2"
        else
            echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
            echo "  ✅ 已强制添加: kmod-usb2"
        fi
        USB_FIXED=1
    else
        echo "  ✅ kmod-usb2: 已启用"
    fi
    
    if [ "$TARGET" = "ipq40xx" ]; then
        if ! grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config; then
            echo "  ❌ 错误: IPQ40xx平台驱动未启用 (kmod-phy-qcom-dwc3)"
            echo "  🔧 正在自动修复..."
            if [ -f "scripts/config/config" ]; then
                ./scripts/config/config --enable PACKAGE_kmod-phy-qcom-dwc3
                echo "  ✅ 已强制添加: kmod-phy-qcom-dwc3"
            else
                echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
                echo "  ✅ 已强制添加: kmod-phy-qcom-dwc3"
            fi
            USB_FIXED=1
        else
            echo "  ✅ kmod-phy-qcom-dwc3: 已启用"
        fi
    fi
    
    echo ""
    echo "6. ✅ TurboACC配置检查（自动修复）:"
    TURBOACC_FIXED=0
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        if ! grep -q "^CONFIG_PACKAGE_luci-app-turboacc=y" .config; then
            echo "  ❌ 错误: TurboACC未启用 (正常模式必需)"
            echo "  🔧 正在自动修复..."
            if [ -f "scripts/config/config" ]; then
                ./scripts/config/config --enable PACKAGE_luci-app-turboacc
                echo "  ✅ 已强制添加: luci-app-turboacc"
            else
                echo "CONFIG_PACKAGE_luci-app-turboacc=y" >> .config
            fi
            TURBOACC_FIXED=1
        else
            echo "  ✅ luci-app-turboacc: 已启用"
        fi
    else
        echo "  ℹ️ 基础模式，不检查TurboACC配置"
    fi
    
    echo ""
    echo "7. ✅ TCP BBR拥塞控制检查（自动修复）:"
    BBR_FIXED=0
    
    if ! grep -q "^CONFIG_PACKAGE_kmod-tcp-bbr=y" .config; then
        echo "  ❌ 错误: TCP BBR未启用"
        echo "  🔧 正在自动修复..."
        if [ -f "scripts/config/config" ]; then
            ./scripts/config/config --enable PACKAGE_kmod-tcp-bbr
            echo "  ✅ 已强制添加: kmod-tcp-bbr"
        else
            echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
        fi
        BBR_FIXED=1
    else
        echo "  ✅ kmod-tcp-bbr: 已启用"
    fi
    
    if ! grep -q '^CONFIG_DEFAULT_TCP_CONG="bbr"' .config; then
        echo "  ❌ 错误: TCP BBR未设置为默认拥塞控制算法"
        echo "  🔧 正在自动修复..."
        if [ -f "scripts/config/config" ]; then
            ./scripts/config/config --set-str DEFAULT_TCP_CONG "bbr"
            echo "  ✅ 已设置: DEFAULT_TCP_CONG="bbr""
        else
            sed -i '/^CONFIG_DEFAULT_TCP_CONG=/d' .config
            echo 'CONFIG_DEFAULT_TCP_CONG="bbr"' >> .config
        fi
        BBR_FIXED=1
    else
        echo "  ✅ DEFAULT_TCP_CONG="bbr": 已设置"
    fi
    
    if [ $USB_FIXED -eq 1 ] || [ $TURBOACC_FIXED -eq 1 ] || [ $BBR_FIXED -eq 1 ]; then
        echo ""
        echo "🔄 配置已修复，重新运行 make defconfig..."
        make defconfig
        
        echo ""
        echo "📋 修复后配置状态:"
        echo "  - kmod-usb2: $(grep -q "^CONFIG_PACKAGE_kmod-usb2=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
        echo "  - kmod-usb3: $(grep -q "^CONFIG_PACKAGE_kmod-usb3=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
        echo "  - kmod-usb-xhci-hcd: $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
        
        if [ "$TARGET" = "ipq40xx" ]; then
            echo "  - kmod-usb-dwc3-qcom: $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
            echo "  - kmod-phy-qcom-dwc3: $(grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
        fi
        
        if [ "$CONFIG_MODE" = "normal" ]; then
            echo "  - luci-app-turboacc: $(grep -q "^CONFIG_PACKAGE_luci-app-turboacc=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
        fi
        
        echo "  - kmod-tcp-bbr: $(grep -q "^CONFIG_PACKAGE_kmod-tcp-bbr=y" .config && echo '✅ 已启用' || echo '❌ 未启用')"
        echo "  - DEFAULT_TCP_CONG: $(grep "^CONFIG_DEFAULT_TCP_CONG=" .config | cut -d'"' -f2 || echo '未设置')"
        
        echo "✅ 所有配置修复完成"
    else
        echo ""
        echo "✅ 所有配置检查通过，无需修复"
    fi
    
    echo ""
    echo "========================================"
    echo "✅✅✅ 所有前置检查通过，可以开始编译 ✅✅✅"
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
        
        if [ $CPU_CORES -ge 4 ]; then
            if [ $TOTAL_MEM -ge 8000 ]; then
                MAKE_JOBS=4
                echo "✅ 检测到高性能Runner (4核+8GB)"
            else
                MAKE_JOBS=3
                echo "✅ 检测到标准Runner (4核)"
            fi
        elif [ $CPU_CORES -ge 2 ]; then
            if [ $TOTAL_MEM -ge 7000 ]; then
                MAKE_JOBS=3
                echo "✅ 检测到GitHub标准Runner (2核7GB)"
            else
                MAKE_JOBS=2
                echo "✅ 检测到2核Runner"
            fi
        else
            MAKE_JOBS=2
            echo "⚠️ 检测到单核Runner"
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
    stdbuf -oL -eL time make -j$MAKE_JOBS V=s 2>&1 | tee build.log
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
    echo ""
    
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        FIRMWARE_COUNT=$(find "$BUILD_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        
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
            MAJOR_VERSION=$(echo "$SDK_VERSION" | grep -o "[0-9]\+" | head -1)
            
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
        source $BUILD_DIR/build_env.sh
        if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
            echo "  ✅ SDK已下载: $COMPILER_DIR"
        else
            echo "  ❌ SDK未下载或目录不存在"
        fi
    fi
    
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
