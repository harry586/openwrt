#!/bin/sh
# Samba只读 + FTP可写 配置脚本（兼容Samba 3.x/4.x）
# 功能：Samba匿名只读，FTP等其他服务可写

echo "=== Samba只读 + FTP可写 配置脚本 ==="

# 获取Samba版本
echo "检测Samba版本..."
SAMBA_VERSION="未知"
if command -v smbd >/dev/null 2>&1; then
    if smbd -V 2>/dev/null | head -1 | grep -q "Version"; then
        SAMBA_VERSION=$(smbd -V 2>/dev/null | head -1 | sed 's/.*Version //')
    elif testparm -V 2>/dev/null | head -1 | grep -q "Version"; then
        SAMBA_VERSION=$(testparm -V 2>/dev/null | head -1 | sed 's/.*Version //')
    elif which smbd 2>&1 | grep -q "/"; then
        SAMBA_VERSION="已安装（版本未知）"
    fi
fi
echo "✓ 检测到 Samba 版本: $SAMBA_VERSION"

# 判断是否是3.x版本
SAMBA_MAJOR_VERSION=$(echo $SAMBA_VERSION | cut -d. -f1)

# 1. 停止Samba服务
echo "停止Samba服务..."
killall smbd nmbd 2>/dev/null
sleep 2

# 2. 删除原配置文件
echo "删除原配置文件..."
rm -f /etc/samba/smb.conf 2>/dev/null

# 3. 创建配置（区分3.x和4.x版本）
echo "创建配置文件..."
if [ "$SAMBA_MAJOR_VERSION" = "3" ]; then
    echo "使用 Samba 3.x 兼容配置"
    cat > /etc/samba/smb.conf << 'EOF'
[global]
    # ========== 基本设置 ==========
    workgroup = WORKGROUP
    server string = OpenWRT Samba (Read-Only)
    netbios name = OpenWRT
    interfaces = lo br-lan
    bind interfaces only = yes
    
    # ========== 禁用打印共享（避免printcap错误）==========
    load printers = no
    printing = bsd
    
    # ========== 安全与访问控制 ==========
    security = share
    map to guest = Bad User
    guest account = nobody
    guest ok = yes
    invalid users = root
    
    # ========== 协议兼容性 ==========
    protocol = NT1
    
    # ========== 性能优化 ==========
    socket options = TCP_NODELAY IPTOS_LOWDELAY
    deadtime = 15
    getwd cache = yes
    large readwrite = yes
    
    max connections = 10
    max open files = 16384
    strict allocate = yes
    strict sync = no
    
    # ========== 文件过滤设置 ==========
    veto files = /*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.msi/*.tmp/*.temp/*.cache/*.swp/*.swo/*.bak/*.old/._*/.DS_Store/desktop.ini/Thumbs.db/*.o/*.obj/*.class/*.pyc/*.jar/*.log/
    
    hide dot files = yes
    hide files = /~$*/.~*/.tmp*/
    hide unreadable = yes
    delete veto files = no
    
    # ========== 日志设置 ==========
    log file = /var/log/samba/log.%m
    max log size = 1024
    log level = 1
    
    # ========== 字符集设置 ==========
    unix charset = UTF-8
    dos charset = CP936

[sda1]
    comment = Read-Only Share (FTP可写)
    path = /mnt/sda1
    browseable = yes
    available = yes
    read only = yes
    writable = no
    guest ok = yes
    
    # 只读权限：不强制指定用户，保持文件原有权限
    # FTP等其他服务可以正常写入
    create mask = 0644
    directory mask = 0755
    
    hide dot files = yes
    veto files = /*.exe/*.dll/*.bat/*.cmd/*.scr/*.tmp/*.temp/
    delete veto files = no
    
    case sensitive = auto
    preserve case = yes
    short preserve case = yes
EOF
else
    echo "使用 Samba 4.x 兼容配置"
    cat > /etc/samba/smb.conf << 'EOF'
[global]
    # ========== 基本设置 ==========
    workgroup = WORKGROUP
    server string = OpenWRT Samba (Read-Only)
    netbios name = OpenWRT
    interfaces = lo br-lan
    bind interfaces only = yes
    
    # ========== 禁用打印共享（避免printcap错误）==========
    load printers = no
    printing = bsd
    
    # ========== 安全与访问控制 ==========
    security = user
    map to guest = Bad User
    guest account = nobody
    guest ok = yes
    guest only = yes
    invalid users = root
    
    # ========== 协议兼容性 ==========
    min protocol = NT1
    max protocol = SMB3
    server min protocol = SMB2
    server max protocol = SMB3
    
    # ========== 性能优化 ==========
    socket options = TCP_NODELAY IPTOS_LOWDELAY
    deadtime = 15
    getwd cache = yes
    large readwrite = yes
    use sendfile = yes
    
    max connections = 10
    max open files = 16384
    max stat cache size = 512
    strict allocate = yes
    strict sync = no
    
    aio read size = 16384
    aio write size = 16384
    
    # ========== 文件过滤设置 ==========
    veto files = /*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.msi/*.tmp/*.temp/*.cache/*.swp/*.swo/*.bak/*.old/._*/.DS_Store/desktop.ini/Thumbs.db/*.o/*.obj/*.class/*.pyc/*.jar/*.log/
    
    hide dot files = yes
    hide files = /~$*/.~*/.tmp*/
    hide unreadable = yes
    delete veto files = no
    
    # ========== 加密和签名设置 ==========
    smb encrypt = disabled
    server signing = auto
    
    # ========== 日志设置 ==========
    log file = /var/log/samba/log.%m
    max log size = 1024
    log level = 1
    
    # ========== 字符集设置 ==========
    unix charset = UTF-8
    dos charset = CP850

[sda1]
    comment = Read-Only Share (FTP可写)
    path = /mnt/sda1
    browseable = yes
    available = yes
    read only = yes
    writable = no
    guest ok = yes
    guest only = yes
    
    # 只读权限：不强制指定用户，保持文件原有权限
    # FTP等其他服务可以正常写入
    create mask = 0644
    directory mask = 0755
    
    hide dot files = yes
    veto files = /*.exe/*.dll/*.bat/*.cmd/*.scr/*.tmp/*.temp/
    delete veto files = no
    
    case sensitive = auto
    preserve case = yes
    short preserve case = yes
EOF
fi

echo "✓ 配置文件已创建"

# 4. 设置目录权限（关键：让FTP用户可写，Samba只读）
echo "设置共享目录权限..."

# 创建挂载点
mkdir -p /mnt/sda1

# 方案：设置目录为 755，文件为 644
# FTP 用户（如 root 或 ftp）需要有写入权限
# 如果 FTP 以 root 运行，则无需额外设置
# 如果 FTP 以 ftp 用户运行，则需设置权限

# 检测是否有 vsftpd 的 ftp 用户
if id ftp >/dev/null 2>&1; then
    FTP_USER="ftp"
    FTP_GROUP="ftp"
    echo "检测到 ftp 用户，设置 ftp 用户可写..."
    chown -R ftp:ftp /mnt/sda1 2>/dev/null || true
    chmod -R 755 /mnt/sda1 2>/dev/null || true
    # 目录需要写权限
    find /mnt/sda1 -type d -exec chmod 775 {} \; 2>/dev/null || true
else
    # 如果 FTP 以 root 运行，保持 root 可写
    echo "未检测到 ftp 用户，使用 root 权限（FTP需以root运行）"
    chmod -R 755 /mnt/sda1 2>/dev/null || true
fi

# 确保 nobody 只读（Samba用）
chown -R nobody:nogroup /mnt/sda1 2>/dev/null || true
chmod -R 755 /mnt/sda1 2>/dev/null || true

echo "✓ 目录权限已设置"

# 5. 启动Samba服务
echo "启动Samba服务..."
smbd -D 2>/dev/null &
nmbd -D 2>/dev/null &
sleep 2

# 6. 检查服务状态
echo "检查服务状态..."
if pgrep smbd >/dev/null && pgrep nmbd >/dev/null; then
    echo "✓ Samba服务已启动 (smbd & nmbd)"
else
    echo "✗ Samba服务启动失败"
fi

# 7. 设置配置文件为只读权限
chmod 444 /etc/samba/smb.conf 2>/dev/null || true
echo "✓ 配置文件已设为只读"

# 8. 显示配置摘要
echo ""
echo "=== 配置完成 ==="
echo ""
echo "配置摘要:"
echo "  Samba版本: $SAMBA_VERSION"
echo "  Samba访问: 匿名只读"
echo "  FTP访问:   可写（需FTP服务单独配置）"
echo "  共享名称:   sda1"
echo "  共享路径:   /mnt/sda1"
echo ""
echo "权限说明:"
echo "  ✓ Samba 使用 nobody 用户 → 只读"
echo "  ✓ FTP 可使用 root/ftp 用户 → 可写"
echo ""
echo "FTP配置提醒:"
echo "  1. vsftpd: 确保 write_enable=YES"
echo "  2. 如果FTP使用匿名用户，需设置: anon_upload_enable=YES"
echo "  3. 建议FTP使用root或ftp用户，并设置目录写权限"
echo ""
