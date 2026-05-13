#【error_monitor.sh-01】
#!/bin/bash
# 错误监控守护脚本
# 功能：实时监控编译过程，记录所有错误、警告、关键事件
# 使用方式：在 workflow 中后台启动

set -e

# 配置
MONITOR_DIR="${MONITOR_DIR:-/tmp/build-monitor}"
LOG_DIR="${LOG_DIR:-/tmp/build-logs}"
REPORT_FILE="${MONITOR_DIR}/error-report.txt"
EVENT_LOG="${MONITOR_DIR}/events.log"
ERROR_LOG="${MONITOR_DIR}/errors.log"
WARNING_LOG="${MONITOR_DIR}/warnings.log"
SUMMARY_FILE="${MONITOR_DIR}/summary.json"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化
init_monitor() {
    mkdir -p "$MONITOR_DIR" "$LOG_DIR"
    > "$REPORT_FILE"
    > "$EVENT_LOG"
    > "$ERROR_LOG"
    > "$WARNING_LOG"
    
    echo "{\"start_time\":\"$(date -Iseconds)\",\"events\":[],\"errors\":[],\"warnings\":[]}" > "$SUMMARY_FILE"
    
    log_event "MONITOR_START" "监控守护进程已启动" "info"
}

# 记录事件
log_event() {
    local event_type="$1"
    local message="$2"
    local severity="${3:-info}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 写入事件日志
    echo "[$timestamp] [$severity] [$event_type] $message" >> "$EVENT_LOG"
    
    # 根据严重程度分别记录
    case "$severity" in
        error)
            echo "[$timestamp] $message" >> "$ERROR_LOG"
            echo -e "${RED}❌ [$event_type] $message${NC}" >&2
            ;;
        warning)
            echo "[$timestamp] $message" >> "$WARNING_LOG"
            echo -e "${YELLOW}⚠️ [$event_type] $message${NC}" >&2
            ;;
        info)
            echo -e "${BLUE}ℹ️ [$event_type] $message${NC}" >&2
            ;;
        success)
            echo -e "${GREEN}✅ [$event_type] $message${NC}" >&2
            ;;
    esac
    
    # 更新 JSON 摘要
    update_json_summary "$event_type" "$message" "$severity" "$timestamp"
}

# 更新 JSON 摘要
update_json_summary() {
    local event_type="$1"
    local message="$2"
    local severity="$3"
    local timestamp="$4"
    
    local temp_file="${MONITOR_DIR}/summary.tmp"
    
    # 使用 jq 如果可用，否则手动处理
    if command -v jq >/dev/null 2>&1; then
        jq --arg ts "$timestamp" \
           --arg type "$event_type" \
           --arg msg "$message" \
           --arg sev "$severity" \
           '.events += [{"timestamp":$ts,"type":$type,"message":$msg,"severity":$sev}] | 
            .errors += (if $sev == "error" then [{"timestamp":$ts,"type":$type,"message":$msg}] else [] end) |
            .warnings += (if $sev == "warning" then [{"timestamp":$ts,"type":$type,"message":$msg}] else [] end)' \
           "$SUMMARY_FILE" > "$temp_file" 2>/dev/null && mv "$temp_file" "$SUMMARY_FILE"
    fi
}

# 监控文件变化（使用 inotifywait 或轮询）
monitor_file() {
    local file_path="$1"
    local file_name=$(basename "$file_path")
    
    # 如果文件不存在，等待创建
    while [ ! -f "$file_path" ]; do
        sleep 2
    done
    
    log_event "FILE_MONITOR" "开始监控文件: $file_path" "info"
    
    # 记录文件初始大小
    local last_size=0
    
    while [ -f "$file_path" ]; do
        local current_size=$(stat -c%s "$file_path" 2>/dev/null || echo "0")
        
        if [ $current_size -gt $last_size ]; then
            # 读取新增内容
            local new_content=$(dd if="$file_path" bs=1 skip=$last_size 2>/dev/null)
            
            # 分析新增内容中的错误和警告
            echo "$new_content" | while IFS= read -r line; do
                analyze_line "$line" "$file_name"
            done
            
            last_size=$current_size
        fi
        
        sleep 1
    done
}

# 分析单行日志
analyze_line() {
    local line="$1"
    local source="$2"
    
    # 错误检测模式
    if echo "$line" | grep -qiE "error:|Error|ERROR|failed:|Failed|FAILED|make.*\*\*\*"; then
        # 过滤掉无害的错误
        if ! echo "$line" | grep -qiE "BUILD_MARK|warning only|ignoring"; then
            log_event "ERROR_DETECTED" "[$source] $line" "error"
        fi
    fi
    
    # 警告检测模式
    if echo "$line" | grep -qiE "warning:|Warning|WARNING|deprecated|deprecation"; then
        if ! echo "$line" | grep -qiE "BUILD_MARK|deprecated package"; then
            log_event "WARNING_DETECTED" "[$source] $line" "warning"
        fi
    fi
    
    # 关键事件检测
    if echo "$line" | grep -qiE "make defconfig|make -j|Compiling|Linking|Building"; then
        # 只记录关键步骤，不记录所有
        if [[ "$line" =~ (make defconfig|make -j[0-9]+|Starting build|Finishing build) ]]; then
            log_event "BUILD_STEP" "$line" "info"
        fi
    fi
    
    # OPKG 依赖错误特殊处理
    if echo "$line" | grep -qiE "pkg_hash_check_unresolved|cannot find dependency"; then
        log_event "DEP_ERROR" "$line" "error"
        
        # 提取问题包名
        if [[ "$line" =~ for[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
            local pkg_name="${BASH_REMATCH[1]}"
            log_event "PROBLEM_PACKAGE" "问题包: $pkg_name" "error"
        fi
        if [[ "$line" =~ dependency[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
            local dep_name="${BASH_REMATCH[1]}"
            log_event "MISSING_DEP" "缺失依赖: $dep_name" "error"
        fi
    fi
    
    # dnsmasq 冲突检测
    if echo "$line" | grep -qiE "dnsmasq.*already provided|dnsmasq-full.*conflict"; then
        log_event "PACKAGE_CONFLICT" "检测到 dnsmasq 冲突: $line" "error"
    fi
    
    # 固件生成成功检测
    if echo "$line" | grep -qiE "sysupgrade.bin.*success|firmware.*generated|Image.*created"; then
        log_event "FIRMWARE_READY" "$line" "success"
    fi
}

# 监控进程
monitor_process() {
    local pid="$1"
    local process_name="$2"
    
    log_event "PROCESS_MONITOR" "开始监控进程: $process_name (PID: $pid)" "info"
    
    while kill -0 "$pid" 2>/dev/null; do
        sleep 5
    done
    
    wait "$pid"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_event "PROCESS_EXIT" "进程 $process_name 正常退出 (exit code: $exit_code)" "success"
    else
        log_event "PROCESS_EXIT" "进程 $process_name 异常退出 (exit code: $exit_code)" "error"
    fi
    
    return $exit_code
}

# 生成最终报告
generate_final_report() {
    local report_path="${1:-$REPORT_FILE}"
    
    {
        echo "================================================================"
        echo "📊 构建监控报告"
        echo "================================================================"
        echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "源码类型: ${SOURCE_REPO_TYPE:-unknown}"
        echo "设备: ${DEVICE:-unknown}"
        echo "目标: ${TARGET:-unknown}/${SUBTARGET:-unknown}"
        echo ""
        
        # 统计信息
        local error_count=$(wc -l < "$ERROR_LOG" 2>/dev/null || echo "0")
        local warning_count=$(wc -l < "$WARNING_LOG" 2>/dev/null || echo "0")
        local event_count=$(wc -l < "$EVENT_LOG" 2>/dev/null || echo "0")
        
        echo "📈 统计信息:"
        echo "   总事件数: $event_count"
        echo "   错误数: $error_count"
        echo "   警告数: $warning_count"
        echo ""
        
        # 错误列表
        if [ -s "$ERROR_LOG" ]; then
            echo "❌ 错误列表:"
            echo "----------------------------------------"
            cat "$ERROR_LOG" | while IFS= read -r line; do
                echo "   $line"
            done
            echo ""
        fi
        
        # 警告列表
        if [ -s "$WARNING_LOG" ]; then
            echo "⚠️ 警告列表:"
            echo "----------------------------------------"
            cat "$WARNING_LOG" | while IFS= read -r line; do
                echo "   $line"
            done
            echo ""
        fi
        
        # 问题包汇总
        echo "🔍 问题包汇总:"
        echo "----------------------------------------"
        grep "PROBLEM_PACKAGE" "$EVENT_LOG" 2>/dev/null | sed 's/^/   /' || echo "   无"
        echo ""
        
        echo "📋 缺失依赖汇总:"
        echo "----------------------------------------"
        grep "MISSING_DEP" "$EVENT_LOG" 2>/dev/null | sed 's/^/   /' || echo "   无"
        echo ""
        
        # 解决建议
        echo "💡 解决建议:"
        echo "----------------------------------------"
        
        if grep -q "dnsmasq.*conflict" "$EVENT_LOG" 2>/dev/null; then
            echo "   1. dnsmasq 冲突: 确保只启用 dnsmasq 或 dnsmasq-full 中的一个"
        fi
        
        local problem_pkgs=$(grep "PROBLEM_PACKAGE" "$EVENT_LOG" 2>/dev/null | sed 's/.*问题包: //' | sort -u)
        if [ -n "$problem_pkgs" ]; then
            echo "   2. 依赖问题: 在 FORBIDDEN_PACKAGES 中添加以下包:"
            echo "$problem_pkgs" | while read pkg; do
                echo "      - $pkg"
            done
        fi
        
        local missing_deps=$(grep "MISSING_DEP" "$EVENT_LOG" 2>/dev/null | sed 's/.*缺失依赖: //' | sort -u)
        if [ -n "$missing_deps" ]; then
            echo "   3. 缺失依赖: 在配置中添加以下包:"
            echo "$missing_deps" | while read dep; do
                echo "      - CONFIG_PACKAGE_${dep}=y"
            done
        fi
        
        echo ""
        echo "================================================================"
        
    } > "$report_path"
    
    log_event "REPORT_GENERATED" "报告已生成: $report_path" "success"
    
    # 输出到 stdout 供 workflow 捕获
    cat "$report_path"
}

# 主函数
main() {
    local mode="$1"
    shift
    
    init_monitor
    
    case "$mode" in
        "monitor-file")
            monitor_file "$@"
            ;;
        "monitor-process")
            monitor_process "$@"
            ;;
        "generate-report")
            generate_final_report "$@"
            ;;
        "daemon")
            # 后台运行，监控构建目录
            local build_dir="${1:-/mnt/openwrt-build}"
            local log_file="${2:-$build_dir/build.log}"
            
            log_event "DAEMON_START" "守护进程启动，监控目录: $build_dir" "info"
            
            # 监控日志文件
            monitor_file "$log_file" &
            local monitor_pid=$!
            
            # 等待构建完成（通过监控 make 进程）
            while pgrep -f "make.*V=s" > /dev/null 2>&1; do
                sleep 10
            done
            
            # 停止监控
            kill $monitor_pid 2>/dev/null
            
            # 生成报告
            generate_final_report
            
            log_event "DAEMON_STOP" "守护进程停止" "info"
            ;;
        *)
            echo "使用方法: $0 {monitor-file|monitor-process|generate-report|daemon} [参数]"
            exit 1
            ;;
    esac
}

# 如果直接运行
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
#【error_monitor.sh-01-end】
