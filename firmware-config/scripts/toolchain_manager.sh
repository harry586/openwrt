#!/bin/bash
set -e

# 智能分层工具链管理器 v2.0
BUILD_TOOLS_BASE="./firmware-config/build-tools"
BUILD_TOOLS_COMMON="$BUILD_TOOLS_BASE/common"
BUILD_TOOLS_PLATFORMS="$BUILD_TOOLS_BASE/platforms"
BUILD_TOOLS_VERSIONS="$BUILD_TOOLS_BASE/versions"
BUILD_TOOLS_CACHE="$BUILD_TOOLS_BASE/cache"
BUILD_TOOLS_ARCHIVES="$BUILD_TOOLS_BASE/archives"
BUILD_TOOLS_LOGS="$BUILD_TOOLS_BASE/logs"

BUILD_DIR="/mnt/openwrt-build"
TOOLCHAIN_DB="$BUILD_TOOLS_BASE/toolchain_db.json"

# 架构映射表
ARCH_MAP='{
  "ipq40xx": {"arch": "arm", "cpu": "cortex-a7"},
  "ramips/mt76x8": {"arch": "mipsel", "cpu": "24kc"},
  "ramips/mt7621": {"arch": "mipsel", "cpu": "1004kc"},
  "ath79/generic": {"arch": "mips", "cpu": "24kc"},
  "x86/64": {"arch": "x86_64", "cpu": "x86_64"},
  "x86/generic": {"arch": "x86", "cpu": "x86"}
}'

# 日志函数
log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

# 错误处理函数
handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 初始化分层目录
init_layered_dirs() {
    log "=== 初始化分层工具链目录 ==="
    
    # 基础目录
    mkdir -p $BUILD_TOOLS_BASE
    
    # 通用工具目录
    mkdir -p $BUILD_TOOLS_COMMON/{host-tools/bin,host-tools/lib,host-tools/include,host-tools/share}
    mkdir -p $BUILD_TOOLS_COMMON/cross-tools/{binutils,gcc,libc}
    
    # 平台目录
    mkdir -p $BUILD_TOOLS_PLATFORMS/{arm,mipsel,mips,x86,x86_64}
    
    # 版本目录
    mkdir -p $BUILD_TOOLS_VERSIONS/{openwrt-21.02,openwrt-23.05}
    for version in openwrt-21.02 openwrt-23.05; do
        mkdir -p $BUILD_TOOLS_VERSIONS/$version/{configs,patches,packages,feeds}
    done
    
    # 缓存目录
    mkdir -p $BUILD_TOOLS_CACHE/{ccache,dl,build}
    
    # 日志目录
    mkdir -p $BUILD_TOOLS_LOGS
    
    # 存档目录
    mkdir -p $BUILD_TOOLS_ARCHIVES
    
    # 初始化数据库
    if [ ! -f "$TOOLCHAIN_DB" ]; then
        cat > $TOOLCHAIN_DB << 'EOF'
{
  "version": "2.0.0",
  "common_tools": {},
  "platforms": {},
  "openwrt_versions": {},
  "compiler_versions": {},
  "last_sync": ""
}
EOF
    fi
    
    # 设置环境变量文件
    cat > $BUILD_TOOLS_BASE/env.sh << 'EOF'
#!/bin/bash
# 工具链基础环境变量
export BUILD_TOOLS_BASE="$(dirname $(dirname $(readlink -f "$0")))"
export BUILD_TOOLS_COMMON="$BUILD_TOOLS_BASE/common"
export BUILD_TOOLS_PLATFORMS="$BUILD_TOOLS_BASE/platforms"
export BUILD_TOOLS_VERSIONS="$BUILD_TOOLS_BASE/versions"

# 添加通用工具到PATH
export PATH="$BUILD_TOOLS_COMMON/host-tools/bin:$PATH"
export LD_LIBRARY_PATH="$BUILD_TOOLS_COMMON/host-tools/lib:$LD_LIBRARY_PATH"

# 编译缓存设置
export CCACHE_DIR="$BUILD_TOOLS_BASE/cache/ccache"
export CCACHE_MAXSIZE="10G"
export CCACHE_COMPRESS="1"
EOF
    
    chmod +x $BUILD_TOOLS_BASE/env.sh
    
    # 更新数据库时间
    jq --arg date "$(date -I)" '.last_sync = $date' $TOOLCHAIN_DB > $TOOLCHAIN_DB.tmp
    mv $TOOLCHAIN_DB.tmp $TOOLCHAIN_DB
    
    log "✅ 分层目录初始化完成"
}

# 获取平台架构信息
get_platform_info() {
    local target=$1
    local subtarget=$2
    
    log "🔍 获取平台信息: $target/$subtarget"
    
    # 使用映射表获取架构信息
    local key="$target/$subtarget"
    local arch_info=$(echo "$ARCH_MAP" | jq -r ".\"$key\" // .\"$target\"")
    
    if [ "$arch_info" = "null" ]; then
        # 默认值
        case "$target" in
            "ipq40xx"|"ipq806x"|"bcm53xx")
                echo "arm cortex-a7"
                ;;
            "ramips")
                case "$subtarget" in
                    "mt7621") echo "mipsel 1004kc" ;;
                    "mt76x8") echo "mipsel 24kc" ;;
                    *) echo "mipsel 24kc" ;;
                esac
                ;;
            "ath79")
                echo "mips 24kc"
                ;;
            "x86")
                if [[ "$subtarget" == *"64"* ]]; then
                    echo "x86_64 x86_64"
                else
                    echo "x86 x86"
                fi
                ;;
            *)
                echo "unknown unknown"
                ;;
        esac
    else
        local arch=$(echo $arch_info | jq -r '.arch')
        local cpu=$(echo $arch_info | jq -r '.cpu')
        echo "$arch $cpu"
    fi
}

# 检查通用工具
check_common_tool() {
    local tool_name=$1
    local required_version=$2
    
    # 检查工具是否在PATH中
    if command -v $tool_name >/dev/null 2>&1; then
        local current_version=$($tool_name --version 2>/dev/null | head -1 || echo "")
        if [ -n "$required_version" ]; then
            if [[ "$current_version" == *"$required_version"* ]]; then
                log "✅ 通用工具满足版本: $tool_name ($current_version)"
                return 0
            fi
        else
            log "✅ 通用工具存在: $tool_name"
            return 0
        fi
    fi
    
    # 检查是否在通用工具目录中
    local tool_path="$BUILD_TOOLS_COMMON/host-tools/bin/$tool_name"
    if [ -f "$tool_path" ]; then
        log "✅ 通用工具已缓存: $tool_name"
        return 0
    fi
    
    log "❌ 通用工具缺失: $tool_name"
    return 1
}

# 安装通用主机工具
install_common_host_tools() {
    log "=== 安装通用主机工具 ==="
    
    # 需要安装的通用工具列表（不依赖目标平台）
    local common_tools=(
        # 基础编译工具
        "cmake"
        "autoconf"
        "automake"
        "libtool"
        "pkg-config"
        "make"
        "gcc"
        "g++"
        "ccache"
        
        # 系统工具
        "file"
        "patch"
        "sed"
        "awk"
        "grep"
        "find"
        "xargs"
        "tar"
        "gzip"
        "bzip2"
        "xz"
        "zstd"
        
        # 开发工具
        "flex"
        "bison"
        "gettext"
        "help2man"
        "texinfo"
        
        # Python工具
        "python3"
        "pip3"
        
        # 版本控制
        "git"
        "svn"
        
        # 网络工具
        "wget"
        "curl"
        "rsync"
        "aria2c"
    )
    
    local missing_tools=()
    for tool in "${common_tools[@]}"; do
        if ! check_common_tool "$tool"; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log "✅ 所有通用工具已就绪"
        return 0
    fi
    
    log "🔄 需要安装通用工具: ${missing_tools[*]}"
    
    # 使用系统包管理器安装
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing_tools[@]}" \
            || handle_error "安装通用工具失败"
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y "${missing_tools[@]}" \
            || handle_error "安装通用工具失败"
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y "${missing_tools[@]}" \
            || handle_error "安装通用工具失败"
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm "${missing_tools[@]}" \
            || handle_error "安装通用工具失败"
    else
        log "❌ 不支持的包管理器"
        return 1
    fi
    
    # 将工具复制到通用目录（可选，用于离线环境）
    for tool in "${missing_tools[@]}"; do
        local tool_path=$(command -v $tool)
        if [ -n "$tool_path" ]; then
            cp "$tool_path" "$BUILD_TOOLS_COMMON/host-tools/bin/" 2>/dev/null || true
            log "📦 缓存工具: $tool"
        fi
    done
    
    # 记录到数据库
    for tool in "${common_tools[@]}"; do
        local version=$($tool --version 2>/dev/null | head -1 || echo "unknown")
        jq --arg tool "$tool" \
           --arg version "$version" \
           '.common_tools[$tool] = $version' \
           $TOOLCHAIN_DB > $TOOLCHAIN_DB.tmp && mv $TOOLCHAIN_DB.tmp $TOOLCHAIN_DB
    done
    
    log "✅ 通用主机工具安装完成"
}

# 检查跨平台编译器
check_cross_compiler() {
    local arch=$1
    local cpu=$2
    local openwrt_version=$3
    
    log "🔍 检查跨平台编译器: $arch-$cpu ($openwrt_version)"
    
    # 检查通用编译器组件
    local compiler_prefix="${arch}-openwrt-linux"
    local gcc_path="$BUILD_TOOLS_COMMON/cross-tools/gcc/${arch}/bin/${compiler_prefix}-gcc"
    
    if [ -f "$gcc_path" ]; then
        local version=$($gcc_path --version 2>/dev/null | head -1)
        log "✅ 通用编译器存在: $arch ($version)"
        return 0
    fi
    
    # 检查平台专用编译器
    local platform_compiler="$BUILD_TOOLS_PLATFORMS/${arch}/${cpu}/bin/${compiler_prefix}-gcc"
    if [ -f "$platform_compiler" ]; then
        log "✅ 平台专用编译器存在: $arch-$cpu"
        return 0
    fi
    
    log "❌ 编译器缺失: $arch-$cpu"
    return 1
}

# 提取通用编译器组件
extract_common_compiler_parts() {
    local toolchain_dir=$1
    local arch=$2
    
    log "🔧 提取通用编译器组件: $arch"
    
    # 通用binutils
    if [ -d "$toolchain_dir/bin" ]; then
        local common_binutils=(
            "ar" "as" "ld" "nm" "objcopy"
            "objdump" "ranlib" "readelf" "strip"
            "strings" "size" "addr2line"
        )
        
        mkdir -p "$BUILD_TOOLS_COMMON/cross-tools/binutils/${arch}/bin"
        
        for util in "${common_binutils[@]}"; do
            local util_file=$(find "$toolchain_dir/bin" -name "*$util" -type f | head -1)
            if [ -f "$util_file" ]; then
                local util_name=$(basename "$util_file")
                cp "$util_file" "$BUILD_TOOLS_COMMON/cross-tools/binutils/${arch}/bin/$util_name"
                log "📦 提取binutil: $util_name"
            fi
        done
    fi
    
    # 通用头文件
    if [ -d "$toolchain_dir/include" ]; then
        mkdir -p "$BUILD_TOOLS_COMMON/cross-tools/libc/${arch}/include"
        cp -r "$toolchain_dir/include/"* "$BUILD_TOOLS_COMMON/cross-tools/libc/${arch}/include/" 2>/dev/null || true
        log "📦 提取头文件"
    fi
    
    # 通用库文件
    if [ -d "$toolchain_dir/lib" ]; then
        mkdir -p "$BUILD_TOOLS_COMMON/cross-tools/libc/${arch}/lib"
        # 只复制基本的C库
        find "$toolchain_dir/lib" -name "libc.*" -o -name "libm.*" -o -name "libgcc.*" | \
            while read lib; do 
                cp "$lib" "$BUILD_TOOLS_COMMON/cross-tools/libc/${arch}/lib/" 2>/dev/null || true
            done
        log "📦 提取基础库文件"
    fi
}

# 编译和保存工具链
build_and_save_toolchain() {
    local openwrt_version=$1
    local target=$2
    local subtarget=$3
    
    log "=== 构建分层工具链: $openwrt_version-$target-$subtarget ==="
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    # 获取平台信息
    read arch cpu < <(get_platform_info "$target" "$subtarget")
    log "📊 平台架构: $arch, CPU: $cpu"
    
    # 1. 编译完整的工具链
    log "🛠️ 编译完整工具链..."
    
    # 创建工具链专用配置
    rm -f .config
    cat > .config << EOF
CONFIG_TARGET_${target}=y
CONFIG_TARGET_${target}_${subtarget}=y
CONFIG_TARGET_ROOTFS_INITRAMFS=y
CONFIG_TOOLCHAIN=y
CONFIG_TOOLCHAIN_BUILD=y
CONFIG_SDK=y
CONFIG_IB=y
# 最小化配置，加快编译
CONFIG_KERNEL_KALLSYMS=n
CONFIG_KERNEL_DEBUG_INFO=n
CONFIG_KERNEL_DEBUG_KERNEL=n
EOF
    
    make defconfig
    local log_file="$BUILD_TOOLS_LOGS/toolchain-build-${openwrt_version}-${target}-${subtarget}.log"
    
    log "📝 编译日志: $log_file"
    make toolchain/install -j$(nproc) V=s 2>&1 | tee $log_file
    
    # 检查编译结果
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log "❌ 工具链编译失败"
        return 1
    fi
    
    # 2. 提取通用部分
    log "🔧 提取工具链通用部分..."
    
    local staging_dir="$BUILD_DIR/staging_dir"
    local toolchain_path=$(find "$staging_dir" -name "toolchain-*" -type d | head -1)
    
    if [ -d "$toolchain_path" ]; then
        # 提取通用编译器组件
        extract_common_compiler_parts "$toolchain_path" "$arch"
        
        # 保存平台专用部分
        save_platform_toolchain "$openwrt_version" "$arch" "$cpu" "$toolchain_path"
        
        # 保存版本专用配置
        save_version_specific_files "$openwrt_version" "$target" "$subtarget"
    else
        log "❌ 未找到工具链目录"
        return 1
    fi
    
    # 3. 更新数据库
    update_toolchain_db "$openwrt_version" "$target" "$subtarget" "$arch" "$cpu"
    
    log "✅ 分层工具链构建完成"
    return 0
}

# 保存平台专用工具链
save_platform_toolchain() {
    local openwrt_version=$1
    local arch=$2
    local cpu=$3
    local toolchain_path=$4
    
    local platform_dir="$BUILD_TOOLS_PLATFORMS/${arch}/${cpu}"
    mkdir -p "$platform_dir"
    
    log "💾 保存平台专用工具链: $arch-$cpu"
    
    # 清理旧工具链
    rm -rf "$platform_dir/toolchain"
    
    # 复制整个工具链（排除通用部分）
    cp -r "$toolchain_path" "$platform_dir/toolchain"
    
    # 创建平台环境脚本
    cat > "$platform_dir/env.sh" << EOF
#!/bin/bash
# 平台专用环境变量: $arch-$cpu
export ARCH="$arch"
export CPU="$cpu"
export CROSS_COMPILE="${arch}-openwrt-linux-"
export STAGING_DIR="\$STAGING_DIR"
export PATH="$platform_dir/toolchain/bin:\$PATH"
export LD_LIBRARY_PATH="$platform_dir/toolchain/lib:\$LD_LIBRARY_PATH"
# 编译器变量
export CC="${arch}-openwrt-linux-gcc"
export CXX="${arch}-openwrt-linux-g++"
export AR="${arch}-openwrt-linux-ar"
export AS="${arch}-openwrt-linux-as"
export LD="${arch}-openwrt-linux-ld"
export NM="${arch}-openwrt-linux-nm"
export OBJCOPY="${arch}-openwrt-linux-objcopy"
export OBJDUMP="${arch}-openwrt-linux-objdump"
export RANLIB="${arch}-openwrt-linux-ranlib"
export READELF="${arch}-openwrt-linux-readelf"
export STRIP="${arch}-openwrt-linux-strip"
EOF
    
    chmod +x "$platform_dir/env.sh"
    
    # 保存版本信息
    echo "$openwrt_version" > "$platform_dir/version.info"
    
    log "📦 平台工具链已保存: $(du -sh $platform_dir | cut -f1)"
}

# 保存版本专用文件
save_version_specific_files() {
    local openwrt_version=$1
    local target=$2
    local subtarget=$3
    
    local version_dir="$BUILD_TOOLS_VERSIONS/$openwrt_version"
    
    log "💾 保存版本专用文件: $openwrt_version"
    
    # 保存配置
    if [ -f "$BUILD_DIR/.config" ]; then
        cp "$BUILD_DIR/.config" "$version_dir/configs/${target}-${subtarget}.config"
    fi
    
    # 保存feeds配置
    if [ -f "$BUILD_DIR/feeds.conf.default" ]; then
        cp "$BUILD_DIR/feeds.conf.default" "$version_dir/feeds/"
    fi
    
    # 保存patch（如果有）
    if [ -d "$BUILD_DIR/patches" ]; then
        mkdir -p "$version_dir/patches/${target}-${subtarget}"
        cp -r "$BUILD_DIR/patches/"* "$version_dir/patches/${target}-${subtarget}/" 2>/dev/null || true
    fi
    
    # 保存目标配置
    if [ -d "$BUILD_DIR/target/linux/$target" ]; then
        mkdir -p "$version_dir/targets/${target}-${subtarget}"
        cp -r "$BUILD_DIR/target/linux/$target" "$version_dir/targets/${target}-${subtarget}/" 2>/dev/null || true
    fi
}

# 更新工具链数据库
update_toolchain_db() {
    local openwrt_version=$1
    local target=$2
    local subtarget=$3
    local arch=$4
    local cpu=$5
    
    local key="${openwrt_version}-${target}-${subtarget}"
    
    jq --arg key "$key" \
       --arg arch "$arch" \
       --arg cpu "$cpu" \
       --arg date "$(date -I)" \
       '.openwrt_versions[$key] = {
            "arch": $arch,
            "cpu": $cpu,
            "created": $date,
            "target": "'$target'",
            "subtarget": "'$subtarget'"
        }
        | .last_sync = $date' \
       $TOOLCHAIN_DB > $TOOLCHAIN_DB.tmp && mv $TOOLCHAIN_DB.tmp $TOOLCHAIN_DB
    
    log "📊 数据库已更新: $key"
}

# 恢复工具链
restore_toolchain() {
    local openwrt_version=$1
    local target=$2
    local subtarget=$3
    
    log "=== 恢复分层工具链: $openwrt_version-$target-$subtarget ==="
    
    # 获取平台信息
    read arch cpu < <(get_platform_info "$target" "$subtarget")
    
    # 1. 设置通用工具
    if [ -f "$BUILD_TOOLS_BASE/env.sh" ]; then
        source "$BUILD_TOOLS_BASE/env.sh"
    fi
    
    # 2. 设置平台专用工具链
    local platform_dir="$BUILD_TOOLS_PLATFORMS/${arch}/${cpu}"
    if [ -d "$platform_dir" ] && [ -f "$platform_dir/env.sh" ]; then
        source "$platform_dir/env.sh"
        
        # 复制到构建目录
        mkdir -p "$BUILD_DIR/staging_dir"
        if [ -d "$platform_dir/toolchain" ]; then
            log "📦 复制平台工具链到构建目录"
            cp -r "$platform_dir/toolchain" "$BUILD_DIR/staging_dir/"
        fi
    else
        log "❌ 平台专用工具链不存在: $arch-$cpu"
        return 1
    fi
    
    # 3. 恢复版本专用文件
    local version_dir="$BUILD_TOOLS_VERSIONS/$openwrt_version"
    if [ -f "$version_dir/configs/${target}-${subtarget}.config" ]; then
        cp "$version_dir/configs/${target}-${subtarget}.config" "$BUILD_DIR/.config"
        log "📋 恢复版本配置"
    fi
    
    if [ -f "$version_dir/feeds/feeds.conf.default" ]; then
        cp "$version_dir/feeds/feeds.conf.default" "$BUILD_DIR/"
        log "📦 恢复feeds配置"
    fi
    
    # 设置环境变量
    export STAGING_DIR="$BUILD_DIR/staging_dir"
    export PATH="$BUILD_DIR/staging_dir/toolchain/bin:$PATH"
    
    log "✅ 分层工具链恢复完成"
    return 0
}

# 检查版本兼容性
check_version_compatibility() {
    local openwrt_version=$1
    local arch=$2
    local cpu=$3
    
    local platform_dir="$BUILD_TOOLS_PLATFORMS/${arch}/${cpu}"
    
    if [ ! -f "$platform_dir/version.info" ]; then
        echo "false"
        return
    fi
    
    local saved_version=$(cat "$platform_dir/version.info" 2>/dev/null || echo "")
    
    if [ -z "$saved_version" ]; then
        echo "false"
        return
    fi
    
    # 主要版本号匹配即可（例如 21.02 和 21.02.5 兼容）
    local major_version=$(echo "$openwrt_version" | cut -d. -f1,2)
    local saved_major=$(echo "$saved_version" | cut -d. -f1,2)
    
    if [ "$major_version" = "$saved_major" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# 智能工具链选择
smart_toolchain_selection() {
    local openwrt_version=$1
    local target=$2
    local subtarget=$3
    local force_rebuild=$4
    
    log "=== 智能工具链选择 ==="
    
    # 获取平台信息
    read arch cpu < <(get_platform_info "$target" "$subtarget")
    log "📊 平台: $arch-$cpu, 版本: $openwrt_version"
    
    # 检查通用工具
    install_common_host_tools
    
    # 检查是否需要完整重建
    if [ "$force_rebuild" = "true" ]; then
        log "🔄 强制重建工具链"
        build_and_save_toolchain "$openwrt_version" "$target" "$subtarget"
        return $?
    fi
    
    # 检查平台专用工具链
    local platform_dir="$BUILD_TOOLS_PLATFORMS/${arch}/${cpu}"
    if [ -d "$platform_dir" ] && [ -f "$platform_dir/env.sh" ]; then
        log "✅ 平台工具链已存在: $arch-$cpu"
        
        # 检查版本兼容性
        local version_compatible=$(check_version_compatibility "$openwrt_version" "$arch" "$cpu")
        if [ "$version_compatible" = "true" ]; then
            log "✅ 版本兼容，复用工具链"
            restore_toolchain "$openwrt_version" "$target" "$subtarget"
            return $?
        else
            log "🔄 版本不兼容，需要重建"
        fi
    else
        log "🔄 平台工具链不存在，需要构建"
    fi
    
    # 构建新的工具链
    build_and_save_toolchain "$openwrt_version" "$target" "$subtarget"
    return $?
}

# 清理工具链缓存
clean_toolchain_cache() {
    local keep_common=$1
    
    log "=== 清理工具链缓存 ==="
    
    if [ "$keep_common" = "true" ]; then
        # 只清理平台专用部分
        rm -rf $BUILD_TOOLS_PLATFORMS/*
        rm -rf $BUILD_TOOLS_VERSIONS/*
        rm -rf $BUILD_TOOLS_CACHE/*
        rm -rf $BUILD_TOOLS_LOGS/*
        log "✅ 已清理平台专用工具链，保留通用工具"
    else
        # 清理所有（保留目录结构）
        rm -rf $BUILD_TOOLS_BASE/*
        mkdir -p $BUILD_TOOLS_BASE
        log "✅ 已清理所有工具链缓存"
    fi
}

# 显示工具链状态
show_toolchain_status() {
    echo "=== 工具链状态报告 ==="
    echo "📁 目录结构:"
    echo "  通用工具: $(find $BUILD_TOOLS_COMMON -type f 2>/dev/null | wc -l) 个文件"
    echo "  平台工具链: $(find $BUILD_TOOLS_PLATFORMS -name "env.sh" 2>/dev/null | wc -l) 个"
    echo "  版本配置: $(find $BUILD_TOOLS_VERSIONS -name "*.config" 2>/dev/null | wc -l) 个"
    echo ""
    
    if [ -f "$TOOLCHAIN_DB" ]; then
        echo "📊 数据库信息:"
        echo "  工具链数量: $(jq -r '.openwrt_versions | length' $TOOLCHAIN_DB 2>/dev/null || echo "0")"
        echo "  最后更新: $(jq -r '.last_sync' $TOOLCHAIN_DB 2>/dev/null || echo "未知")"
        echo ""
        
        echo "🔧 已缓存工具链:"
        jq -r '.openwrt_versions | keys[]' $TOOLCHAIN_DB 2>/dev/null | while read key; do
            echo "  ✅ $key"
        done || echo "  无"
    else
        echo "❌ 数据库文件不存在"
    fi
}

# 主函数
main() {
    case $1 in
        "init")
            init_layered_dirs
            ;;
        "install_common")
            install_common_host_tools
            ;;
        "smart_select")
            smart_toolchain_selection "$2" "$3" "$4" "$5"
            ;;
        "restore")
            restore_toolchain "$2" "$3" "$4"
            ;;
        "clean")
            clean_toolchain_cache "$2"
            ;;
        "status")
            show_toolchain_status
            ;;
        "test_compiler")
            read arch cpu < <(get_platform_info "$2" "$3")
            echo "架构: $arch, CPU: $cpu"
            check_cross_compiler "$arch" "$cpu" "$4"
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  init                     - 初始化分层目录"
            echo "  install_common           - 安装通用主机工具"
            echo "  smart_select <v> <t> <s> [force] - 智能选择/构建工具链"
            echo "  restore <v> <t> <s>      - 恢复工具链"
            echo "  clean [keep_common]      - 清理缓存"
            echo "  status                   - 查看状态"
            echo "  test_compiler <t> <s> <v> - 测试编译器"
            echo ""
            echo "示例:"
            echo "  ./toolchain_manager.sh smart_select openwrt-21.02 ipq40xx generic"
            echo "  ./toolchain_manager.sh restore openwrt-21.02 ipq40xx generic"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
