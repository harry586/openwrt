#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 网络性能优化脚本
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

echo "开始优化网络性能..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/sysctl.d"
    mkdir -p "${prefix}/usr/sbin"
}

create_dirs "$INSTALL_DIR"

# ==================== TCP/IP协议栈优化 ====================
create_network_optimization() {
    local prefix="$1"
    cat > "${prefix}/etc/sysctl.d/99-network-optimization.conf" << 'EOF'
# =============================================
# 网络性能优化配置
# =============================================

# 网络核心缓冲区优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 65536
net.core.wmem_default = 65536
net.core.optmem_max = 65536
net.core.netdev_max_backlog = 5000
net.core.somaxconn = 1024
net.core.default_qdisc = fq_codel

# TCP缓冲区优化
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mem = 65536 131072 262144

# TCP拥塞控制优化
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_notsent_lowat = 16384

# TCP连接优化
net.ipv4.tcp_max_syn_backlog = 1024
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3

# TCP窗口缩放和时间戳
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_ecn = 2

# TCP MTU探测
net.ipv4.tcp_mtu_probing = 1

# IP转发和路由优化
net.ipv4.ip_forward = 1
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.route.gc_timeout = 100

# ARP缓存优化
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 2048
net.ipv4.neigh.default.gc_thresh3 = 4096
net.ipv4.neigh.default.gc_interval = 30
net.ipv4.neigh.default.gc_stale_time = 60

# 减少TIME_WAIT连接
net.ipv4.tcp_max_orphans = 65536
net.ipv4.tcp_orphan_retries = 0

# 快速回收TIME_WAIT套接字
net.ipv4.tcp_tw_recycle = 0  # 注意：在NAT环境中建议为0

# 连接跟踪优化
net.netfilter.nf_conntrack_max = 65536
net.netfilter.nf_conntrack_tcp_timeout_established = 86400
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120
net.netfilter.nf_conntrack_tcp_timeout_close_wait = 60
net.netfilter.nf_conntrack_tcp_timeout_fin_wait = 120

# IPv6优化（如果启用）
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.accept_ra = 2
net.ipv6.conf.default.accept_ra = 2
EOF
}

# ==================== 网络接口优化 ====================
create_interface_optimization() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/optimize-interfaces" << 'EOF'
#!/bin/sh
# 网络接口优化脚本

echo "正在优化网络接口参数..."

# 优化所有网络接口
for iface in $(ls /sys/class/net/ | grep -v lo); do
    echo "优化接口: $iface"
    
    # 启用各种offload功能
    ethtool -K "$iface" rx on tx on sg on tso on 2>/dev/null || true
    ethtool -K "$iface" gso on gro on lro off 2>/dev/null || true
    
    # 设置Ring Buffer大小
    ethtool -G "$iface" rx 4096 tx 4096 2>/dev/null || true
    
    # 设置中断合并
    ethtool -C "$iface" rx-usecs 100 rx-frames 32 2>/dev/null || true
    
    # 对于无线接口的特殊优化
    if echo "$iface" | grep -q "^wlan"; then
        iw dev "$iface" set power_save off 2>/dev/null || true
        echo "无线接口 $iface 已禁用省电模式"
    fi
    
    # 对于以太网接口的特殊优化
    if echo "$iface" | grep -q "^eth"; then
        ethtool -s "$iface" speed 1000 duplex full autoneg on 2>/dev/null || true
    fi
done

# 优化网络队列
echo "优化网络队列..."
for queue in /sys/class/net/*/queues/*; do
    if [ -f "$queue/rps_cpus" ]; then
        echo "f" > "$queue/rps_cpus" 2>/dev/null || true  # 使用所有CPU核心
    fi
    if [ -f "$queue/rps_flow_cnt" ]; then
        echo "32768" > "$queue/rps_flow_cnt" 2>/dev/null || true
    fi
done

echo "网络接口优化完成！"
EOF
    chmod +x "${prefix}/usr/sbin/optimize-interfaces"
}

# ==================== 连接跟踪优化 ====================
create_conntrack_script() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/optimize-conntrack" << 'EOF'
#!/bin/sh
# 连接跟踪优化脚本

echo "正在优化连接跟踪表..."

# 检查conntrack模块是否加载
if [ -d /proc/sys/net/netfilter ]; then
    # 设置连接跟踪表大小
    sysctl -w net.netfilter.nf_conntrack_max=65536 2>/dev/null || true
    
    # 设置超时时间
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=86400 2>/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=120 2>/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close_wait=60 2>/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_tcp_timeout_fin_wait=120 2>/dev/null || true
    
    # UDP连接跟踪优化
    sysctl -w net.netfilter.nf_conntrack_udp_timeout=30 2>/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=180 2>/dev/null || true
    
    # 其他协议
    sysctl -w net.netfilter.nf_conntrack_icmp_timeout=30 2>/dev/null || true
    sysctl -w net.netfilter.nf_conntrack_generic_timeout=600 2>/dev/null || true
    
    # 哈希表大小
    sysctl -w net.netfilter.nf_conntrack_buckets=16384 2>/dev/null || true
    
    echo "连接跟踪表优化完成！"
else
    echo "连接跟踪模块未加载，跳过优化"
fi

# 如果使用iptables，优化规则
if command -v iptables >/dev/null 2>&1; then
    echo "优化iptables规则..."
    # 添加连接跟踪辅助规则
    iptables -t raw -A PREROUTING -p tcp --dport 80 -j NOTRACK 2>/dev/null || true
    iptables -t raw -A PREROUTING -p tcp --sport 80 -j NOTRACK 2>/dev/null || true
fi
EOF
    chmod +x "${prefix}/usr/sbin/optimize-conntrack"
}

# ==================== 应用优化 ====================
create_network_optimization "$INSTALL_DIR"
create_interface_optimization "$INSTALL_DIR"
create_conntrack_script "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行优化脚本
    /usr/sbin/optimize-interfaces
    /usr/sbin/optimize-conntrack
    
    # 应用sysctl设置
    sysctl -p /etc/sysctl.d/99-network-optimization.conf 2>/dev/null || true
    
    # 重启网络服务
    if [ -f /etc/init.d/network ]; then
        /etc/init.d/network restart 2>/dev/null || true
    fi
    
    # 创建计划任务
    echo "# 每天凌晨2点优化网络性能" >> /etc/crontabs/root
    echo "0 2 * * * /usr/sbin/optimize-interfaces >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 3 * * 1 /usr/sbin/optimize-conntrack >/dev/null 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ 网络性能优化已应用"
else
    echo "✓ 网络性能优化配置已集成到固件"
fi

echo "网络性能优化完成！"
echo "优化包括："
echo "  ✓ TCP/IP协议栈优化"
echo "  ✓ 网络接口参数优化"
echo "  ✓ 连接跟踪表优化"
echo "  ✓ BBR拥塞控制算法"
echo "  ✓ 定期自动优化"
