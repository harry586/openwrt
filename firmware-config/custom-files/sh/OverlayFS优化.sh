#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# OverlayFS文件系统优化脚本（添加使用说明）
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

echo "开始配置OverlayFS文件系统优化..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/config"
    mkdir -p "${prefix}/etc/init.d"
    mkdir -p "${prefix}/usr/sbin"
    mkdir -p "${prefix}/usr/lib/lua/luci/controller/admin"
    mkdir -p "${prefix}/usr/lib/lua/luci/view/admin_system"
}

create_dirs "$INSTALL_DIR"

# ==================== OverlayFS内核参数优化 ====================
create_overlayfs_optimization() {
    local prefix="$1"
    
    # 创建内核参数优化配置
    cat > "${prefix}/etc/sysctl.d/99-overlayfs-optimization.conf" << 'EOF'
# =============================================
# OverlayFS文件系统优化配置
# =============================================

# OverlayFS性能优化
fs.overlayfs.upperdir_relaxed=1           # 宽松的上层目录检查
fs.overlayfs.metacopy=1                   # 启用元数据拷贝
fs.overlayfs.redirect_dir=1               # 启用目录重定向
fs.overlayfs.redirect_always_follow=1     # 始终跟随重定向
fs.overlayfs.index=1                      # 启用索引功能
fs.overlayfs.nfs_export=1                 # 启用NFS导出支持
fs.overlayfs.xino=auto                    # 自动生成索引节点号
fs.overlayfs.override_creds=1             # 覆盖凭据检查

# 文件系统缓存优化
fs.file-max=65536                         # 最大打开文件数
fs.inode-max=262144                       # 最大inode数
fs.inode-state=100000                     # inode状态缓存
fs.dentry-state=100000                    # dentry状态缓存
fs.aio-max-nr=65536                       # 最大异步I/O请求数
fs.aio-nr=8192                            # 当前异步I/O请求数

# 文件系统挂载优化
fs.suid_dumpable=0                        # 禁用suid core dump
fs.protected_hardlinks=1                  # 保护硬链接
fs.protected_symlinks=1                   # 保护符号链接
fs.protected_fifos=2                      # 保护FIFO文件
fs.protected_regular=2                    # 保护常规文件

# VFS层优化
fs.lease-break-time=10                    # 租约中断时间（秒）
fs.dir-notify-enable=1                    # 启用目录通知
fs.overflowuid=65534                      # 溢出UID
fs.overflowgid=65534                      # 溢出GID
EOF

    # 创建fstab优化配置
    cat > "${prefix}/etc/fstab.overlay" << 'EOF'
# =============================================
# OverlayFS挂载优化配置
# =============================================

# /overlay 挂载点优化配置
# 格式: <设备> <挂载点> <文件系统> <选项> <dump> <pass>

# 主overlay挂载（最优化配置）
/dev/root /overlay overlay lowerdir=/,upperdir=/overlay/upper,workdir=/overlay/work 0 0

# 如果使用独立分区作为overlay
#/dev/sda1 /overlay ext4 rw,noatime,nodiratime,data=ordered,commit=60,errors=remount-ro 0 0

# 临时文件系统优化
tmpfs /tmp tmpfs rw,nosuid,nodev,noatime,size=128M,mode=1777 0 0
tmpfs /var/lock tmpfs rw,nosuid,nodev,noatime,size=16M,mode=1777 0 0
tmpfs /var/run tmpfs rw,nosuid,nodev,noatime,size=16M,mode=755 0 0
tmpfs /var/tmp tmpfs rw,nosuid,nodev,noatime,size=64M,mode=1777 0 0

# 日志目录使用tmpfs（减少写入）
tmpfs /var/log tmpfs rw,nosuid,nodev,noatime,size=32M,mode=755 0 0
EOF

    # 创建overlay清理脚本（添加使用说明）
    cat > "${prefix}/usr/sbin/overlay-cleanup" << 'EOF'
#!/bin/sh
# =============================================
# OverlayFS清理和优化脚本
# =============================================

LOG_FILE="/var/log/overlay-cleanup.log"
BACKUP_DIR="/tmp/overlay-backup"

# 显示使用说明
show_usage() {
    echo ""
    echo "=========================================="
    echo "OverlayFS优化工具 - 使用说明"
    echo "=========================================="
    echo ""
    echo "📖 什么是OverlayFS？"
    echo "  OverlayFS是OpenWrt的根文件系统，它将只读的基础系统"
    echo "  和可写的上层目录合并，所有修改都保存在上层目录中。"
    echo ""
    echo "🔧 常用功能："
    echo "  1. overlay-cleanup status    - 查看overlay使用情况"
    echo "  2. overlay-cleanup clean     - 清理临时文件"
    echo "  3. overlay-cleanup optimize  - 优化挂载参数"
    echo "  4. overlay-cleanup monitor   - 实时监控模式"
    echo "  5. overlay-cleanup all       - 执行所有优化"
    echo ""
    echo "💡 使用建议："
    echo "  - 定期运行 'overlay-cleanup clean' 清理临时文件"
    echo "  - 空间不足时运行 'overlay-cleanup compress' 压缩日志"
    echo "  - 系统变慢时运行 'overlay-cleanup optimize' 优化参数"
    echo "  - 安装大量软件后运行 'overlay-cleanup status' 查看空间"
    echo ""
    echo "⚠️  注意事项："
    echo "  - 'overlay-cleanup reset' 会删除所有自定义配置"
    echo "  - 操作前建议备份重要配置"
    echo "  - 监控模式按 Ctrl+C 退出"
    echo ""
    echo "📊 查看详细帮助： overlay-cleanup help"
    echo "=========================================="
}

# 显示详细帮助
show_help() {
    echo ""
    echo "=========================================="
    echo "OverlayFS优化工具 - 详细帮助"
    echo "=========================================="
    echo ""
    echo "📋 命令列表："
    echo "  clean     - 清理临时文件（日志、缓存等）"
    echo "  compress  - 压缩overlay数据（压缩大日志文件）"
    echo "  status    - 显示overlay使用情况（磁盘、inode等）"
    echo "  optimize  - 优化挂载参数和目录结构"
    echo "  fix       - 修复损坏的软链接"
    echo "  reset     - 重置overlay（危险！删除所有配置）"
    echo "  all       - 执行所有优化（clean+optimize+fix）"
    echo "  monitor   - 持续监控模式（5秒刷新）"
    echo "  help      - 显示此帮助信息"
    echo "  usage     - 显示使用说明"
    echo ""
    echo "📝 使用示例："
    echo "  1. 查看当前overlay状态："
    echo "     overlay-cleanup status"
    echo ""
    echo "  2. 清理临时文件并优化："
    echo "     overlay-cleanup all"
    echo ""
    echo "  3. 定期清理计划（添加到cron）："
    echo "     0 3 * * * overlay-cleanup clean"
    echo "     0 4 * * 0 overlay-cleanup optimize"
    echo ""
    echo "🔍 常见问题："
    echo "  Q: overlay空间满了怎么办？"
    echo "  A: 运行 'overlay-cleanup clean' 和 'overlay-cleanup compress'"
    echo ""
    echo "  Q: 系统变慢了怎么办？"
    echo "  A: 运行 'overlay-cleanup optimize' 优化挂载参数"
    echo ""
    echo "  Q: 如何查看哪些文件占用空间？"
    echo "  A: 运行 'du -sh /overlay/upper/* | sort -hr'"
    echo ""
    echo "  Q: 如何备份当前配置？"
    echo "  A: 运行 'tar -czf /tmp/overlay-backup.tar.gz /overlay/upper/etc'"
    echo ""
    echo "📞 更多信息："
    echo "  - OpenWrt Wiki: https://openwrt.org/docs/techref/overlay"
    echo "  - OverlayFS文档: https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html"
    echo "=========================================="
}

# 记录日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

# 清理overlay临时文件
clean_temporary_files() {
    log "开始清理overlay临时文件..."
    
    # 清理/tmp目录
    find /tmp -type f -atime +1 -delete 2>/dev/null || true
    find /tmp -type d -empty -mtime +7 -delete 2>/dev/null || true
    log "清理 /tmp 目录完成"
    
    # 清理overlay工作目录
    if [ -d "/overlay/work/work" ]; then
        find /overlay/work/work -type f -name "*.tmp" -delete 2>/dev/null || true
        find /overlay/work/work -type f -name "*.temp" -delete 2>/dev/null || true
        log "清理 overlay work 目录完成"
    fi
    
    # 清理软件包缓存
    if [ -d "/overlay/upper/var/opkg-lists" ]; then
        rm -rf /overlay/upper/var/opkg-lists/* 2>/dev/null || true
        log "清理 opkg 缓存完成"
    fi
    
    # 清理日志文件（保留最近3天）
    find /var/log -name "*.log" -mtime +3 -delete 2>/dev/null || true
    log "清理日志文件完成"
}

# 优化overlay目录结构
optimize_overlay_structure() {
    log "开始优化overlay目录结构..."
    
    # 确保必要的目录存在
    mkdir -p /overlay/upper 2>/dev/null || true
    mkdir -p /overlay/work 2>/dev/null || true
    
    # 创建优化的目录结构
    for dir in etc var usr lib; do
        if [ ! -d "/overlay/upper/$dir" ]; then
            mkdir -p "/overlay/upper/$dir"
            log "创建目录: /overlay/upper/$dir"
        fi
    done
    
    # 设置正确的权限
    chmod 755 /overlay/upper 2>/dev/null || true
    chmod 755 /overlay/work 2>/dev/null || true
    
    # 检查并修复软链接
    fix_broken_links
    
    log "overlay目录结构优化完成"
}

# 修复损坏的软链接
fix_broken_links() {
    log "检查并修复损坏的软链接..."
    
    local broken_count=0
    local fixed_count=0
    
    # 在overlay上层查找损坏的链接
    find /overlay/upper -type l 2>/dev/null | while read -r link; do
        if [ ! -e "$link" ]; then
            target=$(readlink "$link")
            broken_count=$((broken_count + 1))
            
            # 尝试修复常见的链接
            case "$target" in
                /tmp/*|/var/run/*|/var/lock/*)
                    # 临时文件链接，可以删除
                    rm -f "$link"
                    log "删除损坏的临时链接: $link -> $target"
                    fixed_count=$((fixed_count + 1))
                    ;;
                *)
                    # 其他链接，记录但不处理
                    log "发现损坏链接: $link -> $target"
                    ;;
            esac
        fi
    done
    
    log "检查完成: 发现 $broken_count 个损坏链接，修复 $fixed_count 个"
}

# 压缩overlay数据
compress_overlay_data() {
    log "开始压缩overlay数据..."
    
    # 备份重要配置
    mkdir -p "$BACKUP_DIR"
    log "创建备份目录: $BACKUP_DIR"
    
    # 备份网络配置
    if [ -f "/etc/config/network" ]; then
        cp /etc/config/network "$BACKUP_DIR/network.bak"
        log "备份网络配置"
    fi
    
    # 备份无线配置
    if [ -f "/etc/config/wireless" ]; then
        cp /etc/config/wireless "$BACKUP_DIR/wireless.bak"
        log "备份无线配置"
    fi
    
    # 备份防火墙配置
    if [ -f "/etc/config/firewall" ]; then
        cp /etc/config/firewall "$BACKUP_DIR/firewall.bak"
        log "备份防火墙配置"
    fi
    
    # 查找可以压缩的大文件
    log "查找可以压缩的文件..."
    find /overlay/upper -type f -size +1M -name "*.log" -o -name "*.cache" 2>/dev/null | while read -r file; do
        if [ -f "$file" ]; then
            gzip -f "$file" 2>/dev/null && log "压缩文件: $file"
        fi
    done
    
    log "overlay数据压缩完成"
}

# 检查overlay使用情况
check_overlay_usage() {
    echo ""
    echo "========================================"
    echo "OverlayFS使用情况报告"
    echo "========================================"
    
    # 检查挂载点
    echo "📌 挂载状态:"
    mount | grep -E "(overlay|/overlay)" || echo "未找到overlay挂载"
    echo ""
    
    # 检查磁盘使用
    echo "💾 磁盘使用情况:"
    df -h /overlay 2>/dev/null || echo "无法获取/overlay使用情况"
    echo ""
    
    # 检查上层目录大小
    echo "📁 上层目录大小:"
    if [ -d "/overlay/upper" ]; then
        du -sh /overlay/upper 2>/dev/null
        echo "前10个大目录:"
        du -sh /overlay/upper/* 2>/dev/null | sort -hr | head -10
    else
        echo "上层目录不存在"
    fi
    echo ""
    
    # 检查inode使用
    echo "🔢 Inode使用情况:"
    df -i /overlay 2>/dev/null || echo "无法获取inode信息"
    echo ""
    
    # 检查文件数量
    echo "📊 文件数量统计:"
    if [ -d "/overlay/upper" ]; then
        find /overlay/upper -type f | wc -l | awk '{print "文件数: "$1}'
        find /overlay/upper -type d | wc -l | awk '{print "目录数: "$1}'
        find /overlay/upper -type l | wc -l | awk '{print "链接数: "$1}'
    fi
    echo ""
    
    # 使用建议
    echo "💡 使用建议:"
    local usage=$(df /overlay 2>/dev/null | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ -n "$usage" ]; then
        if [ "$usage" -gt 90 ]; then
            echo "  ⚠️  空间严重不足 (${usage}%)，建议:"
            echo "    1. 运行: overlay-cleanup clean"
            echo "    2. 运行: overlay-cleanup compress"
            echo "    3. 删除不需要的软件包"
        elif [ "$usage" -gt 70 ]; then
            echo "  ⚠️  空间紧张 (${usage}%)，建议:"
            echo "    1. 运行: overlay-cleanup clean"
            echo "    2. 考虑清理日志文件"
        else
            echo "  ✅ 空间充足 (${usage}%)"
        fi
    fi
    echo "========================================"
}

# 重置overlay（危险操作）
reset_overlay() {
    echo ""
    echo "========================================"
    echo "⚠️  OverlayFS重置工具"
    echo "========================================"
    echo ""
    echo "警告：此操作将重置overlay，所有自定义配置和安装的软件将丢失！"
    echo ""
    echo "影响范围："
    echo "  ✗ 所有安装的软件包"
    echo "  ✗ 自定义配置文件"
    echo "  ✗ 系统设置"
    echo "  ✗ 用户数据"
    echo ""
    echo "保留内容："
    echo "  ✓ 网络配置（如果已备份）"
    echo "  ✓ 无线配置（如果已备份）"
    echo "  ✓ 防火墙配置（如果已备份）"
    echo ""
    echo "操作步骤："
    echo "  1. 备份当前配置"
    echo "  2. 卸载overlay"
    echo "  3. 清理overlay目录"
    echo "  4. 重新挂载"
    echo "  5. 恢复配置"
    echo ""
    read -p "确定要重置overlay吗？(输入'RESET'确认): " confirm
    
    if [ "$confirm" = "RESET" ]; then
        echo "正在重置overlay..."
        
        # 备份重要配置
        mkdir -p /tmp/overlay-reset-backup
        cp -r /etc/config /tmp/overlay-reset-backup/ 2>/dev/null || true
        
        # 卸载overlay
        umount /overlay 2>/dev/null || true
        
        # 清理overlay目录
        rm -rf /overlay/upper/* 2>/dev/null || true
        rm -rf /overlay/work/* 2>/dev/null || true
        
        # 重新挂载
        mount -t overlay overlay -o lowerdir=/,upperdir=/overlay/upper,workdir=/overlay/work /overlay
        
        # 恢复配置
        cp -r /tmp/overlay-reset-backup/config/* /etc/config/ 2>/dev/null || true
        
        echo ""
        echo "✅ overlay重置完成"
        echo ""
        echo "下一步操作："
        echo "  1. 重启系统: reboot"
        echo "  2. 重新安装需要的软件包"
        echo "  3. 恢复其他配置"
    else
        echo "操作已取消"
    fi
}

# 优化overlay挂载参数
optimize_mount_options() {
    log "优化overlay挂载参数..."
    
    # 重新挂载使用优化参数
    if mount | grep -q "on /overlay type overlay"; then
        # 获取当前挂载参数
        current_opts=$(mount | grep "on /overlay type overlay" | sed 's/.*(\(.*\)).*/\1/')
        
        # 添加优化参数
        new_opts="$current_opts,noatime,nodiratime,metacopy=on,redirect_dir=on"
        
        # 尝试重新挂载
        mount -o remount,$new_opts /overlay 2>/dev/null && {
            log "overlay重新挂载成功，新参数: $new_opts"
            return 0
        }
        
        log "重新挂载失败，保持原参数"
    else
        log "overlay未挂载或不是overlay类型"
    fi
    
    return 1
}

# 主函数
case "$1" in
    clean)
        clean_temporary_files
        optimize_overlay_structure
        ;;
    compress)
        compress_overlay_data
        ;;
    status)
        check_overlay_usage
        ;;
    optimize)
        optimize_mount_options
        optimize_overlay_structure
        ;;
    fix)
        fix_broken_links
        ;;
    reset)
        reset_overlay
        ;;
    all)
        clean_temporary_files
        optimize_overlay_structure
        fix_broken_links
        optimize_mount_options
        check_overlay_usage
        ;;
    monitor)
        # 监控模式
        echo ""
        echo "========================================"
        echo "OverlayFS实时监控模式"
        echo "========================================"
        echo "按 Ctrl+C 退出监控"
        echo ""
        while true; do
            clear
            check_overlay_usage
            echo ""
            echo "监控中... 5秒后刷新"
            sleep 5
        done
        ;;
    help)
        show_help
        ;;
    usage)
        show_usage
        ;;
    *)
        echo ""
        echo "========================================"
        echo "OverlayFS优化工具"
        echo "========================================"
        echo ""
        echo "基本用法: overlay-cleanup [命令]"
        echo ""
        echo "命令列表:"
        echo "  clean     - 清理临时文件"
        echo "  compress  - 压缩overlay数据"
        echo "  status    - 显示使用情况"
        echo "  optimize  - 优化挂载参数和结构"
        echo "  fix       - 修复损坏链接"
        echo "  reset     - 重置overlay（危险）"
        echo "  all       - 执行所有优化"
        echo "  monitor   - 持续监控模式"
        echo "  help      - 显示详细帮助"
        echo "  usage     - 显示使用说明"
        echo ""
        echo "示例:"
        echo "  overlay-cleanup status    # 查看状态"
        echo "  overlay-cleanup all       # 执行所有优化"
        echo "  overlay-cleanup monitor   # 实时监控"
        echo ""
        echo "获取详细帮助: overlay-cleanup help"
        echo "========================================"
        exit 1
        ;;
esac
EOF
    chmod +x "${prefix}/usr/sbin/overlay-cleanup"
}

# ==================== 创建OverlayFS监控服务 ====================
create_overlayfs_service() {
    local prefix="$1"
    cat > "${prefix}/etc/init.d/overlayfs-optimize" << 'EOF'
#!/bin/sh /etc/rc.common

START=98
USE_PROCD=1

start_service() {
    echo "启动OverlayFS优化服务..."
    
    # 等待系统基本就绪
    sleep 5
    
    # 应用内核参数
    if [ -f "/etc/sysctl.d/99-overlayfs-optimization.conf" ]; then
        sysctl -p /etc/sysctl.d/99-overlayfs-optimization.conf >/dev/null 2>&1 || true
        echo "应用OverlayFS内核优化参数"
    fi
    
    # 优化挂载参数
    /usr/sbin/overlay-cleanup optimize >/dev/null 2>&1 || true
    
    # 启动定期清理任务
    setup_cron_jobs
    
    # 记录启动日志
    logger -t overlayfs "OverlayFS优化服务启动完成"
}

stop_service() {
    echo "停止OverlayFS优化服务..."
    
    # 移除计划任务
    remove_cron_jobs
    
    logger -t overlayfs "OverlayFS优化服务停止"
}

setup_cron_jobs() {
    # 添加定期清理任务
    if ! grep -q "overlay-cleanup" /etc/crontabs/root 2>/dev/null; then
        echo "# OverlayFS优化任务" >> /etc/crontabs/root
        echo "0 2 * * * /usr/sbin/overlay-cleanup clean >/dev/null 2>&1" >> /etc/crontabs/root
        echo "0 4 * * 0 /usr/sbin/overlay-cleanup compress >/dev/null 2>&1" >> /etc/crontabs/root
        echo "*/30 * * * * /usr/sbin/overlay-cleanup status >/dev/null 2>&1" >> /etc/crontabs/root
        /etc/init.d/cron restart 2>/dev/null || true
        echo "OverlayFS计划任务已配置"
    fi
}

remove_cron_jobs() {
    # 移除计划任务
    sed -i '/overlay-cleanup/d' /etc/crontabs/root 2>/dev/null || true
    /etc/init.d/cron restart 2>/dev/null || true
}

restart() {
    stop
    sleep 2
    start
}
EOF
    chmod +x "${prefix}/etc/init.d/overlayfs-optimize"
}

# ==================== 创建Web界面 ====================
create_overlayfs_web_interface() {
    local prefix="$1"
    
    # LuCI控制器
    cat > "${prefix}/usr/lib/lua/luci/controller/admin/overlayfs-optimize.lua" << 'EOF'
module("luci.controller.admin.overlayfs-optimize", package.seeall)

function index()
    entry({"admin", "system", "overlayfs-optimize"}, template("admin_system/overlayfs_optimize"), _("OverlayFS优化"), 77)
    entry({"admin", "system", "overlayfs-optimize", "status"}, call("get_status")).leaf = true
    entry({"admin", "system", "overlayfs-optimize", "clean"}, call("clean_overlay")).leaf = true
    entry({"admin", "system", "overlayfs-optimize", "optimize"}, call("optimize_overlay")).leaf = true
    entry({"admin", "system", "overlayfs-optimize", "compress"}, call("compress_overlay")).leaf = true
    entry({"admin", "system", "overlayfs-optimize", "fix"}, call("fix_links")).leaf = true
end

function get_status()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/overlay-cleanup status 2>&1")
    
    http.prepare_content("text/plain")
    http.write(result)
end

function clean_overlay()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/overlay-cleanup clean 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "OverlayFS清理完成"})
end

function optimize_overlay()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/overlay-cleanup optimize 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "OverlayFS优化完成"})
end

function compress_overlay()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/overlay-cleanup compress 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "OverlayFS压缩完成"})
end

function fix_links()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/overlay-cleanup fix 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "损坏链接修复完成"})
end
EOF

    # Web界面（添加使用说明）
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/overlayfs_optimize.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:OverlayFS文件系统优化%></h2>
    
    <!-- 使用说明卡片 -->
    <div class="alert-message" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">📚 OverlayFS优化 - 使用说明</h4>
        <p style="margin-bottom: 10px;"><b>什么是OverlayFS？</b> 它是OpenWrt的根文件系统，将只读的基础系统和可写的上层目录合并。</p>
        
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; margin: 10px 0;">
            <div style="background: white; padding: 10px; border-radius: 4px; border-left: 4px solid #4CAF50;">
                <div style="font-weight: 600; color: #2c3e50;">💾 空间管理</div>
                <div style="font-size: 12px; color: #7f8c8d;">清理临时文件，释放存储空间</div>
            </div>
            <div style="background: white; padding: 10px; border-radius: 4px; border-left: 4px solid #2196F3;">
                <div style="font-weight: 600; color: #2c3e50;">⚡ 性能优化</div>
                <div style="font-size: 12px; color: #7f8c8d;">优化挂载参数，提升文件操作速度</div>
            </div>
            <div style="background: white; padding: 10px; border-radius: 4px; border-left: 4px solid #FF9800;">
                <div style="font-weight: 600; color: #2c3e50;">🔧 系统维护</div>
                <div style="font-size: 12px; color: #7f8c8d;">修复损坏链接，监控使用情况</div>
            </div>
        </div>
        
        <p style="margin: 10px 0 5px 0; font-weight: 600;">💡 使用建议：</p>
        <ol style="margin: 0 0 10px 0; padding-left: 20px; font-size: 13px;">
            <li>定期点击"立即清理"按钮</li>
            <li>空间不足时使用"压缩数据"</li>
            <li>系统变慢时使用"优化配置"</li>
            <li>随时查看"状态"了解使用情况</li>
        </ol>
    </div>
    
    <!-- 状态显示 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:OverlayFS状态%></h3>
        <div id="overlay-status" style="min-height: 300px; padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed; font-family: monospace; font-size: 12px; max-height: 400px; overflow-y: auto;">
            <div style="text-align: center; padding: 40px;">
                <div class="spinner"></div>
                <p>正在加载OverlayFS状态...</p>
            </div>
        </div>
        <div style="margin-top: 15px; display: flex; gap: 12px;">
            <button id="refresh-status" class="btn-primary" style="padding: 10px 20px;">
                <i class="icon icon-refresh"></i> 刷新状态
            </button>
            <button id="clean-now" class="btn-secondary" style="padding: 10px 20px;">
                <i class="icon icon-trash"></i> 立即清理
            </button>
            <button id="show-help" class="btn-neutral" style="padding: 10px 20px;">
                <i class="icon icon-question-circle"></i> 使用帮助
            </button>
        </div>
    </div>
    
    <!-- 优化操作 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:优化操作%></h3>
        
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 20px;">
            <div style="background: white; padding: 15px; border-radius: 8px; text-align: center; border: 1px solid #e1e8ed;">
                <div style="font-size: 24px; color: #28a745; margin-bottom: 8px;">🗑️</div>
                <div style="font-weight: 600; margin-bottom: 5px;">清理临时文件</div>
                <div style="font-size: 12px; color: #7f8c8d; margin-bottom: 10px;">释放存储空间</div>
                <button class="btn-sm btn-success" onclick="performAction('clean')" style="width: 100%;">执行清理</button>
            </div>
            
            <div style="background: white; padding: 15px; border-radius: 8px; text-align: center; border: 1px solid #e1e8ed;">
                <div style="font-size: 24px; color: #2196F3; margin-bottom: 8px;">⚡</div>
                <div style="font-weight: 600; margin-bottom: 5px;">优化配置</div>
                <div style="font-size: 12px; color: #7f8c8d; margin-bottom: 10px;">提升系统性能</div>
                <button class="btn-sm btn-primary" onclick="performAction('optimize')" style="width: 100%;">执行优化</button>
            </div>
            
            <div style="background: white; padding: 15px; border-radius: 8px; text-align: center; border: 1px solid #e1e8ed;">
                <div style="font-size: 24px; color: #FF9800; margin-bottom: 8px;">🗜️</div>
                <div style="font-weight: 600; margin-bottom: 5px;">压缩数据</div>
                <div style="font-size: 12px; color: #7f8c8d; margin-bottom: 10px;">压缩大日志文件</div>
                <button class="btn-sm btn-warning" onclick="performAction('compress')" style="width: 100%;">执行压缩</button>
            </div>
            
            <div style="background: white; padding: 15px; border-radius: 8px; text-align: center; border: 1px solid #e1e8ed;">
                <div style="font-size: 24px; color: #17a2b8; margin-bottom: 8px;">🔗</div>
                <div style="font-weight: 600; margin-bottom: 5px;">修复链接</div>
                <div style="font-size: 12px; color: #7f8c8d; margin-bottom: 10px;">修复损坏的链接</div>
                <button class="btn-sm btn-info" onclick="performAction('fix')" style="width: 100%;">执行修复</button>
            </div>
        </div>
        
        <!-- 一键优化 -->
        <div style="text-align: center; margin-top: 20px;">
            <button id="all-in-one" class="btn-success" style="padding: 12px 30px; font-size: 16px;">
                <i class="icon icon-magic"></i> 一键全面优化
            </button>
            <p style="margin-top: 10px; color: #7f8c8d; font-size: 12px;">
                执行所有优化操作：清理 + 优化 + 修复
            </p>
        </div>
    </div>
    
    <!-- 高级选项 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:高级选项%></h3>
        
        <div class="cbi-value" style="margin-bottom: 15px;">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:监控模式%></label>
            <div class="cbi-value-field">
                <button id="monitor-mode" class="btn-info" style="padding: 10px 20px;">
                    <i class="icon icon-desktop"></i> 启动监控模式
                </button>
                <p style="margin-top: 5px; color: #7f8c8d; font-size: 12px;">
                    实时监控overlay使用情况，5秒刷新一次
                </p>
            </div>
        </div>
        
        <div class="cbi-value" style="margin-bottom: 15px;">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:危险操作%></label>
            <div class="cbi-value-field">
                <button id="reset-overlay" class="btn-danger" style="padding: 10px 20px;">
                    <i class="icon icon-warning"></i> 重置Overlay
                </button>
                <p style="margin-top: 5px; color: #e74c3c; font-size: 12px;">
                    ⚠️ 危险！将删除所有自定义配置和安装的软件
                </p>
            </div>
        </div>
        
        <!-- 命令行参考 -->
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:命令行参考%></label>
            <div class="cbi-value-field">
                <div style="background: #2c3e50; color: white; padding: 12px; border-radius: 6px; font-family: monospace; font-size: 13px;">
                    <p style="margin: 5px 0; color: #95a5a6;"># 查看状态</p>
                    <code style="display: block; background: #34495e; padding: 8px; border-radius: 4px; margin: 5px 0 15px 0;">
                        overlay-cleanup status
                    </code>
                    
                    <p style="margin: 5px 0; color: #95a5a6;"># 一键优化</p>
                    <code style="display: block; background: #34495e; padding: 8px; border-radius: 4px; margin: 5px 0 15px 0;">
                        overlay-cleanup all
                    </code>
                    
                    <p style="margin: 5px 0; color: #95a5a6;"># 获取帮助</p>
                    <code style="display: block; background: #34495e; padding: 8px; border-radius: 4px; margin: 5px 0 0 0;">
                        overlay-cleanup help
                    </code>
                </div>
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

// 加载Overlay状态
function loadOverlayStatus() {
    var statusDiv = document.getElementById('overlay-status');
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/status")%>', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                // 简单格式化显示
                statusDiv.innerHTML = '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; font-size: 12px; line-height: 1.4;">' + xhr.responseText + '</pre>';
            } else {
                statusDiv.innerHTML = '<div style="color: #e74c3c; padding: 20px; text-align: center;">加载状态失败</div>';
            }
        }
    };
    xhr.send();
}

// 执行操作
function performAction(action) {
    var actionNames = {
        'clean': '清理临时文件',
        'optimize': '优化配置',
        'compress': '压缩数据',
        'fix': '修复链接'
    };
    
    var confirmMessages = {
        'clean': '确定要清理OverlayFS临时文件吗？\n这将释放存储空间。',
        'optimize': '确定要优化OverlayFS配置吗？\n这将提升系统性能。',
        'compress': '确定要压缩OverlayFS数据吗？\n这可能需要一些时间。',
        'fix': '确定要检查并修复损坏的链接吗？'
    };
    
    if (confirm(confirmMessages[action])) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/")%>' + action, true);
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        showStatus('✅ ' + actionNames[action] + ' 完成', 'success');
                        setTimeout(loadOverlayStatus, 2000);
                    }
                } catch (e) {
                    showStatus('操作失败: ' + e.message, 'error');
                }
            }
        };
        xhr.send();
    }
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    loadOverlayStatus();
    
    // 刷新状态按钮
    document.getElementById('refresh-status').addEventListener('click', function() {
        loadOverlayStatus();
        showStatus('状态已刷新', 'info');
    });
    
    // 立即清理按钮
    document.getElementById('clean-now').addEventListener('click', function() {
        performAction('clean');
    });
    
    // 使用帮助按钮
    document.getElementById('show-help').addEventListener('click', function() {
        showStatus('📚 使用帮助：<br>1. 定期清理临时文件<br>2. 空间不足时压缩数据<br>3. 系统变慢时优化配置<br>4. 随时查看状态了解使用情况', 'info');
    });
    
    // 一键全面优化按钮
    document.getElementById('all-in-one').addEventListener('click', function() {
        if (confirm('执行全面优化操作，包括：\n1. 清理临时文件\n2. 优化配置\n3. 修复损坏链接\n\n确定继续吗？')) {
            showStatus('正在执行全面优化，请稍候...', 'info');
            
            // 顺序执行所有优化
            var steps = ['clean', 'optimize', 'fix'];
            var currentStep = 0;
            
            function executeNextStep() {
                if (currentStep >= steps.length) {
                    showStatus('✅ 全面优化完成', 'success');
                    loadOverlayStatus();
                    return;
                }
                
                var step = steps[currentStep];
                var xhr = new XMLHttpRequest();
                xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/")%>' + step, true);
                xhr.onreadystatechange = function() {
                    if (xhr.readyState === 4 && xhr.status === 200) {
                        currentStep++;
                        setTimeout(executeNextStep, 1000);
                    }
                };
                xhr.send();
            }
            
            executeNextStep();
        }
    });
    
    // 监控模式按钮
    document.getElementById('monitor-mode').addEventListener('click', function() {
        showStatus('监控模式需要在终端执行: overlay-cleanup monitor<br>按 Ctrl+C 退出监控', 'info');
    });
    
    // 重置Overlay按钮（危险操作）
    document.getElementById('reset-overlay').addEventListener('click', function() {
        var confirmText = prompt('⚠️  危险操作！这将删除所有自定义配置和安装的软件。\n请输入"RESET"确认：');
        
        if (confirmText === 'RESET') {
            showStatus('重置操作需要在终端执行，请使用命令: overlay-cleanup reset', 'warning');
        } else {
            showStatus('操作已取消', 'info');
        }
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

.btn-primary, .btn-secondary, .btn-success, .btn-warning, .btn-info, .btn-neutral, .btn-danger {
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

.btn-danger {
    background: #dc3545;
    color: white;
}

.btn-sm {
    padding: 6px 12px;
    font-size: 12px;
}

.btn-primary:hover, .btn-secondary:hover, .btn-success:hover, .btn-warning:hover, .btn-info:hover, .btn-neutral:hover, .btn-danger:hover {
    opacity: 0.9;
    transform: translateY(-1px);
}
`;
document.head.appendChild(style);
</script>
<%+footer%>
EOF
}

# ==================== 执行安装 ====================
create_overlayfs_optimization "$INSTALL_DIR"
create_overlayfs_service "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 创建Web界面
    create_overlayfs_web_interface "$INSTALL_DIR"
    
    # 启用OverlayFS优化服务
    /etc/init.d/overlayfs-optimize enable 2>/dev/null || true
    /etc/init.d/overlayfs-optimize start 2>/dev/null || true
    
    # 应用内核参数
    if [ -f "/etc/sysctl.d/99-overlayfs-optimization.conf" ]; then
        sysctl -p /etc/sysctl.d/99-overlayfs-optimization.conf 2>/dev/null || true
    fi
    
    # 优化fstab配置（追加方式）
    if [ -f "/etc/fstab" ] && [ -f "/etc/fstab.overlay" ]; then
        # 备份原配置
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
        # 检查是否已存在overlay配置
        if ! grep -q "overlay.*/overlay" /etc/fstab; then
            # 追加配置
            cat /etc/fstab.overlay >> /etc/fstab
            echo "fstab优化配置已追加"
        else
            echo "fstab中已存在overlay配置，跳过"
        fi
    fi
    
    # 重启LuCI使新页面生效
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
    
    # 创建计划任务
    if ! grep -q "overlay-cleanup" /etc/crontabs/root 2>/dev/null; then
        echo "# OverlayFS优化任务" >> /etc/crontabs/root
        echo "0 3 * * * /usr/sbin/overlay-cleanup clean >/dev/null 2>&1" >> /etc/crontabs/root
        echo "30 3 * * 0 /usr/sbin/overlay-cleanup optimize >/dev/null 2>&1" >> /etc/crontabs/root
        /etc/init.d/cron restart 2>/dev/null || true
    fi
    
    echo ""
    echo "========================================"
    echo "✓ OverlayFS文件系统优化已安装"
    echo "========================================"
    echo ""
    echo "📖 使用说明："
    echo "  1. 查看状态：overlay-cleanup status"
    echo "  2. 清理文件：overlay-cleanup clean"
    echo "  3. 优化配置：overlay-cleanup optimize"
    echo "  4. 实时监控：overlay-cleanup monitor"
    echo "  5. 获取帮助：overlay-cleanup help"
    echo ""
    echo "🌐 Web界面："
    echo "  LuCI → 系统 → OverlayFS优化"
    echo ""
    echo "⏰ 计划任务："
    echo "  已设置：每天3点自动清理临时文件"
    echo "          每周日3:30自动优化配置"
    echo ""
    echo "💡 建议："
    echo "  首次使用建议运行：overlay-cleanup all"
    echo "========================================"
else
    create_overlayfs_web_interface "$INSTALL_DIR"
    echo "✓ OverlayFS文件系统优化已集成到固件"
fi

echo "OverlayFS文件系统优化配置完成！"
