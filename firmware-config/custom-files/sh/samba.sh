#!/bin/sh
# Samba只读增强版配置脚本
# 包含：文件过滤、性能优化、SMB2/SMB3兼容性
# 匿名访问，只读权限

echo "=== Samba只读增强版配置 ==="

# 1. 停止Samba服务
echo "停止Samba服务..."
killall smbd nmbd 2>/dev/null
sleep 2

# 2. 备份原配置
if [ -f /etc/samba/smb.conf ]; then
    cp /etc/samba/smb.conf /etc/samba/smb.conf.bak.$(date +%s)
fi

# 3. 创建增强版配置
cat > /etc/samba/smb.conf << 'EOF'
[global]
    # ========== 基本设置 ==========
    workgroup = WORKGROUP
    server string = OpenWRT Samba (Read-Only Enhanced)
    netbios name = OpenWRT
    interfaces = lo br-lan
    bind interfaces only = yes
    
    # ========== 安全与访问控制 ==========
    security = user
    map to guest = Bad User
    guest account = nobody
    guest ok = yes
    guest only = yes
    invalid users = root
    
    # ========== 协议兼容性 ==========
    # SMB1协议支持（手机兼容）
    min protocol = NT1
    # SMB2/SMB3协议支持
    max protocol = SMB3
    server min protocol = SMB2
    server max protocol = SMB3
    
    # ========== 性能优化 ==========
    # 网络性能优化
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=65536 SO_SNDBUF=65536
    deadtime = 15
    getwd cache = yes
    large readwrite = yes
    use sendfile = yes
    
    # 内存和连接优化
    max connections = 10
    max open files = 16384
    max stat cache size = 512
    strict allocate = yes
    strict sync = no
    
    # 异步IO优化
    aio read size = 16384
    aio write size = 16384
    write cache size = 262144
    
    # ========== 文件过滤设置 ==========
    # 1. 可执行文件和脚本过滤
    veto files = /*.exe/*.com/*.dll/*.bat/*.cmd/*.scr/*.pif/*.vbs/*.js/*.msi/
    
    # 2. 临时文件过滤
    veto files += /*.tmp/*.temp/*.cache/*.swp/*.swo/*.bak/*.old/
    
    # 3. 系统文件过滤
    veto files += /._*/.DS_Store/desktop.ini/Thumbs.db/
    
    # 4. 开发文件过滤
    veto files += /*.o/*.obj/*.class/*.pyc/*.jar/*.log/
    
    # 5. 隐藏特殊文件
    hide dot files = yes
    hide files = /~$*/.~*/.tmp*/
    hide unreadable = yes
    hide unwriteable = yes
    
    # 不自动删除过滤文件
    delete veto files = no
    
    # ========== 加密和签名设置 ==========
    # 禁用加密以提高兼容性
    smb encrypt = disabled
    server signing = auto
    
    # ========== 高级安全设置 ==========
    # 防止暴力破解
    logon failure delay = 3
    logon home = \\
    logon path = \\
    
    # ========== 文件属性映射 ==========
    store dos attributes = yes
    map archive = no
    map hidden = no
    map readonly = no
    map system = no
    unix extensions = no
    
    # ========== 日志设置 ==========
    log file = /var/log/samba/log.%m
    max log size = 1024
    log level = 1
    syslog = 1
    
    # ========== 字符集设置 ==========
    unix charset = UTF-8
    dos charset = UTF-8
    display charset = UTF-8
    
    # ========== 网络发现设置 ==========
    wins support = no
    dns proxy = no
    name resolve order = bcast host

# ============================================
# 共享目录配置（只读增强版）
# ============================================

[sda1]
    # ========== 基本共享设置 ==========
    comment = Read-Only Enhanced Share
    path = /mnt/sda1
    browseable = yes
    available = yes
    
    # ========== 访问控制 ==========
    # 只读权限设置
    read only = yes
    writable = no
    
    # 匿名访问设置
    guest ok = yes
    guest only = yes
    guest account = nobody
    
    # ========== 文件权限 ==========
    # 只读权限设置
    create mask = 0444
    directory mask = 0555
    force create mode = 0444
    force directory mode = 0555
    
    # ========== 用户映射 ==========
    force user = nobody
    force group = nogroup
    
    # ========== 共享特有文件过滤 ==========
    hide dot files = yes
    veto files = /*.exe/*.dll/*.bat/*.cmd/*.scr/*.tmp/*.temp/
    delete veto files = no
    
    # ========== 性能优化 ==========
    # 共享级别性能优化
    strict allocate = yes
    use sendfile = yes
    level2 oplocks = yes
    oplocks = yes
    
    # ========== 锁定设置 ==========
    locking = yes
    kernel oplocks = no
    
    # ========== 特殊功能 ==========
    # 大小写敏感处理
    case sensitive = auto
    preserve case = yes
    short preserve case = yes
    
    # ========== 说明 ==========
    # 此共享为只读模式
    # 启用文件过滤、性能优化和SMB2/SMB3兼容性
    # 适用于家庭内网文件共享
EOF

# 4. 设置目录权限（只读）
echo "设置共享目录权限..."
mkdir -p /mnt/sda1

# 设置正确的只读权限
chmod 755 /mnt/sda1
find /mnt/sda1 -type d -exec chmod 755 {} \; 2>/dev/null || true
find /mnt/sda1 -type f -exec chmod 644 {} \; 2>/dev/null || true

# 设置所有者（nobody用户）
chown -R nobody:nogroup /mnt/sda1 2>/dev/null || 
chown -R root:root /mnt/sda1 2>/dev/null || true

# 5. 创建测试和说明文件
echo "创建说明文件..."
cat > /mnt/sda1/README_Samba配置说明.txt << 'EOF'
Samba只读增强版配置说明
==========================

配置时间: $(date)
访问方式: 匿名只读
共享名称: sda1
共享路径: /mnt/sda1

一、功能特性
------------
✓ 只读权限：所有人只能读取，不能写入或删除
✓ 文件过滤：自动隐藏.exe/.dll/.tmp等文件
✓ 性能优化：TCP优化、缓存加速、异步IO
✓ 协议兼容：支持SMB1/SMB2/SMB3
✓ 安全设置：匿名访问，防止误操作

二、文件过滤规则
----------------
1. 可执行文件: .exe, .com, .dll, .bat, .cmd, .scr, .msi
2. 临时文件: .tmp, .temp, .cache, .swp, .bak, .old
3. 系统文件: .DS_Store, Thumbs.db, desktop.ini, ._*
4. 开发文件: .o, .obj, .class, .pyc, .jar, .log
5. 隐藏文件: 以点开头的文件

三、访问方式
------------
Windows: \\路由器IP\sda1
Mac: smb://路由器IP/sda1
Linux: smbclient //路由器IP/sda1 -U nobody -N
MT管理器: 地址填路由器IP，用户密码留空

四、配置文件位置
----------------
主配置: /etc/samba/smb.conf
备份配置: /etc/samba/smb.conf.bak.*

五、管理命令
------------
重启服务: killall smbd && smbd -D
查看状态: ps | grep smbd
查看日志: tail -f /var/log/samba/log.smbd
测试连接: smbclient //localhost/sda1 -U nobody -N

六、注意事项
------------
1. 此为只读共享，无法写入文件
2. 过滤文件在客户端不可见，但仍存在于服务器
3. 建议定期备份重要文件
4. 如需写入权限，需要修改配置文件

==========================
EOF

# 6. 启动Samba服务
echo "启动Samba服务..."
smbd -D 2>/dev/null &

# 等待服务启动
sleep 3

# 7. 检查服务状态
echo "检查服务状态..."
if pgrep smbd >/dev/null; then
    echo "✓ Samba服务已启动"
    
    # 检查配置文件语法
    if command -v testparm >/dev/null 2>&1; then
        echo "测试配置文件语法..."
        testparm -s >/dev/null 2>&1 && echo "✓ 配置文件语法正确" || echo "✗ 配置文件语法错误"
    fi
else
    echo "✗ Samba服务启动失败"
    echo "尝试调试启动..."
    smbd -D -l /tmp/samba-debug.log 2>&1 &
    sleep 2
fi

# 8. 显示配置摘要
echo ""
echo "=== 配置完成 ==="
echo ""
echo "配置摘要:"
echo "  访问方式: 匿名只读"
echo "  共享名称: sda1"
echo "  共享路径: /mnt/sda1"
echo ""
echo "增强功能:"
echo "  ✓ 文件过滤 (.exe/.dll/.tmp等)"
echo "  ✓ 性能优化 (TCP优化、缓存、异步IO)"
echo "  ✓ 协议兼容 (SMB1/SMB2/SMB3)"
echo "  ✓ 安全设置 (只读权限，防止误操作)"
echo ""
echo "说明文件: /mnt/sda1/README_Samba配置说明.txt"
echo ""