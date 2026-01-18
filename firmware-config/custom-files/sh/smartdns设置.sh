#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# SmartDNS DNS服务器设置脚本
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

echo "开始配置SmartDNS DNS服务器..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/smartdns"
}

create_dirs "$INSTALL_DIR"

# ==================== 配置SmartDNS ====================
create_smartdns_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/smartdns" << 'EOF'
config smartdns
    option dualstack_ip_selection '1'
    option prefetch_domain '1'
    option serve_expired '1'
    option seconddns_tcp_server '0'
    option port '6053'
    option seconddns_port '5335'
    option seconddns_server_group 'fq_dns'
    option cache_size '20000'
    option rr_ttl '3600'
    option rr_ttl_min '5'
    option auto_set_dnsmasq '1'
    option bind_device '1'
    option cache_persist '1'
    option resolve_local_hostnames '1'
    option force_https_soa '1'
    option server_name 'SmartDNS_Neptune'
    option response_mode 'fastest-ip'
    option tcp_server '0'
    option ipv6_server '0'
    option force_aaaa_soa '1'
    option speed_check_mode 'tcp:443,tcp:80,ping'
    option seconddns_enabled '1'
    option enabled '0'
    option old_port '6053'
    option old_enabled '0'
    option old_auto_set_dnsmasq '1'

config domain-rule

config server
    option name '114dns_1'
    option ip '114.114.114.114'
    option type 'udp'
    option enabled '0'

config server
    option enabled '1'
    option name '腾讯DNSPod_DNS'
    option ip '119.29.29.29'
    option type 'udp'

config server
    option name 'google_dns_1'
    option ip '8.8.8.8'
    option type 'udp'
    option enabled '0'
EOF
}

create_smartdns_conf() {
    local prefix="$1"
    cat > "${prefix}/etc/smartdns/smartdns.conf" << 'EOF'
# 基础配置
bind [::]:6053
bind-tcp [::]:6053
server-name SmartDNS_Neptune
cache-size 20000
rr-ttl 3600
rr-ttl-min 5
prefetch-domain yes
serve-expired yes
dualstack-ip-selection yes
force-https-soa yes
force-aaaa-soa yes
response-mode fastest-ip
speed-check-mode tcp:443,tcp:80,ping

# 第二DNS服务器组
seconddns-port 5335
seconddns-server-group fq_dns
seconddns-tcp-server no

# DNS服务器
server 119.29.29.29 -group fq_dns
server 8.8.8.8 -group fq_dns -exclude-default-group
server 114.114.114.114 -exclude-default-group

# 缓存持久化
cache-persist yes
cache-file /tmp/smartdns.cache

# 日志配置
log-level info
log-file /var/log/smartdns.log
log-size 128K
log-num 2
EOF
}

if [ "$RUNTIME_MODE" = "true" ]; then
    create_smartdns_config ""
    create_smartdns_conf ""
    
    # 重启服务
    if [ -f /etc/init.d/smartdns ]; then
        /etc/init.d/smartdns restart 2>/dev/null || true
    fi
    
    # 重启dnsmasq使配置生效
    if [ -f /etc/init.d/dnsmasq ]; then
        /etc/init.d/dnsmasq restart 2>/dev/null || true
    fi
    echo "✓ SmartDNS配置已应用"
else
    create_smartdns_config "files"
    create_smartdns_conf "files"
    echo "✓ SmartDNS配置已集成到固件"
fi

echo "SmartDNS DNS服务器设置完成！"