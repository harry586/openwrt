#!/bin/bash
set -e

BUILD_DIR="/mnt/openwrt-build"
ENV_FILE="$BUILD_DIR/build_env.sh"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLCHAIN_DIR="$REPO_ROOT/firmware-config/Toolchain"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

handle_error() {
    log "❌ 错误发生在: $1"
    exit 1
}

# 新增：验证工具链完整性函数（修复版）
verify_toolchain_completeness() {
    local toolchain_dir=$1
    
    log "🔧 验证工具链完整性: $toolchain_dir"
    
    if [ ! -d "$toolchain_dir" ]; then
        log "❌ 工具链目录不存在: $toolchain_dir"
        return 1
    fi
    
    # 检查真正的编译器文件，而不是stamp文件
    log "查找真正的编译器文件..."
    local compilers=($(find "$toolchain_dir" -type f \( -name "*gcc*" -o -name "*g++*" \) ! -name "*.stamp*" ! -name ".gcc_*" 2>/dev/null | grep -v "stamp" | head -20))
    
    if [ ${#compilers[@]} -eq 0 ]; then
        log "⚠️  未找到编译器，尝试在其他位置查找..."
        # 尝试在bin目录查找
        if [ -d "$toolchain_dir/bin" ]; then
            compilers=($(find "$toolchain_dir/bin" -type f -name "*gcc*" 2>/dev/null))
        fi
        
        if [ ${#compilers[@]} -eq 0 ]; then
            log "❌ 未找到任何编译器文件，工具链不完整"
            return 1
        fi
    fi
    
    log "找到 ${#compilers[@]} 个编译器文件"
    
    # 只检查真正的可执行文件，跳过标记文件
    local valid_compilers=0
    for compiler in "${compilers[@]}"; do
        # 跳过非普通文件（如目录、符号链接等）
        if [ ! -f "$compiler" ]; then
            continue
        fi
        
        # 跳过stamp文件和标记文件
        if [[ "$compiler" == *".stamp"* ]] || [[ "$compiler" == *".gcc_"* ]] || [[ "$compiler" == *"/stamp/"* ]]; then
            continue
        fi
        
        # 检查文件大小，太小的文件可能是标记文件
        local file_size=$(stat -c%s "$compiler" 2>/dev/null || echo "0")
        if [ "$file_size" -lt 1000 ]; then
            log "跳过小文件（可能是标记文件）: $compiler ($file_size 字节)"
            continue
        fi
        
        log "检查编译器: $compiler ($(du -h "$compiler" 2>/dev/null | cut -f1))"
        
        # 如果是可执行文件，测试它
        if [ -x "$compiler" ]; then
            log "✅ 可执行: $compiler"
            valid_compilers=$((valid_compilers + 1))
        else
            # 尝试添加执行权限
            if chmod +x "$compiler" 2>/dev/null; then
                log "✅ 已添加执行权限: $compiler"
                valid_compilers=$((valid_compilers + 1))
            else
                log "⚠️  无法添加执行权限: $compiler"
            fi
        fi
    done
    
    if [ $valid_compilers -eq 0 ]; then
        log "❌ 没有找到有效的可执行编译器"
        return 1
    fi
    
    log "✅ 找到 $valid_compilers 个有效的编译器"
    
    # 检查bin目录是否存在
    if [ ! -d "$toolchain_dir/bin" ]; then
        log "⚠️  警告: bin目录不存在，但找到了编译器文件"
        # 列出工具链目录结构以便调试
        log "工具链目录结构:"
        find "$toolchain_dir" -maxdepth 2 -type d | head -10
    else
        log "✅ bin目录存在"
    fi
    
    log "✅ 工具链验证通过"
    return 0
}

# 新增：检查工具链完整性（公开函数）
check_toolchain_completeness() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 检查工具链完整性 ==="
    
    # 查找工具链目录
    local toolchain_dir=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -z "$toolchain_dir" ]; then
        log "❌ 未找到工具链目录"
        return 1
    fi
    
    verify_toolchain_completeness "$toolchain_dir"
    local result=$?
    
    if [ $result -eq 0 ]; then
        log "✅ 工具链完整性检查通过"
    else
        log "❌ 工具链完整性检查失败"
    fi
    
    return $result
}

# 新增：设置工具链环境函数
setup_toolchain_env() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 设置工具链环境 ==="
    
    # 查找工具链目录
    local toolchain_dir=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -d "$toolchain_dir" ]; then
        log "✅ 找到工具链目录: $toolchain_dir"
        
        # 设置工具链环境变量
        export STAGING_DIR="$toolchain_dir"
        
        # 查找编译器路径
        local bin_dir="$toolchain_dir/bin"
        if [ -d "$bin_dir" ]; then
            export PATH="$bin_dir:$PATH"
            log "✅ 添加工具链到PATH: $bin_dir"
            
            # 检查编译器是否存在
            local target_compiler=""
            case "$TARGET" in
                "ipq40xx")
                    target_compiler="arm-openwrt-linux-muslgnueabi-gcc"
                    ;;
                "ramips")
                    if [ "$SUBTARGET" = "mt76x8" ]; then
                        target_compiler="mipsel-openwrt-linux-musl-gcc"
                    elif [ "$SUBTARGET" = "mt7621" ]; then
                        target_compiler="mipsel-openwrt-linux-musl-gcc"
                    fi
                    ;;
            esac
            
            if [ -n "$target_compiler" ] && [ -f "$bin_dir/$target_compiler" ]; then
                log "✅ 找到目标编译器: $bin_dir/$target_compiler"
                # 测试编译器
                if "$bin_dir/$target_compiler" --version >/dev/null 2>&1; then
                    log "✅ 编译器工作正常"
                else
                    log "❌ 编译器无法运行，检查权限"
                    chmod +x "$bin_dir/$target_compiler"
                fi
            else
                log "⚠️  未找到目标编译器: $target_compiler"
                # 显示可用的编译器
                find "$bin_dir" -name "*gcc*" 2>/dev/null | head -5
            fi
        fi
    else
        log "⚠️  未找到工具链目录，将自动下载"
    fi
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

get_toolchain_path() {
    load_env
    # 确保Toolchain目录存在
    mkdir -p "$TOOLCHAIN_DIR/$SELECTED_BRANCH/$TARGET/$SUBTARGET"
    echo "$TOOLCHAIN_DIR/$SELECTED_BRANCH/$TARGET/$SUBTARGET"
}

get_common_toolchain_path() {
    # 确保common目录存在
    mkdir -p "$TOOLCHAIN_DIR/common"
    echo "$TOOLCHAIN_DIR/common"
}

check_large_files() {
    log "=== 检查大文件 ==="
    
    local repo_root="$(pwd)"
    
    # 检查是否有超过 90MB 的文件
    log "检查大于90MB的文件..."
    large_files=$(find . -type f -size +90M 2>/dev/null | grep -v ".git" || true)
    
    if [ -n "$large_files" ]; then
        log "⚠️  发现以下大文件（可能超过GitHub限制）:"
        echo "$large_files"
        log "💡 建议: 将这些文件添加到 .gitattributes 中使用 Git LFS 管理"
        
        # 检查工具链中的大文件
        if [ -d "firmware-config/Toolchain" ]; then
            log "检查工具链中的大文件..."
            find firmware-config/Toolchain -type f -size +50M 2>/dev/null | head -10 || true
        fi
    else
        log "✅ 未发现超过90MB的大文件"
    fi
}

init_toolchain_dir() {
    log "=== 初始化工具链目录 ==="
    mkdir -p "$TOOLCHAIN_DIR"
    log "✅ 工具链目录: $TOOLCHAIN_DIR"
    
    # 确保目录结构正确
    mkdir -p "$TOOLCHAIN_DIR/common"
    mkdir -p "$TOOLCHAIN_DIR/openwrt-21.02"
    mkdir -p "$TOOLCHAIN_DIR/openwrt-23.05"
    
    # 创建README文件（如果不存在）
    if [ ! -f "$TOOLCHAIN_DIR/README.md" ]; then
        cat > "$TOOLCHAIN_DIR/README.md" << EOF
# OpenWrt 编译工具链

## 目录结构
- \`common/\` - 通用工具链组件，包含基本的编译工具
- \`<版本>/<平台>/<子平台>/ - 版本特定的完整工具链

## 用途
1. **加速编译**：保存的工具链可以避免重复下载和编译
2. **离线编译**：在没有网络的环境下也可以进行编译
3. **版本管理**：不同版本和平台的工具链独立保存

## 使用方式
工具链会在编译时自动加载，无需手动操作

## 注意事项
- 工具链文件较大，已使用 Git LFS 管理大文件
- 不同版本的工具链不兼容，请勿混用
- 如果编译失败，可以尝试清理工具链重新下载

## 文件说明
- \`build.config\` - 编译时使用的配置文件备份
- \`bin/\` - 编译工具（gcc, g++, ld等）
- \`lib/\` - 库文件
- \`include/\` - 头文件

## Git LFS 管理
大文件（如编译器、库文件）已使用 Git LFS 管理，确保不会超过 GitHub 文件大小限制
EOF
        log "✅ 创建README.md文件"
    fi
}

save_toolchain() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 保存工具链到仓库 ==="
    
    # 初始化工具链目录
    init_toolchain_dir
    
    local toolchain_path=$(get_toolchain_path)
    local common_path=$(get_common_toolchain_path)
    
    log "🔍 工具链保存路径信息:"
    log "  目标工具链路径: $toolchain_path"
    log "  仓库根目录: $REPO_ROOT"
    log "  当前工作目录: $(pwd)"
    
    # 确保目标目录存在且有写权限
    mkdir -p "$toolchain_path"
    mkdir -p "$common_path"
    
    # 检查是否有工具链可以保存
    local staging_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
    
    if [ -z "$staging_toolchain" ]; then
        log "⚠️  未找到工具链，跳过保存"
        return 0
    fi
    
    log "找到工具链: $staging_toolchain"
    
    # 先清理目标目录
    log "清理目标目录..."
    rm -rf "$toolchain_path"/*
    rm -rf "$common_path"/*
    
    if [ -d "$staging_toolchain" ]; then
        log "保存版本特定工具链到: $toolchain_path"
        
        # 使用rsync保持文件属性和符号链接
        cd "$(dirname "$staging_toolchain")"
        local toolchain_name=$(basename "$staging_toolchain")
        
        # 创建工具链的压缩版本（用于快速传输）
        log "创建工具链..."
        if rsync -av "$toolchain_name/" "$toolchain_path/" --exclude="*.o" --exclude="*.a"; then
            log "✅ 版本特定工具链保存成功 (使用rsync复制)"
            
            # 记录工具链信息
            echo "# Toolchain saved on $(date)" > "$toolchain_path/toolchain.info"
            echo "Version: $SELECTED_BRANCH" >> "$toolchain_path/toolchain.info"
            echo "Target: $TARGET" >> "$toolchain_path/toolchain.info"
            echo "Subtarget: $SUBTARGET" >> "$toolchain_path/toolchain.info"
            echo "Device: $DEVICE" >> "$toolchain_path/toolchain.info"
            echo "Saved with Git LFS: true" >> "$toolchain_path/toolchain.info"
        else
            log "❌ rsync复制失败"
            return 1
        fi
    else
        log "❌ 工具链目录不存在: $staging_toolchain"
        return 1
    fi
    
    log "保存通用工具链到: $common_path"
    mkdir -p "$common_path/bin"
    
    # 复制常用工具
    local tools=("ar" "as" "gcc" "g++" "ld" "nm" "objcopy" "objdump" "ranlib" "strip")
    local copied_tools=0
    for tool in "${tools[@]}"; do
        if find "$staging_toolchain/bin" -name "*$tool*" -type f -exec cp -v {} "$common_path/bin/" \; 2>/dev/null; then
            copied_tools=$((copied_tools + 1))
        fi
    done
    
    log "复制了 $copied_tools 个通用工具"
    
    # 保存编译配置文件
    mkdir -p "$common_path/etc"
    if [ -f "$BUILD_DIR/.config" ]; then
        cp "$BUILD_DIR/.config" "$common_path/etc/build.config"
        log "✅ 保存构建配置文件"
    fi
    
    # 显示保存结果
    log "✅ 工具链保存完成"
    log "特定版本工具链: $toolchain_path"
    log "  文件数: $(find "$toolchain_path" -type f | wc -l)"
    log "  大小: $(du -sh "$toolchain_path" | cut -f1)"
    log "通用工具链: $common_path"
    log "  通用工具: $copied_tools 个"
    log "  大小: $(du -sh "$common_path" | cut -f1)"
    
    # 检查是否有大文件需要Git LFS管理
    log "🔍 检查大文件..."
    local large_files=$(find "$TOOLCHAIN_DIR" -type f -size +50M 2>/dev/null | wc -l)
    if [ $large_files -gt 0 ]; then
        log "⚠️  发现 $large_files 个大于50M的文件，建议使用Git LFS管理"
        find "$TOOLCHAIN_DIR" -type f -size +50M 2>/dev/null | head -5
    fi
    
    return 0
}

load_toolchain() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 加载工具链 ==="
    log "当前工作目录: $(pwd)"
    log "仓库根目录: $REPO_ROOT"
    log "工具链目录: $TOOLCHAIN_DIR"
    
    # 初始化工具链目录
    init_toolchain_dir
    
    local toolchain_path=$(get_toolchain_path)
    local common_path=$(get_common_toolchain_path)
    
    log "检查仓库工具链目录: $toolchain_path"
    if [ -d "$toolchain_path" ]; then
        log "目录存在，内容如下："
        ls -la "$toolchain_path" 2>/dev/null | head -10 || log "无法列出目录内容"
    else
        log "目录不存在"
    fi
    
    log "检查通用工具链目录: $common_path"
    if [ -d "$common_path" ]; then
        log "目录存在，内容如下："
        ls -la "$common_path" 2>/dev/null | head -10 || log "无法列出目录内容"
    else
        log "目录不存在"
    fi
    
    local found_repo_toolchain=0
    
    # 检查仓库中的工具链
    if [ -d "$toolchain_path" ] && [ -n "$(ls -A "$toolchain_path" 2>/dev/null)" ]; then
        found_repo_toolchain=1
        log "🔧 从仓库找到版本特定工具链: $toolchain_path"
    fi
    
    if [ -d "$common_path/bin" ] && [ -n "$(ls -A "$common_path/bin" 2>/dev/null)" ]; then
        found_repo_toolchain=1
        log "🔧 从仓库找到通用工具链: $common_path/bin"
    fi
    
    if [ $found_repo_toolchain -eq 0 ]; then
        log "ℹ️  仓库中未找到工具链，将使用默认工具链"
        return 0
    fi
    
    mkdir -p staging_dir
    
    # 加载版本特定工具链
    if [ -d "$toolchain_path" ] && [ -n "$(ls -A "$toolchain_path" 2>/dev/null)" ]; then
        log "🔧 从仓库加载版本特定工具链: $toolchain_path"
        
        local existing_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
        
        if [ -n "$existing_toolchain" ]; then
            log "已存在工具链: $existing_toolchain，跳过加载"
            # 验证现有工具链
            verify_toolchain_completeness "$existing_toolchain" || log "⚠️ 现有工具链验证失败"
        else
            # 查找工具链目录
            local first_dir=$(find "$toolchain_path" -maxdepth 1 -type d ! -path "$toolchain_path" | head -1)
            if [ -n "$first_dir" ]; then
                local toolchain_name=$(basename "$first_dir")
                log "复制工具链: $toolchain_name 到 staging_dir/"
                cp -r "$first_dir" "staging_dir/"
                
                # 验证工具链完整性
                if verify_toolchain_completeness "staging_dir/$toolchain_name"; then
                    log "✅ 版本特定工具链加载完成: staging_dir/$toolchain_name"
                else
                    log "❌ 工具链验证失败，删除不完整的工具链"
                    rm -rf "staging_dir/$toolchain_name"
                    log "ℹ️  将重新下载完整工具链"
                fi
            else
                # 如果没有子目录，直接使用当前目录
                log "复制工具链文件到 staging_dir/"
                mkdir -p "staging_dir/toolchain-repo"
                cp -r "$toolchain_path"/* "staging_dir/toolchain-repo/" 2>/dev/null || true
                
                # 验证工具链完整性
                if verify_toolchain_completeness "staging_dir/toolchain-repo"; then
                    log "✅ 版本特定工具链文件加载完成"
                else
                    log "❌ 工具链文件不完整"
                fi
            fi
        fi
    fi
    
    # 加载通用工具链
    if [ -d "$common_path/bin" ] && [ -n "$(ls -A "$common_path/bin" 2>/dev/null)" ]; then
        log "🔧 从仓库加载通用工具链组件"
        
        mkdir -p staging_dir/host/bin
        cp -r "$common_path/bin"/* staging_dir/host/bin/ 2>/dev/null || true
        log "✅ 通用工具链组件加载完成"
    fi
    
    # 检查构建目录中是否已有工具链
    if [ -d "staging_dir" ]; then
        local existing_toolchain=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
        if [ -n "$existing_toolchain" ]; then
            log "✅ 构建目录中已有工具链: $existing_toolchain"
            log "工具链大小: $(du -sh "$existing_toolchain" 2>/dev/null | cut -f1 || echo '未知')"
            
            # 验证工具链完整性
            if verify_toolchain_completeness "$existing_toolchain"; then
                log "✅ 工具链完整性验证通过"
            else
                log "❌ 工具链不完整，可能需要重新下载"
            fi
        else
            log "⚠️  构建目录中未找到完整工具链"
        fi
    fi
    
    return 0
}

integrate_custom_files() {
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 集成自定义文件 ==="
    
    local custom_dir="$REPO_ROOT/firmware-config/custom-files"
    
    if [ ! -d "$custom_dir" ]; then
        log "ℹ️  自定义文件目录不存在: $custom_dir"
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
    
    log "=== 🚨 前置错误检查 ==="
    
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
        log "⚠️  警告: dl 目录不存在，可能需要下载依赖"
        warning_count=$((warning_count + 1))
    else
        local dl_count=$(find dl -type f \( -name "*.tar.*" -o -name "*.zip" -o -name "*.gz" \) 2>/dev/null | wc -l)
        log "✅ 依赖包数量: $dl_count 个"
        
        if [ $dl_count -lt 10 ]; then
            log "⚠️  警告: 依赖包数量较少，可能下载不完整"
            warning_count=$((warning_count + 1))
        fi
        
        # 检查关键依赖包是否存在
        local critical_deps=("linux" "gcc" "binutils" "musl")
        for dep in "${critical_deps[@]}"; do
            if find dl -name "*${dep}*" -type f 2>/dev/null | grep -q .; then
                log "✅ 找到关键依赖: $dep"
            else
                log "⚠️  警告: 未找到关键依赖: $dep"
                warning_count=$((warning_count + 1))
            fi
        done
        
        # 额外检查：根据版本检查正确的C库
        if [ "$SELECTED_BRANCH" = "openwrt-21.02" ] || [ "$SELECTED_BRANCH" = "openwrt-23.05" ]; then
            log "🔧 检查musl C库..."
            if find dl -name "*musl*" -type f 2>/dev/null | grep -q .; then
                log "✅ 找到musl C库 (现代OpenWrt使用)"
            else
                log "⚠️  警告: 未找到musl C库"
                warning_count=$((warning_count + 1))
            fi
        fi
    fi
    
    # 4. 检查工具链
    if [ -d "staging_dir" ]; then
        local toolchain_count=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" 2>/dev/null | wc -l)
        if [ $toolchain_count -eq 0 ]; then
            log "⚠️  警告: 未找到编译工具链，将自动下载"
            warning_count=$((warning_count + 1))
        else
            log "✅ 已下载编译工具链: $toolchain_count 个"
            
            # 检查工具链完整性
            local toolchain_dir=$(find staging_dir -maxdepth 1 -type d -name "toolchain-*" | head -1)
            if [ -d "$toolchain_dir/bin" ]; then
                local compiler_count=$(find "$toolchain_dir/bin" -name "*gcc*" -o -name "*g++*" 2>/dev/null | wc -l)
                if [ $compiler_count -gt 0 ]; then
                    log "✅ 工具链编译器文件: $compiler_count 个"
                else
                    log "⚠️  警告: 工具链缺少编译器文件"
                    warning_count=$((warning_count + 1))
                fi
            fi
        fi
    else
        log "ℹ️  staging_dir目录不存在，将自动下载工具链"
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
            log "⚠️  警告: 没有可执行的脚本文件"
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
        log "⚠️  警告: 磁盘空间较低 (建议至少20G，当前${available_gb}G)"
        warning_count=$((warning_count + 1))
    fi
    
    # 8. 检查内存
    local total_mem=$(free -m | awk '/^Mem:/{print $2}')
    log "系统内存: ${total_mem}MB"
    
    if [ $total_mem -lt 1024 ]; then
        log "⚠️  警告: 内存较低 (建议至少1GB)"
        warning_count=$((warning_count + 1))
    fi
    
    # 9. 检查CPU核心数
    local cpu_cores=$(nproc)
    log "CPU核心数: $cpu_cores"
    
    if [ $cpu_cores -lt 2 ]; then
        log "⚠️  警告: CPU核心数较少，编译速度会受影响"
        warning_count=$((warning_count + 1))
    fi
    
    # 10. 检查C库配置
    log "🔧 检查C库配置..."
    if [ -f ".config" ]; then
        if grep -q "CONFIG_EXTERNAL_TOOLCHAIN=y" .config; then
            log "ℹ️  使用外部工具链"
        elif grep -q "CONFIG_USE_MUSL=y" .config; then
            log "✅ 配置为使用musl C库"
        elif grep -q "CONFIG_USE_GLIBC=y" .config; then
            log "✅ 配置为使用glibc C库"
        elif grep -q "CONFIG_USE_UCLIBC=y" .config; then
            log "✅ 配置为使用uclibc C库"
        else
            log "⚠️  警告: 未明确指定C库类型"
            warning_count=$((warning_count + 1))
        fi
    fi
    
    # 总结
    if [ $error_count -eq 0 ]; then
        if [ $warning_count -eq 0 ]; then
            log "✅ 前置检查通过，可以开始编译"
        else
            log "⚠️  前置检查通过，但有 $warning_count 个警告，建议修复"
        fi
        return 0
    else
        log "❌ 前置检查发现 $error_count 个错误，$warning_count 个警告，请修复后再编译"
        return 1
    fi
}

setup_environment() {
    log "=== 安装编译依赖包 ==="
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
    
    # Git LFS
    local git_lfs_packages=(
        git-lfs
    )
    
    log "安装基础编译工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${base_packages[@]}" || handle_error "安装基础编译工具失败"
    
    log "安装Git LFS..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${git_lfs_packages[@]}" || handle_error "安装Git LFS失败"
    
    log "安装网络工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${network_packages[@]}" || handle_error "安装网络工具失败"
    
    log "安装文件系统工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${filesystem_packages[@]}" || handle_error "安装文件系统工具失败"
    
    log "安装调试工具..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${debug_packages[@]}" || handle_error "安装调试工具失败"
    
    # 初始化Git LFS
    git lfs install || log "⚠️  Git LFS初始化失败，但将继续"
    
    # 检查重要工具是否安装成功
    log "=== 验证工具安装 ==="
    local important_tools=("gcc" "g++" "make" "git" "git-lfs" "python3" "cmake" "flex" "bison")
    for tool in "${important_tools[@]}"; do
        if command -v $tool >/dev/null 2>&1; then
            log "✅ $tool 已安装: $(which $tool)"
        else
            log "❌ $tool 未安装"
        fi
    done
    
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
            log "ℹ️  21.02 版本已内置 TurboACC，无需额外添加"
        fi
    else
        log "ℹ️  基础模式不添加 TurboACC 支持"
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
        log "⚠️  警告: 可用空间(${available_gb}G)可能不足，建议至少${estimated_space}G"
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
        echo "CONFIG_PACKAGE_kmod-usb-xhci-mtk=y" >> .config
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
            echo "CONFIG_PACKAGE_luci-i18n-wechatpush-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-sqm-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-hd-idle-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-accesscontrol-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-vlmcsd-zh-cn=y" >> .config
            echo "CONFIG_PACKAGE_luci-i18n-smartdns-zh-cn=y" >> .config
        fi
    fi
    
    # 处理额外插件
    if [ -n "$extra_packages" ]; then
        log "🔧 处理额外安装插件: $extra_packages"
        IFS=';' read -ra EXTRA_PKGS <<< "$extra_packages"
        for pkg_cmd in "${EXTRA_PKGS[@]}"; do
            if [ -n "$pkg_cmd" ]; then
                pkg_cmd_clean=$(echo "$pkg_cmd" | xargs)
                if [[ "$pkg_cmd_clean" == +* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log "启用插件: $pkg_name"
                    echo "CONFIG_PACKAGE_${pkg_name}=y" >> .config
                elif [[ "$pkg_cmd_clean" == -* ]]; then
                    pkg_name="${pkg_cmd_clean:1}"
                    log "禁用插件: $pkg_name"
                    echo "# CONFIG_PACKAGE_${pkg_name} is not set" >> .config
                else
                    log "启用插件: $pkg_cmd_clean"
                    echo "CONFIG_PACKAGE_${pkg_cmd_clean}=y" >> .config
                fi
            fi
        done
    fi
    
    log "✅ 智能配置生成完成"
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
        log "⚠️  警告: 有 $missing_count 个关键USB驱动未启用，可能会影响USB功能"
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
    
    log "=== 应用配置并显示详情 ==="
    
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
        
        # 确保kmod-phy-qcom-dwc3启用（如果是高通平台）
        if [ "$TARGET" = "ipq40xx" ] && ! grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config; then
            echo "  修复: 启用 kmod-phy-qcom-dwc3"
            sed -i 's/^# CONFIG_PACKAGE_kmod-phy-qcom-dwc3 is not set$/CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y/' .config
            if ! grep -q "^CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" .config; then
                echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
            fi
            echo "  ✅ 已修复 kmod-phy-qcom-dwc3"
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
    
    log "🔄 运行 make defconfig..."
    make defconfig || handle_error "应用配置失败"
    
    log "🚨 强制启用关键USB驱动（防止defconfig删除）"
    # 确保 USB 3.0 关键驱动被启用
    echo "CONFIG_PACKAGE_kmod-usb-xhci-hcd=y" >> .config
    
    # 根据平台启用专用驱动
    if [ "$TARGET" = "ipq40xx" ]; then
        echo "CONFIG_PACKAGE_kmod-phy-qcom-dwc3=y" >> .config
        echo "CONFIG_PACKAGE_kmod-usb-dwc3-qcom=y" >> .config
    fi
    
    # 其他关键USB驱动
    echo "CONFIG_PACKAGE_kmod-usb3=y" >> .config
    echo "CONFIG_PACKAGE_kmod-usb-dwc3=y" >> .config
    
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
        log "⚠️  网络连接可能有问题"
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
        log "ℹ️  没有下载新的依赖包"
    fi
    
    # 检查下载日志中的错误
    if grep -q "ERROR\|Failed\|404" download.log 2>/dev/null; then
        log "⚠️  下载过程中发现错误:"
        grep -E "ERROR|Failed|404" download.log | head -10
    fi
    
    log "✅ 依赖包下载完成"
}

build_firmware() {
    local enable_cache=$1
    load_env
    cd $BUILD_DIR || handle_error "进入构建目录失败"
    
    log "=== 编译固件 ==="
    
    # 设置工具链环境
    setup_toolchain_env
    
    # 编译前最终检查
    log "编译前最终检查..."
    if [ ! -f ".config" ]; then
        log "❌ 错误: .config 文件不存在"
        exit 1
    fi
    
    if [ ! -d "staging_dir" ]; then
        log "⚠️  警告: staging_dir 目录不存在"
    fi
    
    if [ ! -d "dl" ]; then
        log "⚠️  警告: dl 目录不存在"
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
        log "⚠️  内存较低(${total_mem}MB)，减少并行任务到 $make_jobs"
    fi
    
    # 开始编译
    if [ "$enable_cache" = "true" ]; then
        log "启用编译缓存，使用 $make_jobs 个并行任务"
        make -j$make_jobs V=s 2>&1 | tee build.log
        BUILD_EXIT_CODE=${PIPESTATUS[0]}
    else
        log "普通编译模式，使用 $make_jobs 个并行任务"
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
                log "⚠️  发现未定义引用错误"
            fi
            
            if grep -q "No such file" build.log; then
                log "⚠️  发现文件不存在错误"
            fi
            
            if grep -q "out of memory\|Killed process" build.log; then
                log "⚠️  可能是内存不足导致编译失败"
            fi
            
            # 特别检查编译器错误
            if grep -q "compiler.*not found" build.log; then
                log "🚨 发现编译器未找到错误"
                log "检查工具链路径..."
                if [ -d "staging_dir" ]; then
                    find staging_dir -name "*gcc*" 2>/dev/null | head -10
                fi
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
        log "⚠️  警告: 磁盘空间较低，建议清理"
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
                log "⚠️  警告: 固件文件可能太小"
            elif [ $total_size_mb -gt 100 ]; then
                log "⚠️  警告: 固件文件可能太大"
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
        log "ℹ️  构建目录不存在，无需清理"
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
        "load_toolchain")
            load_toolchain
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
        "save_toolchain")
            save_toolchain
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
        "init_toolchain_dir")
            init_toolchain_dir
            ;;
        "check_large_files")
            check_large_files
            ;;
        "check_toolchain_completeness")
            check_toolchain_completeness
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  setup_environment, create_build_dir, initialize_build_env"
            echo "  add_turboacc_support, configure_feeds, install_turboacc_packages"
            echo "  pre_build_space_check, generate_config, verify_usb_config, check_usb_drivers_integrity, apply_config"
            echo "  fix_network, download_dependencies, load_toolchain, integrate_custom_files"
            echo "  pre_build_error_check, build_firmware, save_toolchain, post_build_space_check"
            echo "  check_firmware_files, cleanup, init_toolchain_dir, check_large_files, check_toolchain_completeness"
            exit 1
            ;;
    esac
}

main "$@"
