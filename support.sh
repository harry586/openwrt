#!/bin/bash
# /support.sh
# 设备支持系统配置文件 v2.5 - 极简竖排格式

# ==================== 配置文件路径 ====================
CONFIG_BASE_DIR="firmware-config/config"

# ==================== 设备数据库 ====================
# 竖排格式设备定义 - 用户只需填写以下三行内容

declare -A DEVICES=(
    # ================ 用户填写区域开始 ================
    # 添加新设备的格式（复制以下三行，修改值即可）：
    # [设备名称]=
    # "显示名称"
    # "平台"
    # "设备型号"
    
    # 示例设备1: ASUS RT-AC42U/ACRH17
    [ac42u]=
    "ASUS RT-AC42U/ACRH17"
    "ipq40xx"
    "asus_rt-ac42u"
    
    # 示例设备2: 中国移动 RAX3000M
    [cmcc_rax3000m]=
    "中国移动 RAX3000M"
    "mediatek"
    "cmcc_rax3000m"
    
    # 示例设备3: Netgear WNDR3800
    [netgear_3800]=
    "Netgear WNDR3800"
    "ath79"
    "netgear_wndr3800"
    
    # ================ 用户填写区域结束 ================
)

# ==================== SDK URL 数据库 ====================
declare -A SDK_URLS=(
    # OpenWrt 23.05 SDK
    [ipq40xx-generic-23.05]="https://downloads.openwrt.org/releases/23.05.3/targets/ipq40xx/generic/openwrt-sdk-23.05.3-ipq40xx-generic_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
    [mediatek-mt7981-23.05]="https://downloads.openwrt.org/releases/23.05.3/targets/mediatek/mt7981/openwrt-sdk-23.05.3-mediatek-mt7981_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    [ramips-mt7621-23.05]="https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt7621/openwrt-sdk-23.05.3-ramips-mt7621_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    [ramips-mt76x8-23.05]="https://downloads.openwrt.org/releases/23.05.3/targets/ramips/mt76x8/openwrt-sdk-23.05.3-ramips-mt76x8_gcc-12.3.0_musl_eabi.Linux-x86_64.tar.xz"
    [ath79-generic-23.05]="https://downloads.openwrt.org/releases/23.05.3/targets/ath79/generic/openwrt-sdk-23.05.3-ath79-generic_gcc-12.3.0_musl.Linux-x86_64.tar.xz"
    
    # OpenWrt 21.02 SDK
    [ipq40xx-generic-21.02]="https://downloads.openwrt.org/releases/21.02.7/targets/ipq40xx/generic/openwrt-sdk-21.02.7-ipq40xx-generic_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
    [ramips-mt7621-21.02]="https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt7621/openwrt-sdk-21.02.7-ramips-mt7621_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
    [ramips-mt76x8-21.02]="https://downloads.openwrt.org/releases/21.02.7/targets/ramips/mt76x8/openwrt-sdk-21.02.7-ramips-mt76x8_gcc-8.4.0_musl_eabi.Linux-x86_64.tar.xz"
    [ath79-generic-21.02]="https://downloads.openwrt.org/releases/21.02.7/targets/ath79/generic/openwrt-sdk-21.02.7-ath79-generic_gcc-8.4.0_musl.Linux-x86_64.tar.xz"
)

# ==================== 设备信息处理函数 ====================
# 处理竖排格式的设备信息
process_device_info() {
    local device_name="$1"
    local raw_info="${DEVICES[$device_name]}"
    
    if [ -z "$raw_info" ]; then
        echo ""
        return 1
    fi
    
    # 解析竖排格式：每行一个参数
    IFS=$'\n' read -r -d '' -a lines <<< "$raw_info"
    
    if [ ${#lines[@]} -lt 3 ]; then
        echo ""
        return 1
    fi
    
    local display_name="${lines[0]//\"/}"
    local platform="${lines[1]//\"/}"
    local device_model="${lines[2]//\"/}"
    
    # 根据平台自动设置子平台
    local subtarget="generic"
    case "$platform" in
        "ipq40xx") subtarget="generic" ;;
        "mediatek") 
            if [[ "$device_model" == *mt7981* ]]; then
                subtarget="mt7981"
            else
                subtarget="generic"
            fi
            ;;
        "ramips") 
            if [[ "$device_model" == *mt7621* ]]; then
                subtarget="mt7621"
            else
                subtarget="mt76x8"
            fi
            ;;
        "ath79") subtarget="generic" ;;
    esac
    
    # SDK版本默认为23.05
    local sdk_version="gcc-12.3.0"
    
    echo "$display_name|$platform|$subtarget|$device_model|$sdk_version"
}

# ==================== 设备配置函数 ====================
# 获取所有支持的设备列表
get_all_devices() {
    echo "${!DEVICES[@]}" | tr ' ' '\n' | sort
}

# 获取设备完整信息
get_device_info() {
    local device_name="$1"
    process_device_info "$device_name"
}

# 获取设备配置
get_device_config() {
    local device_name="$1"
    local info=$(get_device_info "$device_name")
    
    if [ -z "$info" ]; then
        echo "ipq40xx generic unknown"
        return 1
    fi
    
    IFS='|' read -r display_name platform subtarget device_model sdk_version <<< "$info"
    echo "$platform $subtarget $device_model"
}

# 获取设备特定字段
get_device_field() {
    local device_name="$1"
    local field="$2"
    
    local info=$(get_device_info "$device_name")
    if [ -z "$info" ]; then
        echo ""
        return 1
    fi
    
    IFS='|' read -r display_name platform subtarget device_model sdk_version <<< "$info"
    
    case "$field" in
        "display_name") echo "$display_name" ;;
        "platform") echo "$platform" ;;
        "subtarget") echo "$subtarget" ;;
        "device_model") echo "$device_model" ;;
        "sdk_version") echo "$sdk_version" ;;
        *) echo "" ;;
    esac
}

# 获取设备描述
get_device_description() {
    local device_name="$1"
    
    local display_name=$(get_device_field "$device_name" "display_name")
    local platform=$(get_device_field "$device_name" "platform")
    
    echo "$display_name ($platform平台)"
}

# 获取设备固件名称
get_device_firmware_name() {
    local device_name="$1"
    local version="$2"
    
    local platform=$(get_device_field "$device_name" "platform")
    local subtarget=$(get_device_field "$device_name" "subtarget")
    local device_model=$(get_device_field "$device_name" "device_model")
    
    if [ "$version" = "21.02" ]; then
        echo "immortalwrt-21.02.7-$platform-$subtarget-$device_model-squashfs-sysupgrade.bin"
    else
        echo "immortalwrt-$platform-$subtarget-$device_model-squashfs-sysupgrade.bin"
    fi
}

# 获取SDK URL
get_sdk_url() {
    local device_name="$1"
    local version="$2"
    
    local platform=$(get_device_field "$device_name" "platform")
    local subtarget=$(get_device_field "$device_name" "subtarget")
    
    # 版本映射
    local version_key=""
    if [ "$version" = "23.05" ] || [ "$version" = "openwrt-23.05" ]; then
        version_key="23.05"
    else
        version_key="21.02"
    fi
    
    # 构建SDK key
    local sdk_key="$platform-$subtarget-$version_key"
    
    # 直接查找
    if [ -n "${SDK_URLS[$sdk_key]}" ]; then
        echo "${SDK_URLS[$sdk_key]}"
        return 0
    fi
    
    # 尝试通用查找
    local alt_key="$platform-generic-$version_key"
    if [ -n "${SDK_URLS[$alt_key]}" ]; then
        echo "${SDK_URLS[$alt_key]}"
        return 0
    fi
    
    echo ""
    return 1
}

# 获取设备配置目录
get_device_config_dir() {
    local device_name="$1"
    local platform=$(get_device_field "$device_name" "platform")
    local subtarget=$(get_device_field "$device_name" "subtarget")
    
    echo "$platform/$subtarget"
}

# 获取设备配置文件名
get_device_config_file() {
    local device_name="$1"
    
    local device_config="$CONFIG_BASE_DIR/devices/$device_name.config"
    if [ -f "$device_config" ]; then
        echo "$device_config"
    else
        echo ""
    fi
}

# ==================== 配置合并函数 ====================
# 获取配置文件列表
get_device_config_files() {
    local device_name="$1"
    local config_mode="$2"
    
    local config_files=""
    
    # 基础配置
    if [ "$config_mode" = "base" ]; then
        config_files="$CONFIG_BASE_DIR/base.config"
    else
        config_files="$CONFIG_BASE_DIR/normal.config"
    fi
    
    # 通用USB配置
    config_files="$config_files $CONFIG_BASE_DIR/usb-generic.config"
    
    # 检查设备专用配置
    local device_config=$(get_device_config_file "$device_name")
    if [ -n "$device_config" ]; then
        config_files="$config_files $device_config"
    fi
    
    # 添加平台配置
    local platform=$(get_device_field "$device_name" "platform")
    local platform_config="$CONFIG_BASE_DIR/platforms/$platform.config"
    if [ -f "$platform_config" ]; then
        config_files="$config_files $platform_config"
    fi
    
    echo "$config_files"
}

# 合并配置文件
merge_config_files() {
    local config_files="$1"
    local output_file="$2"
    
    # 创建临时文件
    local temp_file=$(mktemp)
    
    # 添加头部信息
    echo "# ==================== 合并的配置文件 ====================" > "$temp_file"
    echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$temp_file"
    echo "# 配置文件来源:" >> "$temp_file"
    for config_file in $config_files; do
        if [ -f "$config_file" ]; then
            echo "#   - $(basename "$config_file")" >> "$temp_file"
        fi
    done
    echo "" >> "$temp_file"
    
    # 合并所有配置文件，去重并修复格式
    for config_file in $config_files; do
        if [ -f "$config_file" ]; then
            echo "" >> "$temp_file"
            echo "# ===== $(basename "$config_file") =====" >> "$temp_file"
            cat "$config_file" >> "$temp_file"
        fi
    done
    
    # 去重和格式修复
    grep -v "^#" "$temp_file" | sort -u | sed '/^$/d' > "${temp_file}.clean"
    
    # 重新组合文件
    echo "# ==================== 最终配置 ====================" > "$output_file"
    echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
    echo "" >> "$output_file"
    cat "${temp_file}.clean" >> "$output_file"
    
    rm -f "$temp_file" "${temp_file}.clean"
}

# 主要配置生成函数
generate_merged_config() {
    local device_name="$1"
    local config_mode="$2"
    local extra_packages="$3"
    local output_file="$4"
    
    # 获取设备配置信息
    local info=$(get_device_info "$device_name")
    if [ -z "$info" ]; then
        echo "❌ 错误: 设备 '$device_name' 未定义"
        return 1
    fi
    
    IFS='|' read -r display_name platform subtarget device_model sdk_version <<< "$info"
    
    # 创建基础配置
    local temp_file=$(mktemp)
    echo "# ==================== 基础目标配置 ====================" > "$temp_file"
    echo "# 设备: $device_name" >> "$temp_file"
    echo "# 显示名称: $display_name" >> "$temp_file"
    echo "# 平台: $platform, 子平台: $subtarget, 设备型号: $device_model" >> "$temp_file"
    echo "" >> "$temp_file"
    
    # 目标配置
    echo "CONFIG_TARGET_${platform}=y" >> "$temp_file"
    echo "CONFIG_TARGET_${platform}_${subtarget}=y" >> "$temp_file"
    echo "CONFIG_TARGET_${platform}_${subtarget}_DEVICE_${device_model}=y" >> "$temp_file"
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> "$temp_file"
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> "$temp_file"
    echo "" >> "$temp_file"
    
    # 获取配置文件列表并合并
    local config_files=$(get_device_config_files "$device_name" "$config_mode")
    merge_config_files "$config_files" "${temp_file}.merged"
    
    # 合并基础配置和文件配置
    cat "${temp_file}.merged" >> "$temp_file"
    
    # 处理额外包
    if [ -n "$extra_packages" ]; then
        echo "" >> "$temp_file"
        echo "# ==================== 额外包配置 ====================" >> "$temp_file"
        echo "# 额外包字符串: $extra_packages" >> "$temp_file"
        
        IFS=';' read -ra EXTRA_PKGS <<< "$extra_packages"
        for pkg_cmd in "${EXTRA_PKGS[@]}"; do
            if [ -n "$pkg_cmd" ]; then
                pkg_cmd_clean=$(echo "$pkg_cmd" | xargs)
                if [[ "$pkg_cmd_clean" == +* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    echo "CONFIG_PACKAGE_${pkg_name}=y" >> "$temp_file"
                elif [[ "$pkg_cmd_clean" == -* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> "$temp_file"
                else
                    echo "CONFIG_PACKAGE_${pkg_cmd_clean}=y" >> "$temp_file"
                fi
            fi
        done
    fi
    
    # 最终去重和排序
    grep -v "^#" "$temp_file" | sort -u | sed '/^$/d' > "${temp_file}.final"
    
    # 生成最终文件
    echo "# ==================== OpenWrt 配置文件 ====================" > "$output_file"
    echo "# 设备: $device_name" >> "$output_file"
    echo "# 显示名称: $display_name" >> "$output_file"
    echo "# 平台: $platform/$subtarget" >> "$output_file"
    echo "# 设备型号: $device_model" >> "$output_file"
    echo "# 配置模式: $config_mode" >> "$output_file"
    echo "# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$output_file"
    echo "" >> "$output_file"
    cat "${temp_file}.final" >> "$output_file"
    
    rm -f "$temp_file" "${temp_file}.merged" "${temp_file}.final"
    
    echo "✅ 配置文件已生成: $output_file"
    echo "📊 配置行数: $(wc -l < "$output_file")"
    return 0
}

# ==================== 显示函数 ====================
# 显示所有支持的设备
show_all_devices() {
    echo ""
    echo "📱 支持的设备列表:"
    echo "=================="
    echo ""
    
    printf "%-15s %-30s %-15s %-25s\n" \
        "设备代码" "显示名称" "平台" "设备型号"
    echo "----------------------------------------------------------------"
    
    for device in $(get_all_devices); do
        local info=$(get_device_info "$device")
        if [ -n "$info" ]; then
            IFS='|' read -r display_name platform subtarget device_model sdk_version <<< "$info"
            printf "%-15s %-30s %-15s %-25s\n" \
                "$device" "$display_name" "$platform" "$device_model"
        fi
    done
    
    echo ""
    echo "💡 使用方法:"
    echo "  1. 在构建工作流中选择设备代码即可"
    echo "  2. 添加新设备只需复制示例格式，填写三行信息"
}

# ==================== 测试函数 ====================
test_support_functions() {
    echo "🧪 设备支持系统测试:"
    echo "=================="
    
    for device in $(get_all_devices); do
        echo ""
        echo "📱 测试设备: $device"
        local info=$(get_device_info "$device")
        if [ -n "$info" ]; then
            IFS='|' read -r display_name platform subtarget device_model sdk_version <<< "$info"
            echo "  📝 显示名称: $display_name"
            echo "  🖥️  平台: $platform"
            echo "  🎯 子平台: $subtarget"
            echo "  📟 设备型号: $device_model"
            echo "  ⚙️  SDK版本: $sdk_version"
            echo "  🔗 23.05 SDK URL: $(get_sdk_url "$device" "23.05")"
            echo "  🔗 21.02 SDK URL: $(get_sdk_url "$device" "21.02")"
        else
            echo "  ❌ 设备信息获取失败"
        fi
    done
    
    echo ""
    echo "✅ 设备支持系统测试完成"
}

# ==================== 主函数 ====================
# 如果直接运行此脚本，显示帮助信息
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "设备支持系统 v2.5 - 极简竖排格式"
    echo "=================================="
    echo "🔧 主要特性:"
    echo "  - 极简竖排格式，只需填写三行信息"
    echo "  - 自动生成子平台和SDK信息"
    echo "  - 完整的SDK URL数据库"
    echo "  - 自动配置合并"
    echo ""
    
    case "${1:-}" in
        "list")
            show_all_devices
            ;;
        "test")
            test_support_functions
            ;;
        "generate")
            if [ $# -lt 3 ]; then
                echo "用法: $0 generate <设备名> <配置模式> [额外包] [输出文件]"
                echo "示例: $0 generate ac42u normal '+luci-app-ddns' config.txt"
            else
                local device="$2"
                local mode="$3"
                local extra="${4:-}"
                local output="${5:-config.test}"
                generate_merged_config "$device" "$mode" "$extra" "$output"
            fi
            ;;
        *)
            show_all_devices
            echo ""
            echo "🔧 可用命令:"
            echo "  $0 list                     # 显示所有设备列表"
            echo "  $0 test                     # 测试所有函数"
            echo "  $0 generate <设备> <模式> [额外包] [输出文件] # 生成配置文件"
            echo ""
            echo "📚 添加新设备格式:"
            echo "  [设备代码]="
            echo "  \"显示名称\""
            echo "  \"平台\""
            echo "  \"设备型号\""
            ;;
    esac
fi
