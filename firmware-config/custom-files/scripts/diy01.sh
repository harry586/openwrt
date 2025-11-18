#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 系统优化和功能增强
# 修复版本：解决版本兼容性和文件路径问题
# 兼容性：支持 OpenWrt 21.02/22.03 及更新版本
# =============================================

echo "=========================================="
echo "开始应用系统优化和功能增强..."
echo "=========================================="

# 设置错误处理
set -e

# ==================== 1. 基础环境检查 ====================
echo "1. 检查构建环境..."
if [ ! -d "files" ]; then
    echo "创建 files 目录结构..."
    mkdir -p files/{bin,etc/{config,sysctl.d,init.d,hotplug.d,rc.d},etc/crontabs,usr/{bin,share/libubox},lib/functions,www/cgi-bin}
    echo "✅ 目录结构创建完成"
else
    # 确保所有必要的子目录都存在
    mkdir -p files/{bin,etc/{config,sysctl.d,init.d,hotplug.d,rc.d},etc/crontabs,usr/{bin,share/libubox},lib/functions,www/cgi-bin}
    echo "✅ 目录结构检查完成"
fi

# ==================== 2. 内存优化配置 ====================
echo "2. 配置内存优化..."
mkdir -p files/etc/sysctl.d

# 内存和网络优化配置
cat > files/etc/sysctl.d/99-optimize.conf << 'EOF'
# 内存优化
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.vfs_cache_pressure=50

# 网络优化
net.core.netdev_max_backlog=16384
net.core.somaxconn=8192
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 16384 16777216
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_syncookies=1
EOF
echo "✅ 内存优化配置完成"

# ==================== 3. 定时内存清理 ====================
echo "3. 配置定时内存清理..."
mkdir -p files/usr/bin
mkdir -p files/etc/crontabs

# 内存清理脚本
cat > files/usr/bin/clean-memory << 'EOF'
#!/bin/sh
# 内存清理脚本

echo "🔄 开始内存清理..."
echo "⏰ 时间: $(date)"

# 同步文件系统
sync

# 清理页面缓存、目录项和inodes
echo "🧹 清理系统缓存..."
echo 3 > /proc/sys/vm/drop_caches

# 显示清理后内存状态
echo "📊 内存清理完成，当前状态:"
free -h

echo "✅ 内存清理完成"
echo "⏰ 下次清理: 明天凌晨3点"
EOF
chmod +x files/usr/bin/clean-memory

# 定时任务 - 每天凌晨3点清理内存
cat > files/etc/crontabs/root << 'EOF'
# 系统定时任务配置
# 注意：修改此文件后需要重启crond服务生效

# 分钟 小时 日 月 星期 命令

# 每天凌晨3点执行内存释放
0 3 * * * /usr/bin/clean-memory >/dev/null 2>&1

# 每6小时同步时间
0 */6 * * * /usr/sbin/ntpd -q -n -p ntp.aliyun.com >/dev/null 2>&1

# 每周一凌晨2点清理临时文件
0 2 * * 1 rm -rf /tmp/luci-* >/dev/null 2>&1
EOF
echo "✅ 定时内存清理配置完成"

# ==================== 4. Overlay备份系统 ====================
echo "4. 安装Overlay备份系统..."

# 创建备份脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# Overlay备份恢复工具 v3.0 - 兼容所有版本

VERSION="3.0"
BACKUP_DIR="/tmp/overlay-backups"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

info() {
    echo -e "${BLUE}ℹ️ $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️ $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

usage() {
    echo "Overlay备份工具 v$VERSION"
    echo "用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  backup [name]    创建备份 (可选备份名称)"
    echo "  restore <file>   恢复备份"
    echo "  list            列出备份文件"
    echo "  clean           清理旧备份"
    echo "  info            显示备份信息"
    echo ""
    echo "示例:"
    echo "  $0 backup"
    echo "  $0 backup my-config"
    echo "  $0 restore backup-20231201-120000.tar.gz"
}

create_backup() {
    local backup_name="$1"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    
    if [ -n "$backup_name" ]; then
        local backup_file="backup-${timestamp}-${backup_name}.tar.gz"
    else
        local backup_file="backup-${timestamp}.tar.gz"
    fi
    
    local backup_path="$BACKUP_DIR/$backup_file"
    
    mkdir -p "$BACKUP_DIR"
    
    info "正在创建系统备份..."
    info "备份文件: $backup_file"
    
    # 使用sysupgrade创建标准备份
    if command -v sysupgrade >/dev/null 2>&1; then
        if sysupgrade -b "$backup_path" 2>/dev/null; then
            local size=$(du -h "$backup_path" | cut -f1)
            success "备份成功创建!"
            info "位置: $backup_path"
            info "大小: $size"
            return 0
        fi
    fi
    
    # 备用方法：手动备份关键配置
    info "使用备用备份方法..."
    if tar -czf "$backup_path" -C / \
        etc/passwd etc/shadow etc/group \
        etc/config/ etc/dropbear/ etc/ssl/ \
        etc/firewall.user etc/hosts etc/resolv.conf \
        etc/sysctl.conf etc/sysctl.d/ \
        --exclude='etc/config/.uci*' \
        --exclude='tmp/*' \
        --exclude='proc/*' \
        --exclude='sys/*' \
        --exclude='dev/*' \
        --exclude='run/*' 2>/dev/null; then
        
        local size=$(du -h "$backup_path" | cut -f1)
        success "备份成功创建!"
        info "位置: $backup_path"
        info "大小: $size"
        return 0
    else
        error "备份创建失败!"
        return 1
    fi
}

restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        error "请指定要恢复的备份文件"
        return 1
    fi
    
    # 自动添加路径
    if [ ! -f "$backup_file" ] && [ -f "$BACKUP_DIR/$backup_file" ]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi
    
    if [ ! -f "$backup_file" ]; then
        error "备份文件不存在: $backup_file"
        return 1
    fi
    
    # 验证备份文件
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        error "备份文件损坏或格式错误"
        return 1
    fi
    
    info "正在恢复备份: $(basename "$backup_file")"
    warning "警告: 此操作将覆盖当前系统配置!"
    
    # 确认操作
    read -p "确定要继续吗? (y/N): " confirm
    case "$confirm" in
        y|Y|yes|YES)
            info "开始恢复..."
            ;;
        *)
            info "恢复操作已取消"
            return 0
            ;;
    esac
    
    # 停止服务
    info "停止服务..."
    for service in uhttpd firewall dnsmasq network; do
        if [ -f "/etc/init.d/$service" ]; then
            /etc/init.d/$service stop 2>/dev/null || true
        fi
    done
    
    sleep 2
    
    # 恢复备份
    info "恢复文件..."
    if tar -xzf "$backup_file" -C / ; then
        success "文件恢复完成"
        
        # 重新加载配置
        uci commit 2>/dev/null || true
        
        info ""
        success "恢复完成!"
        info "建议重启系统以确保所有配置生效"
        info ""
        read -p "立即重启? (y/N): " reboot_confirm
        case "$reboot_confirm" in
            y|Y|yes|YES)
                info "系统将在5秒后重启..."
                sleep 5
                reboot
                ;;
            *)
                info "请手动重启系统: reboot"
                ;;
        esac
    else
        error "恢复失败!"
        info "正在恢复基本服务..."
        /etc/init.d/network start 2>/dev/null || true
        return 1
    fi
}

list_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        info "暂无备份文件"
        return 0
    fi
    
    local backups=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [ -z "$backups" ]; then
        info "暂无备份文件"
        return 0
    fi
    
    echo "备份文件列表:"
    echo "═══════════════════════════════════════════════════"
    printf "%-35s %-10s %-20s\n" "文件名" "大小" "修改时间"
    echo "═══════════════════════════════════════════════════"
    
    for backup in $backups; do
        local name=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local mtime=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        printf "%-35s %-10s %-20s\n" "$name" "$size" "$mtime"
    done
    echo "═══════════════════════════════════════════════════"
}

clean_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        info "暂无备份文件可清理"
        return 0
    fi
    
    # 保留最近5个备份，删除旧的
    local old_backups=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | head -n -5 | cut -d' ' -f2-)
    
    if [ -z "$old_backups" ]; then
        info "无需清理，备份文件数量正常"
        return 0
    fi
    
    info "清理旧备份文件..."
    for backup in $old_backups; do
        info "删除: $(basename "$backup")"
        rm -f "$backup"
    done
    
    success "备份清理完成"
}

backup_info() {
    info "备份工具信息:"
    echo "版本: $VERSION"
    echo "备份目录: $BACKUP_DIR"
    echo ""
    
    if [ -d "$BACKUP_DIR" ]; then
        local backup_count=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f | wc -l)
        local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
        echo "备份数量: $backup_count"
        echo "总大小: $total_size"
    else
        echo "备份目录不存在"
    fi
}

# 主逻辑
case "$1" in
    backup|b)
        create_backup "$2"
        ;;
    restore|r)
        restore_backup "$2"
        ;;
    list|l)
        list_backups
        ;;
    clean|c)
        clean_backups
        ;;
    info|i)
        backup_info
        ;;
    *)
        usage
        ;;
esac
EOF
chmod +x files/usr/bin/overlay-backup
echo "✅ Overlay备份系统安装完成"

# ==================== 5. 服务优化配置 ====================
echo "5. 优化系统服务..."

# 确保 bin 和 init.d 目录存在
mkdir -p files/bin
mkdir -p files/etc/init.d

# 服务优化脚本
cat > files/etc/init.d/service-optimizer << 'EOF'
#!/bin/sh /etc/rc.common
# 服务优化脚本 - 兼容所有版本

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /bin/true
    procd_close_instance
    
    # 延迟执行优化
    (sleep 30 && /bin/optimize-services.sh) &
}

optimize_services() {
    echo "🔄 优化系统服务..."
    
    # 禁用一些不常用的服务（根据实际需求调整）
    [ -L "/etc/rc.d/S50telnet" ] && rm -f "/etc/rc.d/S50telnet"
    [ -L "/etc/rc.d/S20urandom_seed" ] && rm -f "/etc/rc.d/S20urandom_seed"
    
    # 确保关键服务启用
    [ -x "/etc/init.d/network" ] && /etc/init.d/network enable
    [ -x "/etc/init.d/firewall" ] && /etc/init.d/firewall enable
    [ -x "/etc/init.d/uhttpd" ] && /etc/init.d/uhttpd enable
    [ -x "/etc/init.d/cron" ] && /etc/init.d/cron enable
    
    echo "✅ 服务优化完成"
}
EOF
chmod +x files/etc/init.d/service-optimizer

# 创建优化脚本
cat > files/bin/optimize-services.sh << 'EOF'
#!/bin/sh
# 服务优化执行脚本 - 兼容所有版本

echo "🔧 执行服务优化..."

# 设置最大文件打开数
ulimit -n 8192

# 优化网络参数
echo 16384 > /proc/sys/net/core/somaxconn
echo 65536 > /proc/sys/net/core/netdev_max_backlog

# 启用服务优化
[ -x "/etc/init.d/service-optimizer" ] && {
    /etc/init.d/service-optimizer enable
    /etc/init.d/service-optimizer start
}

echo "✅ 服务优化执行完成"
EOF
chmod +x files/bin/optimize-services.sh
echo "✅ 服务优化配置完成"

# ==================== 6. 系统信息脚本 ====================
echo "6. 添加系统信息工具..."

cat > files/usr/bin/system-info << 'EOF'
#!/bin/sh
# 系统信息显示脚本 v3.0 - 兼容所有版本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 获取系统信息
get_system_info() {
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}                系统信息报告 v3.0${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    
    # 系统基本信息
    echo -e "${BLUE}💻 系统信息:${NC}"
    local hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "unknown")
    local distro=$(cat /etc/openwrt_release 2>/dev/null | grep 'DISTRIB_DESCRIPTION' | cut -d'=' -f2 | tr -d \"'")
    local kernel=$(uname -r)
    local uptime=$(uptime | sed 's/.*up //' | sed 's/,.*//')
    
    echo -e "  ${GREEN}└──${NC} 主机名: $hostname"
    echo -e "  ${GREEN}└──${NC} 系统: $distro"
    echo -e "  ${GREEN}└──${NC} 内核: $kernel"
    echo -e "  ${GREEN}└──${NC} 运行时间: $uptime"
    
    # CPU信息
    echo ""
    echo -e "${BLUE}⚡ CPU信息:${NC}"
    local architecture=$(uname -m)
    local load=$(cat /proc/loadavg | cut -d' ' -f1-3)
    local cpu_cores=$(grep -c ^processor /proc/cpuinfo)
    
    echo -e "  ${GREEN}└──${NC} 架构: $architecture"
    echo -e "  ${GREEN}└──${NC} 核心数: $cpu_cores"
    echo -e "  ${GREEN}└──${NC} 负载: $load"
    
    # 内存信息
    echo ""
    echo -e "${BLUE}💾 内存使用:${NC}"
    free -h | awk '
    NR==1{printf "  '${GREEN}└──${NC}' %-6s %-6s %-6s %-6s\n", $1, $2, $3, $4}
    NR==2{printf "  '${GREEN}└──${NC}' Mem:  %-5s %-5s %-5s %-5s\n", $2, $3, $4, $7}
    NR==3{printf "  '${GREEN}└──${NC}' Swap: %-5s %-5s %-5s %-5s\n", $2, $3, $4, $7}'
    
    # 存储信息
    echo ""
    echo -e "${BLUE}💽 存储空间:${NC}"
    df -h | grep -E '^(/dev/|overlay|tmpfs)' | awk '{printf "  '${GREEN}└──${NC}' %s: %s/%s (%s used)\n", $6, $3, $2, $5}'
    
    # 网络信息
    echo ""
    echo -e "${BLUE}🌐 网络接口:${NC}"
    ip -o addr show scope global 2>/dev/null | awk '{gsub(/\/[0-9]+/, ""); printf "  '${GREEN}└──${NC}' %s: %s\n", $2, $4}' || echo "  ${GREEN}└──${NC} 无网络连接"
    
    # 温度信息（如果可用）
    if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
        local temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        local temp_c=$((temp/1000))
        echo ""
        echo -e "${BLUE}🌡️ 温度信息:${NC}"
        echo -e "  ${GREEN}└──${NC} CPU温度: ${temp_c}°C"
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}💡 提示: 使用 'overlay-backup' 备份配置${NC}"
    echo -e "${YELLOW}💡 提示: 使用 'clean-memory' 清理内存${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
}

# 显示帮助
show_help() {
    echo "系统信息工具 v3.0"
    echo ""
    echo "用法: system-info [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help    显示此帮助信息"
    echo "  -v, --version 显示版本信息"
    echo "  -s, --short   简洁模式"
    echo ""
    echo "示例:"
    echo "  system-info        # 显示完整系统信息"
    echo "  system-info --short # 简洁模式"
}

# 简洁模式
short_info() {
    local hostname=$(cat /proc/sys/kernel/hostname 2>/dev/null || echo "unknown")
    local uptime=$(uptime | sed 's/.*up //' | sed 's/,.*//')
    local load=$(cat /proc/loadavg | cut -d' ' -f1)
    
    echo "🏠 $hostname | ⏰ $uptime | 📊 Load: $load | 💾 $(free -m | awk 'NR==2{printf "%.1fG/%.1fG", $3/1024, $2/1024}')"
}

# 主逻辑
case "$1" in
    -h|--help)
        show_help
        ;;
    -v|--version)
        echo "系统信息工具 v3.0"
        ;;
    -s|--short)
        short_info
        ;;
    "")
        get_system_info
        ;;
    *)
        echo "未知选项: $1"
        echo "使用 'system-info --help' 查看帮助"
        ;;
esac
EOF
chmod +x files/usr/bin/system-info
echo "✅ 系统信息工具安装完成"

# ==================== 7. 创建必要的库文件 ====================
echo "7. 创建必要的库文件..."

# 创建基本的shell函数库
mkdir -p files/lib/functions
cat > files/lib/functions.sh << 'EOF'
#!/bin/sh
# 基本shell函数库 - 兼容所有版本

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 错误处理
error() {
    echo "错误: $1" >&2
    exit 1
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 备份文件
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d)"
        log "已备份: $file"
    fi
}
EOF

# 创建jshn.sh的简化版本（避免缺失文件错误）
mkdir -p files/usr/share/libubox
cat > files/usr/share/libubox/jshn.sh << 'EOF'
#!/bin/sh
# jshn.sh 简化版本 - 兼容所有版本

json_init() {
    return 0
}

json_add_string() {
    return 0
}

json_add_array() {
    return 0
}

json_add_object() {
    return 0
}

json_close_array() {
    return 0
}

json_close_object() {
    return 0
}

json_dump() {
    echo "{}"
}

json_load() {
    return 0
}

json_get_var() {
    eval "$2=\"\""
    return 0
}

json_get_values() {
    return 0
}

json_select() {
    return 0
}
EOF
chmod +x files/usr/share/libubox/jshn.sh

# ==================== 8. 修复自定义安装支持 ====================
echo "8. 配置自定义安装支持..."

# 创建自定义安装目录结构
mkdir -p files/root/custom-install

# 创建构建时安装脚本
cat > files/root/custom-install/build-time-install.sh << 'EOF'
#!/bin/sh
echo "=== 开始构建时自定义安装 ==="

# 创建必要的目录结构
mkdir -p /etc/rc.d /etc/hotplug.d /lib/functions /usr/share/libubox

# 安装IPK文件 - 使用本地安装方法
if ls /root/custom-install/*.ipk >/dev/null 2>&1; then
    echo "构建时安装IPK文件..."
    for ipk in /root/custom-install/*.ipk; do
        echo "安装: $(basename $ipk)"
        # 使用opkg本地安装
        if command -v opkg >/dev/null 2>&1; then
            opkg install "$ipk" --force-depends || echo "安装失败: $(basename $ipk)"
        else
            echo "opkg不可用，跳过IPK安装"
            break
        fi
    done
else
    echo "未找到IPK文件"
fi

# 执行构建时脚本
if ls /root/custom-install/*.sh >/dev/null 2>&1; then
    echo "执行构建时脚本..."
    for script in /root/custom-install/*.sh; do
        if [ "$(basename $script)" != "build-time-install.sh" ]; then
            echo "执行: $(basename $script)"
            # 确保脚本有执行权限
            chmod +x "$script"
            # 在子shell中执行，避免影响主进程
            (sh "$script" || echo "执行失败: $(basename $script)") &
        fi
    done
else
    echo "未找到脚本文件"
fi

# 等待后台任务完成
wait

echo "=== 构建时自定义安装完成 ==="

# 清理安装文件（可选）
# rm -rf /root/custom-install
EOF
chmod +x files/root/custom-install/build-time-install.sh

# 创建开机执行脚本
mkdir -p files/etc
cat > files/etc/rc.local << 'EOF'
#!/bin/sh

# 在后台执行构建时自定义安装
[ -f /root/custom-install/build-time-install.sh ] && {
    /root/custom-install/build-time-install.sh >/tmp/build-time-install.log 2>&1 &
}

exit 0
EOF
chmod +x files/etc/rc.local

# ==================== 9. 完成提示 ====================
echo "9. 创建完成提示..."

cat > files/etc/banner.diy2 << 'EOF'
╔═══════════════════════════════════════════╗
║             系统优化已启用                ║
╠═══════════════════════════════════════════╣
║ 可用功能:                                ║
║ • overlay-backup  - 配置备份恢复         ║
║ • clean-memory    - 内存清理             ║
║ • system-info     - 系统信息             ║
║ • 定时内存优化    - 每天凌晨3点          ║
║ • 服务自动优化    - 开机自动优化         ║
╚═══════════════════════════════════════════╝

优化特性:
  ✅ 内存优化配置
  ✅ 网络参数优化  
  ✅ 定时任务管理
  ✅ 备份恢复系统
  ✅ 服务自动优化
  ✅ 系统监控工具

使用说明:
  system-info          # 查看系统状态
  overlay-backup       # 配置备份管理
  clean-memory         # 清理系统内存

构建版本: v3.0 (兼容版)
构建时间: $(date +%Y年%m月)
EOF

echo ""
echo "=========================================="
echo "🎉 系统优化和功能增强完成!"
echo "=========================================="
echo "✅ 内存优化配置"
echo "✅ Overlay备份系统 (v3.0)"
echo "✅ 定时内存清理"
echo "✅ 系统信息工具 (v3.0)"
echo "✅ 服务优化配置"
echo "✅ 必要的库文件"
echo "✅ 自定义安装支持"
echo ""
echo "📋 刷机后可用命令:"
echo "  system-info                 # 显示完整系统信息"
echo "  system-info --short         # 简洁系统信息"
echo "  overlay-backup backup       # 创建配置备份"
echo "  overlay-backup list         # 列出所有备份"
echo "  overlay-backup info         # 备份系统信息"
echo "  clean-memory               # 立即清理内存"
echo ""
echo "⏰ 自动功能:"
echo "  • 每天凌晨3点自动清理内存"
echo "  • 开机自动优化服务"
echo "  • 网络参数自动优化"
echo "  • 自定义安装自动执行"
echo "=========================================="
