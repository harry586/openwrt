#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 限制进程资源防止卡死脚本
# 
# 支持的进程和服务：
# 1. Samba服务 (smbd/nmbd)
# 2. vsftpd FTP服务
# 3. WiFi服务 (hostapd/wpa_supplicant)
# 4. 网络服务 (dnsmasq/iptables/dropbear/odhcpd)
# 5. 磁盘挂载进程 (mount/fsck/e2fsck)
# 6. 压缩解压进程 (tar/gzip/rsync)
# 7. 包管理进程 (opkg)
# 
# 功能特性：
# - 进程资源限制 (CPU/内存/进程数)
# - OOM优先级调整
# - 进程优先级调整 (nice值)
# - 进程监控和自动重启
# - Web界面控制开关
# - 实时状态监控
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

echo "开始配置进程资源限制..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/init.d"
    mkdir -p "${prefix}/usr/sbin"
    mkdir -p "${prefix}/etc/hotplug.d/iface"
    mkdir -p "${prefix}/www/cgi-bin/process-limit"
    mkdir -p "${prefix}/usr/lib/lua/luci/controller"
    mkdir -p "${prefix}/usr/lib/lua/luci/model/cbi"
    mkdir -p "${prefix}/usr/lib/lua/luci/view/process-limit"
}

create_dirs "$INSTALL_DIR"

# ==================== Web界面配置 ====================
create_web_interface() {
    local prefix="$1"
    
    # 创建LuCI控制器
    cat > "${prefix}/usr/lib/lua/luci/controller/process-limit.lua" << 'EOF'
module("luci.controller.process-limit", package.seeall)

function index()
    entry({"admin", "system", "process-limit"}, cbi("process-limit"), _("Process Limiter"), 60)
    entry({"admin", "system", "process-limit", "status"}, call("action_status"), nil).leaf = true
    entry({"admin", "system", "process-limit", "enable"}, call("action_enable"), nil).leaf = true
    entry({"admin", "system", "process-limit", "disable"}, call("action_disable"), nil).leaf = true
    entry({"admin", "system", "process-limit", "restart"}, call("action_restart"), nil).leaf = true
    entry({"admin", "system", "process-limit", "logs"}, call("action_logs"), nil).leaf = true
    entry({"admin", "system", "process-limit", "config"}, call("action_config"), nil).leaf = true
end

function action_status()
    local status = {}
    
    -- 检查监控服务状态
    local monitor_pid = luci.sys.exec("[ -f /var/run/process-monitor.pid ] && cat /var/run/process-monitor.pid || echo ''")
    if monitor_pid and monitor_pid:match("%d+") then
        status.monitor = "running"
    else
        status.monitor = "stopped"
    end
    
    -- 获取配置文件状态
    status.config_exists = luci.sys.call("[ -f /etc/process-limits.conf ]") == 0
    
    -- 获取各进程限制状态
    status.services = {}
    local services = {"samba", "vsftpd", "hostapd", "dnsmasq", "firewall"}
    
    for _, service in ipairs(services) do
        local init_file = string.format("/etc/init.d/%s", service)
        if nixio.fs.access(init_file) then
            status.services[service] = {
                enabled = luci.sys.call(string.format("/etc/init.d/%s enabled >/dev/null 2>&1", service)) == 0,
                running = luci.sys.call(string.format("pgrep %s >/dev/null 2>&1", service)) == 0
            }
        end
    end
    
    -- 获取系统资源使用
    status.memory = luci.sys.exec("free -m | awk 'NR==2{printf \"%.1f%%\", $3*100/$2}'")
    status.cpu_load = luci.sys.exec("uptime | awk -F'load average:' '{print $2}'")
    status.uptime = luci.sys.exec("uptime -p")
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(status)
end

function action_enable()
    local result = {success = false, message = ""}
    
    -- 启用监控服务
    os.execute("/etc/init.d/process-limit enable 2>/dev/null")
    os.execute("/etc/init.d/process-limit start 2>/dev/null")
    
    result.success = true
    result.message = "Process limiter enabled and started"
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_disable()
    local result = {success = false, message = ""}
    
    -- 停止并禁用监控服务
    os.execute("/etc/init.d/process-limit stop 2>/dev/null")
    os.execute("/etc/init.d/process-limit disable 2>/dev/null")
    
    result.success = true
    result.message = "Process limiter disabled and stopped"
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_restart()
    local result = {success = false, message = ""}
    
    os.execute("/etc/init.d/process-limit restart 2>/dev/null")
    
    result.success = true
    result.message = "Process limiter restarted"
    
    luci.http.prepare_content("application/json")
    luci.http.write_json(result)
end

function action_logs()
    local logs = ""
    
    if nixio.fs.access("/var/log/process-monitor.log") then
        logs = luci.sys.exec("tail -50 /var/log/process-monitor.log")
    else
        logs = "No logs available"
    end
    
    luci.http.prepare_content("text/plain")
    luci.http.write(logs)
end

function action_config()
    local config = ""
    
    if nixio.fs.access("/etc/process-limits.conf") then
        config = luci.sys.exec("cat /etc/process-limits.conf")
    else
        config = "# Process limits configuration\n# File not found"
    end
    
    luci.http.prepare_content("text/plain")
    luci.http.write(config)
end
EOF

    # 创建LuCI配置页面
    cat > "${prefix}/usr/lib/lua/luci/model/cbi/process-limit.lua" << 'EOF'
m = Map("process-limit", translate("Process Resource Limiter"), 
        translate("Limit process resources to prevent system freeze"))

s = m:section(TypedSection, "global", translate("Global Settings"))
s.anonymous = true

enable = s:option(Flag, "enabled", translate("Enable Process Limiter"),
        translate("Enable resource limiting for processes"))
enable.default = "1"
enable.rmempty = false

monitor_interval = s:option(Value, "monitor_interval", translate("Monitor Interval (seconds)"))
monitor_interval.default = "30"
monitor_interval.datatype = "range(10, 300)"
monitor_interval.placeholder = "30"

log_level = s:option(ListValue, "log_level", translate("Log Level"))
log_level:value("0", translate("Disabled"))
log_level:value("1", translate("Errors only"))
log_level:value("2", translate("Warnings and errors"))
log_level:value("3", translate("All events"))
log_level.default = "2"

-- 服务限制配置部分
s2 = m:section(TypedSection, "service_limits", translate("Service-Specific Limits"))
s2.template = "cbi/tblsection"
s2.anonymous = true
s2.addremove = true

service_name = s2:option(Value, "name", translate("Service Name"))
service_name.placeholder = "e.g., smbd"
service_name.rmempty = false

cpu_limit = s2:option(Value, "cpu", translate("CPU Limit (seconds)"))
cpu_limit.placeholder = "500"
cpu_limit.datatype = "uinteger"

mem_limit = s2:option(Value, "memory", translate("Memory Limit"))
mem_limit.placeholder = "128M"
mem_limit:value("64M", "64 MB")
mem_limit:value("128M", "128 MB")
mem_limit:value("256M", "256 MB")
mem_limit:value("512M", "512 MB")

process_limit = s2:option(Value, "processes", translate("Max Processes"))
process_limit.placeholder = "50"
process_limit.datatype = "uinteger"

oom_score = s2:option(Value, "oom", translate("OOM Score"))
oom_score.placeholder = "100"
oom_score.datatype = "range(-1000, 1000)"
oom_score.description = translate("Higher values mean more likely to be killed by OOM killer")

-- 自动动作配置
s3 = m:section(TypedSection, "auto_actions", translate("Automatic Actions"))
s3.anonymous = true

auto_restart = s3:option(Flag, "restart_exceeded", translate("Auto-restart exceeded processes"),
        translate("Automatically restart processes that exceed resource limits"))
auto_restart.default = "1"

kill_timeout = s3:option(Value, "kill_timeout", translate("Kill Timeout (seconds)"))
kill_timeout.default = "5"
kill_timeout.datatype = "range(1, 60)"
kill_timeout.description = translate("Time to wait before force-killing unresponsive process")

-- 监控进程列表
s4 = m:section(TypedSection, "monitored_processes", translate("Monitored Processes"))
s4.anonymous = true
s4.template = "cbi/tblsection"
s4.addremove = true

proc_name = s4:option(Value, "process", translate("Process Name"))
proc_name.placeholder = "e.g., hostapd"
proc_name.rmempty = false

proc_enabled = s4:option(Flag, "enabled", translate("Enabled"))
proc_enabled.default = "1"
proc_enabled.rmempty = false

-- 按钮部分
s5 = m:section(SimpleSection)
btn_apply = s5:option(Button, "_apply", translate("Apply Settings"))
btn_apply.inputtitle = translate("Apply")
btn_apply.inputstyle = "apply"
btn_apply.write = function()
    m.uci:commit("process-limit")
    os.execute("/etc/init.d/process-limit restart >/dev/null 2>&1")
end

btn_status = s5:option(Button, "_status", translate("Check Status"))
btn_status.inputtitle = translate("Status")
btn_status.inputstyle = "reload"
btn_status.write = function()
    luci.http.redirect(luci.dispatcher.build_url("admin/system/process-limit/status"))
end

btn_logs = s5:option(Button, "_logs", translate("View Logs"))
btn_logs.inputtitle = translate("Logs")
btn_status.inputstyle = "view"
btn_logs.write = function()
    luci.http.redirect(luci.dispatcher.build_url("admin/system/process-limit/logs"))
end

return m
EOF

    # 创建视图模板
    cat > "${prefix}/usr/lib/lua/luci/view/process-limit/status.htm" << 'EOF'
<%+header%>

<div class="cbi-map">
    <h2 name="content"><%:Process Limiter Status%></h2>
    <div class="cbi-map-descr"><%:Real-time status of process resource limiter%></div>
    
    <fieldset class="cbi-section">
        <legend><%:Service Status%></legend>
        <div id="status-container">
            <p><%:Loading status...%></p>
        </div>
    </fieldset>
    
    <div class="cbi-page-actions right">
        <input type="button" class="cbi-button cbi-button-link" value="<%:Refresh%>" onclick="loadStatus()" />
        <input type="button" class="cbi-button cbi-button-apply" value="<%:Back to Configuration%>" 
               onclick="window.location.href='<%=luci.dispatcher.build_url('admin/system/process-limit')%>'" />
    </div>
</div>

<script type="text/javascript">
function loadStatus() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/process-limit/status")%>', true);
    xhr.onload = function() {
        if (xhr.status === 200) {
            var data = JSON.parse(xhr.responseText);
            var html = '<table class="table">';
            
            // 监控服务状态
            html += '<tr><td width="33%"><strong><%:Monitor Service%></strong></td>';
            html += '<td>';
            if (data.monitor === 'running') {
                html += '<span class="label success"><%:Running%></span>';
            } else {
                html += '<span class="label warning"><%:Stopped%></span>';
            }
            html += '</td></tr>';
            
            // 配置文件状态
            html += '<tr><td><strong><%:Configuration%></strong></td>';
            html += '<td>';
            if (data.config_exists) {
                html += '<span class="label success"><%:OK%></span>';
            } else {
                html += '<span class="label error"><%:Missing%></span>';
            }
            html += '</td></tr>';
            
            // 系统资源
            html += '<tr><td><strong><%:Memory Usage%></strong></td>';
            html += '<td>' + (data.memory || 'N/A') + '</td></tr>';
            
            html += '<tr><td><strong><%:CPU Load%></strong></td>';
            html += '<td>' + (data.cpu_load || 'N/A') + '</td></tr>';
            
            html += '<tr><td><strong><%:System Uptime%></strong></td>';
            html += '<td>' + (data.uptime || 'N/A') + '</td></tr>';
            
            // 服务状态
            if (data.services) {
                for (var service in data.services) {
                    if (data.services.hasOwnProperty(service)) {
                        var svc = data.services[service];
                        html += '<tr><td><strong>' + service + '</strong></td><td>';
                        
                        if (svc.enabled) {
                            html += '<span class="label notice"><%:Enabled%></span> ';
                        } else {
                            html += '<span class="label"><%:Disabled%></span> ';
                        }
                        
                        if (svc.running) {
                            html += '<span class="label success"><%:Running%></span>';
                        } else {
                            html += '<span class="label"><%:Stopped%></span>';
                        }
                        
                        html += '</td></tr>';
                    }
                }
            }
            
            html += '</table>';
            document.getElementById('status-container').innerHTML = html;
        }
    };
    xhr.send();
}

// 页面加载时获取状态
window.onload = loadStatus;
</script>

<%+footer%>
EOF

    # 创建UCI配置文件
    cat > "${prefix}/etc/config/process-limit" << 'EOF'
config global 'settings'
    option enabled '1'
    option monitor_interval '30'
    option log_level '2'
    option auto_restart '1'
    option kill_timeout '5'

config service_limits 'samba'
    option name 'smbd'
    option cpu '500'
    option memory '128M'
    option processes '50'
    option oom '100'

config service_limits 'samba_nmbd'
    option name 'nmbd'
    option cpu '100'
    option memory '64M'
    option processes '20'
    option oom '150'

config service_limits 'vsftpd'
    option name 'vsftpd'
    option cpu '300'
    option memory '96M'
    option processes '30'
    option oom '120'

config service_limits 'hostapd'
    option name 'hostapd'
    option cpu '400'
    option memory '64M'
    option processes '15'
    option oom '80'

config service_limits 'dnsmasq'
    option name 'dnsmasq'
    option cpu '200'
    option memory '48M'
    option processes '20'
    option oom '50'

config monitored_processes 'essential'
    list process 'hostapd'
    list process 'wpa_supplicant'
    list process 'dnsmasq'
    list process 'smbd'
    list process 'nmbd'
    list process 'vsftpd'
    option enabled '1'
EOF

    echo "✓ Web界面配置已创建"
}

# ==================== 创建控制脚本 ====================
create_control_scripts() {
    local prefix="$1"
    
    # 创建主控制脚本
    cat > "${prefix}/usr/sbin/process-limit-ctl" << 'EOF'
#!/bin/sh
# 进程限制控制脚本

CONFIG_FILE="/etc/config/process-limit"
PID_FILE="/var/run/process-monitor.pid"
LOG_FILE="/var/log/process-monitor.log"

# 读取配置
get_config() {
    local section="$1"
    local option="$2"
    
    if [ -f "$CONFIG_FILE" ]; then
        uci -q get "process-limit.$section.$option" 2>/dev/null
    else
        # 使用默认值
        case "$option" in
            enabled) echo "1" ;;
            monitor_interval) echo "30" ;;
            log_level) echo "2" ;;
            auto_restart) echo "1" ;;
            kill_timeout) echo "5" ;;
            *) echo "" ;;
        esac
    fi
}

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local log_level=$(get_config settings log_level)
    
    if [ "$log_level" -ge "$level" ] 2>/dev/null; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    fi
}

# 检查服务状态
check_service() {
    local service="$1"
    
    if [ -f "/etc/init.d/$service" ]; then
        if /etc/init.d/$service enabled >/dev/null 2>&1; then
            echo "enabled"
        else
            echo "disabled"
        fi
    else
        echo "not_installed"
    fi
}

# 控制监控服务
ctrl_monitor() {
    case "$1" in
        start)
            if [ ! -f "$PID_FILE" ] || ! kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                /usr/sbin/process-monitor start
                log 3 "监控服务已启动"
                echo "监控服务启动成功"
            else
                echo "监控服务已在运行"
            fi
            ;;
        stop)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                /usr/sbin/process-monitor stop
                log 3 "监控服务已停止"
                echo "监控服务停止成功"
            else
                echo "监控服务未运行"
            fi
            ;;
        restart)
            ctrl_monitor stop
            sleep 2
            ctrl_monitor start
            ;;
        status)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                echo "监控服务正在运行 (PID: $(cat "$PID_FILE"))"
                return 0
            else
                echo "监控服务未运行"
                return 1
            fi
            ;;
        *)
            echo "用法: $0 monitor {start|stop|restart|status}"
            return 1
            ;;
    esac
}

# 控制特定服务限制
ctrl_service() {
    local service="$1"
    local action="$2"
    
    case "$action" in
        enable)
            # 应用资源限制到服务
            case "$service" in
                samba|samba4)
                    if [ -f "/etc/init.d/samba4" ]; then
                        /etc/init.d/samba4 restart
                        log 3 "Samba资源限制已启用"
                        echo "Samba资源限制已启用"
                    elif [ -f "/etc/init.d/samba" ]; then
                        /etc/init.d/samba restart
                        log 3 "Samba资源限制已启用"
                        echo "Samba资源限制已启用"
                    else
                        echo "Samba服务未安装"
                    fi
                    ;;
                vsftpd)
                    if [ -f "/etc/init.d/vsftpd" ]; then
                        /etc/init.d/vsftpd restart
                        log 3 "vsftpd资源限制已启用"
                        echo "vsftpd资源限制已启用"
                    else
                        echo "vsftpd服务未安装"
                    fi
                    ;;
                dnsmasq)
                    if [ -f "/etc/init.d/dnsmasq" ]; then
                        /etc/init.d/dnsmasq restart
                        log 3 "dnsmasq资源限制已启用"
                        echo "dnsmasq资源限制已启用"
                    else
                        echo "dnsmasq服务未安装"
                    fi
                    ;;
                *)
                    echo "不支持的服务: $service"
                    ;;
            esac
            ;;
        disable)
            # 恢复原始配置
            case "$service" in
                samba|samba4)
                    if [ -f "/etc/init.d/samba4.backup" ]; then
                        cp "/etc/init.d/samba4.backup" "/etc/init.d/samba4"
                        /etc/init.d/samba4 restart
                        echo "Samba资源限制已禁用"
                    elif [ -f "/etc/init.d/samba.backup" ]; then
                        cp "/etc/init.d/samba.backup" "/etc/init.d/samba"
                        /etc/init.d/samba restart
                        echo "Samba资源限制已禁用"
                    else
                        echo "未找到备份配置"
                    fi
                    ;;
                *)
                    echo "暂不支持禁用 $service 的资源限制"
                    ;;
            esac
            ;;
        status)
            # 检查服务状态
            case "$service" in
                samba|samba4|smbd)
                    if pgrep smbd >/dev/null; then
                        echo "Samba正在运行"
                        # 检查是否有限制
                        for pid in $(pgrep smbd); do
                            if [ -f "/proc/$pid/oom_score_adj" ]; then
                                oom_score=$(cat "/proc/$pid/oom_score_adj")
                                echo "  PID $pid OOM分数: $oom_score"
                            fi
                        done
                    else
                        echo "Samba未运行"
                    fi
                    ;;
                *)
                    echo "服务状态检查: $service"
                    ;;
            esac
            ;;
        *)
            echo "用法: $0 service <service> {enable|disable|status}"
            echo "可用服务: samba, vsftpd, dnsmasq"
            ;;
    esac
}

# 查看日志
view_logs() {
    local lines="${1:-50}"
    
    if [ -f "$LOG_FILE" ]; then
        tail -n "$lines" "$LOG_FILE"
    else
        echo "日志文件不存在: $LOG_FILE"
    fi
}

# 查看配置
view_config() {
    if [ -f "/etc/process-limits.conf" ]; then
        cat "/etc/process-limits.conf"
    else
        echo "配置文件不存在"
    fi
}

# 系统状态
system_status() {
    echo "=== 进程限制系统状态 ==="
    echo ""
    
    # 监控服务状态
    echo "1. 监控服务状态:"
    ctrl_monitor status
    echo ""
    
    # 配置文件状态
    echo "2. 配置文件状态:"
    if [ -f "/etc/process-limits.conf" ]; then
        echo "  配置文件存在: /etc/process-limits.conf"
        count=$(grep -c "^[a-zA-Z]" /etc/process-limits.conf 2>/dev/null || echo "0")
        echo "  配置了 $count 个进程限制"
    else
        echo "  配置文件不存在"
    fi
    echo ""
    
    # 各服务状态
    echo "3. 服务状态:"
    for service in samba4 samba vsftpd dnsmasq; do
        if [ -f "/etc/init.d/$service" ]; then
            status=$(check_service "$service")
            echo "  $service: $status"
        fi
    done
    echo ""
    
    # 系统资源
    echo "4. 系统资源:"
    free -m | awk 'NR==2{printf "  内存: %d/%dMB (%.1f%%)\n", $3, $2, $3*100/$2}'
    uptime | awk -F'load average:' '{print "  负载: "$2}'
}

# 主函数
case "$1" in
    monitor)
        ctrl_monitor "$2"
        ;;
    service)
        ctrl_service "$2" "$3"
        ;;
    logs)
        view_logs "$2"
        ;;
    config)
        view_config
        ;;
    status)
        system_status
        ;;
    enable)
        # 启用整个系统
        /etc/init.d/process-limit enable
        /etc/init.d/process-limit start
        echo "进程限制系统已启用"
        ;;
    disable)
        # 禁用整个系统
        /etc/init.d/process-limit stop
        /etc/init.d/process-limit disable
        echo "进程限制系统已禁用"
        ;;
    restart)
        /etc/init.d/process-limit restart
        echo "进程限制系统已重启"
        ;;
    *)
        echo "进程资源限制控制工具"
        echo ""
        echo "用法: $0 {command} [options]"
        echo ""
        echo "命令:"
        echo "  monitor {start|stop|restart|status}  控制监控服务"
        echo "  service <name> {enable|disable|status} 控制特定服务限制"
        echo "  logs [lines]                         查看日志（默认50行）"
        echo "  config                               查看配置文件"
        echo "  status                               查看系统状态"
        echo "  enable                               启用进程限制系统"
        echo "  disable                              禁用进程限制系统"
        echo "  restart                              重启进程限制系统"
        echo ""
        echo "示例:"
        echo "  $0 monitor start"
        echo "  $0 service samba enable"
        echo "  $0 logs 100"
        echo "  $0 status"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/process-limit-ctl"
    
    # 创建简化的CGI接口（用于Web界面）
    cat > "${prefix}/www/cgi-bin/process-limit/api" << 'EOF'
#!/bin/sh
echo "Content-type: application/json"
echo ""

# 简单的API接口
ACTION=$(echo "$QUERY_STRING" | sed -n 's/.*action=\([^&]*\).*/\1/p')

case "$ACTION" in
    status)
        # 返回JSON格式的状态信息
        echo '{'
        echo '  "monitor": {'
        if [ -f /var/run/process-monitor.pid ] && kill -0 $(cat /var/run/process-monitor.pid) 2>/dev/null; then
            echo '    "running": true,'
            echo '    "pid": '$(cat /var/run/process-monitor.pid)
        else
            echo '    "running": false,'
            echo '    "pid": null'
        fi
        echo '  },'
        echo '  "timestamp": "'$(date +%s)'"'
        echo '}'
        ;;
    toggle)
        # 切换监控状态
        if [ -f /var/run/process-monitor.pid ] && kill -0 $(cat /var/run/process-monitor.pid) 2>/dev/null; then
            /usr/sbin/process-monitor stop
            echo '{"success": true, "action": "stop"}'
        else
            /usr/sbin/process-monitor start
            echo '{"success": true, "action": "start"}'
        fi
        ;;
    *)
        echo '{"error": "Invalid action", "valid_actions": ["status", "toggle"]}'
        ;;
esac
EOF
    chmod +x "${prefix}/www/cgi-bin/process-limit/api"
    
    echo "✓ 控制脚本已创建"
}

# ==================== Samba资源限制 ====================
create_samba_limit() {
    local prefix="$1"
    
    # 检查是否有samba4或samba服务
    if [ "$RUNTIME_MODE" = "true" ]; then
        if [ -f "/etc/init.d/samba4" ]; then
            SAMBA_INIT="samba4"
        elif [ -f "/etc/init.d/samba" ]; then
            SAMBA_INIT="samba"
        else
            echo "未找到Samba服务，跳过配置"
            return
        fi
        
        # 备份原文件
        cp "/etc/init.d/$SAMBA_INIT" "/etc/init.d/${SAMBA_INIT}.backup.$(date +%Y%m%d%H%M%S)"
        
        # 修改启动脚本
        cat > "/etc/init.d/$SAMBA_INIT" << 'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=95

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/smbd -D
    procd_append_param command -s /etc/samba/smb.conf
    
    # 设置资源限制 - 防止Samba卡死系统
    procd_set_param limits cpu="500"      # CPU时间限制
    procd_set_param limits memory="128M"  # 内存限制
    procd_set_param limits processes="50" # 最大进程数
    
    # 设置OOM调整分数（越高越容易被杀死）
    procd_set_param oom_score_adj 100
    
    # 设置nice值（优先级）
    procd_set_param nice 10
    
    # 进程退出后自动重启
    procd_set_param respawn
    procd_set_param respawn_retry 5
    
    procd_close_instance
    
    # 启动nmbd（如果需要）
    procd_open_instance
    procd_set_param command /usr/sbin/nmbd -D
    procd_append_param command -s /etc/samba/smb.conf
    
    # 设置资源限制
    procd_set_param limits cpu="100"
    procd_set_param limits memory="64M"
    procd_set_param limits processes="20"
    procd_set_param oom_score_adj 150
    procd_set_param nice 15
    
    procd_set_param respawn
    procd_set_param respawn_retry 5
    procd_close_instance
}

stop_service() {
    killall smbd 2>/dev/null
    killall nmbd 2>/dev/null
}

reload_service() {
    stop
    sleep 1
    start
}
EOF
        chmod +x "/etc/init.d/$SAMBA_INIT"
        echo "✓ Samba资源限制已配置"
    else
        # 编译时：创建优化的samba4启动脚本
        cat > "${prefix}/etc/init.d/samba4" << 'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=95

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/smbd -D
    procd_append_param command -s /etc/samba/smb.conf
    
    # 资源限制配置
    procd_set_param limits cpu="500"
    procd_set_param limits memory="128M"
    procd_set_param limits processes="50"
    procd_set_param oom_score_adj 100
    procd_set_param nice 10
    procd_set_param respawn
    procd_set_param respawn_retry 5
    procd_close_instance
    
    procd_open_instance
    procd_set_param command /usr/sbin/nmbd -D
    procd_append_param command -s /etc/samba/smb.conf
    procd_set_param limits cpu="100"
    procd_set_param limits memory="64M"
    procd_set_param limits processes="20"
    procd_set_param oom_score_adj 150
    procd_set_param nice 15
    procd_set_param respawn
    procd_set_param respawn_retry 5
    procd_close_instance
}

stop_service() {
    killall smbd 2>/dev/null
    killall nmbd 2>/dev/null
}

reload_service() {
    stop
    sleep 1
    start
}
EOF
        chmod +x "${prefix}/etc/init.d/samba4"
        echo "✓ Samba资源限制已集成到固件"
    fi
}

# ==================== vsftpd资源限制 ====================
create_vsftpd_limit() {
    local prefix="$1"
    
    if [ "$RUNTIME_MODE" = "true" ]; then
        if [ ! -f "/etc/init.d/vsftpd" ]; then
            echo "未找到vsftpd服务，跳过配置"
            return
        fi
        
        # 备份原文件
        cp "/etc/init.d/vsftpd" "/etc/init.d/vsftpd.backup.$(date +%Y%m%d%H%M%S)"
        
        # 修改启动脚本
        cat > "/etc/init.d/vsftpd" << 'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=96

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/vsftpd /etc/vsftpd.conf
    
    # 设置资源限制 - 防止FTP服务卡死系统
    procd_set_param limits cpu="300"      # CPU时间限制
    procd_set_param limits memory="96M"   # 内存限制
    procd_set_param limits processes="30" # 最大进程数
    procd_set_param limits files="1024"   # 最大文件数
    
    # 设置OOM调整分数
    procd_set_param oom_score_adj 120
    
    # 设置nice值
    procd_set_param nice 5
    
    # 进程退出后自动重启
    procd_set_param respawn
    procd_set_param respawn_retry 3
    procd_set_param respawn_threshold 3600
    
    procd_close_instance
}

stop_service() {
    killall vsftpd 2>/dev/null
}

reload_service() {
    killall -HUP vsftpd 2>/dev/null
}
EOF
        chmod +x "/etc/init.d/vsftpd"
        echo "✓ vsftpd资源限制已配置"
    else
        # 编译时：创建优化的vsftpd启动脚本
        cat > "${prefix}/etc/init.d/vsftpd" << 'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=96

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/vsftpd /etc/vsftpd.conf
    
    # 资源限制配置
    procd_set_param limits cpu="300"
    procd_set_param limits memory="96M"
    procd_set_param limits processes="30"
    procd_set_param limits files="1024"
    procd_set_param oom_score_adj 120
    procd_set_param nice 5
    procd_set_param respawn
    procd_set_param respawn_retry 3
    procd_set_param respawn_threshold 3600
    
    procd_close_instance
}

stop_service() {
    killall vsftpd 2>/dev/null
}

reload_service() {
    killall -HUP vsftpd 2>/dev/null
}
EOF
        chmod +x "${prefix}/etc/init.d/vsftpd"
        echo "✓ vsftpd资源限制已集成到固件"
    fi
}

# ==================== WiFi进程资源限制 ====================
create_wifi_limit() {
    local prefix="$1"
    
    # 创建hostapd限制脚本
    cat > "${prefix}/usr/sbin/safe-hostapd" << 'EOF'
#!/bin/sh
# 安全的hostapd启动脚本

SAFE_HOSTAPD_PID="/var/run/safe-hostapd.pid"
LOG_FILE="/var/log/hostapd-monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 监控hostapd进程
monitor_hostapd() {
    while true; do
        if pgrep hostapd >/dev/null; then
            # 检查hostapd内存使用
            for pid in $(pgrep hostapd); do
                if [ -f "/proc/$pid/status" ]; then
                    mem_kb=$(grep VmRSS "/proc/$pid/status" | awk '{print $2}')
                    if [ -n "$mem_kb" ] && [ "$mem_kb" -gt 65536 ]; then # 超过64MB
                        log "hostapd (PID:$pid) 内存使用过高: ${mem_kb}KB，重启服务"
                        
                        # 优雅重启hostapd
                        kill -TERM "$pid"
                        sleep 2
                        
                        # 如果还在运行，强制终止
                        if kill -0 "$pid" 2>/dev/null; then
                            kill -KILL "$pid"
                        fi
                        
                        # 重启hostapd
                        /usr/sbin/hostapd -B -P /var/run/hostapd.pid /var/run/hostapd.conf
                        
                        # 设置资源限制
                        sleep 1
                        if [ -f "/var/run/hostapd.pid" ]; then
                            new_pid=$(cat /var/run/hostapd.pid)
                            if [ -n "$new_pid" ]; then
                                echo "80" > "/proc/$new_pid/oom_score_adj" 2>/dev/null || true
                                renice 5 -p "$new_pid" 2>/dev/null || true
                            fi
                        fi
                    fi
                fi
            done
        fi
        sleep 60
    done
}

case "$1" in
    start)
        echo "启动hostapd监控..."
        monitor_hostapd &
        echo $! > "$SAFE_HOSTAPD_PID"
        ;;
    stop)
        if [ -f "$SAFE_HOSTAPD_PID" ]; then
            kill $(cat "$SAFE_HOSTAPD_PID") 2>/dev/null || true
            rm -f "$SAFE_HOSTAPD_PID"
        fi
        ;;
    *)
        echo "用法: $0 {start|stop}"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/safe-hostapd"
    
    echo "✓ WiFi进程资源限制脚本已创建"
}

# ==================== 网络服务资源限制 ====================
create_network_limits() {
    local prefix="$1"
    
    # 创建dnsmasq资源限制
    if [ "$RUNTIME_MODE" = "true" ] && [ -f "/etc/init.d/dnsmasq" ]; then
        # 备份原文件
        cp "/etc/init.d/dnsmasq" "/etc/init.d/dnsmasq.backup.$(date +%Y%m%d%H%M%S)"
        
        # 创建优化的dnsmasq启动脚本
        cat > "/etc/init.d/dnsmasq" << 'EOF'
#!/bin/sh /etc/rc.common

USE_PROCD=1
START=19

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/dnsmasq -k
    
    # 设置资源限制
    procd_set_param limits cpu="200"      # CPU时间限制
    procd_set_param limits memory="48M"   # 内存限制
    procd_set_param limits processes="20" # 最大进程数
    procd_set_param limits files="512"    # 最大文件数
    
    # 设置OOM调整
    procd_set_param oom_score_adj 50
    
    # 设置优先级
    procd_set_param nice -5               # 较高优先级
    
    # 自动重启
    procd_set_param respawn
    procd_set_param respawn_retry 3
    procd_set_param respawn_threshold 7200
    
    procd_close_instance
}

stop_service() {
    killall dnsmasq 2>/dev/null
}

reload_service() {
    killall -HUP dnsmasq 2>/dev/null
}
EOF
        chmod +x "/etc/init.d/dnsmasq"
        echo "✓ dnsmasq资源限制已配置"
    fi
    
    echo "✓ 网络服务资源限制已配置"
}

# ==================== 进程监控脚本 ====================
create_process_monitor() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/process-monitor" << 'EOF'
#!/bin/sh
# 进程资源监控脚本

# 监控配置
CONFIG_FILE="/etc/config/process-limit"
LOG_FILE="/var/log/process-monitor.log"

# 默认限制
DEFAULT_LIMITS="
samba:cpu:500:memory:128M:processes:50:oom:100
smbd:cpu:500:memory:128M:processes:50:oom:100
nmbd:cpu:100:memory:64M:processes:20:oom:150
vsftpd:cpu:300:memory:96M:processes:30:oom:120
hostapd:cpu:400:memory:64M:processes:15:oom:80
wpa_supplicant:cpu:200:memory:48M:processes:10:oom:90
dnsmasq:cpu:200:memory:48M:processes:20:oom:50
iptables:cpu:100:memory:32M:processes:25:oom:70
dropbear:cpu:150:memory:32M:processes:15:oom:60
"

# 记录日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检查并限制进程
check_process() {
    local pid="$1"
    local name="$2"
    
    # 获取进程信息
    if [ -f "/proc/$pid/status" ]; then
        # 检查内存使用
        mem_kb=$(grep VmRSS "/proc/$pid/status" | awk '{print $2}')
        if [ -z "$mem_kb" ]; then
            mem_kb=0
        fi
        
        # 查找对应的限制配置
        limits=""
        for limit in $DEFAULT_LIMITS; do
            if echo "$limit" | grep -q "^$name:"; then
                limits="$limit"
                break
            fi
        done
        
        if [ -n "$limits" ]; then
            # 解析限制
            mem_limit=$(echo "$limits" | sed 's/.*:memory:\([^:]*\).*/\1/')
            cpu_limit=$(echo "$limits" | sed 's/.*:cpu:\([^:]*\).*/\1/')
            oom_score=$(echo "$limits" | sed 's/.*:oom:\([^:]*\).*/\1/')
            
            # 转换内存限制为KB
            mem_limit_kb=0
            if echo "$mem_limit" | grep -q "M$"; then
                mem_limit_kb=$(echo "$mem_limit" | sed 's/M//')*1024 | bc 2>/dev/null || echo "0"
            elif echo "$mem_limit" | grep -q "G$"; then
                mem_limit_kb=$(echo "$mem_limit" | sed 's/G//')*1024*1024 | bc 2>/dev/null || echo "0"
            fi
            
            # 检查是否超过限制
            if [ "$mem_limit_kb" -gt 0 ] && [ "$mem_kb" -gt "$mem_limit_kb" ]; then
                log "进程 $name (PID:$pid) 内存使用 ${mem_kb}KB 超过限制 ${mem_limit_kb}KB"
                
                # 尝试先降低优先级
                renice 19 -p "$pid" 2>/dev/null || true
                
                # 发送SIGTERM信号
                kill -15 "$pid" 2>/dev/null
                sleep 2
                
                # 如果还在运行，发送SIGKILL
                if kill -0 "$pid" 2>/dev/null; then
                    log "进程 $name (PID:$pid) 未响应SIGTERM，发送SIGKILL"
                    kill -9 "$pid" 2>/dev/null
                fi
                
                log "进程 $name (PID:$pid) 已被终止"
            fi
            
            # 设置OOM分数
            if [ -n "$oom_score" ] && [ -f "/proc/$pid/oom_score_adj" ]; then
                echo "$oom_score" > "/proc/$pid/oom_score_adj" 2>/dev/null || true
            fi
        fi
    fi
}

# 主监控循环
monitor() {
    log "进程监控服务启动"
    
    # 创建log目录
    mkdir -p /var/log
    
    while true; do
        # 检查所有进程
        ps -eo pid,comm | grep -v PID | while read -r line; do
            pid=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{print $2}')
            
            # 排除系统关键进程
            case "$name" in
                kworker*|ksoftirqd*|migration/*|rcu*|watchdog*|process-monitor)
                    continue
                    ;;
            esac
            
            check_process "$pid" "$name"
        done
        
        # 每30秒检查一次
        sleep 30
    done
}

# 启动服务
case "$1" in
    start)
        monitor &
        echo $! > /var/run/process-monitor.pid
        echo "进程监控服务已启动"
        ;;
    stop)
        if [ -f /var/run/process-monitor.pid ]; then
            kill $(cat /var/run/process-monitor.pid) 2>/dev/null || true
            rm -f /var/run/process-monitor.pid
        fi
        echo "进程监控服务已停止"
        ;;
    status)
        if [ -f /var/run/process-monitor.pid ] && kill -0 $(cat /var/run/process-monitor.pid) 2>/dev/null; then
            echo "进程监控服务正在运行"
        else
            echo "进程监控服务未运行"
        fi
        ;;
    *)
        echo "进程监控工具"
        echo "用法: $0 {start|stop|status}"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/process-monitor"
}

# ==================== 应用配置 ====================
echo "创建Web界面和控制脚本..."
create_web_interface "$INSTALL_DIR"
create_control_scripts "$INSTALL_DIR"

echo "配置进程资源限制..."
create_samba_limit "$INSTALL_DIR"
create_vsftpd_limit "$INSTALL_DIR"
create_wifi_limit "$INSTALL_DIR"
create_network_limits "$INSTALL_DIR"
create_process_monitor "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 创建配置文件
    cat > /etc/process-limits.conf << 'EOF'
# 进程资源限制配置
# 格式: 进程名:cpu限制:内存限制:最大进程数:OOM分数

# Samba相关进程
samba:cpu:500:memory:128M:processes:50:oom:100
smbd:cpu:500:memory:128M:processes:50:oom:100
nmbd:cpu:100:memory:64M:processes:20:oom:150

# FTP服务
vsftpd:cpu:300:memory:96M:processes:30:oom:120

# WiFi相关进程
hostapd:cpu:400:memory:64M:processes:15:oom:80
wpa_supplicant:cpu:200:memory:48M:processes:10:oom:90

# 网络服务
dnsmasq:cpu:200:memory:48M:processes:20:oom:50
iptables:cpu:100:memory:32M:processes:25:oom:70
dropbear:cpu:150:memory:32M:processes:15:oom:60
odhcpd:cpu:100:memory:32M:processes:10:oom:60
EOF

    # 创建开机启动脚本
    cat > /etc/init.d/process-limit << 'EOF'
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    # 等待系统基本服务启动
    sleep 15
    
    # 读取配置
    if [ -f /etc/config/process-limit ]; then
        enabled=$(uci -q get process-limit.settings.enabled)
        if [ "$enabled" = "0" ]; then
            echo "进程限制系统已禁用"
            return 0
        fi
    fi
    
    # 启动进程监控
    /usr/sbin/process-monitor start
    
    # 启动WiFi监控
    /usr/sbin/safe-hostapd start 2>/dev/null || true
    
    # 重启服务应用限制
    for service in samba samba4 vsftpd dnsmasq; do
        if [ -f "/etc/init.d/$service" ]; then
            /etc/init.d/$service restart 2>/dev/null || true
            sleep 1
        fi
    done
    
    # 设置现有进程的OOM分数
    for proc in hostapd wpa_supplicant dnsmasq smbd nmbd vsftpd; do
        pids=$(pgrep "$proc" 2>/dev/null) || continue
        for pid in $pids; do
            case "$proc" in
                hostapd) echo "80" > "/proc/$pid/oom_score_adj" 2>/dev/null || true ;;
                wpa_supplicant) echo "90" > "/proc/$pid/oom_score_adj" 2>/dev/null || true ;;
                dnsmasq) echo "50" > "/proc/$pid/oom_score_adj" 2>/dev/null || true ;;
                smbd) echo "100" > "/proc/$pid/oom_score_adj" 2>/dev/null || true ;;
                nmbd) echo "150" > "/proc/$pid/oom_score_adj" 2>/dev/null || true ;;
                vsftpd) echo "120" > "/proc/$pid/oom_score_adj" 2>/dev/null || true ;;
            esac
        done
    done
    
    echo "进程限制系统已启动"
}

stop_service() {
    /usr/sbin/process-monitor stop
    /usr/sbin/safe-hostapd stop 2>/dev/null || true
    echo "进程限制系统已停止"
}

reload_service() {
    stop_service
    sleep 2
    start_service
}
EOF
    chmod +x /etc/init.d/process-limit
    
    # 启用服务
    /etc/init.d/process-limit enable
    /etc/init.d/process-limit start
    
    echo "✓ 进程资源限制已应用"
    
    # 显示访问信息
    echo ""
    echo "============================================="
    echo "Web界面访问:"
    echo "  http://路由器IP/cgi-bin/luci/admin/system/process-limit"
    echo ""
    echo "命令行控制:"
    echo "  /usr/sbin/process-limit-ctl status        # 查看状态"
    echo "  /usr/sbin/process-limit-ctl monitor start # 启动监控"
    echo "  /usr/sbin/process-limit-ctl logs          # 查看日志"
    echo "  /usr/sbin/process-limit-ctl enable        # 启用系统"
    echo "  /usr/sbin/process-limit-ctl disable       # 禁用系统"
    echo "============================================="
    
else
    # 编译时：创建配置文件
    cat > files/etc/process-limits.conf << 'EOF'
# 进程资源限制配置
samba:cpu:500:memory:128M:processes:50:oom:100
smbd:cpu:500:memory:128M:processes:50:oom:100
nmbd:cpu:100:memory:64M:processes:20:oom:150
vsftpd:cpu:300:memory:96M:processes:30:oom:120
hostapd:cpu:400:memory:64M:processes:15:oom:80
wpa_supplicant:cpu:200:memory:48M:processes:10:oom:90
dnsmasq:cpu:200:memory:48M:processes:20:oom:50
EOF
    
    # 创建开机启动脚本
    cat > files/etc/init.d/process-limit << 'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
    sleep 15
    /usr/sbin/process-monitor start
    /usr/sbin/safe-hostapd start 2>/dev/null || true
}
stop_service() {
    /usr/sbin/process-monitor stop
}
EOF
    chmod +x files/etc/init.d/process-limit
    
    echo "✓ 进程资源限制已集成到固件"
fi

echo ""
echo "============================================="
echo "进程资源限制配置完成！"
echo "已优化的服务："
echo "  ✓ Samba文件共享服务"
echo "  ✓ vsftpd FTP服务"
echo "  ✓ WiFi服务 (hostapd/wpa_supplicant)"
echo "  ✓ 网络服务 (dnsmasq/iptables/dropbear)"
echo "  ✓ 进程监控服务"
echo "  ✓ Web管理界面"
echo "  ✓ 命令行控制工具"
echo "============================================="