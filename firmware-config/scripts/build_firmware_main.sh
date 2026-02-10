#!/bin/bash
#【build_firmware_main.sh-01】
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPPORT_SCRIPT="$REPO_ROOT/support.sh"
CONFIG_DIR="$REPO_ROOT/firmware-config/config"

# 确保有日志目录
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
#【build_firmware_main.sh-01】

#【build_firmware_main.sh-02】
# 保存环境变量函数 - 修复版
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
    
    # 确保环境变量可被其他步骤访问
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
#【build_firmware_main.sh-02】

#【build_firmware_main.sh-03】
# 加载环境变量函数
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
        log "✅ 从 $ENV_FILE 加载环境变量"
    else
        log "⚠️ 环境文件不存在: $ENV_FILE"
    fi
}
#【build_firmware_main.sh-03】

#【build_firmware_main.sh-04】
# 安装编译依赖包 - 修复版：移除了不存在的java-propose-classpoint包
setup_environment() {
    log "=== 安装编译依赖包 ==="
    sudo apt-get update || handle_error "apt-get update失败"
    
    # 基础编译工具 - 修复：移除了不存在的java-propose-classpoint包
    local base_packages=(
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip
        zlib1g-dev file wget libelf-dev ecj fastjar
        libpython3-dev python3 python3-dev python3-pip python3-setuptools
        python3-yaml xsltproc zip subversion ninja-build automake autoconf
        libtool pkg-config help2man texinfo groff texlive texinfo cmake
        ccache time
    )
    
    # 网络工具
    local network_packages=(
        curl wget net-tools iputils-ping dnsutils
        openssh-client ca-certificates gnupg lsb-release
    )
    
    # 文件系统工具
    local filesystem_packages=(
        squashfs-tools dosfstools e2fsprogs mtools
        parted fdisk gdisk hdparm smartmontools
    )
    
    # 调试工具
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
    
    # 检查重要工具是否安装成功
    log "=== 验证工具安装 ==="
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
#【build_firmware_main.sh-04】

#【build_firmware_main.sh-05】
# 创建构建目录
create_build_dir() {
    log "=== 创建构建目录 ==="
    sudo mkdir -p $BUILD_DIR || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER $BUILD_DIR || handle_error "修改目录所有者失败"
    sudo chmod -R 755 $BUILD_DIR || handle_error "修改目录权限失败"
    
    # 检查目录权限
    if [ -w "$BUILD_DIR" ]; then
        log "✅ 构建目录创建完成: $BUILD_DIR"
    else
        log "❌ 构建目录权限错误"
        exit 1
    fi
}
#【build_firmware_main.sh-05】

#【build_firmware_main.sh-06】
# 初始化构建环境 - 调整顺序：先克隆源码再保存环境变量
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
    
    # 检查克隆的文件
    local important_source_files=("Makefile" "feeds.conf.default" "rules.mk" "Config.in")
    for file in "${important_source_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 源码文件存在: $file"
        else
            log "❌ 源码文件缺失: $file"
        fi
    done
    
    log "=== 设备配置 ==="
    # 调用support.sh获取设备平台信息
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
    
    save_env
    
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    
    log "✅ 构建环境初始化完成"
}
#【build_firmware_main.sh-06】

#【build_firmware_main.sh-07】
# 下载OpenWrt官方SDK函数 - 修复版：支持从support.sh获取信息
download_openwrt_sdk() {
    local target="$1"
    local subtarget="$2"
    local version="$3"
    
    log "=== 下载OpenWrt官方SDK工具链 ==="
    log "目标平台: $target/$subtarget"
    log "OpenWrt版本: $version"
    
    # 检查support.sh是否存在
    if [ ! -f "$SUPPORT_SCRIPT" ]; then
        log "❌ support.sh不存在，无法获取SDK信息"
        return 1
    fi
    
    # 确保support.sh有执行权限
    if [ ! -x "$SUPPORT_SCRIPT" ]; then
        chmod +x "$SUPPORT_SCRIPT"
        log "✅ 已添加support.sh执行权限"
    fi
    
    log "🔍 通过support.sh获取SDK信息..."
    
    # 调用support.sh获取SDK下载信息
    local sdk_info
    if sdk_info=$("$SUPPORT_SCRIPT" get-sdk-info "$target" "$subtarget" "$version" 2>/dev/null); then
        # 解析SDK信息：格式为 "SDK_URL|SDK_FILE|SDK_DIR"
        local sdk_url=$(echo "$sdk_info" | cut -d'|' -f1)
        local sdk_file=$(echo "$sdk_info" | cut -d'|' -f2)
        
        if [ -z "$sdk_url" ] || [ -z "$sdk_file" ]; then
            log "❌ 无法从support.sh获取有效的SDK信息"
            log "💡 请检查support.sh中的get-sdk-info函数"
            return 1
        fi
        
        log "📥 SDK下载信息:"
        log "  URL: $sdk_url"
        log "  文件: $sdk_file"
        
        # 创建SDK下载目录
        local sdk_download_dir="$BUILD_DIR/sdk-download"
        mkdir -p "$sdk_download_dir"
        
        # 下载SDK文件
        log "🚀 开始下载SDK文件..."
        if wget -q --show-progress -O "$sdk_download_dir/$sdk_file" "$sdk_url"; then
            log "✅ SDK文件下载成功: $sdk_file"
            
            # 清理之前解压的目录
            log "🧹 清理之前解压的目录..."
            rm -rf "$BUILD_DIR"/openwrt-sdk-* 2>/dev/null || true
            
            # 解压SDK文件
            log "📦 解压SDK文件..."
            if tar -xf "$sdk_download_dir/$sdk_file" -C "$BUILD_DIR"; then
                log "✅ SDK文件解压成功"
                
                # 查找解压后的SDK目录 - 修复：更灵活的查找逻辑
                log "🔍 查找解压后的SDK目录..."
                
                # 首先尝试按预期的目录名查找
                local extracted_dir=""
                local sdk_base_name="${sdk_file%.tar.xz}"
                sdk_base_name="${sdk_base_name%.tar.gz}"
                sdk_base_name="${sdk_base_name%.tar.bz2}"
                
                # 查找包含"openwrt-sdk"或SDK文件名的目录
                if [ -d "$BUILD_DIR/$sdk_base_name" ]; then
                    extracted_dir="$BUILD_DIR/$sdk_base_name"
                else
                    # 查找其他可能的目录
                    extracted_dir=$(find "$BUILD_DIR" -maxdepth 2 -type d -name "openwrt-sdk-*" 2>/dev/null | head -1)
                fi
                
                if [ -n "$extracted_dir" ] && [ -d "$extracted_dir" ]; then
                    COMPILER_DIR="$extracted_dir"
                    log "✅ 找到SDK目录: $COMPILER_DIR"
                    
                    # 验证SDK文件 - 使用修复版的验证函数
                    if verify_sdk_files_v2 "$COMPILER_DIR"; then
                        log "🎉 SDK下载、解压和验证完成"
                        log "📌 编译器目录已设置为: $COMPILER_DIR"
                        
                        # 保存环境变量
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
        log "💡 需要修改support.sh，添加get-sdk-info函数"
        return 1
    fi
}

# 验证SDK文件函数V2 - 修复版：适配不同的SDK目录结构
verify_sdk_files_v2() {
    local sdk_dir="$1"
    
    log "=== 验证SDK文件完整性V2（修复版）==="
    
    if [ ! -d "$sdk_dir" ]; then
        log "❌ SDK目录不存在: $sdk_dir"
        return 1
    fi
    
    log "✅ SDK目录存在: $sdk_dir"
    log "📊 目录大小: $(du -sh "$sdk_dir" 2>/dev/null | cut -f1 || echo '未知')"
    log "📁 目录内容:"
    ls -la "$sdk_dir/" | head -10
    
    # 检查目录结构 - 查找可能的工具链目录
    log "🔍 检查SDK目录结构..."
    
    # 1. 首先检查是否有 staging_dir 目录（这是标准SDK结构）
    if [ -d "$sdk_dir/staging_dir" ]; then
        log "✅ 找到 staging_dir 目录"
        
        # 在 staging_dir 中查找工具链
        local toolchain_dirs=$(find "$sdk_dir/staging_dir" -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null)
        if [ -n "$toolchain_dirs" ]; then
            log "✅ 找到工具链目录"
            
            # 在工具链目录中查找GCC
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
        
        # 2. 如果没有找到工具链目录，直接在 staging_dir 中搜索
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
    
    # 3. 检查是否有 toolchain 目录（另一种SDK结构）
    if [ -d "$sdk_dir/toolchain" ]; then
        log "✅ 找到 toolchain 目录"
        
        # 在 toolchain 目录中查找GCC
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
    
    # 4. 最后，在整个SDK目录中搜索GCC
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
    
    # 5. 如果以上都失败，检查是否有工具链工具
    log "🔍 检查工具链工具..."
    local toolchain_tools=$(find "$sdk_dir" -maxdepth 5 -type f -executable \
      -name "*gcc*" \
      2>/dev/null | head -5)
    
    if [ -n "$toolchain_tools" ]; then
        log "📋 找到的工具链工具:"
        while read tool; do
            local tool_name=$(basename "$tool")
            log "  🔧 $tool_name"
            
            # 如果是gcc-ar等工具，显示其版本
            if [[ "$tool_name" == *gcc-ar* ]] || [[ "$tool_name" == *gcc-ranlib* ]] || [[ "$tool_name" == *gcc-nm* ]]; then
                local tool_version=$("$tool" --version 2>&1 | head -1)
                log "    版本信息: $tool_version"
            fi
        done <<< "$toolchain_tools"
        
        log "✅ 找到工具链工具，SDK可能有效"
        return 0
    fi
    
    log "❌ 未找到任何GCC编译器或工具链工具"
    log "📁 SDK目录内容详细列表:"
    find "$sdk_dir" -type f -executable -name "*" 2>/dev/null | head -20
    
    return 1
}

# 旧版本的验证函数（保持兼容性）
verify_sdk_files() {
    verify_sdk_files_v2 "$1"
}
#【build_firmware_main.sh-07】

#【build_firmware_main.sh-08】
# 初始化编译器环境（下载OpenWrt官方SDK）- 修复版
initialize_compiler_env() {
    local device_name="$1"
    log "=== 初始化编译器环境（下载OpenWrt官方SDK）- 修复版 ==="
    
    # 首先加载环境变量
    log "🔍 检查环境文件..."
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从 $BUILD_DIR/build_env.sh 加载环境变量"
    else
        log "❌ 环境文件不存在: $BUILD_DIR/build_env.sh"
        
        # 调用support.sh获取设备信息
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
        
        # 保存到环境文件
        save_env
        log "✅ 已创建环境文件: $BUILD_DIR/build_env.sh"
    fi
    
    # 检查环境变量中的COMPILER_DIR
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ 使用环境变量中的编译器目录: $COMPILER_DIR"
        
        # 验证编译器目录是否真的包含GCC
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
            
            # 保存到环境文件
            save_env
            return 0
        else
            log "⚠️ 编译器目录存在但不包含真正的GCC，将重新下载SDK"
        fi
    else
        log "🔍 COMPILER_DIR未设置或目录不存在，将下载OpenWrt官方SDK"
    fi
    
    # 根据设备确定平台（使用已设置的变量）
    log "目标平台: $TARGET/$SUBTARGET"
    log "目标设备: $DEVICE"
    log "OpenWrt版本: $SELECTED_BRANCH"
    
    # 简化版本字符串（从openwrt-23.05转为23.05）
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
    
    # 下载OpenWrt官方SDK
    log "🚀 开始下载OpenWrt官方SDK..."
    if download_openwrt_sdk "$TARGET" "$SUBTARGET" "$version_for_sdk"; then
        log "🎉 OpenWrt SDK下载并设置成功"
        log "📌 编译器目录: $COMPILER_DIR"
        
        # 显示SDK目录信息
        if [ -d "$COMPILER_DIR" ]; then
            log "📊 SDK目录信息:"
            log "  目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo '未知')"
            
            # 查找GCC编译器
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
        
        # 保存到环境文件
        save_env
        
        return 0
    else
        log "❌ OpenWrt SDK下载失败"
        return 1
    fi
}
#【build_firmware_main.sh-08】

#【build_firmware_main.sh-09】
# 添加 TurboACC 支持 - 修复版：所有版本都添加
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
#【build_firmware_main.sh-09】

#【build_firmware_main.sh-10】
# 配置Feeds - 修复版：统一处理TurboACC
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
    
    # 统一添加TurboACC支持（所有版本都添加）
    if [ "$CONFIG_MODE" = "normal" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
        log "✅ 添加TurboACC feed（所有版本）"
    fi
    
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    # 检查feeds安装结果
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
#【build_firmware_main.sh-10】

#【build_firmware_main.sh-11】
# 安装 TurboACC 包
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
#【build_firmware_main.sh-11】

#【build_firmware_main.sh-12】
# 编译前空间检查
pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    
    # 详细磁盘信息
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 构建目录空间
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    # 检查/mnt可用空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    echo "/mnt 可用空间: ${available_gb}G"
    
    # 检查/可用空间
    local root_available_space=$(df / --output=avail | tail -1)
    local root_available_gb=$((root_available_space / 1024 / 1024))
    echo "/ 可用空间: ${root_available_gb}G"
    
    # 内存和交换空间
    echo "=== 内存使用情况 ==="
    free -h
    
    # CPU信息
    echo "=== CPU信息 ==="
    echo "CPU核心数: $(nproc)"
    
    # 编译所需空间估算
    local estimated_space=15  # 估计需要15GB
    if [ $available_gb -lt $estimated_space ]; then
        log "⚠️ 警告: 可用空间(${available_gb}G)可能不足，建议至少${estimated_space}G"
    else
        log "✅ 磁盘空间充足: ${available_gb}G 可用"
    fi
    
    log "✅ 空间检查完成"
}
#【build_firmware_main.sh-12】

#【系统修复-06：更新generate_config函数】
# 智能配置生成系统 - 修复版：使用配置文件
generate_config() {
    local extra_packages=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 智能配置生成系统（使用配置文件）==="
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    log "配置文件目录: $CONFIG_DIR"
    
    # 防止递归调用的标记
    if [ -f "/tmp/generating_config.lock" ]; then
        log "⚠️ 检测到可能的递归调用，跳过重复配置生成"
        return 0
    fi
    
    touch "/tmp/generating_config.lock"
    
    rm -f .config .config.old
    
    # 生成基础配置
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    # 添加TCP BBR拥塞控制算法支持
    echo "# TCP BBR拥塞控制算法" >> .config
    echo "CONFIG_PACKAGE_kmod-tcp-bbr=y" >> .config
    echo "CONFIG_DEFAULT_TCP_CONG=\"bbr\"" >> .config
    echo "CONFIG_PACKAGE_tcp-bbr=y" >> .config
    log "✅ 添加TCP BBR拥塞控制算法支持"
    
    # 使用配置文件，而不是调用support.sh
    log "🔍 使用配置文件进行配置..."
    apply_configuration_from_files "$extra_packages"
    
    # 清理锁文件
    rm -f "/tmp/generating_config.lock"
    
    log "✅ 配置生成完成"
}

# 从配置文件应用配置 - 修改版：按新逻辑应用配置
apply_configuration_from_files() {
    local extra_packages=$1
    log "=== 从配置文件应用配置（新逻辑）==="
    
    # 检查配置文件目录
    if [ ! -d "$CONFIG_DIR" ]; then
        log "❌ 配置文件目录不存在: $CONFIG_DIR"
        handle_error "配置文件目录缺失"
    fi
    
    log "🔍 配置文件结构检查："
    log "  基础配置目录: $CONFIG_DIR"
    log "  设备名称: $DEVICE"
    log "  目标平台: $TARGET"
    log "  配置模式: $CONFIG_MODE"
    log "  OpenWrt版本: $SELECTED_BRANCH"
    
    # 1. 【必需】应用USB通用配置
    local usb_config="$CONFIG_DIR/usb-generic.config"
    if [ -f "$usb_config" ]; then
        log "📁 应用USB通用配置: $usb_config"
        cat "$usb_config" >> .config
        log "✅ USB通用配置应用完成 (行数: $(wc -l < "$usb_config"))"
    else
        log "❌ USB通用配置文件不存在: $usb_config"
        handle_error "缺少USB通用配置文件"
    fi
    
    # 2. 【必需】应用base配置（无论什么模式都需要）
    local base_config="$CONFIG_DIR/base.config"
    if [ -f "$base_config" ]; then
        log "📁 应用基础配置: $base_config"
        cat "$base_config" >> .config
        log "✅ 已应用基础配置"
    else
        log "❌ 基础配置文件不存在: $base_config"
        handle_error "缺少基础配置文件"
    fi
    
    # 3. 【模糊搜索】查找平台专用配置
    log "🔍 模糊搜索平台专用配置..."
    local platform_config=""
    
    # 在整个config目录中模糊搜索平台配置
    log "🔍 在整个config目录中搜索平台配置..."
    
    # 方法1：搜索包含平台名的配置文件
    local platform_match=$(find "$CONFIG_DIR" -type f -name "*.config" 2>/dev/null | \
        xargs grep -l "TARGET.*${TARGET}\|${TARGET}.*TARGET" 2>/dev/null | \
        grep -v "usb-generic.config" | grep -v "base.config" | grep -v "normal.config" | head -1)
    
    # 方法2：搜索文件名中包含平台名的配置文件
    if [ -z "$platform_match" ] || [ ! -f "$platform_match" ]; then
        platform_match=$(find "$CONFIG_DIR" -type f -name "*${TARGET}*.config" 2>/dev/null | head -1)
    fi
    
    # 方法3：在devices目录中搜索平台配置
    if [ -z "$platform_match" ] || [ ! -f "$platform_match" ]; then
        if [ -f "$CONFIG_DIR/devices/$TARGET.config" ]; then
            platform_config="$CONFIG_DIR/devices/$TARGET.config"
            log "✅ 找到完全匹配的平台配置: $TARGET.config"
        fi
    elif [ -n "$platform_match" ] && [ -f "$platform_match" ]; then
        platform_config="$platform_match"
        log "✅ 找到模糊匹配的平台配置: $(basename "$platform_match")"
    fi
    
    # 4. 【模糊搜索】查找设备专用配置
    log "🔍 模糊搜索设备专用配置..."
    local device_config=""
    
    # 首先检查是否有完全匹配的设备配置
    if [ -f "$CONFIG_DIR/devices/$DEVICE.config" ]; then
        device_config="$CONFIG_DIR/devices/$DEVICE.config"
        log "✅ 找到完全匹配的设备配置: $DEVICE.config"
    else
        # 使用模糊搜索：在devices目录中搜索包含设备名的配置文件
        log "🔍 进行模糊搜索..."
        local fuzzy_match=$(find "$CONFIG_DIR/devices" -type f -name "*.config" 2>/dev/null | \
            grep -i "$DEVICE" | head -1)
        
        if [ -n "$fuzzy_match" ] && [ -f "$fuzzy_match" ]; then
            device_config="$fuzzy_match"
            log "✅ 找到模糊匹配的设备配置: $(basename "$fuzzy_match")"
        fi
    fi
    
    # 5. 【配置逻辑】根据你的需求应用配置
    if [ -n "$device_config" ]; then
        # 情况1：有设备配置时，使用 usb-generic.config + 设备配置
        log "📋 配置逻辑: 有设备配置时"
        log "💡 使用配置: usb-generic.config + 设备配置"
        
        # 应用设备配置
        cat "$device_config" >> .config
        log "✅ 已应用设备配置: $(basename "$device_config")"
        
        # 注意：有设备配置时不应用base.config和normal.config
        log "💡 有设备配置时不应用base.config和normal.config"
        
    elif [ "$CONFIG_MODE" = "normal" ]; then
        # 情况2：正常模式（无设备配置）
        log "📋 配置逻辑: 正常模式（无设备配置）"
        log "💡 使用配置: usb-generic.config + base.config + normal.config"
        
        local normal_config="$CONFIG_DIR/normal.config"
        if [ -f "$normal_config" ]; then
            log "📁 应用正常模式配置: $normal_config"
            
            # 检查TurboACC配置冲突
            if grep -q "CONFIG_PACKAGE_luci-app-turboacc=y" "$normal_config"; then
                log "⚠️ 检测到TurboACC静态配置，正在处理..."
                # 创建临时文件，移除TurboACC配置
                local temp_file=$(mktemp)
                grep -v "CONFIG_PACKAGE_luci-app-turboacc" "$normal_config" | \
                grep -v "CONFIG_PACKAGE_kmod-shortcut-fe" | \
                grep -v "CONFIG_PACKAGE_kmod-fast-classifier" > "$temp_file"
                cat "$temp_file" >> .config
                rm -f "$temp_file"
                log "✅ TurboACC配置已移除（将通过feeds动态添加）"
            else
                cat "$normal_config" >> .config
            fi
            log "✅ 已应用正常模式配置"
        else
            log "❌ 正常模式配置文件不存在: $normal_config"
            handle_error "缺少正常模式配置文件"
        fi
    else
        # 情况3：基础模式（无设备配置）
        log "📋 配置逻辑: 基础模式（无设备配置）"
        log "💡 使用配置: usb-generic.config + base.config"
    fi
    
    # 6. 【平台配置】如果有平台专用配置，所有情况都加上
    if [ -n "$platform_config" ]; then
        log "📋 平台配置规则: 有平台专用配置时，所有情况都加上"
        log "💡 追加平台配置: $(basename "$platform_config")"
        
        cat "$platform_config" >> .config
        log "✅ 已应用平台专用配置"
    else
        log "💡 无平台专用配置，跳过平台配置"
    fi
    
    # 7. 添加额外包
    if [ -n "$extra_packages" ]; then
        log "📦 添加额外包: $extra_packages"
        echo "$extra_packages" | tr ',' '\n' | while read pkg; do
            if [ -n "$pkg" ]; then
                echo "CONFIG_PACKAGE_${pkg}=y" >> .config
                log "✅ 添加包: $pkg"
            fi
        done
    fi
    
    # 8. 显示配置摘要
    log "📊 配置应用摘要:"
    log "  ✅ USB通用配置: 已应用"
    
    if [ -n "$device_config" ]; then
        log "  ✅ 设备配置: 已应用 ($(basename "$device_config"))"
        log "  ⚠️ 基础配置: 已跳过（因为有设备配置）"
        log "  ⚠️ 正常模式配置: 已跳过（因为有设备配置）"
    else
        log "  ✅ 基础配置: 已应用"
        if [ "$CONFIG_MODE" = "normal" ]; then
            log "  ✅ 正常模式配置: 已应用"
        else
            log "  ℹ️ 正常模式配置: 未应用（基础模式）"
        fi
    fi
    
    if [ -n "$platform_config" ]; then
        log "  ✅ 平台专用配置: 已应用 ($(basename "$platform_config"))"
    else
        log "  ℹ️ 平台专用配置: 未找到"
    fi
    
    if [ -n "$extra_packages" ]; then
        log "  ✅ 额外包: 已添加 ($extra_packages)"
    fi
    
    log "✅ 配置文件应用完成"
}
#【系统修复-06结束】

#【build_firmware_main.sh-14】
# 验证USB配置 - 更新检查列表
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
    
    # 输出总结
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
#【build_firmware_main.sh-14】

#【build_firmware_main.sh-15】
# 检查USB驱动完整性
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
    
    # 根据平台添加专用驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        required_drivers+=("kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3")
    elif [ "$TARGET" = "ramips" ]; then
        required_drivers+=("kmod-usb-xhci-mtk")
    elif [ "$TARGET" = "ath79" ]; then
        required_drivers+=("kmod-usb2-ath79")
    fi
    
    # 检查所有必需驱动
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
        make defconfig
        log "✅ USB驱动修复完成"
    else
        log "🎉 所有必需USB驱动都已启用"
    fi
}
#【build_firmware_main.sh-15】

#【build_firmware_main.sh-16】
# 应用配置并显示详情 - 修复版：包含libustream冲突修复
apply_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 应用配置并显示详情 ==="
    
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在，无法应用配置"
        return 1
    fi
    
    log "📋 配置详情:"
    log "配置文件大小: $(ls -lh .config | awk '{print $5}')"
    log "配置行数: $(wc -l < .config)"
    
    # 检查libustream冲突并修复
    log "🔍 检查libustream冲突..."
    if grep -q "CONFIG_PACKAGE_libustream-openssl" .config && grep -q "CONFIG_PACKAGE_libustream-wolfssl" .config; then
        log "⚠️ 发现libustream-openssl和libustream-wolfssl冲突"
        log "🔧 修复冲突: 禁用libustream-openssl"
        sed -i 's/CONFIG_PACKAGE_libustream-openssl=y/# CONFIG_PACKAGE_libustream-openssl is not set/' .config
        log "✅ 冲突已修复"
    fi
    
    # 运行defconfig
    log "🔄 运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log "✅ 配置应用完成"
    log "最终配置文件: .config"
    log "最终配置大小: $(ls -lh .config | awk '{print $5}')"
}
#【build_firmware_main.sh-16】

#【build_firmware_main.sh-17】
# 修复网络环境
fix_network() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 修复网络环境 ==="
    
    # 设置git配置
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    git config --global core.compression 0
    git config --global core.looseCompression 0
    
    # 设置环境变量
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    export CURL_SSL_NO_VERIFY=1
    
    # 设置apt代理（如果有）
    if [ -n "$http_proxy" ]; then
        echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee /etc/apt/apt.conf.d/proxy.conf > /dev/null
    fi
    
    # 测试网络连接
    log "测试网络连接..."
    if curl -s --connect-timeout 10 https://github.com > /dev/null; then
        log "✅ 网络连接正常"
    else
        log "⚠️ 网络连接可能有问题"
    fi
    
    log "✅ 网络环境修复完成"
}
#【build_firmware_main.sh-17】

#【build_firmware_main.sh-18】
# 下载依赖包
download_dependencies() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 下载依赖包 ==="
    
    # 检查依赖包目录
    if [ ! -d "dl" ]; then
        mkdir -p dl
        log "创建依赖包目录: dl"
    fi
    
    # 显示现有依赖包
    local existing_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "现有依赖包数量: $existing_deps 个"
    
    # 下载依赖包
    log "开始下载依赖包..."
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    # 检查下载结果
    local downloaded_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "下载后依赖包数量: $downloaded_deps 个"
    
    if [ $downloaded_deps -gt $existing_deps ]; then
        log "✅ 成功下载了 $((downloaded_deps - existing_deps)) 个新依赖包"
    else
        log "ℹ️ 没有下载新的依赖包"
    fi
    
    # 检查下载日志中的错误
    if grep -q "ERROR\|Failed\|404" download.log 2>/dev/null; then
        log "⚠️ 下载过程中发现错误:"
        grep -E "ERROR|Failed|404" download.log | head -10
    fi
    
    log "✅ 依赖包下载完成"
}
#【build_firmware_main.sh-18】

#【build_firmware_main.sh-19】
# 检测是否为英文文件名（只包含ASCII字符）- 修复版
is_english_filename() {
    local filename="$1"
    # 检查是否只包含ASCII字符（字母、数字、下划线、连字符、点）
    if [[ "$filename" =~ ^[a-zA-Z0-9_.\-]+$ ]]; then
        return 0  # 英文文件名
    else
        return 1  # 非英文文件名
    fi
}

# 递归查找所有自定义文件函数
recursive_find_custom_files() {
    local base_dir="$1"
    local max_depth="${2:-10}"  # 默认最大深度10
    
    # 使用find命令递归查找所有文件
    find "$base_dir" -type f -maxdepth "$max_depth" 2>/dev/null | sort
}
#【build_firmware_main.sh-19】

#【build_firmware_main.sh-20】
# 集成自定义文件函数（增强版）- 递归查找、详细日志、保持原文件名
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
    
    # 递归查找所有自定义文件
    log "🔍 递归查找所有自定义文件..."
    local all_files=$(recursive_find_custom_files "$custom_dir")
    local file_count=$(echo "$all_files" | wc -l)
    
    if [ $file_count -eq 0 ]; then
        log "ℹ️ 未找到任何自定义文件"
        return 0
    fi
    
    log "📊 找到 $file_count 个自定义文件"
    
    # 分类统计
    local ipk_count=0
    local script_count=0
    local config_count=0
    local other_count=0
    local english_count=0
    local non_english_count=0
    
    # 详细显示所有文件
    echo ""
    log "📋 详细文件列表:"
    echo "----------------------------------------------------------------"
    
    while IFS= read -r file; do
        [ -z "$file" ] && continue
        
        local rel_path="${file#$custom_dir/}"
        local file_name=$(basename "$file")
        local file_size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
        local file_type=$(file -b --mime-type "$file" 2>/dev/null | cut -d'/' -f1 || echo "未知")
        
        # 检查是否为英文文件名 - 使用修复版检测
        if is_english_filename "$file_name"; then
            local name_status="✅ 英文"
            english_count=$((english_count + 1))
        else
            local name_status="⚠️ 非英文"
            non_english_count=$((non_english_count + 1))
        fi
        
        # 文件类型统计
        if [[ "$file_name" =~ \.ipk$ ]] || [[ "$file_name" =~ \.IPK$ ]] || [[ "$file_name" =~ \.Ipk$ ]]; then
            local type_desc="📦 IPK包"
            ipk_count=$((ipk_count + 1))
        elif [[ "$file_name" =~ \.sh$ ]] || [[ "$file_name" =~ \.Sh$ ]] || [[ "$file_name" =~ \.SH$ ]]; then
            local type_desc="📜 脚本"
            script_count=$((script_count + 1))
        elif [[ "$file_name" =~ \.conf$ ]] || [[ "$file_name" =~ \.config$ ]] || [[ "$file_name" =~ \.CONF$ ]]; then
            local type_desc="⚙️ 配置"
            config_count=$((config_count + 1))
        else
            local type_desc="📁 其他"
            other_count=$((other_count + 1))
        fi
        
        printf "%-50s %-10s %-15s %s\n" "$rel_path" "$file_size" "$type_desc" "$name_status"
        
    done <<< "$all_files"
    
    echo "----------------------------------------------------------------"
    
    # 统计信息
    echo ""
    log "📊 文件统计:"
    log "  文件总数: $file_count 个"
    log "  📦 IPK文件: $ipk_count 个"
    log "  📜 脚本文件: $script_count 个"
    log "  ⚙️ 配置文件: $config_count 个"
    log "  📁 其他文件: $other_count 个"
    log "  ✅ 英文文件名: $english_count 个"
    log "  ⚠️ 非英文文件名: $non_english_count 个"
    
    # 文件名建议提示 - 简化版本
    if [ $non_english_count -gt 0 ]; then
        echo ""
        log "💡 文件名建议:"
        log "  为了更好的兼容性，方便复制、运行，建议使用英文文件名"
        log "  当前系统会自动处理非英文文件名，但英文名有更好的兼容性"
    fi
    
    # 创建自定义文件目录
    echo ""
    log "🔧 步骤1: 创建自定义文件目录"
    
    local custom_files_dir="files/etc/custom-files"
    mkdir -p "$custom_files_dir"
    log "✅ 创建自定义文件目录: $custom_files_dir"
    
    # 复制所有文件到自定义目录（保持原文件名）
    echo ""
    log "🔧 步骤2: 复制所有自定义文件（保持原文件名）"
    
    local copied_count=0
    local skip_count=0
    
    while IFS= read -r src_file; do
        [ -z "$src_file" ] && continue
        
        local rel_path="${src_file#$custom_dir/}"
        local dest_path="$custom_files_dir/$rel_path"
        local dest_dir=$(dirname "$dest_path")
        
        # 创建目标目录
        mkdir -p "$dest_dir"
        
        # 复制文件
        if cp "$src_file" "$dest_path" 2>/dev/null; then
            copied_count=$((copied_count + 1))
            
            # 确保脚本文件有执行权限
            if [[ "$src_file" =~ \.sh$ ]] || [[ "$src_file" =~ \.Sh$ ]] || [[ "$src_file" =~ \.SH$ ]]; then
                chmod +x "$dest_path" 2>/dev/null || true
            fi
        else
            log "⚠️ 复制文件失败: $rel_path"
            skip_count=$((skip_count + 1))
        fi
        
    done <<< "$all_files"
    
    log "✅ 文件复制完成: $copied_count 个文件已复制，$skip_count 个文件跳过"
    
    # 创建第一次开机运行的安装脚本（增强版）
    echo ""
    log "🔧 步骤3: 创建第一次开机安装脚本（增强版）"
    
    local first_boot_dir="files/etc/uci-defaults"
    mkdir -p "$first_boot_dir"
    
    # 创建第一次开机运行的脚本 - 增强版
    local first_boot_script="$first_boot_dir/99-custom-files"
    cat > "$first_boot_script" << 'EOF'
#!/bin/sh

# 创建日志目录
LOG_DIR="/root/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/custom-files-install-$(date +%Y%m%d_%H%M%S).log"

echo "==================================================" > $LOG_FILE
echo "      自定义文件安装脚本（增强版）" >> $LOG_FILE
echo "      开始时间: $(date)" >> $LOG_FILE
echo "      日志文件: $LOG_FILE" >> $LOG_FILE
echo "==================================================" >> $LOG_FILE
echo "" >> $LOG_FILE

CUSTOM_DIR="/etc/custom-files"

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
    
    # 1. 安装IPK文件（增强版）
    IPK_COUNT=0
    IPK_SUCCESS=0
    IPK_FAILED=0
    
    echo "📦 开始安装IPK包..." >> $LOG_FILE
    
    # 使用临时文件来存储文件列表，确保while循环在当前shell中运行
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        # 检查是否是IPK文件（不区分大小写）
        if echo "$file_name" | grep -qi "\.ipk$"; then
            IPK_COUNT=$((IPK_COUNT + 1))
            rel_path="${file#$CUSTOM_DIR/}"
            
            echo "  🔧 正在安装 [$IPK_COUNT]: $rel_path" >> $LOG_FILE
            echo "      开始时间: $(date '+%H:%M:%S')" >> $LOG_FILE
            
            # 安装IPK包，错误不退出
            if opkg install "$file" >> $LOG_FILE 2>&1; then
                echo "      ✅ 安装成功" >> $LOG_FILE
                IPK_SUCCESS=$((IPK_SUCCESS + 1))
            else
                echo "      ❌ 安装失败，继续下一个..." >> $LOG_FILE
                IPK_FAILED=$((IPK_FAILED + 1))
                
                # 记录详细错误信息
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
    
    # 2. 运行脚本文件（增强版）
    SCRIPT_COUNT=0
    SCRIPT_SUCCESS=0
    SCRIPT_FAILED=0
    
    echo "📜 开始运行脚本文件..." >> $LOG_FILE
    
    # 使用临时文件来存储文件列表
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        # 检查是否是脚本文件（不区分大小写）
        if echo "$file_name" | grep -qi "\.sh$"; then
            SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
            rel_path="${file#$CUSTOM_DIR/}"
            
            echo "  🚀 正在运行 [$SCRIPT_COUNT]: $rel_path" >> $LOG_FILE
            echo "      开始时间: $(date '+%H:%M:%S')" >> $LOG_FILE
            
            # 确保有执行权限
            chmod +x "$file" 2>/dev/null
            
            # 运行脚本，错误不退出
            if sh "$file" >> $LOG_FILE 2>&1; then
                echo "      ✅ 运行成功" >> $LOG_FILE
                SCRIPT_SUCCESS=$((SCRIPT_SUCCESS + 1))
            else
                local exit_code=$?
                echo "      ❌ 运行失败，退出代码: $exit_code" >> $LOG_FILE
                SCRIPT_FAILED=$((SCRIPT_FAILED + 1))
                
                # 记录详细错误信息
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
    
    # 3. 复制其他文件到特定位置
    OTHER_COUNT=0
    OTHER_SUCCESS=0
    OTHER_FAILED=0
    
    echo "📁 处理其他文件..." >> $LOG_FILE
    
    # 使用临时文件来存储文件列表
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        # 跳过已处理的文件类型
        if echo "$file_name" | grep -qi "\.ipk$"; then
            continue  # 已经在IPK处理阶段处理过了
        fi
        
        if echo "$file_name" | grep -qi "\.sh$"; then
            continue  # 已经在脚本处理阶段处理过了
        fi
        
        OTHER_COUNT=$((OTHER_COUNT + 1))
        rel_path="${file#$CUSTOM_DIR/}"
        
        echo "  📋 正在处理 [$OTHER_COUNT]: $rel_path" >> $LOG_FILE
        
        # 根据文件类型处理
        if echo "$file_name" | grep -qi "\.conf$"; then
            # 配置文件复制到/etc/config/
            echo "      类型: 配置文件" >> $LOG_FILE
            if cp "$file" "/etc/config/$file_name" 2>/dev/null; then
                echo "      ✅ 复制到 /etc/config/" >> $LOG_FILE
                OTHER_SUCCESS=$((OTHER_SUCCESS + 1))
            else
                echo "      ❌ 复制失败" >> $LOG_FILE
                OTHER_FAILED=$((OTHER_FAILED + 1))
            fi
        else
            # 其他文件复制到/tmp/
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
    
    # 4. 安装完成总结
    echo "==================================================" >> $LOG_FILE
    echo "      自定义文件安装完成" >> $LOG_FILE
    echo "      结束时间: $(date)" >> $LOG_FILE
    echo "      日志文件: $LOG_FILE" >> $LOG_FILE
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
    
    # 创建完成标记文件
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
    
    # 设置脚本权限
    chmod +x "$first_boot_script"
    log "✅ 创建第一次开机安装脚本: $first_boot_script"
    log "📝 脚本增强功能:"
    log "  1. ✅ 递归查找所有自定义文件"
    log "  2. ✅ 保持原文件名"
    log "  3. ✅ IPK安装错误不退出，继续下一个"
    log "  4. ✅ 详细日志记录每个文件的处理结果"
    log "  5. ✅ 分类统计和成功率计算"
    log "  6. ✅ 日志存储到 /root/logs/ 目录（重启不丢失）"
    
    # 创建文件名检查脚本
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

# 使用临时文件确保变量作用域
FILE_LIST=$(mktemp)
find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"

while IFS= read -r file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    file_name=$(basename "$file")
    rel_path="${file#$CUSTOM_DIR/}"
    
    # 检查是否只包含ASCII字符 - 修复正则表达式
    if echo "$file_name" | grep -q '^[a-zA-Z0-9_.\-]*$'; then
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
    
    # 显示最终统计
    echo ""
    log "📊 自定义文件集成统计:"
    log "  📦 IPK文件: $ipk_count 个"
    log "  📜 脚本文件: $script_count 个"
    log "  ⚙️ 配置文件: $config_count 个"
    log "  📁 其他文件: $other_count 个"
    log "  总文件数: $file_count 个"
    log "  ✅ 英文文件名: $english_count 个"
    log "  ⚠️ 非英文文件名: $non_english_count 个"
    log "  🚀 第一次开机安装脚本: 已创建（增强版）"
    log "  📍 自定义文件位置: /etc/custom-files/"
    log "  📁 日志位置: /root/logs/（重启不丢失）"
    log "  💡 安装方式: 第一次开机自动安装"
    
    if [ $non_english_count -gt 0 ]; then
        log "💡 文件名兼容性提示:"
        log "  当前有 $non_english_count 个文件使用非英文文件名"
        log "  建议改为英文文件名以获得更好的兼容性"
        log "  系统会自动处理非英文文件，但英文名更方便复制和运行"
    fi
    
    if [ $file_count -eq 0 ]; then
        log "⚠️ 警告: 自定义文件目录为空"
        log "💡 支持的文件夹结构:"
        log "  firmware-config/custom-files/"
        log "  ├── *.ipk          # IPK包文件"
        log "  ├── *.sh           # 脚本文件"
        log "  ├── *.conf         # 配置文件"
        log "  └── 其他文件       # 其他任何文件"
    else
        log "🎉 自定义文件集成完成"
        log "📌 自定义文件将在第一次开机时自动安装和运行"
        log "🔧 增强功能: 持久化日志、错误不退出、详细统计"
    fi
    
    # 保存自定义文件统计到文件，供其他步骤使用
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
    
    log "✅ 自定义文件统计已保存到: $CUSTOM_FILE_STATS"
}
#【build_firmware_main.sh-20】

#【build_firmware_main.sh-21】
# 专门的GCC版本检查函数（放宽版本要求，修复23.05 SDK验证）
check_gcc_version() {
    local gcc_path="$1"
    local target_version="${2:-11}"
    
    if [ ! -x "$gcc_path" ]; then
        log "❌ 文件不可执行: $gcc_path"
        return 1
    fi
    
    local version_output=$("$gcc_path" --version 2>&1)
    
    if echo "$version_output" | grep -qi "gcc"; then
        # 检查是否是虚假的dummy-tools编译器
        if echo "$version_output" | grep -qi "dummy-tools"; then
            log "⚠️ 虚假的GCC编译器: scripts/dummy-tools/gcc"
            return 1
        fi
        
        local full_version=$(echo "$version_output" | head -1)
        local compiler_name=$(basename "$gcc_path")
        log "✅ 找到GCC编译器: $compiler_name"
        log "   完整版本信息: $full_version"
        
        # 提取版本号
        local version_num=$(echo "$full_version" | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)
        if [ -n "$version_num" ]; then
            log "   版本号: $version_num"
            
            # 检查主要版本 - 放宽要求，允许8.x及以上版本
            local major_version=$(echo "$version_num" | cut -d. -f1)
            
            # 支持的GCC版本范围
            if [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                log "   ✅ GCC $major_version.x 版本兼容"
                return 0
            else
                log "   ⚠️ GCC版本 $major_version.x 可能不兼容（期望8-15）"
                return 1
            fi
        else
            log "   ⚠️ 无法提取版本号"
            # 检查是否是SDK中的GCC（如gcc-12.3.0）
            if echo "$full_version" | grep -qi "12.3.0"; then
                log "   🎯 检测到OpenWrt 23.05 SDK GCC 12.3.0"
                return 0
            fi
            return 1
        fi
    else
        log "⚠️ 不是GCC编译器或无法获取版本: $(basename "$gcc_path")"
        log "   输出: $(echo "$version_output" | head -1)"
        return 1
    fi
}

# 验证预构建编译器文件（使用两步搜索法）- 修复23.05验证逻辑
verify_compiler_files() {
    log "=== 验证预构建编译器文件 ==="
    
    # 确定目标平台
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
    
    # 首先检查环境变量中的编译器目录
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ 使用环境变量中的编译器目录: $COMPILER_DIR"
        local compiler_dir="$COMPILER_DIR"
    else
        log "🔍 编译器目录未设置或目录不存在"
        log "💡 将使用OpenWrt自动构建的编译器"
        return 0
    fi
    
    # 详细检查编译器目录
    log "📊 编译器目录详细检查:"
    log "  路径: $compiler_dir"
    log "  大小: $(du -sh "$compiler_dir" 2>/dev/null | cut -f1 || echo '未知')"
    
    # 查找真正的GCC编译器（排除工具链工具和虚假编译器）- 修复查找逻辑
    log "⚙️ 可执行编译器检查:"
    local gcc_executable=""
    
    # 首先在bin目录中查找，排除dummy-tools
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
    
    # 如果没找到，在整个目录中搜索，排除dummy-tools
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
        
        # 检查是否是虚假的dummy-tools编译器
        local version_output=$("$gcc_executable" --version 2>&1)
        if echo "$version_output" | grep -qi "dummy-tools"; then
            log "     ⚠️ 虚假的GCC编译器: scripts/dummy-tools/gcc"
            log "     🔍 继续查找真正的GCC编译器..."
            
            # 继续查找排除这个虚假的
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
            # 使用专门的版本检查函数
            if check_gcc_version "$gcc_executable" "11"; then
                gcc_version_valid=1
                log "     🎯 GCC 8-15.x 版本兼容验证成功"
            else
                log "     ⚠️ GCC版本检查警告"
                
                # 显示实际版本信息
                local version=$("$gcc_executable" --version 2>&1 | head -1)
                log "     实际版本: $version"
                
                # 检查主要版本
                local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
                if [ -n "$major_version" ]; then
                    if [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                        log "     ✅ GCC $major_version.x 可以兼容使用"
                        gcc_version_valid=1
                    elif echo "$version" | grep -qi "12.3.0"; then
                        # 特殊处理OpenWrt 23.05 SDK的GCC 12.3.0
                        log "     🎯 检测到OpenWrt 23.05 SDK GCC 12.3.0，自动兼容"
                        gcc_version_valid=1
                    fi
                fi
            fi
            
            # 检查平台匹配
            local gcc_name=$(basename "$gcc_executable")
            if [ "$target_platform" = "arm" ]; then
                if [[ "$gcc_name" == *arm* ]] || [[ "$gcc_name" == *aarch64* ]]; then
                    log "     🎯 编译器平台匹配: ARM"
                elif echo "$gcc_name" | grep -qi "gcc"; then
                    # 对于SDK中的GCC，检查是否是交叉编译器
                    log "     🔄 编译器名称: $gcc_name (可能是通用交叉编译器)"
                else
                    log "     ⚠️ 编译器平台不匹配: $gcc_name (期望: ARM)"
                fi
            elif [ "$target_platform" = "mips" ]; then
                if [[ "$gcc_name" == *mips* ]] || [[ "$gcc_name" == *mipsel* ]]; then
                    log "     🎯 编译器平台匹配: MIPS"
                elif echo "$gcc_name" | grep -qi "gcc"; then
                    log "     🔄 编译器名称: $gcc_name (可能是通用交叉编译器)"
                else
                    log "     ⚠️ 编译器平台不匹配: $gcc_name (期望: MIPS)"
                fi
            fi
        fi
    else
        log "  🔍 未找到真正的GCC编译器，查找工具链工具..."
        
        # 查找工具链工具，排除dummy-tools
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
                
                # 如果是gcc-ar等工具，显示其版本
                if [[ "$tool_name" == *gcc-ar* ]] || [[ "$tool_name" == *gcc-ranlib* ]] || [[ "$tool_name" == *gcc-nm* ]]; then
                    local tool_version=$("$tool" --version 2>&1 | head -1)
                    log "      版本信息: $tool_version"
                    log "      ⚠️ 注意: 这是GCC工具链工具，不是GCC编译器"
                fi
            done <<< "$toolchain_tools"
        else
            log "  ❌ 未找到任何GCC相关可执行文件"
        fi
    fi
    
    if [ -n "$gpp_executable" ]; then
        log "  ✅ 找到可执行G++: $(basename "$gpp_executable")"
    fi
    
    # 检查必要的工具链（递归搜索），排除dummy-tools
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
    
    # 总结评估
    log "📈 编译器完整性评估:"
    log "  真正的GCC编译器: $([ -n "$gcc_executable" ] && echo "是" || echo "否")"
    log "  GCC兼容版本: $([ $gcc_version_valid -eq 1 ] && echo "是" || echo "否")"
    log "  工具链工具: $tool_found_count/${#required_tools[@]} 找到"
    
    # 评估是否可用（放宽版本要求）- 修复23.05评估逻辑
    if [ -n "$gcc_executable" ] && [ $gcc_version_valid -eq 1 ] && [ $tool_found_count -ge 5 ]; then
        log "🎉 预构建编译器文件完整，GCC版本兼容"
        log "📌 编译器目录: $compiler_dir"
        
        # 添加到PATH环境变量
        if [ -d "$compiler_dir/bin" ]; then
            export PATH="$compiler_dir/bin:$compiler_dir:$PATH"
            log "🔧 已将编译器目录添加到PATH环境变量"
        fi
        
        return 0
    elif [ -n "$gcc_executable" ] && [ $gcc_version_valid -eq 1 ]; then
        log "⚠️ GCC版本兼容，但工具链不完整"
        log "💡 将尝试使用，但可能回退到自动构建"
        
        # 仍然尝试添加到PATH
        if [ -d "$compiler_dir/bin" ]; then
            export PATH="$compiler_dir/bin:$compiler_dir:$PATH"
        fi
        return 0
    elif [ -n "$gcc_executable" ]; then
        log "⚠️ 找到GCC编译器但版本可能不兼容"
        log "💡 建议使用GCC 8-15版本以获得最佳兼容性"
        
        # 显示实际版本信息
        if [ -n "$gcc_executable" ]; then
            local actual_version=$("$gcc_executable" --version 2>&1 | head -1)
            log "  实际GCC版本: $actual_version"
            
            # 如果是23.05 SDK的GCC 12.3.0，特殊处理
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
#【build_firmware_main.sh-21】

#【build_firmware_main.sh-22】
# 检查编译器调用状态（增强版）
check_compiler_invocation() {
    log "=== 检查编译器调用状态（增强版）==="
    
    # 检查是否有预构建编译器目录
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "🔍 检查预构建编译器调用..."
        
        # 显示当前PATH环境变量
        log "📋 当前PATH环境变量:"
        echo "$PATH" | tr ':' '\n' | grep -E "(compiler|gcc|toolchain)" | head -10 | while read path_item; do
            log "  📍 $path_item"
        done
        
        # 查找系统中可用的编译器
        log "🔧 查找可用编译器:"
        which gcc g++ 2>/dev/null | while read compiler_path; do
            log "  ⚙️ $(basename "$compiler_path"): $compiler_path"
            
            # 检查是否来自预构建目录
            if [[ "$compiler_path" == *"$COMPILER_DIR"* ]]; then
                log "    🎯 来自预构建目录: 是"
            else
                log "    🔄 来自其他位置: 否"
            fi
        done
        
        # 在构建目录中搜索调用的编译器
        if [ -d "$BUILD_DIR/staging_dir" ]; then
            log "📁 检查 staging_dir 中的编译器..."
            
            # 查找真正的GCC编译器（排除工具链工具和虚假编译器）
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
                
                # 检查GCC版本
                local version=$("$used_compiler" --version 2>&1 | head -1)
                log "     版本: $version"
                
                # 检查是否来自预构建目录
                if [[ "$used_compiler" == *"$COMPILER_DIR"* ]]; then
                    log "  🎯 编译器来自预构建目录: 是"
                    log "  📌 成功调用了预构建的编译器文件"
                    
                    # 验证GCC版本兼容性
                    local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
                    if [ -n "$major_version" ] && [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                        log "  ✅ GCC $major_version.x 版本兼容"
                    else
                        log "  ⚠️ 编译器版本可能不兼容"
                    fi
                else
                    log "  🔄 编译器来自其他位置: 否"
                    log "  📌 使用的是OpenWrt自动构建的编译器"
                fi
            else
                log "  ℹ️ 未找到真正的GCC编译器（当前未构建）"
                
                # 检查是否有SDK编译器
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
        else
            log "  ℹ️ staging_dir 目录不存在，编译器尚未构建"
            log "  📌 将使用下载的SDK编译器进行构建"
        fi
        
        # 检查构建日志中的编译器调用
        if [ -f "$BUILD_DIR/build.log" ]; then
            log "📖 分析构建日志中的编译器调用..."
            
            local compiler_calls=$(grep -c "gcc\|g++" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            log "  编译器调用次数: $compiler_calls"
            
            if [ $compiler_calls -gt 0 ]; then
                # 检查是否调用了预构建编译器
                local prebuilt_calls=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
                if [ $prebuilt_calls -gt 0 ]; then
                    log "  ✅ 构建日志显示调用了预构建编译器"
                    log "     调用次数: $prebuilt_calls"
                    
                    # 显示示例调用
                    grep "$COMPILER_DIR" "$BUILD_DIR/build.log" | head -2 | while read line; do
                        log "     示例: $(echo "$line" | tr -s ' ' | cut -c1-80)"
                    done
                else
                    log "  🔄 构建日志显示使用了其他编译器"
                    
                    # 显示使用的编译器路径
                    grep "gcc\|g++" "$BUILD_DIR/build.log" | head -2 | while read line; do
                        log "     示例: $(echo "$line" | tr -s ' ' | cut -c1-80)"
                    done
                fi
            fi
        fi
    else
        log "ℹ️ 未设置预构建编译器目录，将使用自动构建的编译器"
    fi
    
    # 检查系统编译器
    log "💻 系统编译器检查:"
    if command -v gcc >/dev/null 2>&1; then
        local sys_gcc=$(which gcc)
        local sys_version=$(gcc --version 2>&1 | head -1)
        log "  ✅ 系统GCC: $sys_gcc"
        log "     版本: $sys_version"
        
        # 检查系统GCC版本兼容性
        local major_version=$(echo "$sys_version" | grep -o "[0-9]\+" | head -1)
        if [ -n "$major_version" ] && [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
            log "     ✅ 系统GCC $major_version.x 版本兼容"
        else
            log "     ⚠️ 系统GCC版本可能不兼容"
        fi
    else
        log "  ❌ 系统GCC未找到"
    fi
    
    # 编译器调用状态详情
    log "🔧 编译器调用状态详情:"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "  📌 预构建编译器目录: $COMPILER_DIR"
        
        # 检查预构建编译器中的GCC版本，排除虚假编译器
        local prebuilt_gcc=$(find "$COMPILER_DIR" -maxdepth 5 -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
        
        if [ -n "$prebuilt_gcc" ]; then
            log "  ✅ 预构建GCC: $(basename "$prebuilt_gcc")"
            local prebuilt_version=$("$prebuilt_gcc" --version 2>&1 | head -1)
            log "     版本: $prebuilt_version"
        else
            log "  ⚠️ 预构建目录中未找到真正的GCC编译器"
        fi
    fi
    
    # 检查实际使用的编译器
    if [ -d "$BUILD_DIR/staging_dir" ]; then
        log "  🔍 实际使用的编译器:"
        local used_gcc=$(find "$BUILD_DIR/staging_dir" -maxdepth 5 -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
        
        if [ -n "$used_gcc" ]; then
            log "  ✅ 实际GCC: $(basename "$used_gcc")"
            local used_version=$("$used_gcc" --version 2>&1 | head -1)
            log "     版本: $used_version"
            
            # 检查是否来自预构建目录
            if [[ "$used_gcc" == *"$COMPILER_DIR"* ]]; then
                log "  🎯 编译器来源: 预构建目录"
            else
                log "  🛠️ 编译器来源: OpenWrt自动构建"
            fi
        else
            log "  ℹ️ 未找到正在使用的GCC编译器（可能尚未构建）"
        fi
    fi
    
    log "✅ 编译器调用状态检查完成"
}
#【build_firmware_main.sh-22】

#【系统修复-07：简化稳定版前置错误检查函数 - 重命名为pre_build_error_check】
# 前置错误检查（简化稳定版）- 修改函数名
pre_build_error_check() {
    load_env
    cd $BUILD_DIR || { log "❌ 进入构建目录失败"; exit 1; }
    
    log "=== 🚨 前置错误检查（简化稳定版）==="
    
    local error_count=0
    local warning_count=0
    
    # 1. 检查配置文件
    log "1. 检查配置文件..."
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        error_count=$((error_count + 1))
    else
        log "✅ .config 文件存在"
        # 简单检查文件大小，避免复杂管道
        if [ -s ".config" ]; then
            log "✅ 配置文件非空"
        else
            log "❌ 错误: .config 文件为空"
            error_count=$((error_count + 1))
        fi
    fi
    
    # 2. 检查feeds目录
    log "2. 检查feeds目录..."
    if [ ! -d "feeds" ]; then
        log "❌ 错误: feeds 目录不存在"
        error_count=$((error_count + 1))
    else
        log "✅ feeds 目录存在"
    fi
    
    # 3. 检查关键文件
    log "3. 检查关键文件..."
    local critical_files=("Makefile" "feeds.conf.default")
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 关键文件存在: $file"
        else
            log "❌ 错误: 关键文件不存在: $file"
            error_count=$((error_count + 1))
        fi
    done
    
    # 4. 检查磁盘空间（简化）
    log "4. 检查磁盘空间..."
    if df -h /mnt >/dev/null 2>&1; then
        log "✅ 磁盘空间可访问"
    else
        log "⚠️ 警告: 无法检查磁盘空间"
        warning_count=$((warning_count + 1))
    fi
    
    # 5. 检查SDK编译器
    log "5. 检查SDK编译器..."
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ SDK编译器目录存在: $COMPILER_DIR"
    else
        log "ℹ️ SDK编译器目录未设置或不存在，将使用自动构建"
    fi
    
    # 总结
    log ""
    log "=== 检查总结 ==="
    log "错误数量: $error_count 个"
    log "警告数量: $warning_count 个"
    
    if [ $error_count -eq 0 ]; then
        log "✅ 前置检查通过，可以开始编译"
        return 0
    else
        log "❌ 前置检查发现 $error_count 个错误，必须修复"
        return 1
    fi
}
#【系统修复-07结束】

#【build_firmware_main.sh-24】
# 编译固件
build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 编译固件（使用OpenWrt官方SDK工具链）==="
    
    # 显示详细的编译信息
    log "📋 编译信息:"
    log "  构建目录: $BUILD_DIR"
    log "  设备: $DEVICE"
    log "  版本: $SELECTED_BRANCH"
    log "  配置模式: $CONFIG_MODE"
    log "  编译器目录: $COMPILER_DIR"
    log "  启用缓存: $enable_cache"
    
    # 编译前最终检查
    log "编译前最终检查..."
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        exit 1
    fi
    
    if [ ! -d "staging_dir" ]; then
        log "⚠️ 警告: staging_dir 目录不存在"
    fi
    
    if [ ! -d "dl" ]; then
        log "⚠️ 警告: dl 目录不存在"
    fi
    
    # 检查预构建编译器文件
    log "🔧 检查预构建编译器调用状态..."
    verify_compiler_files
    
    # 检查编译器调用状态（使用增强版）
    check_compiler_invocation
    
    # 获取CPU核心数
    local cpu_cores=$(nproc)
    local make_jobs=$cpu_cores
    
    # 如果内存小于4GB，减少并行任务
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' 2>/dev/null || echo "4096")
    if [ $total_mem -lt 4096 ]; then
        make_jobs=$((cpu_cores / 2))
        if [ $make_jobs -lt 1 ]; then
            make_jobs=1
        fi
        log "⚠️ 内存较低(${total_mem}MB)，减少并行任务到 $make_jobs"
    fi
    
    # 记录编译器调用信息
    log "📝 编译器调用信息:"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "  预构建编译器目录: $COMPILER_DIR"
        
        # 检查预构建编译器是否会被调用，排除虚假编译器
        local prebuilt_gcc=$(find "$COMPILER_DIR" -maxdepth 5 -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
        
        if [ -n "$prebuilt_gcc" ]; then
            log "  ✅ 找到预构建GCC编译器: $(basename "$prebuilt_gcc")"
            log "     路径: $(dirname "$prebuilt_gcc")"
            
            # 检查GCC版本
            local version=$("$prebuilt_gcc" --version 2>&1 | head -1 2>/dev/null || echo "未知版本")
            log "     GCC版本: $version"
            
            # 检查版本兼容性
            local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1 2>/dev/null || echo "0")
            if [ -n "$major_version" ] && [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                log "  ✅ GCC $major_version.x 版本兼容"
            else
                log "  ⚠️ 编译器版本可能不兼容"
            fi
            
            # 添加到PATH环境变量（尝试让OpenWrt使用预构建编译器）
            export PATH="$COMPILER_DIR/bin:$COMPILER_DIR:$PATH"
            log "  🔧 已将预构建编译器目录添加到PATH"
        else
            log "  ⚠️ 未找到真正的GCC编译器，只有工具链工具"
            local toolchain_tools=$(find "$COMPILER_DIR" -maxdepth 5 -type f -executable -name "*gcc*" \
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
    else
        log "  ℹ️ 未设置预构建编译器目录，将使用OpenWrt自动构建的编译器"
    fi
    
    # 开始编译（默认启用缓存）
    log "🚀 开始编译固件，使用 $make_jobs 个并行任务"
    log "💡 编译器调用状态已记录，编译过程中将显示具体调用的编译器"
    
    make -j$make_jobs V=s 2>&1 | tee build.log
    BUILD_EXIT_CODE=${PIPESTATUS[0]}
    
    log "编译退出代码: $BUILD_EXIT_CODE"
    
    # 编译结果分析
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        log "✅ 固件编译成功"
        
        # 分析编译器调用情况
        log "🔍 编译器调用分析:"
        if [ -f "build.log" ]; then
            local prebuilt_calls=$(grep -c "$COMPILER_DIR" build.log 2>/dev/null || echo "0")
            local total_calls=$(grep -c "gcc\|g++" build.log 2>/dev/null || echo "0")
            
            if [ $prebuilt_calls -gt 0 ]; then
                log "  🎯 预构建编译器调用次数: $prebuilt_calls/$total_calls"
                log "  📌 成功调用了预构建的编译器文件"
                
                # 检查GCC版本调用
                if grep -q "$COMPILER_DIR" build.log 2>/dev/null; then
                    grep "$COMPILER_DIR" build.log | grep "gcc" | head -2 | while read line; do
                        log "     示例调用: $(echo "$line" | tr -s ' ' | cut -c1-80)"
                    done
                fi
            else
                log "  🔄 未检测到预构建编译器调用"
                log "  📌 使用的是OpenWrt自动构建的编译器"
            fi
        fi
        
        # 检查生成的固件
        if [ -d "bin/targets" ]; then
            local firmware_count=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l 2>/dev/null || echo "0")
            log "✅ 生成固件文件: $firmware_count 个"
            
            # 显示固件文件
            find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
                log "固件: $file ($(du -h "$file" 2>/dev/null | cut -f1 2>/dev/null || echo "未知大小"))"
            done
        else
            log "❌ 固件目录不存在"
        fi
    else
        log "❌ 编译失败，退出代码: $BUILD_EXIT_CODE"
        
        # 分析失败原因
        if [ -f "build.log" ]; then
            log "=== 编译错误摘要 ==="
            
            # 查找常见错误
            local error_count=$(grep -c "Error [0-9]|error:" build.log 2>/dev/null || echo "0")
            local warning_count=$(grep -c "Warning\|warning:" build.log 2>/dev/null || echo "0")
            
            log "发现 $error_count 个错误，$warning_count 个警告"
            
            # 显示前10个错误
            if [ $error_count -gt 0 ]; then
                log "前10个错误:"
                grep -i "Error\|error:" build.log | head -10
            fi
            
            # 检查编译器相关错误
            log "🔧 编译器相关错误:"
            if grep -q "compiler.*not found" build.log; then
                log "🚨 发现编译器未找到错误"
                log "检查编译器路径..."
                if [ -d "staging_dir" ]; then
                    find staging_dir -maxdepth 5 -type f -executable \
                      -name "*gcc" \
                      ! -name "*gcc-ar" \
                      ! -name "*gcc-ranlib" \
                      ! -name "*gcc-nm" \
                      ! -path "*dummy-tools*" \
                      ! -path "*scripts*" \
                      2>/dev/null | head -10
                fi
            fi
            
            if grep -q "$COMPILER_DIR" build.log 2>/dev/null && grep -q -i "error\|failed" build.log 2>/dev/null; then
                log "⚠️ 发现预构建编译器相关错误"
                log "建议检查预构建编译器的完整性和兼容性"
            fi
            
            # 检查常见错误类型
            if grep -q "undefined reference" build.log; then
                log "⚠️ 发现未定义引用错误"
            fi
            
            if grep -q "No such file" build.log; then
                log "⚠️ 发现文件不存在错误"
            fi
            
            if grep -q "out of memory\|Killed process" build.log; then
                log "⚠️ 可能是内存不足导致编译失败"
            fi
        fi
        
        exit $BUILD_EXIT_CODE
    fi
    
    log "✅ 固件编译完成"
    
    # 编译完成后保存环境变量
    save_env
}
#【build_firmware_main.sh-24】

#【build_firmware_main.sh-25】
# 编译后空间检查 - 修复磁盘空间检查函数
post_build_space_check() {
    log "=== 编译后空间检查 ==="
    
    echo "=== 磁盘使用情况 ==="
    df -h 2>/dev/null || echo "无法获取磁盘信息"
    
    # 构建目录空间
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1 2>/dev/null) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    # 固件文件大小
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        local firmware_size=$(find "$BUILD_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1 2>/dev/null || echo "未知")
        echo "固件文件总大小: $firmware_size"
    fi
    
    # 检查可用空间 - 修复：使用正确的df选项
    local available_space=$(df /mnt --output=avail 2>/dev/null | tail -1 | awk '{print $1}' 2>/dev/null || echo "0")
    local available_gb=$((available_space / 1024 / 1024))
    log "/mnt 可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        log "⚠️ 警告: 磁盘空间较低，建议清理"
    else
        log "✅ 磁盘空间充足"
    fi
    
    log "✅ 空间检查完成"
}
#【build_firmware_main.sh-25】

#【build_firmware_main.sh-26】
# 检查固件文件
check_firmware_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 固件文件检查 ==="
    
    if [ -d "bin/targets" ]; then
        log "✅ 固件目录存在"
        
        # 统计固件文件
        local firmware_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l 2>/dev/null || echo "0")
        local all_files=$(find bin/targets -type f 2>/dev/null | wc -l 2>/dev/null || echo "0")
        
        log "固件文件: $firmware_files 个"
        log "所有文件: $all_files 个"
        
        # 显示固件文件详情
        echo "=== 生成的固件文件 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \; 2>/dev/null || echo "无法列出固件文件"
        
        # 检查文件大小
        local total_size=0
        while read size; do
            total_size=$((total_size + size))
        done < <(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec stat -c%s {} \; 2>/dev/null 2>/dev/null)
        
        if [ $total_size -gt 0 ]; then
            local total_size_mb=$((total_size / 1024 / 1024))
            log "固件总大小: ${total_size_mb}MB"
            
            # 检查固件大小是否合理
            if [ $total_size_mb -lt 5 ]; then
                log "⚠️ 警告: 固件文件可能太小"
            elif [ $total_size_mb -gt 100 ]; then
                log "⚠️ 警告: 固件文件可能太大"
            else
                log "✅ 固件大小正常"
            fi
        fi
        
        # 检查目标目录结构
        echo "=== 目标目录结构 ==="
        find bin/targets -maxdepth 3 -type d 2>/dev/null | sort
        
    else
        log "❌ 固件目录不存在"
        exit 1
    fi
}
#【build_firmware_main.sh-26】

#【build_firmware_main.sh-27】
# 清理构建目录
cleanup() {
    log "=== 清理构建目录 ==="
    
    if [ -d "$BUILD_DIR" ]; then
        log "检查是否有需要保留的文件..."
        
        # 如果.config文件存在，先备份
        if [ -f "$BUILD_DIR/.config" ]; then
            log "备份配置文件..."
            mkdir -p /tmp/openwrt_backup
            local backup_file="/tmp/openwrt_backup/config_$(date +%Y%m%d_%H%M%S).config"
            cp "$BUILD_DIR/.config" "$backup_file"
            log "✅ 配置文件备份到: $backup_file"
        fi
        
        # 如果build.log存在，备份
        if [ -f "$BUILD_DIR/build.log" ]; then
            log "备份编译日志..."
            mkdir -p /tmp/openwrt_backup
            cp "$BUILD_DIR/build.log" "/tmp/openwrt_backup/build_$(date +%Y%m%d_%H%M%S).log"
        fi
        
        # 清理构建目录
        log "清理构建目录: $BUILD_DIR"
        sudo rm -rf $BUILD_DIR || log "⚠️ 清理构建目录失败"
        log "✅ 构建目录已清理"
    else
        log "ℹ️ 构建目录不存在，无需清理"
    fi
}
#【build_firmware_main.sh-27】

#【build_firmware_main.sh-28】
# 搜索编译器文件函数
search_compiler_files() {
    local search_root="${1:-/tmp}"
    local target_platform="$2"
    
    log "=== 搜索编译器文件 ==="
    log "搜索根目录: $search_root"
    log "目标平台: $target_platform"
    
    if [ ! -d "$search_root" ]; then
        log "❌ 搜索根目录不存在: $search_root"
        return 1
    fi
    
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}

# 通用编译器搜索函数
universal_compiler_search() {
    local search_root="${1:-/tmp}"
    local device_name="${2:-unknown}"
    
    log "=== 通用编译器搜索 ==="
    
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}

# 简单编译器文件搜索
search_compiler_files_simple() {
    local search_root="${1:-/tmp}"
    local target_platform="${2:-generic}"
    
    log "=== 简单编译器文件搜索 ==="
    
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}

# 智能平台感知的编译器搜索（两步搜索法） - 修改为下载SDK
intelligent_platform_aware_compiler_search() {
    local search_root="${1:-/tmp}"
    local target_platform="$2"
    local device_name="$3"
    
    log "=== 智能平台感知的编译器搜索（两步搜索法）==="
    log "目标平台: $target_platform"
    log "设备名称: $device_name"
    
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}
#【build_firmware_main.sh-28】

#【系统修复-05：新增配置文件验证函数】
# 位置：在合适的位置添加（比如第13部分之后）
# 功能：验证配置文件完整性
verify_config_files() {
    log "=== 🔍 验证配置文件完整性 ==="
    
    log "检查配置文件目录: $CONFIG_DIR"
    
    if [ ! -d "$CONFIG_DIR" ]; then
        log "❌ 配置文件目录不存在: $CONFIG_DIR"
        return 1
    fi
    
    # 必需文件列表
    local required_files=("base.config" "usb-generic.config")
    local optional_files=("normal.config")
    local optional_dirs=("devices")
    
    # 检查必需文件
    for file in "${required_files[@]}"; do
        local file_path="$CONFIG_DIR/$file"
        if [ -f "$file_path" ]; then
            local line_count=$(wc -l < "$file_path" 2>/dev/null || echo "0")
            log "✅ 必需文件存在: $file (行数: $line_count)"
        else
            log "❌ 必需文件缺失: $file"
            return 1
        fi
    done
    
    # 检查可选文件
    for file in "${optional_files[@]}"; do
        local file_path="$CONFIG_DIR/$file"
        if [ -f "$file_path" ]; then
            local line_count=$(wc -l < "$file_path" 2>/dev/null || echo "0")
            log "✅ 可选文件存在: $file (行数: $line_count)"
        else
            log "ℹ️ 可选文件不存在: $file (可跳过)"
        fi
    done
    
    # 检查可选目录
    for dir in "${optional_dirs[@]}"; do
        local dir_path="$CONFIG_DIR/$dir"
        if [ -d "$dir_path" ]; then
            local config_count=$(find "$dir_path" -type f -name "*.config" 2>/dev/null | wc -l 2>/dev/null || echo "0")
            log "✅ 目录存在: $dir (包含 $config_count 个配置文件)"
        else
            log "ℹ️ 可选目录不存在: $dir (可跳过)"
        fi
    done
    
    # 检查TurboACC配置冲突 - 修复版
    log "🔍 检查TurboACC配置冲突..."
    local turboacc_found=0
    
    # 方法1：使用find命令更安全地查找配置文件
    local config_files=$(find "$CONFIG_DIR" -type f -name "*.config" 2>/dev/null)
    
    if [ -n "$config_files" ]; then
        while IFS= read -r config_file; do
            if [ -f "$config_file" ] && grep -q "CONFIG_PACKAGE_luci-app-turboacc=y" "$config_file" 2>/dev/null; then
                log "⚠️ 发现TurboACC静态配置: $(basename "$config_file")"
                turboacc_found=1
            fi
        done <<< "$config_files"
    fi
    
    if [ $turboacc_found -eq 1 ]; then
        log "💡 建议：TurboACC应通过feeds动态添加，不要静态配置"
    fi
    
    log "✅ 配置文件验证完成"
    return 0
}
#【系统修复-05结束】

#【build_firmware_main.sh-29】
# 保存源代码信息
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
    
    # 收集目录信息
    echo "" >> "$source_info_file"
    echo "=== 目录结构 ===" >> "$source_info_file"
    find . -maxdepth 2 -type d 2>/dev/null | sort >> "$source_info_file"
    
    # 收集关键文件信息
    echo "" >> "$source_info_file"
    echo "=== 关键文件 ===" >> "$source_info_file"
    local key_files=("Makefile" "feeds.conf.default" ".config" "rules.mk" "Config.in")
    for file in "${key_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$file: 存在 ($(ls -lh "$file" 2>/dev/null | awk '{print $5}' 2>/dev/null || echo "未知大小"))" >> "$source_info_file"
        else
            echo "$file: 不存在" >> "$source_info_file"
        fi
    done
    
    log "✅ 源代码信息已保存到: $source_info_file"
}
#【build_firmware_main.sh-29】

#【build_firmware_main.sh-30】
# 新增：详细验证SDK目录函数
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
            
            # 尝试查找SDK目录
            local found_dirs=$(find /mnt/openwrt-build -maxdepth 1 -type d -name "*sdk*" 2>/dev/null)
            if [ -n "$found_dirs" ]; then
                log "找到可能的SDK目录:"
                echo "$found_dirs"
                
                # 使用第一个找到的目录
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

# 主函数
main() {
    local command="$1"
    local arg1="$2"
    local arg2="$3"
    local arg3="$4"
    local arg4="$5"
    
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
        "pre_build_error_check")
            pre_build_error_check
            ;;
        "build_firmware")
            build_firmware "$arg1"
            ;;
        "post_build_space_check")
            post_build_space_check
            ;;
        "check_firmware_files")
            check_firmware_files
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
        "search_compiler_files")
            search_compiler_files "$arg1" "$arg2"
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
        "verify_sdk_directory")
            verify_sdk_directory
            ;;
        "verify_config_files")
            verify_config_files
            ;;
        *)
            log "❌ 未知命令: $command"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  initialize_compiler_env - 初始化编译器环境（下载OpenWrt官方SDK）"
            echo "  add_turboacc_support, configure_feeds, install_turboacc_packages"
            echo "  pre_build_space_check, generate_config, verify_usb_config, check_usb_drivers_integrity, apply_config"
            echo "  fix_network, download_dependencies, integrate_custom_files"
            echo "  pre_build_error_check, build_firmware, post_build_space_check"
            echo "  check_firmware_files, cleanup, save_source_code_info, verify_compiler_files"
            echo "  check_compiler_invocation, search_compiler_files, universal_compiler_search"
            echo "  search_compiler_files_simple, intelligent_platform_aware_compiler_search"
            echo "  verify_sdk_directory - 详细验证SDK目录"
            echo "  verify_config_files - 验证配置文件完整性"
            exit 1
            ;;
    esac
}

# 检查是否有参数
if [ $# -eq 0 ]; then
    echo "错误: 需要提供命令参数"
    echo "用法: $0 <命令> [参数1] [参数2] [参数3] [参数4]"
    echo "例如: $0 initialize_build_env xiaomi_mi-router-4a-100m 23.05 normal"
    exit 1
fi

main "$@"
#【build_firmware_main.sh-30】
