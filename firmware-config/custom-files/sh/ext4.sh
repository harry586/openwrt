#!/bin/bash
# =============================================
# OpenWrt DIY 脚本 - 双重模式：编译集成 + 运行时安装
# ext4文件系统优化脚本
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

echo "开始优化ext4文件系统..."

# ==================== 优化fstab配置 ====================
optimize_fstab() {
    local prefix="$1"
    
    if [ "$RUNTIME_MODE" = "true" ]; then
        # 运行时：直接修改/etc/fstab
        if [ -f "/etc/fstab" ]; then
            # 备份原文件
            cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
            
            # 修改overlay挂载选项
            sed -i '/\/overlay.*ext4/s/rw,/rw,noatime,nodiratime,/g' /etc/fstab
            sed -i '/\/overlay.*ext4/s/rw$/rw,noatime,nodiratime/g' /etc/fstab
            
            # 添加磁盘优化挂载选项
            for i in 1 2 3 4; do
                if grep -q "/dev/sda$i" /etc/fstab; then
                    sed -i "/\/dev\/sda$i.*ext4/s/rw,/rw,noatime,nodiratime,/g" /etc/fstab
                    sed -i "/\/dev\/sda$i.*ext4/s/rw$/rw,noatime,nodiratime/g" /etc/fstab
                else
                    # 添加新的挂载点
                    echo "/dev/sda$i /mnt/sda$i ext4 rw,noatime,nodiratime,errors=remount-ro 0 0" >> /etc/fstab
                    mkdir -p /mnt/sda$i 2>/dev/null || true
                fi
            done
            
            echo "✓ fstab配置已优化"
        fi
    else
        # 编译时：创建优化的fstab文件
        cat > "${prefix}/etc/fstab" << 'EOF'
# /etc/fstab: static file system information
#
# <file system> <mount point> <type> <options> <dump> <pass>

# Overlay filesystem
/dev/root /overlay ext4 rw,noatime,nodiratime,errors=remount-ro 0 0

# Additional storage optimization
/dev/sda1 /mnt/sda1 ext4 rw,noatime,nodiratime,errors=remount-ro,data=ordered 0 0
/dev/sda2 /mnt/sda2 ext4 rw,noatime,nodiratime,errors=remount-ro,data=ordered 0 0
/dev/sda3 /mnt/sda3 ext4 rw,noatime,nodiratime,errors=remount-ro,data=ordered 0 0
/dev/sda4 /mnt/sda4 ext4 rw,noatime,nodiratime,errors=remount-ro,data=ordered 0 0

# Temporary filesystems
tmpfs /tmp tmpfs rw,nosuid,nodev,noatime,size=128M 0 0
tmpfs /var/lock tmpfs rw,nosuid,nodev,noatime,size=32M 0 0
tmpfs /var/run tmpfs rw,nosuid,nodev,noatime,size=32M 0 0
EOF
        echo "✓ fstab配置已集成到固件"
    fi
}

# ==================== 创建优化脚本 ====================
create_tune2fs_script() {
    local prefix="$1"
    cat > "${prefix}/usr/sbin/tune-ext4" << 'EOF'
#!/bin/sh
# ext4文件系统优化脚本

echo "正在优化ext4文件系统参数..."

# 检查并优化已挂载的ext4分区
for device in $(lsblk -o NAME,FSTYPE | grep ext4 | awk '{print "/dev/"$1}'); do
    echo "优化 $device ..."
    
    # 设置保留块比例为0%（不保留）
    tune2fs -m 0 "$device" 2>/dev/null || true
    
    # 启用dir_index特性
    tune2fs -O dir_index "$device" 2>/dev/null || true
    
    # 启用extent特性（减少碎片）
    tune2fs -O extent "$device" 2>/dev/null || true
    
    # 禁用最后一次挂载检查（加快启动速度）
    tune2fs -c 0 -i 0 "$device" 2>/dev/null || true
    
    # 设置日志提交时间为5秒（默认是5，但确认一下）
    tune2fs -o journal_data_ordered "$device" 2>/dev/null || true
done

# 重新挂载所有分区应用noatime设置
mount -o remount /overlay 2>/dev/null || true
for i in 1 2 3 4; do
    if mount | grep -q "/mnt/sda$i"; then
        mount -o remount /mnt/sda$i 2>/dev/null || true
    fi
done

echo "ext4文件系统优化完成！"
echo "优化包括："
echo "  ✓ 禁用保留块"
echo "  ✓ 启用目录索引"
echo "  ✓ 启用extent特性"
echo "  ✓ 禁用定期文件系统检查"
echo "  ✓ 应用noatime挂载选项"
EOF
    chmod +x "${prefix}/usr/sbin/tune-ext4"
}

optimize_fstab "$INSTALL_DIR"
create_tune2fs_script "$INSTALL_DIR"

if [ "$RUNTIME_MODE" = "true" ]; then
    # 运行优化脚本
    /usr/sbin/tune-ext4 2>/dev/null || true
    
    # 创建计划任务，每月优化一次
    echo "0 2 1 * * /usr/sbin/tune-ext4 >/dev/null 2>&1" >> /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
fi

echo "ext4文件系统优化完成！"
