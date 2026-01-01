#!/bin/bash
set -e

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

error_analysis() {
    log "=== 🔍 错误分析系统（增强版）==="
    
    BUILD_DIR="${BUILD_DIR:-/mnt/openwrt-build}"
    ANALYSIS_DIR="/tmp/error-analysis"
    REPORT_FILE="$ANALYSIS_DIR/report.txt"
    
    mkdir -p "$ANALYSIS_DIR"
    
    echo "==================================================" > "$REPORT_FILE"
    echo "           🚨 OpenWrt构建错误分析报告           " >> "$REPORT_FILE"
    echo "==================================================" >> "$REPORT_FILE"
    echo "分析时间: $(date)" >> "$REPORT_FILE"
    echo "构建目录: $BUILD_DIR" >> "$REPORT_FILE"
    echo "设备: ${DEVICE:-未知}" >> "$REPORT_FILE"
    echo "目标平台: ${TARGET:-未知}" >> "$REPORT_FILE"
    echo "子目标: ${SUBTARGET:-未知}" >> "$REPORT_FILE"
    echo "版本分支: ${SELECTED_BRANCH:-未知}" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 1. 构建环境信息
    analyze_environment() {
        log "📋 收集构建环境信息..."
        
        echo "=== 构建环境信息 ===" >> "$REPORT_FILE"
        echo "构建目录: $BUILD_DIR" >> "$REPORT_FILE"
        echo "主机系统: $(uname -a)" >> "$REPORT_FILE"
        echo "用户: $(whoami)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "=== 系统资源状态 ===" >> "$REPORT_FILE"
        echo "磁盘空间:" >> "$REPORT_FILE"
        df -h /mnt /tmp /home 2>/dev/null || df -h >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "内存使用:" >> "$REPORT_FILE"
        free -h >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        echo "CPU信息:" >> "$REPORT_FILE"
        echo "核心数: $(nproc)" >> "$REPORT_FILE"
        echo "负载: $(uptime | awk -F'load average:' '{print $2}')" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    }
    
    # 2. 构建结果检查
    analyze_build_result() {
        log "📊 检查构建结果..."
        
        echo "=== 构建结果摘要 ===" >> "$REPORT_FILE"
        if [ -d "$BUILD_DIR/bin/targets" ]; then
            local firmware_count=$(find "$BUILD_DIR/bin/targets" -name '*.bin' -o -name '*.img' 2>/dev/null | wc -l)
            echo "✅ 构建状态: 成功" >> "$REPORT_FILE"
            echo "✅ 生成的固件文件: $firmware_count" >> "$REPORT_FILE"
            if [ $firmware_count -gt 0 ]; then
                echo "生成的固件:" >> "$REPORT_FILE"
                find "$BUILD_DIR/bin/targets" -name "*.bin" -o -name "*.img" 2>/dev/null | head -5 >> "$REPORT_FILE"
            fi
        else
            echo "❌ 构建状态: 失败" >> "$REPORT_FILE"
            echo "❌ 未找到固件输出目录" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    }
    
    # 3. 配置文件分析
    analyze_config_file() {
        log "⚙️  分析配置文件..."
        
        echo "=== 配置状态检查 ===" >> "$REPORT_FILE"
        if [ -f "$BUILD_DIR/.config" ]; then
            local config_size=$(ls -lh "$BUILD_DIR/.config" 2>/dev/null | awk '{print $5}' || echo "未知")
            echo "✅ 配置文件存在 ($config_size)" >> "$REPORT_FILE"
            
            # 统计包数量
            local enabled_pkgs=$(grep "^CONFIG_PACKAGE_.*=y$" "$BUILD_DIR/.config" 2>/dev/null | wc -l)
            local disabled_pkgs=$(grep "^# CONFIG_PACKAGE_.* is not set$" "$BUILD_DIR/.config" 2>/dev/null | wc -l)
            echo "启用的包数量: $enabled_pkgs" >> "$REPORT_FILE"
            echo "禁用的包数量: $disabled_pkgs" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            # C库配置
            echo "=== C库配置状态 ===" >> "$REPORT_FILE"
            if grep -q "CONFIG_USE_MUSL=y" "$BUILD_DIR/.config" 2>/dev/null; then
                echo "✅ C库: musl (现代OpenWrt默认使用)" >> "$REPORT_FILE"
            elif grep -q "CONFIG_USE_GLIBC=y" "$BUILD_DIR/.config" 2>/dev/null; then
                echo "✅ C库: glibc (功能完整的C库)" >> "$REPORT_FILE"
            elif grep -q "CONFIG_USE_UCLIBC=y" "$BUILD_DIR/.config" 2>/dev/null; then
                echo "✅ C库: uclibc (旧版OpenWrt使用)" >> "$REPORT_FILE"
            else
                echo "⚠️ C库: 未明确指定" >> "$REPORT_FILE"
            fi
            echo "" >> "$REPORT_FILE"
            
            # USB配置检查
            echo "=== 关键USB配置状态 ===" >> "$REPORT_FILE"
            local usb_configs=(
                "kmod-usb-core" "kmod-usb2" "kmod-usb3" 
                "kmod-usb-storage" "kmod-usb-dwc3" 
                "kmod-usb-xhci-hcd" "kmod-usb-ehci"
                "kmod-usb-ohci" "kmod-scsi-core"
            )
            
            for config in "${usb_configs[@]}"; do
                if grep -q "CONFIG_PACKAGE_${config}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                    echo "✅ $config: 已启用" >> "$REPORT_FILE"
                else
                    echo "❌ $config: 未启用" >> "$REPORT_FILE"
                fi
            done
            echo "" >> "$REPORT_FILE"
            
            # 平台专用驱动
            if [ -n "$TARGET" ]; then
                echo "=== 平台专用驱动状态 ===" >> "$REPORT_FILE"
                if [ "$TARGET" = "ipq40xx" ]; then
                    echo "🔧 高通IPQ40xx平台专用驱动:" >> "$REPORT_FILE"
                    local qcom_configs=("kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3")
                    for config in "${qcom_configs[@]}"; do
                        if grep -q "CONFIG_PACKAGE_${config}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                            echo "✅ $config: 已启用" >> "$REPORT_FILE"
                        else
                            echo "❌ $config: 未启用" >> "$REPORT_FILE"
                        fi
                    done
                elif [[ "$TARGET" == *"ramips"* ]] && [[ "$SUBTARGET" == *"mt76"* ]]; then
                    echo "🔧 雷凌MT76xx平台专用驱动:" >> "$REPORT_FILE"
                    local mtk_configs=("kmod-usb-xhci-mtk" "kmod-usb-ohci-pci" "kmod-usb2-pci")
                    for config in "${mtk_configs[@]}"; do
                        if grep -q "CONFIG_PACKAGE_${config}=y" "$BUILD_DIR/.config" 2>/dev/null; then
                            echo "✅ $config: 已启用" >> "$REPORT_FILE"
                        else
                            echo "❌ $config: 未启用" >> "$REPORT_FILE"
                        fi
                    done
                fi
                echo "" >> "$REPORT_FILE"
            fi
            
            # 显示前5个被禁用的插件
            echo "=== 前5个被禁用的插件 ===" >> "$REPORT_FILE"
            grep "^# CONFIG_PACKAGE_.* is not set$" "$BUILD_DIR/.config" 2>/dev/null | head -5 | while read line; do
                pkg_name=$(echo $line | sed 's/# CONFIG_PACKAGE_//;s/ is not set//')
                echo "❌ $pkg_name" >> "$REPORT_FILE"
            done
            
        else
            echo "❌ 配置文件不存在" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    }
    
    # 4. 编译器状态分析
    analyze_compiler_status() {
        log "🔧 检查编译器状态..."
        
        echo "=== 编译器文件状态检查 ===" >> "$REPORT_FILE"
        if [ -d "$BUILD_DIR/staging_dir" ]; then
            echo "✅ 编译目录存在: staging_dir" >> "$REPORT_FILE"
            
            # 检查编译器文件
            echo "🔍 检查编译器文件:" >> "$REPORT_FILE"
            find "$BUILD_DIR/staging_dir" -name "*gcc*" -type f -executable 2>/dev/null | head -5 >> "$REPORT_FILE" || echo "  未找到编译器文件" >> "$REPORT_FILE"
            
            # 根据平台检查编译器
            if [ "$TARGET" = "ipq40xx" ]; then
                echo "🔍 检查arm编译器 (IPQ40xx):" >> "$REPORT_FILE"
                find "$BUILD_DIR/staging_dir" -name "arm-openwrt-linux-muslgnueabi-gcc" -type f 2>/dev/null >> "$REPORT_FILE" || echo "  未找到arm编译器" >> "$REPORT_FILE"
            elif [[ "$TARGET" == *"ramips"* ]] && [[ "$SUBTARGET" == *"mt76"* ]]; then
                echo "🔍 检查mipsel编译器 (MT76xx):" >> "$REPORT_FILE"
                find "$BUILD_DIR/staging_dir" -name "mipsel-openwrt-linux-musl-gcc" -type f 2>/dev/null >> "$REPORT_FILE" || echo "  未找到mipsel编译器" >> "$REPORT_FILE"
            fi
            
            # 检查编译器版本
            echo "🔍 检查编译器版本:" >> "$REPORT_FILE"
            find "$BUILD_DIR/staging_dir" -name "*gcc" -type f -executable 2>/dev/null | head -2 | while read compiler; do
                echo "编译器: $compiler" >> "$REPORT_FILE"
                "$compiler" --version 2>&1 | head -1 >> "$REPORT_FILE" 2>/dev/null || echo "  无法获取版本" >> "$REPORT_FILE"
            done
            echo "" >> "$REPORT_FILE"
            
            # 检查头文件目录
            echo "🔍 检查头文件目录:" >> "$REPORT_FILE"
            if [ -d "$BUILD_DIR/staging_dir/host/include" ]; then
                echo "✅ host/include目录存在" >> "$REPORT_FILE"
                local header_count=$(find "$BUILD_DIR/staging_dir/host/include" -name "*.h" 2>/dev/null | wc -l)
                echo "  头文件数量: $header_count" >> "$REPORT_FILE"
            else
                echo "❌ host/include目录不存在" >> "$REPORT_FILE"
            fi
            
            # 检查工具链
            echo "🔍 检查工具链状态:" >> "$REPORT_FILE"
            local toolchain_dir=$(find "$BUILD_DIR/staging_dir" -name "toolchain-*" -type d 2>/dev/null | head -1)
            if [ -n "$toolchain_dir" ]; then
                echo "✅ 工具链目录: $(basename "$toolchain_dir")" >> "$REPORT_FILE"
                
                # 检查stamp目录
                local stamp_dir="$toolchain_dir/stamp"
                if [ -d "$stamp_dir" ]; then
                    echo "✅ stamp目录存在" >> "$REPORT_FILE"
                    echo "  标记文件数量: $(find "$stamp_dir" -type f 2>/dev/null | wc -l)" >> "$REPORT_FILE"
                else
                    echo "❌ stamp目录不存在" >> "$REPORT_FILE"
                fi
            else
                echo "❌ 未找到工具链目录" >> "$REPORT_FILE"
            fi
            
        else
            echo "❌ 编译目录不存在" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    }
    
    # 5. 构建日志分析
    analyze_build_log() {
        log "📝 分析构建日志..."
        
        echo "=== 关键错误检查 ===" >> "$REPORT_FILE"
        if [ -f "$BUILD_DIR/build.log" ]; then
            local log_size=$(ls -lh "$BUILD_DIR/build.log" 2>/dev/null | awk '{print $5}' || echo "未知")
            echo "检查日志文件: build.log ($log_size)" >> "$REPORT_FILE"
            
            # 错误统计
            local error_count=$(grep -c -i "error" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            local warning_count=$(grep -c -i "warning" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            local failed_count=$(grep -c -i "failed" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
            
            echo "日志统计: 错误=$error_count, 警告=$warning_count, 失败=$failed_count" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            # 提取各类错误
            local error_patterns=(
                "❌ 编译错误:|error:|Error [0-9]"
                "❌ Makefile错误:|make.*Error|Makefile.*failed|recipe for target"
                "❌ 依赖错误:|depends on|missing dependencies"
                "❌ 文件缺失:|No such file|file not found|cannot find"
                "❌ 内存错误:|out of memory|Killed process|oom"
                "❌ 权限错误:|Permission denied|operation not permitted"
                "❌ 编译器错误:|gcc: error|ld: error|binutils"
                "❌ 头文件错误:|stdc-predef.h|host/include|include.*not found"
                "❌ 工具链错误:|toolchain/Makefile|stamp/.toolchain_compile"
                "❌ GDB错误:|_GL_ATTRIBUTE_FORMAT_PRINTF|gdb.*failed"
            )
            
            for pattern in "${error_patterns[@]}"; do
                IFS='|' read -r category_name search_pattern <<< "$pattern"
                echo "$category_name" >> "$REPORT_FILE"
                grep -i -E "$search_pattern" "$BUILD_DIR/build.log" 2>/dev/null | head -5 >> "$REPORT_FILE" || echo "  无相关错误" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            done
            
            # 特别检查关键错误
            echo "🚨 关键错误详细分析:" >> "$REPORT_FILE"
            
            # 检查toolchain/Makefile:93错误
            if grep -q "toolchain/Makefile.*93" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 发现 toolchain/Makefile:93 错误" >> "$REPORT_FILE"
                echo "💡 解决方案: 创建stamp目录和标记文件" >> "$REPORT_FILE"
                echo "  mkdir -p staging_dir/toolchain-*/stamp" >> "$REPORT_FILE"
                echo "  touch staging_dir/toolchain-*/stamp/.toolchain_compile" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            # 检查GDB错误
            if grep -q "_GL_ATTRIBUTE_FORMAT_PRINTF" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "❌ 发现 GDB _GL_ATTRIBUTE_FORMAT_PRINTF 错误" >> "$REPORT_FILE"
                echo "💡 解决方案: 修复gdbsupport/common-defs.h第111行" >> "$REPORT_FILE"
                echo "  sed -i '111s/#define ATTRIBUTE_PRINTF _GL_ATTRIBUTE_FORMAT_PRINTF/#define ATTRIBUTE_PRINTF(format_idx, arg_idx) __attribute__ ((__format__ (__printf__, format_idx, arg_idx)))/' gdbsupport/common-defs.h" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            # 显示最后50行日志
            if [ "$error_count" -gt 0 ]; then
                echo "📄 构建日志最后50行:" >> "$REPORT_FILE"
                tail -50 "$BUILD_DIR/build.log" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
        else
            echo "未找到构建日志文件 build.log" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    }
    
    # 6. 版本特定问题分析
    analyze_version_specific_issues() {
        log "🔍 分析版本特定问题..."
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            echo "=== 23.05版本特定问题分析 ===" >> "$REPORT_FILE"
            echo "🔧 OpenWrt 23.05 常见问题:" >> "$REPORT_FILE"
            echo "1. 编译器版本: GCC 11.3.0" >> "$REPORT_FILE"
            echo "2. 内核版本: Linux 5.15" >> "$REPORT_FILE"
            echo "3. GDB编译错误: _GL_ATTRIBUTE_FORMAT_PRINTF" >> "$REPORT_FILE"
            echo "4. 工具链构建错误: toolchain/Makefile:93" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
            
            echo "🛠️ 解决方案:" >> "$REPORT_FILE"
            echo "1. 单独编译工具链: make toolchain/install -j2 V=s" >> "$REPORT_FILE"
            echo "2. 修复GDB错误: 修改common-defs.h第111行" >> "$REPORT_FILE"
            echo "3. 创建stamp标记文件" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        elif [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            echo "=== 21.02版本特定问题分析 ===" >> "$REPORT_FILE"
            echo "🔧 OpenWrt 21.02 特点:" >> "$REPORT_FILE"
            echo "1. 编译器版本: GCC 8.4.0" >> "$REPORT_FILE"
            echo "2. 内核版本: Linux 5.4" >> "$REPORT_FILE"
            echo "3. 相对稳定，问题较少" >> "$REPORT_FILE"
            echo "" >> "$REPORT_FILE"
        fi
    }
    
    # 7. 综合修复建议
    generate_fix_suggestions() {
        log "💡 生成修复建议..."
        
        echo "=== 综合修复建议 ===" >> "$REPORT_FILE"
        
        # 基本修复步骤
        echo "🛠️ 基本修复步骤:" >> "$REPORT_FILE"
        echo "1. 🔄 重新运行构建: cd $BUILD_DIR && make -j2 V=s" >> "$REPORT_FILE"
        echo "2. 🧹 清理构建目录: make clean" >> "$REPORT_FILE"
        echo "3. 📦 更新feeds: ./scripts/feeds update -a && ./scripts/feeds install -a" >> "$REPORT_FILE"
        echo "4. ⚙️ 同步配置: make defconfig" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # 根据问题类型给出建议
        echo "🎯 针对性修复:" >> "$REPORT_FILE"
        
        # 检查是否有USB配置问题
        if [ -f "$BUILD_DIR/.config" ]; then
            local missing_usb=$(grep -c "CONFIG_PACKAGE_kmod-usb.*=y" "$BUILD_DIR/.config" 2>/dev/null || echo "0")
            if [ "$missing_usb" -lt 5 ]; then
                echo "🔌 USB驱动不足: 建议启用更多USB驱动" >> "$REPORT_FILE"
                echo "  运行: make menuconfig" >> "$REPORT_FILE"
                echo "  定位到: Kernel modules -> USB Support" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
        fi
        
        # 检查是否有编译错误
        if [ -f "$BUILD_DIR/build.log" ]; then
            if grep -q "toolchain/Makefile" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "🔧 工具链构建失败:" >> "$REPORT_FILE"
                echo "  修复命令:" >> "$REPORT_FILE"
                echo "  TOOLCHAIN_DIR=\$(find $BUILD_DIR/staging_dir -name 'toolchain-*' -type d | head -1)" >> "$REPORT_FILE"
                echo "  mkdir -p \"\$TOOLCHAIN_DIR/stamp\"" >> "$REPORT_FILE"
                echo "  echo '修复标记' > \"\$TOOLCHAIN_DIR/stamp/.toolchain_compile\"" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
            
            if grep -q "out of memory\|Killed process" "$BUILD_DIR/build.log" 2>/dev/null; then
                echo "💾 内存不足:" >> "$REPORT_FILE"
                echo "  解决方案:" >> "$REPORT_FILE"
                echo "  1. 减少并行任务: make -j1 V=s" >> "$REPORT_FILE"
                echo "  2. 增加交换空间" >> "$REPORT_FILE"
                echo "  3. 使用更高内存的设备" >> "$REPORT_FILE"
                echo "" >> "$REPORT_FILE"
            fi
        fi
        
        # 高级修复选项
        echo "🚀 高级修复选项:" >> "$REPORT_FILE"
        echo "1. 单独编译工具链: make toolchain/compile -j2 V=s" >> "$REPORT_FILE"
        echo "2. 修复头文件问题: mkdir -p $BUILD_DIR/staging_dir/host/include" >> "$REPORT_FILE"
        echo "3. 修复libtool: cp /usr/share/aclocal/libtool.m4 $BUILD_DIR/staging_dir/host/share/aclocal/" >> "$REPORT_FILE"
        echo "4. 禁用GDB编译: echo '# CONFIG_PACKAGE_gdb is not set' >> .config" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # 检查是否需要安装依赖
        echo "📦 系统依赖检查:" >> "$REPORT_FILE"
        echo "建议安装以下包:" >> "$REPORT_FILE"
        echo "  sudo apt-get install build-essential libncurses5-dev gawk git libssl-dev gettext zlib1g-dev swig unzip time xsltproc python3 python3-setuptools rsync wget" >> "$REPORT_FILE"
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            echo "  sudo apt-get install libtool autoconf automake libltdl-dev pkg-config gettext" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
    }
    
    # 8. 生成摘要报告
    generate_summary() {
        log "📋 生成分析摘要..."
        
        echo "==================================================" >> "$REPORT_FILE"
        echo "                    📊 分析摘要                  " >> "$REPORT_FILE"
        echo "==================================================" >> "$REPORT_FILE"
        
        # 收集统计信息
        local firmware_exists=0
        local has_build_log=0
        local error_count=0
        local config_exists=0
        
        if [ -d "$BUILD_DIR/bin/targets" ]; then
            firmware_exists=1
        fi
        
        if [ -f "$BUILD_DIR/build.log" ]; then
            has_build_log=1
            error_count=$(grep -c -i "error" "$BUILD_DIR/build.log" 2>/dev/null || echo "0")
        fi
        
        if [ -f "$BUILD_DIR/.config" ]; then
            config_exists=1
        fi
        
        echo "✅ 构建目录: $BUILD_DIR" >> "$REPORT_FILE"
        echo "✅ 配置文件: $(if [ $config_exists -eq 1 ]; then echo '存在'; else echo '缺失'; fi)" >> "$REPORT_FILE"
        echo "✅ 构建日志: $(if [ $has_build_log -eq 1 ]; then echo '存在 (错误: '$error_count')'; else echo '缺失'; fi)" >> "$REPORT_FILE"
        echo "✅ 固件生成: $(if [ $firmware_exists -eq 1 ]; then echo '成功'; else echo '失败'; fi)" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # 状态评估
        echo "📈 构建状态评估:" >> "$REPORT_FILE"
        if [ $firmware_exists -eq 1 ]; then
            echo "🎉 状态: 构建成功！" >> "$REPORT_FILE"
            echo "💡 建议: 固件已生成，可以刷机使用" >> "$REPORT_FILE"
        elif [ $error_count -eq 0 ] && [ $config_exists -eq 1 ]; then
            echo "⏳ 状态: 构建进行中或尚未开始" >> "$REPORT_FILE"
            echo "💡 建议: 运行 make -j2 V=s 开始构建" >> "$REPORT_FILE"
        elif [ $error_count -lt 10 ]; then
            echo "⚠️  状态: 轻微问题" >> "$REPORT_FILE"
            echo "💡 建议: 根据上方建议修复后重试" >> "$REPORT_FILE"
        elif [ $error_count -lt 50 ]; then
            echo "⚠️  状态: 中等问题" >> "$REPORT_FILE"
            echo "💡 建议: 需要针对性修复" >> "$REPORT_FILE"
        else
            echo "🚨 状态: 严重问题" >> "$REPORT_FILE"
            echo "💡 建议: 可能需要从头开始" >> "$REPORT_FILE"
        fi
        echo "" >> "$REPORT_FILE"
        
        # 快速行动指南
        echo "🚀 快速行动指南:" >> "$REPORT_FILE"
        if [ $firmware_exists -eq 0 ] && [ $error_count -gt 0 ]; then
            echo "1. 查看上方错误信息" >> "$REPORT_FILE"
            echo "2. 执行对应修复方案" >> "$REPORT_FILE"
            echo "3. 重新编译: cd $BUILD_DIR && make -j2 V=s" >> "$REPORT_FILE"
        elif [ $firmware_exists -eq 1 ]; then
            echo "1. 固件位置: $BUILD_DIR/bin/targets/" >> "$REPORT_FILE"
            echo "2. 准备刷机工具" >> "$REPORT_FILE"
            echo "3. 备份原系统配置" >> "$REPORT_FILE"
        else
            echo "1. 检查配置: make menuconfig" >> "$REPORT_FILE"
            echo "2. 开始编译: make -j2 V=s" >> "$REPORT_FILE"
            echo "3. 监控进度: tail -f build.log" >> "$REPORT_FILE"
        fi
        echo "==================================================" >> "$REPORT_FILE"
    }
    
    # 执行所有分析步骤
    analyze_environment
    analyze_build_result
    analyze_config_file
    analyze_compiler_status
    analyze_build_log
    analyze_version_specific_issues
    generate_fix_suggestions
    generate_summary
    
    # 输出报告
    log "📄 显示错误分析报告..."
    echo ""
    cat "$REPORT_FILE"
    echo ""
    
    # 保存报告副本
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/tmp/openwrt-error-analysis-$timestamp.txt"
    cp "$REPORT_FILE" "$backup_file"
    
    log "✅ 错误分析完成"
    log "📁 详细报告保存到: $backup_file"
    log "📁 临时报告位置: $REPORT_FILE"
    
    # 返回状态码
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        return 0  # 构建成功
    else
        return 1  # 构建失败
    fi
}

# 主执行
if [ "$0" = "$BASH_SOURCE" ] || [ -z "$BASH_SOURCE" ]; then
    error_analysis
    exit $?
fi
