#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# 磁盘性能优化脚本
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

echo "开始优化磁盘性能..."

# ==================== 创建目录结构 ====================
create_dirs() {
    local prefix="$1"
    mkdir -p "${prefix}/etc/sysctl.d"
    mkdir -p "${prefix}/usr/sbin"
}

create_dirs "$INSTALL_DIR"

# ==================== 磁盘I/O调度器优化 ====================
create_ioscheduler_script() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/optimize-io" << 'EOF'
#!/bin/sh
# 磁盘I/O调度器优化脚本

echo "正在优化磁盘I/O调度器..."

# 检测磁盘类型并设置合适的调度器
for disk in /sys/block/sd* /sys/block/mmcblk*; do
    if [ -d "$disk" ]; then
        disk_name=$(basename "$disk")
        
        # 判断磁盘类型
        if [ -f "/sys/block/$disk_name/queue/rotational" ]; then
            rotational=$(cat "/sys/block/$disk_name/queue/rotational")
            
            if [ "$rotational" = "1" ]; then
                # 机械硬盘：使用deadline调度器
                echo "机械硬盘 $disk_name 使用deadline调度器"
                echo "deadline" > "/sys/block/$disk_name/queue/scheduler" 2>/dev/null || true
                
                # 优化队列参数
                echo "256" > "/sys/block/$disk_name/queue/nr_requests" 2>/dev/null || true
                echo "1024" > "/sys/block/$disk_name/queue/read_ahead_kb" 2>/dev/null || true
            else
                # SSD固态硬盘：使用noop或mq-deadline调度器
                echo "固态硬盘 $disk_name 使用mq-deadline调度器"
                if [ -f "/sys/block/$disk_name/queue/scheduler" ]; then
                    if grep -q "mq-deadline" "/sys/block/$disk_name/queue/scheduler"; then
                        echo "mq-deadline" > "/sys/block/$disk_name/queue/scheduler" 2>/dev/null || true
                    elif grep -q "noop" "/sys/block/$disk_name/queue/scheduler"; then
                        echo "noop" > "/sys/block/$disk_name/queue/scheduler" 2>/dev/null || true
                    fi
                fi
                
                # SSD优化参数
                echo "128" > "/sys/block/$disk_name/queue/nr_requests" 2>/dev/null || true
                echo "128" > "/sys/block/$disk_name/queue/read_ahead_kb" 2>/dev/null || true
                
                # 启用TRIM支持
                if [ -f "/sys/block/$disk_name/queue/discard_granularity" ]; then
                    discard_gran=$(cat "/sys/block/$disk_name/queue/discard_granularity")
                    if [ "$discard_gran" != "0" ]; then
                        echo "启用 $disk_name 的TRIM支持"
                        echo "1" > "/sys/block/$disk_name/queue/discard_max_bytes" 2>/dev/null || true
                    fi
                fi
            fi
            
            # 通用优化
            echo "1" > "/sys/block/$disk_name/queue/rq_affinity" 2>/dev/null || true
            echo "0" > "/sys/block/$disk_name/queue/add_random" 2>/dev/null || true
            echo "2" > "/sys/block/$disk_name/queue/nomerges" 2>/dev/null || true
        fi
    fi
done

echo "磁盘I/O调度器优化完成！"
EOF
    chmod +x "${prefix}/usr/sbin/optimize-io"
}

# ==================== 虚拟内存优化 ====================
create_vm_optimization() {
    local prefix="$1"
    cat > "${prefix}/etc/sysctl.d/99-vm-optimization.conf" << 'EOF'
# 虚拟内存和磁盘缓存优化
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_expire_centisecs = 3000
vm.dirty_writeback_centisecs = 500
vm.min_free_kbytes = 65536
vm.overcommit_memory = 1
vm.overcommit_ratio = 50

# 文件系统缓存优化
vm.page-cluster = 0
vm.laptop_mode = 0

# 减少内存碎片
vm.extfrag_threshold = 500

# ZRAM压缩（如果启用）
vm.page-cluster = 0
EOF
}

# ==================== 文件系统缓存优化 ====================
create_fs_cache_script() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/optimize-fs-cache" << 'EOF'
#!/bin/sh
# 文件系统缓存优化脚本

echo "正在优化文件系统缓存..."

# 调整inode缓存
sysctl -w fs.inode-state=100000 2>/dev/null || true
sysctl -w fs.file-max=65536 2>/dev/null || true

# 调整dentry缓存
sysctl -w fs.dentry-state=100000 2>/dev/null || true

# 对于小内存设备，减少缓存压力
MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$MEM_KB" -lt 256000 ]; then
    # 小于256MB内存
    sysctl -w vm.vfs_cache_pressure=100
    sysctl -w vm.swappiness=20
else
    # 大于256MB内存
    sysctl -w vm.vfs_cache_pressure=50
    sysctl -w vm.swappiness=10
fi

echo "文件系统缓存优化完成！"
EOF
    chmod +x "${prefix}/usr/sbin/optimize-fs-cache"
}

# ==================== 执行优化 ====================
create_ioscheduler_script "$INSTALL_DIR"
create_vm_optimization "$INSTALL_DIR"
create_fs_cache_script "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行优化脚本
    /usr/sbin/optimize-io
    /usr/sbin/optimize-fs-cache
    
    # 应用sysctl设置
    sysctl -p /etc/sysctl.d/99-vm-optimization.conf 2>/dev/null || true
    
    # 创建计划任务
    echo "# 每周日凌晨3点优化磁盘性能" >> /etc/crontabs/root
    echo "0 3 * * 0 /usr/sbin/optimize-io >/dev/null 2>&1" >> /etc/crontabs/root
    echo "0 4 * * 0 /usr/sbin/optimize-fs-cache >/dev/null 2>&1" >> /etc/crontabs/root
    
    /etc/init.d/cron restart 2>/dev/null || true
    
    echo "✓ 磁盘性能优化已应用"
else
    echo "✓ 磁盘性能优化配置已集成到固件"
fi

echo "磁盘性能优化完成！"
echo "优化包括："
echo "  ✓ I/O调度器优化（SSD/HDD自动识别）"
echo "  ✓ 虚拟内存参数优化"
echo "  ✓ 文件系统缓存优化"
echo "  ✓ TRIM支持（SSD）"
echo "  ✓ 定期自动优化"