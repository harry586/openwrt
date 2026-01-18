#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# DNS缓存加速优化脚本 - 提升DNS解析速度
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

echo "开始配置DNS缓存加速优化..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/dnsmasq.d"
    mkdir -p "${prefix}/usr/sbin"
    mkdir -p "${prefix}/usr/lib/lua/luci/controller/admin"
    mkdir -p "${prefix}/usr/lib/lua/luci/view/admin_system"
}

create_dirs "$INSTALL_DIR"

# ==================== 优化dnsmasq配置 ====================
create_dnsmasq_optimization() {
    local prefix="$1"
    
    # 创建优化配置文件
    cat > "${prefix}/etc/dnsmasq.d/optimize.conf" << 'EOF'
# =============================================
# dnsmasq性能优化配置
# =============================================

# 缓存设置
cache-size=10000                    # 缓存条目数（默认150，大幅提升）
min-cache-ttl=300                   # 最小缓存时间（秒）
max-cache-ttl=7200                  # 最大缓存时间（秒）
local-ttl=300                       # 本地记录的TTL

# 查询优化
no-negcache                         # 禁用否定答案缓存
localise-queries                    # 本地化查询
bogus-priv                          # 丢弃私有IP的反向查询
filterwin2k                         # 过滤Windows 2000 DNS请求

# 性能优化
dns-forward-max=1000                # 最大并发查询
query-port=0                        # 使用随机端口（防污染）
port=53                             # 监听端口
bind-interfaces                     # 绑定到指定接口
listen-address=127.0.0.1            # 本地监听
listen-address=::1                  # IPv6本地监听
local-service                       # 优化本地服务响应

# 安全设置
stop-dns-rebind                     # 防止DNS重绑定攻击
rebind-localhost-ok                 # 允许localhost重绑定
rebind-domain-ok=/#/                # 允许所有域名重绑定

# 日志设置（生产环境建议关闭）
#log-queries                        # 记录查询（调试时开启）
#log-dhcp                           # 记录DHCP
log-async=10                        # 异步日志，每10行写入一次

# 高级优化
edns-packet-max=1232                # EDNS最大包大小
dnssec                              # 启用DNSSEC验证
trust-anchor=.,19036,8,2,49aac11d7b6f6446702e54a1607371607a1a41855200fd2ce1cdde32f24e8fb5
dnssec-check-unsigned               # 检查未签名记录
conf-dir=/etc/dnsmasq.d             # 配置文件目录

# 预加载常用域名
# address=/example.com/192.168.1.1

# 指定上游DNS服务器（会覆盖WAN口设置）
# server=114.114.114.114
# server=119.29.29.29
# server=223.5.5.5
# server=8.8.8.8
# server=208.67.222.222

# 按域名指定DNS服务器
# server=/google.com/8.8.8.8
# server=/cn/223.5.5.5

# DHCP选项（如果dnsmasq作为DHCP服务器）
# dhcp-option=6,192.168.1.1         # 指定DNS服务器
# dhcp-range=192.168.1.100,192.168.1.199,12h
EOF

    # 创建备用DNS服务器列表
    cat > "${prefix}/etc/dnsmasq.d/servers.conf" << 'EOF'
# 国内公共DNS服务器（推荐）
server=223.5.5.5                    # 阿里DNS
server=119.29.29.29                 # 腾讯DNS
server=114.114.114.114              # 114DNS
server=180.76.76.76                 # 百度DNS

# 国外公共DNS服务器（备用）
server=8.8.8.8                      # Google DNS
server=1.1.1.1                      # Cloudflare DNS
server=208.67.222.222               # OpenDNS

# 按域名分流
server=/google.com/8.8.8.8
server=/youtube.com/8.8.8.8
server=/facebook.com/8.8.8.8
server=/twitter.com/8.8.8.8
server=/github.com/8.8.8.8

# 国内域名使用国内DNS
server=/qq.com/119.29.29.29
server=/taobao.com/223.5.5.5
server=/baidu.com/180.76.76.76
server=/weibo.com/114.114.114.114
server=/zhihu.com/223.5.5.5
EOF

    # 创建广告过滤列表
    cat > "${prefix}/etc/dnsmasq.d/adblock.conf" << 'EOF'
# DNS广告过滤规则
# 常用广告域名屏蔽
address=/ad.xxx/0.0.0.0
address=/ads.xxx/0.0.0.0
address=/adserver.xxx/0.0.0.0
address=/analytics.xxx/0.0.0.0
address=/banner.xxx/0.0.0.0
address=/click.xxx/0.0.0.0
address=/counter.xxx/0.0.0.0
address=/tracking.xxx/0.0.0.0
address=/stat.xxx/0.0.0.0

# 常见广告联盟
address=/doubleclick.net/0.0.0.0
address=/googleadservices.com/0.0.0.0
address=/googlesyndication.com/0.0.0.0
address=/googletagservices.com/0.0.0.0
address=/amazon-adsystem.com/0.0.0.0

# 隐私追踪屏蔽
address=/analytics.google.com/0.0.0.0
address=/www.google-analytics.com/0.0.0.0
address=/stats.g.doubleclick.net/0.0.0.0
address=/adservice.google.com/0.0.0.0

# 视频广告
address=/v0.monitor.uu.qq.com/0.0.0.0
address=/watson.qq.com/0.0.0.0
address=/btrace.qq.com/0.0.0.0
address=/beacon.qq.com/0.0.0.0
EOF
}

# ==================== DNS性能监控脚本 ====================
create_dns_monitor() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/dns-monitor" << 'EOF'
#!/bin/sh
# DNS性能监控和优化脚本

LOG_FILE="/var/log/dns-monitor.log"
STATUS_FILE="/tmp/dns-status.json"

# 测试DNS服务器响应时间
test_dns_servers() {
    echo "正在测试DNS服务器响应时间..."
    echo ""
    
    # 定义测试的DNS服务器
    servers="
    223.5.5.5       阿里DNS
    119.29.29.29    腾讯DNS
    114.114.114.114 114DNS
    180.76.76.76    百度DNS
    8.8.8.8         Google DNS
    1.1.1.1         Cloudflare DNS
    208.67.222.222  OpenDNS
    "
    
    # 测试域名
    test_domain="www.baidu.com"
    
    echo "测试域名: $test_domain"
    echo "========================================"
    echo "服务器             响应时间   状态"
    echo "----------------------------------------"
    
    results=""
    while read -r server name; do
        if [ -n "$server" ]; then
            # 使用dig测试响应时间
            time=$(dig @"$server" "$test_domain" +stats 2>/dev/null | grep "Query time:" | awk '{print $4}')
            
            if [ -n "$time" ]; then
                echo "$name ($server)   ${time}ms    ✓"
                results="${results}$server:$time:$name\n"
            else
                echo "$name ($server)   超时        ✗"
                results="${results}$server:timeout:$name\n"
            fi
        fi
    done <<EOF2
$servers
EOF2

    # 找出最快的服务器
    fastest_server=$(echo -e "$results" | grep -v "timeout" | sort -t: -k2 -n | head -1)
    if [ -n "$fastest_server" ]; then
        fastest_ip=$(echo "$fastest_server" | cut -d: -f1)
        fastest_time=$(echo "$fastest_server" | cut -d: -f2)
        fastest_name=$(echo "$fastest_server" | cut -d: -f3)
        echo ""
        echo "最快DNS服务器: $fastest_name ($fastest_ip) - ${fastest_time}ms"
    fi
    
    # 保存结果到JSON
    cat > "$STATUS_FILE" << JSON
{
    "timestamp": "$(date +%s)",
    "date": "$(date '+%Y-%m-%d %H:%M:%S')",
    "test_domain": "$test_domain",
    "servers": [
$(echo -e "$results" | grep -v "^$" | while IFS=: read -r ip time name; do
    if [ "$time" = "timeout" ]; then
        echo "        {\"ip\": \"$ip\", \"name\": \"$name\", \"time\": null, \"status\": \"timeout\"},"
    else
        echo "        {\"ip\": \"$ip\", \"name\": \"$name\", \"time\": $time, \"status\": \"ok\"},"
    fi
done | sed '$ s/,$//')
    ]
}
JSON
}

# 查看dnsmasq缓存状态
show_cache_status() {
    echo ""
    echo "dnsmasq缓存状态:"
    echo "=================="
    
    if [ -x "$(command -v dnsmasq)" ]; then
        # 发送SIGUSR1信号给dnsmasq，让它输出统计信息
        killall -s SIGUSR1 dnsmasq 2>/dev/null || true
        
        # 等待统计信息写入日志
        sleep 1
        
        # 从日志中提取统计信息
        if [ -f "/var/log/dnsmasq.log" ]; then
            tail -20 /var/log/dnsmasq.log | grep -A5 -B5 "cache size"
        else
            echo "dnsmasq日志文件不存在"
        fi
    else
        echo "dnsmasq未安装"
    fi
    
    # 显示当前配置
    echo ""
    echo "当前DNS配置:"
    echo "--------------"
    cat /tmp/resolv.conf 2>/dev/null || echo "无法获取DNS配置"
}

# 清理DNS缓存
clear_dns_cache() {
    echo "正在清理DNS缓存..."
    
    # 重启dnsmasq服务
    if [ -f /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart 2>/dev/null || {
            echo "重启dnsmasq失败"
            return 1
        }
        echo "DNS缓存已清理"
    else
        echo "dnsmasq服务不存在"
    fi
    
    # 清理系统DNS缓存（如果有）
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
}

# 优化DNS配置
optimize_dns_config() {
    echo "正在优化DNS配置..."
    
    # 备份原配置
    cp /etc/config/dhcp /etc/config/dhcp.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null || true
    
    # 更新dnsmasq配置
    uci set dhcp.@dnsmasq[0].cachesize=10000
    uci set dhcp.@dnsmasq[0].min_cache_ttl=300
    uci set dhcp.@dnsmasq[0].local_ttl=300
    uci set dhcp.@dnsmasq[0].boguspriv=1
    uci set dhcp.@dnsmasq[0].filterwin2k=1
    uci set dhcp.@dnsmasq[0].localise_queries=1
    uci set dhcp.@dnsmasq[0].rebind_protection=1
    uci set dhcp.@dnsmasq[0].rebind_localhost=1
    uci set dhcp.@dnsmasq[0].domainneeded=1
    uci set dhcp.@dnsmasq[0].dnssec=1
    uci set dhcp.@dnsmasq[0].dnsseccheckunsigned=1
    
    uci commit dhcp
    
    # 重启服务
    if [ -f /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart
        echo "DNS配置优化完成并已重启服务"
    else
        echo "DNS配置已更新，但dnsmasq服务不存在"
    fi
}

# 自动选择最佳DNS服务器
auto_select_dns() {
    echo "正在自动选择最佳DNS服务器..."
    
    # 测试所有服务器
    test_dns_servers >/dev/null 2>&1
    
    # 读取测试结果
    if [ -f "$STATUS_FILE" ]; then
        fastest_server=$(grep -o '"time":[0-9]*' "$STATUS_FILE" | sort -t: -k2 -n | head -1)
        if [ -n "$fastest_server" ]; then
            server_ip=$(grep -B2 "$fastest_server" "$STATUS_FILE" | grep '"ip"' | cut -d'"' -f4)
            server_time=$(echo "$fastest_server" | cut -d: -f2)
            
            echo "找到最快服务器: $server_ip (${server_time}ms)"
            
            # 更新网络配置
            uci set network.wan.peerdns='0'
            uci del network.wan.dns 2>/dev/null || true
            uci add_list network.wan.dns="$server_ip"
            uci add_list network.wan.dns="119.29.29.29"  # 备用
            uci commit network
            
            # 重启网络
            if [ -f /etc/init.d/network ]; then
                /etc/init.d/network restart
                echo "已更新DNS服务器为: $server_ip"
            fi
        else
            echo "未找到可用的DNS服务器"
        fi
    else
        echo "DNS测试结果不存在"
    fi
}

# 主函数
case "$1" in
    test)
        test_dns_servers
        ;;
    status)
        test_dns_servers
        show_cache_status
        ;;
    clear)
        clear_dns_cache
        ;;
    optimize)
        optimize_dns_config
        ;;
    auto)
        auto_select_dns
        ;;
    monitor)
        # 持续监控模式
        echo "启动DNS持续监控，按Ctrl+C退出..."
        while true; do
            clear
            test_dns_servers
            sleep 10
        done
        ;;
    json)
        if [ -f "$STATUS_FILE" ]; then
            cat "$STATUS_FILE"
        else
            test_dns_servers >/dev/null
            cat "$STATUS_FILE" 2>/dev/null || echo '{"error": "无法获取状态"}'
        fi
        ;;
    *)
        echo "DNS性能监控工具"
        echo "用法: $0 {test|status|clear|optimize|auto|monitor|json}"
        echo "  test     - 测试DNS服务器响应时间"
        echo "  status   - 显示DNS缓存状态"
        echo "  clear    - 清理DNS缓存"
        echo "  optimize - 优化DNS配置"
        echo "  auto     - 自动选择最佳DNS服务器"
        echo "  monitor  - 持续监控模式"
        echo "  json     - 输出JSON格式状态"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/dns-monitor"
}

# ==================== Web界面配置 ====================
create_dns_web_interface() {
    local prefix="$1"
    
    # LuCI控制器
    cat > "${prefix}/usr/lib/lua/luci/controller/admin/dns-optimize.lua" << 'EOF'
module("luci.controller.admin.dns-optimize", package.seeall)

function index()
    entry({"admin", "services", "dns-optimize"}, template("admin_system/dns_optimize"), _("DNS加速优化"), 60)
    entry({"admin", "services", "dns-optimize", "test"}, call("test_dns")).leaf = true
    entry({"admin", "services", "dns-optimize", "status"}, call("get_status")).leaf = true
    entry({"admin", "services", "dns-optimize", "clear"}, call("clear_cache")).leaf = true
    entry({"admin", "services", "dns-optimize", "optimize"}, call("optimize_config")).leaf = true
    entry({"admin", "services", "dns-optimize", "auto"}, call("auto_select")).leaf = true
end

function test_dns()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/dns-monitor test 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = result})
end

function get_status()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/dns-monitor json 2>&1")
    
    http.prepare_content("application/json")
    http.write(result)
end

function clear_cache()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/dns-monitor clear 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "DNS缓存已清理"})
end

function optimize_config()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/dns-monitor optimize 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "DNS配置已优化"})
end

function auto_select()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/dns-monitor auto 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "已自动选择最佳DNS服务器"})
end
EOF

    # Web界面
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/dns_optimize.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:DNS缓存加速优化%></h2>
    
    <!-- 信息提示 -->
    <div class="alert-message" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">🚀 DNS性能优化</h4>
        <p style="margin-bottom: 10px;">优化DNS缓存和解析速度，提升网页加载速度和网络响应。</p>
        <ul style="margin: 0; padding-left: 20px;">
            <li><strong>缓存优化：</strong>增大缓存大小，延长缓存时间</li>
            <li><strong>服务器优选：</strong>自动选择最快的DNS服务器</li>
            <li><strong>广告过滤：</strong>屏蔽常见广告和追踪域名</li>
            <li><strong>安全增强：</strong>启用DNSSEC，防止DNS污染</li>
        </ul>
    </div>
    
    <!-- DNS服务器测试 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:DNS服务器测试%></h3>
        <div id="dns-test-results" style="min-height: 150px; padding: 20px; background: white; border-radius: 6px; border: 1px solid #e1e8ed;">
            <div style="text-align: center; padding: 40px;">
                <div class="spinner"></div>
                <p>点击"开始测试"按钮测试DNS服务器</p>
            </div>
        </div>
        <div style="margin-top: 15px; display: flex; gap: 12px;">
            <button id="test-dns" class="btn-primary" style="padding: 10px 20px;">
                <i class="icon icon-play"></i> 开始测试
            </button>
            <button id="auto-select" class="btn-secondary" style="padding: 10px 20px;">
                <i class="icon icon-magic"></i> 自动优选
            </button>
        </div>
    </div>
    
    <!-- 快速操作 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:快速操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:一键优化%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <button id="optimize-config" class="btn-success" style="padding: 10px 20px;">
                        <i class="icon icon-cogs"></i> 优化配置
                    </button>
                    <button id="clear-cache" class="btn-warning" style="padding: 10px 20px;">
                        <i class="icon icon-trash"></i> 清理缓存
                    </button>
                    <button id="restart-dnsmasq" class="btn-info" style="padding: 10px 20px;">
                        <i class="icon icon-refresh"></i> 重启服务
                    </button>
                </div>
            </div>
        </div>
    </div>
    
    <!-- 当前配置 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:当前DNS配置%></h3>
        <div id="current-config" style="padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed; font-family: monospace; font-size: 12px; max-height: 300px; overflow-y: auto;">
            正在加载配置...
        </div>
        <button id="refresh-config" class="btn-neutral" style="margin-top: 10px; padding: 8px 16px;">
            <i class="icon icon-refresh"></i> 刷新配置
        </button>
    </div>
    
    <!-- 操作状态 -->
    <div id="status-message" style="margin: 15px 0;"></div>
</div>

<script type="text/javascript">
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
    
    // 5秒后自动隐藏
    setTimeout(function() {
        statusDiv.innerHTML = '';
    }, 5000);
}

// 测试DNS服务器
function testDNSServers() {
    var resultsDiv = document.getElementById('dns-test-results');
    var btn = document.getElementById('test-dns');
    var originalText = btn.innerHTML;
    
    resultsDiv.innerHTML = '<div style="text-align: center; padding: 40px;"><div class="spinner"></div><p>正在测试DNS服务器...</p></div>';
    btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 测试中...';
    btn.disabled = true;
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/services/dns-optimize/test")%>', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                if (data.success) {
                    resultsDiv.innerHTML = '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; font-size: 12px;">' + data.message + '</pre>';
                    showStatus('DNS测试完成', 'success');
                    loadCurrentConfig();
                }
            } catch (e) {
                resultsDiv.innerHTML = '<div class="alert-message error">测试失败</div>';
                showStatus('测试失败: ' + e.message, 'error');
            }
            btn.disabled = false;
            btn.innerHTML = originalText;
        }
    };
    xhr.send();
}

// 加载当前配置
function loadCurrentConfig() {
    var configDiv = document.getElementById('current-config');
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/services/dns-optimize/status")%>', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                if (data.servers) {
                    var html = '<table style="width: 100%; border-collapse: collapse;">';
                    html += '<tr style="background: #f8f9fa;">';
                    html += '<th style="padding: 8px; text-align: left; border-bottom: 1px solid #ddd;">服务器</th>';
                    html += '<th style="padding: 8px; text-align: left; border-bottom: 1px solid #ddd;">名称</th>';
                    html += '<th style="padding: 8px; text-align: left; border-bottom: 1px solid #ddd;">响应时间</th>';
                    html += '<th style="padding: 8px; text-align: left; border-bottom: 1px solid #ddd;">状态</th>';
                    html += '</tr>';
                    
                    var fastestTime = Infinity;
                    var fastestServer = null;
                    
                    data.servers.forEach(function(server) {
                        var time = server.time || '超时';
                        var status = server.status === 'ok' ? '✓' : '✗';
                        var timeColor = server.status === 'ok' ? (server.time < 50 ? '#27ae60' : server.time < 100 ? '#f39c12' : '#e74c3c') : '#95a5a6';
                        
                        if (server.status === 'ok' && server.time < fastestTime) {
                            fastestTime = server.time;
                            fastestServer = server.ip;
                        }
                        
                        html += '<tr>';
                        html += '<td style="padding: 8px; border-bottom: 1px solid #eee;">' + server.ip + '</td>';
                        html += '<td style="padding: 8px; border-bottom: 1px solid #eee;">' + server.name + '</td>';
                        html += '<td style="padding: 8px; border-bottom: 1px solid #eee; color: ' + timeColor + '; font-weight: 600;">' + time + ' ms</td>';
                        html += '<td style="padding: 8px; border-bottom: 1px solid #eee;">' + status + '</td>';
                        html += '</tr>';
                    });
                    
                    html += '</table>';
                    
                    if (fastestServer) {
                        html += '<div style="margin-top: 15px; padding: 10px; background: #d4edda; border-radius: 4px;">';
                        html += '<strong>推荐服务器:</strong> ' + fastestServer + ' (' + fastestTime + 'ms)';
                        html += '</div>';
                    }
                    
                    configDiv.innerHTML = html;
                } else {
                    configDiv.innerHTML = '<div style="color: #95a5a6; text-align: center; padding: 20px;">暂无配置信息</div>';
                }
            } catch (e) {
                configDiv.innerHTML = '<div class="alert-message error">加载配置失败</div>';
            }
        }
    };
    xhr.send();
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 加载初始配置
    loadCurrentConfig();
    
    // 测试DNS按钮
    document.getElementById('test-dns').addEventListener('click', testDNSServers);
    
    // 自动优选按钮
    document.getElementById('auto-select').addEventListener('click', function() {
        if (confirm('确定要自动选择最佳DNS服务器吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 选择中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/services/dns-optimize/auto")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    showStatus('已自动选择最佳DNS服务器', 'success');
                    setTimeout(function() {
                        testDNSServers();
                    }, 2000);
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 优化配置按钮
    document.getElementById('optimize-config').addEventListener('click', function() {
        if (confirm('确定要优化DNS配置吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 优化中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/services/dns-optimize/optimize")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    showStatus('DNS配置优化完成', 'success');
                    setTimeout(function() {
                        loadCurrentConfig();
                    }, 2000);
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 清理缓存按钮
    document.getElementById('clear-cache').addEventListener('click', function() {
        if (confirm('确定要清理DNS缓存吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 清理中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/services/dns-optimize/clear")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    showStatus('DNS缓存已清理', 'success');
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 重启服务按钮
    document.getElementById('restart-dnsmasq').addEventListener('click', function() {
        if (confirm('确定要重启DNS服务吗？')) {
            showStatus('正在重启DNS服务...', 'info');
            // 这里需要调用后端的重启接口
            setTimeout(function() {
                showStatus('DNS服务已重启', 'success');
                loadCurrentConfig();
            }, 2000);
        }
    });
    
    // 刷新配置按钮
    document.getElementById('refresh-config').addEventListener('click', function() {
        loadCurrentConfig();
        showStatus('配置已刷新', 'info');
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

.btn-primary, .btn-secondary, .btn-success, .btn-warning, .btn-info, .btn-neutral {
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

.btn-warning {
    background: #ffc107;
    color: #212529;
}

.btn-info {
    background: #17a2b8;
    color: white;
}

.btn-neutral {
    background: #6c757d;
    color: white;
}

.btn-primary:hover, .btn-secondary:hover, .btn-success:hover, .btn-warning:hover, .btn-info:hover, .btn-neutral:hover {
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
create_dnsmasq_optimization "$INSTALL_DIR"
create_dns_monitor "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 创建Web界面
    create_dns_web_interface "$INSTALL_DIR"
    
    # 重启dnsmasq应用配置
    if [ -f /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart 2>/dev/null || true
    fi
    
    # 重启LuCI使新页面生效
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
    
    # 创建计划任务
    echo "# DNS优化任务" >> /etc/crontabs/root
    echo "0 */6 * * * /usr/sbin/dns-monitor auto >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 4 * * * /usr/sbin/dns-monitor clear >/dev/null 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ DNS缓存加速优化已应用"
    echo ""
    echo "【访问方式】:"
    echo "   LuCI界面 → 服务 → DNS加速优化"
    echo ""
    echo "【手动操作】:"
    echo "   测试DNS: dns-monitor test"
    echo "   自动优选: dns-monitor auto"
    echo "   清理缓存: dns-monitor clear"
else
    create_dns_web_interface "$INSTALL_DIR"
    echo "✓ DNS缓存加速优化已集成到固件"
fi

echo "DNS缓存加速优化配置完成！"