#!/bin/bash

# 错误分析脚本
BUILD_DIR="/mnt/openwrt-build"
ERROR_LOG="$BUILD_DIR/error_analysis.log"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

analyze_errors() {
    log "=== 开始错误分析 ==="
    
    echo "OpenWrt 编译错误分析报告" > $ERROR_LOG
    echo "生成时间: $(date)" >> $ERROR_LOG
    echo "==========================================" >> $ERROR_LOG
    
    # 检查编译日志是否存在
    if [ ! -f "$BUILD_DIR/build.log" ]; then
        echo "❌ 编译日志不存在" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
        echo "可能的原因：" >> $ERROR_LOG
        echo "1. 编译步骤未执行" >> $ERROR_LOG
        echo "2. 编译过程被中断" >> $ERROR_LOG
        echo "3. 磁盘空间不足" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
        
        # 检查构建目录
        echo "=== 构建目录内容 ===" >> $ERROR_LOG
        ls -la $BUILD_DIR/ 2>/dev/null | head -20 >> $ERROR_LOG
        
        log "⚠️ 编译日志不存在"
        return 0
    fi
    
    # 检查日志大小
    LOG_SIZE=$(wc -l < "$BUILD_DIR/build.log" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -lt 10 ]; then
        echo "⚠️ 编译日志过小，可能编译未正常开始" >> $ERROR_LOG
        return 0
    fi
    
    # 1. 检查常见错误模式
    log "🔍 分析常见错误..."
    
    # 检查下载失败
    if grep -q "Download failed\|Failed to download" "$BUILD_DIR/build.log"; then
        echo "❌ 发现下载失败错误" >> $ERROR_LOG
        grep -A2 -B2 "Download failed\|Failed to download" "$BUILD_DIR/build.log" | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查依赖错误
    if grep -q "satisfy dependencies" "$BUILD_DIR/build.log"; then
        echo "❌ 发现依赖错误" >> $ERROR_LOG
        grep -A2 -B2 "satisfy dependencies" "$BUILD_DIR/build.log" | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查编译错误
    if grep -q "Error:" "$BUILD_DIR/build.log"; then
        echo "❌ 发现编译错误" >> $ERROR_LOG
        grep "Error:" "$BUILD_DIR/build.log" | tail -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 2. 检查空间问题
    if grep -q "No space left" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现磁盘空间不足错误" >> $ERROR_LOG
        echo "建议: 清理 /mnt 目录或增加磁盘空间" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 3. 检查网络问题
    if grep -q "Connection refused\|timeout\|network unreachable" "$BUILD_DIR/build.log"; then
        echo "⚠️ 发现网络相关错误" >> $ERROR_LOG
        echo "建议: 检查网络连接或使用代理" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 4. 生成摘要
    echo "==========================================" >> $ERROR_LOG
    echo "错误统计:" >> $ERROR_LOG
    echo "  日志行数: $LOG_SIZE" >> $ERROR_LOG
    echo "  错误数量: $(grep -c "Error:" "$BUILD_DIR/build.log")" >> $ERROR_LOG
    echo "  警告数量: $(grep -c "Warning:" "$BUILD_DIR/build.log")" >> $ERROR_LOG
    
    # 显示最后50行日志
    echo "" >> $ERROR_LOG
    echo "=== 最后50行日志 ===" >> $ERROR_LOG
    tail -50 "$BUILD_DIR/build.log" >> $ERROR_LOG 2>/dev/null
    
    log "✅ 错误分析完成"
    log "📄 分析报告: $ERROR_LOG"
}

# 执行分析（即使失败也不退出）
analyze_errors || {
    echo "错误分析脚本执行失败，但继续执行后续步骤" > "$ERROR_LOG"
}
