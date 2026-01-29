#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# 修复：SUPPORT_DIR 应该指向 firmware-config 目录本身
SUPPORT_DIR="$REPO_ROOT/firmware-config"

# 确保有日志目录
mkdir -p /tmp/build-logs

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    log "详细错误信息:"
    echo "最后100行构建日志:"
    tail -100 /tmp/build-logs/*.log 2>/dev/null || echo "无日志文件"
    
    # 检查defconfig日志
    if [ -f "/tmp/defconfig.log" ]; then
        echo "defconfig 错误日志:"
        cat /tmp/defconfig.log
    fi
    
    # 检查.config文件
    if [ -f ".config" ]; then
        echo ".config 最后50行:"
        tail -50 .config
    fi
    
    exit 1
}

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
    echo "export DEVICE_NAME=\"${DEVICE_NAME}\"" >> $ENV_FILE
    echo "export PLATFORM=\"${PLATFORM}\"" >> $ENV_FILE
    echo "export SOURCE_REPO=\"${SOURCE_REPO}\"" >> $ENV_FILE
    
    # 确保环境变量可被其他步骤访问
    if [ -n "$GITHUB_ENV" ]; then
        echo "SELECTED_REPO_URL=${SELECTED_REPO_URL}" >> $GITHUB_ENV
        echo "SELECTED_BRANCH=${SELECTED_BRANCH}" >> $GITHUB_ENV
        echo "TARGET=${TARGET}" >> $GITHUB_ENV
        echo "SUBTARGET=${SUBTARGET}" >> $GITHUB_ENV
        echo "DEVICE=${DEVICE}" >> $GITHUB_ENV
        echo "CONFIG_MODE=${CONFIG_MODE}" >> $GITHUB_ENV
        echo "COMPILER_DIR=${COMPILER_DIR}" >> $GITHUB_ENV
        echo "DEVICE_NAME=${DEVICE_NAME}" >> $GITHUB_ENV
        echo "PLATFORM=${PLATFORM}" >> $GITHUB_ENV
        echo "SOURCE_REPO=${SOURCE_REPO}" >> $GITHUB_ENV
    fi
    
    chmod +x $ENV_FILE
    log "✅ 环境变量已保存到: $ENV_FILE"
}

# 加载环境变量函数
load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
        log "✅ 从 $ENV_FILE 加载环境变量"
    else
        log "⚠️ 环境文件不存在: $ENV_FILE"
    fi
}

# 加载设备支持脚本
load_device_support() {
    # 修复：support.sh 在 firmware-config 根目录下
    local support_file="$SUPPORT_DIR/support.sh"
    if [ -f "$support_file" ]; then
        source "$support_file"
        log "✅ 加载设备支持脚本: $support_file"
        return 0
    else
        log "⚠️ 设备支持脚本不存在: $support_file"
        return 1
    fi
}

# 加载配置模板
load_config_template() {
    local template_name="$1"
    # 修复：配置文件在 firmware-config/config/ 目录下
    local template_file="$SUPPORT_DIR/config/${template_name}.config"
    
    if [ -f "$template_file" ]; then
        log "📋 加载配置模板: $template_name"
        cat "$template_file" >> .config
        return 0
    else
        log "⚠️ 配置模板不存在: $template_file"
        return 1
    fi
}

# 加载USB配置
load_usb_config() {
    local platform="$1"
    local version="$2"
    
    log "🔧 加载USB配置 - 平台: $platform, 版本: $version"
    
    # 首先加载通用USB配置
    load_config_template "usb-generic"
    
    # 根据平台添加专用驱动
    echo "" >> .config
    echo "# 🟡 平台专用USB控制器驱动" >> .config
    
    case "$platform" in
        "ipq40xx")
            echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
            echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
            log "✅ 添加高通IPQ40xx平台专用USB驱动"
            ;;
        "ramips")
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
            log "✅ 添加雷凌MT76xx平台专用USB驱动"
            ;;
        "ath79")
            echo "CONFIG_PACKAGE_kmod-usb2-ath79=y" >> .config
            log "✅ 添加ath79平台专用USB驱动"
            ;;
    esac
    
    # 版本特定的NTFS配置
    echo "" >> .config
    echo "# 🔧 NTFS配置 - 版本: $version" >> .config
    if [ "$version" = "openwrt-23.05" ] || [ "$version" = "23.05" ]; then
        echo "# CONFIG_PACKAGE_ntfs-3g is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g-utils is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs3-mount is not set" >> .config
        log "✅ 23.05版本NTFS配置优化"
    else
        echo "CONFIG_PACKAGE_ntfs3-mount=y" >> .config
        log "✅ 21.02版本NTFS配置"
    fi
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

# 新增：下载OpenWrt官方SDK工具链函数
download_openwrt_sdk() {
    local target="$1"
    local subtarget="$2"
    local version="$3"
    
    log "=== 下载OpenWrt官方SDK工具链 ==="
    log "目标平台: $target/$subtarget"
    log "OpenWrt版本: $version"
    
    # 确定SDK下载URL
    local sdk_url=""
    local sdk_filename=""
    
    # 加载设备支持脚本获取SDK URL
    if load_device_support; then
        sdk_url=$(get_sdk_url "$target" "$subtarget" "$version")
    fi
    
    if [ -z "$sdk_url" ]; then
        # 如果支持脚本没有提供URL，使用内置配置
        if [ "$version" = "23.05" ] || [ "$version" = "openwrt-23.05" ]; then
            # OpenWrt 23.05 SDK - 修复GCC版本为12.3.0
            case "$target" in
                "ipq40xx")
                    sdk_url="https://downloads.openwrt.org/releases/23.05.3/targets/ipq40xx/generic/openwrt-sdk-23.05.3-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                    ;;
                "ramips")
                    if [ "$subtarget" = "mt76x8" ]; then
                        sdk_url="https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt76x8/openwrt-sdk-23.05.3-ramips-mt76x8_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                    elif [ "$subtarget" = "mt7621" ]; then
                        sdk_url="https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt7621/openwrt-sdk-23.05.3-ramips-mt7621_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                    fi
                    ;;
                "ath79")
                    sdk_url="https://downloads.openwrt.org/releases/23.05.3/targets/ath79/generic/openwrt-sdk-23.05.3-ath79-generic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                    ;;
            esac
        elif [ "$version" = "21.02" ] || [ "$version" = "openwrt-21.02" ]; then
            # OpenWrt 21.02 SDK - GCC版本保持8.4.0
            case "$target" in
                "ipq40xx")
                    sdk_url="https://downloads.openwrt.org/releases/21.02.7/targets/ipq40xx/generic/openwrt-sdk-21.02.7-ipq40xx-generic_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                    ;;
                "ramips")
                    if [ "$subtarget" = "mt76x8" ]; then
                        sdk_url="https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt76x8/openwrt-sdk-21.02.7-ramips-mt76x8_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                    elif [ "$subtarget" = "mt7621" ]; then
                        sdk_url="https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt7621/openwrt-sdk-21.02.7-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                    fi
                    ;;
                "ath79")
                    sdk_url="https://downloads.openwrt.org/releases/21.02.7/targets/ath79/generic/openwrt-sdk-21.02.7-ath79-generic_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                    ;;
            esac
        fi
    fi
    
    if [ -z "$sdk_url" ]; then
        log "❌ 无法确定SDK下载URL"
        return 1
    fi
    
    sdk_filename=$(basename "$sdk_url")
    log "📥 SDK下载URL: $sdk_url"
    log "📁 SDK文件名: $sdk_filename"
    
    # 创建SDK目录
    local sdk_dir="$BUILD_DIR/sdk"
    mkdir -p "$sdk_dir"
    
    # 下载SDK
    log "开始下载OpenWrt SDK..."
    if wget --tries=3 --timeout=30 -q -O "$sdk_dir/$sdk_filename" "$sdk_url"; then
        log "✅ SDK下载成功"
    else
        log "⚠️ 首次下载失败，尝试备用下载..."
        # 尝试使用curl
        if curl -L --connect-timeout 30 --retry 3 -o "$sdk_dir/$sdk_filename" "$sdk_url"; then
            log "✅ SDK下载成功（使用curl）"
        else
            log "❌ SDK下载失败"
            return 1
        fi
    fi
    
    # 解压SDK
    log "解压SDK..."
    cd "$sdk_dir"
    if tar -xf "$sdk_filename" --strip-components=1; then
        log "✅ SDK解压成功"
        rm -f "$sdk_filename"
    else
        log "❌ SDK解压失败"
        return 1
    fi
    
    # 查找SDK中的编译器
    local toolchain_dir=""
    if [ -d "toolchain" ]; then
        toolchain_dir="$sdk_dir/toolchain"
        log "✅ 找到toolchain目录: $toolchain_dir"
    else
        # 在SDK中搜索编译器，排除虚假的dummy-tools
        local gcc_file=$(find "$sdk_dir" -type f -executable \
            -name "*gcc" \
            ! -name "*gcc-ar" \
            ! -name "*gcc-ranlib" \
            ! -name "*gcc-nm" \
            ! -path "*dummy-tools*" \
            ! -path "*scripts*" \
            2>/dev/null | head -1)
        
        if [ -n "$gcc_file" ]; then
            toolchain_dir=$(dirname "$(dirname "$gcc_file")")
            log "✅ 在SDK中找到GCC编译器: $gcc_file"
            log "📁 编译器目录: $toolchain_dir"
        else
            # 尝试查找staging_dir中的工具链
            if [ -d "staging_dir" ]; then
                toolchain_dir=$(find "$sdk_dir/staging_dir" -name "toolchain-*" -type d | head -1)
                if [ -n "$toolchain_dir" ]; then
                    log "✅ 在staging_dir中找到工具链目录: $toolchain_dir"
                fi
            fi
        fi
    fi
    
    if [ -n "$toolchain_dir" ] && [ -d "$toolchain_dir" ]; then
        log "✅ 找到SDK中的编译器目录: $toolchain_dir"
        export COMPILER_DIR="$toolchain_dir"
        
        # 验证编译器
        verify_compiler_files
        return 0
    else
        log "❌ 未在SDK中找到编译器目录"
        return 1
    fi
}

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
        "ath79")
            target_platform="mips"
            target_suffix="mips_24kc"
            log "目标平台: MIPS (ath79)"
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
        log "🔍 编译器目录未设置或不存在"
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
    
    # 首先尝试在bin目录中查找，排除dummy-tools
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
    
    # 如果没有找到，在整个目录中搜索，排除dummy-tools
    if [ -z "$gcc_executable" ]; then
        gcc_executable=$(find "$compiler_dir" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -1)
    fi
    
    local gpp_executable=$(find "$compiler_dir" -type f -executable \
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
            gcc_executable=$(find "$compiler_dir" -type f -executable \
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
        local toolchain_tools=$(find "$compiler_dir" -type f -executable \
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
        local tool_executable=$(find "$compiler_dir" -type f -executable -name "*${tool}*" \
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
            local used_compiler=$(find "$BUILD_DIR/staging_dir" -type f -executable \
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
                    local sdk_gcc=$(find "$COMPILER_DIR" -type f -executable \
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
        local prebuilt_gcc=$(find "$COMPILER_DIR" -type f -executable \
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
        local used_gcc=$(find "$BUILD_DIR/staging_dir" -type f -executable \
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

# 前置错误检查（修复23.05 SDK验证问题） - 关键修复
pre_build_error_check() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 前置错误检查（修复23.05 SDK验证）==="
    
    local error_count=0
    local warning_count=0
    
    # 显示当前环境变量
    log "当前环境变量:"
    log "  SELECTED_BRANCH: $SELECTED_BRANCH"
    log "  TARGET: $TARGET"
    log "  SUBTARGET: $SUBTARGET"
    log "  DEVICE: $DEVICE"
    log "  CONFIG_MODE: $CONFIG_MODE"
    log "  COMPILER_DIR: $COMPILER_DIR"
    log "  DEVICE_NAME: $DEVICE_NAME"
    log "  PLATFORM: $PLATFORM"
    log "  SOURCE_REPO: $SOURCE_REPO"
    
    # 1. 检查配置文件
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        error_count=$((error_count + 1))
    else
        log "✅ .config 文件存在"
    fi
    
    # 2. 检查feeds
    if [ ! -d "feeds" ]; then
        log "❌ 错误: feeds 目录不存在"
        error_count=$((error_count + 1))
    else
        log "✅ feeds 目录存在"
    fi
    
    # 3. 检查依赖包
    if [ ! -d "dl" ]; then
        log "⚠️ 警告: dl 目录不存在，可能需要下载依赖"
        warning_count=$((warning_count + 1))
    else
        local dl_count=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
        log "✅ 依赖包数量: $dl_count 个"
    fi
    
    # 4. 检查编译器状态
    if [ -d "staging_dir" ]; then
        local compiler_count=$(find staging_dir -maxdepth 1 -type d -name "compiler-*" 2>/dev/null | wc -l)
        if [ $compiler_count -eq 0 ]; then
            log "ℹ️ 未找到已构建的编译器"
            log "📌 已下载SDK编译器，无需自动构建"
        else
            log "✅ 已检测到编译器: $compiler_count 个"
        fi
    else
        log "ℹ️ staging_dir目录不存在"
        log "📌 将使用下载的SDK编译器进行构建"
    fi
    
    # 5. 检查关键文件
    local critical_files=("Makefile" "rules.mk" "Config.in" "feeds.conf.default")
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 关键文件存在: $file"
        else
            log "❌ 错误: 关键文件不存在: $file"
            error_count=$((error_count + 1))
        fi
    done
    
    # 6. 检查磁盘空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log "磁盘可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 10 ]; then
        log "❌ 错误: 磁盘空间不足 (需要至少10G，当前${available_gb}G)"
        error_count=$((error_count + 1))
    elif [ $available_gb -lt 20 ]; then
        log "⚠️ 警告: 磁盘空间较低 (建议至少20G，当前${available_gb}G)"
        warning_count=$((warning_count + 1))
    else
        log "✅ 编译前空间充足"
    fi
    
    # 7. 检查内存
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    log "系统内存: ${total_mem}MB"
    
    if [ $total_mem -lt 1024 ]; then
        log "⚠️ 警告: 内存较低 (建议至少1GB)"
        warning_count=$((warning_count + 1))
    fi
    
    # 8. 检查预构建编译器文件 - 关键修复：简化23.05验证逻辑
    log "🔧 检查预构建编译器文件..."
    
    # 简化验证逻辑，只做基本检查
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ 预构建编译器目录存在: $COMPILER_DIR"
        log "📊 目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo '未知')"
        
        # 放宽检查：只需要有编译器文件，不要求特定目录结构，排除虚假编译器
        local gcc_files=$(find "$COMPILER_DIR" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | wc -l)
        
        if [ $gcc_files -gt 0 ]; then
            log "✅ 找到 $gcc_files 个GCC编译器文件"
            
            # 显示第一个GCC的版本信息
            local first_gcc=$(find "$COMPILER_DIR" -type f -executable \
              -name "*gcc" \
              ! -name "*gcc-ar" \
              ! -name "*gcc-ranlib" \
              ! -name "*gcc-nm" \
              ! -path "*dummy-tools*" \
              ! -path "*scripts*" \
              2>/dev/null | head -1)
            
            if [ -n "$first_gcc" ]; then
                log "🔧 第一个GCC版本: $("$first_gcc" --version 2>&1 | head -1)"
                
                # 对于23.05 SDK的特殊处理
                if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
                    local sdk_version=$("$first_gcc" --version 2>&1 | head -1)
                    if echo "$sdk_version" | grep -qi "12.3.0"; then
                        log "🎯 确认是OpenWrt 23.05 SDK GCC 12.3.0"
                    elif echo "$sdk_version" | grep -qi "dummy-tools"; then
                        log "⚠️ 检测到虚假的dummy-tools编译器，继续查找..."
                        # 查找其他GCC
                        local real_gcc=$(find "$COMPILER_DIR" -type f -executable \
                          -name "*gcc" \
                          ! -name "*gcc-ar" \
                          ! -name "*gcc-ranlib" \
                          ! -name "*gcc-nm" \
                          ! -path "*dummy-tools*" \
                          ! -path "*scripts*" \
                          ! -path "$(dirname "$first_gcc")" \
                          2>/dev/null | head -1)
                        
                        if [ -n "$real_gcc" ]; then
                            log "✅ 找到真正的GCC: $(basename "$real_gcc")"
                            log "🔧 版本: $("$real_gcc" --version 2>&1 | head -1)"
                        fi
                    else
                        log "⚠️ 23.05 SDK GCC版本不是预期的12.3.0"
                        log "💡 可能不是官方的23.05 SDK，但可以继续尝试"
                    fi
                fi
            fi
        else
            log "⚠️ 警告: 预构建编译器目录中未找到真正的GCC编译器"
            warning_count=$((warning_count + 1))
            
            # 检查是否有工具链工具
            local toolchain_tools=$(find "$COMPILER_DIR" -type f -executable -name "*gcc*" \
              ! -path "*dummy-tools*" \
              ! -path "*scripts*" \
              2>/dev/null | wc -l)
            if [ $toolchain_tools -gt 0 ]; then
                log "📊 找到 $toolchain_tools 个工具链工具"
                log "💡 有工具链工具但没有真正的GCC编译器"
            fi
        fi
    else
        log "ℹ️ 未设置预构建编译器目录或目录不存在"
        log "💡 将使用OpenWrt自动构建的编译器"
    fi
    
    # 9. 检查编译器调用状态（使用增强版）
    check_compiler_invocation
    
    # 总结
    if [ $error_count -eq 0 ]; then
        if [ $warning_count -eq 0 ]; then
            log "✅ 前置检查通过，可以开始编译"
        else
            log "⚠️ 前置检查通过，但有 $warning_count 个警告，建议修复"
        fi
        return 0
    else
        log "❌ 前置检查发现 $error_count 个错误，$warning_count 个警告，请修复后再编译"
        return 1
    fi
}

setup_environment() {
    log "=== 安装编译依赖包 ==="
    sudo apt-get update || handle_error "apt-get update失败"
    
    # 基础编译工具
    local base_packages=(
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip
        zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath
        libpython3-dev python3 python3-dev python3-pip python3-setuptools
        python3-yaml xsltproc zip subversion ninja-build automake autoconf
        libtool pkg-config help2man texinfo aria2 liblz4-dev zstd
        libcurl4-openssl-dev groff texlive texinfo cmake
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

# 初始化构建环境 - 使用设备支持脚本
initialize_build_env() {
    local device_name=$1
    local version_selection=$2
    local config_mode=$3
    local source_repo=${4:-"immortalwrt"}  # 添加第四个参数，默认immortalwrt
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 版本选择 ==="
    log "源代码仓库: $source_repo"
    
    # 根据仓库选择不同的URL
    case "$source_repo" in
        "immortalwrt")
            SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
            ;;
        "openwrt-official")
            SELECTED_REPO_URL="https://github.com/openwrt/openwrt.git"
            ;;
        "lede")
            SELECTED_REPO_URL="https://github.com/coolsnowwolf/lede.git"
            ;;
        "openwrt-cc")
            SELECTED_REPO_URL="https://github.com/project-openwrt/openwrt.git"
            ;;
        *)
            SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
            source_repo="immortalwrt"
            ;;
    esac
    
    # 根据版本选择分支
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_BRANCH="openwrt-23.05"
    else
        SELECTED_BRANCH="openwrt-21.02"
    fi
    
    # 对于特定仓库的分支调整
    if [ "$source_repo" = "lede" ]; then
        SELECTED_BRANCH="master"  # LEDE通常使用master分支
    fi
    
    # 设置SOURCE_REPO环境变量
    SOURCE_REPO="$source_repo"
    
    log "✅ 版本选择完成: $SELECTED_BRANCH (仓库: $source_repo)"
    
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
    DEVICE_NAME="$device_name"
    
    # 加载设备支持脚本
    if load_device_support; then
        local device_config=$(get_device_config "$device_name")
        TARGET=$(echo $device_config | awk '{print $1}')
        SUBTARGET=$(echo $device_config | awk '{print $2}')
        DEVICE=$(echo $device_config | awk '{print $3}')
        PLATFORM=$(echo $device_config | awk '{print $4}')
        
        local device_desc=$(get_device_description "$device_name")
        log "🔧 设备: $device_desc"
        log "目标: $TARGET"
        log "子目标: $SUBTARGET"
        log "设备: $DEVICE"
        log "平台: $PLATFORM"
    else
        # 默认配置（兼容旧版）
        case "$device_name" in
            "ac42u"|"acrh17")
                TARGET="ipq40xx"
                SUBTARGET="generic"
                DEVICE="asus_rt-ac42u"
                PLATFORM="ipq40xx"
                ;;
            "mi_router_4a_gigabit"|"r4ag")
                TARGET="ramips"
                SUBTARGET="mt76x8"
                DEVICE="xiaomi_mi-router-4a-gigabit"
                PLATFORM="ramips"
                ;;
            "mi_router_3g"|"r3g")
                TARGET="ramips"
                SUBTARGET="mt7621"
                DEVICE="xiaomi_mi-router-3g"
                PLATFORM="ramips"
                ;;
            *)
                TARGET="ipq40xx"
                SUBTARGET="generic"
                DEVICE="$device_name"
                PLATFORM="generic"
                ;;
        esac
        log "🔧 检测到设备: $device_name"
        log "目标: $TARGET"
        log "子目标: $SUBTARGET"
        log "设备: $DEVICE"
        log "平台: $PLATFORM"
    fi
    
    CONFIG_MODE="$config_mode"
    
    save_env
    
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    echo "DEVICE_NAME=$DEVICE_NAME" >> $GITHUB_ENV
    echo "PLATFORM=$PLATFORM" >> $GITHUB_ENV
    echo "SOURCE_REPO=$SOURCE_REPO" >> $GITHUB_ENV
    
    log "✅ 构建环境初始化完成"
}

# 初始化编译器环境（下载OpenWrt官方SDK）- 修复版
initialize_compiler_env() {
    local device_name="$1"
    log "=== 初始化编译器环境（下载OpenWrt官方SDK）- 修复版 ==="
    
    # 首先加载环境变量 - 修复检查逻辑
    log "🔍 检查环境文件..."
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从 $BUILD_DIR/build_env.sh 加载环境变量"
        
        # 显示关键环境变量
        log "📋 当前环境变量:"
        log "  SELECTED_BRANCH: $SELECTED_BRANCH"
        log "  TARGET: $TARGET"
        log "  SUBTARGET: $SUBTARGET"
        log "  DEVICE: $DEVICE"
        log "  CONFIG_MODE: $CONFIG_MODE"
        log "  REPO_ROOT: $REPO_ROOT"
        log "  COMPILER_DIR: $COMPILER_DIR"
        log "  DEVICE_NAME: $DEVICE_NAME"
        log "  PLATFORM: $PLATFORM"
        log "  SOURCE_REPO: $SOURCE_REPO"
    else
        log "⚠️ 环境文件不存在: $BUILD_DIR/build_env.sh"
        log "💡 环境文件应该在步骤6.3中创建，但未找到"
        
        # 设置默认值
        if [ -z "$SELECTED_BRANCH" ]; then
            SELECTED_BRANCH="openwrt-21.02"
            log "⚠️ SELECTED_BRANCH未设置，使用默认值: $SELECTED_BRANCH"
        fi
        
        if [ -z "$SOURCE_REPO" ]; then
            SOURCE_REPO="immortalwrt"
            log "⚠️ SOURCE_REPO未设置，使用默认值: $SOURCE_REPO"
        fi
        
        if [ -z "$TARGET" ]; then
            # 使用设备支持脚本获取配置
            if load_device_support; then
                local device_config=$(get_device_config "$device_name")
                TARGET=$(echo $device_config | awk '{print $1}')
                SUBTARGET=$(echo $device_config | awk '{print $2}')
                DEVICE=$(echo $device_config | awk '{print $3}')
                PLATFORM=$(echo $device_config | awk '{print $4}')
                log "⚠️ 平台变量未设置，从设备支持脚本获取: TARGET=$TARGET, SUBTARGET=$SUBTARGET, DEVICE=$DEVICE, PLATFORM=$PLATFORM"
            else
                # 默认配置
                TARGET="ipq40xx"
                SUBTARGET="generic"
                DEVICE="$device_name"
                PLATFORM="generic"
                log "⚠️ 平台变量未设置，使用默认值: TARGET=$TARGET, SUBTARGET=$SUBTARGET, DEVICE=$DEVICE"
            fi
        fi
        
        if [ -z "$CONFIG_MODE" ]; then
            CONFIG_MODE="normal"
            log "⚠️ CONFIG_MODE未设置，使用默认值: $CONFIG_MODE"
        fi
        
        if [ -z "$DEVICE_NAME" ]; then
            DEVICE_NAME="$device_name"
            log "⚠️ DEVICE_NAME未设置，使用: $DEVICE_NAME"
        fi
        
        if [ -z "$PLATFORM" ]; then
            PLATFORM="generic"
            log "⚠️ PLATFORM未设置，使用默认值: $PLATFORM"
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
        local gcc_files=$(find "$COMPILER_DIR" -type f -executable \
          -name "*gcc" \
          ! -name "*gcc-ar" \
          ! -name "*gcc-ranlib" \
          ! -name "*gcc-nm" \
          ! -path "*dummy-tools*" \
          ! -path "*scripts*" \
          2>/dev/null | head -3)
        
        if [ -n "$gcc_files" ]; then
            log "✅ 确认编译器目录包含真正的GCC"
            local first_gcc=$(echo "$gcc_files" | head -1)
            log "  🎯 GCC文件: $(basename "$first_gcc")"
            log "  🔧 GCC版本: $("$first_gcc" --version 2>&1 | head -1)"
            
            # 保存到环境文件
            save_env
            
            # 验证编译器
            verify_compiler_files
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
    log "平台类型: $PLATFORM"
    log "源代码仓库: $SOURCE_REPO"
    
    # 简化版本字符串（从openwrt-23.05转为23.05）
    local version_for_sdk=""
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        version_for_sdk="23.05"
    elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
        version_for_sdk="21.02"
    else
        # 尝试提取版本号
        version_for_sdk=$(echo "$SELECTED_BRANCH" | grep -o "[0-9][0-9]\.[0-9][0-9]" || echo "21.02")
        log "⚠️ 无法识别的版本分支，尝试使用: $version_for_sdk"
    fi
    
    log "📌 SDK版本: $version_for_sdk"
    log "📌 目标平台: $TARGET/$SUBTARGET"
    
    # 详细显示SDK下载信息
    log "🔍 SDK下载详细信息:"
    log "  设备: $device_name"
    log "  OpenWrt版本: $SELECTED_BRANCH"
    log "  SDK版本: $version_for_sdk"
    log "  目标: $TARGET"
    log "  子目标: $SUBTARGET"
    log "  平台: $PLATFORM"
    log "  源代码仓库: $SOURCE_REPO"
    
    # 下载OpenWrt官方SDK
    log "🚀 开始下载OpenWrt官方SDK..."
    if download_openwrt_sdk "$TARGET" "$subtarget" "$version_for_sdk"; then
        log "🎉 OpenWrt SDK下载并设置成功"
        log "📌 编译器目录: $COMPILER_DIR"
        
        # 显示SDK目录信息
        if [ -d "$COMPILER_DIR" ]; then
            log "📊 SDK目录信息:"
            log "  目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo '未知')"
            log "  文件数量: $(find "$COMPILER_DIR" -type f 2>/dev/null | wc -l)"
            
            # 查找GCC编译器，排除虚假编译器
            local gcc_file=$(find "$COMPILER_DIR" -type f -executable \
              -name "*gcc" \
              ! -name "*gcc-ar" \
              ! -name "*gcc-ranlib" \
              ! -name "*gcc-nm" \
              ! -path "*dummy-tools*" \
              ! -path "*scripts*" \
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
        log "💡 将使用OpenWrt自动构建的编译器作为后备"
        
        # 设置空的编译器目录
        export COMPILER_DIR=""
        save_env
        
        # 不返回错误，继续执行
        return 0
    fi
}

add_turboacc_support() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 添加 TurboACC 支持 ==="
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "🔧 为正常模式添加 TurboACC 支持"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log "🔧 为 23.05 添加 TurboACC 支持"
            echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
            log "✅ TurboACC feed 添加完成"
        else
            log "ℹ️ 21.02 版本已内置 TurboACC，无需额外添加"
        fi
    else
        log "ℹ️ 基础模式不添加 TurboACC 支持"
    fi
}

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
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
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

# 智能配置生成系统（模板化版）
generate_config() {
    local extra_packages=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 智能配置生成系统（模板化版）==="
    log "设备: $DEVICE_NAME"
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "平台: $PLATFORM"
    log "配置模式: $CONFIG_MODE"
    log "源代码仓库: $SOURCE_REPO"
    
    rm -f .config .config.old
    
    # 1. 基本目标配置
    echo "# ============================================" > .config
    echo "# 目标平台配置" >> .config
    echo "# ============================================" >> .config
    echo "CONFIG_TARGET_${TARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    
    # 2. 加载基础配置模板
    log "📋 加载基础配置模板..."
    if ! load_config_template "base"; then
        # 如果模板不存在，使用内置配置
        log "⚠️ 基础配置模板不存在，使用内置配置"
        echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
        echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
        echo "CONFIG_PACKAGE_busybox=y" >> .config
        echo "CONFIG_PACKAGE_base-files=y" >> .config
        echo "CONFIG_PACKAGE_dropbear=y" >> .config
    fi
    
    # 3. 加载模式配置
    log "⚙️ 加载配置模式: $CONFIG_MODE"
    if [ "$CONFIG_MODE" = "normal" ]; then
        if load_config_template "normal"; then
            log "✅ 加载正常模式配置"
        else
            log "⚠️ 正常模式模板不存在，使用基础配置"
        fi
    else
        log "🔧 基础模式，不加载额外插件"
        echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> .config
    fi
    
    # 4. 加载USB配置
    log "🔌 加载USB配置..."
    load_usb_config "$PLATFORM" "$SELECTED_BRANCH"
    
    # 5. 加载设备特殊配置（如果有）
    log "🎯 检查设备特殊配置..."
    # 修复：设备配置文件在 firmware-config/config/ 目录下
    local device_config_file="$SUPPORT_DIR/config/${DEVICE_NAME}.config"
    if [ -f "$device_config_file" ]; then
        log "✅ 加载设备特殊配置: $DEVICE_NAME"
        echo "" >> .config
        echo "# ============================================" >> .config
        echo "# 设备特殊配置: $DEVICE_NAME" >> .config
        echo "# ============================================" >> .config
        cat "$device_config_file" >> .config
    else
        log "ℹ️ 未找到设备特殊配置: $DEVICE_NAME"
    fi
    
    # 6. 处理额外插件
    if [ -n "$extra_packages" ]; then
        log "🔧 处理额外安装插件: $extra_packages"
        echo "" >> .config
        echo "# ============================================" >> .config
        echo "# 额外插件配置" >> .config
        echo "# ============================================" >> .config
        
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
    
    # 7. 添加版本特定的配置
    echo "" >> .config
    echo "# ============================================" >> .config
    echo "# 版本特定配置: $SELECTED_BRANCH" >> .config
    echo "# ============================================" >> .config
    
    if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
        # 21.02版本的语言包
        if [ "$CONFIG_MODE" = "normal" ]; then
            echo "CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-arpbind-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-cpulimit-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-hd-idle-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-accesscontrol-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y" >> .config
        fi
    fi
    
    log "✅ 智能配置生成完成"
}

verify_usb_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 详细验证USB和存储配置 ==="
    
    echo "1. 🟢 USB核心模块:"
    grep "CONFIG_PACKAGE_kmod-usb-core" .config | grep "=y" && echo "✅ USB核心" || echo "❌ 缺少USB核心"
    
    echo "2. 🟢 USB控制器:"
    grep -E "CONFIG_PACKAGE_kmod-usb2|CONFIG_PACKAGE_kmod-usb3|CONFIG_PACKAGE_kmod-usb-ehci|CONFIG_PACKAGE_kmod-usb-ohci|CONFIG_PACKAGE_kmod-usb-xhci-hcd" .config | grep "=y" || echo "❌ 缺少USB控制器"
    
    echo "3. 🚨 USB 3.0关键驱动:"
    echo "  - kmod-usb-xhci-hcd:" $(grep "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb3:" $(grep "CONFIG_PACKAGE_kmod-usb3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    echo "4. 🚨 平台专用USB控制器:"
    if [ "$PLATFORM" = "ipq40xx" ]; then
        echo "  🔧 检测到高通IPQ40xx平台，检查专用驱动:"
        echo "  - kmod-usb-dwc3-qcom:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    elif [ "$PLATFORM" = "ramips" ]; then
        echo "  🔧 检测到雷凌平台，检查专用驱动:"
        echo "  - kmod-usb-xhci-mtk:" $(grep "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    elif [ "$PLATFORM" = "ath79" ]; then
        echo "  🔧 检测到ath79平台，检查专用驱动:"
        echo "  - kmod-usb2-ath79:" $(grep "CONFIG_PACKAGE_kmod-usb2-ath79=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    fi
    
    echo "5. 🟢 USB存储:"
    grep "CONFIG_PACKAGE_kmod-usb-storage" .config | grep "=y" && echo "✅ USB存储" || echo "❌ 缺少USB存储"
    
    echo "6. 🟢 SCSI支持:"
    grep -E "CONFIG_PACKAGE_kmod-scsi-core|CONFIG_PACKAGE_kmod-scsi-generic" .config | grep "=y" && echo "✅ SCSI支持" || echo "❌ 缺少SCSI支持"
    
    echo "7. 🟢 文件系统支持:"
    echo "  - NTFS3:" $(grep "CONFIG_PACKAGE_kmod-fs-ntfs3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - ext4:" $(grep "CONFIG_PACKAGE_kmod-fs-ext4=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - vfat:" $(grep "CONFIG_PACKAGE_kmod-fs-vfat=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    log "=== 🚨 USB配置验证完成 ==="
    
    # 输出总结
    log "📊 USB配置状态总结:"
    local usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-ehci" "kmod-usb-ohci" "kmod-usb-xhci-hcd" "kmod-usb-storage")
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
    )
    
    # 根据平台添加专用驱动
    if [ "$PLATFORM" = "ipq40xx" ]; then
        required_drivers+=("kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3")
    elif [ "$PLATFORM" = "ramips" ]; then
        required_drivers+=("kmod-usb-xhci-mtk")
    elif [ "$PLATFORM" = "ath79" ]; then
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

# ============ 新增：配置语法验证函数 ============
validate_config_syntax() {
    log "=== 🔍 验证.config文件语法 ==="
    
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        return 1
    fi
    
    local error_count=0
    local warning_count=0
    
    log "1. 检查文件基本信息..."
    local config_size=$(ls -lh ".config" | awk '{print $5}')
    local config_lines=$(wc -l < ".config")
    log "  文件大小: $config_size"
    log "  行数: $config_lines"
    
    log "2. 检查空行和注释..."
    local blank_lines=$(grep -c "^[[:space:]]*$" .config)
    if [ $blank_lines -gt 0 ]; then
        log "  ⚠️ 发现 $blank_lines 个空行，但可以继续"
        warning_count=$((warning_count + 1))
    fi
    
    log "3. 检查无效配置（包含空格）..."
    local invalid_lines=$(grep -n "CONFIG_[^=]*[[:space:]]" .config)
    if [ -n "$invalid_lines" ]; then
        log "❌ 发现无效配置行（配置名包含空格）:"
        echo "$invalid_lines" | head -5
        error_count=$((error_count + 1))
    fi
    
    log "4. 检查重复配置项..."
    local duplicates=$(awk -F'=' '/^CONFIG_/ {print $1}' .config | sort | uniq -d)
    if [ -n "$duplicates" ]; then
        log "❌ 发现重复配置项:"
        echo "$duplicates"
        error_count=$((error_count + 1))
        
        # 修复重复配置
        log "🔄 正在修复重复配置..."
        awk -F'=' '!seen[$1]++' .config > .config.tmp && mv .config.tmp .config
        log "✅ 重复配置已修复"
    fi
    
    log "5. 检查配置冲突（同一配置既有=y又有is not set）..."
    local config_names=$(awk -F'[ =]' '/^CONFIG_/ {print $2}' .config | sort | uniq)
    local conflict_count=0
    
    for config in $config_names; do
        local enabled_count=$(grep -c "^CONFIG_${config}=y" .config)
        local disabled_count=$(grep -c "^# CONFIG_${config} is not set" .config)
        
        if [ $enabled_count -gt 0 ] && [ $disabled_count -gt 0 ]; then
            log "❌ 配置冲突: $config 同时启用和禁用"
            conflict_count=$((conflict_count + 1))
            error_count=$((error_count + 1))
            
            # 修复冲突：保留启用的配置，删除禁用的配置
            log "  🔧 修复冲突: 保留 CONFIG_${config}=y，删除禁用的配置"
            sed -i "/^# CONFIG_${config} is not set/d" .config
        fi
    done
    
    log "6. 检查配置语法正确性..."
    local syntax_errors=0
    while IFS= read -r line; do
        # 跳过空行和注释
        if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        
        # 检查配置行格式
        if [[ "$line" =~ ^CONFIG_[A-Za-z0-9_]+= ]]; then
            # 启用配置，格式正确
            continue
        elif [[ "$line" =~ ^#\ CONFIG_[A-Za-z0-9_]+\ is\ not\ set ]]; then
            # 禁用配置，格式正确
            continue
        else
            log "  ⚠️ 语法警告: 非标准配置行: $line"
            warning_count=$((warning_count + 1))
        fi
    done < .config
    
    # 总结
    if [ $error_count -eq 0 ]; then
        if [ $warning_count -eq 0 ]; then
            log "✅ 配置语法验证通过，无错误和警告"
        else
            log "⚠️ 配置语法验证通过，但有 $warning_count 个警告"
        fi
        return 0
    else
        log "❌ 配置语法验证发现 $error_count 个错误，$warning_count 个警告"
        return 1
    fi
}

# ============ 修复：apply_config 函数 ============
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
    
    # 先备份原始配置文件
    if [ -f ".config" ]; then
        cp ".config" ".config.backup.$(date +%Y%m%d_%H%M%S)"
        log "✅ 已备份原始配置文件"
    fi
    
    # 步骤1: 验证配置语法
    log "🔍 步骤1: 验证配置语法..."
    if validate_config_syntax; then
        log "✅ 配置语法验证通过"
    else
        log "⚠️ 配置语法有问题，尝试自动修复..."
        # 尝试修复常见问题
        make defconfig 2>&1 | tee /tmp/defconfig_fix.log
        if [ $? -eq 0 ]; then
            log "✅ defconfig 修复成功"
        else
            log "❌ defconfig 修复失败"
            log "defconfig 错误日志:"
            cat /tmp/defconfig_fix.log
        fi
    fi
    
    # 步骤2: 清理重复配置和冲突配置
    log "🔧 步骤2: 清理重复和冲突配置..."
    
    # 清理重复的USB配置
    local usb_configs=(
        "kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-xhci-hcd"
        "kmod-usb-xhci-pci" "kmod-usb-xhci-plat-hcd" "kmod-usb-ohci-pci"
        "kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3"
        "kmod-usb-dwc3-of-simple" "kmod-usb-xhci-mtk" "kmod-usb2-ath79"
    )
    
    for config in "${usb_configs[@]}"; do
        # 删除重复的启用配置
        local enabled_count=$(grep -c "^CONFIG_PACKAGE_${config}=y" .config)
        if [ $enabled_count -gt 1 ]; then
            log "🔄 清理重复的启用配置: $config ($enabled_count 次)"
            awk -v cfg="CONFIG_PACKAGE_${config}=y" '$0 == cfg && !seen[cfg]++' .config > .config.tmp && mv .config.tmp .config
        fi
        
        # 删除重复的禁用配置
        local disabled_count=$(grep -c "^# CONFIG_PACKAGE_${config} is not set" .config)
        if [ $disabled_count -gt 1 ]; then
            log "🔄 清理重复的禁用配置: $config ($disabled_count 次)"
            awk -v cfg="# CONFIG_PACKAGE_${config} is not set" '$0 == cfg && !seen[cfg]++' .config > .config.tmp && mv .config.tmp .config
        fi
        
        # 解决冲突：如果既有启用又有禁用，保留启用
        if [ $enabled_count -gt 0 ] && [ $disabled_count -gt 0 ]; then
            log "🔄 解决配置冲突: $config (保留启用，删除禁用)"
            sed -i "/^# CONFIG_PACKAGE_${config} is not set/d" .config
        fi
    done
    
    # 步骤3: 运行 make defconfig (使用改进的错误处理)
    log "🔄 步骤3: 运行 make defconfig..."
    
    # 清除旧的defconfig日志
    rm -f /tmp/defconfig.log
    
    # 运行defconfig并捕获详细日志
    if ! make defconfig 2>&1 | tee /tmp/defconfig.log; then
        log "❌ make defconfig 失败"
        log "详细错误信息:"
        cat /tmp/defconfig.log
        
        # 尝试分析错误原因
        if grep -q "invalid option" /tmp/defconfig.log; then
            log "💡 错误分析: 发现无效配置选项"
            log "🔧 尝试修复: 删除无效配置后重试..."
            
            # 提取无效配置
            grep "invalid option" /tmp/defconfig.log | while read line; do
                invalid_config=$(echo "$line" | grep -o "CONFIG_[A-Za-z0-9_]*")
                if [ -n "$invalid_config" ]; then
                    log "  删除无效配置: $invalid_config"
                    sed -i "/^${invalid_config}=/d" .config
                    sed -i "/^# ${invalid_config} is not set/d" .config
                fi
            done
            
            # 再次尝试defconfig
            log "🔄 重新运行 make defconfig..."
            if make defconfig 2>&1 | tee /tmp/defconfig_retry.log; then
                log "✅ defconfig 修复成功"
            else
                log "❌ defconfig 仍然失败"
                log "第二次尝试的错误日志:"
                cat /tmp/defconfig_retry.log
                handle_error "应用配置失败"
            fi
        else
            handle_error "应用配置失败"
        fi
    else
        log "✅ make defconfig 成功"
    fi
    
    # 步骤4: 强制启用关键USB驱动（防止defconfig删除）
    log "🔧 步骤4: 确保关键USB驱动被启用..."
    
    # 定义关键USB驱动
    local critical_usb_drivers=(
        "CONFIG_PACKAGE_kmod-usb-core=y"
        "CONFIG_PACKAGE_kmod-usb2=y"
        "CONFIG_PACKAGE_kmod-usb3=y"
        "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y"
        "CONFIG_PACKAGE_kmod-usb-xhci-pci=y"
        "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y"
        "CONFIG_PACKAGE_kmod-usb-ohci-pci=y"
        "CONFIG_PACKAGE_kmod-usb-dwc3=y"
        "CONFIG_PACKAGE_kmod-usb-storage=y"
        "CONFIG_PACKAGE_kmod-scsi-core=y"
    )
    
    # 平台专用驱动
    if [ "$PLATFORM" = "ipq40xx" ]; then
        critical_usb_drivers+=(
            "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y"
            "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y"
            "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y"
        )
    elif [ "$PLATFORM" = "ramips" ]; then
        critical_usb_drivers+=(
            "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y"
        )
    elif [ "$PLATFORM" = "ath79" ]; then
        critical_usb_drivers+=(
            "CONFIG_PACKAGE_kmod-usb2-ath79=y"
        )
    fi
    
    # 添加或确保关键驱动
    for driver in "${critical_usb_drivers[@]}"; do
        local config_name=$(echo "$driver" | cut -d'=' -f1)
        if ! grep -q "^${config_name}=y" .config; then
            # 删除可能的禁用配置
            sed -i "/^# ${config_name} is not set/d" .config
            # 添加启用配置
            echo "$driver" >> .config
            log "✅ 已添加: $config_name"
        else
            log "ℹ️ 已存在: $config_name"
        fi
    done
    
    # 步骤5: 再次验证配置
    log "🔍 步骤5: 最终配置验证..."
    validate_config_syntax
    
    # 步骤6: 运行defconfig确保配置一致
    log "🔄 步骤6: 最终运行 make defconfig..."
    if make defconfig 2>&1 | tee /tmp/final_defconfig.log; then
        log "✅ 最终 defconfig 成功"
    else
        log "⚠️ 最终 defconfig 有警告，但继续执行"
        cat /tmp/final_defconfig.log | tail -20
    fi
    
    # 步骤7: 显示最终配置状态
    log "📊 步骤7: 显示最终配置状态..."
    local final_enabled=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local final_disabled=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    log "✅ 最终状态: 已启用 $final_enabled 个, 已禁用 $final_disabled 个"
    
    # 显示关键配置状态
    log "🔧 关键配置状态:"
    echo "1. USB核心: $(grep -q "^CONFIG_PACKAGE_kmod-usb-core=y" .config && echo "✅" || echo "❌")"
    echo "2. USB 3.0: $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo "✅" || echo "❌")"
    echo "3. USB存储: $(grep -q "^CONFIG_PACKAGE_kmod-usb-storage=y" .config && echo "✅" || echo "❌")"
    
    # 根据平台显示专用驱动
    if [ "$PLATFORM" = "ipq40xx" ]; then
        echo "4. 高通USB: $(grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo "✅" || echo "❌")"
    elif [ "$PLATFORM" = "ramips" ]; then
        echo "4. 雷凌USB: $(grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config && echo "✅" || echo "❌")"
    elif [ "$PLATFORM" = "ath79" ]; then
        echo "4. ath79 USB: $(grep -q "^CONFIG_PACKAGE_kmod-usb2-ath79=y" .config && echo "✅" || echo "❌")"
    fi
    
    log "✅ 配置应用完成"
    log "最终配置文件: .config"
    log "最终配置大小: $(ls -lh .config | awk '{print $5}')"
}

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
    log "源代码仓库: $SOURCE_REPO"
    
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
    
    # 创建第一次开机运行的安装脚本（增强版）- 无SSH测试
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
    log "  平台: $PLATFORM"
    log "  源代码仓库: $SOURCE_REPO"
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
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
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
        local prebuilt_gcc=$(find "$COMPILER_DIR" -type f -executable \
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
            local version=$("$prebuilt_gcc" --version 2>&1 | head -1)
            log "     GCC版本: $version"
            
            # 检查版本兼容性
            local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
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
            local toolchain_tools=$(find "$COMPILER_DIR" -type f -executable -name "*gcc*" \
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
            local firmware_count=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
            log "✅ 生成固件文件: $firmware_count 个"
            
            # 显示固件文件
            find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
                log "固件: $file ($(du -h "$file" | cut -f1))"
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
            local error_count=$(grep -c "Error [0-9]|error:" build.log)
            local warning_count=$(grep -c "Warning\|warning:" build.log)
            
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
                    find staging_dir -type f -executable \
                      -name "*gcc" \
                      ! -name "*gcc-ar" \
                      ! -name "*gcc-ranlib" \
                      ! -name "*gcc-nm" \
                      ! -path "*dummy-tools*" \
                      ! -path "*scripts*" \
                      2>/dev/null | head -10
                fi
            fi
            
            if grep -q "$COMPILER_DIR" build.log | grep -i "error\|failed" 2>/dev/null; then
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

# 编译后空间检查 - 修复磁盘空间检查函数
post_build_space_check() {
    log "=== 编译后空间检查 ==="
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 构建目录空间
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    # 固件文件大小
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        local firmware_size=$(find "$BUILD_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo "固件文件总大小: $firmware_size"
    fi
    
    # 检查可用空间 - 修复：使用正确的df选项
    local available_space=$(df /mnt --output=avail | tail -1 | awk '{print $1}')
    local available_gb=$((available_space / 1024 / 1024))
    log "/mnt 可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        log "⚠️ 警告: 磁盘空间较低，建议清理"
    else
        log "✅ 磁盘空间充足"
    fi
    
    log "✅ 空间检查完成"
}

check_firmware_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 固件文件检查 ==="
    
    if [ -d "bin/targets" ]; then
        log "✅ 固件目录存在"
        
        # 统计固件文件
        local firmware_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        local all_files=$(find bin/targets -type f 2>/dev/null | wc -l)
        
        log "固件文件: $firmware_files 个"
        log "所有文件: $all_files 个"
        
        # 显示固件文件详情
        echo "=== 生成的固件文件 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \;
        
        # 检查文件大小
        local total_size=0
        while read size; do
            total_size=$((total_size + size))
        done < <(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec stat -c%s {} \; 2>/dev/null)
        
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
        find bin/targets -maxdepth 3 -type d | sort
        
    else
        log "❌ 固件目录不存在"
        exit 1
    fi
}

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
    echo "设备名称: $DEVICE_NAME" >> "$source_info_file"
    echo "平台: $PLATFORM" >> "$source_info_file"
    echo "源代码仓库: $SOURCE_REPO" >> "$source_info_file"
    
    # 收集目录信息
    echo "" >> "$source_info_file"
    echo "=== 目录结构 ===" >> "$source_info_file"
    find . -maxdepth 2 -type d | sort >> "$source_info_file"
    
    # 收集关键文件信息
    echo "" >> "$source_info_file"
    echo "=== 关键文件 ===" >> "$source_info_file"
    local key_files=("Makefile" "feeds.conf.default" ".config" "rules.mk" "Config.in")
    for file in "${key_files[@]}"; do
        if [ -f "$file" ]; then
            echo "$file: 存在 ($(ls -lh "$file" | awk '{print $5}'))" >> "$source_info_file"
        else
            echo "$file: 不存在" >> "$source_info_file"
        fi
    done
    
    log "✅ 源代码信息已保存到: $source_info_file"
}

# 主函数
main() {
    case $1 in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$2" "$3" "$4" "$5"
            ;;
        "initialize_compiler_env")
            initialize_compiler_env "$2"
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
            generate_config "$2"
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
        "validate_config_syntax")
            validate_config_syntax
            ;;
        "build_firmware")
            build_firmware "$2"
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
            search_compiler_files "$2" "$3"
            ;;
        "universal_compiler_search")
            universal_compiler_search "$2" "$3"
            ;;
        "search_compiler_files_simple")
            search_compiler_files_simple "$2" "$3"
            ;;
        "intelligent_platform_aware_compiler_search")
            intelligent_platform_aware_compiler_search "$2" "$3" "$4"
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  initialize_compiler_env - 初始化编译器环境（下载OpenWrt官方SDK）"
            echo "  add_turboacc_support, configure_feeds, install_turboacc_packages"
            echo "  pre_build_space_check, generate_config, verify_usb_config, check_usb_drivers_integrity, apply_config"
            echo "  fix_network, download_dependencies, integrate_custom_files"
            echo "  pre_build_error_check, validate_config_syntax, build_firmware, post_build_space_check"
            echo "  check_firmware_files, cleanup, save_source_code_info, verify_compiler_files"
            echo "  check_compiler_invocation, search_compiler_files, universal_compiler_search"
            echo "  search_compiler_files_simple, intelligent_platform_aware_compiler_search"
            exit 1
            ;;
    esac
}

main "$@"
