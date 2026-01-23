#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CUSTOM_STATS_FILE="$BUILD_DIR/custom_files_stats.txt"

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

# 保存环境变量函数
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
    
    if [ -f "$CUSTOM_STATS_FILE" ]; then
        source "$CUSTOM_STATS_FILE" 2>/dev/null || true
        
        echo "export CUSTOM_IPK_COUNT=\"${CUSTOM_IPK_COUNT:-0}\"" >> $ENV_FILE
        echo "export CUSTOM_SCRIPT_COUNT=\"${CUSTOM_SCRIPT_COUNT:-0}\"" >> $ENV_FILE
        echo "export CUSTOM_CONFIG_COUNT=\"${CUSTOM_CONFIG_COUNT:-0}\"" >> $ENV_FILE
        echo "export CUSTOM_OTHER_COUNT=\"${CUSTOM_OTHER_COUNT:-0}\"" >> $ENV_FILE
        echo "export CUSTOM_CHINESE_COUNT=\"${CUSTOM_CHINESE_COUNT:-0}\"" >> $ENV_FILE
        echo "export CUSTOM_PRIORITY_SCRIPT_COUNT=\"${CUSTOM_PRIORITY_SCRIPT_COUNT:-0}\"" >> $ENV_FILE
        echo "export CUSTOM_TOTAL_FILES=\"${CUSTOM_TOTAL_FILES:-0}\"" >> $ENV_FILE
        echo "export CUSTOM_FILES_INTEGRATED=\"${CUSTOM_FILES_INTEGRATED:-false}\"" >> $ENV_FILE
    else
        echo "export CUSTOM_IPK_COUNT=\"0\"" >> $ENV_FILE
        echo "export CUSTOM_SCRIPT_COUNT=\"0\"" >> $ENV_FILE
        echo "export CUSTOM_CONFIG_COUNT=\"0\"" >> $ENV_FILE
        echo "export CUSTOM_OTHER_COUNT=\"0\"" >> $ENV_FILE
        echo "export CUSTOM_CHINESE_COUNT=\"0\"" >> $ENV_FILE
        echo "export CUSTOM_PRIORITY_SCRIPT_COUNT=\"0\"" >> $ENV_FILE
        echo "export CUSTOM_TOTAL_FILES=\"0\"" >> $ENV_FILE
        echo "export CUSTOM_FILES_INTEGRATED=\"false\"" >> $ENV_FILE
    fi
    
    if [ -n "$GITHUB_ENV" ]; then
        echo "SELECTED_REPO_URL=${SELECTED_REPO_URL}" >> $GITHUB_ENV
        echo "SELECTED_BRANCH=${SELECTED_BRANCH}" >> $GITHUB_ENV
        echo "TARGET=${TARGET}" >> $GITHUB_ENV
        echo "SUBTARGET=${SUBTARGET}" >> $GITHUB_ENV
        echo "DEVICE=${DEVICE}" >> $GITHUB_ENV
        echo "CONFIG_MODE=${CONFIG_MODE}" >> $GITHUB_ENV
        echo "COMPILER_DIR=${COMPILER_DIR}" >> $GITHUB_ENV
        
        if [ -f "$CUSTOM_STATS_FILE" ]; then
            source "$CUSTOM_STATS_FILE" 2>/dev/null || true
            echo "CUSTOM_IPK_COUNT=${CUSTOM_IPK_COUNT:-0}" >> $GITHUB_ENV
            echo "CUSTOM_SCRIPT_COUNT=${CUSTOM_SCRIPT_COUNT:-0}" >> $GITHUB_ENV
            echo "CUSTOM_CONFIG_COUNT=${CUSTOM_CONFIG_COUNT:-0}" >> $GITHUB_ENV
            echo "CUSTOM_OTHER_COUNT=${CUSTOM_OTHER_COUNT:-0}" >> $GITHUB_ENV
            echo "CUSTOM_CHINESE_COUNT=${CUSTOM_CHINESE_COUNT:-0}" >> $GITHUB_ENV
            echo "CUSTOM_PRIORITY_SCRIPT_COUNT=${CUSTOM_PRIORITY_SCRIPT_COUNT:-0}" >> $GITHUB_ENV
            echo "CUSTOM_TOTAL_FILES=${CUSTOM_TOTAL_FILES:-0}" >> $GITHUB_ENV
            echo "CUSTOM_FILES_INTEGRATED=${CUSTOM_FILES_INTEGRATED:-false}" >> $GITHUB_ENV
        else
            echo "CUSTOM_FILES_INTEGRATED=false" >> $GITHUB_ENV
        fi
    fi
    
    export SELECTED_REPO_URL="${SELECTED_REPO_URL}"
    export SELECTED_BRANCH="${SELECTED_BRANCH}"
    export TARGET="${TARGET}"
    export SUBTARGET="${SUBTARGET}"
    export DEVICE="${DEVICE}"
    export CONFIG_MODE="${CONFIG_MODE}"
    export REPO_ROOT="${REPO_ROOT}"
    export COMPILER_DIR="${COMPILER_DIR}"
    
    if [ -f "$CUSTOM_STATS_FILE" ]; then
        source "$CUSTOM_STATS_FILE" 2>/dev/null || true
        export CUSTOM_IPK_COUNT="${CUSTOM_IPK_COUNT:-0}"
        export CUSTOM_SCRIPT_COUNT="${CUSTOM_SCRIPT_COUNT:-0}"
        export CUSTOM_CONFIG_COUNT="${CUSTOM_CONFIG_COUNT:-0}"
        export CUSTOM_OTHER_COUNT="${CUSTOM_OTHER_COUNT:-0}"
        export CUSTOM_CHINESE_COUNT="${CUSTOM_CHINESE_COUNT:-0}"
        export CUSTOM_PRIORITY_SCRIPT_COUNT="${CUSTOM_PRIORITY_SCRIPT_COUNT:-0}"
        export CUSTOM_TOTAL_FILES="${CUSTOM_TOTAL_FILES:-0}"
        export CUSTOM_FILES_INTEGRATED="${CUSTOM_FILES_INTEGRATED:-false}"
    else
        export CUSTOM_IPK_COUNT="0"
        export CUSTOM_SCRIPT_COUNT="0"
        export CUSTOM_CONFIG_COUNT="0"
        export CUSTOM_OTHER_COUNT="0"
        export CUSTOM_CHINESE_COUNT="0"
        export CUSTOM_PRIORITY_SCRIPT_COUNT="0"
        export CUSTOM_TOTAL_FILES="0"
        export CUSTOM_FILES_INTEGRATED="false"
    fi
    
    chmod +x $ENV_FILE
    log "✅ 环境变量已保存到: $ENV_FILE"
    
    if [ -f "$CUSTOM_STATS_FILE" ] && [ "$1" = "with_stats" ]; then
        log "📊 当前环境中的自定义文件统计: IPK=${CUSTOM_IPK_COUNT}, 脚本=${CUSTOM_SCRIPT_COUNT}, 总数=${CUSTOM_TOTAL_FILES}"
    fi
}

save_custom_stats() {
    cat > "$CUSTOM_STATS_FILE" << EOF
CUSTOM_IPK_COUNT="$integrate_ipk_count"
CUSTOM_SCRIPT_COUNT="$integrate_script_count"
CUSTOM_CONFIG_COUNT="$integrate_config_count"
CUSTOM_OTHER_COUNT="$integrate_other_count"
CUSTOM_CHINESE_COUNT="$integrate_chinese_count"
CUSTOM_PRIORITY_SCRIPT_COUNT="$integrate_priority_script_count"
CUSTOM_TOTAL_FILES="$integrate_total_files"
CUSTOM_FILES_INTEGRATED="true"
EOF
    
    log "✅ 自定义文件统计信息已保存到: $CUSTOM_STATS_FILE"
    
    export CUSTOM_IPK_COUNT="$integrate_ipk_count"
    export CUSTOM_SCRIPT_COUNT="$integrate_script_count"
    export CUSTOM_CONFIG_COUNT="$integrate_config_count"
    export CUSTOM_OTHER_COUNT="$integrate_other_count"
    export CUSTOM_CHINESE_COUNT="$integrate_chinese_count"
    export CUSTOM_PRIORITY_SCRIPT_COUNT="$integrate_priority_script_count"
    export CUSTOM_TOTAL_FILES="$integrate_total_files"
    export CUSTOM_FILES_INTEGRATED="true"
    
    log "📊 已导出到当前环境: IPK=$CUSTOM_IPK_COUNT, 脚本=$CUSTOM_SCRIPT_COUNT, 总数=$CUSTOM_TOTAL_FILES"
    
    save_env "with_stats"
}

load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
        log "✅ 从 $ENV_FILE 加载环境变量"
        
        log "📋 关键环境变量:"
        log "  SELECTED_BRANCH: $SELECTED_BRANCH"
        log "  TARGET: $TARGET"
        log "  SUBTARGET: $SUBTARGET"
        log "  DEVICE: $DEVICE"
        log "  CONFIG_MODE: $CONFIG_MODE"
        
        if [ "$1" = "show_stats" ] && [ -n "$CUSTOM_FILES_INTEGRATED" ]; then
            log "📊 已加载自定义文件统计信息:"
            log "  IPK文件: ${CUSTOM_IPK_COUNT:-0} 个"
            log "  脚本文件: ${CUSTOM_SCRIPT_COUNT:-0} 个"
            log "  总文件数: ${CUSTOM_TOTAL_FILES:-0} 个"
            log "  集成状态: ${CUSTOM_FILES_INTEGRATED}"
        fi
    else
        log "⚠️ 环境文件不存在: $ENV_FILE"
    fi
}

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

download_openwrt_sdk() {
    local target="$1"
    local subtarget="$2"
    local version="$3"
    
    log "=== 下载OpenWrt官方SDK工具链 ==="
    log "目标平台: $target/$subtarget"
    log "OpenWrt版本: $version"
    
    local sdk_url=""
    local sdk_filename=""
    
    if [ "$version" = "23.05" ] || [ "$version" = "openwrt-23.05" ]; then
        case "$target" in
            "ipq40xx")
                sdk_url="https://downloads.openwrt.org/releases/23.05.3/targets/ipq40xx/generic/openwrt-sdk-23.05.3-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                sdk_filename="openwrt-sdk-23.05.3-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                ;;
            "ramips")
                if [ "$subtarget" = "mt76x8" ]; then
                    sdk_url="https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt76x8/openwrt-sdk-23.05.3-ramips-mt76x8_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                    sdk_filename="openwrt-sdk-23.05.3-ramips-mt76x8_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
                elif [ "$subtarget" = "mt7621" ]; then
                    sdk_url="https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt7621/openwrt-sdk-23.05.3-ramips-mt7621_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                    sdk_filename="openwrt-sdk-23.05.3-ramips-mt7621_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
                else
                    log "❌ 不支持的子目标: $subtarget"
                    return 1
                fi
                ;;
            *)
                log "❌ 不支持的目标平台: $target"
                return 1
                ;;
        esac
    elif [ "$version" = "21.02" ] || [ "$version" = "openwrt-21.02" ]; then
        case "$target" in
            "ipq40xx")
                sdk_url="https://downloads.openwrt.org/releases/21.02.7/targets/ipq40xx/generic/openwrt-sdk-21.02.7-ipq40xx-generic_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                sdk_filename="openwrt-sdk-21.02.7-ipq40xx-generic_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                ;;
            "ramips")
                if [ "$subtarget" = "mt76x8" ]; then
                    sdk_url="https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt76x8/openwrt-sdk-21.02.7-ramips-mt76x8_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                    sdk_filename="openwrt-sdk-21.02.7-ramips-mt76x8_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
                elif [ "$subtarget" = "mt7621" ]; then
                    sdk_url="https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt7621/openwrt-sdk-21.02.7-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                    sdk_filename="openwrt-sdk-21.02.7-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
                else
                    log "❌ 不支持的子目标: $subtarget"
                    return 1
                fi
                ;;
            *)
                log "❌ 不支持的目标平台: $target"
                return 1
                ;;
        esac
    else
        log "❌ 不支持的OpenWrt版本: $version"
        return 1
    fi
    
    if [ -z "$sdk_url" ]; then
        log "❌ 无法确定SDK下载URL"
        return 1
    fi
    
    log "📥 SDK下载URL: $sdk_url"
    log "📁 SDK文件名: $sdk_filename"
    
    local sdk_dir="$BUILD_DIR/sdk"
    mkdir -p "$sdk_dir"
    
    log "开始下载OpenWrt SDK..."
    if wget --tries=3 --timeout=30 -q -O "$sdk_dir/$sdk_filename" "$sdk_url"; then
        log "✅ SDK下载成功"
    else
        log "⚠️ 首次下载失败，尝试备用下载..."
        if curl -L --connect-timeout 30 --retry 3 -o "$sdk_dir/$sdk_filename" "$sdk_url"; then
            log "✅ SDK下载成功（使用curl）"
        else
            log "❌ SDK下载失败"
            return 1
        fi
    fi
    
    log "解压SDK..."
    cd "$sdk_dir"
    if tar -xf "$sdk_filename" --strip-components=1; then
        log "✅ SDK解压成功"
        rm -f "$sdk_filename"
    else
        log "❌ SDK解压失败"
        return 1
    fi
    
    local toolchain_dir=""
    if [ -d "toolchain" ]; then
        toolchain_dir="$sdk_dir/toolchain"
        log "✅ 找到toolchain目录: $toolchain_dir"
    else
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
        
        verify_compiler_files
        return 0
    else
        log "❌ 未在SDK中找到编译器目录"
        return 1
    fi
}

check_gcc_version() {
    local gcc_path="$1"
    local target_version="${2:-11}"
    
    if [ ! -x "$gcc_path" ]; then
        log "❌ 文件不可执行: $gcc_path"
        return 1
    fi
    
    local version_output=$("$gcc_path" --version 2>&1)
    
    if echo "$version_output" | grep -qi "gcc"; then
        if echo "$version_output" | grep -qi "dummy-tools"; then
            log "⚠️ 虚假的GCC编译器: scripts/dummy-tools/gcc"
            return 1
        fi
        
        local full_version=$(echo "$version_output" | head -1)
        local compiler_name=$(basename "$gcc_path")
        log "✅ 找到GCC编译器: $compiler_name"
        log "   完整版本信息: $full_version"
        
        local version_num=$(echo "$full_version" | grep -o "[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)
        if [ -n "$version_num" ]; then
            log "   版本号: $version_num"
            
            local major_version=$(echo "$version_num" | cut -d. -f1)
            
            if [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                log "   ✅ GCC $major_version.x 版本兼容"
                return 0
            else
                log "   ⚠️ GCC版本 $major_version.x 可能不兼容（期望8-15）"
                return 1
            fi
        else
            log "   ⚠️ 无法提取版本号"
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
        log "🔍 编译器目录未设置或不存在"
        log "💡 将使用OpenWrt自动构建的编译器"
        return 0
    fi
    
    log "📊 编译器目录详细检查:"
    log "  路径: $compiler_dir"
    log "  大小: $(du -sh "$compiler_dir" 2>/dev/null | cut -f1 || echo '未知')"
    
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
        
        local version_output=$("$gcc_executable" --version 2>&1)
        if echo "$version_output" | grep -qi "dummy-tools"; then
            log "     ⚠️ 虚假的GCC编译器: scripts/dummy-tools/gcc"
            log "     🔍 继续查找真正的GCC编译器..."
            
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
            
            local gcc_name=$(basename "$gcc_executable")
            if [ "$target_platform" = "arm" ]; then
                if [[ "$gcc_name" == *arm* ]] || [[ "$gcc_name" == *aarch64* ]]; then
                    log "     🎯 编译器平台匹配: ARM"
                elif echo "$gcc_name" | grep -qi "gcc"; then
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
                
                local version=$("$used_compiler" --version 2>&1 | head -1)
                log "     版本: $version"
                
                if [[ "$used_compiler" == *"$COMPILER_DIR"* ]]; then
                    log "  🎯 编译器来自预构建目录: 是"
                    log "  📌 成功调用了预构建的编译器文件"
                    
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
        
        if [ -f "$BUILD_DIR/build.log" ]; then
            log "📖 分析构建日志中的编译器调用..."
            
            local compiler_calls=$(grep -c "gcc\|g++" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            log "  编译器调用次数: $compiler_calls"
            
            if [ $compiler_calls -gt 0 ]; then
                local prebuilt_calls=$(grep -c "$COMPILER_DIR" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
                if [ $prebuilt_calls -gt 0 ]; then
                    log "  ✅ 构建日志显示调用了预构建编译器"
                    log "     调用次数: $prebuilt_calls"
                    
                    grep "$COMPILER_DIR" "$BUILD_DIR/build.log" | head -2 | while read line; do
                        log "     示例: $(echo "$line" | tr -s ' ' | cut -c1-80)"
                    done
                else
                    log "  🔄 构建日志显示使用了其他编译器"
                    
                    grep "gcc\|g++" "$BUILD_DIR/build.log" | head -2 | while read line; do
                        log "     示例: $(echo "$line" | tr -s ' ' | cut -c1-80)"
                    done
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
    
    log "🔧 编译器调用状态详情:"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "  📌 预构建编译器目录: $COMPILER_DIR"
        
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

pre_build_error_check() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 前置错误检查（修复23.05 SDK验证）==="
    
    local error_count=0
    local warning_count=0
    
    log "当前环境变量:"
    log "  SELECTED_BRANCH: $SELECTED_BRANCH"
    log "  TARGET: $TARGET"
    log "  SUBTARGET: $SUBTARGET"
    log "  DEVICE: $DEVICE"
    log "  CONFIG_MODE: $CONFIG_MODE"
    log "  COMPILER_DIR: $COMPILER_DIR"
    
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        error_count=$((error_count + 1))
    else
        log "✅ .config 文件存在"
    fi
    
    if [ ! -d "feeds" ]; then
        log "❌ 错误: feeds 目录不存在"
        error_count=$((error_count + 1))
    else
        log "✅ feeds 目录存在"
    fi
    
    if [ ! -d "dl" ]; then
        log "⚠️ 警告: dl 目录不存在，可能需要下载依赖"
        warning_count=$((warning_count + 1))
    else
        local dl_count=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
        log "✅ 依赖包数量: $dl_count 个"
    fi
    
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
    
    local critical_files=("Makefile" "rules.mk" "Config.in" "feeds.conf.default")
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 关键文件存在: $file"
        else
            log "❌ 错误: 关键文件不存在: $file"
            error_count=$((error_count + 1))
        fi
    done
    
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log "磁盘可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 10 ]; then
        log "❌ 错误: 磁盘空间不足 (需要至少10G，当前${available_gb}G)"
        error_count=$((error_count + 1))
    elif [ $available_gb -lt 20 ]; then
        log "⚠️ 警告: 磁盘空间较低 (建议至少20G，当前${available_gb}G)"
        warning_count=$((warning_count + 1))
    fi
    
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    log "系统内存: ${total_mem}MB"
    
    if [ $total_mem -lt 1024 ]; then
        log "⚠️ 警告: 内存较低 (建议至少1GB)"
        warning_count=$((warning_count + 1))
    fi
    
    log "🔧 检查预构建编译器文件..."
    
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ 预构建编译器目录存在: $COMPILER_DIR"
        log "📊 目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo '未知')"
        
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
                
                if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
                    local sdk_version=$("$first_gcc" --version 2>&1 | head -1)
                    if echo "$sdk_version" | grep -qi "12.3.0"; then
                        log "🎯 确认是OpenWrt 23.05 SDK GCC 12.3.0"
                    elif echo "$sdk_version" | grep -qi "dummy-tools"; then
                        log "⚠️ 检测到虚假的dummy-tools编译器，继续查找..."
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
    
    check_compiler_invocation
    
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
    
    local base_packages=(
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip
        zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath
        libpython3-dev python3 python3-dev python3-pip python3-setuptools
        python3-yaml xsltproc zip subversion ninja-build automake autoconf
        libtool pkg-config help2man texinfo aria2 liblz4-dev zstd
        libcurl4-openssl-dev groff texlive texinfo cmake
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
    
    if [ -w "$BUILD_DIR" ]; then
        log "✅ 构建目录创建完成: $BUILD_DIR"
    else
        log "❌ 构建目录权限错误"
        exit 1
    fi
}

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
    
    log "🔧 修复克隆源码，设置Git重试和超时..."
    
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    git config --global core.compression 0
    git config --global core.looseCompression 0
    git config --global http.sslVerify false
    
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    export CURL_SSL_NO_VERIFY=1
    
    local clone_attempt=1
    local max_attempts=3
    local clone_success=false
    
    while [ $clone_attempt -le $max_attempts ]; do
        log "尝试克隆第 $clone_attempt 次..."
        
        if timeout 300 git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" .; then
            clone_success=true
            break
        else
            log "⚠️ 克隆尝试 $clone_attempt 失败，等待10秒后重试..."
            sleep 10
            rm -rf .git* 2>/dev/null || true
            rm -rf * 2>/dev/null || true
            clone_attempt=$((clone_attempt + 1))
        fi
    done
    
    if [ "$clone_success" = false ]; then
        log "❌ 克隆源码失败，尝试备用方案..."
        
        log "尝试使用wget下载源码tar包..."
        
        local repo_name=$(basename "$SELECTED_REPO_URL" .git)
        local tar_url="${SELECTED_REPO_URL%.git}/archive/refs/heads/$SELECTED_BRANCH.tar.gz"
        
        if wget --tries=3 --timeout=30 -q -O source.tar.gz "$tar_url"; then
            log "✅ 下载源码tar包成功"
            tar -xzf source.tar.gz --strip-components=1
            rm -f source.tar.gz
            log "✅ 源码解压成功"
        else
            handle_error "克隆源码失败，所有尝试都失败"
        fi
    fi
    
    log "✅ 源码获取完成"
    
    local important_source_files=("Makefile" "feeds.conf.default" "rules.mk" "Config.in")
    for file in "${important_source_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 源码文件存在: $file"
        else
            log "❌ 源码文件缺失: $file"
        fi
    done
    
    log "=== 设备配置 ==="
    case "$device_name" in
        "ac42u"|"acrh17")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-ac42u"
            log "🔧 检测到高通IPQ40xx平台设备: $device_name"
            log "🔧 该设备支持USB 3.0，将启用所有USB 3.0相关驱动"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            TARGET="ramips"
            SUBTARGET="mt76x8"
            DEVICE="xiaomi_mi-router-4a-gigabit"
            log "🔧 检测到雷凌MT76x8平台设备: $device_name"
            ;;
        "mi_router_3g"|"r3g")
            TARGET="ramips"
            SUBTARGET="mt7621"
            DEVICE="xiaomi_mi-router-3g"
            log "🔧 检测到雷凌MT7621平台设备: $device_name"
            ;;
        *)
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="$device_name"
            log "🔧 未知设备，默认为高通IPQ40xx平台"
            ;;
    esac
    
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

initialize_compiler_env() {
    local device_name="$1"
    log "=== 初始化编译器环境（下载OpenWrt官方SDK）- 修复版 ==="
    
    log "🔍 检查环境文件..."
    if [ -f "$BUILD_DIR/build_env.sh" ]; then
        source "$BUILD_DIR/build_env.sh"
        log "✅ 从 $BUILD_DIR/build_env.sh 加载环境变量"
        
        log "📋 当前环境变量:"
        log "  SELECTED_BRANCH: $SELECTED_BRANCH"
        log "  TARGET: $TARGET"
        log "  SUBTARGET: $SUBTARGET"
        log "  DEVICE: $DEVICE"
        log "  CONFIG_MODE: $CONFIG_MODE"
        log "  REPO_ROOT: $REPO_ROOT"
        log "  COMPILER_DIR: $COMPILER_DIR"
    else
        log "⚠️ 环境文件不存在: $BUILD_DIR/build_env.sh"
        log "💡 环境文件应该在步骤6.3中创建，但未找到"
        
        if [ -z "$SELECTED_BRANCH" ]; then
            if [ "$device_name" = "ac42u" ] || [ "$device_name" = "acrh17" ]; then
                SELECTED_BRANCH="openwrt-21.02"
            else
                SELECTED_BRANCH="openwrt-21.02"
            fi
            log "⚠️ SELECTED_BRANCH未设置，使用默认值: $SELECTED_BRANCH"
        fi
        
        if [ -z "$TARGET" ]; then
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
            log "⚠️ 平台变量未设置，使用默认值: TARGET=$TARGET, SUBTARGET=$SUBTARGET, DEVICE=$DEVICE"
        fi
        
        if [ -z "$CONFIG_MODE" ]; then
            CONFIG_MODE="normal"
            log "⚠️ CONFIG_MODE未设置，使用默认值: $CONFIG_MODE"
        fi
        
        save_env
        log "✅ 已创建环境文件: $BUILD_DIR/build_env.sh"
    fi
    
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "✅ 使用环境变量中的编译器目录: $COMPILER_DIR"
        
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
            
            save_env
            
            verify_compiler_files
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
        version_for_sdk=$(echo "$SELECTED_BRANCH" | grep -o "[0-9][0-9]\.[0-9][0-9]" || echo "21.02")
        log "⚠️ 无法识别的版本分支，尝试使用: $version_for_sdk"
    fi
    
    log "📌 SDK版本: $version_for_sdk"
    log "📌 目标平台: $TARGET/$SUBTARGET"
    
    log "🔍 SDK下载详细信息:"
    log "  设备: $device_name"
    log "  OpenWrt版本: $SELECTED_BRANCH"
    log "  SDK版本: $version_for_sdk"
    log "  目标: $TARGET"
    log "  子目标: $SUBTARGET"
    
    log "🚀 开始下载OpenWrt官方SDK..."
    if download_openwrt_sdk "$TARGET" "$SUBTARGET" "$version_for_sdk"; then
        log "🎉 OpenWrt SDK下载并设置成功"
        log "📌 编译器目录: $COMPILER_DIR"
        
        if [ -d "$COMPILER_DIR" ]; then
            log "📊 SDK目录信息:"
            log "  目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo '未知')"
            log "  文件数量: $(find "$COMPILER_DIR" -type f 2>/dev/null | wc -l)"
            
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
        
        save_env
        
        return 0
    else
        log "❌ OpenWrt SDK下载失败"
        log "💡 将使用OpenWrt自动构建的编译器作为后备"
        
        export COMPILER_DIR=""
        save_env
        
        return 1
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
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
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

generate_config() {
    local extra_packages=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 智能配置生成系统（USB完全修复通用版）==="
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    
    rm -f .config .config.old
    
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
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
    
    echo "# CONFIG_PACKAGE_dnsmasq is not set" >> .config
    echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcp=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dnssec=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_ipset=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_conntrack=y" >> .config
    
    echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
    echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
    echo "CONFIG_PACKAGE_ath10k-firmware-qca988x=y" >> .config
    echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config
    
    echo "CONFIG_PACKAGE_iptables=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-ipopt=y" >> .config
    echo "CONFIG_PACKAGE_ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config
    
    echo "CONFIG_PACKAGE_bridge=y" >> .config
    echo "CONFIG_PACKAGE_blockd=y" >> .config
    echo "# CONFIG_PACKAGE_busybox-selinux is not set" >> .config
    echo "# CONFIG_PACKAGE_attendedsysupgrade-common is not set" >> .config
    echo "# CONFIG_PACKAGE_auc is not set" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 开始 ==="
    
    echo "# 🟢 USB 核心驱动 - 基础必须" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
    
    echo "# 🟢 USB 主机控制器驱动 - 通用支持" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ehci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-uhci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
    
    echo "# 🟢 USB 3.0扩展主机控制器接口驱动 - 支持USB 3.0高速数据传输" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
    
    echo "# 🟡 平台专用USB控制器驱动 - 根据平台启用" >> .config
    log "🔍 检测平台类型: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
    
    if [ "$TARGET" = "ipq40xx" ]; then
        log "🚨 关键修复：IPQ40xx 专用USB控制器驱动（高通平台，支持USB 3.0）"
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-xhci-mtk is not set" >> .config
        log "✅ 已启用所有高通IPQ40xx平台的USB驱动"
    fi
    
    if [ "$TARGET" = "ramips" ]; then
        if [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; then
            log "🚨 关键修复：MT76xx/雷凌 平台USB控制器驱动"
            echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
            echo "# CONFIG_PACKAGE_kmod-usb-dwc3-qcom is not set" >> .config
            echo "# CONFIG_PACKAGE_kmod-phy-qcom-dwc3 is not set" >> .config
            log "✅ 已启用雷凌MT76xx平台的USB驱动"
        fi
    fi
    
    echo "# 🟢 USB 存储驱动 - 核心功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    
    echo "# 🟢 SCSI 支持 - 硬盘和U盘必需" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> .config
    
    echo "# 🟢 文件系统支持 - 完整文件系统兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-autofs4=y" >> .config
    
    echo "# 🟢 USB大容量存储额外驱动" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本NTFS配置优化"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g-utils is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs3-mount is not set" >> .config
    else
        log "🔧 21.02版本NTFS配置"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        echo "CONFIG_PACKAGE_ntfs3-mount=y" >> .config
    fi
    
    echo "# 🟢 编码支持 - 多语言文件名兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp437=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-iso8859-1=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp936=y" >> .config
    
    echo "# 🟢 自动挂载工具 - 即插即用支持" >> .config
    echo "CONFIG_PACKAGE_block-mount=y" >> .config
    echo "CONFIG_PACKAGE_automount=y" >> .config
    
    echo "# 🟢 USB 工具和热插拔支持 - 设备管理" >> .config
    echo "CONFIG_PACKAGE_usbutils=y" >> .config
    echo "CONFIG_PACKAGE_lsusb=y" >> .config
    echo "CONFIG_PACKAGE_udev=y" >> .config
    
    echo "# 🟢 USB串口支持 - 扩展功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial-ftdi=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial-pl2303=y" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 完成 ==="
    
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config
    
    if [ "$CONFIG_MODE" = "base" ]; then
        log "🔧 使用基础模式 (最小化，用于测试编译)"
        echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> .config
        echo "# CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn is not set" >> .config
    else
        log "🔧 使用正常模式 (完整功能)"
        
        NORMAL_PLUGINS=(
          "CONFIG_PACKAGE_luci-app-turboacc=y"
          "CONFIG_PACKAGE_kmod-shortcut-fe=y"
          "CONFIG_PACKAGE_kmod-fast-classifier=y"
          "CONFIG_PACKAGE_luci-app-upnp=y"
          "CONFIG_PACKAGE_miniupnpd=y"
          "CONFIG_PACKAGE_vsftpd=y"
          "CONFIG_PACKAGE_luci-app-vsftpd=y"
          "CONFIG_PACKAGE_luci-app-arpbind=y"
          "CONFIG_PACKAGE_luci-app-cpulimit=y"
          "CONFIG_PACKAGE_samba4-server=y"
          "CONFIG_PACKAGE_luci-app-samba4=y"
          "CONFIG_PACKAGE_luci-app-wechatpush=y"
          "CONFIG_PACKAGE_sqm-scripts=y"
          "CONFIG_PACKAGE_luci-app-sqm=y"
          "CONFIG_PACKAGE_luci-app-hd-idle=y"
          "CONFIG_PACKAGE_luci-app-diskman=y"
          "CONFIG_PACKAGE_luci-app-accesscontrol=y"
          "CONFIG_PACKAGE_vlmcsd=y"
          "CONFIG_PACKAGE_luci-app-vlmcsd=y"
          "CONFIG_PACKAGE_smartdns=y"
          "CONFIG_PACKAGE_luci-app-smartdns=y"
        )
        
        for plugin in "${NORMAL_PLUGINS[@]}"; do
            echo "$plugin" >> .config
        done
        
        echo "CONFIG_PACKAGE_luci-app-accesscontrol=y" >> .config
        log "✅ 已添加上网时间控制插件"
        
        if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
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
    
    if [ -n "$extra_packages" ]; then
        log "🔧 处理额外安装插件: $extra_packages"
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
    echo "  - kmod-usb-dwc3:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    echo "4. 🚨 平台专用USB控制器:"
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "  🔧 检测到高通IPQ40xx平台，检查专用驱动:"
        echo "  - kmod-usb-dwc3-qcom:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-phy-qcom-dwc3:" $(grep "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    elif [ "$TARGET" = "ramips" ]; then
        echo "  🔧 检测到雷凌平台，检查专用驱动:"
        echo "  - kmod-usb-ohci-pci:" $(grep "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-usb2-pci:" $(grep "CONFIG_PACKAGE_kmod-usb2-pci=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
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
    
    if [ "$TARGET" = "ipq40xx" ]; then
        required_drivers+=("kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3")
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
    
    echo ""
    echo "=== 详细配置状态 ==="
    
    echo "🔧 关键USB配置状态:"
    local critical_usb_drivers=(
        "kmod-usb-core" "kmod-usb2" "kmod-usb3" 
        "kmod-usb-ehci" "kmod-usb-ohci" "kmod-usb-xhci-hcd"
        "kmod-usb-storage" "kmod-usb-storage-uas" "kmod-usb-storage-extras"
        "kmod-scsi-core" "kmod-scsi-generic"
    )
    
    local missing_usb=0
    for driver in "${critical_usb_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "  ✅ $driver"
        else
            echo "  ❌ $driver - 缺失！"
            missing_usb=$((missing_usb + 1))
        fi
    done
    
    echo ""
    echo "🔧 平台专用USB驱动状态:"
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "  高通IPQ40xx平台专用驱动:"
        local qcom_drivers=("kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3-of-simple")
        for driver in "${qcom_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "    ✅ $driver"
            else
                echo "    ❌ $driver - 缺失！"
                missing_usb=$((missing_usb + 1))
            fi
        done
    elif [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; }; then
        echo "  雷凌MT76xx平台专用驱动:"
        local mtk_drivers=("kmod-usb-ohci-pci" "kmod-usb2-pci" "kmod-usb-xhci-mtk")
        for driver in "${mtk_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "    ✅ $driver"
            else
                echo "    ❌ $driver - 缺失！"
                missing_usb=$((missing_usb + 1))
            fi
        done
    fi
    
    echo ""
    echo "🔧 文件系统支持状态:"
    local fs_drivers=("kmod-fs-ext4" "kmod-fs-vfat" "kmod-fs-exfat" "kmod-fs-ntfs3")
    for driver in "${fs_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "  ✅ $driver"
        else
            echo "  ❌ $driver - 缺失！"
        fi
    done
    
    echo ""
    echo "🚀 功能性插件状态:"
    
    local functional_plugins=(
        "luci-app-turboacc" "TurboACC 网络加速"
        "luci-app-upnp" "UPnP 自动端口转发"
        "samba4-server" "Samba 文件共享"
        "luci-app-diskman" "磁盘管理"
        "vlmcsd" "KMS 激活服务"
        "smartdns" "SmartDNS 智能DNS"
        "luci-app-accesscontrol" "家长控制"
        "luci-app-wechatpush" "微信推送"
        "sqm-scripts" "流量控制 (SQM)"
        "vsftpd" "FTP 服务器"
        "luci-app-arpbind" "ARP 绑定"
        "luci-app-cpulimit" "CPU 限制"
        "luci-app-hd-idle" "硬盘休眠"
    )
    
    for i in $(seq 0 2 $((${#functional_plugins[@]} - 1))); do
        local plugin="${functional_plugins[$i]}"
        local desc="${functional_plugins[$((i + 1))]}"
        
        if grep -q "^CONFIG_PACKAGE_${plugin}=y" .config; then
            echo "  ✅ $desc ($plugin)"
        elif grep -q "^# CONFIG_PACKAGE_${plugin} is not set" .config; then
            echo "  ❌ $desc ($plugin) - 已禁用"
        else
            echo "  ⚪ $desc ($plugin) - 未配置"
        fi
    done
    
    echo ""
    echo "📊 配置统计信息:"
    local enabled_count=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local disabled_count=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    echo "  ✅ 已启用插件: $enabled_count 个"
    echo "  ❌ 已禁用插件: $disabled_count 个"
    
    if [ $disabled_count -gt 0 ]; then
        echo ""
        echo "📋 具体被禁用的插件:"
        local count=0
        grep "^# CONFIG_PACKAGE_.* is not set$" .config | while read line; do
            if [ $count -lt 20 ]; then
                local pkg_name=$(echo $line | sed 's/# CONFIG_PACKAGE_//;s/ is not set//')
                echo "  ❌ $pkg_name"
                count=$((count + 1))
            else
                local remaining=$((disabled_count - 20))
                echo "  ... 还有 $remaining 个被禁用的插件"
                break
            fi
        done
    fi
    
    if [ $missing_usb -gt 0 ]; then
        echo ""
        echo "🚨 修复缺失的关键USB驱动:"
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-hcd"
            sed -i 's/^# CONFIG_PACKAGE_kmod-usb-xhci-hcd is not set$/CONFIG_PACKAGE_kmod-usb-xhci-hcd=y/' .config
            if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
                echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
            fi
            echo "  ✅ 已修复 kmod-usb-xhci-hcd"
        fi
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-pci=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-pci"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-pci"
        fi
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-plat-hcd"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-plat-hcd"
        fi
        
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-ohci-pci=y" .config; then
            echo "  修复: 启用 kmod-usb-ohci-pci"
            echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
            echo "  ✅ 已修复 kmod-usb-ohci-pci"
        fi
        
        if [ "$TARGET" = "ipq40xx" ] && ! grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" .config; then
            echo "  修复: 启用 kmod-usb-dwc3-of-simple"
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
            echo "  ✅ 已修复 kmod-usb-dwc3-of-simple"
        fi
        
        if [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; } && ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-mtk"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-mtk"
        fi
    fi
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本配置预处理"
        sed -i 's/CONFIG_PACKAGE_ntfs-3g=y/# CONFIG_PACKAGE_ntfs-3g is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs-3g-utils=y/# CONFIG_PACKAGE_ntfs-3g-utils is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs3-mount=y/# CONFIG_PACKAGE_ntfs3-mount is not set/g' .config
        log "✅ NTFS配置修复完成"
    fi
    
    log "🔄 运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log "🚨 强制启用关键USB驱动（防止defconfig删除）"
    echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
    
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-xhci-mtk is not set" >> .config
    elif [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; }; then
        echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-dwc3-qcom is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-phy-qcom-dwc3 is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-dwc3-of-simple is not set" >> .config
    fi
    
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
    
    check_usb_drivers_integrity
    
    echo ""
    echo "=== 最终配置检查 ==="
    local final_enabled=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local final_disabled=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    echo "✅ 最终状态: 已启用 $final_enabled 个, 已禁用 $final_disabled 个"
    
    log "✅ 配置应用完成"
    log "最终配置文件: .config"
    log "最终配置大小: $(ls -lh .config | awk '{print $5}')"
}

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

detect_chinese_characters() {
    local text="$1"
    
    if echo "$text" | grep -q -P '[\x{4e00}-\x{9fff}\x{3400}-\x{4dbf}]'; then
        return 0
    fi
    
    if echo "$text" | grep -q -P '[\x{3000}-\x{303f}\x{ff00}-\x{ffef}]'; then
        return 0
    fi
    
    local chinese_keywords="备份|恢复|安装|配置|设置|脚本|文件|固件|插件|网络|系统|路由|无线"
    if echo "$text" | grep -q -E "$chinese_keywords"; then
        return 0
    fi
    
    return 1
}

analyze_script() {
    local script="$1"
    local script_name=$(basename "$script")
    
    local script_type="misc"
    local priority=50
    
    local content=$(head -50 "$script" 2>/dev/null)
    
    case "$script_name" in
        *package*|*install*|*opkg*|*安装*|*包管理*)
            script_type="package"
            priority=10
            ;;
        *network*|*firewall*|*网络*|*防火墙*)
            script_type="network"
            priority=20
            ;;
        *cron*|*crontab*|*定时*|*计划任务*)
            script_type="cron"
            priority=30
            ;;
        *config*|*配置*|*设置*)
            script_type="config"
            priority=35
            ;;
        *service*|*启动*|*停止*|*restart*)
            script_type="service"
            priority=40
            ;;
        *backup*|*restore*|*备份*|*恢复*)
            script_type="backup"
            priority=60
            ;;
    esac
    
    if [ "$script_type" = "misc" ]; then
        if echo "$content" | grep -qi "opkg\|install\|package\|安装\|包管理"; then
            script_type="package"
            priority=10
        elif echo "$content" | grep -qi "network\|firewall\|网络设置\|防火墙"; then
            script_type="network"
            priority=20
        elif echo "$content" | grep -qi "crontab\|cron\|定时任务\|计划任务"; then
            script_type="cron"
            priority=30
        elif echo "$content" | grep -qi "config\|配置\|设置"; then
            script_type="config"
            priority=35
        elif echo "$content" | grep -qi "service\|启动\|停止\|restart"; then
            script_type="service"
            priority=40
        elif echo "$content" | grep -qi "backup\|restore\|备份\|恢复"; then
            script_type="backup"
            priority=60
        fi
    fi
    
    echo "$script_name:$script_type:$priority"
}

# 集成自定义文件函数 - 修复第一次开机脚本执行问题
integrate_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 集成自定义文件（修复第一次开机脚本执行问题）==="
    
    local custom_dir="$REPO_ROOT/firmware-config/custom-files"
    
    if [ ! -d "$custom_dir" ]; then
        log "ℹ️ 自定义文件目录不存在: $custom_dir"
        log "💡 如需集成自定义文件，请在 firmware-config/custom-files/ 目录中添加文件"
        return 0
    fi
    
    log "自定义文件目录: $custom_dir"
    log "OpenWrt版本: $SELECTED_BRANCH"
    
    log "🧹 清理旧的统计和环境变量..."
    
    if [ -f "$CUSTOM_STATS_FILE" ]; then
        rm -f "$CUSTOM_STATS_FILE"
        log "✅ 清理旧的统计文件: $CUSTOM_STATS_FILE"
    fi
    
    unset CUSTOM_IPK_COUNT CUSTOM_SCRIPT_COUNT CUSTOM_CONFIG_COUNT CUSTOM_OTHER_COUNT
    unset CUSTOM_CHINESE_COUNT CUSTOM_PRIORITY_SCRIPT_COUNT CUSTOM_TOTAL_FILES CUSTOM_FILES_INTEGRATED
    
    log "🔧 步骤1: 创建自定义文件目录"
    
    local custom_files_dir="files/etc/custom-files"
    mkdir -p "$custom_files_dir"
    log "✅ 创建自定义文件目录: $custom_files_dir"
    
    local integrate_ipk_count=0
    local integrate_script_count=0
    local integrate_config_count=0
    local integrate_other_count=0
    local integrate_chinese_count=0
    local integrate_copied_count=0
    local integrate_folder_count=0
    local integrate_total_files=0
    local integrate_priority_script_count=0
    
    recursive_copy_files() {
        local src_dir="$1"
        local dst_dir="$2"
        local relative_path="${3:-}"
        
        mkdir -p "$dst_dir"
        
        for src_item in "$src_dir"/*; do
            [ ! -e "$src_item" ] && continue
            
            local src_name=$(basename "$src_item")
            local dst_name="$src_name"
            
            if [ -d "$src_item" ]; then
                integrate_folder_count=$((integrate_folder_count + 1))
                log "  发现子文件夹: $relative_path$src_name/"
                
                recursive_copy_files "$src_item" "$dst_dir/$src_name" "$relative_path$src_name/"
                continue
            fi
            
            local full_dst_path="$dst_dir/$dst_name"
            
            if [ -f "$full_dst_path" ]; then
                local counter=1
                while [ -f "${dst_dir}/${counter}_${dst_name}" ]; do
                    counter=$((counter + 1))
                done
                dst_name="${counter}_${dst_name}"
                full_dst_path="$dst_dir/$dst_name"
            fi
            
            if detect_chinese_characters "$src_name"; then
                integrate_chinese_count=$((integrate_chinese_count + 1))
                log "    发现中文文件名: $relative_path$src_name"
            fi
            
            if echo "$src_name" | grep -qi "\.ipk$"; then
                integrate_ipk_count=$((integrate_ipk_count + 1))
                log "    📦 IPK文件: $relative_path$src_name"
            elif [[ "$src_name" == *.sh ]] || [[ "$src_name" == *.Sh ]] || [[ "$src_name" == *.SH ]] || \
                 head -2 "$src_item" 2>/dev/null | grep -q "^#!"; then
                integrate_script_count=$((integrate_script_count + 1))
                
                local analysis_result=$(analyze_script "$src_item")
                local script_type=$(echo "$analysis_result" | cut -d':' -f2)
                local priority=$(echo "$analysis_result" | cut -d':' -f3)
                
                if [ "$priority" -lt 50 ]; then
                    integrate_priority_script_count=$((integrate_priority_script_count + 1))
                fi
                
                log "    📜 脚本文件: $relative_path$src_name (类型: $script_type, 优先级: $priority)"
            elif [[ "$src_name" == *.conf ]] || [[ "$src_name" == *.config ]] || [[ "$src_name" == *.CONF ]]; then
                integrate_config_count=$((integrate_config_count + 1))
                log "    ⚙️ 配置文件: $relative_path$src_name"
            else
                integrate_other_count=$((integrate_other_count + 1))
                log "    📁 其他文件: $relative_path$src_name"
            fi
            
            if cp "$src_item" "$full_dst_path" 2>/dev/null; then
                integrate_copied_count=$((integrate_copied_count + 1))
                integrate_total_files=$((integrate_total_files + 1))
                if [[ "$dst_name" == *.sh ]] || head -2 "$full_dst_path" 2>/dev/null | grep -q "^#!"; then
                    chmod +x "$full_dst_path" 2>/dev/null || true
                fi
            else
                log "    ⚠️ 复制文件失败: $src_name"
            fi
        done
    }
    
    log "🔧 步骤2: 递归复制所有自定义文件并进行分析（保持原文件名）"
    recursive_copy_files "$custom_dir" "$custom_files_dir" ""
    
    log "📊 保存自定义文件统计信息..."
    
    cat > "$CUSTOM_STATS_FILE" << EOF
CUSTOM_IPK_COUNT="$integrate_ipk_count"
CUSTOM_SCRIPT_COUNT="$integrate_script_count"
CUSTOM_CONFIG_COUNT="$integrate_config_count"
CUSTOM_OTHER_COUNT="$integrate_other_count"
CUSTOM_CHINESE_COUNT="$integrate_chinese_count"
CUSTOM_PRIORITY_SCRIPT_COUNT="$integrate_priority_script_count"
CUSTOM_TOTAL_FILES="$integrate_total_files"
CUSTOM_FILES_INTEGRATED="true"
EOF
    
    log "✅ 自定义文件统计信息已保存到: $CUSTOM_STATS_FILE"
    
    export CUSTOM_IPK_COUNT="$integrate_ipk_count"
    export CUSTOM_SCRIPT_COUNT="$integrate_script_count"
    export CUSTOM_CONFIG_COUNT="$integrate_config_count"
    export CUSTOM_OTHER_COUNT="$integrate_other_count"
    export CUSTOM_CHINESE_COUNT="$integrate_chinese_count"
    export CUSTOM_PRIORITY_SCRIPT_COUNT="$integrate_priority_script_count"
    export CUSTOM_TOTAL_FILES="$integrate_total_files"
    export CUSTOM_FILES_INTEGRATED="true"
    
    log "📊 已导出到当前环境: IPK=$CUSTOM_IPK_COUNT, 脚本=$CUSTOM_SCRIPT_COUNT, 总数=$CUSTOM_TOTAL_FILES"
    
    save_env "with_stats"
    
    log "📊 文件统计:"
    log "  📦 IPK文件: $integrate_ipk_count 个"
    log "  📜 脚本文件: $integrate_script_count 个"
    log "    其中 $integrate_priority_script_count 个具有高优先级"
    log "  ⚙️ 配置文件: $integrate_config_count 个"
    log "  📁 其他文件: $integrate_other_count 个"
    log "  📁 子文件夹: $integrate_folder_count 个"
    log "  🇨🇳 中文文件: $integrate_chinese_count 个"
    log "  📋 总复制文件: $integrate_copied_count 个"
    log "  💾 统计信息已保存到: $CUSTOM_STATS_FILE"
    
    # 修复：创建更可靠的第一次开机脚本
    log "🔧 步骤3: 创建可靠的第一次开机脚本（修复执行中断问题）"
    
    local smart_script="$custom_files_dir/smart_install.sh"
    cat > "$smart_script" << 'EOF'
#!/bin/sh
# 可靠的智能安装管理器 - 修复执行中断问题

LOG_FILE="/tmp/smart-install.log"
CUSTOM_DIR="/etc/custom-files"
INSTALL_MARKER="/etc/custom-files-installed"

echo "=== 可靠的智能安装管理器 ===" > $LOG_FILE
echo "开始时间: $(date)" >> $LOG_FILE
echo "" >> $LOG_FILE

# 检查是否已经安装过
if [ -f "$INSTALL_MARKER" ]; then
    echo "ℹ️ 检测到已安装标记，跳过重复安装" >> $LOG_FILE
    echo "📌 如需重新安装，请删除 $INSTALL_MARKER 文件" >> $LOG_FILE
    exit 0
fi

# 确保日志目录存在
mkdir -p /tmp

# 安装IPK包（失败不中断）
install_ipk_packages() {
    echo "" >> $LOG_FILE
    echo "=== 安装IPK包（失败不中断） ===" >> $LOG_FILE
    
    local ipk_count=0
    local success_count=0
    local failed_count=0
    
    # 查找所有IPK文件
    for file in $(find "$CUSTOM_DIR" -type f 2>/dev/null); do
        local filename=$(basename "$file")
        if echo "$filename" | grep -qi "\.ipk$"; then
            ipk_count=$((ipk_count + 1))
            echo "" >> $LOG_FILE
            echo "📦 处理IPK [$ipk_count]: $filename" >> $LOG_FILE
            
            # 检查文件大小
            local filesize=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
            echo "文件大小: $filesize" >> $LOG_FILE
            
            # 使用绝对路径安装
            echo "执行: opkg install \"$file\"" >> $LOG_FILE
            if opkg install "$file" >> $LOG_FILE 2>&1; then
                success_count=$((success_count + 1))
                echo "✅ $filename 安装成功" >> $LOG_FILE
            else
                failed_count=$((failed_count + 1))
                echo "⚠️ $filename 安装失败" >> $LOG_FILE
                echo "💡 安装失败不影响继续执行其他任务" >> $LOG_FILE
            fi
        fi
    done
    
    echo "" >> $LOG_FILE
    echo "📊 IPK安装统计:" >> $LOG_FILE
    echo "  总IPK文件: $ipk_count 个" >> $LOG_FILE
    echo "  成功安装: $success_count 个" >> $LOG_FILE
    echo "  安装失败: $failed_count 个" >> $LOG_FILE
    
    if [ $ipk_count -eq 0 ]; then
        echo "ℹ️ 未找到IPK文件" >> $LOG_FILE
    fi
    
    return 0
}

# 执行脚本（失败不中断）
execute_scripts() {
    echo "" >> $LOG_FILE
    echo "=== 执行脚本（失败不中断） ===" >> $LOG_FILE
    
    local script_count=0
    local success_count=0
    local failed_count=0
    
    # 查找所有脚本文件
    for script in $(find "$CUSTOM_DIR" -type f 2>/dev/null); do
        local script_name=$(basename "$script")
        
        # 检查是否是脚本文件
        if [[ "$script_name" == *.sh ]] || [[ "$script_name" == *.Sh ]] || [[ "$script_name" == *.SH ]] || \
           head -1 "$script" 2>/dev/null | grep -q "^#!"; then
            script_count=$((script_count + 1))
            echo "" >> $LOG_FILE
            echo "📜 处理脚本 [$script_count]: $script_name" >> $LOG_FILE
            
            # 确保有执行权限
            chmod +x "$script" 2>/dev/null || true
            
            # 执行脚本
            echo "执行脚本..." >> $LOG_FILE
            if sh "$script" >> $LOG_FILE 2>&1; then
                success_count=$((success_count + 1))
                echo "✅ $script_name 执行成功" >> $LOG_FILE
            else
                failed_count=$((failed_count + 1))
                echo "⚠️ $script_name 执行失败" >> $LOG_FILE
                echo "💡 脚本执行失败不影响继续执行其他任务" >> $LOG_FILE
            fi
        fi
    done
    
    echo "" >> $LOG_FILE
    echo "📊 脚本执行统计:" >> $LOG_FILE
    echo "  找到脚本: $script_count 个" >> $LOG_FILE
    echo "  执行成功: $success_count 个" >> $LOG_FILE
    echo "  执行失败: $failed_count 个" >> $LOG_FILE
    
    if [ $script_count -eq 0 ]; then
        echo "ℹ️ 未找到脚本文件" >> $LOG_FILE
    fi
}

# 主安装流程
echo "1. 安装IPK包..." >> $LOG_FILE
install_ipk_packages

echo "" >> $LOG_FILE
echo "2. 执行脚本..." >> $LOG_FILE
execute_scripts

# 创建安装标记
echo "" >> $LOG_FILE
echo "3. 创建安装完成标记..." >> $LOG_FILE
touch "$INSTALL_MARKER" 2>/dev/null
if [ -f "$INSTALL_MARKER" ]; then
    echo "✅ 安装标记已创建: $INSTALL_MARKER" >> $LOG_FILE
else
    echo "⚠️ 无法创建安装标记" >> $LOG_FILE
fi

echo "" >> $LOG_FILE
echo "=== 智能安装完成 ===" >> $LOG_FILE
echo "结束时间: $(date)" >> $LOG_FILE
echo "安装日志: $LOG_FILE" >> $LOG_FILE

echo ""
echo "智能安装管理器执行完成"
echo "📝 详细日志请查看: $LOG_FILE"
exit 0
EOF
    
    chmod +x "$smart_script"
    log "✅ 创建可靠的智能安装脚本: $smart_script"
    
    # 修复：创建更简单的第一次开机脚本，避免执行中断
    log "🔧 步骤4: 创建简单的第一次开机脚本（避免执行中断）"
    
    local first_boot_dir="files/etc/uci-defaults"
    mkdir -p "$first_boot_dir"
    
    local first_boot_script="$first_boot_dir/99-custom-files"
    cat > "$first_boot_script" << 'EOF'
#!/bin/sh
# 第一次开机脚本 - 修复版
# 避免执行中断问题

LOG_FILE="/tmp/custom-files-install.log"
CUSTOM_DIR="/etc/custom-files"
SMART_SCRIPT="$CUSTOM_DIR/smart_install.sh"
INSTALL_MARKER="/etc/custom-files-installed"

# 创建日志文件
echo "=== 第一次开机脚本 - 修复版 ===" > $LOG_FILE
echo "开始时间: $(date)" >> $LOG_FILE
echo "" >> $LOG_FILE

# 确保脚本能继续执行，即使有错误
set +e

# 检查是否已经安装过
if [ -f "$INSTALL_MARKER" ]; then
    echo "ℹ️ 检测到已安装标记，跳过重复安装" >> $LOG_FILE
    echo "📌 如需重新安装，请删除 $INSTALL_MARKER 文件" >> $LOG_FILE
    echo "✅ 脚本执行完成" >> $LOG_FILE
    exit 0
fi

# 检查自定义文件目录是否存在
if [ -d "$CUSTOM_DIR" ]; then
    echo "✅ 找到自定义文件目录: $CUSTOM_DIR" >> $LOG_FILE
    
    # 检查文件数量
    FILE_COUNT=$(find "$CUSTOM_DIR" -type f 2>/dev/null | wc -l)
    echo "📁 自定义文件数量: $FILE_COUNT 个" >> $LOG_FILE
    
    # 显示前10个文件
    echo "📋 文件列表 (前10个):" >> $LOG_FILE
    find "$CUSTOM_DIR" -type f 2>/dev/null | head -10 | while read file; do
        local filename=$(basename "$file")
        local filesize=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
        echo "  📄 $filename ($filesize)" >> $LOG_FILE
    done
    
    # 使用智能安装管理器
    echo "🚀 启动智能安装管理器..." >> $LOG_FILE
    
    if [ -f "$SMART_SCRIPT" ]; then
        echo "✅ 找到智能安装脚本: $SMART_SCRIPT" >> $LOG_FILE
        
        # 检查执行权限
        if [ ! -x "$SMART_SCRIPT" ]; then
            echo "⚠️ 智能安装脚本不可执行，修复权限..." >> $LOG_FILE
            chmod +x "$SMART_SCRIPT" 2>/dev/null
        fi
        
        if [ -x "$SMART_SCRIPT" ]; then
            echo "✅ 智能安装脚本可执行，开始执行..." >> $LOG_FILE
            
            # 执行智能安装脚本
            sh "$SMART_SCRIPT"
            
            INSTALL_RESULT=$?
            if [ $INSTALL_RESULT -eq 0 ]; then
                echo "✅ 智能安装管理器执行成功" >> $LOG_FILE
                echo "📌 安装结果请查看: /tmp/smart-install.log" >> $LOG_FILE
            else
                echo "⚠️ 智能安装管理器执行失败，退出代码: $INSTALL_RESULT" >> $LOG_FILE
                echo "📌 错误信息请查看: /tmp/smart-install.log" >> $LOG_FILE
            fi
        else
            echo "❌ 无法修复智能安装脚本权限" >> $LOG_FILE
            echo "⚠️ 尝试手动处理文件..." >> $LOG_FILE
            
            # 手动处理文件（失败不中断）
            for file in "$CUSTOM_DIR"/*.ipk "$CUSTOM_DIR"/*.IPK 2>/dev/null; do
                if [ -f "$file" ]; then
                    echo "安装IPK: $(basename "$file")" >> $LOG_FILE
                    opkg install "$file" >> $LOG_FILE 2>&1 || echo "⚠️ IPK安装失败，继续执行..." >> $LOG_FILE
                fi
            done
            
            for script in "$CUSTOM_DIR"/*.sh 2>/dev/null; do
                if [ -f "$script" ]; then
                    echo "执行脚本: $(basename "$script")" >> $LOG_FILE
                    chmod +x "$script" 2>/dev/null
                    sh "$script" >> $LOG_FILE 2>&1 || echo "⚠️ 脚本执行失败，继续执行..." >> $LOG_FILE
                fi
            done
        fi
    else
        echo "❌ 未找到智能安装脚本" >> $LOG_FILE
        echo "⚠️ 尝试手动处理文件（失败不中断）..." >> $LOG_FILE
        
        # 手动处理文件
        for file in "$CUSTOM_DIR"/*.ipk "$CUSTOM_DIR"/*.IPK 2>/dev/null; do
            if [ -f "$file" ]; then
                echo "安装IPK: $(basename "$file")" >> $LOG_FILE
                opkg install "$file" >> $LOG_FILE 2>&1 || echo "⚠️ IPK安装失败，继续执行..." >> $LOG_FILE
            fi
        done
        
        for script in "$CUSTOM_DIR"/*.sh 2>/dev/null; do
            if [ -f "$script" ]; then
                echo "执行脚本: $(basename "$script")" >> $LOG_FILE
                chmod +x "$script" 2>/dev/null
                sh "$script" >> $LOG_FILE 2>&1 || echo "⚠️ 脚本执行失败，继续执行..." >> $LOG_FILE
            fi
        done
    fi
    
    # 创建安装标记
    touch "$INSTALL_MARKER" 2>/dev/null
    if [ -f "$INSTALL_MARKER" ]; then
        echo "✅ 已创建安装标记: $INSTALL_MARKER" >> $LOG_FILE
    else
        echo "⚠️ 无法创建安装标记" >> $LOG_FILE
    fi
else
    echo "❌ 自定义文件目录不存在: $CUSTOM_DIR" >> $LOG_FILE
    echo "📌 跳过自定义文件安装" >> $LOG_FILE
fi

echo "" >> $LOG_FILE
echo "=== 第一次开机脚本执行完成 ===" >> $LOG_FILE
echo "结束时间: $(date)" >> $LOG_FILE

# 删除自身，确保只运行一次
rm -f /etc/uci-defaults/99-custom-files 2>/dev/null

exit 0
EOF
    
    chmod +x "$first_boot_script"
    log "✅ 创建简单的第一次开机脚本: $first_boot_script"
    
    log "🔍 步骤5: 验证文件复制结果"
    local actual_file_count=$(find "$custom_files_dir" -type f 2>/dev/null | wc -l)
    log "📊 目标目录文件数量: $actual_file_count 个"
    
    if [ $actual_file_count -ge $integrate_copied_count ]; then
        log "✅ 文件复制验证通过"
    else
        log "⚠️ 警告: 复制的文件数量 ($actual_file_count) 少于预期 ($integrate_copied_count)"
    fi
    
    log ""
    log "🎉 自定义文件集成完成"
    log "📊 集成统计:"
    log "  📦 IPK文件: $integrate_ipk_count 个"
    log "  📜 脚本文件: $integrate_script_count 个"
    log "    其中 $integrate_priority_script_count 个具有高优先级"
    log "  ⚙️ 配置文件: $integrate_config_count 个"
    log "  📁 其他文件: $integrate_other_count 个"
    log "  📁 子文件夹: $integrate_folder_count 个"
    log "  🇨🇳 中文文件: $integrate_chinese_count 个"
    log "  🔧 修复特性:"
    log "    - 避免第一次开机脚本执行中断"
    log "    - 简化脚本逻辑"
    log "    - 设置 set +e 避免错误中断"
    log "    - 脚本执行后自动删除自身"
    log "  📁 文件夹结构: 支持任意层级子文件夹"
    log "  📍 自定义文件位置: /etc/custom-files/"
    log "  🚀 安装方式: 第一次开机自动安装"
    log "  🔒 文件名策略: 保持原文件名"
    
    if [ $integrate_copied_count -eq 0 ]; then
        log "⚠️ 警告: 自定义文件目录为空"
        log "💡 支持的文件: .sh脚本、.ipk包、.conf配置文件等"
    fi
    
    return 0
}

build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 编译固件（使用OpenWrt官方SDK工具链）==="
    
    log "📋 编译信息:"
    log "  构建目录: $BUILD_DIR"
    log "  设备: $DEVICE"
    log "  版本: $SELECTED_BRANCH"
    log "  配置模式: $CONFIG_MODE"
    log "  编译器目录: $COMPILER_DIR"
    log "  启用缓存: $enable_cache"
    
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
    
    log "🔧 检查预构建编译器调用状态..."
    verify_compiler_files
    
    check_compiler_invocation
    
    local cpu_cores=$(nproc)
    local make_jobs=$cpu_cores
    
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_mem -lt 4096 ]; then
        make_jobs=$((cpu_cores / 2))
        if [ $make_jobs -lt 1 ]; then
            make_jobs=1
        fi
        log "⚠️ 内存较低(${total_mem}MB)，减少并行任务到 $make_jobs"
    fi
    
    log "📝 编译器调用信息:"
    if [ -n "$COMPILER_DIR" ] && [ -d "$COMPILER_DIR" ]; then
        log "  预构建编译器目录: $COMPILER_DIR"
        
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
            
            local version=$("$prebuilt_gcc" --version 2>&1 | head -1)
            log "     GCC版本: $version"
            
            local major_version=$(echo "$version" | grep -o "[0-9]\+" | head -1)
            if [ -n "$major_version" ] && [ "$major_version" -ge 8 ] && [ "$major_version" -le 15 ]; then
                log "  ✅ GCC $major_version.x 版本兼容"
            else
                log "  ⚠️ 编译器版本可能不兼容"
            fi
            
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
    
    log "🚀 开始编译固件，使用 $make_jobs 个并行任务"
    log "💡 编译器调用状态已记录，编译过程中将显示具体调用的编译器"
    
    make -j$make_jobs V=s 2>&1 | tee build.log
    BUILD_EXIT_CODE=${PIPESTATUS[0]}
    
    log "编译退出代码: $BUILD_EXIT_CODE"
    
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        log "✅ 固件编译成功"
        
        log "🔍 编译器调用分析:"
        if [ -f "build.log" ]; then
            local prebuilt_calls=$(grep -c "$COMPILER_DIR" build.log 2>/dev/null || echo "0")
            local total_calls=$(grep -c "gcc\|g++" build.log 2>/dev/null || echo "0")
            
            if [ $prebuilt_calls -gt 0 ]; then
                log "  🎯 预构建编译器调用次数: $prebuilt_calls/$total_calls"
                log "  📌 成功调用了预构建的编译器文件"
                
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
        
        if [ -d "bin/targets" ]; then
            local firmware_count=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
            log "✅ 生成固件文件: $firmware_count 个"
            
            find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
                log "固件: $file ($(du -h "$file" | cut -f1))"
            done
        else
            log "❌ 固件目录不存在"
        fi
    else
        log "❌ 编译失败，退出代码: $BUILD_EXIT_CODE"
        
        if [ -f "build.log" ]; then
            log "=== 编译错误摘要 ==="
            
            local error_count=$(grep -c "Error [0-9]|error:" build.log)
            local warning_count=$(grep -c "Warning\|warning:" build.log)
            
            log "发现 $error_count 个错误，$warning_count 个警告"
            
            if [ $error_count -gt 0 ]; then
                log "前10个错误:"
                grep -i "Error\|error:" build.log | head -10
            fi
            
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
    
    save_env
}

post_build_space_check() {
    log "=== 编译后空间检查 ==="
    
    log "=== 磁盘使用情况 ==="
    df -h
    
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        local firmware_size=$(find "$BUILD_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo "固件文件总大小: $firmware_size"
    fi
    
    local available_space=$(df /mnt --output=avail | tail -1)
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
        
        local firmware_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        local all_files=$(find bin/targets -type f 2>/dev/null | wc -l)
        
        log "固件文件: $firmware_files 个"
        log "所有文件: $all_files 个"
        
        echo "=== 生成的固件文件 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \;
        
        local total_size=0
        while read size; do
            total_size=$((total_size + size))
        done < <(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec stat -c%s {} \; 2>/dev/null)
        
        if [ $total_size -gt 0 ]; then
            local total_size_mb=$((total_size / 1024 / 1024))
            log "固件总大小: ${total_size_mb}MB"
            
            if [ $total_size_mb -lt 5 ]; then
                log "⚠️ 警告: 固件文件可能太小"
            elif [ $total_size_mb -gt 100 ]; then
                log "⚠️ 警告: 固件文件可能太大"
            else
                log "✅ 固件大小正常"
            fi
        fi
        
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

universal_compiler_search() {
    local search_root="${1:-/tmp}"
    local device_name="${2:-unknown}"
    
    log "=== 通用编译器搜索 ==="
    
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}

search_compiler_files_simple() {
    local search_root="${1:-/tmp}"
    local target_platform="${2:-generic}"
    
    log "=== 简单编译器文件搜索 ==="
    
    log "🔍 不再搜索本地编译器，将下载OpenWrt官方SDK"
    return 1
}

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
    echo "=== 自定义文件统计 ===" >> "$source_info_file"
    if [ -n "$CUSTOM_FILES_INTEGRATED" ] && [ "$CUSTOM_FILES_INTEGRATED" = "true" ]; then
        echo "IPK文件: ${CUSTOM_IPK_COUNT:-0} 个" >> "$source_info_file"
        echo "脚本文件: ${CUSTOM_SCRIPT_COUNT:-0} 个" >> "$source_info_file"
        echo "配置文件: ${CUSTOM_CONFIG_COUNT:-0} 个" >> "$source_info_file"
        echo "其他文件: ${CUSTOM_OTHER_COUNT:-0} 个" >> "$source_info_file"
        echo "中文文件: ${CUSTOM_CHINESE_COUNT:-0} 个" >> "$source_info_file"
        echo "优先级脚本: ${CUSTOM_PRIORITY_SCRIPT_COUNT:-0} 个" >> "$source_info_file"
        echo "总文件数: ${CUSTOM_TOTAL_FILES:-0} 个" >> "$source_info_file"
        echo "集成状态: 已集成" >> "$source_info_file"
    else
        echo "自定义文件: 未集成" >> "$source_info_file"
    fi
    
    echo "" >> "$source_info_file"
    echo "=== 目录结构 ===" >> "$source_info_file"
    find . -maxdepth 2 -type d | sort >> "$source_info_file"
    
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

check_custom_files_integration() {
    load_env
    log "=== 检查自定义文件集成结果（简化版）==="
    
    local custom_dir="files/etc/custom-files"
    
    if [ -d "$custom_dir" ]; then
        log "✅ 自定义文件目录存在: $custom_dir"
        
        local total_files=$(find "$custom_dir" -type f 2>/dev/null | wc -l)
        log "📊 总文件数量: $total_files 个"
        
        log "📋 部分文件列表（前10个）:"
        find "$custom_dir" -type f 2>/dev/null | head -10 | while read file; do
            filename=$(basename "$file")
            filesize=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
            log "  📄 $filename ($filesize)"
        done
        
        if [ -f "$custom_dir/smart_install.sh" ]; then
            log "✅ 智能安装脚本存在"
            if [ -x "$custom_dir/smart_install.sh" ]; then
                log "✅ 智能安装脚本可执行"
            else
                log "⚠️ 智能安装脚本不可执行"
            fi
        else
            log "❌ 智能安装脚本不存在"
        fi
        
        return 0
    else
        log "❌ 自定义文件目录不存在: $custom_dir"
        return 1
    fi
}

sync_custom_stats_to_github_env() {
    log "=== 同步自定义文件统计到GitHub环境变量 ==="
    
    if [ -f "$CUSTOM_STATS_FILE" ]; then
        source "$CUSTOM_STATS_FILE" 2>/dev/null || true
        log "📊 从统计文件加载统计: IPK=$CUSTOM_IPK_COUNT, 脚本=$CUSTOM_SCRIPT_COUNT"
    fi
    
    if [ -n "$GITHUB_ENV" ]; then
        echo "CUSTOM_IPK_COUNT=${CUSTOM_IPK_COUNT:-0}" >> $GITHUB_ENV
        echo "CUSTOM_SCRIPT_COUNT=${CUSTOM_SCRIPT_COUNT:-0}" >> $GITHUB_ENV
        echo "CUSTOM_CONFIG_COUNT=${CUSTOM_CONFIG_COUNT:-0}" >> $GITHUB_ENV
        echo "CUSTOM_OTHER_COUNT=${CUSTOM_OTHER_COUNT:-0}" >> $GITHUB_ENV
        echo "CUSTOM_CHINESE_COUNT=${CUSTOM_CHINESE_COUNT:-0}" >> $GITHUB_ENV
        echo "CUSTOM_PRIORITY_SCRIPT_COUNT=${CUSTOM_PRIORITY_SCRIPT_COUNT:-0}" >> $GITHUB_ENV
        echo "CUSTOM_TOTAL_FILES=${CUSTOM_TOTAL_FILES:-0}" >> $GITHUB_ENV
        echo "CUSTOM_FILES_INTEGRATED=${CUSTOM_FILES_INTEGRATED:-false}" >> $GITHUB_ENV
        
        log "✅ 自定义文件统计已同步到GitHub环境变量"
        log "📊 同步统计: IPK=${CUSTOM_IPK_COUNT:-0}, 脚本=${CUSTOM_SCRIPT_COUNT:-0}, 总数=${CUSTOM_TOTAL_FILES:-0}, 集成状态=${CUSTOM_FILES_INTEGRATED:-false}"
    else
        log "⚠️ GITHUB_ENV未设置，无法同步到GitHub环境变量"
    fi
}

# 新增：修复第一次开机脚本的函数
fix_firstboot_script() {
    log "=== 修复第一次开机脚本执行问题 ==="
    
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    local first_boot_dir="files/etc/uci-defaults"
    local first_boot_script="$first_boot_dir/99-custom-files"
    
    if [ -f "$first_boot_script" ]; then
        log "✅ 找到第一次开机脚本: $first_boot_script"
        
        # 备份原始脚本
        cp "$first_boot_script" "$first_boot_script.backup"
        log "✅ 备份原始脚本: $first_boot_script.backup"
        
        # 创建修复版的脚本
        log "🔧 创建修复版的第一次开机脚本..."
        
        cat > "$first_boot_script" << 'EOF'
#!/bin/sh
# 第一次开机脚本 - 修复执行中断问题
# 版本: 修复版

LOG_FILE="/tmp/firstboot-fixed.log"
CUSTOM_DIR="/etc/custom-files"
INSTALL_MARKER="/etc/custom-files-installed"

echo "=== 第一次开机脚本（修复版） ===" > $LOG_FILE
echo "开始时间: $(date)" >> $LOG_FILE
echo "修复特性: 避免执行中断，简化逻辑" >> $LOG_FILE
echo "" >> $LOG_FILE

# 关键修复：设置不因错误而退出
set +e

# 检查是否已经安装过
if [ -f "$INSTALL_MARKER" ]; then
    echo "✅ 检测到已安装标记，跳过安装" >> $LOG_FILE
    echo "💡 标记文件: $INSTALL_MARKER" >> $LOG_FILE
    echo "✅ 脚本执行完成" >> $LOG_FILE
    
    # 删除自身，确保只运行一次
    rm -f /etc/uci-defaults/99-custom-files 2>/dev/null
    echo "🗑️ 已删除脚本自身" >> $LOG_FILE
    exit 0
fi

echo "🔍 检查自定义文件目录..." >> $LOG_FILE
if [ -d "$CUSTOM_DIR" ]; then
    echo "✅ 自定义文件目录存在: $CUSTOM_DIR" >> $LOG_FILE
    
    # 统计文件数量
    FILE_COUNT=$(find "$CUSTOM_DIR" -type f 2>/dev/null | wc -l)
    echo "📊 文件数量: $FILE_COUNT 个" >> $LOG_FILE
    
    # 安装IPK文件（失败不中断）
    echo "" >> $LOG_FILE
    echo "📦 安装IPK文件..." >> $LOG_FILE
    IPK_COUNT=0
    SUCCESS_IPK=0
    
    for ipk_file in "$CUSTOM_DIR"/*.ipk "$CUSTOM_DIR"/*.IPK 2>/dev/null; do
        if [ -f "$ipk_file" ]; then
            IPK_COUNT=$((IPK_COUNT + 1))
            echo "  安装 [$IPK_COUNT]: $(basename "$ipk_file")" >> $LOG_FILE
            
            if opkg install "$ipk_file" >> $LOG_FILE 2>&1; then
                SUCCESS_IPK=$((SUCCESS_IPK + 1))
                echo "    ✅ 安装成功" >> $LOG_FILE
            else
                echo "    ⚠️ 安装失败，继续执行..." >> $LOG_FILE
            fi
        fi
    done
    
    if [ $IPK_COUNT -eq 0 ]; then
        echo "ℹ️ 未找到IPK文件" >> $LOG_FILE
    else
        echo "📊 IPK安装结果: $SUCCESS_IPK/$IPK_COUNT 成功" >> $LOG_FILE
    fi
    
    # 执行脚本文件（失败不中断）
    echo "" >> $LOG_FILE
    echo "📜 执行脚本文件..." >> $LOG_FILE
    SCRIPT_COUNT=0
    SUCCESS_SCRIPT=0
    
    for script_file in "$CUSTOM_DIR"/*.sh 2>/dev/null; do
        if [ -f "$script_file" ]; then
            SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
            echo "  执行 [$SCRIPT_COUNT]: $(basename "$script_file")" >> $LOG_FILE
            
            # 确保有执行权限
            chmod +x "$script_file" 2>/dev/null
            
            if sh "$script_file" >> $LOG_FILE 2>&1; then
                SUCCESS_SCRIPT=$((SUCCESS_SCRIPT + 1))
                echo "    ✅ 执行成功" >> $LOG_FILE
            else
                echo "    ⚠️ 执行失败，继续执行..." >> $LOG_FILE
            fi
        fi
    done
    
    if [ $SCRIPT_COUNT -eq 0 ]; then
        echo "ℹ️ 未找到脚本文件" >> $LOG_FILE
    else
        echo "📊 脚本执行结果: $SUCCESS_SCRIPT/$SCRIPT_COUNT 成功" >> $LOG_FILE
    fi
    
    # 创建安装标记
    echo "" >> $LOG_FILE
    echo "🏷️ 创建安装标记..." >> $LOG_FILE
    if touch "$INSTALL_MARKER" 2>/dev/null; then
        echo "✅ 安装标记已创建: $INSTALL_MARKER" >> $LOG_FILE
        echo "💡 下次启动将跳过安装" >> $LOG_FILE
    else
        echo "⚠️ 无法创建安装标记" >> $LOG_FILE
    fi
else
    echo "❌ 自定义文件目录不存在: $CUSTOM_DIR" >> $LOG_FILE
    echo "📌 跳过自定义文件安装" >> $LOG_FILE
fi

# 删除自身，确保只运行一次
rm -f /etc/uci-defaults/99-custom-files 2>/dev/null
echo "🗑️ 已删除脚本自身" >> $LOG_FILE

echo "" >> $LOG_FILE
echo "=== 第一次开机脚本执行完成 ===" >> $LOG_FILE
echo "结束时间: $(date)" >> $LOG_FILE
echo "📝 详细日志: $LOG_FILE" >> $LOG_FILE

exit 0
EOF
        
        chmod +x "$first_boot_script"
        log "✅ 已创建修复版的第一次开机脚本"
        log "🔧 修复特性:"
        log "  - 设置 set +e 避免错误中断"
        log "  - 简化脚本逻辑"
        log "  - 详细的日志记录"
        log "  - 安装后自动删除脚本"
        log "  - 失败不中断执行"
        
        # 验证脚本
        log "🔍 验证修复后的脚本..."
        if [ -x "$first_boot_script" ]; then
            log "✅ 脚本可执行"
            log "📄 脚本前20行内容:"
            head -20 "$first_boot_script"
        else
            log "❌ 脚本不可执行，修复权限..."
            chmod +x "$first_boot_script"
        fi
    else
        log "⚠️ 第一次开机脚本不存在: $first_boot_script"
        log "💡 将重新创建修复版的脚本"
        
        mkdir -p "$first_boot_dir"
        
        cat > "$first_boot_script" << 'EOF'
#!/bin/sh
# 第一次开机脚本 - 修复执行中断问题
# 版本: 新创建修复版

LOG_FILE="/tmp/firstboot-new.log"
INSTALL_MARKER="/etc/custom-files-installed"

echo "=== 第一次开机脚本（新创建修复版） ===" > $LOG_FILE
echo "开始时间: $(date)" >> $LOG_FILE
echo "" >> $LOG_FILE

# 关键修复：设置不因错误而退出
set +e

# 检查是否已经安装过
if [ -f "$INSTALL_MARKER" ]; then
    echo "✅ 检测到已安装标记，跳过安装" >> $LOG_FILE
    echo "💡 标记文件: $INSTALL_MARKER" >> $LOG_FILE
else
    echo "🔍 未找到安装标记，继续执行..." >> $LOG_FILE
    
    # 检查自定义文件目录
    CUSTOM_DIR="/etc/custom-files"
    if [ -d "$CUSTOM_DIR" ]; then
        echo "✅ 自定义文件目录存在: $CUSTOM_DIR" >> $LOG_FILE
        
        # 简单处理：尝试安装IPK和执行脚本
        for file in "$CUSTOM_DIR"/* 2>/dev/null; do
            if [ -f "$file" ]; then
                FILENAME=$(basename "$file")
                echo "处理文件: $FILENAME" >> $LOG_FILE
                
                # 如果是IPK文件
                if echo "$FILENAME" | grep -qi "\.ipk$"; then
                    echo "  安装IPK..." >> $LOG_FILE
                    opkg install "$file" >> $LOG_FILE 2>&1 || echo "  ⚠️ 安装失败，继续..." >> $LOG_FILE
                fi
                
                # 如果是脚本文件
                if echo "$FILENAME" | grep -qi "\.sh$"; then
                    echo "  执行脚本..." >> $LOG_FILE
                    chmod +x "$file" 2>/dev/null
                    sh "$file" >> $LOG_FILE 2>&1 || echo "  ⚠️ 执行失败，继续..." >> $LOG_FILE
                fi
            fi
        done
        
        # 创建安装标记
        touch "$INSTALL_MARKER" 2>/dev/null && echo "✅ 安装标记已创建" >> $LOG_FILE || echo "⚠️ 无法创建安装标记" >> $LOG_FILE
    else
        echo "❌ 自定义文件目录不存在: $CUSTOM_DIR" >> $LOG_FILE
    fi
fi

# 删除自身，确保只运行一次
rm -f /etc/uci-defaults/99-custom-files 2>/dev/null
echo "🗑️ 已删除脚本自身" >> $LOG_FILE

echo "" >> $LOG_FILE
echo "=== 脚本执行完成 ===" >> $LOG_FILE
echo "结束时间: $(date)" >> $LOG_FILE

exit 0
EOF
        
        chmod +x "$first_boot_script"
        log "✅ 已创建新的修复版第一次开机脚本"
    fi
    
    log "✅ 第一次开机脚本修复完成"
}

main() {
    case $1 in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$2" "$3" "$4"
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
            sync_custom_stats_to_github_env
            ;;
        "pre_build_error_check")
            pre_build_error_check
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
        "check_custom_files_integration")
            check_custom_files_integration
            ;;
        "sync_custom_stats_to_github_env")
            sync_custom_stats_to_github_env
            ;;
        "fix_firstboot_script")
            fix_firstboot_script
            ;;
        *)
            log "❌ 未知命令: $1"
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
            echo "  check_custom_files_integration - 检查自定义文件集成结果"
            echo "  sync_custom_stats_to_github_env - 同步自定义文件统计到GitHub环境变量"
            echo "  fix_firstboot_script - 修复第一次开机脚本执行问题"
            exit 1
            ;;
    esac
}

main "$@"
