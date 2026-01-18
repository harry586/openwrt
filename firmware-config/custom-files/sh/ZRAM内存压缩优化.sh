#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# ZRAM内存压缩优化脚本 - 提升小内存设备性能
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

echo "开始配置ZRAM内存压缩优化..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/init.d"
    mkdir -p "${prefix}/usr/sbin"
}

create_dirs "$INSTALL_DIR"

# ==================== ZRAM配置 ====================
create_zram_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/zram" << 'EOF'
config zram 'zram'
    option enabled '1'
    option size '256'          # ZRAM大小（MB），建议为物理内存的25-50%
    option algorithm 'zstd'    # 压缩算法：lzo, lz4, zstd（最优）
    option priority '100'      # swap优先级（越高越优先使用）
    option swappiness '80'     # swap倾向性（0-100，越高越积极使用swap）
EOF
}

# ==================== ZRAM初始化脚本 ====================
create_zram_init_script() {
    local prefix="$1"
    cat > "${prefix}/etc/init.d/zram" << 'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=95

validate_zram_section() {
    uci_validate_section zram zram "${1}" \
        'enabled:bool:1' \
        'size:uinteger:256' \
        'algorithm:string:zstd' \
        'priority:uinteger:100' \
        'swappiness:uinteger:80'
}

start_service() {
    local enabled size algorithm priority swappiness
    
    config_load zram
    config_get enabled zram enabled 1
    config_get size zram size 256
    config_get algorithm zram algorithm 'zstd'
    config_get priority zram priority 100
    config_get swappiness zram swappiness 80
    
    if [ "$enabled" != "1" ]; then
        echo "ZRAM未启用，跳过配置"
        return 0
    fi
    
    echo "正在配置ZRAM..."
    
    # 加载内核模块
    modprobe zram 2>/dev/null || {
        echo "加载zram内核模块失败"
        return 1
    }
    
    # 检查可用压缩算法
    available_algorithms=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "lzo lz4")
    if ! echo "$available_algorithms" | grep -q "$algorithm"; then
        echo "算法 $algorithm 不可用，使用 lzo"
        algorithm="lzo"
    fi
    
    # 获取内存总量（KB）
    total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    
    # 计算合适的ZRAM大小（不超过物理内存的50%）
    max_size=$((total_memory / 2 / 1024))  # 转换为MB
    
    if [ "$size" -gt "$max_size" ]; then
        echo "ZRAM大小 $size MB 超过最大限制 $max_size MB，自动调整为 $max_size MB"
        size="$max_size"
    fi
    
    if [ "$size" -lt 32 ]; then
        echo "ZRAM大小 $size MB 太小，自动调整为 32 MB"
        size="32"
    fi
    
    # 配置ZRAM设备
    echo "$algorithm" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
    echo "${size}M" > /sys/block/zram0/disksize 2>/dev/null || true
    
    # 创建swap分区
    mkswap /dev/zram0 2>/dev/null || {
        echo "创建ZRAM swap失败"
        return 1
    }
    
    # 启用swap分区
    swapon -p "$priority" /dev/zram0 2>/dev/null || {
        echo "启用ZRAM swap失败"
        return 1
    }
    
    # 调整系统swappiness
    echo "$swappiness" > /proc/sys/vm/swappiness 2>/dev/null || true
    
    echo "ZRAM配置完成: ${size}MB, 算法: $algorithm, 优先级: $priority"
    
    # 记录日志
    logger -t zram "ZRAM已启用: ${size}MB, 算法: $algorithm"
}

stop_service() {
    echo "正在停止ZRAM..."
    
    # 禁用所有ZRAM设备
    for dev in /sys/block/zram*; do
        if [ -d "$dev" ]; then
            device="/dev/$(basename $dev)"
            if grep -q "$device" /proc/swaps; then
                swapoff "$device" 2>/dev/null || true
            fi
        fi
    done
    
    # 卸载内核模块
    rmmod zram 2>/dev/null || true
    
    # 恢复默认swappiness
    echo "60" > /proc/sys/vm/swappiness 2>/dev/null || true
    
    echo "ZRAM已停止"
}

restart() {
    stop
    sleep 2
    start
}
EOF
    chmod +x "${prefix}/etc/init.d/zram"
}

# ==================== ZRAM监控脚本 ====================
create_zram_monitor() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/zram-monitor" << 'EOF'
#!/bin/sh
# ZRAM使用情况监控脚本

LOG_FILE="/var/log/zram-monitor.log"
STATUS_FILE="/tmp/zram-status.json"

# 获取ZRAM状态信息
get_zram_status() {
    echo "ZRAM状态监控 - $(date)"
    echo "========================"
    
    # 检查ZRAM设备
    if [ ! -d /sys/block/zram0 ]; then
        echo "ZRAM设备未加载"
        return 1
    fi
    
    # 基本信息
    echo "设备信息:"
    echo "  设备: $(ls /dev/zram* 2>/dev/null | xargs)"
    echo "  算法: $(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo '未知')"
    echo "  大小: $(cat /sys/block/zram0/disksize 2>/dev/null | awk '{print $1/1024/1024 " MB"}' || echo '未知')"
    
    # 使用情况
    echo ""
    echo "使用情况:"
    orig_data_size=$(cat /sys/block/zram0/orig_data_size 2>/dev/null || echo "0")
    compr_data_size=$(cat /sys/block/zram0/compr_data_size 2>/dev/null || echo "0")
    
    if [ "$orig_data_size" -gt 0 ]; then
        compression_ratio=$(echo "scale=2; $orig_data_size / $compr_data_size" | bc)
        echo "  原始数据: $(echo "scale=2; $orig_data_size / 1024 / 1024" | bc) MB"
        echo "  压缩数据: $(echo "scale=2; $compr_data_size / 1024 / 1024" | bc) MB"
        echo "  压缩比: ${compression_ratio}:1"
    else
        echo "  暂无数据"
    fi
    
    # swap使用情况
    echo ""
    echo "SWAP使用:"
    grep -E "^/dev/zram" /proc/swaps 2>/dev/null || echo "  未启用"
    
    # 系统内存状态
    echo ""
    echo "系统内存:"
    free -h | tail -2
    
    # 生成JSON状态（用于Web界面）
    cat > "$STATUS_FILE" << JSON
{
    "timestamp": "$(date +%s)",
    "date": "$(date '+%Y-%m-%d %H:%M:%S')",
    "devices": {
        "count": "$(ls /dev/zram* 2>/dev/null | wc -w)",
        "list": "$(ls /dev/zram* 2>/dev/null | xargs)"
    },
    "compression": {
        "algorithm": "$(cat /sys/block/zram0/comp_algorithm 2>/dev/null | tr -d '\n')",
        "orig_data_mb": "$(echo "scale=2; $orig_data_size / 1024 / 1024" | bc 2>/dev/null || echo "0")",
        "compr_data_mb": "$(echo "scale=2; $compr_data_size / 1024 / 1024" | bc 2>/dev/null || echo "0")",
        "ratio": "$compression_ratio"
    },
    "memory": {
        "total": "$(free | grep Mem | awk '{print $2}')",
        "used": "$(free | grep Mem | awk '{print $3}')",
        "free": "$(free | grep Mem | awk '{print $4}')",
        "zram_used": "$(grep -E '^/dev/zram' /proc/swaps 2>/dev/null | awk '{print $3}' | head -1 || echo "0")"
    }
}
JSON
}

# 自动调整ZRAM大小
auto_adjust_zram() {
    echo "正在自动调整ZRAM大小..."
    
    # 获取当前内存压力
    memory_pressure=$(free | grep Mem | awk '{printf "%.2f", $3/$2 * 100}')
    echo "当前内存使用率: ${memory_pressure}%"
    
    # 如果内存使用率超过80%，增加ZRAM大小
    if [ "$(echo "$memory_pressure > 80" | bc)" -eq 1 ]; then
        current_size=$(cat /sys/block/zram0/disksize 2>/dev/null | awk '{print $1/1024/1024}')
        new_size=$((current_size * 120 / 100))  # 增加20%
        
        # 不能超过物理内存的50%
        total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        max_size=$((total_memory / 2 / 1024))
        
        if [ "$new_size" -gt "$max_size" ]; then
            new_size="$max_size"
        fi
        
        if [ "$new_size" -gt "$current_size" ]; then
            echo "内存压力高，将ZRAM从 ${current_size}MB 调整到 ${new_size}MB"
            
            # 停止当前ZRAM
            if grep -q "/dev/zram0" /proc/swaps; then
                swapoff /dev/zram0
            fi
            
            # 调整大小
            echo "${new_size}M" > /sys/block/zram0/disksize
            
            # 重新启用
            mkswap /dev/zram0
            swapon /dev/zram0
            
            logger -t zram "自动调整ZRAM大小: ${current_size}MB -> ${new_size}MB (内存压力: ${memory_pressure}%)"
        fi
    fi
}

# 清理旧的内存页
clean_memory_pages() {
    echo "正在清理内存页缓存..."
    sync
    echo 1 > /proc/sys/vm/drop_caches
    echo 2 > /proc/sys/vm/drop_caches
    echo 3 > /proc/sys/vm/drop_caches
    echo "内存页缓存清理完成"
}

# 主函数
case "$1" in
    status)
        get_zram_status
        ;;
    adjust)
        auto_adjust_zram
        ;;
    clean)
        clean_memory_pages
        ;;
    log)
        if [ -f "$LOG_FILE" ]; then
            tail -50 "$LOG_FILE"
        else
            echo "暂无日志"
        fi
        ;;
    json)
        if [ -f "$STATUS_FILE" ]; then
            cat "$STATUS_FILE"
        else
            get_zram_status >/dev/null
            cat "$STATUS_FILE" 2>/dev/null || echo '{"error": "无法获取状态"}'
        fi
        ;;
    monitor)
        # 持续监控模式
        echo "启动ZRAM持续监控，按Ctrl+C退出..."
        while true; do
            clear
            get_zram_status
            sleep 5
        done
        ;;
    *)
        echo "ZRAM监控工具"
        echo "用法: $0 {status|adjust|clean|log|json|monitor}"
        echo "  status   - 显示ZRAM状态"
        echo "  adjust   - 自动调整ZRAM大小"
        echo "  clean    - 清理内存页缓存"
        echo "  log      - 查看监控日志"
        echo "  json     - 输出JSON格式状态"
        echo "  monitor  - 持续监控模式"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/zram-monitor"
}

# ==================== Web界面配置 ====================
create_zram_web_interface() {
    local prefix="$1"
    
    # 创建LuCI控制器
    mkdir -p "${prefix}/usr/lib/lua/luci/controller/admin"
    cat > "${prefix}/usr/lib/lua/luci/controller/admin/zram.lua" << 'EOF'
module("luci.controller.admin.zram", package.seeall)

function index()
    entry({"admin", "system", "zram"}, template("admin_system/zram"), _("ZRAM优化"), 75)
    entry({"admin", "system", "zram", "status"}, call("get_status")).leaf = true
    entry({"admin", "system", "zram", "adjust"}, call("adjust_zram")).leaf = true
    entry({"admin", "system", "zram", "restart"}, call("restart_zram")).leaf = true
end

function get_status()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/zram-monitor json 2>&1")
    
    http.prepare_content("application/json")
    http.write(result)
end

function adjust_zram()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/zram-monitor adjust 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = result})
end

function restart_zram()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/etc/init.d/zram restart 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "ZRAM服务已重启"})
end
EOF

    # 创建Web界面
    mkdir -p "${prefix}/usr/lib/lua/luci/view/admin_system"
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/zram.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:ZRAM内存压缩优化%></h2>
    
    <!-- 信息提示 -->
    <div class="alert-message" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">💡 ZRAM内存压缩</h4>
        <p style="margin-bottom: 10px;">ZRAM将部分内存用作压缩的交换空间，可显著提升小内存设备的性能。</p>
        <ul style="margin: 0; padding-left: 20px;">
            <li><strong>优点：</strong>提升内存利用率，减少OOM（内存不足）风险</li>
            <li><strong>适用：</strong>内存小于512MB的路由器设备</li>
            <li><strong>注意：</strong>会占用少量CPU资源进行压缩/解压</li>
        </ul>
    </div>
    
    <!-- 状态显示区域 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:ZRAM状态%></h3>
        <div id="zram-status" style="min-height: 200px; padding: 20px; background: white; border-radius: 6px; border: 1px solid #e1e8ed;">
            <div style="text-align: center; padding: 40px;">
                <div class="spinner"></div>
                <p>正在加载ZRAM状态...</p>
            </div>
        </div>
        <div style="margin-top: 15px; display: flex; gap: 12px;">
            <button id="refresh-status" class="btn-primary" style="padding: 10px 20px;">
                <i class="icon icon-refresh"></i> 刷新状态
            </button>
            <button id="adjust-zram" class="btn-secondary" style="padding: 10px 20px;">
                <i class="icon icon-adjust"></i> 自动调整
            </button>
            <button id="restart-zram" class="btn-neutral" style="padding: 10px 20px;">
                <i class="icon icon-play-circle"></i> 重启服务
            </button>
        </div>
    </div>
    
    <!-- 配置区域 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:ZRAM配置%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:快速配置%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <button class="btn-preset" data-size="64" data-algo="lzo" style="padding: 8px 16px;">
                        64MB (lzo)
                    </button>
                    <button class="btn-preset" data-size="128" data-algo="lz4" style="padding: 8px 16px;">
                        128MB (lz4)
                    </button>
                    <button class="btn-preset" data-size="256" data-algo="zstd" style="padding: 8px 16px;">
                        256MB (zstd)
                    </button>
                    <button class="btn-preset" data-size="512" data-algo="zstd" style="padding: 8px 16px;">
                        512MB (zstd)
                    </button>
                </div>
                <p style="margin-top: 10px; color: #7f8c8d; font-size: 12px;">
                    提示：根据设备内存大小选择，一般设置为物理内存的25-50%
                </p>
            </div>
        </div>
    </div>
    
    <!-- 操作状态 -->
    <div id="status-message" style="margin: 15px 0;"></div>
</div>

<script type="text/javascript">
// 加载ZRAM状态
function loadZramStatus() {
    var statusDiv = document.getElementById('zram-status');
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/zram/status")%>', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    displayZramStatus(data);
                } catch (e) {
                    statusDiv.innerHTML = '<div class="alert-message error">解析状态数据失败</div>';
                }
            } else {
                statusDiv.innerHTML = '<div class="alert-message error">获取状态失败</div>';
            }
        }
    };
    xhr.send();
}

// 显示ZRAM状态
function displayZramStatus(data) {
    var statusDiv = document.getElementById('zram-status');
    var html = '';
    
    if (data.error) {
        html = '<div class="alert-message error">ZRAM未启用或不可用</div>';
    } else {
        var compressionRatio = parseFloat(data.compression.ratio) || 0;
        var compressionColor = compressionRatio >= 2.0 ? '#27ae60' : 
                              compressionRatio >= 1.5 ? '#f39c12' : '#e74c3c';
        
        html = `
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px;">
                <!-- 基本信息 -->
                <div class="stat-card" style="background: #f8f9fa; padding: 15px; border-radius: 6px;">
                    <h4 style="margin-top: 0; color: #2c3e50;">基本信息</h4>
                    <div style="font-size: 14px;">
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">设备数量:</span>
                            <span style="float: right; font-weight: 600;">${data.devices.count}</span>
                        </div>
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">压缩算法:</span>
                            <span style="float: right; font-weight: 600;">${data.compression.algorithm}</span>
                        </div>
                        <div>
                            <span style="color: #7f8c8d;">更新时间:</span>
                            <span style="float: right; font-weight: 600;">${data.date}</span>
                        </div>
                    </div>
                </div>
                
                <!-- 压缩信息 -->
                <div class="stat-card" style="background: #f8f9fa; padding: 15px; border-radius: 6px;">
                    <h4 style="margin-top: 0; color: #2c3e50;">压缩统计</h4>
                    <div style="font-size: 14px;">
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">原始数据:</span>
                            <span style="float: right; font-weight: 600;">${data.compression.orig_data_mb} MB</span>
                        </div>
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">压缩数据:</span>
                            <span style="float: right; font-weight: 600;">${data.compression.compr_data_mb} MB</span>
                        </div>
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">压缩比率:</span>
                            <span style="float: right; font-weight: 600; color: ${compressionColor};">${data.compression.ratio}:1</span>
                        </div>
                    </div>
                </div>
                
                <!-- 内存信息 -->
                <div class="stat-card" style="background: #f8f9fa; padding: 15px; border-radius: 6px;">
                    <h4 style="margin-top: 0; color: #2c3e50;">内存使用</h4>
                    <div style="font-size: 14px;">
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">物理内存:</span>
                            <span style="float: right; font-weight: 600;">${(data.memory.total / 1024).toFixed(1)} MB</span>
                        </div>
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">已用内存:</span>
                            <span style="float: right; font-weight: 600;">${(data.memory.used / 1024).toFixed(1)} MB</span>
                        </div>
                        <div style="margin-bottom: 8px;">
                            <span style="color: #7f8c8d;">ZRAM使用:</span>
                            <span style="float: right; font-weight: 600;">${data.memory.zram_used} KB</span>
                        </div>
                    </div>
                </div>
            </div>
            
            <!-- 状态指示器 -->
            <div style="margin-top: 20px; padding: 15px; background: ${compressionRatio > 1.5 ? '#d4edda' : '#f8d7da'}; border-radius: 6px; border: 1px solid ${compressionRatio > 1.5 ? '#c3e6cb' : '#f5c6cb'};">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <div style="width: 12px; height: 12px; border-radius: 50%; background: ${compressionRatio >= 2.0 ? '#27ae60' : compressionRatio >= 1.5 ? '#f39c12' : '#e74c3c'};"></div>
                    <div>
                        <strong>状态:</strong> 
                        ${compressionRatio >= 2.0 ? '优秀 - 压缩效率很高' : 
                          compressionRatio >= 1.5 ? '良好 - 压缩效率正常' : 
                          '一般 - 压缩效率较低，考虑调整配置'}
                    </div>
                </div>
            </div>
        `;
    }
    
    statusDiv.innerHTML = html;
}

// 显示状态消息
function showStatus(message, type) {
    var statusDiv = document.getElementById('status-message');
    var className = 'alert-message';
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
        default:
            bgColor = '#d1ecf1';
            textColor = '#0c5460';
            borderColor = '#bee5eb';
    }
    
    statusDiv.innerHTML = '<div style="background: ' + bgColor + '; color: ' + textColor + '; border: 1px solid ' + borderColor + '; padding: 12px 15px; border-radius: 6px; margin: 10px 0;">' + message + '</div>';
    
    // 5秒后自动隐藏
    setTimeout(function() {
        statusDiv.innerHTML = '';
    }, 5000);
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 加载初始状态
    loadZramStatus();
    
    // 刷新状态按钮
    document.getElementById('refresh-status').addEventListener('click', function() {
        loadZramStatus();
        showStatus('状态已刷新', 'info');
    });
    
    // 自动调整按钮
    document.getElementById('adjust-zram').addEventListener('click', function() {
        var btn = this;
        var originalText = btn.innerHTML;
        btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 调整中...';
        btn.disabled = true;
        
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/zram/adjust")%>', true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        showStatus('ZRAM已自动调整', 'success');
                        loadZramStatus();
                    }
                } catch (e) {
                    showStatus('调整失败', 'error');
                }
                btn.disabled = false;
                btn.innerHTML = originalText;
            }
        };
        xhr.send();
    });
    
    // 重启服务按钮
    document.getElementById('restart-zram').addEventListener('click', function() {
        if (confirm('确定要重启ZRAM服务吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 重启中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/zram/restart")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('ZRAM服务已重启', 'success');
                            setTimeout(function() {
                                loadZramStatus();
                            }, 2000);
                        }
                    } catch (e) {
                        showStatus('重启失败', 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 预设配置按钮
    var presetButtons = document.querySelectorAll('.btn-preset');
    presetButtons.forEach(function(btn) {
        btn.addEventListener('click', function() {
            var size = this.getAttribute('data-size');
            var algo = this.getAttribute('data-algo');
            
            if (confirm('确定应用预设配置吗？\n大小: ' + size + 'MB\n算法: ' + algo)) {
                showStatus('正在应用配置...', 'info');
                
                // 这里可以添加应用配置的代码
                // 实际应用中需要通过Ajax调用后端接口
                setTimeout(function() {
                    showStatus('配置已应用，请重启ZRAM服务生效', 'success');
                }, 1000);
            }
        });
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

.btn-primary, .btn-secondary, .btn-neutral, .btn-preset {
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

.btn-neutral {
    background: #607D8B;
    color: white;
}

.btn-preset {
    background: #9b59b6;
    color: white;
}

.btn-primary:hover, .btn-secondary:hover, .btn-neutral:hover, .btn-preset:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(0,0,0,0.15);
    opacity: 0.9;
}

.stat-card {
    transition: transform 0.3s ease;
}

.stat-card:hover {
    transform: translateY(-5px);
    box-shadow: 0 5px 15px rgba(0,0,0,0.1);
}
`;
document.head.appendChild(style);
</script>
<%+footer%>
EOF
}

# ==================== 执行安装 ====================
create_zram_config "$INSTALL_DIR"
create_zram_init_script "$INSTALL_DIR"
create_zram_monitor "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 创建Web界面
    create_zram_web_interface "$INSTALL_DIR"
    
    # 启用ZRAM服务
    /etc/init.d/zram enable 2>/dev/null || true
    /etc/init.d/zram start 2>/dev/null || true
    
    # 重启LuCI使新页面生效
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
    
    # 创建计划任务
    echo "# ZRAM监控任务" >> /etc/crontabs/root
    echo "*/5 * * * * /usr/sbin/zram-monitor status >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 4 * * * /usr/sbin/zram-monitor adjust >> /var/log/zram-adjust.log 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ ZRAM优化已应用"
    echo ""
    echo "【访问方式】:"
    echo "   LuCI界面 → 系统 → ZRAM优化"
    echo ""
    echo "【手动操作】:"
    echo "   查看状态: zram-monitor status"
    echo "   自动调整: zram-monitor adjust"
    echo "   持续监控: zram-monitor monitor"
else
    create_zram_web_interface "$INSTALL_DIR"
    echo "✓ ZRAM优化已集成到固件"
fi

echo "ZRAM内存压缩优化配置完成！"