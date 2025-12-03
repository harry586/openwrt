#!/bin/bash

# 错误分析脚本
BUILD_DIR="/mnt/openwrt-build"
ERROR_LOG="$BUILD_DIR/error_analysis.log"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

analyze_errors() {
    log "=== 开始错误分析 ==="
    
    if [ ! -f "$BUILD_DIR/build.log" ]; then
        log "❌ 编译日志不存在"
        return 1
    fi
    
    echo "OpenWrt 编译错误分析报告" > $ERROR_LOG
    echo "生成时间: $(date)" >> $ERROR_LOG
    echo "==========================================" >> $ERROR_LOG
    
    # 1. 检查常见错误模式
    log "🔍 分析常见错误..."
    
    # 检查下载失败
    if grep -q "Download failed" $BUILD_DIR/build.log; then
        echo "❌ 发现下载失败错误" >> $ERROR_LOG
        grep -A2 -B2 "Download failed" $BUILD_DIR/build.log | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查依赖错误
    if grep -q "satisfy dependencies" $BUILD_DIR/build.log; then
        echo "❌ 发现依赖错误" >> $ERROR_LOG
        grep -A2 -B2 "satisfy dependencies" $BUILD_DIR/build.log | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查配置错误
    if grep -q "Configuration failed" $BUILD_DIR/build.log; then
        echo "❌ 发现配置错误" >> $ERROR_LOG
        grep -A2 -B2 "Configuration failed" $BUILD_DIR/build.log | head -20 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 检查编译错误
    if grep -q "Error" $BUILD_DIR/build.log; then
        echo "❌ 发现编译错误" >> $ERROR_LOG
        grep -i "error:" $BUILD_DIR/build.log | head -30 >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 2. 检查空间问题
    if grep -q "No space left" $BUILD_DIR/build.log; then
        echo "⚠️ 发现磁盘空间不足错误" >> $ERROR_LOG
        echo "建议: 清理 /mnt 目录或增加磁盘空间" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 3. 检查网络问题
    if grep -q "Connection refused\|timeout\|network" $BUILD_DIR/build.log; then
        echo "⚠️ 发现网络相关错误" >> $ERROR_LOG
        echo "建议: 检查网络连接或使用代理" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 4. 检查工具链问题
    if grep -q "toolchain\|compiler\|gcc" $BUILD_DIR/build.log | grep -i "error"; then
        echo "⚠️ 发现工具链相关错误" >> $ERROR_LOG
        echo "建议: 重新构建工具链 (设置 rebuild_toolchain=true)" >> $ERROR_LOG
        echo "" >> $ERROR_LOG
    fi
    
    # 5. 生成摘要
    echo "==========================================" >> $ERROR_LOG
    echo "错误统计:" >> $ERROR_LOG
    echo "  下载错误: $(grep -c "Download failed" $BUILD_DIR/build.log)" >> $ERROR_LOG
    echo "  依赖错误: $(grep -c "satisfy dependencies" $BUILD_DIR/build.log)" >> $ERROR_LOG
    echo "  配置错误: $(grep -c "Configuration failed" $BUILD_DIR/build.log)" >> $ERROR_LOG
    echo "  编译错误: $(grep -c "Error:" $BUILD_DIR/build.log)" >> $ERROR_LOG
    echo "  警告数量: $(grep -c "Warning:" $BUILD_DIR/build.log)" >> $ERROR_LOG
    
    log "✅ 错误分析完成"
    log "📄 分析报告: $ERROR_LOG"
}

# 执行分析
analyze_errors
