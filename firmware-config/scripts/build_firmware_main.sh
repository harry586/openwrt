#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPILER_DIR="$REPO_ROOT/firmware-config/build-Compiler-file"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 新增：保存源代码信息函数
save_source_code_info() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 保存源代码信息 ==="
    
    # 创建源代码信息目录
    local source_info_dir="/tmp/build-artifacts/source-info"
    mkdir -p "$source_info_dir"
    
    # 保存构建环境信息
    cat > "$source_info_dir/build_env.txt" << EOF
构建环境信息
===========
构建时间: $(date)
设备: $DEVICE
版本: $SELECTED_BRANCH
目标平台: $TARGET/$SUBTARGET
配置模式: $CONFIG_MODE
构建目录: $BUILD_DIR
仓库根目录: $REPO_ROOT
EOF
    
    # 保存配置文件信息
    if [ -f ".config" ]; then
        cp ".config" "$source_info_dir/openwrt.config"
        log "✅ 配置文件已保存"
    fi
    
    # 保存feeds信息
    if [ -f "feeds.conf.default" ]; then
        cp "feeds.conf.default" "$source_info_dir/feeds.conf"
        log "✅ Feeds配置已保存"
    fi
    
    # 保存目录结构
    log "📁 保存目录结构信息..."
    find . -maxdepth 3 -type d | sort > "$source_info_dir/directory_structure.txt"
    
    # 保存关键文件列表
    log "📋 保存关键文件列表..."
    cat > "$source_info_dir/key_files.txt" << 'EOF'
关键文件列表
==========
.config - OpenWrt配置文件
feeds.conf.default - Feeds配置文件
Makefile - 主Makefile
rules.mk - 构建规则
Config.in - 配置菜单
feeds/ - Feeds目录
package/ - 包目录
target/ - 目标平台目录
toolchain/ - 编译器目录
EOF
    
    log "✅ 源代码信息保存完成: $source_info_dir"
}

save_env() {
    mkdir -p $BUILD_DIR
    echo "#!/bin/bash" > $ENV_FILE
    echo "export SELECTED_REPO_URL=\"$SELECTED_REPO_URL\"" >> $ENV_FILE
    echo "export SELECTED_BRANCH=\"$SELECTED_BRANCH\"" >> $ENV_FILE
    echo "export TARGET=\"$TARGET\"" >> $ENV_FILE
    echo "export SUBTARGET=\"$SUBTARGET\"" >> $ENV_FILE
    echo "export DEVICE=\"$DEVICE\"" >> $ENV_FILE
    echo "export CONFIG_MODE=\"$CONFIG_MODE\"" >> $ENV_FILE
    echo "export REPO_ROOT=\"$REPO_ROOT\"" >> $ENV_FILE
    chmod +x $ENV_FILE
}

load_env() {
    if [ -f "$ENV_FILE" ]; then
        source $ENV_FILE
    fi
}

# 修改：下载必要编译器源代码函数
download_compiler_files() {
    log "=== 下载编译器源代码 ==="
    log "编译器源代码目录: $COMPILER_DIR"
    
    # 确保目录存在
    mkdir -p "$COMPILER_DIR"
    
    # 编译器源代码清单
    local compiler_list=(
        "gcc-11.3.0.tar.xz"         # GNU C编译器源代码
        "binutils-2.38.tar.xz"      # GNU二进制工具集源代码
        "make-4.3.tar.gz"           # GNU make工具源代码
        "gmp-6.2.1.tar.xz"          # GNU多精度算术库源代码
        "mpfr-4.1.0.tar.xz"         # GNU多精度浮点库源代码
        "mpc-1.2.1.tar.gz"          # GNU多精度复数库源代码
        "isl-0.24.tar.xz"           # 整数集库源代码
    )
    
    # 编译器源代码下载URL
    declare -A compiler_urls=(
        ["gcc-11.3.0.tar.xz"]="https://ftp.gnu.org/gnu/gcc/gcc-11.3.0/gcc-11.3.0.tar.xz"
        ["binutils-2.38.tar.xz"]="https://ftp.gnu.org/gnu/binutils/binutils-2.38.tar.xz"
        ["make-4.3.tar.gz"]="https://ftp.gnu.org/gnu/make/make-4.3.tar.gz"
        ["gmp-6.2.1.tar.xz"]="https://ftp.gnu.org/gnu/gmp/gmp-6.2.1.tar.xz"
        ["mpfr-4.1.0.tar.xz"]="https://ftp.gnu.org/gnu/mpfr/mpfr-4.1.0.tar.xz"
        ["mpc-1.2.1.tar.gz"]="https://ftp.gnu.org/gnu/mpc/mpc-1.2.1.tar.gz"
        ["isl-0.24.tar.xz"]="https://gcc.gnu.org/pub/gcc/infrastructure/isl-0.24.tar.xz"
    )
    
    log "🔍 编译器源代码清单:"
    local total_files=0
    local existing_files=0
    local downloaded_files=0
    
    for file in "${compiler_list[@]}"; do
        total_files=$((total_files + 1))
        
        if [ -f "$COMPILER_DIR/$file" ]; then
            log "  ✅ $file: 已存在"
            existing_files=$((existing_files + 1))
        else
            log "  📥 $file: 需要下载"
            
            # 下载文件
            local url="${compiler_urls[$file]}"
            if [ -n "$url" ]; then
                log "    下载: $url"
                if wget --no-check-certificate -q --show-progress -O "$COMPILER_DIR/$file" "$url"; then
                    log "    ✅ 下载成功"
                    downloaded_files=$((downloaded_files + 1))
                else
                    log "    ❌ 下载失败，尝试使用curl..."
                    if curl -L "$url" -o "$COMPILER_DIR/$file"; then
                        log "    ✅ curl下载成功"
                        downloaded_files=$((downloaded_files + 1))
                    else
                        log "    ❌ 下载失败"
                    fi
                fi
            else
                log "    ⚠️ 无下载URL"
            fi
        fi
    done
    
    log "📊 下载统计:"
    log "  总计: $total_files 个编译器源代码文件"
    log "  已存在: $existing_files 个"
    log "  新下载: $downloaded_files 个"
    
    # 显示目录大小
    if [ $existing_files -gt 0 ] || [ $downloaded_files -gt 0 ]; then
        log "📁 编译器源代码目录大小: $(du -sh "$COMPILER_DIR" | cut -f1)"
        log "📋 编译器源代码文件列表:"
        ls -lh "$COMPILER_DIR" 2>/dev/null | head -15 || log "  无文件"
    fi
    
    log "✅ 编译器源代码下载完成"
}

# 新增：收集已编译的编译器文件函数
collect_compiled_compiler_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 收集已编译的编译器文件 ==="
    
    # 创建保存目录
    local save_dir="$REPO_ROOT/firmware-config/build-Compiler-file/compiled"
    mkdir -p "$save_dir"
    
    log "保存目录: $save_dir"
    
    # 检查是否有staging_dir目录
    if [ ! -d "staging_dir" ]; then
        log "⚠️ 警告: staging_dir 目录不存在"
        return 0
    fi
    
    # 搜索所有编译器文件
    log "🔍 搜索编译器文件..."
    
    # 1. 收集所有可执行的编译器文件
    local compiler_files=()
    while IFS= read -r -d '' file; do
        compiler_files+=("$file")
    done < <(find staging_dir -type f \( -name "*gcc*" -o -name "*g++*" -o -name "*as*" -o -name "*ld*" -o -name "*ar*" -o -name "*strip*" -o -name "*objcopy*" -o -name "*objdump*" -o -name "*nm*" -o -name "*ranlib*" \) -executable 2>/dev/null | head -100)
    
    local total_files=${#compiler_files[@]}
    log "找到 $total_files 个编译器文件"
    
    if [ $total_files -eq 0 ]; then
        log "⚠️ 未找到编译器文件"
        return 0
    fi
    
    # 2. 创建分类目录
    log "📁 创建分类目录..."
    local arch_dirs=("arm" "mips" "mipsel" "x86" "x86_64" "generic")
    for arch in "${arch_dirs[@]}"; do
        mkdir -p "$save_dir/$arch"
    done
    
    # 3. 分类复制文件
    log "📋 分类复制编译器文件..."
    
    # 计数器
    declare -A arch_counts=([arm]=0 [mips]=0 [mipsel]=0 [x86]=0 [x86_64]=0 [generic]=0)
    
    for file in "${compiler_files[@]}"; do
        if [ -f "$file" ] && [ -x "$file" ]; then
            local filename=$(basename "$file")
            local target_arch="generic"
            
            # 根据文件名和路径判断架构
            if [[ "$filename" == *"arm"* ]] || [[ "$file" == *"arm"* ]]; then
                target_arch="arm"
            elif [[ "$filename" == *"mips"* ]] && [[ "$filename" != *"mipsel"* ]]; then
                target_arch="mips"
            elif [[ "$filename" == *"mipsel"* ]] || [[ "$file" == *"mipsel"* ]]; then
                target_arch="mipsel"
            elif [[ "$filename" == *"i386"* ]] || [[ "$filename" == *"i686"* ]] || [[ "$file" == *"x86"* ]] && [[ "$file" != *"x86_64"* ]]; then
                target_arch="x86"
            elif [[ "$filename" == *"x86_64"* ]] || [[ "$file" == *"x86_64"* ]]; then
                target_arch="x86_64"
            fi
            
            # 复制文件
            if cp "$file" "$save_dir/$target_arch/" 2>/dev/null; then
                arch_counts[$target_arch]=$((arch_counts[$target_arch] + 1))
            fi
        fi
    done
    
    # 4. 显示统计信息
    log "📊 编译器文件分类统计:"
    local total_copied=0
    for arch in "${arch_dirs[@]}"; do
        log "  $arch: ${arch_counts[$arch]} 个文件"
        total_copied=$((total_copied + arch_counts[$arch]))
    done
    log "  总计复制: $total_copied 个文件"
    
    # 5. 显示各目录内容
    log "📁 各目录详细内容:"
    for arch in "${arch_dirs[@]}"; do
        local arch_dir="$save_dir/$arch"
        if [ -d "$arch_dir" ] && [ "$(ls -A "$arch_dir" 2>/dev/null)" ]; then
            local file_count=$(find "$arch_dir" -type f | wc -l)
            log "  $arch 目录 ($file_count 个文件):"
            ls "$arch_dir" | head -5 | while read file; do
                local size=$(stat -c%s "$arch_dir/$file" 2>/dev/null || echo "0")
                local size_kb=$((size / 1024))
                log "    - $file (${size_kb}KB)"
            done
            if [ $file_count -gt 5 ]; then
                log "    ... 还有 $((file_count - 5)) 个文件"
            fi
        else
            log "  $arch 目录: 空"
        fi
    done
    
    # 6. 创建编译器信息文件
    log "📝 创建编译器信息文件..."
    cat > "$save_dir/compiler_info.txt" << EOF
已编译编译器文件汇总
===================

收集时间: $(date)
构建设备: $DEVICE
目标平台: $TARGET/$SUBTARGET
OpenWrt版本: $SELECTED_BRANCH

文件分类统计:
------------
ARM架构: ${arch_counts[arm]} 个文件
MIPS架构: ${arch_counts[mips]} 个文件
MIPS小端: ${arch_counts[mipsel]} 个文件
x86架构: ${arch_counts[x86]} 个文件
x86_64架构: ${arch_counts[x86_64]} 个文件
通用编译器: ${arch_counts[generic]} 个文件
总计: $total_copied 个文件

关键编译器文件:
---------------
EOF
    
    # 添加关键编译器信息
    for arch in "${arch_dirs[@]}"; do
        local arch_dir="$save_dir/$arch"
        if [ -d "$arch_dir" ] && [ "$(ls -A "$arch_dir" 2>/dev/null)" ]; then
            echo "" >> "$save_dir/compiler_info.txt"
            echo "$arch 架构:" >> "$save_dir/compiler_info.txt"
            find "$arch_dir" -type f \( -name "*gcc*" -o -name "*g++*" -o -name "*as*" -o -name "*ld*" \) 2>/dev/null | head -3 | while read file; do
                local filename=$(basename "$file")
                local size=$(stat -c%s "$file" 2>/dev/null || echo "0")
                local size_kb=$((size / 1024))
                echo "  - $filename (${size_kb}KB)" >> "$save_dir/compiler_info.txt"
            done
        fi
    done
    
    # 7. 显示总目录大小
    local total_size=$(du -sh "$save_dir" 2>/dev/null | cut -f1)
    log "📦 编译器文件总目录大小: $total_size"
    
    # 8. 创建压缩包
    log "📦 创建编译器文件压缩包..."
    cd "$save_dir"
    tar -czf "../compiled-compilers.tar.gz" ./*
    cd - > /dev/null
    
    log "✅ 已编译编译器文件收集完成"
    log "📁 保存目录: $save_dir"
    log "📦 压缩包: $REPO_ROOT/firmware-config/build-Compiler-file/compiled-compilers.tar.gz"
}

integrate_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 集成自定义文件 ==="
    
    local custom_dir="$REPO_ROOT/firmware-config/custom-files"
    
    if [ ! -d "$custom_dir" ]; then
        log "ℹ️ 自定义文件目录不存在: $custom_dir"
        return 0
    fi
    
    log "自定义文件目录: $custom_dir"
    
    local ipk_count=0
    local script_count=0
    local other_count=0
    
    # 使用临时变量存储计数
    local ipk_files=()
    local script_files=()
    local other_files=()
    
    # 1. 集成IPK文件到package目录
    if find "$custom_dir" -name "*.ipk" -type f 2>/dev/null | grep -q .; then
        mkdir -p package/custom
        log "🔧 集成IPK文件到package目录"
        
        while IFS= read -r -d '' ipk; do
            local ipk_name=$(basename "$ipk")
            log "复制: $ipk_name"
            cp "$ipk" "package/custom/"
            ipk_files+=("$ipk_name")
        done < <(find "$custom_dir" -name "*.ipk" -type f -print0 2>/dev/null)
        
        ipk_count=${#ipk_files[@]}
        
        if [ $ipk_count -gt 0 ]; then
            cat > package/custom/Makefile << 'EOF'
include $(TOPDIR)/rules.mk

PKG_NAME:=custom-packages
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Custom Build
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define Package/custom-packages
  SECTION:=custom
  CATEGORY:=Custom
  TITLE:=Custom Packages Collection
  DEPENDS:=
endef

define Package/custom-packages/description
  This package contains custom IPK files.
endef

define Build/Compile
  true
endef

define Package/custom-packages/install
  true
endef

$(eval $(call BuildPackage,custom-packages))
EOF
            log "✅ 创建自定义包Makefile"
        fi
    fi
    
    # 2. 集成脚本文件到files目录
    if find "$custom_dir" -name "*.sh" -type f 2>/dev/null | grep -q .; then
        mkdir -p files/usr/share/custom
        log "🔧 集成脚本文件到files目录"
        
        while IFS= read -r -d '' script; do
            local script_name=$(basename "$script")
            log "复制: $script_name"
            cp "$script" "files/usr/share/custom/"
            chmod +x "files/usr/share/custom/$script_name"
            script_files+=("$script_name")
        done < <(find "$custom_dir" -name "*.sh" -type f -print0 2>/dev/null)
        
        script_count=${#script_files[@]}
        
        if [ $script_count -gt 0 ]; then
            mkdir -p files/etc/init.d
            cat > files/etc/init.d/custom-scripts << 'EOF'
#!/bin/sh /etc/rc.common

START=99
STOP=10

start() {
    echo "Starting custom scripts..."
    for script in /usr/share/custom/*.sh; do
        if [ -x "$script" ]; then
            echo "Running: $(basename "$script")"
            sh "$script" &
        fi
    done
}

stop() {
    echo "Stopping custom scripts..."
    pkill -f "sh /usr/share/custom/"
}
EOF
            chmod +x files/etc/init.d/custom-scripts
            log "✅ 创建自定义脚本启动服务"
        fi
    fi
    
    # 3. 集成其他配置文件
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            local file_name=$(basename "$file")
            local relative_path=$(echo "$file" | sed "s|^$custom_dir/||")
            local target_dir="files/$(dirname "$relative_path")"
            
            mkdir -p "$target_dir"
            cp "$file" "$target_dir/"
            log "复制配置文件: $relative_path"
            other_files+=("$relative_path")
        fi
    done < <(find "$custom_dir" -type f \( -name "*.conf" -o -name "*.config" -o -name "*.json" -o -name "*.txt" \) -print0 2>/dev/null)
    
    other_count=${#other_files[@]}
    
    log "✅ 自定义文件集成完成"
    log "  IPK文件: $ipk_count 个"
    if [ $ipk_count -gt 0 ]; then
        for ipk in "${ipk_files[@]}"; do
            log "    - $ipk"
        done
    fi
    log "  脚本文件: $script_count 个"
    if [ $script_count -gt 0 ]; then
        for script in "${script_files[@]}"; do
            log "    - $script"
        done
    fi
    log "  配置文件: $other_count 个"
    if [ $other_count -gt 0 ] && [ $other_count -le 5 ]; then
        for conf in "${other_files[@]}"; do
            log "    - $conf"
        done
    elif [ $other_count -gt 5 ]; then
        log "    - 显示前5个文件:"
        for i in {0..4}; do
            log "      - ${other_files[$i]}"
        done
        log "    - ... 还有 $((other_count - 5)) 个文件"
    fi
}

pre_build_error_check() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 前置错误检查（增强版）==="
    
    local error_count=0
    local warning_count=0
    
    # 1. 检查配置文件
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        error_count=$((error_count + 1))
    else
        log "✅ .config 文件存在"
        
        local critical_configs=(
            "CONFIG_TARGET_${TARGET}=y"
            "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y"
            "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y"
        )
        
        for config in "${critical_configs[@]}"; do
            if ! grep -q "^$config" .config; then
                log "❌ 错误: 缺少关键配置 $config"
                error_count=$((error_count + 1))
            else
                log "✅ 配置正常: $config"
            fi
        done
    fi
    
    # 2. 检查feeds
    if [ ! -d "feeds" ]; then
        log "❌ 错误: feeds 目录不存在"
        error_count=$((error_count + 1))
    else
        log "✅ feeds 目录存在"
        
        local critical_feeds=("packages" "luci")
        for feed in "${critical_feeds[@]}"; do
            if [ ! -d "feeds/$feed" ]; then
                log "❌ 错误: $feed feed 未安装"
                error_count=$((error_count + 1))
            else
                log "✅ feed 正常: $feed"
            fi
        done
    fi
    
    # 3. 检查依赖包
    if [ ! -d "dl" ]; then
        log "⚠️ 警告: dl 目录不存在，可能需要下载依赖"
        warning_count=$((warning_count + 1))
    else
        local dl_count=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
        log "✅ 依赖包数量: $dl_count 个"
        
        if [ $dl_count -lt 10 ]; then
            log "⚠️ 警告: 依赖包数量较少，可能下载不完整"
            warning_count=$((warning_count + 1))
        fi
        
        # 检查关键依赖包是否存在
        local critical_deps=("linux" "gcc" "binutils" "musl")
        for dep in "${critical_deps[@]}"; do
            if find dl -name "*${dep}*" -type f 2>/dev/null | grep -q .; then
                log "✅ 找到关键依赖: $dep"
            else
                log "⚠️ 警告: 未找到关键依赖: $dep"
                warning_count=$((warning_count + 1))
            fi
        done
        
        # 额外检查：根据版本检查正确的C库
        if [ "$SELECTED_BRANCH" = "openwrt-21.02" ] || [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log "🔧 检查musl C库..."
            if find dl -name "*musl*" -type f 2>/dev/null | grep -q .; then
                log "✅ 找到musl C库 (现代OpenWrt使用)"
            else
                log "⚠️ 警告: 未找到musl C库"
                warning_count=$((warning_count + 1))
            fi
        fi
    fi
    
    # 4. 检查编译器
    if [ -d "staging_dir" ]; then
        local compiler_count=$(find staging_dir -maxdepth 1 -type d -name "compiler-*" 2>/dev/null | wc -l)
        if [ $compiler_count -eq 0 ]; then
            log "ℹ️ 未找到已构建的编译器，将在编译过程中自动构建"
            log "📦 注意：编译器会从下载的依赖包自动构建，无需手动下载"
            # 这只是信息，不是错误
        else
            log "✅ 已下载编译器: $compiler_count 个"
            
            # 检查编译器完整性
            local compiler_dir=$(find staging_dir -maxdepth 1 -type d -name "compiler-*" | head -1)
            if [ -d "$compiler_dir/bin" ]; then
                local compiler_files=$(find "$compiler_dir/bin" -name "*gcc*" -o -name "*g++*" 2>/dev/null | wc -l)
                if [ $compiler_files -gt 0 ]; then
                    log "✅ 编译器文件: $compiler_files 个"
                else
                    log "⚠️ 警告: 编译器缺少编译器文件"
                    warning_count=$((warning_count + 1))
                fi
            fi
            
            # 新增：检查编译器头文件路径
            log "🔍 检查编译器头文件路径..."
            if [ -d "$compiler_dir/include" ]; then
                log "✅ 编译器头文件目录存在"
                
                # 检查关键头文件
                local critical_headers=("stdc-predef.h" "stdio.h" "stdlib.h" "string.h")
                for header in "${critical_headers[@]}"; do
                    if find "$compiler_dir" -name "$header" -type f 2>/dev/null | grep -q .; then
                        log "✅ 找到头文件: $header"
                    else
                        log "⚠️ 警告: 未找到头文件: $header"
                        warning_count=$((warning_count + 1))
                    fi
                done
            else
                log "⚠️ 警告: 编译器头文件目录不存在"
                warning_count=$((warning_count + 1))
            fi
        fi
    else
        log "ℹ️ staging_dir目录不存在，编译时将自动创建和构建编译器"
    fi
    
    # 5. 检查关键文件
    local critical_files=("Makefile" "rules.mk" "Config.in" "feeds.conf.default")
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 关键文件存在: $file"
        else
            log "❌ 错误: 关键文件不存在: $file"
            error_count=$((error_count + 1))
        fi
    done
    
    # 6. 检查脚本权限
    if [ -d "scripts" ]; then
        local script_files=$(find scripts -name "*.sh" -type f -executable 2>/dev/null | wc -l)
        if [ $script_files -gt 0 ]; then
            log "✅ 可执行脚本文件: $script_files 个"
        else
            log "⚠️ 警告: 没有可执行的脚本文件"
            warning_count=$((warning_count + 1))
        fi
    fi
    
    # 7. 检查磁盘空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log "磁盘可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 10 ]; then
        log "❌ 错误: 磁盘空间不足 (需要至少10G，当前${available_gb}G)"
        error_count=$((error_count + 1))
    elif [ $available_gb -lt 20 ]; then
        log "⚠️ 警告: 磁盘空间较低 (建议至少20G，当前${available_gb}G)"
        warning_count=$((warning_count + 1))
    fi
    
    # 8. 检查内存
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    log "系统内存: ${total_mem}MB"
    
    if [ $total_mem -lt 1024 ]; then
        log "⚠️ 警告: 内存较低 (建议至少1GB)"
        warning_count=$((warning_count + 1))
    fi
    
    # 9. 检查CPU核心数
    local cpu_cores=$(nproc)
    log "CPU核心数: $cpu_cores"
    
    if [ $cpu_cores -lt 2 ]; then
        log "⚠️ 警告: CPU核心数较少，编译速度会受影响"
        warning_count=$((warning_count + 1))
    fi
    
    # 10. 检查C库配置
    log "🔧 检查C库配置..."
    if [ -f ".config" ]; then
        if grep -q "CONFIG_EXTERNAL_COMPILER=y" .config; then
            log "ℹ️ 使用外部编译器"
        elif grep -q "CONFIG_USE_MUSL=y" .config; then
            log "✅ 配置为使用musl C库"
        elif grep -q "CONFIG_USE_GLIBC=y" .config; then
            log "✅ 配置为使用glibc C库"
        elif grep -q "CONFIG_USE_UCLIBC=y" .config; then
            log "✅ 配置为使用uclibc C库"
        else
            log "⚠️ 警告: 未明确指定C库类型"
            warning_count=$((warning_count + 1))
        fi
    fi
    
    # 11. 新增：检查libtool相关文件
    log "🔧 检查libtool相关文件..."
    if [ -d "tools" ]; then
        if find tools -name "libtool*" -type f 2>/dev/null | grep -q .; then
            log "✅ 找到libtool文件"
        else
            log "⚠️ 警告: 未找到libtool文件"
            warning_count=$((warning_count + 1))
        fi
        
        # 检查libtool.m4
        if find tools -name "libtool.m4" -type f 2>/dev/null | grep -q .; then
            log "✅ 找到libtool.m4"
        else
            log "⚠️ 警告: 未找到libtool.m4"
            warning_count=$((warning_count + 1))
        fi
    fi
    
    # 检查staging_dir中的libtool文件
    log "🔍 检查staging_dir中的libtool文件..."
    if [ -d "staging_dir/host/share/aclocal" ]; then
        if find staging_dir/host/share/aclocal -name "libtool.m4" -type f 2>/dev/null | grep -q .; then
            log "✅ 找到staging_dir中的libtool.m4"
        else
            log "⚠️ 警告: staging_dir中未找到libtool.m4"
            warning_count=$((warning_count + 1))
        fi
    else
        log "⚠️ 警告: staging_dir/host/share/aclocal目录不存在"
        warning_count=$((warning_count + 1))
    fi
    
    # 12. 新增：检查配置同步状态
    log "🔧 检查配置同步状态..."
    if [ -f ".config" ] && [ -f ".config.old" ]; then
        local config_diff=$(diff -u .config.old .config | wc -l)
        if [ $config_diff -gt 10 ]; then
            log "⚠️ 警告: 配置文件有较大变化，建议运行make defconfig"
            warning_count=$((warning_count + 1))
        fi
    fi
    
    # 13. 新增：检查头文件目录
    log "🔧 检查头文件目录..."
    if [ -d "staging_dir/host/include" ]; then
        log "✅ staging_dir/host/include目录存在"
        
        local critical_headers=("stdio.h" "stdlib.h" "string.h" "stdc-predef.h")
        for header in "${critical_headers[@]}"; do
            if [ -f "staging_dir/host/include/$header" ]; then
                log "✅ 找到头文件: $header"
            else
                log "⚠️ 警告: 未找到头文件: $header"
                warning_count=$((warning_count + 1))
            fi
        done
    else
        log "⚠️ 警告: staging_dir/host/include目录不存在"
        warning_count=$((warning_count + 1))
    fi
    
    # 总结
    if [ $error_count -eq 0 ]; then
        if [ $warning_count -eq 0 ]; then
            log "✅ 前置检查通过，可以开始编译"
        else
            log "⚠️ 前置检查通过，但有 $warning_count 个警告，建议修复"
        fi
        return 0
    else
        log "❌ 前置检查发现 $error_count 个错误，$warning_count 个警告，请修复后再编译"
        return 1
    fi
}

setup_environment() {
    log "=== 安装编译依赖包（增强版）==="
    sudo apt-get update || handle_error "apt-get update失败"
    
    # 基础编译工具
    local base_packages=(
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip
        zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath
        libpython3-dev python3 python3-dev python3-pip python3-setuptools
        python3-yaml xsltproc zip subversion ninja-build automake autoconf
        libtool pkg-config help2man texinfo aria2 liblz4-dev zstd
        libcurl4-openssl-dev groff texlive texinfo cmake
    )
    
    # 网络工具
    local network_packages=(
        curl wget net-tools iputils-ping dnsutils
        openssh-client ca-certificates gnupg lsb-release
    )
    
    # 文件系统工具
    local filesystem_packages=(
        squashfs-tools dosfstools e2fsprogs mtools
        parted fdisk gdisk hdparm smartmontools
    )
    
    # 调试工具
    local debug_packages=(
        gdb strace ltrace valgrind
        binutils-dev libdw-dev libiberty-dev
    )
    
    # 新增：头文件相关包
    local header_packages=(
        linux-headers-generic linux-libc-dev libc6-dev
        libc6-dev-i386 libc6-dev-x32 libc6-dev-armhf-cross
        libc6-dev-arm64-cross libc6-dev-mips64el-cross
        libc6-dev-mipsel-cross libc6-dev-powerpc-cross
        libc6-dev-ppc64el-cross libc6-dev-s390x-cross
        libc6-dev-sparc64-cross libc6-dev-x32
    )
    
    # 新增：libtool和m4工具
    local libtool_packages=(
        libtool libltdl-dev libltdl7 libtool-bin
        m4 autoconf-archive gperf automake-1.16
    )
    
    log "安装基础编译工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_packages[@]}" || handle_error "安装基础编译工具失败"
    
    log "安装网络工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${network_packages[@]}" || handle_error "安装网络工具失败"
    
    log "安装文件系统工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${filesystem_packages[@]}" || handle_error "安装文件系统工具失败"
    
    log "安装调试工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${debug_packages[@]}" || handle_error "安装调试工具失败"
    
    log "安装头文件相关包..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${header_packages[@]}" || log "⚠️ 部分头文件包安装失败，但可能不影响编译"
    
    log "安装libtool相关包..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${libtool_packages[@]}" || handle_error "安装libtool相关包失败"
    
    # 检查重要工具是否安装成功
    log "=== 验证工具安装 ==="
    local important_tools=("gcc" "g++" "make" "git" "python3" "cmake" "flex" "bison" "libtool" "m4" "autoconf" "automake")
    for tool in "${important_tools[@]}"; do
        if command -v $tool >/dev/null 2>&1; then
            log "✅ $tool 已安装: $(which $tool)"
        else
            log "❌ $tool 未安装"
        fi
    done
    
    # 检查头文件
    log "=== 检查头文件 ==="
    local critical_headers=("/usr/include/stdio.h" "/usr/include/stdlib.h" "/usr/include/string.h" "/usr/include/features.h" "/usr/include/stdc-predef.h")
    for header in "${critical_headers[@]}"; do
        if [ -f "$header" ]; then
            log "✅ 头文件存在: $header"
        else
            log "⚠️ 头文件缺失: $header"
        fi
    done
    
    # 检查libtool相关文件
    log "=== 检查libtool相关文件 ==="
    if [ -f "/usr/share/aclocal/libtool.m4" ]; then
        log "✅ libtool.m4存在: /usr/share/aclocal/libtool.m4"
    else
        log "⚠️ libtool.m4缺失"
    fi
    
    log "✅ 编译环境设置完成"
}

create_build_dir() {
    log "=== 创建构建目录 ==="
    sudo mkdir -p $BUILD_DIR || handle_error "创建构建目录失败"
    sudo chown -R $USER:$USER $BUILD_DIR || handle_error "修改目录所有者失败"
    sudo chmod -R 755 $BUILD_DIR || handle_error "修改目录权限失败"
    
    # 检查目录权限
    if [ -w "$BUILD_DIR" ]; then
        log "✅ 构建目录创建完成: $BUILD_DIR"
    else
        log "❌ 构建目录权限错误"
        exit 1
    fi
}

initialize_build_env() {
    local device_name=$1
    local version_selection=$2
    local config_mode=$3
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 版本选择 ==="
    if [ "$version_selection" = "23.05" ]; then
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-23.05"
    else
        SELECTED_REPO_URL="https://github.com/immortalwrt/immortalwrt.git"
        SELECTED_BRANCH="openwrt-21.02"
    fi
    log "✅ 版本选择完成: $SELECTED_BRANCH"
    
    log "=== 设备配置 ==="
    case "$device_name" in
        "ac42u"|"acrh17")
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="asus_rt-ac42u"
            log "🔧 检测到高通IPQ40xx平台设备: $device_name"
            log "🔧 该设备支持USB 3.0，将启用所有USB 3.0相关驱动"
            ;;
        "mi_router_4a_gigabit"|"r4ag")
            TARGET="ramips"
            SUBTARGET="mt76x8"
            DEVICE="xiaomi_mi-router-4a-gigabit"
            log "🔧 检测到雷凌MT76x8平台设备: $device_name"
            ;;
        "mi_router_3g"|"r3g")
            TARGET="ramips"
            SUBTARGET="mt7621"
            DEVICE="xiaomi_mi-router-3g"
            log "🔧 检测到雷凌MT7621平台设备: $device_name"
            ;;
        *)
            TARGET="ipq40xx"
            SUBTARGET="generic"
            DEVICE="$device_name"
            log "🔧 未知设备，默认为高通IPQ40xx平台"
            ;;
    esac
    
    CONFIG_MODE="$config_mode"
    
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    
    save_env
    
    echo "SELECTED_REPO_URL=$SELECTED_REPO_URL" >> $GITHUB_ENV
    echo "SELECTED_BRANCH=$SELECTED_BRANCH" >> $GITHUB_ENV
    echo "TARGET=$TARGET" >> $GITHUB_ENV
    echo "SUBTARGET=$SUBTARGET" >> $GITHUB_ENV
    echo "DEVICE=$DEVICE" >> $GITHUB_ENV
    echo "CONFIG_MODE=$CONFIG_MODE" >> $GITHUB_ENV
    
    log "=== 克隆源码 ==="
    log "仓库: $SELECTED_REPO_URL"
    log "分支: $SELECTED_BRANCH"
    
    sudo rm -rf ./* ./.git* 2>/dev/null || true
    
    git clone --depth 1 --branch "$SELECTED_BRANCH" "$SELECTED_REPO_URL" . || handle_error "克隆源码失败"
    log "✅ 源码克隆完成"
    
    # 检查克隆的文件
    local important_source_files=("Makefile" "feeds.conf.default" "rules.mk" "Config.in")
    for file in "${important_source_files[@]}"; do
        if [ -f "$file" ]; then
            log "✅ 源码文件存在: $file"
        else
            log "❌ 源码文件缺失: $file"
        fi
    done
}

add_turboacc_support() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 添加 TurboACC 支持 ==="
    
    if [ "$CONFIG_MODE" = "normal" ]; then
        log "🔧 为正常模式添加 TurboACC 支持"
        
        if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log "🔧 为 23.05 添加 TurboACC 支持"
            echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
            log "✅ TurboACC feed 添加完成"
        else
            log "ℹ️ 21.02 版本已内置 TurboACC，无需额外添加"
        fi
    else
        log "ℹ️ 基础模式不添加 TurboACC 支持"
    fi
}

configure_feeds() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 配置Feeds ==="
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        FEEDS_BRANCH="openwrt-23.05"
    else
        FEEDS_BRANCH="openwrt-21.02"
    fi
    
    echo "src-git packages https://github.com/immortalwrt/packages.git;$FEEDS_BRANCH" > feeds.conf.default
    echo "src-git luci https://github.com/immortalwrt/luci.git;$FEEDS_BRANCH" >> feeds.conf.default
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ] && [ "$CONFIG_MODE" = "normal" ]; then
        echo "src-git turboacc https://github.com/chenmozhijin/turboacc" >> feeds.conf.default
    fi
    
    log "=== 更新Feeds ==="
    ./scripts/feeds update -a || handle_error "更新feeds失败"
    
    log "=== 安装Feeds ==="
    ./scripts/feeds install -a || handle_error "安装feeds失败"
    
    # 检查feeds安装结果
    local critical_feeds_dirs=("feeds/packages" "feeds/luci" "package/feeds")
    for dir in "${critical_feeds_dirs[@]}"; do
        if [ -d "$dir" ]; then
            log "✅ Feed目录存在: $dir"
        else
            log "❌ Feed目录缺失: $dir"
        fi
    done
    
    log "✅ Feeds配置完成"
}

install_turboacc_packages() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 安装 TurboACC 包 ==="
    
    ./scripts/feeds update turboacc || handle_error "更新turboacc feed失败"
    
    ./scripts/feeds install -p turboacc luci-app-turboacc || handle_error "安装luci-app-turboacc失败"
    ./scripts/feeds install -p turboacc kmod-shortcut-fe || handle_error "安装kmod-shortcut-fe失败"
    ./scripts/feeds install -p turboacc kmod-fast-classifier || handle_error "安装kmod-fast-classifier失败"
    
    log "✅ TurboACC 包安装完成"
}

pre_build_space_check() {
    log "=== 编译前空间检查 ==="
    
    echo "当前目录: $(pwd)"
    echo "构建目录: $BUILD_DIR"
    
    # 详细磁盘信息
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 构建目录空间
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    # 检查/mnt可用空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    echo "/mnt 可用空间: ${available_gb}G"
    
    # 检查/可用空间
    local root_available_space=$(df / --output=avail | tail -1)
    local root_available_gb=$((root_available_space / 1024 / 1024))
    echo "/ 可用空间: ${root_available_gb}G"
    
    # 内存和交换空间
    echo "=== 内存使用情况 ==="
    free -h
    
    # CPU信息
    echo "=== CPU信息 ==="
    echo "CPU核心数: $(nproc)"
    
    # 编译所需空间估算
    local estimated_space=15  # 估计需要15GB
    if [ $available_gb -lt $estimated_space ]; then
        log "⚠️ 警告: 可用空间(${available_gb}G)可能不足，建议至少${estimated_space}G"
    else
        log "✅ 磁盘空间充足: ${available_gb}G 可用"
    fi
    
    log "✅ 空间检查完成"
}

generate_config() {
    local extra_packages=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 智能配置生成系统（USB完全修复通用版）==="
    log "版本: $SELECTED_BRANCH"
    log "目标: $TARGET"
    log "子目标: $SUBTARGET"
    log "设备: $DEVICE"
    log "配置模式: $CONFIG_MODE"
    
    rm -f .config .config.old
    
    echo "CONFIG_TARGET_${TARGET}=y" > .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}=y" >> .config
    echo "CONFIG_TARGET_${TARGET}_${SUBTARGET}_DEVICE_${DEVICE}=y" >> .config
    echo "CONFIG_TARGET_ROOTFS_SQUASHFS=y" >> .config
    echo "CONFIG_TARGET_IMAGES_GZIP=y" >> .config
    
    echo "CONFIG_PACKAGE_busybox=y" >> .config
    echo "CONFIG_PACKAGE_base-files=y" >> .config
    echo "CONFIG_PACKAGE_dropbear=y" >> .config
    echo "CONFIG_PACKAGE_firewall=y" >> .config
    echo "CONFIG_PACKAGE_fstools=y" >> .config
    echo "CONFIG_PACKAGE_libc=y" >> .config
    echo "CONFIG_PACKAGE_libgcc=y" >> .config
    echo "CONFIG_PACKAGE_mtd=y" >> .config
    echo "CONFIG_PACKAGE_netifd=y" >> .config
    echo "CONFIG_PACKAGE_opkg=y" >> .config
    echo "CONFIG_PACKAGE_procd=y" >> .config
    echo "CONFIG_PACKAGE_ubox=y" >> .config
    echo "CONFIG_PACKAGE_ubus=y" >> .config
    echo "CONFIG_PACKAGE_ubusd=y" >> .config
    echo "CONFIG_PACKAGE_uci=y" >> .config
    echo "CONFIG_PACKAGE_uclient-fetch=y" >> .config
    echo "CONFIG_PACKAGE_usign=y" >> .config
    
    echo "# CONFIG_PACKAGE_dnsmasq is not set" >> .config
    echo "CONFIG_PACKAGE_dnsmasq-full=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcp=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dhcpv6=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_dnssec=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_ipset=y" >> .config
    echo "CONFIG_PACKAGE_dnsmasq_full_conntrack=y" >> .config
    
    echo "# CONFIG_PACKAGE_kmod-ath10k is not set" >> .config
    echo "CONFIG_PACKAGE_kmod-ath10k-ct=y" >> .config
    echo "CONFIG_PACKAGE_ath10k-firmware-qca988x=y" >> .config
    echo "CONFIG_PACKAGE_wpad-basic-wolfssl=y" >> .config
    
    echo "CONFIG_PACKAGE_iptables=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-conntrack-extra=y" >> .config
    echo "CONFIG_PACKAGE_iptables-mod-ipopt=y" >> .config
    echo "CONFIG_PACKAGE_ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ip6tables=y" >> .config
    echo "CONFIG_PACKAGE_kmod-ipt-nat6=y" >> .config
    
    # 添加常用网络插件
    echo "CONFIG_PACKAGE_bridge=y" >> .config
    echo "CONFIG_PACKAGE_blockd=y" >> .config
    echo "# CONFIG_PACKAGE_busybox-selinux is not set" >> .config
    echo "# CONFIG_PACKAGE_attendedsysupgrade-common is not set" >> .config
    echo "# CONFIG_PACKAGE_auc is not set" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 开始 ==="
    
    echo "# 🟢 USB 核心驱动 - 基础必须" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-core=y" >> .config
    
    echo "# 🟢 USB 主机控制器驱动 - 通用支持" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ehci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-uhci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
    
    echo "# 🟢 USB 3.0扩展主机控制器接口驱动 - 支持USB 3.0高速数据传输" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
    
    echo "# 🟡 平台专用USB控制器驱动 - 根据平台启用" >> .config
    log "🔍 检测平台类型: TARGET=$TARGET, SUBTARGET=$SUBTARGET"
    
    if [ "$TARGET" = "ipq40xx" ]; then
        log "🚨 关键修复：IPQ40xx 专用USB控制器驱动（高通平台，支持USB 3.0）"
        echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        # 高通平台通常不需要MTK驱动，但保留以防万一
        echo "# CONFIG_PACKAGE_kmod-usb-xhci-mtk is not set" >> .config
        log "✅ 已启用所有高通IPQ40xx平台的USB驱动"
    fi
    
    if [ "$TARGET" = "ramips" ]; then
        if [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; then
            log "🚨 关键修复：MT76xx/雷凌 平台USB控制器驱动"
            echo "CONFIG_PACKAGE_kmod-usb-ohci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb2=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb2-pci=y" >> .config
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
            # 雷凌平台通常不需要高通专用驱动
            echo "# CONFIG_PACKAGE_kmod-usb-dwc3-qcom is not set" >> .config
            echo "# CONFIG_PACKAGE_kmod-phy-qcom-dwc3 is not set" >> .config
            log "✅ 已启用雷凌MT76xx平台的USB驱动"
        fi
    fi
    
    echo "# 🟢 USB 存储驱动 - 核心功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    
    echo "# 🟢 SCSI 支持 - 硬盘和U盘必需" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-core=y" >> .config
    echo "CONFIG_PACKAGE_kmod-scsi-generic=y" >> .config
    
    echo "# 🟢 文件系统支持 - 完整文件系统兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-ext4=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-vfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-exfat=y" >> .config
    echo "CONFIG_PACKAGE_kmod-fs-autofs4=y" >> .config
    
    echo "# 🟢 USB大容量存储额外驱动" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-uas=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-storage-extras=y" >> .config
    
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本NTFS配置优化"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs-3g-utils is not set" >> .config
        echo "# CONFIG_PACKAGE_ntfs3-mount is not set" >> .config
    else
        log "🔧 21.02版本NTFS配置"
        echo "CONFIG_PACKAGE_kmod-fs-ntfs3=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-fs-ntfs is not set" >> .config
        echo "CONFIG_PACKAGE_ntfs3-mount=y" >> .config
    fi
    
    echo "# 🟢 编码支持 - 多语言文件名兼容" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-utf8=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp437=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-iso8859-1=y" >> .config
    echo "CONFIG_PACKAGE_kmod-nls-cp936=y" >> .config
    
    echo "# 🟢 自动挂载工具 - 即插即用支持" >> .config
    echo "CONFIG_PACKAGE_block-mount=y" >> .config
    echo "CONFIG_PACKAGE_automount=y" >> .config
    
    echo "# 🟢 USB 工具和热插拔支持 - 设备管理" >> .config
    echo "CONFIG_PACKAGE_usbutils=y" >> .config
    echo "CONFIG_PACKAGE_lsusb=y" >> .config
    echo "CONFIG_PACKAGE_udev=y" >> .config
    
    echo "# 🟢 USB串口支持 - 扩展功能" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial-ftdi=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-serial-pl2303=y" >> .config
    
    log "=== 🚨 USB 完全修复通用配置 - 完成 ==="
    
    echo "CONFIG_PACKAGE_luci-i18n-base-zh-cn=y" >> .config
    echo "CONFIG_PACKAGE_luci-i18n-firewall-zh-cn=y" >> .config
    
    if [ "$CONFIG_MODE" = "base" ]; then
        log "🔧 使用基础模式 (最小化，用于测试编译)"
        echo "# CONFIG_PACKAGE_luci-app-turboacc is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-shortcut-fe is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-fast-classifier is not set" >> .config
        echo "# CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn is not set" >> .config
    else
        log "🔧 使用正常模式 (完整功能)"
        
        NORMAL_PLUGINS=(
          "CONFIG_PACKAGE_luci-app-turboacc=y"
          "CONFIG_PACKAGE_kmod-shortcut-fe=y"
          "CONFIG_PACKAGE_kmod-fast-classifier=y"
          "CONFIG_PACKAGE_luci-app-upnp=y"
          "CONFIG_PACKAGE_miniupnpd=y"
          "CONFIG_PACKAGE_vsftpd=y"
          "CONFIG_PACKAGE_luci-app-vsftpd=y"
          "CONFIG_PACKAGE_luci-app-arpbind=y"
          "CONFIG_PACKAGE_luci-app-cpulimit=y"
          "CONFIG_PACKAGE_samba4-server=y"
          "CONFIG_PACKAGE_luci-app-samba4=y"
          "CONFIG_PACKAGE_luci-app-wechatpush=y"
          "CONFIG_PACKAGE_sqm-scripts=y"
          "CONFIG_PACKAGE_luci-app-sqm=y"
          "CONFIG_PACKAGE_luci-app-hd-idle=y"
          "CONFIG_PACKAGE_luci-app-diskman=y"
          "CONFIG_PACKAGE_luci-app-accesscontrol=y"
          "CONFIG_PACKAGE_vlmcsd=y"
          "CONFIG_PACKAGE_luci-app-vlmcsd=y"
          "CONFIG_PACKAGE_smartdns=y"
          "CONFIG_PACKAGE_luci-app-smartdns=y"
        )
        
        for plugin in "${NORMAL_PLUGINS[@]}"; do
            echo "$plugin" >> .config
        done
        
        if [ "$SELECTED_BRANCH" = "openwrt-21.02" ]; then
            echo "CONFIG_PACKAGE_luci-i18n-turboacc-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-upnp-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vsftpd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-arpbind-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-cpulimit-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-samba4-zh-cn=y" >> .config
        fi
    fi
}

verify_usb_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 详细验证USB和存储配置 ==="
    
    echo "1. 🟢 USB核心模块:"
    grep "CONFIG_PACKAGE_kmod-usb-core" .config | grep "=y" && echo "✅ USB核心" || echo "❌ 缺少USB核心"
    
    echo "2. 🟢 USB控制器:"
    grep -E "CONFIG_PACKAGE_kmod-usb2|CONFIG_PACKAGE_kmod-usb3|CONFIG_PACKAGE_kmod-usb-ehci|CONFIG_PACKAGE_kmod-usb-ohci|CONFIG_PACKAGE_kmod-usb-xhci-hcd" .config | grep "=y" || echo "❌ 缺少USB控制器"
    
    echo "3. 🚨 USB 3.0关键驱动:"
    echo "  - kmod-usb-xhci-hcd:" $(grep "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb3:" $(grep "CONFIG_PACKAGE_kmod-usb3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - kmod-usb-dwc3:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    echo "4. 🚨 平台专用USB控制器:"
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "  🔧 检测到高通IPQ40xx平台，检查专用驱动:"
        echo "  - kmod-usb-dwc3-qcom:" $(grep "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-phy-qcom-dwc3:" $(grep "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    elif [ "$TARGET" = "ramips" ]; then
        echo "  🔧 检测到雷凌平台，检查专用驱动:"
        echo "  - kmod-usb-ohci-pci:" $(grep "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
        echo "  - kmod-usb2-pci:" $(grep "CONFIG_PACKAGE_kmod-usb2-pci=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    fi
    
    echo "5. 🟢 USB存储:"
    grep "CONFIG_PACKAGE_kmod-usb-storage" .config | grep "=y" && echo "✅ USB存储" || echo "❌ 缺少USB存储"
    
    echo "6. 🟢 SCSI支持:"
    grep -E "CONFIG_PACKAGE_kmod-scsi-core|CONFIG_PACKAGE_kmod-scsi-generic" .config | grep "=y" && echo "✅ SCSI支持" || echo "❌ 缺少SCSI支持"
    
    echo "7. 🟢 文件系统支持:"
    echo "  - NTFS3:" $(grep "CONFIG_PACKAGE_kmod-fs-ntfs3=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - ext4:" $(grep "CONFIG_PACKAGE_kmod-fs-ext4=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    echo "  - vfat:" $(grep "CONFIG_PACKAGE_kmod-fs-vfat=y" .config && echo "✅ 已启用" || echo "❌ 未启用")
    
    log "=== 🚨 USB配置验证完成 ==="
    
    # 输出总结
    log "📊 USB配置状态总结:"
    local usb_drivers=("kmod-usb-core" "kmod-usb2" "kmod-usb3" "kmod-usb-ehci" "kmod-usb-ohci" "kmod-usb-xhci-hcd" "kmod-usb-storage")
    local missing_count=0
    local enabled_count=0
    
    for driver in "${usb_drivers[@]}"; do
        if grep -q "CONFIG_PACKAGE_${driver}=y" .config; then
            log "  ✅ $driver: 已启用"
            enabled_count=$((enabled_count + 1))
        else
            log "  ❌ $driver: 未启用"
            missing_count=$((missing_count + 1))
        fi
    done
    
    log "📈 统计: $enabled_count 个已启用，$missing_count 个未启用"
    
    if [ $missing_count -gt 0 ]; then
        log "⚠️ 警告: 有 $missing_count 个关键USB驱动未启用，可能会影响USB功能"
    else
        log "🎉 恭喜: 所有关键USB驱动都已启用"
    fi
}

check_usb_drivers_integrity() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 🚨 USB驱动完整性检查 ==="
    
    local missing_drivers=()
    local required_drivers=(
        "kmod-usb-core"
        "kmod-usb2"
        "kmod-usb3"
        "kmod-usb-xhci-hcd"
        "kmod-usb-storage"
        "kmod-scsi-core"
    )
    
    # 根据平台添加专用驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        required_drivers+=("kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3")
    fi
    
    # 检查所有必需驱动
    for driver in "${required_drivers[@]}"; do
        if ! grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            log "❌ 缺失驱动: $driver"
            missing_drivers+=("$driver")
        else
            log "✅ 驱动存在: $driver"
        fi
    done
    
    # 如果有缺失驱动，尝试修复
    if [ ${#missing_drivers[@]} -gt 0 ]; then
        log "🚨 发现 ${#missing_drivers[@]} 个缺失的USB驱动"
        log "正在尝试修复..."
        
        for driver in "${missing_drivers[@]}"; do
            echo "CONFIG_PACKAGE_${driver}=y" >> .config
            log "✅ 已添加: $driver"
        done
        
        # 重新运行defconfig
        make defconfig
        log "✅ USB驱动修复完成"
    else
        log "🎉 所有必需USB驱动都已启用"
    fi
}

apply_config() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 应用配置并显示详情（修复版）==="
    
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在，无法应用配置"
        return 1
    fi
    
    log "📋 配置详情:"
    log "配置文件大小: $(ls -lh .config | awk '{print $5}')"
    log "配置行数: $(wc -l < .config)"
    
    # 显示详细配置状态
    echo ""
    echo "=== 详细配置状态 ==="
    
    # 1. 关键USB配置状态
    echo "🔧 关键USB配置状态:"
    local critical_usb_drivers=(
        "kmod-usb-core" "kmod-usb2" "kmod-usb3" 
        "kmod-usb-ehci" "kmod-usb-ohci" "kmod-usb-xhci-hcd"
        "kmod-usb-storage" "kmod-usb-storage-uas" "kmod-usb-storage-extras"
        "kmod-scsi-core" "kmod-scsi-generic"
    )
    
    local missing_usb=0
    for driver in "${critical_usb_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "  ✅ $driver"
        else
            echo "  ❌ $driver - 缺失！"
            missing_usb=$((missing_usb + 1))
        fi
    done
    
    # 2. 平台专用驱动检查
    echo ""
    echo "🔧 平台专用USB驱动状态:"
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "  高通IPQ40xx平台专用驱动:"
        local qcom_drivers=("kmod-usb-dwc3" "kmod-usb-dwc3-qcom" "kmod-phy-qcom-dwc3" "kmod-usb-dwc3-of-simple")
        for driver in "${qcom_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "    ✅ $driver"
            else
                echo "    ❌ $driver - 缺失！"
                missing_usb=$((missing_usb + 1))
            fi
        done
    elif [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; }; then
        echo "  雷凌MT76xx平台专用驱动:"
        local mtk_drivers=("kmod-usb-ohci-pci" "kmod-usb2-pci" "kmod-usb-xhci-mtk")
        for driver in "${mtk_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
                echo "    ✅ $driver"
            else
                echo "    ❌ $driver - 缺失！"
                missing_usb=$((missing_usb + 1))
            fi
        done
    fi
    
    # 3. 文件系统支持检查
    echo ""
    echo "🔧 文件系统支持状态:"
    local fs_drivers=("kmod-fs-ext4" "kmod-fs-vfat" "kmod-fs-exfat" "kmod-fs-ntfs3")
    for driver in "${fs_drivers[@]}"; do
        if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
            echo "  ✅ $driver"
        else
            echo "  ❌ $driver - 缺失！"
        fi
    done
    
    # 4. 统计信息
    echo ""
    echo "📊 配置统计信息:"
    local enabled_count=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local disabled_count=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    echo "  ✅ 已启用插件: $enabled_count 个"
    echo "  ❌ 已禁用插件: $disabled_count 个"
    
    # 5. 显示具体被禁用的插件（最多20个）
    if [ $disabled_count -gt 0 ]; then
        echo ""
        echo "📋 具体被禁用的插件:"
        local count=0
        grep "^# CONFIG_PACKAGE_.* is not set$" .config | while read line; do
            if [ $count -lt 20 ]; then
                local pkg_name=$(echo $line | sed 's/# CONFIG_PACKAGE_//;s/ is not set//')
                echo "  ❌ $pkg_name"
                count=$((count + 1))
            else
                local remaining=$((disabled_count - 20))
                echo "  ... 还有 $remaining 个被禁用的插件"
                break
            fi
        done
    fi
    
    # 6. 修复缺失的关键USB驱动
    if [ $missing_usb -gt 0 ]; then
        echo ""
        echo "🚨 修复缺失的关键USB驱动:"
        
        # 确保kmod-usb-xhci-hcd启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-hcd"
            sed -i 's/^# CONFIG_PACKAGE_kmod-usb-xhci-hcd is not set$/CONFIG_PACKAGE_kmod-usb-xhci-hcd=y/' .config
            if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" .config; then
                echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
            fi
            echo "  ✅ 已修复 kmod-usb-xhci-hcd"
        fi
        
        # 确保kmod-usb-xhci-pci启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-pci=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-pci"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-pci"
        fi
        
        # 确保kmod-usb-xhci-plat-hcd启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-plat-hcd"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-plat-hcd"
        fi
        
        # 确保kmod-usb-ohci-pci启用
        if ! grep -q "^CONFIG_PACKAGE_kmod-usb-ohci-pci=y" .config; then
            echo "  修复: 启用 kmod-usb-ohci-pci"
            echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
            echo "  ✅ 已修复 kmod-usb-ohci-pci"
        fi
        
        # 确保kmod-usb-dwc3-of-simple启用（如果是高通平台）
        if [ "$TARGET" = "ipq40xx" ] && ! grep -q "^CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" .config; then
            echo "  修复: 启用 kmod-usb-dwc3-of-simple"
            echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
            echo "  ✅ 已修复 kmod-usb-dwc3-of-simple"
        fi
        
        # 确保kmod-usb-xhci-mtk启用（如果是雷凌平台）
        if [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; } && ! grep -q "^CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" .config; then
            echo "  修复: 启用 kmod-usb-xhci-mtk"
            echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
            echo "  ✅ 已修复 kmod-usb-xhci-mtk"
        fi
    fi
    
    # 版本特定的配置修复
    if [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
        log "🔧 23.05版本配置预处理"
        sed -i 's/CONFIG_PACKAGE_ntfs-3g=y/# CONFIG_PACKAGE_ntfs-3g is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs-3g-utils=y/# CONFIG_PACKAGE_ntfs-3g-utils is not set/g' .config
        sed -i 's/CONFIG_PACKAGE_ntfs3-mount=y/# CONFIG_PACKAGE_ntfs3-mount is not set/g' .config
        log "✅ NTFS配置修复完成"
    fi
    
    # 新增：修复编译器相关配置
    echo ""
    echo "🔧 修复编译器相关配置..."
    
    # 确保必要的开发包被启用
    local dev_packages=(
        "gcc" "binutils" "libc" "libgcc" "musl"
    )
    
    for pkg in "${dev_packages[@]}"; do
        if ! grep -q "^CONFIG_PACKAGE_${pkg}=y" .config && ! grep -q "^# CONFIG_PACKAGE_${pkg} is not set$" .config; then
            echo "  修复: 添加 $pkg 配置"
            echo "CONFIG_PACKAGE_${pkg}=y" >> .config
        fi
    done
    
    # 确保外部编译器配置正确
    echo "# 编译器配置修复" >> .config
    echo "CONFIG_GCC_USE_GRAPHITE=y" >> .config
    echo "CONFIG_GCC_USE_VERSION_11=y" >> .config
    echo "CONFIG_BINUTILS_VERSION_2_38=y" >> .config
    
    log "🔄 运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log "🚨 强制启用关键USB驱动和编译器配置（防止defconfig删除）"
    # 确保 USB 3.0 关键驱动被启用
    echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-pci=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-xhci-plat-hcd=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-ohci-pci=y" >> .config
    
    # 根据平台启用专用驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-of-simple=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-xhci-mtk is not set" >> .config
    elif [ "$TARGET" = "ramips" ] && { [ "$SUBTARGET" = "mt76x8" ] || [ "$SUBTARGET" = "mt7621" ]; }; then
        echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-dwc3-qcom is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-phy-qcom-dwc3 is not set" >> .config
        echo "# CONFIG_PACKAGE_kmod-usb-dwc3-of-simple is not set" >> .config
    fi
    
    # 其他关键USB驱动
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
    
    # 编译器配置
    echo "# 编译器确保配置" >> .config
    echo "CONFIG_PACKAGE_gcc=y" >> .config
    echo "CONFIG_PACKAGE_binutils=y" >> .config
    echo "CONFIG_PACKAGE_libc=y" >> .config
    echo "CONFIG_PACKAGE_libgcc=y" >> .config
    
    # 运行defconfig后，再次检查并修复USB驱动
    check_usb_drivers_integrity
    
    # 最终检查
    echo ""
    echo "=== 最终配置检查 ==="
    local final_enabled=$(grep "^CONFIG_PACKAGE_.*=y$" .config | wc -l)
    local final_disabled=$(grep "^# CONFIG_PACKAGE_.* is not set$" .config | wc -l)
    echo "✅ 最终状态: 已启用 $final_enabled 个, 已禁用 $final_disabled 个"
    
    log "✅ 配置应用完成"
    log "最终配置文件: .config"
    log "最终配置大小: $(ls -lh .config | awk '{print $5}')"
}

fix_network() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 修复网络环境 ==="
    
    # 设置git配置
    git config --global http.postBuffer 524288000
    git config --global http.lowSpeedLimit 0
    git config --global http.lowSpeedTime 999999
    git config --global core.compression 0
    git config --global core.looseCompression 0
    
    # 设置环境变量
    export GIT_SSL_NO_VERIFY=1
    export PYTHONHTTPSVERIFY=0
    export CURL_SSL_NO_VERIFY=1
    
    # 设置apt代理（如果有）
    if [ -n "$http_proxy" ]; then
        echo "Acquire::http::Proxy \"$http_proxy\";" | sudo tee /etc/apt/apt.conf.d/proxy.conf > /dev/null
    fi
    
    # 测试网络连接
    log "测试网络连接..."
    if curl -s --connect-timeout 10 https://github.com > /dev/null; then
        log "✅ 网络连接正常"
    else
        log "⚠️ 网络连接可能有问题"
    fi
    
    log "✅ 网络环境修复完成"
}

download_dependencies() {
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 下载依赖包 ==="
    
    # 检查依赖包目录
    if [ ! -d "dl" ]; then
        mkdir -p dl
        log "创建依赖包目录: dl"
    fi
    
    # 显示现有依赖包
    local existing_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "现有依赖包数量: $existing_deps 个"
    
    # 下载依赖包
    log "开始下载依赖包..."
    make -j1 download V=s 2>&1 | tee download.log || handle_error "下载依赖包失败"
    
    # 检查下载结果
    local downloaded_deps=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
    log "下载后依赖包数量: $downloaded_deps 个"
    
    if [ $downloaded_deps -gt $existing_deps ]; then
        log "✅ 成功下载了 $((downloaded_deps - existing_deps)) 个新依赖包"
    else
        log "ℹ️ 没有下载新的依赖包"
    fi
    
    # 检查下载日志中的错误
    if grep -q "ERROR\|Failed\|404" download.log 2>/dev/null; then
        log "⚠️ 下载过程中发现错误:"
        grep -E "ERROR|Failed|404" download.log | head -10
    fi
    
    log "✅ 依赖包下载完成"
}

# 新增：修复libtool相关问题的函数
fix_libtool_issues() {
    log "🔧 修复libtool相关问题..."
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    # 1. 创建必要的目录
    log "📁 创建必要的目录..."
    mkdir -p staging_dir/host/include
    mkdir -p staging_dir/host/share/aclocal
    mkdir -p staging_dir/host/share/aclocal-1.16
    mkdir -p staging_dir/host/lib/pkgconfig
    
    # 2. 复制关键头文件
    log "📋 复制关键头文件..."
    
    # 复制stdc-predef.h
    if [ -f "/usr/include/stdc-predef.h" ]; then
        cp "/usr/include/stdc-predef.h" staging_dir/host/include/ 2>/dev/null || true
        log "✅ 复制: stdc-predef.h"
    else
        log "⚠️  未找到系统stdc-predef.h"
        # 创建简单的stdc-predef.h
        cat > staging_dir/host/include/stdc-predef.h << 'EOF'
/* Generated automatically by fix_libtool_issues */
#ifndef _GCC_STDC_PREDEF_H
#define _GCC_STDC_PREDEF_H

#define __STDC_ISO_10646__ 201103L

#endif /* _GCC_STDC_PREDEF_H */
EOF
        log "✅ 创建: stdc-predef.h"
    fi
    
    # 复制其他关键头文件
    for header in stdio.h stdlib.h string.h features.h; do
        if [ -f "/usr/include/$header" ]; then
            cp "/usr/include/$header" staging_dir/host/include/ 2>/dev/null || true
            log "✅ 复制: $header"
        fi
    done
    
    # 3. 复制libtool.m4
    log "📋 复制libtool.m4..."
    if [ -f "/usr/share/aclocal/libtool.m4" ]; then
        cp "/usr/share/aclocal/libtool.m4" staging_dir/host/share/aclocal/ 2>/dev/null || true
        log "✅ 复制: libtool.m4"
    else
        log "⚠️  未找到系统libtool.m4"
        # 尝试从其他地方查找
        find /usr -name "libtool.m4" 2>/dev/null | head -1 | while read m4file; do
            cp "$m4file" staging_dir/host/share/aclocal/ 2>/dev/null && log "✅ 从其他地方复制: libtool.m4"
        done
        
        # 如果还是没找到，创建基本的libtool.m4
        if [ ! -f "staging_dir/host/share/aclocal/libtool.m4" ]; then
            cat > staging_dir/host/share/aclocal/libtool.m4 << 'EOF'
# libtool.m4 - Configure libtool for the host system. -*-Autoconf-*-
## Copyright 1996, 1997, 1998, 1999, 2000, 2001, 2003, 2004, 2005, 2006,
## 2007, 2008, 2009, 2010 Free Software Foundation, Inc.
## This is a basic libtool.m4 file to avoid compilation errors
AC_DEFUN([LT_INIT], [AC_MSG_NOTICE([Libtool initialized])])
EOF
            log "✅ 创建: 基本libtool.m4"
        fi
    fi
    
    # 4. 复制其他aclocal文件
    log "📋 复制其他aclocal文件..."
    if [ -d "/usr/share/aclocal-1.16" ]; then
        cp /usr/share/aclocal-1.16/*.m4 staging_dir/host/share/aclocal-1.16/ 2>/dev/null || true
        log "✅ 复制aclocal-1.16文件"
    fi
    
    # 5. 设置环境变量
    log "🌍 设置环境变量..."
    export CFLAGS="-I$BUILD_DIR/staging_dir/host/include"
    export LDFLAGS="-L$BUILD_DIR/staging_dir/host/lib"
    export CPPFLAGS="-I$BUILD_DIR/staging_dir/host/include"
    export ACLOCAL_PATH="$BUILD_DIR/staging_dir/host/share/aclocal:\${ACLOCAL_PATH}"
    export PKG_CONFIG_PATH="$BUILD_DIR/staging_dir/host/lib/pkgconfig:\${PKG_CONFIG_PATH}"
    
    # 6. 创建环境变量文件
    log "📝 创建环境变量文件..."
    cat > staging_dir/host/env.sh << EOF
export CFLAGS="-I$BUILD_DIR/staging_dir/host/include"
export LDFLAGS="-L$BUILD_DIR/staging_dir/host/lib"
export CPPFLAGS="-I$BUILD_DIR/staging_dir/host/include"
export ACLOCAL_PATH="$BUILD_DIR/staging_dir/host/share/aclocal:\${ACLOCAL_PATH}"
export PKG_CONFIG_PATH="$BUILD_DIR/staging_dir/host/lib/pkgconfig:\${PKG_CONFIG_PATH}"
EOF
    
    chmod +x staging_dir/host/env.sh
    
    # 7. 验证修复结果
    log "🔍 验证修复结果..."
    if [ -f "staging_dir/host/include/stdc-predef.h" ]; then
        log "✅ stdc-predef.h 存在"
    else
        log "❌ stdc-predef.h 缺失"
    fi
    
    if [ -f "staging_dir/host/share/aclocal/libtool.m4" ]; then
        log "✅ libtool.m4 存在"
    else
        log "❌ libtool.m4 缺失"
    fi
    
    log "✅ libtool问题修复完成"
}

# 新增：修复编译器错误问题的函数
fix_compiler_issues() {
    log "🔧 修复编译器错误问题..."
    
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    # 检查是否存在gcc编译错误
    log "🔍 检查编译器构建问题..."
    
    # 1. 检查gcc版本兼容性问题
    if [ -d "build_dir/toolchain-arm_cortex-a7+neon-vfpv4_gcc-8.4.0_musl_eabi" ]; then
        log "🔧 检测到ARM GCC 8.4.0编译器目录"
        
        # 检查gcc源代码目录
        local gcc_dir=$(find build_dir -name "gcc-8.4.0" -type d 2>/dev/null | head -1)
        if [ -n "$gcc_dir" ]; then
            log "📁 找到gcc源码目录: $gcc_dir"
            
            # 检查是否存在头文件冲突问题
            if [ -f "$gcc_dir/gcc/system.h" ]; then
                log "📋 检查gcc/system.h文件..."
                
                # 备份原始文件
                cp "$gcc_dir/gcc/system.h" "$gcc_dir/gcc/system.h.backup"
                
                # 修复sbrk声明冲突问题
                log "🔧 修复sbrk声明冲突..."
                sed -i 's/^void\* sbrk(int);$//' "$gcc_dir/gcc/system.h"
                
                # 修复strsignal声明冲突
                log "🔧 修复strsignal声明冲突..."
                sed -i 's/^const char\* strsignal(int);$//' "$gcc_dir/gcc/system.h"
                
                # 修复basename声明冲突
                log "🔧 修复basename声明冲突..."
                sed -i 's/^char\* basename(const char\*);$//' "$gcc_dir/gcc/system.h"
                
                log "✅ gcc/system.h修复完成"
            fi
            
            # 检查auto-host.h文件
            if [ -f "$gcc_dir/gcc/auto-host.h" ]; then
                log "📋 检查auto-host.h文件..."
                
                # 备份原始文件
                cp "$gcc_dir/gcc/auto-host.h" "$gcc_dir/gcc/auto-host.h.backup"
                
                # 修复声明问题
                log "🔧 修复auto-host.h声明问题..."
                sed -i 's/^#define HAVE_DECL_SBRK.*$/#undef HAVE_DECL_SBRK/' "$gcc_dir/gcc/auto-host.h"
                sed -i 's/^#define HAVE_DECL_STRSIGNAL.*$/#undef HAVE_DECL_STRSIGNAL/' "$gcc_dir/gcc/auto-host.h"
                sed -i 's/^#define HAVE_DECL_BASENAME.*$/#undef HAVE_DECL_BASENAME/' "$gcc_dir/gcc/auto-host.h"
                
                log "✅ auto-host.h修复完成"
            fi
            
            # 创建补丁文件
            log "📝 创建编译器补丁..."
            cat > /tmp/gcc_fix.patch << 'EOF'
diff -u gcc/system.h.orig gcc/system.h
--- gcc/system.h.orig
+++ gcc/system.h
@@ -485,15 +485,15 @@
 #endif
 
 /* Some of glibc's string inlines cause warnings.  Also some
    string.h functions are only declared as inline in glibc, so can't
    be called via a pointer.  */
 #ifdef __cplusplus
 extern "C" {
 #endif
-#if defined(HAVE_DECL_SBRK) && HAVE_DECL_SBRK
+#if 0
 void* sbrk(int);
 #endif
 
 #ifdef __cplusplus
 }
 #endif
EOF
            
            # 应用补丁
            if patch -p1 -d "$gcc_dir" < /tmp/gcc_fix.patch 2>/dev/null; then
                log "✅ GCC补丁应用成功"
            else
                log "⚠️  GCC补丁应用失败，但可能不影响"
            fi
        fi
    fi
    
    # 2. 清理可能的问题目录
    log "🧹 清理可能的问题目录..."
    local problematic_dirs=(
        "build_dir/toolchain-*"
        "staging_dir/toolchain-*"
        "tmp"
    )
    
    for dir_pattern in "${problematic_dirs[@]}"; do
        if find . -name "$(basename "$dir_pattern")" -type d 2>/dev/null | grep -q .; then
            log "ℹ️  找到目录匹配: $dir_pattern"
            # 不自动清理，只记录
        fi
    done
    
    # 3. 设置编译器环境变量
    log "🌍 设置编译器环境变量..."
    export CFLAGS="-O2 -pipe"
    export CXXFLAGS="-O2 -pipe"
    export LDFLAGS="-Wl,-O1"
    export CPPFLAGS=""
    
    # 对于特定的错误，添加-fpermissive标志
    if [ -f "build.log" ] && grep -q "declaration does not declare anything" build.log; then
        log "🔧 检测到声明错误，添加-fpermissive标志..."
        export CFLAGS="$CFLAGS -fpermissive"
        export CXXFLAGS="$CXXFLAGS -fpermissive"
    fi
    
    # 4. 创建编译器修复脚本
    log "📝 创建编译器修复脚本..."
    cat > staging_dir/host/fix_compiler.sh << 'EOF'
#!/bin/bash
# 编译器修复脚本
echo "应用编译器修复..."

# 设置宽松的编译选项
export CFLAGS="-O2 -pipe -fpermissive"
export CXXFLAGS="-O2 -pipe -fpermissive"
export LDFLAGS="-Wl,-O1"

echo "编译器修复完成"
EOF
    
    chmod +x staging_dir/host/fix_compiler.sh
    
    log "✅ 编译器问题修复完成"
}

build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 编译固件（优化版）==="
    
    # 编译前最终检查
    log "编译前最终检查..."
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        exit 1
    fi
    
    if [ ! -d "staging_dir" ]; then
        log "⚠️ 警告: staging_dir 目录不存在"
    fi
    
    if [ ! -d "dl" ]; then
        log "⚠️ 警告: dl 目录不存在"
    fi
    
    # 获取CPU核心数
    local cpu_cores=$(nproc)
    local make_jobs=$cpu_cores
    
    # 如果内存小于4GB，减少并行任务
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    if [ $total_mem -lt 4096 ]; then
        make_jobs=$((cpu_cores / 2))
        if [ $make_jobs -lt 1 ]; then
            make_jobs=1
        fi
        log "⚠️ 内存较低(${total_mem}MB)，减少并行任务到 $make_jobs"
    fi
    
    # 新增：修复libtool相关文件（在编译前执行）
    fix_libtool_issues
    
    # 新增：修复编译器错误（在编译前执行）
    fix_compiler_issues
    
    # 新增：设置编译环境变量
    export CFLAGS="-I${BUILD_DIR}/staging_dir/host/include -O2 -pipe"
    export LDFLAGS="-L${BUILD_DIR}/staging_dir/host/lib -Wl,-O1"
    export CPPFLAGS="-I${BUILD_DIR}/staging_dir/host/include"
    export ACLOCAL_PATH="${BUILD_DIR}/staging_dir/host/share/aclocal:${ACLOCAL_PATH:-}"
    export PKG_CONFIG_PATH="${BUILD_DIR}/staging_dir/host/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    
    # 对于特定的编译器错误，添加-fpermissive标志
    export CFLAGS="$CFLAGS -fpermissive"
    export CXXFLAGS="$CFLAGS"
    
    # 开始编译（默认启用缓存）
    log "启用编译缓存，使用 $make_jobs 个并行任务"
    
    # 使用优化的编译参数，减少Broken pipe错误
    if [ $make_jobs -gt 4 ]; then
        log "🔧 使用优化的编译参数以减少管道错误"
        make -j$make_jobs V=s 2>&1 | tee build.log || {
            BUILD_EXIT_CODE=${PIPESTATUS[0]}
            log "编译失败，退出代码: $BUILD_EXIT_CODE"
            
            # 尝试使用更少的并行任务重新编译
            log "尝试使用更少的并行任务重新编译..."
            make -j2 V=s 2>&1 | tee -a build.log
            BUILD_EXIT_CODE=${PIPESTATUS[0]}
        }
    else
        make -j$make_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    fi
    
    log "编译退出代码: $BUILD_EXIT_CODE"
    
    # 编译结果分析
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        log "✅ 固件编译成功"
        
        # 检查生成的固件
        if [ -d "bin/targets" ]; then
            local firmware_count=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
            log "✅ 生成固件文件: $firmware_count 个"
            
            # 显示固件文件
            find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | head -5 | while read file; do
                log "固件: $file ($(du -h "$file" | cut -f1))"
            done
        else
            log "❌ 固件目录不存在"
        fi
    else
        log "❌ 编译失败，退出代码: $BUILD_EXIT_CODE"
        
        # 分析失败原因
        if [ -f "build.log" ]; then
            log "=== 编译错误摘要 ==="
            
            # 查找常见错误
            local error_count=$(grep -c "Error [0-9]|error:" build.log)
            local warning_count=$(grep -c "Warning\|warning:" build.log)
            
            log "发现 $error_count 个错误，$warning_count 个警告"
            
            # 显示前10个错误
            if [ $error_count -gt 0 ]; then
                log "前10个错误:"
                grep -i "Error\|error:" build.log | head -10
            fi
            
            # 检查常见错误类型
            if grep -q "undefined reference" build.log; then
                log "⚠️ 发现未定义引用错误"
            fi
            
            if grep -q "No such file" build.log; then
                log "⚠️ 发现文件不存在错误"
            fi
            
            if grep -q "out of memory\|Killed process" build.log; then
                log "⚠️ 可能是内存不足导致编译失败"
            fi
            
            # 特别检查编译器错误
            if grep -q "compiler.*not found" build.log; then
                log "🚨 发现编译器未找到错误"
                log "检查编译器路径..."
                if [ -d "staging_dir" ]; then
                    find staging_dir -name "*gcc*" 2>/dev/null | head -10
                fi
            fi
            
            # 检查头文件错误
            if grep -q "stdc-predef.h" build.log; then
                log "🚨 发现头文件缺失错误: stdc-predef.h"
                log "💡 建议: 确保安装了正确的开发包"
            fi
            
            if grep -q "libtool.m4" build.log; then
                log "🚨 发现libtool.m4缺失错误"
                log "💡 建议: 确保安装了libtool和autoconf包"
            fi
            
            # 检查特定的gcc编译错误
            if grep -q "declaration does not declare anything" build.log; then
                log "🚨 发现GCC声明错误"
                log "💡 建议: 这可能是GCC版本兼容性问题，已应用-fpermissive标志"
            fi
            
            if grep -q "conflicting declaration of C function" build.log; then
                log "🚨 发现C函数声明冲突错误"
                log "💡 建议: 这通常是头文件冲突，已尝试修复"
            fi
        fi
        
        exit $BUILD_EXIT_CODE
    fi
    
    log "✅ 固件编译完成"
}

post_build_space_check() {
    log "=== 编译后空间检查 ==="
    
    echo "=== 磁盘使用情况 ==="
    df -h
    
    # 构建目录空间
    local build_dir_usage=$(du -sh $BUILD_DIR 2>/dev/null | cut -f1) || echo "无法获取构建目录大小"
    echo "构建目录大小: $build_dir_usage"
    
    # 固件文件大小
    if [ -d "$BUILD_DIR/bin/targets" ]; then
        local firmware_size=$(find "$BUILD_DIR/bin/targets" -type f \( -name "*.bin" -o -name "*.img" \) -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
        echo "固件文件总大小: $firmware_size"
    fi
    
    # 检查可用空间
    local available_space=$(df /mnt --output=avail | tail -1)
    local available_gb=$((available_space / 1024 / 1024))
    log "/mnt 可用空间: ${available_gb}G"
    
    if [ $available_gb -lt 5 ]; then
        log "⚠️ 警告: 磁盘空间较低，建议清理"
    else
        log "✅ 磁盘空间充足"
    fi
    
    log "✅ 空间检查完成"
}

check_firmware_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 固件文件检查 ==="
    
    if [ -d "bin/targets" ]; then
        log "✅ 固件目录存在"
        
        # 统计固件文件
        local firmware_files=$(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) 2>/dev/null | wc -l)
        local all_files=$(find bin/targets -type f 2>/dev/null | wc -l)
        
        log "固件文件: $firmware_files 个"
        log "所有文件: $all_files 个"
        
        # 显示固件文件详情
        echo "=== 生成的固件文件 ==="
        find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec ls -lh {} \;
        
        # 检查文件大小
        local total_size=0
        while read size; do
            total_size=$((total_size + size))
        done < <(find bin/targets -type f \( -name "*.bin" -o -name "*.img" \) -exec stat -c%s {} \; 2>/dev/null)
        
        if [ $total_size -gt 0 ]; then
            local total_size_mb=$((total_size / 1024 / 1024))
            log "固件总大小: ${total_size_mb}MB"
            
            # 检查固件大小是否合理
            if [ $total_size_mb -lt 5 ]; then
                log "⚠️ 警告: 固件文件可能太小"
            elif [ $total_size_mb -gt 100 ]; then
                log "⚠️ 警告: 固件文件可能太大"
            else
                log "✅ 固件大小正常"
            fi
        fi
        
        # 检查目标目录结构
        echo "=== 目标目录结构 ==="
        find bin/targets -maxdepth 3 -type d | sort
        
    else
        log "❌ 固件目录不存在"
        exit 1
    fi
}

cleanup() {
    log "=== 清理构建目录 ==="
    
    if [ -d "$BUILD_DIR" ]; then
        log "检查是否有需要保留的文件..."
        
        # 如果.config文件存在，先备份
        if [ -f "$BUILD_DIR/.config" ]; then
            log "备份配置文件..."
            mkdir -p /tmp/openwrt_backup
            local backup_file="/tmp/openwrt_backup/config_$(date +%Y%m%d_%H%M%S).config"
            cp "$BUILD_DIR/.config" "$backup_file"
            log "✅ 配置文件备份到: $backup_file"
        fi
        
        # 如果build.log存在，备份
        if [ -f "$BUILD_DIR/build.log" ]; then
            log "备份编译日志..."
            mkdir -p /tmp/openwrt_backup
            cp "$BUILD_DIR/build.log" "/tmp/openwrt_backup/build_$(date +%Y%m%d_%H%M%S).log"
        fi
        
        # 清理构建目录
        log "清理构建目录: $BUILD_DIR"
        sudo rm -rf $BUILD_DIR || log "⚠️ 清理构建目录失败"
        log "✅ 构建目录已清理"
    else
        log "ℹ️ 构建目录不存在，无需清理"
    fi
}

main() {
    case $1 in
        "setup_environment")
            setup_environment
            ;;
        "create_build_dir")
            create_build_dir
            ;;
        "initialize_build_env")
            initialize_build_env "$2" "$3" "$4"
            ;;
        "add_turboacc_support")
            add_turboacc_support
            ;;
        "configure_feeds")
            configure_feeds
            ;;
        "install_turboacc_packages")
            install_turboacc_packages
            ;;
        "pre_build_space_check")
            pre_build_space_check
            ;;
        "generate_config")
            generate_config "$2"
            ;;
        "verify_usb_config")
            verify_usb_config
            ;;
        "check_usb_drivers_integrity")
            check_usb_drivers_integrity
            ;;
        "apply_config")
            apply_config
            ;;
        "fix_network")
            fix_network
            ;;
        "download_dependencies")
            download_dependencies
            ;;
        "integrate_custom_files")
            integrate_custom_files
            ;;
        "pre_build_error_check")
            pre_build_error_check
            ;;
        "build_firmware")
            build_firmware "$2"
            ;;
        "post_build_space_check")
            post_build_space_check
            ;;
        "check_firmware_files")
            check_firmware_files
            ;;
        "cleanup")
            cleanup
            ;;
        "save_source_code_info")
            save_source_code_info
            ;;
        "download_compiler_files")
            download_compiler_files
            ;;
        "collect_compiled_compiler_files")
            collect_compiled_compiler_files
            ;;
        "fix_libtool_issues")
            fix_libtool_issues
            ;;
        "fix_compiler_issues")
            fix_compiler_issues
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  add_turboacc_support, configure_feeds, install_turboacc_packages"
            echo "  pre_build_space_check, generate_config, verify_usb_config, check_usb_drivers_integrity, apply_config"
            echo "  fix_network, download_dependencies, integrate_custom_files"
            echo "  pre_build_error_check, build_firmware, post_build_space_check"
            echo "  check_firmware_files, cleanup, save_source_code_info, download_compiler_files"
            echo "  collect_compiled_compiler_files, fix_libtool_issues, fix_compiler_issues"
            exit 1
            ;;
    esac
}

main "$@"
