#!/bin/bash

# 详细错误分析脚本
BUILD_DIR="/mnt/openwrt-build"
ERROR_LOG="$BUILD_DIR/error_analysis_detailed.log"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

analyze_errors() {
    log "=== 开始详细错误分析 ==="
    
    echo "OpenWrt 详细错误分析报告" > $ERROR_LOG
    echo "生成时间: $(date)" >> $ERROR_LOG
    echo "==========================================" >> $ERROR_LOG
    
    # 检查编译日志是否存在
    if [ ! -f "$BUILD_DIR/build.log" ]; then
        echo "❌ 编译日志不存在" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
        echo "详细诊断信息:" >> $ERROR_LOG
        echo "1. 检查构建目录:" >> $ERROR_LOG
        ls -la $BUILD_DIR/ 2>/dev/null | head -20 >> $ERROR_LOG
        
        echo "" >> $ERROR_LOG
        echo "2. 检查进程状态:" >> $ERROR_LOG
        ps aux | grep -E "make|gcc|g++" | head -10 >> $ERROR_LOG
        
        echo "" >> $ERROR_LOG
        echo "3. 磁盘空间状态:" >> $ERROR_LOG
        df -h /mnt >> $ERROR_LOG
        
        log "❌ 编译日志不存在，详细诊断信息已保存"
        return 0
    fi
    
    # 检查日志大小
    LOG_SIZE=$(wc -l < "$BUILD_DIR/build.log" 2>/dev/null || echo 0)
    echo "日志大小: $LOG_SIZE 行" >> $ERROR_LOG
    echo "" >> $ERROR_LOG
    
    if [ "$LOG_SIZE" -lt 10 ]; then
        echo "⚠️ 编译日志过小，可能编译未正常开始" >> $ERROR_LOG
        echo "最后10行日志:" >> $ERROR_LOG
        tail -10 "$BUILD_DIR/build.log" >> $ERROR_LOG
        return 0
    fi
    
    # 1. 检查常见错误模式
    echo "=== 常见错误分析 ===" >> $ERROR_LOG
    
    # 检查下载失败
    DOWNLOAD_ERRORS=$(grep -c "Download failed\|Failed to download\|wget failed" "$BUILD_DIR/build.log")
    if [ "$DOWNLOAD_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $DOWNLOAD_ERRORS 个下载失败错误" >> $ERROR_LOG
        grep -A2 -B2 "Download failed\|Failed to download\|wget failed" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查依赖错误
    DEPENDENCY_ERRORS=$(grep -c "satisfy dependencies\|undefined reference" "$BUILD_DIR/build.log")
    if [ "$DEPENDENCY_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $DEPENDENCY_ERRORS 个依赖/链接错误" >> $ERROR_LOG
        grep -A2 -B2 "satisfy dependencies\|undefined reference" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查配置错误
    CONFIG_ERRORS=$(grep -c "Configuration failed\|Invalid config\|config error" "$BUILD_DIR/build.log")
    if [ "$CONFIG_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $CONFIG_ERRORS 个配置错误" >> $ERROR_LOG
        grep -A2 -B2 "Configuration failed\|Invalid config\|config error" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查编译错误
    COMPILE_ERRORS=$(grep -c "Error:\|error:" "$BUILD_DIR/build.log")
    if [ "$COMPILE_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $COMPILE_ERRORS 个编译错误" >> $ERROR_LOG
        echo "前30个编译错误:" >> $ERROR_LOG
        grep -i "Error:\|error:" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
        
        # 显示具体的错误上下文
        echo "详细错误上下文（示例）:" >> $ERROR_LOG
        grep -B5 -A5 "Error:\|error:" "$BUILD_DIR/build.log" | head -50 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 2. 检查空间问题
    if grep -q "No space left\|disk full\|out of space" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现磁盘空间不足错误" >> $ERROR_LOG
        echo "当前磁盘空间:" >> $ERROR_LOG
        df -h >> $ERROR_LOG
        echo "" >> $ERROR_LOG
        echo "建议: 清理 /mnt 目录或增加磁盘空间" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 3. 检查网络问题
    NETWORK_ERRORS=$(grep -c "Connection refused\|timeout\|network unreachable\|Host unreachable" "$BUILD_DIR/build.log")
    if [ "$NETWORK_ERRORS" -gt 0 ]; then
        echo "⚠️ 发现 $NETWORK_ERRORS 个网络相关错误" >> $ERROR_LOG
        grep -A2 -B2 "Connection refused\|timeout\|network unreachable\|Host unreachable" "$BUILD_DIR/build.log" | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
        echo "建议: 检查网络连接或使用代理" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 4. 检查工具链问题
    TOOLCHAIN_ERRORS=$(grep -c "toolchain\|compiler\|gcc\|ld\|ar\|as" "$BUILD_DIR/build.log" | grep -i "error")
    if [ "$TOOLCHAIN_ERRORS" -gt 0 ]; then
        echo "⚠️ 发现 $TOOLCHAIN_ERRORS 个工具链相关错误" >> $ERROR_LOG
        grep -i "toolchain\|compiler\|gcc\|ld\|ar\|as" "$BUILD_DIR/build.log" | grep -i "error" | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
        echo "建议: 重新构建工具链 (设置 rebuild_toolchain=true)" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 5. 检查警告
    WARNINGS=$(grep -c "Warning:\|warning:" "$BUILD_DIR/build.log")
    if [ "$WARNINGS" -gt 0 ]; then
        echo "⚠️ 发现 $WARNINGS 个警告" >> $ERROR_LOG
        echo "前20个警告:" >> $ERROR_LOG
        grep -i "Warning:\|warning:" "$BUILD_DIR/build.log" | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 6. 生成摘要
    echo "==========================================" >> $ERROR_LOG
    echo "错误统计摘要:" >> $ERROR_LOG
    echo "  总日志行数: $LOG_SIZE" >> $ERROR_LOG
    echo "  下载错误: $DOWNLOAD_ERRORS" >> $ERROR_LOG
    echo "  依赖错误: $DEPENDENCY_ERRORS" >> $ERROR_LOG
    echo "  配置错误: $CONFIG_ERRORS" >> $ERROR_LOG
    echo "  编译错误: $COMPILE_ERRORS" >> $ERROR_LOG
    echo "  网络错误: $NETWORK_ERRORS" >> $ERROR_LOG
    echo "  工具链错误: $TOOLCHAIN_ERRORS" >> $ERROR_LOG
    echo "  警告数量: $WARNINGS" >> $ERROR_LOG
    
    # 7. 时间线分析
    echo "" >> $ERROR_LOG
    echo "=== 编译时间线 ===" >> $ERROR_LOG
    echo "开始时间:" >> $ERROR_LOG
    head -5 "$BUILD_DIR/build.log" >> $ERROR_LOG
    echo "" >> $ERROR_LOG
    echo "结束时间:" >> $ERROR_LOG
    tail -5 "$BUILD_DIR/build.log" >> $ERROR_LOG
    
    # 8. 显示最后100行日志
    echo "" >> $ERROR_LOG
    echo "=== 最后100行日志 ===" >> $ERROR_LOG
    tail -100 "$BUILD_DIR/build.log" >> $ERROR_LOG
    
    # 9. 关键错误位置
    echo "" >> $ERROR_LOG
    echo "=== 关键错误位置 ===" >> $ERROR_LOG
    grep -n "Error:\|error:" "$BUILD_DIR/build.log" | head -10 >> $ERROR_LOG
    
    log "✅ 详细错误分析完成"
    log "📄 分析报告: $ERROR_LOG"
    
    # 在控制台输出关键信息
    echo ""
    echo "=== 关键错误摘要 ==="
    if [ "$COMPILE_ERRORS" -gt 0 ]; then
        echo "❌ 编译错误: $COMPILE_ERRORS 个"
    fi
    if [ "$DOWNLOAD_ERRORS" -gt 0 ]; then
        echo "⚠️ 下载错误: $DOWNLOAD_ERRORS 个"
    fi
    if [ "$DEPENDENCY_ERRORS" -gt 0 ]; then
        echo "⚠️ 依赖错误: $DEPENDENCY_ERRORS 个"
    fi
    echo "📊 详细报告: $ERROR_LOG"
}

# 执行分析
analyze_errors
