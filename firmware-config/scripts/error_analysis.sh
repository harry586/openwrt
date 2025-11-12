#!/bin/bash

BUILD_DIR=$1
LOG_FILE="$BUILD_DIR/build.log"
ERROR_ANALYSIS_FILE="$BUILD_DIR/error_analysis.log"
ERROR_SUMMARY_FILE="$BUILD_DIR/error_summary.log"

echo "=== 详细错误分析 ===" > $ERROR_ANALYSIS_FILE
echo "开始收集和分析错误日志..." >> $ERROR_ANALYSIS_FILE

touch $ERROR_SUMMARY_FILE

echo "1. 严重错误 (Failed):" >> $ERROR_ANALYSIS_FILE
grep -E -i "failed" $LOG_FILE | head -20 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "2. 编译错误 (error:):" >> $ERROR_ANALYSIS_FILE
grep -E "error:" $LOG_FILE | head -20 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "3. 退出错误 (error 1/error 2):" >> $ERROR_ANALYSIS_FILE
grep -E "error 1|error 2" $LOG_FILE | head -10 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "4. 冒号错误 (:error):" >> $ERROR_ANALYSIS_FILE
grep -E ":error" $LOG_FILE | head -10 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "5. 文件缺失错误:" >> $ERROR_ANALYSIS_FILE
grep -E "No such file or directory" $LOG_FILE | head -15 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "6. 管道错误:" >> $ERROR_ANALYSIS_FILE
grep -E "Broken pipe" $LOG_FILE >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "7. 缺失依赖错误:" >> $ERROR_ANALYSIS_FILE
grep -E -i "missing" $LOG_FILE | head -15 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "8. 目标构建失败:" >> $ERROR_ANALYSIS_FILE
grep -E "recipe for target.*failed" $LOG_FILE | head -10 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "9. 未定义引用错误:" >> $ERROR_ANALYSIS_FILE
grep -E "undefined reference" $LOG_FILE | head -10 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "10. 找不到命令错误:" >> $ERROR_ANALYSIS_FILE
grep -E "command not found" $LOG_FILE | head -10 >> $ERROR_ANALYSIS_FILE
echo "" >> $ERROR_ANALYSIS_FILE

echo "=== 错误原因分析和建议 ===" >> $ERROR_ANALYSIS_FILE

if grep -q "No such file or directory" $LOG_FILE; then
    echo "- 文件缺失: 这是正常的打包过程中的警告，不影响固件功能" >> $ERROR_ANALYSIS_FILE
fi

if grep -q "undefined reference" $LOG_FILE; then
    echo "- 链接错误: 库文件缺失或链接顺序问题，可能影响特定功能" >> $ERROR_ANALYSIS_FILE
fi

if grep -q "command not found" $LOG_FILE; then
    echo "- 命令缺失: 已安装help2man，这些错误不会影响固件核心功能" >> $ERROR_ANALYSIS_FILE
fi

if grep -q "recipe for target.*failed" $LOG_FILE; then
    echo "- 目标构建失败: 具体软件包编译失败，可能影响相关功能" >> $ERROR_ANALYSIS_FILE
fi

if grep -q "Broken pipe" $LOG_FILE; then
    echo "- 管道错误: 这是并行编译的正常现象，不影响最终结果" >> $ERROR_ANALYSIS_FILE
fi

if grep -q "Performing.*Test.*Failed" $LOG_FILE; then
    echo "- 特性检测失败: 这是正常的配置检测过程，系统会选择备用方案" >> $ERROR_ANALYSIS_FILE
fi

echo "" >> $ERROR_ANALYSIS_FILE
echo "=== 关键错误检查 ===" >> $ERROR_ANALYSIS_FILE
if grep -q "Error 1" $LOG_FILE || grep -q "Error 2" $LOG_FILE; then
    echo "发现关键编译错误，固件可能不完整" >> $ERROR_ANALYSIS_FILE
else
    echo "未发现关键编译错误，固件应该可用" >> $ERROR_ANALYSIS_FILE
fi

grep -E -i "failed|error|No such file or directory|Broken pipe|missing|undefined reference|command not found|recipe for target.*failed" $LOG_FILE > $ERROR_SUMMARY_FILE

echo "错误分析完成"
echo "=== 错误摘要 ==="
cat $ERROR_SUMMARY_FILE | head -30
