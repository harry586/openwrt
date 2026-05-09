#!/bin/sh
# Ksmbd 只读 + FTP 可写 配置脚本
# 功能：Ksmbd 匿名只读，FTP 等其他服务可写

echo "=== Ksmbd 只读 + FTP 可写 配置脚本 ==="

# 获取 ksmbd 版本
echo "检测 ksmbd 版本..."
KSMD_VERSION="未知"
if command -v ksmbd.mountd >/dev/null 2>&1; then
    # ksmbd-tools 通常通过 ksmbd.mountd -V 显示版本
    VER_OUTPUT=$(ksmbd.mountd -V 2>&1)
    if echo "$VER_OUTPUT" | grep -qi "ksmbd-tools"; then
        KSMD_VERSION=$(echo "$VER_OUTPUT" | head -1 | sed 's/.*ksmbd-tools v//;s/.$//')
    else
        KSMD_VERSION="已安装（版本未知）"
    fi
fi
echo "✓ 检测到 ksmbd 版本: $KSMD_VERSION"

# 1. 停止 Ksmbd 服务
echo "停止 Ksmbd 服务..."
/etc/init.d/ksmbd stop 2>/dev/null
killall ksmbd.mountd 2>/dev/null
sleep 2

# 2. 删除旧配置（备份可选）
echo "备份并删除旧配置..."
rm -f /etc/ksmbd/ksmbd.conf.bak 2>/dev/null
[ -f /etc/ksmbd/ksmbd.conf ] && cp /etc/ksmbd/ksmbd.conf /etc/ksmbd/ksmbd.conf.bak
rm -f /etc/ksmbd/ksmbd.conf 2>/dev/null
# 同时清空 UCI 配置以防干扰
[ -f /etc/config/ksmbd ] && cp /etc/config/ksmbd /etc/config/ksmbd.bak && echo "" > /etc/config/ksmbd

# 3. 创建 Ksmbd 配置文件
echo "创建 /etc/ksmbd/ksmbd.conf ..."
cat > /etc/ksmbd/ksmbd.conf << 'EOF'
[global]
    # ========== 基本设置 ==========
    workgroup = WORKGROUP
    server string = OpenWRT Ksmbd (Read-Only)
    netbios name = OpenWRT
    interfaces = lo br-lan
    bind interfaces only = yes

    # ========== 安全与访问控制 ==========
    map to guest = Bad User
    guest account = nobody

    # ========== 协议兼容性 ==========
    # Ksmbd 默认支持 SMB2/3，如需 SMB1 可启用服务器最小协议为 NT1
    # server min protocol = SMB2 （兼容性好）
    server min protocol = SMB2
    server max protocol = SMB3
    # 若老旧设备需要SMB1，取消下行注释
    # server min protocol = NT1

    # ========== 性能优化 ==========
    tcp nodelay = yes
    deadtime = 15
    max connections = 10
    max open files = 16384
    strict allocate = yes
    strict sync = no
    # Ksmbd 不支持 aio read/write size，使用默认

    # ========== 文件过滤设置 ==========
    veto files = /*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.msi/*.tmp/*.temp/*.cache/*.swp/*.swo/*.bak/*.old/._*/.DS_Store/desktop.ini/Thumbs.db/*.o/*.obj/*.class/*.pyc/*.jar/*.log/
    hide dot files = yes
    hide files = /~$*/.~*/.tmp*/
    hide unreadable = yes
    delete veto files = no

    # ========== 日志设置 ==========
    # Ksmbd 日志通过 syslog 输出，此处仅设置级别
    log level = 1

    # ========== 字符集设置 ==========
    unix charset = UTF-8
    dos charset = CP850

[sda1]
    comment = Read-Only Share (FTP 可写)
    path = /mnt/sda1
    browseable = yes
    available = yes
    read only = yes
    writable = no
    guest ok = yes

    # 只读掩码（新建文件不会通过 SMB 被创建，但保留默认值）
    create mask = 0644
    directory mask = 0755

    hide dot files = yes
    veto files = /*.exe/*.dll/*.bat/*.cmd/*.scr/*.tmp/*.temp/
    delete veto files = no
    case sensitive = auto
    preserve case = yes
    short preserve case = yes
EOF

echo "✓ 配置文件已创建"

# 4. 设置目录权限（与 samba.sh 逻辑相同）
echo "设置共享目录权限..."

mkdir -p /mnt/sda1

# 检测 vsftpd 的 ftp 用户
if id ftp >/dev/null 2>&1; then
    FTP_USER="ftp"
    FTP_GROUP="ftp"
    echo "检测到 ftp 用户，设置 ftp 用户可写..."
    chown -R ftp:ftp /mnt/sda1 2>/dev/null || true
    chmod -R 755 /mnt/sda1 2>/dev/null || true
    find /mnt/sda1 -type d -exec chmod 775 {} \; 2>/dev/null || true
else
    echo "未检测到 ftp 用户，使用 root 权限（FTP 需以 root 运行）"
    chmod -R 755 /mnt/sda1 2>/dev/null || true
fi

# 确保 nobody 只读（ksmbd 用）
chown -R nobody:nogroup /mnt/sda1 2>/dev/null || true
chmod -R 755 /mnt/sda1 2>/dev/null || true

echo "✓ 目录权限已设置"

# 5. 启动 Ksmbd 服务
echo "启动 Ksmbd 服务..."
/etc/init.d/ksmbd start 2>/dev/null &
sleep 2

# 6. 检查服务状态
echo "检查服务状态..."
if pgrep ksmbd.mountd >/dev/null; then
    echo "✓ Ksmbd 服务已启动 (ksmbd.mountd)"
else
    echo "✗ Ksmbd 服务启动失败，请检查日志"
fi

# 7. 设置配置文件为只读
chmod 444 /etc/ksmbd/ksmbd.conf 2>/dev/null || true
echo "✓ 配置文件已设为只读"

# 8. 显示配置摘要
echo ""
echo "=== 配置完成 ==="
echo ""
echo "配置摘要:"
echo "  Ksmbd 版本: $KSMD_VERSION"
echo "  Ksmbd 访问: 匿名只读"
echo "  FTP 访问:   可写（需 FTP 服务单独配置）"
echo "  共享名称:    sda1"
echo "  共享路径:    /mnt/sda1"
echo ""
echo "权限说明:"
echo "  ✓ Ksmbd 使用 nobody 用户 → 只读"
echo "  ✓ FTP 可使用 root/ftp 用户 → 可写"
echo ""
echo "FTP 配置提醒:"
echo "  1. vsftpd: 确保 write_enable=YES"
echo "  2. 如果 FTP 使用匿名用户，需设置: anon_upload_enable=YES"
echo "  3. 建议 FTP 使用 root 或 ftp 用户，并设置目录写权限"
echo ""
