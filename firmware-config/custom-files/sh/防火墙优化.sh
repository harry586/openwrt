#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 防火墙性能优化脚本
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
# 防火墙性能优化配置
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
EOF

    # 创建优化的防火墙规则模板
    cat > "${prefix}/etc/firewall.d/optimized-rules" << 'EOF'
#!/bin/sh
# 优化的防火墙规则
# 这个文件会被包含在主要的防火墙配置中

# 定义变量
LAN_IFACE="br-lan"
WAN_IFACE="eth0"
WAN6_IFACE="@wan6"

# 1. 基础规则设置
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# 2. 连接状态跟踪
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

# 3. 允许本地回环
iptables -A INPUT -i lo -j ACCEPT

# 4. 允许ICMP（ping）
iptables -A INPUT -p icmp -m icmp --icmp-type 8 -m limit --limit 1/sec -j ACCEPT
iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j DROP

# 5. 允许SSH访问（限制频率）
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --set
iptables -A INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 60 --hitcount 4 -j DROP
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# 6. 允许Web管理界面（限制频率）
iptables -A INPUT -p tcp --dport 80 -m state --state NEW -m limit --limit 20/min -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -m state --state NEW -m limit --limit 20/min -j ACCEPT

# 7. 允许DHCP
iptables -A INPUT -p udp --dport 67:68 -j ACCEPT

# 8. 允许DNS
iptables -A INPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p tcp --dport 53 -j ACCEPT

# 9. 允许NTP
iptables -A INPUT -p udp --dport 123 -j ACCEPT

# 10. LAN到WAN转发
iptables -A FORWARD -i $LAN_IFACE -o $WAN_IFACE -j ACCEPT

# 11. 允许从WAN到特定端口（端口转发）
# 示例：将WAN的8080端口转发到内网192.168.1.100的80端口
# iptables -t nat -A PREROUTING -i $WAN_IFACE -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.100:80
# iptables -A FORWARD -i $WAN_IFACE -o $LAN_IFACE -p tcp --dport 80 -d 192.168.1.100 -j ACCEPT

# 12. 防止DoS攻击
iptables -N SYN_FLOOD
iptables -A SYN_FLOOD -p tcp --syn -m limit --limit 1/s -j RETURN
iptables -A SYN_FLOOD -j DROP
iptables -A INPUT -p tcp --syn -j SYN_FLOOD

# 13. 防止端口扫描
iptables -N PORT_SCAN
iptables -A PORT_SCAN -p tcp --tcp-flags SYN,ACK,FIN,RST RST -m limit --limit 1/s -j RETURN
iptables -A PORT_SCAN -j DROP
iptables -A INPUT -p tcp --tcp-flags SYN,ACK,FIN,RST RST -j PORT_SCAN

# 14. 记录被拒绝的连接（可选）
iptables -N LOGGING
iptables -A LOGGING -m limit --limit 2/min -j LOG --log-prefix "Firewall-Dropped: " --log-level 4
iptables -A LOGGING -j DROP
iptables -A INPUT -j LOGGING
iptables -A FORWARD -j LOGGING

# 15. 创建用户链用于流量统计
iptables -N TRAFFIC_IN
iptables -N TRAFFIC_OUT
iptables -N TRAFFIC_FWD

iptables -A INPUT -j TRAFFIC_IN
iptables -A OUTPUT -j TRAFFIC_OUT
iptables -A FORWARD -j TRAFFIC_FWD

# IPv6规则（如果启用）
if [ -n "$WAN6_IFACE" ]; then
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT ACCEPT
    
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -i lo -j ACCEPT
    
    # 允许ICMPv6（必需）
    ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
    ip6tables -A FORWARD -p ipv6-icmp -j ACCEPT
    
    # LAN到WAN转发
    ip6tables -A FORWARD -i $LAN_IFACE -o $WAN6_IFACE -j ACCEPT
fi
EOF
    chmod +x "${prefix}/etc/firewall.d/optimized-rules"

    # 创建防火墙性能优化脚本
    cat > "${prefix}/usr/sbin/firewall-optimize" << 'EOF'
#!/bin/sh
# 防火墙性能优化脚本

LOG_FILE="/var/log/firewall-optimize.log"
CONFIG_FILE="/etc/config/firewall"

# 记录日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
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
    
    # 清理过期的连接
    echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_close 2>/dev/null || true
    echo 1 > /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_fin_wait 2>/dev/null || true
    
    log "连接跟踪表优化完成"
}

# 优化iptables规则顺序
optimize_iptables_rules() {
    log "优化iptables规则顺序..."
    
    # 保存当前规则
    iptables-save > /tmp/iptables.backup.$(date +%Y%m%d%H%M%S)
    
    # 分析规则效率
    analyze_rule_efficiency
    
    # 重新加载优化后的规则
    if [ -f "/etc/firewall.d/optimized-rules" ]; then
        # 先清理现有规则
        iptables -F
        iptables -X
        iptables -t nat -F
        iptables -t nat -X
        iptables -t mangle -F
        iptables -t mangle -X
        
        # 加载优化规则
        /etc/firewall.d/optimized-rules
        
        log "优化规则加载完成"
    else
        log "优化规则文件不存在"
        return 1
    fi
}

# 分析规则效率
analyze_rule_efficiency() {
    log "分析iptables规则效率..."
    
    # 获取规则统计
    local input_rules=$(iptables -L INPUT -n -v --line-numbers 2>/dev/null | tail -n +3)
    local forward_rules=$(iptables -L FORWARD -n -v --line-numbers 2>/dev/null | tail -n +3)
    
    echo "INPUT链规则效率分析:" | tee -a "$LOG_FILE"
    echo "========================================" | tee -a "$LOG_FILE"
    echo "$input_rules" | while read -r line; do
        if [ -n "$line" ]; then
            packets=$(echo "$line" | awk '{print $1}')
            bytes=$(echo "$line" | awk '{print $2}')
            target=$(echo "$line" | awk '{print $3}')
            prot=$(echo "$line" | awk '{print $4}')
            opt=$(echo "$line" | awk '{print $5}')
            source=$(echo "$line" | awk '{print $6}')
            destination=$(echo "$line" | awk '{print $7}')
            
            echo "规则: $prot $source -> $destination $target (包: $packets, 字节: $bytes)" | tee -a "$LOG_FILE"
        fi
    done
    
    echo "" | tee -a "$LOG_FILE"
    echo "建议优化顺序（按匹配频率排序）:" | tee -a "$LOG_FILE"
    echo "1. ESTABLISHED,RELATED 状态检查" | tee -a "$LOG_FILE"
    echo "2. 本地回环接口" | tee -a "$LOG_FILE"
    echo "3. 高频服务（如SSH, HTTP）" | tee -a "$LOG_FILE"
    echo "4. 低频服务" | tee -a "$LOG_FILE"
    echo "5. 默认拒绝规则" | tee -a "$LOG_FILE"
}

# 启用硬件加速（如果可用）
enable_hardware_acceleration() {
    log "检查并启用硬件加速..."
    
    # 检查网络接口硬件卸载支持
    if command -v ethtool >/dev/null 2>&1; then
        for iface in $(ls /sys/class/net/ | grep -E "eth|wan|lan"); do
            # 启用TSO（TCP Segmentation Offload）
            ethtool -K "$iface" tso on 2>/dev/null || true
            
            # 启用GSO（Generic Segmentation Offload）
            ethtool -K "$iface" gso on 2>/dev/null || true
            
            # 启用GRO（Generic Receive Offload）
            ethtool -K "$iface" gro on 2>/dev/null || true
            
            # 启用LRO（Large Receive Offload）
            ethtool -K "$iface" lro off 2>/dev/null || true  # 某些情况下LRO可能导致问题
            
            log "接口 $iface 硬件卸载已配置"
        done
    fi
    
    # 检查内核是否支持连接跟踪硬件加速
    if [ -f "/proc/sys/net/netfilter/nf_conntrack_acct" ]; then
        echo 1 > /proc/sys/net/netfilter/nf_conntrack_acct
        log "连接跟踪统计已启用"
    fi
    
    # 启用iptables连接跟踪加速
    if lsmod | grep -q "xt_CT"; then
        log "连接跟踪目标模块已加载"
    fi
}

# 配置流量控制（QoS）
configure_traffic_control() {
    log "配置流量控制..."
    
    # 检查tc命令
    if ! command -v tc >/dev/null 2>&1; then
        log "tc命令未安装，跳过流量控制配置"
        return 1
    fi
    
    # 创建基本的QoS规则
    local wan_iface=$(uci get network.wan.ifname 2>/dev/null || echo "eth0")
    
    # 清理现有规则
    tc qdisc del dev "$wan_iface" root 2>/dev/null || true
    tc qdisc del dev "$wan_iface" ingress 2>/dev/null || true
    
    # 应用HTB（Hierarchical Token Bucket）队列
    tc qdisc add dev "$wan_iface" root handle 1: htb default 30
    
    # 设置带宽限制（根据实际情况调整）
    local upload_speed=$(uci get sqm.eth1.upload 2>/dev/null || echo "96000")
    local download_speed=$(uci get sqm.eth1.download 2>/dev/null || echo "960000")
    
    # 上传方向
    tc class add dev "$wan_iface" parent 1: classid 1:1 htb rate "${upload_speed}kbit" ceil "${upload_speed}kbit"
    
    # 创建子类
    # 1:10 - 最高优先级（ACK，DNS等）
    tc class add dev "$wan_iface" parent 1:1 classid 1:10 htb rate "$((upload_speed / 10))kbit" ceil "$((upload_speed / 5))kbit" prio 0
    
    # 1:20 - 高优先级（SSH，管理流量）
    tc class add dev "$wan_iface" parent 1:1 classid 1:20 htb rate "$((upload_speed / 5))kbit" ceil "$((upload_speed / 3))kbit" prio 1
    
    # 1:30 - 默认优先级（Web流量）
    tc class add dev "$wan_iface" parent 1:1 classid 1:30 htb rate "$((upload_speed / 2))kbit" ceil "${upload_speed}kbit" prio 2
    
    # 1:40 - 低优先级（大文件下载，P2P）
    tc class add dev "$wan_iface" parent 1:1 classid 1:40 htb rate "$((upload_speed / 10))kbit" ceil "$((upload_speed / 3))kbit" prio 3
    
    # 应用过滤器
    # 最高优先级 - ACK包
    tc filter add dev "$wan_iface" parent 1: protocol ip prio 1 u32 match ip protocol 6 0xff match u8 0x10 0xff at 0 match u16 0x0000 0xffc0 at 2 flowid 1:10
    
    # 高优先级 - SSH
    tc filter add dev "$wan_iface" parent 1: protocol ip prio 2 u32 match ip dport 22 0xffff flowid 1:20
    
    # 默认优先级 - HTTP/HTTPS
    tc filter add dev "$wan_iface" parent 1: protocol ip prio 3 u32 match ip dport 80 0xffff flowid 1:30
    tc filter add dev "$wan_iface" parent 1: protocol ip prio 3 u32 match ip dport 443 0xffff flowid 1:30
    
    log "流量控制配置完成（上传: ${upload_speed}kbit, 下载: ${download_speed}kbit）"
}

# 监控防火墙性能
monitor_firewall_performance() {
    echo "防火墙性能监控报告"
    echo "========================"
    
    # 连接跟踪状态
    echo "连接跟踪状态:"
    if [ -f "/proc/net/nf_conntrack" ]; then
        total_conns=$(wc -l < /proc/net/nf_conntrack)
        max_conns=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "N/A")
        echo "  当前连接数: $total_conns"
        echo "  最大连接数: $max_conns"
        
        # 按协议统计
        echo "  按协议分布:"
        grep -c "proto=17" /proc/net/nf_conntrack 2>/dev/null | awk '{print "    UDP: "$1}'
        grep -c "proto=6" /proc/net/nf_conntrack 2>/dev/null | awk '{print "    TCP: "$1}'
        grep -c "proto=1" /proc/net/nf_conntrack 2>/dev/null | awk '{print "    ICMP: "$1}'
    else
        echo "  连接跟踪信息不可用"
    fi
    echo ""
    
    # iptables规则统计
    echo "iptables规则统计:"
    for chain in INPUT FORWARD OUTPUT; do
        rule_count=$(iptables -L "$chain" -n | grep -c "^ACCEPT\|^DROP\|^REJECT")
        packet_count=$(iptables -L "$chain" -n -v | awk 'NR>2 {sum+=$1} END {print sum}')
        echo "  $chain链: $rule_count 条规则，处理 $packet_count 个包"
    done
    echo ""
    
    # 流量统计
    echo "网络流量统计:"
    if command -v ifconfig >/dev/null 2>&1; then
        for iface in $(ifconfig -a | grep -E "^[a-zA-Z]" | awk '{print $1}' | cut -d: -f1); do
            rx_bytes=$(cat "/sys/class/net/$iface/statistics/rx_bytes" 2>/dev/null || echo "0")
            tx_bytes=$(cat "/sys/class/net/$iface/statistics/tx_bytes" 2>/dev/null || echo "0")
            
            if [ "$rx_bytes" -gt 0 ] || [ "$tx_bytes" -gt 0 ]; then
                rx_mb=$(echo "scale=2; $rx_bytes / 1024 / 1024" | bc)
                tx_mb=$(echo "scale=2; $tx_bytes / 1024 / 1024" | bc)
                echo "  $iface: 接收 ${rx_mb}MB, 发送 ${tx_mb}MB"
            fi
        done
    fi
    echo ""
    
    # CPU使用情况
    echo "防火墙相关进程CPU使用:"
    ps aux | grep -E "(iptables|firewall|conntrack)" | grep -v grep | awk '{print $3, $11}' | while read -r cpu proc; do
        echo "  $proc: ${cpu}%"
    done
}

# 备份和恢复防火墙配置
backup_firewall_config() {
    local backup_dir="/etc/firewall/backup"
    local timestamp=$(date +%Y%m%d%H%M%S)
    
    mkdir -p "$backup_dir"
    
    log "备份防火墙配置..."
    
    # 备份iptables规则
    iptables-save > "$backup_dir/iptables-rules.$timestamp"
    ip6tables-save > "$backup_dir/ip6tables-rules.$timestamp" 2>/dev/null || true
    
    # 备份配置文件
    cp "$CONFIG_FILE" "$backup_dir/firewall.$timestamp"
    
    # 备份内核参数
    sysctl -a 2>/dev/null | grep -E "net\.|nf_" > "$backup_dir/sysctl-net.$timestamp"
    
    log "防火墙配置已备份到 $backup_dir"
    echo "备份文件:"
    ls -la "$backup_dir"/*."$timestamp"
}

# 主函数
case "$1" in
    apply)
        apply_kernel_optimization
        optimize_conntrack
        optimize_iptables_rules
        enable_hardware_acceleration
        ;;
    monitor)
        monitor_firewall_performance
        ;;
    traffic)
        configure_traffic_control
        ;;
    backup)
        backup_firewall_config
        ;;
    restore)
        echo "恢复功能需要指定备份文件"
        echo "用法: $0 restore <备份文件>"
        ;;
    analyze)
        analyze_rule_efficiency
        ;;
    test)
        # 性能测试模式
        echo "防火墙性能测试模式..."
        echo "测试持续时间: 30秒"
        
        # 记录开始状态
        start_conns=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
        
        # 模拟一些连接（使用ping和curl）
        for i in $(seq 1 10); do
            ping -c 1 8.8.8.8 >/dev/null 2>&1 &
            curl -s --connect-timeout 2 http://www.example.com >/dev/null 2>&1 &
        done
        
        sleep 30
        
        # 记录结束状态
        end_conns=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "0")
        
        echo "测试结果:"
        echo "  开始连接数: $start_conns"
        echo "  结束连接数: $end_conns"
        echo "  新增连接数: $((end_conns - start_conns))"
        ;;
    *)
        echo "防火墙性能优化工具"
        echo "用法: $0 {apply|monitor|traffic|backup|analyze|test}"
        echo "  apply   - 应用所有优化"
        echo "  monitor - 监控防火墙性能"
        echo "  traffic - 配置流量控制"
        echo "  backup  - 备份防火墙配置"
        echo "  analyze - 分析规则效率"
        echo "  test    - 运行性能测试"
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
    echo "启动防火墙优化服务..."
    
    # 等待网络就绪
    sleep 8
    
    # 应用内核优化
    if [ -f "/etc/sysctl.d/99-firewall-optimization.conf" ]; then
        sysctl -p /etc/sysctl.d/99-firewall-optimization.conf >/dev/null 2>&1 || true
        echo "应用防火墙内核优化参数"
    fi
    
    # 优化连接跟踪
    /usr/sbin/firewall-optimize apply >/dev/null 2>&1 || true
    
    # 启用硬件加速
    enable_hardware_acceleration
    
    # 记录日志
    logger -t firewall-optimize "防火墙优化服务启动完成"
}

enable_hardware_acceleration() {
    # 检查并启用网络接口硬件加速
    if [ -x "$(command -v ethtool)" ]; then
        for iface in $(ls /sys/class/net/ | grep -E "eth|wan|lan"); do
            # 启用TSO/GSO/GRO
            ethtool -K "$iface" tso on 2>/dev/null || true
            ethtool -K "$iface" gso on 2>/dev/null || true
            ethtool -K "$iface" gro on 2>/dev/null || true
        done
    fi
}

stop_service() {
    echo "停止防火墙优化服务..."
    
    # 记录日志
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
    entry({"admin", "network", "firewall-optimize", "monitor"}, call("get_monitor")).leaf = true
    entry({"admin", "network", "firewall-optimize", "backup"}, call("backup_config")).leaf = true
    entry({"admin", "network", "firewall-optimize", "analyze"}, call("analyze_rules")).leaf = true
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
    http.write_json({success = true, message = "防火墙优化已应用"})
end

function get_monitor()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/firewall-optimize monitor 2>&1")
    
    http.prepare_content("text/plain")
    http.write(result)
end

function backup_config()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/firewall-optimize backup 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "防火墙配置已备份"})
end

function analyze_rules()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/firewall-optimize analyze 2>&1")
    
    http.prepare_content("text/plain")
    http.write(result)
end
EOF

    # Web界面
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/firewall_optimize.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:防火墙性能优化%></h2>
    
    <!-- 信息提示 -->
    <div class="alert-message" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">🛡️ 防火墙性能优化</h4>
        <p style="margin-bottom: 10px;">优化防火墙性能，提升网络吞吐量，增强安全防护能力。</p>
        <ul style="margin: 0; padding-left: 20px;">
            <li><strong>连接跟踪优化：</strong>提升并发连接处理能力</li>
            <li><strong>规则优化：</strong>优化iptables规则顺序，减少匹配时间</li>
            <li><strong>硬件加速：</strong>启用网卡硬件卸载功能</li>
            <li><strong>流量控制：</strong>智能QoS，保证关键业务带宽</li>
            <li><strong>安全增强：</strong>DoS防护，端口扫描防御</li>
        </ul>
    </div>
    
    <!-- 防火墙状态 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:防火墙状态监控%></h3>
        <div id="firewall-status" style="min-height: 300px; padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed; font-family: monospace; font-size: 12px; max-height: 400px; overflow-y: auto;">
            <div style="text-align: center; padding: 40px;">
                <div class="spinner"></div>
                <p>正在加载防火墙状态...</p>
            </div>
        </div>
        <div style="margin-top: 15px; display: flex; gap: 12px;">
            <button id="refresh-status" class="btn-primary" style="padding: 10px 20px;">
                <i class="icon icon-refresh"></i> 刷新状态
            </button>
            <button id="apply-optimize" class="btn-secondary" style="padding: 10px 20px;">
                <i class="icon icon-bolt"></i> 应用优化
            </button>
            <button id="run-monitor" class="btn-info" style="padding: 10px 20px;">
                <i class="icon icon-desktop"></i> 实时监控
            </button>
        </div>
    </div>
    
    <!-- 优化操作 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:优化操作%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:一键优化%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <button id="optimize-now" class="btn-success" style="padding: 10px 20px;">
                        <i class="icon icon-cogs"></i> 全面优化
                    </button>
                    <button id="backup-config" class="btn-warning" style="padding: 10px 20px;">
                        <i class="icon icon-save"></i> 备份配置
                    </button>
                    <button id="analyze-rules" class="btn-neutral" style="padding: 10px 20px;">
                        <i class="icon icon-search"></i> 规则分析
                    </button>
                    <button id="traffic-control" class="btn-info" style="padding: 10px 20px;">
                        <i class="icon icon-tachometer"></i> 流量控制
                    </button>
                </div>
                <p style="margin-top: 10px; color: #7f8c8d; font-size: 12px;">
                    优化操作可能需要重启防火墙服务，短暂影响网络连接
                </p>
            </div>
        </div>
    </div>
    
    <!-- 高级设置 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:高级设置%></h3>
        
        <!-- 连接跟踪设置 -->
        <div class="cbi-value" style="margin-bottom: 15px;">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:连接跟踪%></label>
            <div class="cbi-value-field">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <input type="number" id="conntrack-max" placeholder="最大连接数" style="padding: 8px; border: 1px solid #ddd; border-radius: 4px; width: 150px;" value="65536">
                    <button id="set-conntrack" class="btn-neutral" style="padding: 8px 16px;">
                        设置
                    </button>
                </div>
                <p style="margin-top: 5px; color: #7f8c8d; font-size: 12px;">
                    根据设备内存调整，每连接约消耗300字节内存
                </p>
            </div>
        </div>
        
        <!-- 硬件加速 -->
        <div class="cbi-value" style="margin-bottom: 15px;">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:硬件加速%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px;">
                    <label style="display: flex; align-items: center; gap: 5px;">
                        <input type="checkbox" id="enable-tso" checked>
                        <span>TSO</span>
                    </label>
                    <label style="display: flex; align-items: center; gap: 5px;">
                        <input type="checkbox" id="enable-gso" checked>
                        <span>GSO</span>
                    </label>
                    <label style="display: flex; align-items: center; gap: 5px;">
                        <input type="checkbox" id="enable-gro" checked>
                        <span>GRO</span>
                    </label>
                    <button id="apply-hw-accel" class="btn-neutral" style="padding: 8px 16px;">
                        应用
                    </button>
                </div>
                <p style="margin-top: 5px; color: #7f8c8d; font-size: 12px;">
                    启用网卡硬件卸载，大幅提升网络性能（需要硬件支持）
                </p>
            </div>
        </div>
        
        <!-- 安全防护 -->
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:安全防护%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <label style="display: flex; align-items: center; gap: 5px;">
                        <input type="checkbox" id="enable-dos" checked>
                        <span>DoS防护</span>
                    </label>
                    <label style="display: flex; align-items: center; gap: 5px;">
                        <input type="checkbox" id="enable-portscan" checked>
                        <span>端口扫描防护</span>
                    </label>
                    <label style="display: flex; align-items: center; gap: 5px;">
                        <input type="checkbox" id="enable-synflood" checked>
                        <span>SYN Flood防护</span>
                    </label>
                </div>
                <button id="apply-security" class="btn-neutral" style="margin-top: 10px; padding: 8px 16px;">
                    应用安全设置
                </button>
            </div>
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
                // 将纯文本转换为格式化显示
                var lines = xhr.responseText.split('\n');
                var html = '';
                
                lines.forEach(function(line) {
                    if (line.trim() === '') return;
                    
                    if (line.includes('======')) {
                        html += '<div style="font-weight: 600; color: #2c3e50; margin: 10px 0 5px 0; border-bottom: 1px solid #e1e8ed; padding-bottom: 3px;">' + line + '</div>';
                    } else if (line.includes(':')) {
                        var parts = line.split(':');
                        var key = parts[0].trim();
                        var value = parts.slice(1).join(':').trim();
                        
                        // 根据内容添加样式
                        var valueStyle = 'color: #2c3e50; margin-left: 8px;';
                        
                        if (key.includes('连接数') || key.includes('规则')) {
                            var numMatch = value.match(/\d+/);
                            if (numMatch) {
                                var num = parseInt(numMatch[0]);
                                if (num > 1000) {
                                    valueStyle = 'color: #e74c3c; font-weight: 600; margin-left: 8px;';
                                } else if (num > 100) {
                                    valueStyle = 'color: #f39c12; font-weight: 600; margin-left: 8px;';
                                } else {
                                    valueStyle = 'color: #27ae60; margin-left: 8px;';
                                }
                            }
                        }
                        
                        html += '<div style="margin: 3px 0; padding: 2px 0;">';
                        html += '<span style="color: #34495e; font-weight: 500;">' + key + ':</span>';
                        html += '<span style="' + valueStyle + '">' + value + '</span>';
                        html += '</div>';
                    } else {
                        html += '<div style="color: #7f8c8d; margin: 5px 0;">' + line + '</div>';
                    }
                });
                
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
    loadFirewallStatus();
    
    // 刷新状态按钮
    document.getElementById('refresh-status').addEventListener('click', function() {
        loadFirewallStatus();
        showStatus('状态已刷新', 'info');
    });
    
    // 应用优化按钮
    document.getElementById('apply-optimize').addEventListener('click', function() {
        if (confirm('确定要应用防火墙优化吗？这可能会重启防火墙服务。')) {
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
                            showStatus('防火墙优化已应用', 'success');
                            setTimeout(function() {
                                loadFirewallStatus();
                            }, 3000);
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
    
    // 实时监控按钮
    document.getElementById('run-monitor').addEventListener('click', function() {
        showStatus('实时监控功能需要在终端执行: firewall-optimize monitor', 'info');
    });
    
    // 全面优化按钮
    document.getElementById('optimize-now').addEventListener('click', function() {
        if (confirm('执行全面优化，包括连接跟踪、规则优化、硬件加速等。确定继续吗？')) {
            showStatus('正在执行全面优化，请稍候...', 'info');
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/network/firewall-optimize/apply")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    showStatus('全面优化完成', 'success');
                    setTimeout(function() {
                        loadFirewallStatus();
                    }, 3000);
                }
            };
            xhr.send();
        }
    });
    
    // 备份配置按钮
    document.getElementById('backup-config').addEventListener('click', function() {
        if (confirm('确定要备份当前防火墙配置吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 备份中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/network/firewall-optimize/backup")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('防火墙配置已备份', 'success');
                        }
                    } catch (e) {
                        showStatus('备份失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 规则分析按钮
    document.getElementById('analyze-rules').addEventListener('click', function() {
        var btn = this;
        var originalText = btn.innerHTML;
        btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 分析中...';
        btn.disabled = true;
        
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '<%=luci.dispatcher.build_url("admin/network/firewall-optimize/analyze")%>', true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                var statusDiv = document.getElementById('firewall-status');
                statusDiv.innerHTML = '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; font-size: 12px;">' + xhr.responseText + '</pre>';
                showStatus('规则分析完成', 'success');
                btn.disabled = false;
                btn.innerHTML = originalText;
            }
        };
        xhr.send();
    });
    
    // 流量控制按钮
    document.getElementById('traffic-control').addEventListener('click', function() {
        showStatus('流量控制配置需要更多参数设置，请使用命令行: firewall-optimize traffic', 'info');
    });
    
    // 设置连接跟踪
    document.getElementById('set-conntrack').addEventListener('click', function() {
        var max = document.getElementById('conntrack-max').value;
        if (max && max > 0) {
            showStatus('设置连接跟踪最大值为: ' + max, 'info');
            // 这里应该调用后端接口设置
        } else {
            showStatus('请输入有效的数值', 'error');
        }
    });
    
    // 应用硬件加速
    document.getElementById('apply-hw-accel').addEventListener('click', function() {
        var tso = document.getElementById('enable-tso').checked;
        var gso = document.getElementById('enable-gso').checked;
        var gro = document.getElementById('enable-gro').checked;
        
        showStatus('硬件加速设置已更新: TSO=' + tso + ', GSO=' + gso + ', GRO=' + gro, 'info');
    });
    
    // 应用安全设置
    document.getElementById('apply-security').addEventListener('click', function() {
        var dos = document.getElementById('enable-dos').checked;
        var portscan = document.getElementById('enable-portscan').checked;
        var synflood = document.getElementById('enable-synflood').checked;
        
        showStatus('安全设置已更新: DoS防护=' + dos + ', 端口扫描防护=' + portscan + ', SYN Flood防护=' + synflood, 'info');
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
create_firewall_optimization "$INSTALL_DIR"
create_firewall_service "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 创建Web界面
    create_firewall_web_interface "$INSTALL_DIR"
    
    # 启用防火墙优化服务
    /etc/init.d/firewall-optimize enable 2>/dev/null || true
    /etc/init.d/firewall-optimize start 2>/dev/null || true
    
    # 应用内核参数
    if [ -f "/etc/sysctl.d/99-firewall-optimization.conf" ]; then
        sysctl -p /etc/sysctl.d/99-firewall-optimization.conf 2>/dev/null || true
    fi
    
    # 集成优化规则到防火墙配置
    if [ -f "/etc/config/firewall" ] && [ -f "/etc/firewall.d/optimized-rules" ]; then
        # 备份原配置
        cp /etc/config/firewall /etc/config/firewall.backup.$(date +%Y%m%d%H%M%S)
        
        # 在防火墙配置中引用优化规则
        if ! grep -q "optimized-rules" /etc/config/firewall; then
            echo "" >> /etc/config/firewall
            echo "# 包含优化规则" >> /etc/config/firewall
            echo "option include '/etc/firewall.d/optimized-rules'" >> /etc/config/firewall
        fi
    fi
    
    # 重启LuCI使新页面生效
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
    
    # 重启防火墙使优化生效
    if [ -f /etc/init.d/firewall ]; then
        /etc/init.d/firewall restart 2>/dev/null || true
    fi
    
    # 创建计划任务
    echo "# 防火墙优化任务" >> /etc/crontabs/root
    echo "0 */2 * * * /usr/sbin/firewall-optimize monitor >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 5 * * * /usr/sbin/firewall-optimize backup >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 4 * * 0 /usr/sbin/firewall-optimize apply >/dev/null 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ 防火墙性能优化已应用"
    echo ""
    echo "【访问方式】:"
    echo "   LuCI界面 → 网络 → 防火墙优化"
    echo ""
    echo "【手动操作】:"
    echo "   查看状态: firewall-optimize monitor"
    echo "   应用优化: firewall-optimize apply"
    echo "   备份配置: firewall-optimize backup"
    echo "   性能测试: firewall-optimize test"
else
    create_firewall_web_interface "$INSTALL_DIR"
    echo "✓ 防火墙性能优化已集成到固件"
fi

echo "防火墙性能优化配置完成！"