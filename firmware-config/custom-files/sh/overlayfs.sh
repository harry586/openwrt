#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# OverlayFS文件系统优化脚本（简化版）
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

    # 创建overlay清理脚本（简化版）
    cat > "${prefix}/usr/sbin/overlay-cleanup" << 'EOF'
#!/bin/sh
# =============================================
# OverlayFS清理和优化脚本（简化版）
# =============================================

LOG_FILE="/var/log/overlay-cleanup.log"

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
    echo "  4. overlay-cleanup all       - 执行所有优化"
    echo "  5. overlay-cleanup schedule  - 配置定时任务"
    echo ""
    echo "💡 使用建议："
    echo "  - 定期运行 'overlay-cleanup clean' 清理临时文件"
    echo "  - 空间不足时运行 'overlay-cleanup all' 全面优化"
    echo "  - 使用 'overlay-cleanup schedule' 配置自动清理"
    echo ""
    echo "📊 查看状态： overlay-cleanup status"
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
            echo "  ⚠️  空间严重不足 (${usage}%)，建议立即清理"
        elif [ "$usage" -gt 70 ]; then
            echo "  ⚠️  空间紧张 (${usage}%)，建议清理"
        else
            echo "  ✅ 空间充足 (${usage}%)"
        fi
    fi
    echo "========================================"
}

# 配置定时任务
configure_schedule() {
    local hour="$1"
    local minute="$2"
    local frequency="$3"
    
    log "配置定时任务..."
    
    # 清理现有overlay-cleanup计划任务
    sed -i '/overlay-cleanup/d' /etc/crontabs/root 2>/dev/null || true
    
    case "$frequency" in
        daily)
            # 每天执行
            echo "$minute $hour * * * /usr/sbin/overlay-cleanup all >/dev/null 2>&1" >> /etc/crontabs/root
            log "已设置每天 $hour:$minute 执行全面优化"
            ;;
        weekly)
            # 每周执行（周日）
            echo "$minute $hour * * 0 /usr/sbin/overlay-cleanup all >/dev/null 2>&1" >> /etc/crontabs/root
            log "已设置每周日 $hour:$minute 执行全面优化"
            ;;
        monthly)
            # 每月1号执行
            echo "$minute $hour 1 * * /usr/sbin/overlay-cleanup all >/dev/null 2>&1" >> /etc/crontabs/root
            log "已设置每月1号 $hour:$minute 执行全面优化"
            ;;
        *)
            # 自定义cron表达式
            echo "$frequency /usr/sbin/overlay-cleanup all >/dev/null 2>&1" >> /etc/crontabs/root
            log "已设置自定义计划: $frequency"
            ;;
    esac
    
    # 重启cron服务
    /etc/init.d/cron restart 2>/dev/null || true
    log "定时任务配置完成"
}

# 查看当前定时任务
show_schedule() {
    echo ""
    echo "========================================"
    echo "当前定时任务配置"
    echo "========================================"
    echo ""
    
    if grep -q "overlay-cleanup" /etc/crontabs/root 2>/dev/null; then
        grep "overlay-cleanup" /etc/crontabs/root
    else
        echo "未配置定时任务"
    fi
    
    echo ""
    echo "💡 配置示例："
    echo "  overlay-cleanup schedule 3 0 daily     # 每天3:00执行"
    echo "  overlay-cleanup schedule 4 30 weekly   # 每周日4:30执行"
    echo "  overlay-cleanup schedule 5 0 monthly   # 每月1号5:00执行"
    echo "========================================"
}

# 主函数
case "$1" in
    clean)
        clean_temporary_files
        optimize_overlay_structure
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
    all)
        log "开始执行全面优化..."
        clean_temporary_files
        optimize_overlay_structure
        fix_broken_links
        optimize_mount_options
        check_overlay_usage
        log "全面优化完成"
        echo "✅ OverlayFS全面优化完成"
        ;;
    schedule)
        if [ -n "$2" ] && [ -n "$3" ] && [ -n "$4" ]; then
            configure_schedule "$2" "$3" "$4"
        else
            show_schedule
        fi
        ;;
    help|usage)
        show_usage
        ;;
    *)
        echo ""
        echo "========================================"
        echo "OverlayFS优化工具（简化版）"
        echo "========================================"
        echo ""
        echo "基本用法: overlay-cleanup [命令]"
        echo ""
        echo "命令列表:"
        echo "  clean     - 清理临时文件"
        echo "  status    - 查看使用情况"
        echo "  optimize  - 优化挂载参数"
        echo "  fix       - 修复损坏链接"
        echo "  all       - 执行全面优化"
        echo "  schedule  - 配置定时任务"
        echo "  help      - 显示使用说明"
        echo ""
        echo "定时任务配置:"
        echo "  overlay-cleanup schedule <时> <分> <频率>"
        echo "  频率可选: daily, weekly, monthly"
        echo ""
        echo "示例:"
        echo "  overlay-cleanup status    # 查看状态"
        echo "  overlay-cleanup all       # 全面优化"
        echo "  overlay-cleanup schedule 3 0 daily  # 每天3点执行"
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
    
    # 设置默认定时任务（如果未设置）
    if ! grep -q "overlay-cleanup" /etc/crontabs/root 2>/dev/null; then
        # 每天凌晨3点执行清理
        echo "0 3 * * * /usr/sbin/overlay-cleanup clean >/dev/null 2>&1" >> /etc/crontabs/root
        # 每周日凌晨4点执行全面优化
        echo "0 4 * * 0 /usr/sbin/overlay-cleanup all >/dev/null 2>&1" >> /etc/crontabs/root
        /etc/init.d/cron restart 2>/dev/null || true
        echo "已设置默认定时任务"
    fi
    
    # 记录启动日志
    logger -t overlayfs "OverlayFS优化服务启动完成"
}

stop_service() {
    echo "停止OverlayFS优化服务..."
    logger -t overlayfs "OverlayFS优化服务停止"
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
    entry({"admin", "system", "overlayfs-optimize", "all"}, call("optimize_all")).leaf = true
    entry({"admin", "system", "overlayfs-optimize", "schedule"}, call("set_schedule")).leaf = true
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

function optimize_all()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local result = sys.exec("/usr/sbin/overlay-cleanup all 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({success = true, message = "OverlayFS全面优化完成"})
end

function set_schedule()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local hour = luci.http.formvalue("hour")
    local minute = luci.http.formvalue("minute")
    local frequency = luci.http.formvalue("frequency")
    
    if hour and minute and frequency then
        local result = sys.exec("/usr/sbin/overlay-cleanup schedule " .. hour .. " " .. minute .. " " .. frequency .. " 2>&1")
        
        http.prepare_content("application/json")
        http.write_json({success = true, message = "定时任务设置完成: " .. hour .. ":" .. minute .. " " .. frequency})
    else
        http.prepare_content("application/json")
        http.write_json({success = false, message = "参数错误"})
    end
end
EOF

    # Web界面（简化版）
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/overlayfs_optimize.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:OverlayFS文件系统优化%></h2>
    
    <!-- 使用说明卡片 -->
    <div class="alert-message" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">📚 OverlayFS优化</h4>
        <p style="margin-bottom: 10px;"><b>什么是OverlayFS？</b> 它是OpenWrt的根文件系统，将只读的基础系统和可写的上层目录合并。</p>
        
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; margin: 10px 0;">
            <div style="background: white; padding: 10px; border-radius: 4px; border-left: 4px solid #4CAF50;">
                <div style="font-weight: 600; color: #2c3e50;">💾 空间管理</div>
                <div style="font-size: 12px; color: #7f8c8d;">清理临时文件，释放存储空间</div>
            </div>
            <div style="background: white; padding: 10px; border-radius: 4px; border-left: 4px solid #2196F3;">
                <div style="font-weight: 600; color: #2c3e50;">⚡ 性能优化</div>
                <div style="font-size: 12px; color: #7f8c8d;">优化挂载参数，提升系统性能</div>
            </div>
            <div style="background: white; padding: 10px; border-radius: 4px; border-left: 4px solid #FF9800;">
                <div style="font-weight: 600; color: #2c3e50;">🕐 定时任务</div>
                <div style="font-size: 12px; color: #7f8c8d;">自动清理优化，省心省力</div>
            </div>
        </div>
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
    
    <!-- 定时任务配置 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px; margin-bottom: 20px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:定时任务配置%></h3>
        
        <div class="cbi-value" style="margin-bottom: 15px;">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e; width: 120px;"><%:执行时间%></label>
            <div class="cbi-value-field" style="display: flex; gap: 10px; align-items: center;">
                <input type="number" id="schedule-hour" min="0" max="23" value="3" style="width: 80px; padding: 8px; border: 1px solid #ddd; border-radius: 4px;">
                <span>:</span>
                <input type="number" id="schedule-minute" min="0" max="59" value="0" style="width: 80px; padding: 8px; border: 1px solid #ddd; border-radius: 4px;">
                <select id="schedule-frequency" style="padding: 8px; border: 1px solid #ddd; border-radius: 4px;">
                    <option value="daily">每天</option>
                    <option value="weekly">每周</option>
                    <option value="monthly">每月</option>
                </select>
            </div>
        </div>
        
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e; width: 120px;"><%:操作%></label>
            <div class="cbi-value-field">
                <button id="set-schedule" class="btn-primary" style="padding: 10px 20px;">
                    <i class="icon icon-clock-o"></i> 设置定时任务
                </button>
                <p style="margin-top: 10px; color: #7f8c8d; font-size: 12px;">
                    设置后系统会在指定时间自动执行全面优化
                </p>
            </div>
        </div>
        
        <!-- 当前定时任务显示 -->
        <div id="current-schedule" style="margin-top: 20px; padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed;">
            <div style="font-weight: 600; margin-bottom: 10px; color: #2c3e50;">当前定时任务：</div>
            <div id="schedule-info" style="font-family: monospace; font-size: 12px; color: #7f8c8d;">
                加载中...
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
                statusDiv.innerHTML = '<pre style="margin: 0; white-space: pre-wrap; font-family: monospace; font-size: 12px; line-height: 1.4;">' + xhr.responseText + '</pre>';
            } else {
                statusDiv.innerHTML = '<div style="color: #e74c3c; padding: 20px; text-align: center;">加载状态失败</div>';
            }
        }
    };
    xhr.send();
}

// 加载当前定时任务
function loadCurrentSchedule() {
    var scheduleDiv = document.getElementById('schedule-info');
    
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/system/overlayfs-optimize/status', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var lines = xhr.responseText.split('\n');
            var found = false;
            
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].includes('overlay-cleanup')) {
                    scheduleDiv.innerHTML = '<span style="color: #27ae60;">' + lines[i].trim() + '</span>';
                    found = true;
                    break;
                }
            }
            
            if (!found) {
                scheduleDiv.innerHTML = '<span style="color: #e74c3c;">未设置定时任务</span>';
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
        'fix': '修复链接'
    };
    
    var confirmMessages = {
        'clean': '确定要清理OverlayFS临时文件吗？\n这将释放存储空间。',
        'optimize': '确定要优化OverlayFS配置吗？\n这将提升系统性能。',
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
    loadCurrentSchedule();
    
    // 刷新状态按钮
    document.getElementById('refresh-status').addEventListener('click', function() {
        loadOverlayStatus();
        showStatus('状态已刷新', 'info');
    });
    
    // 立即清理按钮
    document.getElementById('clean-now').addEventListener('click', function() {
        performAction('clean');
    });
    
    // 一键全面优化按钮
    document.getElementById('all-in-one').addEventListener('click', function() {
        if (confirm('执行全面优化操作，包括：\n1. 清理临时文件\n2. 优化配置\n3. 修复损坏链接\n\n确定继续吗？')) {
            showStatus('正在执行全面优化，请稍候...', 'info');
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/all")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('✅ 全面优化完成', 'success');
                            setTimeout(loadOverlayStatus, 3000);
                        }
                    } catch (e) {
                        showStatus('优化失败: ' + e.message, 'error');
                    }
                }
            };
            xhr.send();
        }
    });
    
    // 设置定时任务按钮
    document.getElementById('set-schedule').addEventListener('click', function() {
        var hour = document.getElementById('schedule-hour').value;
        var minute = document.getElementById('schedule-minute').value;
        var frequency = document.getElementById('schedule-frequency').value;
        
        var frequencyNames = {
            'daily': '每天',
            'weekly': '每周',
            'monthly': '每月'
        };
        
        if (confirm('确定要设置定时任务吗？\n\n' + 
                   '时间: ' + hour + ':' + minute + '\n' +
                   '频率: ' + frequencyNames[frequency] + '\n\n' +
                   '系统将在指定时间自动执行全面优化。')) {
            
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 设置中...';
            btn.disabled = true;
            
            var formData = new FormData();
            formData.append('hour', hour);
            formData.append('minute', minute);
            formData.append('frequency', frequency);
            
            var xhr = new XMLHttpRequest();
            xhr.open('POST', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/schedule")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('✅ ' + data.message, 'success');
                            setTimeout(loadCurrentSchedule, 1000);
                        } else {
                            showStatus('设置失败: ' + data.message, 'error');
                        }
                    } catch (e) {
                        showStatus('设置失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send(formData);
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

.btn-primary, .btn-secondary, .btn-success, .btn-info, .btn-sm {
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

.btn-info {
    background: #17a2b8;
    color: white;
}

.btn-sm {
    padding: 6px 12px;
    font-size: 12px;
}

.btn-primary:hover, .btn-secondary:hover, .btn-success:hover, .btn-info:hover, .btn-sm:hover {
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
    
    echo ""
    echo "========================================"
    echo "✓ OverlayFS文件系统优化已安装"
    echo "========================================"
    echo ""
    echo "📖 使用说明："
    echo "  1. 查看状态：overlay-cleanup status"
    echo "  2. 清理文件：overlay-cleanup clean"
    echo "  3. 全面优化：overlay-cleanup all"
    echo "  4. 定时任务：overlay-cleanup schedule"
    echo ""
    echo "🌐 Web界面："
    echo "  LuCI → 系统 → OverlayFS优化"
    echo ""
    echo "⏰ 默认计划任务："
    echo "  已设置：每天3:00自动清理临时文件"
    echo "          每周日4:00自动全面优化"
    echo ""
    echo "💡 建议："
    echo "  首次使用建议运行：overlay-cleanup all"
    echo "========================================"
else
    create_overlayfs_web_interface "$INSTALL_DIR"
    echo "✓ OverlayFS文件系统优化已集成到固件"
fi

echo "OverlayFS文件系统优化配置完成！"
