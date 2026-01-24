#!/bin/sh

# ==================================================
# 自定义文件安装脚本（增强版）- 带SSH测试
# 版本: 1.0
# 作者: OpenWrt固件构建系统
# ==================================================

# 创建日志目录
LOG_DIR="/root/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/custom-files-install-$(date +%Y%m%d_%H%M%S).log"

echo "==================================================" > $LOG_FILE
echo "      自定义文件安装脚本（增强版）- 带SSH测试" >> $LOG_FILE
echo "      开始时间: $(date)" >> $LOG_FILE
echo "      日志文件: $LOG_FILE" >> $LOG_FILE
echo "==================================================" >> $LOG_FILE
echo "" >> $LOG_FILE

# 同时输出到控制台
echo "=================================================="
echo "      自定义文件安装脚本（增强版）- 带SSH测试"
echo "      开始时间: $(date)"
echo "      日志文件: $LOG_FILE"
echo "=================================================="
echo ""

# SSH测试函数
test_ssh_connection() {
    local test_name="$1"
    echo "  🔌 测试SSH连接 [$test_name]..." | tee -a "$LOG_FILE"
    echo "      开始时间: $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
    
    local ssh_ok=0
    
    # 方式1: 测试localhost SSH连接
    if timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no localhost "echo SSH-test-OK-$(date +%s)" 2>/dev/null; then
        ssh_ok=1
        echo "      ✅ SSH连接正常 (localhost)" | tee -a "$LOG_FILE"
    else
        echo "      ⚠️ localhost连接失败" | tee -a "$LOG_FILE"
    fi
    
    # 方式2: 测试127.0.0.1 SSH连接
    if [ $ssh_ok -eq 0 ]; then
        if timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no 127.0.0.1 "echo SSH-test-OK-$(date +%s)" 2>/dev/null; then
            ssh_ok=1
            echo "      ✅ SSH连接正常 (127.0.0.1)" | tee -a "$LOG_FILE"
        else
            echo "      ⚠️ 127.0.0.1连接失败" | tee -a "$LOG_FILE"
        fi
    fi
    
    # 方式3: 检查SSH服务状态
    if [ $ssh_ok -eq 0 ]; then
        if ps aux | grep -q "[s]shd"; then
            ssh_ok=1
            echo "      ✅ SSH服务正在运行" | tee -a "$LOG_FILE"
        else
            echo "      ⚠️ SSH服务未运行" | tee -a "$LOG_FILE"
        fi
    fi
    
    if [ $ssh_ok -eq 1 ]; then
        echo "      ✅ SSH测试通过" | tee -a "$LOG_FILE"
        return 0
    else
        echo "      ⚠️ SSH连接测试失败" | tee -a "$LOG_FILE"
        echo "      💡 建议检查: 1) SSH服务是否安装 2) 防火墙设置 3) SSH配置" | tee -a "$LOG_FILE"
        return 1
    fi
    
    echo "      结束时间: $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
}

# 测试初始SSH连接
echo "🔌 初始SSH连接测试..." | tee -a "$LOG_FILE"
test_ssh_connection "INITIAL"

CUSTOM_DIR="/etc/custom-files"

if [ -d "$CUSTOM_DIR" ]; then
    echo "✅ 找到自定义文件目录: $CUSTOM_DIR" | tee -a "$LOG_FILE"
    echo "📊 目录结构:" | tee -a "$LOG_FILE"
    find "$CUSTOM_DIR" -type f 2>/dev/null | sort | while read file; do
        file_name=$(basename "$file")
        file_size=$(ls -lh "$file" 2>/dev/null | awk '{print $5}' || echo "未知")
        rel_path="${file#$CUSTOM_DIR/}"
        echo "  📄 $rel_path ($file_size)" | tee -a "$LOG_FILE"
    done
    echo "" | tee -a "$LOG_FILE"
    
    # 1. 安装IPK文件（增强版）- 带SSH测试
    IPK_COUNT=0
    IPK_SUCCESS=0
    IPK_FAILED=0
    IPK_SSH_TESTS=0
    IPK_SSH_SUCCESS=0
    
    echo "📦 开始安装IPK包（安装后测试SSH）..." | tee -a "$LOG_FILE"
    
    # 使用临时文件来存储文件列表
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        # 检查是否是IPK文件（不区分大小写）
        if echo "$file_name" | grep -qi "\.ipk$"; then
            IPK_COUNT=$((IPK_COUNT + 1))
            rel_path="${file#$CUSTOM_DIR/}"
            
            echo "  🔧 正在安装 [$IPK_COUNT]: $rel_path" | tee -a "$LOG_FILE"
            echo "      开始时间: $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
            
            # 安装IPK包，错误不退出
            if opkg install "$file" 2>&1 | tee -a "$LOG_FILE"; then
                echo "      ✅ 安装成功" | tee -a "$LOG_FILE"
                IPK_SUCCESS=$((IPK_SUCCESS + 1))
                
                # 安装后测试SSH
                IPK_SSH_TESTS=$((IPK_SSH_TESTS + 1))
                if test_ssh_connection "IPK-$IPK_COUNT"; then
                    IPK_SSH_SUCCESS=$((IPK_SSH_SUCCESS + 1))
                fi
            else
                echo "      ❌ 安装失败，继续下一个..." | tee -a "$LOG_FILE"
                IPK_FAILED=$((IPK_FAILED + 1))
                
                # 记录详细错误信息
                echo "      错误信息:" | tee -a "$LOG_FILE"
                tail -5 $LOG_FILE | tee -a "$LOG_FILE"
            fi
            
            echo "      结束时间: $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
        fi
    done < "$FILE_LIST"
    
    rm -f "$FILE_LIST"
    
    echo "📊 IPK包安装统计:" | tee -a "$LOG_FILE"
    echo "  尝试安装: $IPK_COUNT 个" | tee -a "$LOG_FILE"
    echo "  成功: $IPK_SUCCESS 个" | tee -a "$LOG_FILE"
    echo "  失败: $IPK_FAILED 个" | tee -a "$LOG_FILE"
    echo "  SSH测试: $IPK_SSH_SUCCESS/$IPK_SSH_TESTS 通过" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # 2. 运行脚本文件（增强版）- 带SSH测试
    SCRIPT_COUNT=0
    SCRIPT_SUCCESS=0
    SCRIPT_FAILED=0
    SCRIPT_SSH_TESTS=0
    SCRIPT_SSH_SUCCESS=0
    
    echo "📜 开始运行脚本文件（运行后测试SSH）..." | tee -a "$LOG_FILE"
    
    # 使用临时文件来存储文件列表
    FILE_LIST=$(mktemp)
    find "$CUSTOM_DIR" -type f 2>/dev/null > "$FILE_LIST"
    
    while IFS= read -r file; do
        file_name=$(basename "$file")
        
        # 检查是否是脚本文件（不区分大小写）
        if echo "$file_name" | grep -qi "\.sh$"; then
            SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
            rel_path="${file#$CUSTOM_DIR/}"
            
            echo "  🚀 正在运行 [$SCRIPT_COUNT]: $rel_path" | tee -a "$LOG_FILE"
            echo "      开始时间: $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
            
            # 确保有执行权限
            chmod +x "$file" 2>/dev/null
            
            # 运行脚本，错误不退出
            if sh "$file" 2>&1 | tee -a "$LOG_FILE"; then
                echo "      ✅ 运行成功" | tee -a "$LOG_FILE"
                SCRIPT_SUCCESS=$((SCRIPT_SUCCESS + 1))
                
                # 运行后测试SSH
                SCRIPT_SSH_TESTS=$((SCRIPT_SSH_TESTS + 1))
                if test_ssh_connection "SCRIPT-$SCRIPT_COUNT"; then
                    SCRIPT_SSH_SUCCESS=$((SCRIPT_SSH_SUCCESS + 1))
                fi
            else
                local exit_code=$?
                echo "      ❌ 运行失败，退出代码: $exit_code" | tee -a "$LOG_FILE"
                SCRIPT_FAILED=$((SCRIPT_FAILED + 1))
                
                # 记录详细错误信息
                echo "      错误信息:" | tee -a "$LOG_FILE"
                tail -5 $LOG_FILE | tee -a "$LOG_FILE"
            fi
            
            echo "      结束时间: $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
            echo "" | tee -a "$LOG_FILE"
        fi
    done < "$FILE_LIST"
    
    rm -f "$FILE_LIST"
    
    echo "📊 脚本运行统计:" | tee -a "$LOG_FILE"
    echo "  尝试运行: $SCRIPT_COUNT 个" | tee -a "$LOG_FILE"
    echo "  成功: $SCRIPT_SUCCESS 个" | tee -a "$LOG_FILE"
    echo "  失败: $SCRIPT_FAILED 个" | tee -a "$LOG_FILE"
    echo "  SSH测试: $SCRIPT_SSH_SUCCESS/$SCRIPT_SSH_TESTS 通过" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # 3. 复制其他文件到特定位置 - 带SSH测试
    OTHER_COUNT=0
    OTHER_SUCCESS=0
    OTHER_FAILED=0
    OTHER_SSH_TESTS=0
    OTHER_SSH_SUCCESS=0
    
    echo "📁 处理其他文件（处理后测试SSH）..." | tee -a "$LOG_FILE"
    
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
        
        echo "  📋 正在处理 [$OTHER_COUNT]: $rel_path" | tee -a "$LOG_FILE"
        
        # 根据文件类型处理
        if echo "$file_name" | grep -qi "\.conf$"; then
            # 配置文件复制到/etc/config/
            echo "      类型: 配置文件" | tee -a "$LOG_FILE"
            if cp "$file" "/etc/config/$file_name" 2>/dev/null; then
                echo "      ✅ 复制到 /etc/config/" | tee -a "$LOG_FILE"
                OTHER_SUCCESS=$((OTHER_SUCCESS + 1))
            else
                echo "      ❌ 复制失败" | tee -a "$LOG_FILE"
                OTHER_FAILED=$((OTHER_FAILED + 1))
            fi
        elif echo "$file_name" | grep -qi "\.config$"; then
            # 配置文件复制到/etc/config/
            echo "      类型: 配置文件" | tee -a "$LOG_FILE"
            if cp "$file" "/etc/config/$file_name" 2>/dev/null; then
                echo "      ✅ 复制到 /etc/config/" | tee -a "$LOG_FILE"
                OTHER_SUCCESS=$((OTHER_SUCCESS + 1))
            else
                echo "      ❌ 复制失败" | tee -a "$LOG_FILE"
                OTHER_FAILED=$((OTHER_FAILED + 1))
            fi
        else
            # 其他文件复制到/tmp/
            echo "      类型: 其他文件" | tee -a "$LOG_FILE"
            if cp "$file" "/tmp/$file_name" 2>/dev/null; then
                echo "      ✅ 复制到 /tmp/" | tee -a "$LOG_FILE"
                OTHER_SUCCESS=$((OTHER_SUCCESS + 1))
            else
                echo "      ❌ 复制失败" | tee -a "$LOG_FILE"
                OTHER_FAILED=$((OTHER_FAILED + 1))
            fi
        fi
        
        # 处理后测试SSH（每5个文件测试一次）
        if [ $((OTHER_COUNT % 5)) -eq 0 ]; then
            OTHER_SSH_TESTS=$((OTHER_SSH_TESTS + 1))
            if test_ssh_connection "OTHER-$OTHER_COUNT"; then
                OTHER_SSH_SUCCESS=$((OTHER_SSH_SUCCESS + 1))
            fi
        fi
        
        echo "" | tee -a "$LOG_FILE"
    done < "$FILE_LIST"
    
    rm -f "$FILE_LIST"
    
    # 最后再测试一次SSH
    OTHER_SSH_TESTS=$((OTHER_SSH_TESTS + 1))
    if test_ssh_connection "FINAL"; then
        OTHER_SSH_SUCCESS=$((OTHER_SSH_SUCCESS + 1))
    fi
    
    echo "📊 其他文件处理统计:" | tee -a "$LOG_FILE"
    echo "  尝试处理: $OTHER_COUNT 个" | tee -a "$LOG_FILE"
    echo "  成功: $OTHER_SUCCESS 个" | tee -a "$LOG_FILE"
    echo "  失败: $OTHER_FAILED 个" | tee -a "$LOG_FILE"
    echo "  SSH测试: $OTHER_SSH_SUCCESS/$OTHER_SSH_TESTS 通过" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # 4. 安装完成总结
    echo "==================================================" | tee -a "$LOG_FILE"
    echo "      自定义文件安装完成" | tee -a "$LOG_FILE"
    echo "      结束时间: $(date)" | tee -a "$LOG_FILE"
    echo "      日志文件: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "==================================================" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    TOTAL_FILES=$((IPK_COUNT + SCRIPT_COUNT + OTHER_COUNT))
    TOTAL_SUCCESS=$((IPK_SUCCESS + SCRIPT_SUCCESS + OTHER_SUCCESS))
    TOTAL_FAILED=$((IPK_FAILED + SCRIPT_FAILED + OTHER_FAILED))
    TOTAL_SSH_TESTS=$((IPK_SSH_TESTS + SCRIPT_SSH_TESTS + OTHER_SSH_TESTS))
    TOTAL_SSH_SUCCESS=$((IPK_SSH_SUCCESS + SCRIPT_SSH_SUCCESS + OTHER_SSH_SUCCESS))
    
    echo "📈 总体统计:" | tee -a "$LOG_FILE"
    echo "  总文件数: $TOTAL_FILES 个" | tee -a "$LOG_FILE"
    echo "  成功处理: $TOTAL_SUCCESS 个" | tee -a "$LOG_FILE"
    echo "  失败处理: $TOTAL_FAILED 个" | tee -a "$LOG_FILE"
    if [ $((TOTAL_SUCCESS + TOTAL_FAILED)) -gt 0 ]; then
        echo "  成功率: $((TOTAL_SUCCESS * 100 / (TOTAL_SUCCESS + TOTAL_FAILED)))%" | tee -a "$LOG_FILE"
    else
        echo "  成功率: 0%" | tee -a "$LOG_FILE"
    fi
    echo "  SSH测试: $TOTAL_SSH_SUCCESS/$TOTAL_SSH_TESTS 通过" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    echo "📋 详细分类统计:" | tee -a "$LOG_FILE"
    echo "  📦 IPK包: $IPK_SUCCESS/$IPK_COUNT 成功, SSH: $IPK_SSH_SUCCESS/$IPK_SSH_TESTS" | tee -a "$LOG_FILE"
    echo "  📜 脚本: $SCRIPT_SUCCESS/$SCRIPT_COUNT 成功, SSH: $SCRIPT_SSH_SUCCESS/$SCRIPT_SSH_TESTS" | tee -a "$LOG_FILE"
    echo "  📁 其他文件: $OTHER_SUCCESS/$OTHER_COUNT 成功, SSH: $OTHER_SSH_SUCCESS/$OTHER_SSH_TESTS" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    
    # SSH连接质量评估
    echo "🔌 SSH连接质量评估:" | tee -a "$LOG_FILE"
    if [ $TOTAL_SSH_TESTS -gt 0 ]; then
        SSH_SUCCESS_RATE=$((TOTAL_SSH_SUCCESS * 100 / TOTAL_SSH_TESTS))
        echo "  SSH成功率: $SSH_SUCCESS_RATE%" | tee -a "$LOG_FILE"
        
        if [ $SSH_SUCCESS_RATE -ge 90 ]; then
            echo "  🎉 SSH连接质量: 优秀" | tee -a "$LOG_FILE"
        elif [ $SSH_SUCCESS_RATE -ge 70 ]; then
            echo "  ✅ SSH连接质量: 良好" | tee -a "$LOG_FILE"
        elif [ $SSH_SUCCESS_RATE -ge 50 ]; then
            echo "  ⚠️ SSH连接质量: 一般" | tee -a "$LOG_FILE"
        else
            echo "  ❌ SSH连接质量: 较差，建议检查SSH配置" | tee -a "$LOG_FILE"
        fi
    else
        echo "  ℹ️ 未进行SSH测试" | tee -a "$LOG_FILE"
    fi
    echo "" | tee -a "$LOG_FILE"
    
    # 创建完成标记文件
    touch /etc/custom-files-installed
    echo "✅ 已创建安装完成标记: /etc/custom-files-installed" | tee -a "$LOG_FILE"
    
    echo "📝 重要信息:" | tee -a "$LOG_FILE"
    echo "  安装日志位置: $LOG_FILE" | tee -a "$LOG_FILE"
    echo "  日志目录: /root/logs/" | tee -a "$LOG_FILE"
    echo "  下次启动不会再次安装（已有标记文件）" | tee -a "$LOG_FILE"
    echo "  如需重新安装，请删除: /etc/custom-files-installed" | tee -a "$LOG_FILE"
    
else
    echo "❌ 自定义文件目录不存在: $CUSTOM_DIR" | tee -a "$LOG_FILE"
    echo "💡 请将自定义文件放到 /etc/custom-files/ 目录中" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "=== 自定义文件安装脚本执行完成 ===" | tee -a "$LOG_FILE"

# 显示日志文件位置
echo ""
echo "=================================================="
echo "安装完成！"
echo "日志文件: $LOG_FILE"
echo "下次运行前请删除: /etc/custom-files-installed"
echo "=================================================="

exit 0
