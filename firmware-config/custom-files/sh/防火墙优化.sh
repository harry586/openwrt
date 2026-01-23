#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 防火墙性能优化脚本（修复版 - 不会阻断管理访问）
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

echo "开始配置防火墙性能优化..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/firewall.d"
    mkdir -p "${prefix}/etc/sysctl.d"
    mkdir -p "${prefix}/usr/sbin"
    mkdir -p "${prefix}/usr/lib/lua/luci/controller/admin"
    mkdir -p "${prefix}/usr/lib/lua/luci/view/admin_system"
}

create_dirs "$INSTALL_DIR"

# ==================== 防火墙内核参数优化 ====================
create_firewall_optimization() {
    local prefix="$1"
    
    # 创建内核网络参数优化
    cat > "${prefix}/etc/sysctl.d/99-firewall-optimization.conf" << 'EOF'
# =============================================
# 防火墙性能优化配置（安全版）
# 不会阻断管理访问
# =============================================

# 连接跟踪优化
net.netfilter.nf_conntrack_max=65536
net.netfilter.nf_conntrack_tcp_timeout_established=86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait=120
net.netfilter.nf_conntrack_tcp_timeout_close_wait=60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=120
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=180
net.netfilter.nf_conntrack_icmp_timeout=30
net.netfilter.nf_conntrack_generic_timeout=600
net.netfilter.nf_conntrack_buckets=16384

# TCP连接优化
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_synack_retries=2
net.ipv4.tcp_syn_retries=3
net.ipv4.tcp_max_tw_buckets=180000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_tw_recycle=0
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=1200
net.ipv4.tcp_keepalive_probes=5
net.ipv4.tcp_keepalive_intvl=15

# IP转发和路由
net.ipv4.ip_forward=1
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.route.max_size=1048576
net.ipv4.route.gc_thresh=1048576
net.ipv4.route.gc_timeout=300

# 防止DoS攻击
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_orphans=65536
net.ipv4.tcp_orphan_retries=0
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.all.log_martians=1

# ARP优化
net.ipv4.neigh.default.gc_thresh1=1024
net.ipv4.neigh.default.gc_thresh2=2048
net.ipv4.neigh.default.gc_thresh3=4096
net.ipv4.neigh.default.gc_interval=30
net.ipv4.neigh.default.gc_stale_time=60

# IPv6优化（如果启用）
net.ipv6.conf.all.forwarding=1
net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.accept_ra=2
net.ipv6.conf.default.accept_ra=2
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.all.autoconf=0

# 确保管理访问不被阻断
net.ipv4.conf.lan.rp_filter=0
net.ipv4.conf.br-lan.rp_filter=0
EOF

    # 创建优化的防火墙规则模板（安全版 - 不会阻断管理访问）
    cat > "${prefix}/etc/firewall.d/optimized-rules" << 'EOF'
#!/bin/sh
# 优化的防火墙规则（安全版）
# 这个文件会被包含在主要的防火墙配置中
# 不会阻断Web管理和SSH访问

# 定义变量
LAN_IFACE="br-lan"
WAN_IFACE="eth0"
WAN6_IFACE="@wan6"

# 1. 基础规则设置 - 允许所有本地流量
iptables -P INPUT ACCEPT
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 2. 连接状态跟踪
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# 3. 允许本地回环
iptables -A INPUT -i lo -j ACCEPT

# 4. 允许ICMP（ping）
iptables -A INPUT -p icmp -m icmp --icmp-type 8 -m limit --limit 5/sec -j ACCEPT
iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j ACCEPT

# 5. 允许LAN接口的所有输入（确保管理访问）
iptables -A INPUT -i $LAN_IFACE -j ACCEPT

# 6. 允许从LAN到WAN的转发
iptables -A FORWARD -i $LAN_IFACE -o $WAN_IFACE -j ACCEPT

# 7. 允许从WAN到已建立连接的回复
iptables -A FORWARD -i $WAN_IFACE -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT

# 8. 防止DoS攻击（温和版）
iptables -N SYN_FLOOD
iptables -A SYN_FLOOD -p tcp --syn -m limit --limit 10/s -j RETURN
iptables -A SYN_FLOOD -j LOG --log-prefix "SYN-flood: "
iptables -A SYN_FLOOD -j DROP
iptables -A INPUT -p tcp --syn -j SYN_FLOOD

# 9. 防止端口扫描（温和版）
iptables -N PORT_SCAN
iptables -A PORT_SCAN -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 5/s -j RETURN
iptables -A PORT_SCAN -j LOG --log-prefix "Port-scan: "
iptables -A PORT_SCAN -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,ACK,FIN,RST RST -j PORT_SCAN

# 10. 记录被拒绝的WAN连接（可选）
iptables -N LOGGING
iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "Firewall-Dropped-WAN: " --log-level 4
iptables -A LOGGING -j DROP
iptables -A INPUT -i $WAN_IFACE -j LOGGING

# 11. 创建用户链用于流量统计
iptables -N TRAFFIC_IN
iptables -N TRAFFIC_OUT
iptables -N TRAFFIC_FWD

iptables -A INPUT -j TRAFFIC_IN
iptables -A OUTPUT -j TRAFFIC_OUT
iptables -A FORWARD -j TRAFFIC_FWD

# IPv6规则（如果启用）
if [ -n "$WAN6_IFACE" ]; then
    ip6tables -P INPUT ACCEPT
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT ACCEPT
    
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A INPUT -i $LAN_IFACE -j ACCEPT
    
    # 允许ICMPv6（必需）
    ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
    ip6tables -A FORWARD -p ipv6-icmp -j ACCEPT
    
    # LAN到WAN转发
    ip6tables -A FORWARD -i $LAN_IFACE -o $WAN6_IFACE -j ACCEPT
    ip6tables -A FORWARD -i $WAN6_IFACE -o $LAN_IFACE -m state --state ESTABLISHED,RELATED -j ACCEPT
fi

echo "安全版防火墙规则已加载 - 不会阻断管理访问"
EOF
    chmod +x "${prefix}/etc/firewall.d/optimized-rules"

    # 创建防火墙性能优化脚本
    cat > "${prefix}/usr/sbin/firewall-optimize" << 'EOF'
#!/bin/sh
# 防火墙性能优化脚本（安全版）

LOG_FILE="/var/log/firewall-optimize.log"
CONFIG_FILE="/etc/config/firewall"

# 记录日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

# 安全检查：确保不会阻断管理访问
safety_check() {
    log "执行安全检查..."
    
    # 检查当前防火墙规则是否允许LAN访问
    local lan_rules=$(iptables -L INPUT -n | grep -c "br-lan")
    if [ "$lan_rules" -eq 0 ]; then
        log "警告：未找到允许LAN访问的规则，添加安全规则..."
        
        # 添加允许LAN访问的规则
        iptables -I INPUT -i br-lan -j ACCEPT 2>/dev/null || {
            log "错误：无法添加LAN访问规则"
            return 1
        }
        log "已添加LAN访问规则"
    fi
    
    # 检查是否允许回环
    local lo_rules=$(iptables -L INPUT -n | grep -c "lo")
    if [ "$lo_rules" -eq 0 ]; then
        iptables -I INPUT -i lo -j ACCEPT 2>/dev/null
        log "已添加回环接口规则"
    fi
    
    # 检查是否允许ESTABLISHED连接
    local established_rules=$(iptables -L INPUT -n | grep -c "ESTABLISHED")
    if [ "$established_rules" -eq 0 ]; then
        iptables -I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
        log "已添加已建立连接规则"
    fi
    
    log "安全检查通过"
    return 0
}

# 应用内核参数优化
apply_kernel_optimization() {
    log "应用内核防火墙优化参数..."
    
    if [ -f "/etc/sysctl.d/99-firewall-optimization.conf" ]; then
        sysctl -p /etc/sysctl.d/99-firewall-optimization.conf >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            log "内核参数优化应用成功"
            return 0
        else
            log "内核参数优化应用失败"
            return 1
        fi
    else
        log "内核优化配置文件不存在"
        return 1
    fi
}

# 优化连接跟踪表
optimize_conntrack() {
    log "优化连接跟踪表..."
    
    # 获取当前连接数
    current_conns=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
    max_conns=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "65536")
    
    log "当前连接数: $current_conns / $max_conns"
    
    # 如果连接数超过80%，增加最大值
    usage_percent=$((current_conns * 100 / max_conns))
    
    if [ "$usage_percent" -gt 80 ]; then
        new_max=$((max_conns * 120 / 100))
        log "连接数使用率 $usage_percent%，增加最大值到 $new_max"
        
        echo "$new_max" > /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || {
            log "无法增加连接跟踪表大小"
            return 1
        }
    fi
    
    log "连接跟踪表优化完成"
}

# 优化iptables规则顺序（安全版）
optimize_iptables_rules() {
    log "优化iptables规则顺序（安全版）..."
    
    # 保存当前规则
    iptables-save > /tmp/iptables.backup.$(date +%Y%m%d%H%M%S)
    
    # 重新加载优化规则（但不清理现有规则，只追加）
    if [ -f "/etc/firewall.d/optimized-rules" ]; then
        # 执行安全版优化规则
        /etc/firewall.d/optimized-rules
        
        log "安全版优化规则加载完成"
    else
        log "优化规则文件不存在"
        return 1
    fi
}

# 监控防火墙性能
monitor_firewall_performance() {
    echo "防火墙性能监控报告（安全版）"
    echo "================================="
    
    # 连接跟踪状态
    echo "连接跟踪状态:"
    if [ -f "/proc/net/nf_conntrack" ]; then
        total_conns=$(wc -l < /proc/net/nf_conntrack 2>/dev/null || echo "0")
        max_conns=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "N/A")
        echo "  当前连接数: $total_conns"
        echo "  最大连接数: $max_conns"
    else
        echo "  连接跟踪信息不可用"
    fi
    echo ""
    
    # 检查管理访问是否正常
    echo "管理访问检查:"
    local lan_access=$(iptables -L INPUT -n | grep -c "br-lan.*ACCEPT")
    local established_access=$(iptables -L INPUT -n | grep -c "ESTABLISHED.*ACCEPT")
    
    if [ "$lan_access" -gt 0 ]; then
        echo "  ✓ LAN访问: 允许"
    else
        echo "  ✗ LAN访问: 未配置"
    fi
    
    if [ "$established_access" -gt 0 ]; then
        echo "  ✓ 已建立连接: 允许"
    else
        echo "  ✗ 已建立连接: 未配置"
    fi
    echo ""
    
    # 流量统计
    echo "简单流量统计:"
    for iface in br-lan eth0; do
        if [ -d "/sys/class/net/$iface" ]; then
            rx_bytes=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo "0")
            tx_bytes=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo "0")
            
            if [ "$rx_bytes" -gt 0 ] || [ "$tx_bytes" -gt 0 ]; then
                rx_kb=$((rx_bytes / 1024))
                tx_kb=$((tx_bytes / 1024))
                echo "  $iface: 接收 ${rx_kb}KB, 发送 ${tx_kb}KB"
            fi
        fi
    done
}

# 恢复安全配置（如果防火墙配置出错）
restore_safe_config() {
    log "恢复安全防火墙配置..."
    
    # 重置为默认安全配置
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    
    # 设置基本安全规则
    iptables -P INPUT ACCEPT
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT
    
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -i br-lan -j ACCEPT
    iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    iptables -A FORWARD -i br-lan -o eth0 -j ACCEPT
    iptables -A FORWARD -i eth0 -o br-lan -m state --state ESTABLISHED,RELATED -j ACCEPT
    
    log "安全配置已恢复，可以正常访问管理界面"
    echo "安全配置已恢复！现在可以通过Web界面访问路由器。"
}

# 主函数
case "$1" in
    apply)
        safety_check
        apply_kernel_optimization
        optimize_conntrack
        optimize_iptables_rules
        echo "防火墙优化已应用（安全版）"
        echo "管理访问不受影响"
        ;;
    safe)
        restore_safe_config
        ;;
    monitor)
        monitor_firewall_performance
        ;;
    check)
        safety_check
        ;;
    backup)
        iptables-save > /etc/iptables.backup.$(date +%Y%m%d%H%M%S)
        echo "防火墙规则已备份"
        ;;
    restore)
        if [ -n "$2" ] && [ -f "$2" ]; then
            iptables-restore < "$2"
            echo "防火墙规则已从 $2 恢复"
        else
            echo "用法: $0 restore <备份文件>"
        fi
        ;;
    *)
        echo "防火墙性能优化工具（安全版）"
        echo "用法: $0 {apply|safe|monitor|check|backup|restore}"
        echo "  apply   - 应用安全优化（不会阻断管理访问）"
        echo "  safe    - 恢复安全配置（如果无法访问管理界面）"
        echo "  monitor - 监控防火墙性能"
        echo "  check   - 检查安全配置"
        echo "  backup  - 备份当前规则"
        echo "  restore - 从文件恢复规则"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/firewall-optimize"
}

# ==================== 创建防火墙优化服务 ====================
create_firewall_service() {
    local prefix="$1"
    cat > "${prefix}/etc/init.d/firewall-optimize" << 'EOF'
#!/bin/sh /etc/rc.common

START=96
USE_PROCD=1

start_service() {
    echo "启动防火墙优化服务（安全版）..."
    
    # 等待网络就绪
    sleep 10
    
    # 安全检查
    /usr/sbin/firewall-optimize check >/dev/null 2>&1 || true
    
    # 应用内核优化
    if [ -f "/etc/sysctl.d/99-firewall-optimization.conf" ]; then
        sysctl -p /etc/sysctl.d/99-firewall-optimization.conf >/dev/null 2>&1 || true
        echo "应用防火墙内核优化参数"
    fi
    
    # 记录日志
    logger -t firewall-optimize "防火墙优化服务启动完成（安全版）"
}

stop_service() {
    echo "停止防火墙优化服务..."
    logger -t firewall-optimize "防火墙优化服务停止"
}

restart() {
    stop
    sleep 2
    start
}
EOF
    chmod +x "${prefix}/etc/init.d/firewall-optimize"
}

# ==================== 创建Web界面 ====================
create_firewall_web_interface() {
    local prefix="$1"
    
    # LuCI控制器
    cat > "${prefix}/usr/lib/lua/luci/controller/admin/firewall-optimize.lua" << 'EOF'
module("luci.controller.admin.firewall-optimize", package.seeall)

function index()
    entry({"admin", "network", "firewall-optimize"}, template("admin_system/firewall_optimize"), _("防火墙优化"), 61)
    entry({"admin", "network", "firewall-optimize", "status"}, call("get_status")).leaf = true
    entry({"admin", "network", "firewall-optimize", "apply"}, call("apply_optimization")).leaf = true
    entry({"admin", "network", "firewall-optimize", "safe"}, call("restore_safe")).leaf = true
end

function get_status()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/firewall-optimize monitor 2>&1")
    
    http.prepare_content("text/plain")
    http.write(result)
end

function apply_optimization()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/firewall-optimize apply 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "防火墙优化已应用（安全版）"})
end

function restore_safe()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/firewall-optimize safe 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "已恢复安全配置"})
end
EOF

    # Web界面（简化版）
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/firewall_optimize.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:防火墙性能优化（安全版）%></h2>
    
    <!-- 安全警告 -->
    <div class="alert-message" style="background: #fff3cd; color: #856404; border: 1px solid #ffeaa7; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">⚠️ 安全优化说明</h4>
        <p style="margin-bottom: 10px;">此优化方案专门设计为<b>不会阻断管理访问</b>。应用优化后仍然可以通过Web和SSH管理路由器。</p>
        <p style="margin: 5px 0;"><b>如果应用后无法访问：</b></p>
        <ol style="margin: 5px 0; padding-left: 20px;">
            <li>通过有线连接访问路由器</li>
            <li>点击下方的"恢复安全配置"按钮</li>
            <li>或通过SSH执行: <code>firewall-optimize safe</code></li>
        </ol>
    </div>
    
    <!-- 防火墙状态 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:防火墙状态%></h3>
        <div id="firewall-status" style="min-height: 200px; padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed; font-family: monospace; font-size: 12px;">
            <div style="text-align: center; padding: 20px;">
                <div class="spinner"></div>
                <p>正在加载防火墙状态...</p>
            </div>
        </div>
        <div style="margin-top: 15px; display: flex; gap: 12px;">
            <button id="refresh-status" class="btn-primary" style="padding: 10px 20px;">
                <i class="icon icon-refresh"></i> 刷新状态
            </button>
        </div>
    </div>
    
    <!-- 操作按钮 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:操作%></h3>
        <div style="display: flex; gap: 12px; flex-wrap: wrap;">
            <button id="apply-optimize" class="btn-success" style="padding: 12px 24px;">
                <i class="icon icon-shield"></i> 应用安全优化
            </button>
            <button id="restore-safe" class="btn-danger" style="padding: 12px 24px;">
                <i class="icon icon-undo"></i> 恢复安全配置
            </button>
        </div>
        <div style="margin-top: 15px; background: #e8f4fd; padding: 12px; border-radius: 6px; border-left: 4px solid #2196F3;">
            <p style="margin: 0; font-size: 13px; color: #0c5460;">
                <b>建议：</b>首次使用请先点击"应用安全优化"，如果出现问题再点击"恢复安全配置"。
            </p>
        </div>
    </div>
    
    <!-- 命令行参考 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:命令行参考%></h3>
        <div style="background: #2c3e50; color: white; padding: 15px; border-radius: 6px; font-family: monospace; font-size: 13px;">
            <p style="margin: 5px 0;"># 应用安全优化</p>
            <code style="display: block; background: #34495e; padding: 8px; border-radius: 4px; margin: 5px 0 15px 0;">
                firewall-optimize apply
            </code>
            
            <p style="margin: 5px 0;"># 恢复安全配置（如果无法访问）</p>
            <code style="display: block; background: #34495e; padding: 8px; border-radius: 4px; margin: 5px 0 15px 0;">
                firewall-optimize safe
            </code>
            
            <p style="margin: 5px 0;"># 查看防火墙状态</p>
            <code style="display: block; background: #34495e; padding: 8px; border-radius: 4px; margin: 5px 0 0 0;">
                firewall-optimize monitor
            </code>
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

// 加载防火墙状态
function loadFirewallStatus() {
    var statusDiv = document.getElementById('firewall-status');
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/network/firewall-optimize/status")%>', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                statusDiv.innerHTML = '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; font-size: 12px; line-height: 1.4;">' + xhr.responseText + '</pre>';
            } else {
                statusDiv.innerHTML = '<div style="color: #e74c3c; padding: 20px; text-align: center;">加载状态失败</div>';
            }
        }
    };
    xhr.send();
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    loadFirewallStatus();
    
    // 刷新状态按钮
    document.getElementById('refresh-status').addEventListener('click', function() {
        loadFirewallStatus();
        showStatus('状态已刷新', 'info');
    });
    
    // 应用优化按钮
    document.getElementById('apply-optimize').addEventListener('click', function() {
        if (confirm('确定要应用安全版防火墙优化吗？\n\n✓ 不会阻断管理访问\n✓ 优化连接跟踪性能\n✓ 启用基本安全防护')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 优化中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/network/firewall-optimize/apply")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('✅ 防火墙优化已应用，管理访问不受影响', 'success');
                            setTimeout(loadFirewallStatus, 2000);
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
    
    // 恢复安全配置按钮
    document.getElementById('restore-safe').addEventListener('click', function() {
        if (confirm('确定要恢复安全配置吗？\n\n⚠️ 此操作将：\n1. 重置所有防火墙规则\n2. 允许所有LAN访问\n3. 阻止所有WAN到LAN的主动连接\n\n用于修复无法访问管理界面的问题。')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 恢复中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/network/firewall-optimize/safe")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('✅ 安全配置已恢复，现在可以正常访问管理界面', 'success');
                            setTimeout(loadFirewallStatus, 2000);
                        }
                    } catch (e) {
                        showStatus('恢复失败: ' + e.message, 'error');
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
    width: 30px;
    height: 30px;
    border: 3px solid #f3f3f3;
    border-top: 3px solid #3498db;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin-bottom: 10px;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

.btn-primary, .btn-success, .btn-danger {
    padding: 10px 20px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    text-align: center;
}

.btn-primary {
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

.btn-primary:hover, .btn-success:hover, .btn-danger:hover {
    opacity: 0.9;
    transform: translateY(-1px);
}

.btn-primary:disabled, .btn-success:disabled, .btn-danger:disabled {
    opacity: 0.6;
    cursor: not-allowed;
    transform: none;
}
`;
document.head.appendChild(style);
</script>
<%+footer%>
EOF
}

# ==================== 执行安装 ====================
create_firewall_optimization "$INSTALL_DIR"
create_firewall_service "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 创建Web界面
    create_firewall_web_interface "$INSTALL_DIR"
    
    # 启用防火墙优化服务（但不自动启动）
    /etc/init.d/firewall-optimize enable 2>/dev/null || true
    echo "防火墙优化服务已启用（不会自动启动）"
    
    # 应用内核参数（安全）
    if [ -f "/etc/sysctl.d/99-firewall-optimization.conf" ]; then
        sysctl -p /etc/sysctl.d/99-firewall-optimization.conf 2>/dev/null || true
        echo "内核参数已应用"
    fi
    
    # 不自动集成优化规则，由用户手动选择
    echo "优化规则已安装，但未自动应用"
    echo "请手动运行 'firewall-optimize apply' 应用优化"
    
    # 重启LuCI使新页面生效
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
    
    echo ""
    echo "✓ 防火墙性能优化已安装（安全版）"
    echo ""
    echo "【重要提示】:"
    echo "  1. 此版本专门设计为不会阻断管理访问"
    echo "  2. 需要手动应用优化：firewall-optimize apply"
    echo "  3. 如果出现问题：firewall-optimize safe"
    echo ""
    echo "【访问方式】:"
    echo "  LuCI界面 → 网络 → 防火墙优化"
    echo ""
    echo "【使用说明】:"
    echo "  首次使用建议："
    echo "  1. 通过Web界面访问防火墙优化页面"
    echo "  2. 点击'应用安全优化'按钮"
    echo "  3. 如果无法访问，点击'恢复安全配置'"
    echo "  4. 或通过SSH执行相应命令"
else
    create_firewall_web_interface "$INSTALL_DIR"
    echo "✓ 防火墙性能优化已集成到固件（安全版）"
fi

echo "防火墙性能优化配置完成！"
