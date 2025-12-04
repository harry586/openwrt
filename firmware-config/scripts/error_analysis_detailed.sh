#!/bin/bash

BUILD_DIR="/mnt/openwrt-build"
ERROR_LOG="$BUILD_DIR/error_analysis_detailed.log"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

analyze_errors() {
    log "=== 开始详细错误分析 ==="
    echo "OpenWrt 错误分析报告" > $ERROR_LOG
    echo "生成时间: $(date)" >> $ERROR_LOG
    
    if [ ! -f "$BUILD_DIR/build.log" ]; then
        echo "❌ 编译日志不存在" >> $ERROR_LOG
        log "❌ 编译日志不存在"
        return 0
    fi
    
    LOG_SIZE=$(wc -l < "$BUILD_DIR/build.log" 2>/dev/null || echo 0)
    echo "日志大小: $LOG_SIZE 行" >> $ERROR_LOG
    
    DOWNLOAD_ERRORS=$(grep -c "Download failed\|Failed to download\|wget failed" "$BUILD_DIR/build.log")
    if [ "$DOWNLOAD_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $DOWNLOAD_ERRORS 个下载失败错误" >> $ERROR_LOG
        grep -A2 -B2 "Download failed\|Failed to download\|wget failed" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
    fi
    
    DEPENDENCY_ERRORS=$(grep -c "satisfy dependencies\|undefined reference" "$BUILD_DIR/build.log")
    if [ "$DEPENDENCY_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $DEPENDENCY_ERRORS 个依赖/链接错误" >> $ERROR_LOG
        grep -A2 -B2 "satisfy dependencies\|undefined reference" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
    fi
    
    CONFIG_ERRORS=$(grep -c "Configuration failed\|Invalid config\|config error" "$BUILD_DIR/build.log")
    if [ "$CONFIG_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $CONFIG_ERRORS 个配置错误" >> $ERROR_LOG
        grep -A2 -B2 "Configuration failed\|Invalid config\|config error" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
    fi
    
    COMPILE_ERRORS=$(grep -c "Error:\|error:" "$BUILD_DIR/build.log")
    if [ "$COMPILE_ERRORS" -gt 0 ]; then
        echo "❌ 发现 $COMPILE_ERRORS 个编译错误" >> $ERROR_LOG
        grep -i "Error:\|error:" "$BUILD_DIR/build.log" | head -30 >> $ERROR_LOG
    fi
    
    if grep -q "No space left\|disk full\|out of space" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现磁盘空间不足错误" >> $ERROR_LOG
        df -h >> $ERROR_LOG
    fi
    
    NETWORK_ERRORS=$(grep -c "Connection refused\|timeout\|network unreachable\|Host unreachable" "$BUILD_DIR/build.log")
    if [ "$NETWORK_ERRORS" -gt 0 ]; then
        echo "⚠️ 发现 $NETWORK_ERRORS 个网络相关错误" >> $ERROR_LOG
        grep -A2 -B2 "Connection refused\|timeout\|network unreachable\|Host unreachable" "$BUILD_DIR/build.log" | head -20 >> $ERROR_LOG
    fi
    
    WARNINGS=$(grep -c "Warning:\|warning:" "$BUILD_DIR/build.log")
    if [ "$WARNINGS" -gt 0 ]; then
        echo "⚠️ 发现 $WARNINGS 个警告" >> $ERROR_LOG
        grep -i "Warning:\|warning:" "$BUILD_DIR/build.log" | head -20 >> $ERROR_LOG
    fi
    
    echo "错误统计摘要:" >> $ERROR_LOG
    echo "  总日志行数: $LOG_SIZE" >> $ERROR_LOG
    echo "  下载错误: $DOWNLOAD_ERRORS" >> $ERROR_LOG
    echo "  依赖错误: $DEPENDENCY_ERRORS" >> $ERROR_LOG
    echo "  配置错误: $CONFIG_ERRORS" >> $ERROR_LOG
    echo "  编译错误: $COMPILE_ERRORS" >> $ERROR_LOG
    echo "  网络错误: $NETWORK_ERRORS" >> $ERROR_LOG
    echo "  警告数量: $WARNINGS" >> $ERROR_LOG
    
    echo "最后100行日志:" >> $ERROR_LOG
    tail -100 "$BUILD_DIR/build.log" >> $ERROR_LOG
    
    log "✅ 详细错误分析完成"
    
    echo ""
    echo "=== 关键错误摘要 ==="
    if [ "$COMPILE_ERRORS" -gt 0 ]; then
        echo "❌ 编译错误: $COMPILE_ERRORS 个"
    fi
    if [ "$DOWNLOAD_ERRORS" -gt 0 ]; then
        echo "⚠️ 下载错误: $DOWNLOAD_ERRORS 个"
    fi
    echo "📊 详细报告: $ERROR_LOG"
}

analyze_errors
