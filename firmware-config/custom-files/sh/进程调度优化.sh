#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 系统进程调度优化脚本 - 提升系统响应速度
# =============================================

# 检测运行环境
if [ -f "/etc/openwrt_release" ] || [ -d "/etc/config" ]; then
    echo "检测到在路由器环境运行，执行运行时安装..."
    RUNTIME_MODE="true"
    INSTALL_DIR="/"
else
    echo "检测到在编译环境运行，集成到固件..."
    RUNTIME_MODE="false"
    INSTALL_DIR="files/"
fi

echo "开始配置系统进程调度优化..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/sysctl.d"
    mkdir -p "${prefix}/usr/sbin"
    mkdir -p "${prefix}/etc/hotplug.d/block"
    mkdir -p "${prefix}/usr/lib/lua/luci/controller/admin"
    mkdir -p "${prefix}/usr/lib/lua/luci/view/admin_system"
}

create_dirs "$INSTALL_DIR"

# ==================== 进程调度优化配置 ====================
create_sched_optimization() {
    local prefix="$1"
    
    # 创建内核调度参数优化
    cat > "${prefix}/etc/sysctl.d/99-sched-optimization.conf" << 'EOF'
# =============================================
# 系统进程调度优化配置
# =============================================

# CPU调度优化
kernel.sched_min_granularity_ns = 1000000      # 最小调度粒度（1ms）
kernel.sched_wakeup_granularity_ns = 1500000   # 唤醒调度粒度（1.5ms）
kernel.sched_migration_cost_ns = 5000000       # 迁移成本（5ms）
kernel.sched_nr_migrate = 32                   # 每次迁移的最大进程数

# 交互性优化
kernel.sched_child_runs_first = 1              # 子进程优先运行
kernel.sched_rt_runtime_us = 950000            # 实时任务运行时间（95%）
kernel.sched_rt_period_us = 1000000            # 实时任务周期（1s）

# CFS（完全公平调度器）优化
kernel.sched_latency_ns = 24000000             # 调度延迟（24ms）
kernel.sched_cfs_bandwidth_slice_us = 5000     # CFS带宽切片（5ms）

#  NUMA优化（如果支持）
# kernel.numa_balancing = 1
# kernel.numa_balancing_scan_delay_ms = 1000
# kernel.numa_balancing_scan_period_min_ms = 1000

# 进程限制优化
kernel.threads-max = 65536                     # 最大线程数
kernel.pid_max = 65536                         # 最大进程ID
kernel.pty.max = 4096                          # 最大伪终端
kernel.pty.nr = 1024                           # 当前伪终端

# 进程优先级调整
kernel.sched_autogroup_enabled = 1             # 启用自动进程分组
EOF

    # 创建CPU频率调节配置
    cat > "${prefix}/etc/init.d/cpufreq" << 'EOF'
#!/bin/sh /etc/rc.common

START=95
USE_PROCD=1

start_service() {
    echo "正在优化CPU频率调节..."
    
    # 检查CPU频率调节驱动
    if [ -d /sys/devices/system/cpu/cpu0/cpufreq ]; then
        # 设置调节器为ondemand（平衡性能和省电）
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
            if [ -f "$cpu/scaling_governor" ]; then
                echo "ondemand" > "$cpu/scaling_governor" 2>/dev/null || true
            fi
            
            # 设置频率参数
            if [ -f "$cpu/scaling_min_freq" ]; then
                cat "$cpu/cpuinfo_min_freq" > "$cpu/scaling_min_freq" 2>/dev/null || true
            fi
            
            if [ -f "$cpu/scaling_max_freq" ]; then
                cat "$cpu/cpuinfo_max_freq" > "$cpu/scaling_max_freq" 2>/dev/null || true
            fi
            
            # 设置ondemand参数
            if [ -f "$cpu/scaling_governor" ] && grep -q "ondemand" "$cpu/scaling_governor"; then
                echo "50" > "$cpu/ondemand/up_threshold" 2>/dev/null || true
                echo "10" > "$cpu/ondemand/down_threshold" 2>/dev/null || true
                echo "1" > "$cpu/ondemand/sampling_rate" 2>/dev/null || true
                echo "10000" > "$cpu/ondemand/sampling_rate_min" 2>/dev/null || true
            fi
            
            # 设置性能参数
            if [ -f "$cpu/scaling_governor" ] && grep -q "performance" "$cpu/scaling_governor"; then
                # 性能模式下保持最高频率
                echo "1" > "$cpu/scaling_max_freq" 2>/dev/null || true
            fi
        done
        
        echo "CPU频率调节优化完成"
    else
        echo "CPU频率调节不可用"
    fi
    
    # 设置IRQ亲和性
    optimize_irq_affinity
}

optimize_irq_affinity() {
    echo "正在优化IRQ亲和性..."
    
    # 获取CPU核心数
    cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
    
    if [ "$cpu_cores" -gt 1 ]; then
        # 为每个中断设置CPU亲和性
        for irq in /proc/irq/*; do
            if [ -d "$irq" ] && [ -f "$irq/smp_affinity" ]; then
                # 根据核心数设置掩码
                if [ "$cpu_cores" -eq 2 ]; then
                    echo "2" > "$irq/smp_affinity" 2>/dev/null || true  # CPU1
                elif [ "$cpu_cores" -eq 4 ]; then
                    echo "2" > "$irq/smp_affinity" 2>/dev/null || true  # CPU1
                elif [ "$cpu_cores" -ge 8 ]; then
                    echo "aa" > "$irq/smp_affinity" 2>/dev/null || true  # 奇数CPU
                fi
            fi
        done
        
        # 网络中断优化
        if [ -f "/proc/irq/default_smp_affinity" ]; then
            if [ "$cpu_cores" -eq 2 ]; then
                echo "3" > /proc/irq/default_smp_affinity 2>/dev/null || true
            elif [ "$cpu_cores" -eq 4 ]; then
                echo "f" > /proc/irq/default_smp_affinity 2>/dev/null || true
            elif [ "$cpu_cores" -ge 8 ]; then
                echo "ff" > /proc/irq/default_smp_affinity 2>/dev/null || true
            fi
        fi
        
        echo "IRQ亲和性优化完成（CPU核心数: $cpu_cores）"
    else
        echo "单核CPU，跳过IRQ亲和性优化"
    fi
}

stop_service() {
    echo "停止CPU频率调节优化..."
    # 恢复默认调节器
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        if [ -f "$cpu/scaling_governor" ]; then
            echo "ondemand" > "$cpu/scaling_governor" 2>/dev/null || true
        fi
    done
}
EOF
    chmod +x "${prefix}/etc/init.d/cpufreq"
}

# ==================== 进程优先级优化脚本 ====================
create_process_priority() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/process-priority" << 'EOF'
#!/bin/sh
# 进程优先级优化脚本

CONFIG_FILE="/etc/process-priority.conf"
LOG_FILE="/var/log/process-priority.log"

# 默认优先级配置
DEFAULT_PRIORITIES="
# 格式: 进程名:nice值:ionice级别:ionice优先级
# nice值: -20（最高优先级）到19（最低优先级）
# ionice级别: 0=无, 1=实时, 2=尽力, 3=空闲
# ionice优先级: 0-7（仅对实时和尽力级别有效）

# 系统关键进程（高优先级）
init:-15:2:0
systemd:-10:2:0
udevd:-10:2:0

# 网络相关（较高优先级）
dnsmasq:-5:2:0
hostapd:-5:2:0
wpa_supplicant:-5:2:0
network:-5:2:0

# 用户交互进程（正常优先级）
dropbear:0:2:4
sshd:0:2:4
uhttpd:0:2:4

# 后台服务（较低优先级）
samba:5:2:6
vsftpd:5:2:6
transmission:5:2:6

# 批量任务（低优先级）
rsync:10:3:0
tar:10:3:0
gzip:10:3:0
backup:10:3:0
"

# 记录日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 设置进程优先级
set_process_priority() {
    local pid="$1"
    local name="$2"
    local nice_value="$3"
    local ionice_class="$4"
    local ionice_priority="$5"
    
    # 设置nice值（CPU优先级）
    if [ -n "$nice_value" ] && [ "$nice_value" != "null" ]; then
        renice -n "$nice_value" -p "$pid" 2>/dev/null || true
        log "进程 $name (PID:$pid) nice值设置为: $nice_value"
    fi
    
    # 设置ionice值（I/O优先级）
    if [ -n "$ionice_class" ] && [ "$ionice_class" != "null" ] && [ -x "$(command -v ionice)" ]; then
        if [ "$ionice_class" = "3" ]; then
            # 空闲级别
            ionice -c "$ionice_class" -p "$pid" 2>/dev/null || true
        elif [ -n "$ionice_priority" ] && [ "$ionice_priority" != "null" ]; then
            # 实时或尽力级别
            ionice -c "$ionice_class" -n "$ionice_priority" -p "$pid" 2>/dev/null || true
        fi
        log "进程 $name (PID:$pid) ionice设置为: class=$ionice_class, priority=$ionice_priority"
    fi
}

# 应用优先级配置
apply_priorities() {
    echo "正在应用进程优先级配置..."
    
    # 加载配置文件
    if [ -f "$CONFIG_FILE" ]; then
        PRIORITIES=$(cat "$CONFIG_FILE")
    else
        PRIORITIES="$DEFAULT_PRIORITIES"
        echo "$DEFAULT_PRIORITIES" > "$CONFIG_FILE"
    fi
    
    # 应用配置
    echo "$PRIORITIES" | grep -v "^#" | grep -v "^$" | while IFS=: read -r process_name nice_value ionice_class ionice_priority; do
        if [ -n "$process_name" ]; then
            # 查找匹配的进程
            pids=$(pgrep -f "$process_name" 2>/dev/null || echo "")
            
            for pid in $pids; do
                if [ -f "/proc/$pid/status" ]; then
                    set_process_priority "$pid" "$process_name" "$nice_value" "$ionice_class" "$ionice_priority"
                fi
            done
        fi
    done
    
    echo "进程优先级配置应用完成"
}

# 监控并调整进程优先级
monitor_processes() {
    echo "启动进程优先级监控..."
    log "进程优先级监控服务启动"
    
    while true; do
        # 检查新进程
        ps -eo pid,comm | grep -v PID | while read -r line; do
            pid=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            
            # 检查是否已有配置
            if grep -q "^$name:" "$CONFIG_FILE" 2>/dev/null; then
                # 读取配置
                config=$(grep "^$name:" "$CONFIG_FILE" | head -1)
                nice_value=$(echo "$config" | cut -d: -f2)
                ionice_class=$(echo "$config" | cut -d: -f3)
                ionice_priority=$(echo "$config" | cut -d: -f4)
                
                # 应用配置
                set_process_priority "$pid" "$name" "$nice_value" "$ionice_class" "$ionice_priority"
            fi
        done
        
        # 每30秒检查一次
        sleep 30
    done
}

# 显示当前优先级
show_current_priorities() {
    echo "当前进程优先级状态:"
    echo "========================================"
    printf "%-20s %-8s %-12s %-12s\n" "进程名" "PID" "Nice值" "IOnice"
    echo "----------------------------------------"
    
    ps -eo pid,comm,nice | grep -v PID | while read -r line; do
        pid=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        nice_value=$(echo "$line" | awk '{print $3}')
        
        # 获取ionice值
        if [ -x "$(command -v ionice)" ]; then
            ionice_output=$(ionice -p "$pid" 2>/dev/null || echo "none")
            ionice_str=$(echo "$ionice_output" | awk '{print $3 $4}')
        else
            ionice_str="N/A"
        fi
        
        printf "%-20s %-8s %-12s %-12s\n" "$name" "$pid" "$nice_value" "$ionice_str"
    done | head -30
}

# 优化系统服务启动顺序
optimize_boot_sequence() {
    echo "正在优化系统服务启动顺序..."
    
    # 关键网络服务优先
    for service in network firewall dnsmasq; do
        if [ -f "/etc/init.d/$service" ]; then
            # 设置较高的启动优先级
            sed -i "s/START=.*/START=10/" "/etc/init.d/$service" 2>/dev/null || true
            echo "服务 $service 启动优先级设置为 10"
        fi
    done
    
    # 用户服务稍后启动
    for service in samba vsftpd transmission; do
        if [ -f "/etc/init.d/$service" ]; then
            sed -i "s/START=.*/START=90/" "/etc/init.d/$service" 2>/dev/null || true
            echo "服务 $service 启动优先级设置为 90"
        fi
    done
    
    # 计划任务最后启动
    if [ -f "/etc/init.d/cron" ]; then
        sed -i "s/START=.*/START=99/" "/etc/init.d/cron" 2>/dev/null || true
        echo "服务 cron 启动优先级设置为 99"
    fi
    
    echo "系统服务启动顺序优化完成"
}

# 主函数
case "$1" in
    apply)
        apply_priorities
        ;;
    monitor)
        monitor_processes &
        echo $! > /var/run/process-priority.pid
        echo "进程优先级监控已启动 (PID: $!)"
        ;;
    stop)
        if [ -f /var/run/process-priority.pid ]; then
            kill $(cat /var/run/process-priority.pid) 2>/dev/null || true
            rm -f /var/run/process-priority.pid
        fi
        echo "进程优先级监控已停止"
        ;;
    status)
        show_current_priorities
        ;;
    optimize)
        optimize_boot_sequence
        ;;
    config)
        if [ -f "$CONFIG_FILE" ]; then
            cat "$CONFIG_FILE"
        else
            echo "$DEFAULT_PRIORITIES"
        fi
        ;;
    *)
        echo "进程优先级优化工具"
        echo "用法: $0 {apply|monitor|stop|status|optimize|config}"
        echo "  apply    - 应用优先级配置"
        echo "  monitor  - 启动优先级监控"
        echo "  stop     - 停止优先级监控"
        echo "  status   - 显示当前优先级状态"
        echo "  optimize - 优化服务启动顺序"
        echo "  config   - 显示配置文件"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/process-priority"
}

# ==================== Web界面配置 ====================
create_sched_web_interface() {
    local prefix="$1"
    
    # LuCI控制器
    cat > "${prefix}/usr/lib/lua/luci/controller/admin/sched-optimize.lua" << 'EOF'
module("luci.controller.admin.sched-optimize", package.seeall)

function index()
    entry({"admin", "system", "sched-optimize"}, template("admin_system/sched_optimize"), _("进程调度优化"), 76)
    entry({"admin", "system", "sched-optimize", "status"}, call("get_status")).leaf = true
    entry({"admin", "system", "sched-optimize", "apply"}, call("apply_priorities")).leaf = true
    entry({"admin", "system", "sched-optimize", "monitor"}, call("start_monitor")).leaf = true
    entry({"admin", "system", "sched-optimize", "stop"}, call("stop_monitor")).leaf = true
    entry({"admin", "system", "sched-optimize", "optimize"}, call("optimize_boot")).leaf = true
end

function get_status()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/process-priority status 2>&1")
    
    http.prepare_content("text/plain")
    http.write(result)
end

function apply_priorities()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/process-priority apply 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "进程优先级已应用"})
end

function start_monitor()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/process-priority monitor 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "进程优先级监控已启动"})
end

function stop_monitor()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/process-priority stop 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "进程优先级监控已停止"})
end

function optimize_boot()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/process-priority optimize 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "系统启动顺序已优化"})
end
EOF

    # Web界面
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/sched_optimize.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:系统进程调度优化%></h2>
    
    <!-- 信息提示 -->
    <div class="alert-message" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">⚡ 进程调度优化</h4>
        <p style="margin-bottom: 10px;">优化系统进程调度策略，提升关键服务响应速度，平衡系统负载。</p>
        <ul style="margin: 0; padding-left: 20px;">
            <li><strong>CPU调度：</strong>优化时间片分配，减少上下文切换</li>
            <li><strong>进程优先级：</strong>关键服务优先，批量任务延后</li>
            <li><strong>I/O调度：</strong>优化磁盘访问顺序，减少等待时间</li>
            <li><strong>启动优化：</strong>调整服务启动顺序，加快启动速度</li>
        </ul>
    </div>
    
    <!-- 进程状态 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:进程优先级状态%></h3>
        <div id="process-status" style="min-height: 300px; padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed; font-family: monospace; font-size: 12px; max-height: 400px; overflow-y: auto;">
            <div style="text-align: center; padding: 40px;">
                <div class="spinner"></div>
                <p>正在加载进程状态...</p>
            </div>
        </div>
        <div style="margin-top: 15px; display: flex; gap: 12px;">
            <button id="refresh-status" class="btn-primary" style="padding: 10px 20px;">
                <i class="icon icon-refresh"></i> 刷新状态
            </button>
            <button id="apply-priorities" class="btn-secondary" style="padding: 10px 20px;">
                <i class="icon icon-check"></i> 应用优先级
            </button>
        </div>
    </div>
    
    <!-- 监控控制 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:进程优先级监控%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:自动监控%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <button id="start-monitor" class="btn-success" style="padding: 10px 20px;">
                        <i class="icon icon-play"></i> 启动监控
                    </button>
                    <button id="stop-monitor" class="btn-danger" style="padding: 10px 20px;">
                        <i class="icon icon-stop"></i> 停止监控
                    </button>
                    <button id="optimize-boot" class="btn-warning" style="padding: 10px 20px;">
                        <i class="icon icon-rocket"></i> 优化启动
                    </button>
                </div>
                <p style="margin-top: 10px; color: #7f8c8d; font-size: 12px;">
                    监控服务会自动为新进程应用配置的优先级设置
                </p>
            </div>
        </div>
    </div>
    
    <!-- 配置说明 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:优先级配置说明%></h3>
        <div style="padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed;">
            <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
                <thead>
                    <tr style="background: #f8f9fa;">
                        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">级别</th>
                        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">Nice值</th>
                        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">I/O级别</th>
                        <th style="padding: 8px; border: 1px solid #ddd; text-align: left;">适用进程</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td style="padding: 8px; border: 1px solid #ddd;">最高</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">-20 ~ -10</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">实时(1)</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">内核、中断处理</td>
                    </tr>
                    <tr>
                        <td style="padding: 8px; border: 1px solid #ddd;">高</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">-9 ~ -1</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">尽力(2,0)</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">网络、交互服务</td>
                    </tr>
                    <tr>
                        <td style="padding: 8px; border: 1px solid #ddd;">普通</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">0 ~ 9</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">尽力(2,4)</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">Web服务、SSH</td>
                    </tr>
                    <tr>
                        <td style="padding: 8px; border: 1px solid #ddd;">低</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">10 ~ 19</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">尽力(2,7)</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">文件服务、备份</td>
                    </tr>
                    <tr>
                        <td style="padding: 8px; border: 1px solid #ddd;">空闲</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">19</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">空闲(3)</td>
                        <td style="padding: 8px; border: 1px solid #ddd;">批量任务、压缩</td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
    
    <!-- 操作状态 -->
    <div id="status-message" style="margin: 15px 0;"></div>
</div>

<script type="text/javascript">
// 显示状态消息
function showStatus(message, type) {
    var statusDiv = document.getElementById('status-message');
    var bgColor, textColor, borderColor;
    
    switch(type) {
        case 'success':
            bgColor = '#d4edda';
            textColor = '#155724';
            borderColor = '#c3e6cb';
            break;
        case 'error':
            bgColor = '#f8d7da';
            textColor = '#721c24';
            borderColor = '#f5c6cb';
            break;
        case 'warning':
            bgColor = '#fff3cd';
            textColor = '#856404';
            borderColor = '#ffeaa7';
            break;
        default:
            bgColor = '#d1ecf1';
            textColor = '#0c5460';
            borderColor = '#bee5eb';
    }
    
    statusDiv.innerHTML = '<div style="background: ' + bgColor + '; color: ' + textColor + '; border: 1px solid ' + borderColor + '; padding: 12px 15px; border-radius: 6px; margin: 10px 0;">' + message + '</div>';
    
    setTimeout(function() {
        statusDiv.innerHTML = '';
    }, 5000);
}

// 加载进程状态
function loadProcessStatus() {
    var statusDiv = document.getElementById('process-status');
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/sched-optimize/status")%>', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                // 将纯文本转换为HTML表格
                var lines = xhr.responseText.split('\n');
                var html = '<table style="width: 100%; border-collapse: collapse; font-family: monospace; font-size: 12px;">';
                
                for (var i = 0; i < lines.length; i++) {
                    var line = lines[i];
                    if (line.trim() === '') continue;
                    
                    if (i === 0 || line.includes('---')) {
                        // 表头或分隔线
                        html += '<tr style="background: #f8f9fa;">';
                        var cells = line.split(/\s+/).filter(cell => cell.length > 0);
                        cells.forEach(function(cell, index) {
                            if (i === 0) {
                                html += '<th style="padding: 6px 8px; border: 1px solid #ddd; text-align: left;">' + cell + '</th>';
                            }
                        });
                        html += '</tr>';
                    } else {
                        // 数据行
                        html += '<tr>';
                        var cells = line.split(/\s+/).filter(cell => cell.length > 0);
                        if (cells.length >= 4) {
                            var name = cells[0];
                            var pid = cells[1];
                            var nice = parseInt(cells[2]);
                            var ionice = cells.slice(3).join(' ');
                            
                            // 根据nice值设置颜色
                            var niceColor = '#34495e';
                            if (nice < 0) {
                                niceColor = '#27ae60';  // 高优先级
                            } else if (nice > 10) {
                                niceColor = '#e74c3c';  // 低优先级
                            } else if (nice > 5) {
                                niceColor = '#f39c12';  // 中低优先级
                            }
                            
                            html += '<td style="padding: 6px 8px; border: 1px solid #eee;">' + name + '</td>';
                            html += '<td style="padding: 6px 8px; border: 1px solid #eee;">' + pid + '</td>';
                            html += '<td style="padding: 6px 8px; border: 1px solid #eee; color: ' + niceColor + '; font-weight: 600;">' + nice + '</td>';
                            html += '<td style="padding: 6px 8px; border: 1px solid #eee;">' + ionice + '</td>';
                        }
                        html += '</tr>';
                    }
                }
                
                html += '</table>';
                statusDiv.innerHTML = html;
            } else {
                statusDiv.innerHTML = '<div class="alert-message error">加载状态失败</div>';
            }
        }
    };
    xhr.send();
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 加载初始状态
    loadProcessStatus();
    
    // 刷新状态按钮
    document.getElementById('refresh-status').addEventListener('click', function() {
        loadProcessStatus();
        showStatus('进程状态已刷新', 'info');
    });
    
    // 应用优先级按钮
    document.getElementById('apply-priorities').addEventListener('click', function() {
        if (confirm('确定要应用进程优先级配置吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 应用中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/sched-optimize/apply")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('进程优先级已应用', 'success');
                            setTimeout(function() {
                                loadProcessStatus();
                            }, 2000);
                        }
                    } catch (e) {
                        showStatus('应用失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 启动监控按钮
    document.getElementById('start-monitor').addEventListener('click', function() {
        if (confirm('确定要启动进程优先级监控吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 启动中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/sched-optimize/monitor")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('进程优先级监控已启动', 'success');
                        }
                    } catch (e) {
                        showStatus('启动失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 停止监控按钮
    document.getElementById('stop-monitor').addEventListener('click', function() {
        if (confirm('确定要停止进程优先级监控吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 停止中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/sched-optimize/stop")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('进程优先级监控已停止', 'success');
                        }
                    } catch (e) {
                        showStatus('停止失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 优化启动按钮
    document.getElementById('optimize-boot').addEventListener('click', function() {
        if (confirm('确定要优化系统服务启动顺序吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 优化中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/sched-optimize/optimize")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('系统启动顺序已优化', 'success');
                        }
                    } catch (e) {
                        showStatus('优化失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
});

// 添加CSS样式
var style = document.createElement('style');
style.textContent = `
.spinner {
    display: inline-block;
    width: 40px;
    height: 40px;
    border: 3px solid #f3f3f3;
    border-top: 3px solid #3498db;
    border-radius: 50%;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

.btn-primary, .btn-secondary, .btn-success, .btn-danger, .btn-warning {
    padding: 8px 16px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    text-align: center;
}

.btn-primary {
    background: #4CAF50;
    color: white;
}

.btn-secondary {
    background: #2196F3;
    color: white;
}

.btn-success {
    background: #28a745;
    color: white;
}

.btn-danger {
    background: #dc3545;
    color: white;
}

.btn-warning {
    background: #ffc107;
    color: #212529;
}

.btn-primary:hover, .btn-secondary:hover, .btn-success:hover, .btn-danger:hover, .btn-warning:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(0,0,0,0.15);
    opacity: 0.9;
}
`;
document.head.appendChild(style);
</script>
<%+footer%>
EOF
}

# ==================== 执行安装 ====================
create_sched_optimization "$INSTALL_DIR"
create_process_priority "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 创建Web界面
    create_sched_web_interface "$INSTALL_DIR"
    
    # 启用CPU频率调节服务
    /etc/init.d/cpufreq enable 2>/dev/null || true
    /etc/init.d/cpufreq start 2>/dev/null || true
    
    # 应用sysctl配置
    sysctl -p /etc/sysctl.d/99-sched-optimization.conf 2>/dev/null || true
    
    # 重启LuCI使新页面生效
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
    
    # 创建计划任务
    echo "# 进程调度优化任务" >> /etc/crontabs/root
    echo "*/10 * * * * /usr/sbin/process-priority apply >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 3 * * * /etc/init.d/cpufreq restart >/dev/null 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ 系统进程调度优化已应用"
    echo ""
    echo "【访问方式】:"
    echo "   LuCI界面 → 系统 → 进程调度优化"
    echo ""
    echo "【手动操作】:"
    echo "   查看状态: process-priority status"
    echo "   应用配置: process-priority apply"
    echo "   启动监控: process-priority monitor"
else
    create_sched_web_interface "$INSTALL_DIR"
    echo "✓ 系统进程调度优化已集成到固件"
fi

echo "系统进程调度优化配置完成！"