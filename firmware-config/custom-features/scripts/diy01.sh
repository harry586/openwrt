#!/bin/bash
# =============================================
# OpenWrt DIY 脚本第二部分 - 系统优化和功能增强
# 功能：内存优化、Overlay备份系统、服务优化
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
    mkdir -p files/{etc/config,etc/init.d,etc/crontabs,usr/bin,usr/lib/lua/luci/{controller,view}}
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

# ==================== 3. 定时内存清理 ====================
echo "3. 配置定时内存清理..."
mkdir -p files/usr/bin
mkdir -p files/etc/crontabs

# 内存清理脚本
cat > files/usr/bin/clean-memory << 'EOF'
#!/bin/sh
# 内存清理脚本

echo "开始内存清理..."
sync

# 清理页面缓存、目录项和inodes
echo 3 > /proc/sys/vm/drop_caches

# 清理slab缓存（可选，更彻底）
if [ -f /proc/slabinfo ]; then
    echo 2 > /proc/sys/vm/drop_caches
fi

# 显示清理后内存状态
echo "内存清理完成，当前状态:"
free -m
EOF
chmod +x files/usr/bin/clean-memory

# 定时任务 - 每天凌晨3点清理内存
echo "0 3 * * * /usr/bin/clean-memory >/dev/null 2>&1" >> files/etc/crontabs/root

# ==================== 4. Overlay备份系统 ====================
echo "4. 安装Overlay备份系统..."

# 创建备份脚本
cat > files/usr/bin/overlay-backup << 'EOF'
#!/bin/sh
# Overlay备份恢复工具 v2.0

VERSION="2.0"
BACKUP_DIR="/tmp/overlay-backups"

usage() {
    echo "Overlay备份工具 v$VERSION"
    echo "用法: $0 <command> [options]"
    echo ""
    echo "命令:"
    echo "  backup [name]    创建备份 (可选备份名称)"
    echo "  restore <file>   恢复备份"
    echo "  list            列出备份文件"
    echo "  clean           清理旧备份"
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
    
    echo "正在创建系统备份..."
    echo "备份文件: $backup_file"
    
    # 使用sysupgrade创建标准备份
    if command -v sysupgrade >/dev/null 2>&1; then
        if sysupgrade -b "$backup_path" 2>/dev/null; then
            local size=$(du -h "$backup_path" | cut -f1)
            echo "✅ 备份成功创建!"
            echo "📁 位置: $backup_path"
            echo "📊 大小: $size"
            return 0
        fi
    fi
    
    # 备用方法：手动备份关键配置
    echo "使用备用备份方法..."
    if tar -czf "$backup_path" -C / \
        etc/passwd etc/shadow etc/group etc/config \
        etc/rc.local etc/crontabs etc/sysctl.conf \
        etc/ssl/certs etc/hosts etc/resolv.conf \
        --exclude='etc/config/.uci*' \
        --exclude='tmp/*' \
        --exclude='proc/*' \
        --exclude='sys/*' \
        --exclude='dev/*' \
        --exclude='run/*' 2>/dev/null; then
        
        local size=$(du -h "$backup_path" | cut -f1)
        echo "✅ 备份成功创建!"
        echo "📁 位置: $backup_path"
        echo "📊 大小: $size"
        return 0
    else
        echo "❌ 备份创建失败!"
        return 1
    fi
}

restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        echo "❌ 请指定要恢复的备份文件"
        return 1
    fi
    
    # 自动添加路径
    if [ ! -f "$backup_file" ] && [ -f "$BACKUP_DIR/$backup_file" ]; then
        backup_file="$BACKUP_DIR/$backup_file"
    fi
    
    if [ ! -f "$backup_file" ]; then
        echo "❌ 备份文件不存在: $backup_file"
        return 1
    fi
    
    # 验证备份文件
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        echo "❌ 备份文件损坏或格式错误"
        return 1
    fi
    
    echo "正在恢复备份: $(basename "$backup_file")"
    echo "⚠️  警告: 此操作将覆盖当前系统配置!"
    
    # 确认操作
    read -p "确定要继续吗? (y/N): " confirm
    case "$confirm" in
        y|Y|yes|YES)
            echo "开始恢复..."
            ;;
        *)
            echo "恢复操作已取消"
            return 0
            ;;
    esac
    
    # 停止服务
    echo "停止服务..."
    for service in uhttpd firewall dnsmasq network; do
        if [ -f "/etc/init.d/$service" ]; then
            /etc/init.d/$service stop 2>/dev/null || true
        fi
    done
    
    sleep 2
    
    # 恢复备份
    echo "恢复文件..."
    if tar -xzf "$backup_file" -C / ; then
        echo "✅ 文件恢复完成"
        
        # 重新加载配置
        uci commit 2>/dev/null || true
        
        echo ""
        echo "📋 恢复完成!"
        echo "🔄 建议重启系统以确保所有配置生效"
        echo ""
        echo "立即重启? (y/N): "
        read -p "" reboot_confirm
        case "$reboot_confirm" in
            y|Y|yes|YES)
                echo "系统将在5秒后重启..."
                sleep 5
                reboot
                ;;
            *)
                echo "请手动重启系统: reboot"
                ;;
        esac
    else
        echo "❌ 恢复失败!"
        echo "正在恢复基本服务..."
        /etc/init.d/network start 2>/dev/null || true
        return 1
    fi
}

list_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "暂无备份文件"
        return 0
    fi
    
    local backups=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [ -z "$backups" ]; then
        echo "暂无备份文件"
        return 0
    fi
    
    echo "备份文件列表:"
    echo "═══════════════════════════════════════════════════"
    printf "%-30s %-10s %-20s\n" "文件名" "大小" "修改时间"
    echo "═══════════════════════════════════════════════════"
    
    for backup in $backups; do
        local name=$(basename "$backup")
        local size=$(du -h "$backup" | cut -f1)
        local mtime=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
        printf "%-30s %-10s %-20s\n" "$name" "$size" "$mtime"
    done
}

clean_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "暂无备份文件可清理"
        return 0
    fi
    
    # 保留最近5个备份，删除旧的
    local old_backups=$(find "$BACKUP_DIR" -name "backup-*.tar.gz" -type f -printf '%T@ %p\n' | sort -n | head -n -5 | cut -d' ' -f2-)
    
    if [ -z "$old_backups" ]; then
        echo "无需清理，备份文件数量正常"
        return 0
    fi
    
    echo "清理旧备份文件..."
    for backup in $old_backups; do
        echo "删除: $(basename "$backup")"
        rm -f "$backup"
    done
    
    echo "✅ 备份清理完成"
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
    *)
        usage
        ;;
esac
EOF
chmod +x files/usr/bin/overlay-backup

# ==================== 5. 服务优化配置 ====================
echo "5. 优化系统服务..."

# 禁用不必要的服务（示例）
mkdir -p files/etc/rc.d
cat > files/etc/init.d/service-optimizer << 'EOF'
#!/bin/sh /etc/rc.common

START=15

boot() {
    # 禁用一些不常用的服务（根据实际需求调整）
    [ -L "/etc/rc.d/S50telnet" ] && rm -f "/etc/rc.d/S50telnet"
    [ -L "/etc/rc.d/S20urandom_seed" ] && rm -f "/etc/rc.d/S20urandom_seed"
    
    # 确保关键服务启用
    [ -x "/etc/init.d/network" ] && /etc/init.d/network enable
    [ -x "/etc/init.d/firewall" ] && /etc/init.d/firewall enable
    [ -x "/etc/init.d/uhttpd" ] && /etc/init.d/uhttpd enable
}
EOF
chmod +x files/etc/init.d/service-optimizer

# ==================== 6. 系统信息脚本 ====================
echo "6. 添加系统信息工具..."

cat > files/usr/bin/system-info << 'EOF'
#!/bin/sh
# 系统信息显示脚本

echo "═══════════════════════════════════════════════════"
echo "                系统信息报告"
echo "═══════════════════════════════════════════════════"

# 系统基本信息
echo "💻 系统信息:"
echo "  └── 主机名: $(cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown)"
echo "  └── 系统: $(cat /etc/openwrt_release 2>/dev/null | grep 'DISTRIB_DESCRIPTION' | cut -d'=' -f2 | tr -d \"')"
echo "  └── 内核: $(uname -r)"
echo "  └── 运行时间: $(uptime | awk -F'( |,|:)+' '{print $6,$7",",$8,"hours,",$9,"minutes"}')"

# 内存信息
echo ""
echo "💾 内存使用:"
free -m | awk '
NR==1{printf "  └── %s %s %s %s\n", $1, $2, $3, $4}
NR==2{printf "  └── Mem: %sMB %sMB %sMB %sMB\n", $2, $3, $4, $7}
NR==3{printf "  └── Swap: %sMB %sMB %sMB %sMB\n", $2, $3, $4, $7}'

# 存储信息
echo ""
echo "💽 存储空间:"
df -h | grep -E '^(/dev/|overlay)' | awk '{printf "  └── %s: %s/%s (%s used)\n", $6, $3, $2, $5}'

# 网络信息
echo ""
echo "🌐 网络接口:"
ip -o addr show scope global | awk '{gsub(/\/[0-9]+/, ""); printf "  └── %s: %s\n", $2, $4}'

# CPU信息
echo ""
echo "⚡ CPU信息:"
echo "  └── 架构: $(uname -m)"
echo "  └── 负载: $(cat /proc/loadavg | cut -d' ' -f1-3)"

echo "═══════════════════════════════════════════════════"
EOF
chmod +x files/usr/bin/system-info

# ==================== 7. 完成提示 ====================
echo "7. 创建完成提示..."

cat > files/etc/banner.diy2 << 'EOF'
╔════════════════════════╗
║           系统优化已启用                             ║
╠════════════════════════╣
║ 可用功能:                                                 ║
║ • overlay-backup  - 配置备份恢复       ║
║ • clean-memory    - 内存清理              ║
║ • system-info     - 系统信息                  ║
║ • 定时内存优化    - 每天凌晨3点            ║
╚════════════════════════╝
EOF

echo ""
echo "=========================================="
echo "系统优化和功能增强完成!"
echo "=========================================="
echo "✅ 内存优化配置"
echo "✅ Overlay备份系统"
echo "✅ 定时内存清理"
echo "✅ 系统信息工具"
echo "✅ 服务优化配置"
echo ""
echo "刷机后可用命令:"
echo "  overlay-backup backup    # 创建备份"
echo "  overlay-backup list      # 列出备份"
echo "  clean-memory            # 清理内存"
echo "  system-info             # 系统信息"
echo "=========================================="
