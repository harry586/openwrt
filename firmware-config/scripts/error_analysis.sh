#!/bin/bash
set -e

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

# 分析自定义文件安装问题
analyze_custom_files_issue() {
    log "=== 自定义文件安装问题分析 ==="
    
    # 检查常见问题
    log "🔍 检查常见问题..."
    
    # 1. 检查环境变量
    log "1. 检查环境变量:"
    if [ -f "/mnt/openwrt-build/build_env.sh" ]; then
        source "/mnt/openwrt-build/build_env.sh"
        echo "  ✅ 环境文件存在"
        echo "  📊 CUSTOM_FILES_INTEGRATED: ${CUSTOM_FILES_INTEGRATED:-未设置}"
        echo "  📦 CUSTOM_IPK_COUNT: ${CUSTOM_IPK_COUNT:-未设置}"
        echo "  📜 CUSTOM_SCRIPT_COUNT: ${CUSTOM_SCRIPT_COUNT:-未设置}"
    else
        echo "  ❌ 环境文件不存在"
    fi
    
    # 2. 检查自定义文件目录
    log "2. 检查自定义文件目录:"
    if [ -d "/mnt/openwrt-build/files/etc/custom-files" ]; then
        local file_count=$(find "/mnt/openwrt-build/files/etc/custom-files" -type f 2>/dev/null | wc -l)
        echo "  ✅ 自定义文件目录存在"
        echo "  📊 文件数量: $file_count 个"
        
        # 检查是否有优先级前缀
        local priority_files=$(find "/mnt/openwrt-build/files/etc/custom-files" -name "[0-9]*_*" 2>/dev/null | wc -l)
        echo "  🔢 优先级前缀文件: $priority_files 个"
    else
        echo "  ❌ 自定义文件目录不存在"
    fi
    
    # 3. 检查智能安装脚本
    log "3. 检查智能安装脚本:"
    local smart_script="/mnt/openwrt-build/files/etc/custom-files/smart_install.sh"
    if [ -f "$smart_script" ]; then
        echo "  ✅ 智能安装脚本存在"
        if [ -x "$smart_script" ]; then
            echo "  ✅ 脚本可执行"
        else
            echo "  ⚠️ 脚本不可执行"
        fi
    else
        echo "  ❌ 智能安装脚本不存在"
    fi
    
    # 4. 检查第一次开机脚本
    log "4. 检查第一次开机脚本:"
    local first_boot_script="/mnt/openwrt-build/files/etc/uci-defaults/99-custom-files"
    if [ -f "$first_boot_script" ]; then
        echo "  ✅ 第一次开机脚本存在"
        if [ -x "$first_boot_script" ]; then
            echo "  ✅ 脚本可执行"
        else
            echo "  ⚠️ 脚本不可执行"
        fi
    else
        echo "  ❌ 第一次开机脚本不存在"
    fi
    
    # 5. 分析可能的IPK安装问题
    log "5. IPK安装问题分析:"
    if [ -f "/tmp/smart-install.log" ]; then
        echo "  ✅ 找到安装日志"
        
        # 检查IPK安装相关错误
        if grep -q "安装IPK" "/tmp/smart-install.log"; then
            echo "  📦 IPK安装尝试记录"
            
            # 检查文件冲突错误
            if grep -q "check_data_file_clashes" "/tmp/smart-install.log"; then
                echo "  ⚠️ 发现文件冲突错误"
                echo "  💡 建议: 尝试强制安装或移除冲突包"
            fi
            
            # 检查网络下载错误
            if grep -q "Failed to download" "/tmp/smart-install.log"; then
                echo "  ⚠️ 发现网络下载错误"
                echo "  💡 建议: 检查网络连接或使用离线安装"
            fi
            
            # 检查安装成功计数
            local success_count=$(grep -c "✅.*安装成功" "/tmp/smart-install.log" || echo "0")
            local fail_count=$(grep -c "❌.*安装失败" "/tmp/smart-install.log" || echo "0")
            echo "  📊 安装成功: $success_count, 失败: $fail_count"
        else
            echo "  ℹ️ 未找到IPK安装记录"
        fi
    else
        echo "  ℹ️ 未找到安装日志"
    fi
    
    # 6. 分析脚本执行问题
    log "6. 脚本执行问题分析:"
    if [ -f "/tmp/smart-install.log" ]; then
        # 检查脚本执行记录
        if grep -q "执行脚本" "/tmp/smart-install.log"; then
            echo "  📜 脚本执行尝试记录"
            
            # 检查执行成功计数
            local script_success=$(grep -c "✅.*执行成功" "/tmp/smart-install.log" || echo "0")
            local script_fail=$(grep -c "⚠️.*执行失败" "/tmp/smart-install.log" || echo "0")
            echo "  📊 执行成功: $script_success, 失败: $script_fail"
        else
            echo "  ℹ️ 未找到脚本执行记录"
            echo "  💡 可能原因: 脚本文件未正确识别或优先级排序失败"
        fi
        
        # 检查"未找到脚本文件"错误
        if grep -q "未找到脚本文件" "/tmp/smart-install.log"; then
            echo "  ⚠️ 发现'未找到脚本文件'错误"
            echo "  💡 可能原因:"
            echo "    1. 脚本文件没有被正确识别"
            echo "    2. 文件权限问题"
            echo "    3. 搜索路径错误"
        fi
    fi
    
    # 7. 修复建议
    log "7. 修复建议:"
    echo "  🛠️ 针对IPK安装问题:"
    echo "    1. 检查IPK文件是否完整"
    echo "    2. 尝试手动安装: opkg install /etc/custom-files/*.ipk"
    echo "    3. 使用强制安装: opkg install --force-reinstall /etc/custom-files/*.ipk"
    echo ""
    echo "  🛠️ 针对脚本执行问题:"
    echo "    1. 检查脚本文件权限: chmod +x /etc/custom-files/*.sh"
    echo "    2. 手动执行脚本: cd /etc/custom-files && LANG=zh_CN.UTF-8 ./smart_install.sh"
    echo "    3. 检查脚本文件编码: 确保为UTF-8格式"
    echo ""
    echo "  🛠️ 针对uci-defaults脚本问题:"
    echo "    1. 检查脚本退出代码: 必须为0才会被OpenWrt删除"
    echo "    2. 添加调试信息: 在脚本开头添加 set -x"
    echo "    3. 检查环境变量: 确保LANG=zh_CN.UTF-8"
    
    log "✅ 问题分析完成"
}

# 分析编译器问题
analyze_compiler_issue() {
    log "=== 编译器问题分析 ==="
    
    # 检查SDK下载状态
    log "🔍 检查SDK状态:"
    if [ -d "/mnt/openwrt-build/sdk" ]; then
        echo "  ✅ SDK目录存在"
        
        # 查找真正的GCC
        local gcc_file=$(find "/mnt/openwrt-build/sdk" -type f -executable \
            -name "*gcc" \
            ! -name "*gcc-ar" \
            ! -name "*gcc-ranlib" \
            ! -name "*gcc-nm" \
            ! -path "*dummy-tools*" \
            ! -path "*scripts*" \
            2>/dev/null | head -1)
        
        if [ -n "$gcc_file" ]; then
            echo "  ✅ 找到真正的GCC: $(basename "$gcc_file")"
            echo "  🔧 版本: $("$gcc_file" --version 2>&1 | head -1)"
        else
            echo "  ⚠️ 未找到真正的GCC（可能只有虚假的dummy-tools）"
            
            # 检查dummy-tools
            local dummy_gcc=$(find "/mnt/openwrt-build/sdk" -type f -executable \
                -name "*gcc" \
                -path "*dummy-tools*" \
                2>/dev/null | head -1)
            
            if [ -n "$dummy_gcc" ]; then
                echo "  ⚠️ 检测到虚假的dummy-tools编译器"
                echo "  💡 这是OpenWrt构建系统的占位符，不是真正的编译器"
            fi
        fi
    else
        echo "  ❌ SDK目录不存在"
    fi
    
    # 检查编译器调用
    log "📊 编译器调用分析:"
    if [ -f "/mnt/openwrt-build/build.log" ]; then
        # 检查编译器调用次数
        local gcc_calls=$(grep -c "gcc\|g++" "/mnt/openwrt-build/build.log" 2>/dev/null || echo "0")
        echo "  🔧 编译器调用次数: $gcc_calls"
        
        # 检查是否使用了SDK编译器
        local sdk_calls=$(grep -c "/mnt/openwrt-build/sdk" "/mnt/openwrt-build/build.log" 2>/dev/null || echo "0")
        echo "  🎯 SDK编译器调用: $sdk_calls"
        
        # 检查编译器错误
        if grep -qi "compiler.*not found" "/mnt/openwrt-build/build.log"; then
            echo "  ⚠️ 发现编译器未找到错误"
        fi
        
        if grep -qi "undefined reference" "/mnt/openwrt-build/build.log"; then
            echo "  ⚠️ 发现未定义引用错误"
        fi
    else
        echo "  ℹ️ 未找到构建日志"
    fi
    
    log "✅ 编译器分析完成"
}

# 分析构建日志
analyze_build_log() {
    local log_file="${1:-/mnt/openwrt-build/build.log}"
    
    if [ ! -f "$log_file" ]; then
        log "❌ 日志文件不存在: $log_file"
        return 1
    fi
    
    log "=== 构建日志分析 ==="
    
    # 1. 统计错误和警告
    local error_count=$(grep -ci "error" "$log_file" || echo "0")
    local warning_count=$(grep -ci "warning" "$log_file" || echo "0")
    
    echo "📊 统计信息:"
    echo "  ❌ 错误: $error_count 个"
    echo "  ⚠️ 警告: $warning_count 个"
    echo "  📄 文件大小: $(ls -lh "$log_file" | awk '{print $5}')"
    echo "  📝 文件行数: $(wc -l < "$log_file")"
    
    # 2. 显示前10个错误
    if [ $error_count -gt 0 ]; then
        echo ""
        echo "🔍 前10个错误:"
        grep -i "error" "$log_file" | head -10
    fi
    
    # 3. 显示前10个警告
    if [ $warning_count -gt 0 ]; then
        echo ""
        echo "🔍 前10个警告:"
        grep -i "warning" "$log_file" | head -10
    fi
    
    # 4. 检查常见构建问题
    echo ""
    echo "🔧 常见构建问题检查:"
    
    # 检查磁盘空间
    if grep -qi "No space left on device" "$log_file"; then
        echo "  ⚠️ 发现磁盘空间不足"
    fi
    
    # 检查内存不足
    if grep -qi "out of memory\|Killed process" "$log_file"; then
        echo "  ⚠️ 可能内存不足"
    fi
    
    # 检查网络下载问题
    if grep -qi "Failed to download\|404\|Connection refused" "$log_file"; then
        echo "  ⚠️ 发现网络下载问题"
    fi
    
    # 检查依赖问题
    if grep -qi "dependency\|depends on" "$log_file"; then
        echo "  ⚠️ 发现依赖问题"
    fi
    
    # 5. 构建时间分析
    echo ""
    echo "⏱️ 构建时间分析:"
    if grep -q "real\s" "$log_file"; then
        local build_time=$(grep "real\s" "$log_file" | tail -1)
        echo "  🕐 实际时间: $build_time"
    fi
    
    log "✅ 构建日志分析完成"
}

# 主函数
main() {
    case $1 in
        "analyze_custom_files")
            analyze_custom_files_issue
            ;;
        "analyze_compiler")
            analyze_compiler_issue
            ;;
        "analyze_build")
            analyze_build_log "$2"
            ;;
        *)
            echo "用法: $0 [命令]"
            echo "命令:"
            echo "  analyze_custom_files - 分析自定义文件安装问题"
            echo "  analyze_compiler     - 分析编译器问题"
            echo "  analyze_build [日志文件] - 分析构建日志"
            exit 1
            ;;
    esac
}

main "$@"
