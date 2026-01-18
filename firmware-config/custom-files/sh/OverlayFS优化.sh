#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# OverlayFS文件系统优化脚本
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

    # 创建overlay清理脚本
    cat > "${prefix}/usr/sbin/overlay-cleanup" << 'EOF'
#!/bin/sh
# OverlayFS清理和优化脚本

LOG_FILE="/var/log/overlay-cleanup.log"
BACKUP_DIR="/tmp/overlay-backup"

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
    echo "OverlayFS使用情况报告"
    echo "========================"
    
    # 检查挂载点
    echo "挂载状态:"
    mount | grep -E "(overlay|/overlay)" || echo "未找到overlay挂载"
    echo ""
    
    # 检查磁盘使用
    echo "磁盘使用情况:"
    df -h /overlay 2>/dev/null || echo "无法获取/overlay使用情况"
    echo ""
    
    # 检查上层目录大小
    echo "上层目录大小:"
    if [ -d "/overlay/upper" ]; then
        du -sh /overlay/upper/* 2>/dev/null | sort -hr | head -10
    else
        echo "上层目录不存在"
    fi
    echo ""
    
    # 检查inode使用
    echo "Inode使用情况:"
    df -i /overlay 2>/dev/null || echo "无法获取inode信息"
    echo ""
    
    # 检查文件数量
    echo "文件数量统计:"
    if [ -d "/overlay/upper" ]; then
        find /overlay/upper -type f | wc -l | awk '{print "文件数: "$1}'
        find /overlay/upper -type d | wc -l | awk '{print "目录数: "$1}'
        find /overlay/upper -type l | wc -l | awk '{print "链接数: "$1}'
    fi
}

# 重置overlay（危险操作）
reset_overlay() {
    echo "⚠️  警告：此操作将重置overlay，所有自定义配置和安装的软件将丢失！"
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
        
        echo "overlay重置完成，需要重启系统"
        echo "重启命令: reboot"
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
        echo "启动overlay监控模式，按Ctrl+C退出..."
        while true; do
            clear
            check_overlay_usage
            echo ""
            echo "监控中... 5秒后刷新"
            sleep 5
        done
        ;;
    *)
        echo "OverlayFS优化工具"
        echo "用法: $0 {clean|compress|status|optimize|fix|reset|all|monitor}"
        echo "  clean    - 清理临时文件"
        echo "  compress - 压缩overlay数据"
        echo "  status   - 显示使用情况"
        echo "  optimize - 优化挂载参数和结构"
        echo "  fix      - 修复损坏链接"
        echo "  reset    - 重置overlay（危险）"
        echo "  all      - 执行所有优化"
        echo "  monitor  - 持续监控模式"
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
    /usr/sbin/overlay-cleanup optimize
    
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

    # Web界面
    cat > "${prefix}/usr/lib/lua/luci/view/admin_system/overlayfs_optimize.htm" << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content"><%:OverlayFS文件系统优化%></h2>
    
    <!-- 信息提示 -->
    <div class="alert-message" style="background: #e8f4fd; color: #0c5460; border: 1px solid #bee5eb; padding: 15px; margin-bottom: 20px; border-radius: 6px;">
        <h4 style="margin-top: 0;">💾 OverlayFS优化</h4>
        <p style="margin-bottom: 10px;">OverlayFS是OpenWrt的根文件系统，优化它可以提升系统性能和稳定性。</p>
        <ul style="margin: 0; padding-left: 20px;">
            <li><strong>性能优化：</strong>优化挂载参数，提升文件操作速度</li>
            <li><strong>空间管理：</strong>定期清理临时文件，释放存储空间</li>
            <li><strong>稳定性：</strong>修复损坏的链接和文件</li>
            <li><strong>监控：</strong>实时监控overlay使用情况</li>
        </ul>
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
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:一键优化%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <button id="optimize-now" class="btn-success" style="padding: 10px 20px;">
                        <i class="icon icon-cogs"></i> 优化配置
                    </button>
                    <button id="compress-now" class="btn-warning" style="padding: 10px 20px;">
                        <i class="icon icon-compress"></i> 压缩数据
                    </button>
                    <button id="fix-links" class="btn-info" style="padding: 10px 20px;">
                        <i class="icon icon-chain-broken"></i> 修复链接
                    </button>
                    <button id="advanced-opt" class="btn-neutral" style="padding: 10px 20px;">
                        <i class="icon icon-magic"></i> 高级优化
                    </button>
                </div>
                <p style="margin-top: 10px; color: #7f8c8d; font-size: 12px;">
                    优化操作可能需要一些时间，请勿在操作期间断电或重启
                </p>
            </div>
        </div>
    </div>
    
    <!-- 高级选项 -->
    <div class="cbi-section" style="background: #f8f9fa; padding: 20px; border-radius: 8px;">
        <h3 style="margin-top: 0; color: #2c3e50;"><%:高级选项%></h3>
        <div class="cbi-value">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:危险操作%></label>
            <div class="cbi-value-field">
                <div style="display: flex; gap: 12px; flex-wrap: wrap;">
                    <button id="reset-overlay" class="btn-danger" style="padding: 10px 20px;">
                        <i class="icon icon-warning"></i> 重置Overlay
                    </button>
                    <button id="monitor-mode" class="btn-secondary" style="padding: 10px 20px;">
                        <i class="icon icon-desktop"></i> 监控模式
                    </button>
                </div>
                <p style="margin-top: 10px; color: #e74c3c; font-size: 12px;">
                    ⚠️ 重置Overlay会删除所有自定义配置和安装的软件，请谨慎操作！
                </p>
            </div>
        </div>
        
        <!-- 配置参数 -->
        <div class="cbi-value" style="margin-top: 20px;">
            <label class="cbi-value-title" style="font-weight: 600; color: #34495e;"><%:挂载参数%></label>
            <div class="cbi-value-field">
                <div style="padding: 15px; background: white; border-radius: 6px; border: 1px solid #e1e8ed; font-family: monospace; font-size: 12px;">
                    <div style="margin-bottom: 8px;"><strong>当前参数：</strong></div>
                    <div id="mount-params" style="color: #34495e;">加载中...</div>
                </div>
                <button id="reload-params" class="btn-neutral" style="margin-top: 10px; padding: 8px 16px;">
                    <i class="icon icon-redo"></i> 重载参数
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
        case 'danger':
            bgColor = '#f8d7da';
            textColor = '#721c24';
            borderColor = '#f5c6cb';
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
                // 将纯文本转换为格式化显示
                var lines = xhr.responseText.split('\n');
                var html = '';
                
                lines.forEach(function(line) {
                    if (line.trim() === '') return;
                    
                    if (line.includes('======')) {
                        html += '<div style="font-weight: 600; color: #2c3e50; margin: 10px 0 5px 0; border-bottom: 1px solid #e1e8ed; padding-bottom: 3px;">' + line + '</div>';
                    } else if (line.includes(':')) {
                        var parts = line.split(':');
                        var key = parts[0];
                        var value = parts.slice(1).join(':');
                        
                        html += '<div style="margin: 3px 0; padding: 2px 0;">';
                        html += '<span style="color: #34495e; font-weight: 500;">' + key + ':</span>';
                        html += '<span style="color: #2c3e50; margin-left: 8px;">' + value + '</span>';
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

// 加载挂载参数
function loadMountParams() {
    var paramsDiv = document.getElementById('mount-params');
    
    // 获取挂载信息
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/cgi-bin/luci/admin/system/overlayfs-optimize/status', true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
            var lines = xhr.responseText.split('\n');
            var mountLine = lines.find(function(line) {
                return line.includes('on /overlay type overlay');
            });
            
            if (mountLine) {
                // 提取参数部分
                var params = mountLine.match(/\((.*)\)/);
                if (params && params[1]) {
                    paramsDiv.innerHTML = params[1].replace(/,/g, ', ');
                } else {
                    paramsDiv.innerHTML = '无法解析参数';
                }
            } else {
                paramsDiv.innerHTML = '未找到overlay挂载信息';
            }
        }
    };
    xhr.send();
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 加载初始状态
    loadOverlayStatus();
    loadMountParams();
    
    // 刷新状态按钮
    document.getElementById('refresh-status').addEventListener('click', function() {
        loadOverlayStatus();
        loadMountParams();
        showStatus('状态已刷新', 'info');
    });
    
    // 重载参数按钮
    document.getElementById('reload-params').addEventListener('click', function() {
        loadMountParams();
        showStatus('参数已重载', 'info');
    });
    
    // 立即清理按钮
    document.getElementById('clean-now').addEventListener('click', function() {
        if (confirm('确定要立即清理OverlayFS临时文件吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 清理中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/clean")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('OverlayFS清理完成', 'success');
                            setTimeout(function() {
                                loadOverlayStatus();
                            }, 2000);
                        }
                    } catch (e) {
                        showStatus('清理失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 优化配置按钮
    document.getElementById('optimize-now').addEventListener('click', function() {
        if (confirm('确定要优化OverlayFS配置吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 优化中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/optimize")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('OverlayFS优化完成', 'success');
                            setTimeout(function() {
                                loadOverlayStatus();
                                loadMountParams();
                            }, 2000);
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
    
    // 压缩数据按钮
    document.getElementById('compress-now').addEventListener('click', function() {
        if (confirm('确定要压缩OverlayFS数据吗？这可能需要一些时间。')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 压缩中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/compress")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('OverlayFS压缩完成', 'success');
                            setTimeout(function() {
                                loadOverlayStatus();
                            }, 3000);
                        }
                    } catch (e) {
                        showStatus('压缩失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 修复链接按钮
    document.getElementById('fix-links').addEventListener('click', function() {
        if (confirm('确定要检查并修复损坏的链接吗？')) {
            var btn = this;
            var originalText = btn.innerHTML;
            btn.innerHTML = '<i class="icon icon-spinner icon-spin"></i> 修复中...';
            btn.disabled = true;
            
            var xhr = new XMLHttpRequest();
            xhr.open('GET', '<%=luci.dispatcher.build_url("admin/system/overlayfs-optimize/fix")%>', true);
            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4 && xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        if (data.success) {
                            showStatus('链接修复完成', 'success');
                            setTimeout(function() {
                                loadOverlayStatus();
                            }, 2000);
                        }
                    } catch (e) {
                        showStatus('修复失败: ' + e.message, 'error');
                    }
                    btn.disabled = false;
                    btn.innerHTML = originalText;
                }
            };
            xhr.send();
        }
    });
    
    // 高级优化按钮
    document.getElementById('advanced-opt').addEventListener('click', function() {
        if (confirm('执行高级优化操作，包括所有优化步骤。确定继续吗？')) {
            showStatus('正在执行高级优化，请稍候...', 'info');
            
            // 顺序执行所有优化
            var steps = ['clean', 'optimize', 'fix'];
            var currentStep = 0;
            
            function executeNextStep() {
                if (currentStep >= steps.length) {
                    showStatus('高级优化完成', 'success');
                    loadOverlayStatus();
                    loadMountParams();
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
    
    // 重置Overlay按钮（危险操作）
    document.getElementById('reset-overlay').addEventListener('click', function() {
        var confirmText = prompt('⚠️  危险操作！这将删除所有自定义配置和安装的软件。\n请输入"RESET"确认：');
        
        if (confirmText === 'RESET') {
            showStatus('正在重置Overlay，请勿断电或重启...', 'danger');
            
            // 这里应该调用后端的重置接口
            // 由于是危险操作，实际应用中需要更完善的保护
            setTimeout(function() {
                showStatus('重置操作需要在终端执行，请使用命令: overlay-cleanup reset', 'warning');
            }, 1000);
        } else {
            showStatus('操作已取消', 'info');
        }
    });
    
    // 监控模式按钮
    document.getElementById('monitor-mode').addEventListener('click', function() {
        showStatus('监控模式需要在终端执行: overlay-cleanup monitor', 'info');
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

.btn-primary:hover, .btn-secondary:hover, .btn-success:hover, .btn-warning:hover, .btn-info:hover, .btn-neutral:hover, .btn-danger:hover {
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
    
    # 优化fstab配置
    if [ -f "/etc/fstab" ] && [ -f "/etc/fstab.overlay" ]; then
        # 备份原配置
        cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
        # 合并配置
        cat /etc/fstab.overlay >> /etc/fstab
    fi
    
    # 重启LuCI使新页面生效
    if [ -f /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd restart 2>/dev/null || true
    fi
    
    # 创建计划任务
    echo "# OverlayFS优化任务" >> /etc/crontabs/root
    echo "0 3 * * * /usr/sbin/overlay-cleanup clean >/dev/null 2>&1" >> /etc/crontabs/root
    echo "30 3 * * 0 /usr/sbin/overlay-cleanup optimize >/dev/null 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ OverlayFS文件系统优化已应用"
    echo ""
    echo "【访问方式】:"
    echo "   LuCI界面 → 系统 → OverlayFS优化"
    echo ""
    echo "【手动操作】:"
    echo "   查看状态: overlay-cleanup status"
    echo "   清理文件: overlay-cleanup clean"
    echo "   优化配置: overlay-cleanup optimize"
    echo "   监控模式: overlay-cleanup monitor"
else
    create_overlayfs_web_interface "$INSTALL_DIR"
    echo "✓ OverlayFS文件系统优化已集成到固件"
fi

echo "OverlayFS文件系统优化配置完成！"