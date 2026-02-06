#!/bin/bash
# =============================================
# OpenWrt SmartDNS 优化配置脚本
# 根据 smartdns.txt 调整配置，保持其他配置不变
# =============================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# 检测运行环境
echo "========================================"
print_info "SmartDNS 配置脚本（基于 smartdns.txt）"
echo "========================================"

if [ -f "/etc/openwrt_release" ] || [ -d "/etc/config" ]; then
    print_status "检测到在路由器环境运行，执行运行时安装..."
    RUNTIME_MODE="true"
    INSTALL_DIR="/"
else
    print_status "检测到在编译环境运行，集成到固件..."
    RUNTIME_MODE="false"
    INSTALL_DIR="files/"
fi

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/smartdns"
    mkdir -p "${prefix}/var/log/smartdns" 2>/dev/null || true
    
    print_status "创建目录结构完成"
}

# ==================== SmartDNS 配置（根据 smartdns.txt） ====================
create_smartdns_config() {
    local prefix="$1"
    cat > "${prefix}/etc/config/smartdns" << 'EOF'
config smartdns
    # ==================== 基础设置 ====================
    option enabled '1'
    option port '6053'
    option server_name 'SmartDNS_Neptune'
    
    # ==================== 缓存优化设置（根据 smartdns.txt） ====================
    option cache_size '0'               # 缓存条目数：0（无限制）- 根据 smartdns.txt
    option cache_persist '0'            # 持久化缓存：禁用 - 根据 smartdns.txt
    option serve_expired '0'            # 过期缓存服务：禁用 - 根据 smartdns.txt
    option prefetch_domain '1'          # 域名预获取：启用（保持）
    option rr_ttl '7200'                # 最大TTL：7200秒
    option rr_ttl_min '30'              # 最小TTL：30秒
    
    # ==================== 智能解析设置（保持原样） ====================
    option dualstack_ip_selection '1'   # 双栈IP优选
    option resolve_local_hostnames '1'  # 解析本地主机名（保持启用）
    option response_mode 'fastest-ip'   # 返回最快IP
    option speed_check_mode 'ping,tcp:80,tcp:443'  # 测速模式（保持原样）
    
    # ==================== 第二DNS设置（保持原样） ====================
    option seconddns_enabled '1'        # 启用第二DNS
    option seconddns_port '5335'        # 第二DNS端口
    option seconddns_server_group 'fq_dns'  # 第二DNS服务器组
    
    # ==================== 网络协议设置（保持原样） ====================
    option seconddns_tcp_server '0'     # 第二DNS禁用TCP
    option tcp_server '0'               # 主DNS禁用TCP
    option ipv6_server '0'              # 禁用IPv6服务器
    option bind_device '1'              # 绑定网络接口
    
    # ==================== DNS记录优化（保持原样） ====================
    option force_https_soa '1'          # 强制HTTPS SOA记录
    option force_aaaa_soa '1'           # 强制AAAA SOA记录
    
    # ==================== 系统集成设置（保持原样） ====================
    option auto_set_dnsmasq '1'         # 自动设置dnsmasq
    option old_port '6053'              # 旧端口
    option old_enabled '1'              # 旧服务启用状态
    option old_auto_set_dnsmasq '1'     # 旧自动设置开关

# ==================== 域名规则（保持原样） ====================
config domain-rule

# ==================== DNS服务器配置（保持原样） ====================
config server
    option name '114dns_1'
    option ip '114.114.114.114'
    option type 'udp'
    option enabled '1'

config server
    option enabled '1'
    option name '腾讯DNSPod_DNS'
    option ip '119.29.29.29'
    option type 'udp'

config server
    option name 'google_dns_1'
    option ip '8.8.8.8'
    option type 'udp'
    option enabled '1'
EOF
    print_status "创建主配置文件完成（根据 smartdns.txt）"
}

# ==================== 自定义配置文件（空白） ====================
create_smartdns_custom_conf() {
    local prefix="$1"
    cat > "${prefix}/etc/smartdns/custom.conf" << 'EOF'
# =============================================
# SmartDNS 自定义配置文件
# 注意：为避免配置冲突，此文件保持空白
# 所有配置通过 /etc/config/smartdns 管理
# =============================================

# 如需添加自定义配置，请确保不会与主配置冲突
# 冲突配置项包括：
# - server 相关配置
# - speed-check-mode（测速模式）
# - rr-ttl 相关设置
# - cache 相关设置

# 可以安全添加的配置：
# 1. 域名屏蔽（广告屏蔽）
# address /ad.example.com/#
# address /tracking.domain/#

# 2. 特定域名解析
# address /home.server/192.168.1.100

# 3. 特殊域名规则
# domain-rules /example.com/ -c none
EOF
    print_status "创建空白自定义配置文件（避免冲突）"
}

# ==================== 兼容性配置文件 ====================
create_smartdns_old_conf() {
    local prefix="$1"
    cat > "${prefix}/etc/smartdns/smartdns.conf" << 'EOF'
# SmartDNS 兼容性配置文件
# 注意：此文件仅用于兼容旧版本
# 主要配置在 /etc/config/smartdns 中管理

# 基础配置（自动生成）
bind [::]:6053
bind-tcp [::]:6053

# 缓存配置（根据 smartdns.txt）
cache-size 0
cache-persist no

# 警告：不要在此手动添加 server 配置
# 所有服务器配置通过 LuCI 界面管理
EOF
    print_status "创建兼容性配置文件"
}

# ==================== 主程序逻辑 ====================
if [ "$RUNTIME_MODE" = "true" ]; then
    print_info "正在应用配置..."
    
    # 备份原始配置
    BACKUP_FILE="/etc/config/smartdns.backup.$(date +%Y%m%d_%H%M%S)"
    if [ -f "/etc/config/smartdns" ]; then
        cp "/etc/config/smartdns" "$BACKUP_FILE"
        print_status "原始配置已备份到: $BACKUP_FILE"
    fi
    
    # 创建新配置
    create_smartdns_config ""
    create_smartdns_custom_conf ""
    create_smartdns_old_conf ""
    
    # 清理可能存在的冲突配置
    if [ -f /etc/smartdns/custom.conf ]; then
        sed -i '/^server/d' /etc/smartdns/custom.conf 2>/dev/null || true
        sed -i '/^speed-check-mode/d' /etc/smartdns/custom.conf 2>/dev/null || true
        sed -i '/^rr-ttl/d' /etc/smartdns/custom.conf 2>/dev/null || true
        sed -i '/^cache-/d' /etc/smartdns/custom.conf 2>/dev/null || true
        sed -i '/^serve-expired/d' /etc/smartdns/custom.conf 2>/dev/null || true
    fi
    
    # 重启服务
    if [ -f /etc/init.d/smartdns ]; then
        print_info "重启 SmartDNS 服务..."
        /etc/init.d/smartdns restart 2>/dev/null
        sleep 2
    fi
    
    if [ -f /etc/init.d/dnsmasq ]; then
        print_info "重启 dnsmasq 服务..."
        /etc/init.d/dnsmasq restart 2>/dev/null
    fi
    
    # 显示配置摘要
    echo ""
    print_info "配置摘要（基于 smartdns.txt）："
    print_status "✓ 测速模式保持: ping,tcp:80,tcp:443"
    print_status "✓ 最大TTL: 7200 秒"
    print_status "✓ 最小TTL: 30 秒"
    print_status "✓ 缓存大小: 0（无限制）"
    print_status "✓ 缓存持久化: 禁用"
    print_status "✓ 过期缓存服务: 禁用"
    print_status "✓ 域名预获取: 启用"
    print_status "✓ 解析本地主机名: 启用"
    print_status "✓ DNS服务器: 114DNS, DNSPod, Google DNS"
    
else
    print_info "正在集成配置到固件..."
    create_smartdns_config "files"
    create_smartdns_custom_conf "files"
    create_smartdns_old_conf "files"
    print_status "✓ 配置已集成到固件"
fi

echo ""
print_info "SmartDNS 配置完成！"
print_warning "注意：配置已按照 smartdns.txt 更新缓存设置"
print_warning "      - 缓存大小: 0（无限制）"
print_warning "      - 缓存持久化: 禁用"
print_warning "      - 过期缓存服务: 禁用"
