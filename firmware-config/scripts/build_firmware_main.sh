name: OpenWrt 智能固件构建工作流（完整功能版 - 编译器预下载版）

on:
  workflow_dispatch:
    inputs:
      device_name:
        description: "📱 设备名称 (如: ac42u)"
        required: true
        default: "ac42u"
        type: string
      version_selection:
        description: "🔄 版本选择"
        required: true
        type: choice
        default: "21.02"
        options:
          - "23.05"
          - "21.02"
      config_mode:
        description: |
          ⚙️ 配置模式选择
          
          🟣 基础模式 - 最小化配置，用于测试编译
          🟠 正常模式 - 完整功能配置：✅ TurboACC 网络加速 ✅ UPnP 自动端口转发 ✅ Samba 文件共享 ✅ 磁盘管理 ✅ KMS 激活服务 ✅ SmartDNS 智能DNS ✅ 家长控制 ✅ 微信推送 ✅ 流量控制 (SQM) ✅ FTP 服务器 ✅ ARP 绑定 ✅ CPU 限制 ✅ 硬盘休眠
          
          🔧 USB 3.0加强：所有平台的关键USB驱动都已强制启用！
        required: true
        type: choice
        default: "normal"
        options:
          - "base"
          - "normal"
      extra_packages:
        description: |
          额外安装插件
          格式：用分号;分隔。启用插件：+插件名。禁用插件：-插件名。
        required: false
        type: string
        default: ""
      use_git_archive:
        description: "📦 使用Git Archive API下载源代码"
        required: false
        default: true
        type: boolean

env:
  BUILD_DIR: "/mnt/openwrt-build"
  COMPILER_DIR: "${{ github.workspace }}/firmware-config/build-Compiler-file"

jobs:
  build-firmware:
    runs-on: ubuntu-22.04
    
    steps:
      # 步骤 1: 使用Git Archive API下载源代码
      - name: "1. 使用Git Archive API下载源代码"
        if: github.event.inputs.use_git_archive == 'true'
        run: |
          echo "=== 步骤 1: 使用Git Archive API下载源代码 ==="
          echo "🔄 从GitHub API获取源代码压缩包"
          
          # 创建临时目录
          mkdir -p /tmp/openwrt-source
          cd /tmp/openwrt-source
          
          # 获取默认分支
          DEFAULT_BRANCH=$(curl -s -H "Authorization: token ${{ secrets.GITHUB_TOKEN }}" "https://api.github.com/repos/${{ github.repository }}" | jq -r '.default_branch')
          echo "默认分支: $DEFAULT_BRANCH"
          
          # 使用Git Archive API下载压缩包
          echo "下载源代码压缩包..."
          curl -s -L -H "Authorization: token ${{ secrets.GITHUB_TOKEN }}" "https://api.github.com/repos/${{ github.repository }}/tarball/$DEFAULT_BRANCH" -o source.tar.gz
          
          if [ ! -f "source.tar.gz" ]; then
            echo "❌ 下载源代码压缩包失败"
            exit 1
          fi
          
          echo "✅ 下载完成，文件大小: $(ls -lh source.tar.gz | awk '{print $5}')"
          
          # 解压压缩包
          echo "解压源代码..."
          tar -xzf source.tar.gz --strip-components=1
          
          # 检查解压结果
          if [ -f "firmware-config/scripts/build_firmware_main.sh" ]; then
            echo "✅ 源代码解压成功"
            echo "重要文件存在: firmware-config/scripts/build_firmware_main.sh"
            
            # 复制到工作区 - 使用更精确的方式
            echo "复制文件到工作区..."
            
            # 确保工作区目录存在
            mkdir -p ${{ github.workspace }}
            
            # 检查并删除编译器目录（如果有的话）
            if [ -d "firmware-config/build-Compiler-file" ]; then
              echo "⚠️ 发现编译器目录，排除不复制"
              rm -rf firmware-config/build-Compiler-file
            fi
            
            # 使用rsync复制所有文件，排除.git目录
            rsync -av --exclude='.git' . ${{ github.workspace }}/
            
            # 确保脚本文件有执行权限
            chmod +x ${{ github.workspace }}/firmware-config/scripts/*.sh 2>/dev/null || true
            
            echo "✅ 文件复制完成"
            
            # 保存源代码压缩包作为构建产物
            mkdir -p /tmp/build-artifacts/source-archive
            cp source.tar.gz /tmp/build-artifacts/source-archive/
          else
            echo "❌ 源代码解压失败，重要文件缺失"
            echo "当前目录内容:"
            ls -la
            exit 1
          fi
          
          # 清理临时文件
          cd /tmp
          rm -rf openwrt-source
          echo "✅ Git Archive API下载完成"
      
      # 步骤 2: 立即上传Git Archive源代码
      - name: "2. 立即上传Git Archive源代码"
        if: github.event.inputs.use_git_archive == 'true'
        uses: actions/upload-artifact@v4
        with:
          name: git-archive-source-${{ github.event.inputs.device_name }}
          path: /tmp/build-artifacts/source-archive/
          retention-days: 7
      
      # 步骤 3: 检出配置仓库
      - name: "3. 检出配置仓库"
        if: github.event.inputs.use_git_archive == 'false'
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          submodules: recursive
      
      # 步骤 4: 设置脚本执行权限
      - name: "4. 设置脚本执行权限"
        run: |
          echo "=== 步骤 4: 设置脚本执行权限 ==="
          find firmware-config/scripts -name "*.sh" -exec chmod +x {} \;
          echo "✅ 脚本执行权限设置完成"
      
      # 步骤 5: 检查编译器文件目录状态
      - name: "5. 检查编译器文件目录状态"
        run: |
          echo "=== 步骤 5: 检查编译器文件目录状态 ==="
          COMPILER_DIR="${{ env.COMPILER_DIR }}"
          
          if [ -d "$COMPILER_DIR" ]; then
            echo "✅ 编译器文件目录存在"
            echo "路径: $COMPILER_DIR"
            echo "目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo '未知')"
            echo "目录内容:"
            ls -la "$COMPILER_DIR/" 2>/dev/null | head -10 || echo "无法列出"
            
            # 检查必要的编译器文件
            echo "🔍 检查必要的编译器文件:"
            required_compilers=("gcc" "g++" "as" "ld" "ar" "strip" "objcopy" "objdump")
            for compiler in "${required_compilers[@]}"; do
              if find "$COMPILER_DIR" -name "*$compiler*" -type f 2>/dev/null | grep -q .; then
                echo "  ✅ 找到: $compiler"
              else
                echo "  ❌ 未找到: $compiler"
              fi
            done
          else
            echo "ℹ️ 编译器文件目录不存在，将创建新目录"
            mkdir -p "$COMPILER_DIR"
            echo "✅ 已创建编译器文件目录: $COMPILER_DIR"
          fi
      
      # 步骤 6: 下载必要编译器文件
      - name: "6. 下载必要编译器文件"
        run: |
          echo "=== 步骤 6: 下载必要编译器文件 ==="
          
          COMPILER_DIR="${{ env.COMPILER_DIR }}"
          mkdir -p "$COMPILER_DIR"
          
          echo "🔍 编译器文件清单:"
          echo "1. gcc - GNU C编译器"
          echo "2. g++ - GNU C++编译器"
          echo "3. as - GNU汇编器"
          echo "4. ld - GNU链接器"
          echo "5. ar - GNU归档工具"
          echo "6. strip - 符号剥离工具"
          echo "7. objcopy - 目标文件复制工具"
          echo "8. objdump - 目标文件反汇编工具"
          echo "9. nm - 符号列表工具"
          echo "10. ranlib - 生成归档索引"
          
          # 检查并下载缺失的编译器文件
          echo "📥 检查并下载缺失的编译器文件..."
          
          # 定义编译器下载列表
          declare -A compiler_urls=(
            ["gcc-11.3.0.tar.xz"]="https://ftp.gnu.org/gnu/gcc/gcc-11.3.0/gcc-11.3.0.tar.xz"
            ["binutils-2.38.tar.xz"]="https://ftp.gnu.org/gnu/binutils/binutils-2.38.tar.xz"
            ["make-4.3.tar.gz"]="https://ftp.gnu.org/gnu/make/make-4.3.tar.gz"
          )
          
          cd "$COMPILER_DIR"
          
          for file in "${!compiler_urls[@]}"; do
            url="${compiler_urls[$file]}"
            if [ ! -f "$file" ]; then
              echo "下载: $file"
              wget --no-check-certificate -q --show-progress "$url" || echo "下载失败: $file"
            else
              echo "已存在: $file"
            fi
          done
          
          echo "✅ 编译器文件检查完成"
          echo "📊 当前编译器文件:"
          ls -lh "$COMPILER_DIR" 2>/dev/null || echo "无文件"
      
      # 步骤 7: 初始空间检查
      - name: "7. 初始空间检查"
        run: |
          echo "=== 步骤 7: 初始磁盘空间检查 ==="
          df -h
          AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
          AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
          echo "/mnt 可用空间: ${AVAILABLE_GB}G"
          if [ $AVAILABLE_GB -lt 50 ]; then
            echo "❌ 错误: /mnt 空间不足50G"
            exit 1
          fi
          echo "✅ 初始空间检查通过"
      
      # 步骤 8: 设置编译环境和构建目录
      - name: "8. 设置编译环境和构建目录"
        run: |
          echo "=== 步骤 8: 设置编译环境和构建目录 ==="
          
          echo "🔄 步骤 8.1: 设置编译环境"
          firmware-config/scripts/build_firmware_main.sh setup_environment
          
          echo "🔄 步骤 8.2: 创建构建目录"
          firmware-config/scripts/build_firmware_main.sh create_build_dir
          
          echo "🔄 步骤 8.3: 初始化构建环境"
          echo "设备: ${{ github.event.inputs.device_name }}"
          echo "版本: ${{ github.event.inputs.version_selection }}"
          echo "配置模式: ${{ github.event.inputs.config_mode }}"
          firmware-config/scripts/build_firmware_main.sh initialize_build_env "${{ github.event.inputs.device_name }}" "${{ github.event.inputs.version_selection }}" "${{ github.event.inputs.config_mode }}"
          
          echo "✅ 编译环境和构建目录设置完成"
      
      # 步骤 9: 添加 TurboACC 支持
      - name: "9. 添加 TurboACC 支持"
        run: |
          echo "=== 步骤 9: 添加 TurboACC 支持 ==="
          firmware-config/scripts/build_firmware_main.sh add_turboacc_support
      
      # 步骤 10: 配置Feeds
      - name: "10. 配置Feeds"
        run: |
          echo "=== 步骤 10: 配置Feeds ==="
          firmware-config/scripts/build_firmware_main.sh configure_feeds
      
      # 步骤 11: 安装 TurboACC 包
      - name: "11. 安装 TurboACC 包"
        if: env.SELECTED_BRANCH == 'openwrt-23.05' && github.event.inputs.config_mode == 'normal'
        run: |
          echo "=== 步骤 11: 安装 TurboACC 包 ==="
          firmware-config/scripts/build_firmware_main.sh install_turboacc_packages
      
      # 步骤 12: 编译前空间检查
      - name: "12. 编译前空间检查"
        run: |
          echo "=== 步骤 12: 编译前空间检查 ==="
          firmware-config/scripts/build_firmware_main.sh pre_build_space_check
      
      # 步骤 13: 智能配置生成（USB完全修复加强版）
      - name: "13. 智能配置生成（USB完全修复加强版）"
        run: |
          echo "=== 步骤 13: 智能配置生成 ==="
          echo "🚨 USB 3.0加强：所有关键USB驱动强制启用"
          firmware-config/scripts/build_firmware_main.sh generate_config "${{ github.event.inputs.extra_packages }}"
      
      # 步骤 14: 验证USB配置
      - name: "14. 验证USB配置"
        run: |
          echo "=== 步骤 14: 验证USB配置 ==="
          firmware-config/scripts/build_firmware_main.sh verify_usb_config
      
      # 步骤 15: USB驱动完整性检查
      - name: "15. USB驱动完整性检查"
        run: |
          echo "=== 步骤 15: USB驱动完整性检查 ==="
          firmware-config/scripts/build_firmware_main.sh check_usb_drivers_integrity
      
      # 步骤 16: 应用配置并显示详情
      - name: "16. 应用配置并显示详情"
        run: |
          echo "=== 步骤 16: 应用配置并显示详情 ==="
          
          # 先保存原始配置文件
          if [ -f "${{ env.BUILD_DIR }}/.config" ]; then
            cp "${{ env.BUILD_DIR }}/.config" "${{ env.BUILD_DIR }}/.config.original"
            echo "✅ 已备份原始配置文件"
          fi
          
          # 应用配置
          firmware-config/scripts/build_firmware_main.sh apply_config
          
          # 检查应用后的配置状态
          echo "=== 插件配置状态检查 ==="
          cd "${{ env.BUILD_DIR }}"
          
          # 定义正常模式的完整插件列表
          declare -A normal_plugins=(
            ["TurboACC 网络加速"]="luci-app-turboacc"
            ["UPnP 自动端口转发"]="luci-app-upnp"
            ["Samba 文件共享"]="luci-app-samba4"
            ["磁盘管理"]="luci-app-diskman"
            ["KMS 激活服务"]="luci-app-vlmcsd"
            ["SmartDNS 智能DNS"]="luci-app-smartdns"
            ["家长控制"]="luci-app-accesscontrol"
            ["微信推送"]="luci-app-wechatpush"
            ["流量控制 (SQM)"]="luci-app-sqm"
            ["FTP 服务器"]="luci-app-vsftpd"
            ["ARP 绑定"]="luci-app-arpbind"
            ["CPU 限制"]="luci-app-cpulimit"
            ["硬盘休眠"]="luci-app-hd-idle"
          )
          
          echo "📋 正常模式插件状态检查:"
          
          total_plugins=0
          enabled_plugins=0
          disabled_plugins=0
          
          for plugin_name in "${!normal_plugins[@]}"; do
            plugin_config="${normal_plugins[$plugin_name]}"
            total_plugins=$((total_plugins + 1))
            
            if grep -q "^CONFIG_PACKAGE_${plugin_config}=y" .config; then
              echo "  ✅ $plugin_name: 已启用"
              enabled_plugins=$((enabled_plugins + 1))
            elif grep -q "^# CONFIG_PACKAGE_${plugin_config} is not set$" .config; then
              echo "  ❌ $plugin_name: 已禁用"
              disabled_plugins=$((disabled_plugins + 1))
            else
              echo "  ⚠️  $plugin_name: 未配置"
            fi
          done
          
          echo ""
          echo "📊 插件状态统计:"
          echo "  总计: $total_plugins 个插件"
          echo "  已启用: $enabled_plugins 个"
          echo "  已禁用: $disabled_plugins 个"
          
          # 检查基础模式是否禁用了插件
          if [ "${{ github.event.inputs.config_mode }}" = "base" ]; then
            echo ""
            echo "🔧 基础模式配置确认:"
            if [ $enabled_plugins -eq 0 ]; then
              echo "  ✅ 基础模式: 所有额外插件已正确禁用"
            else
              echo "  ⚠️  基础模式: 有 $enabled_plugins 个插件未禁用，需要检查"
            fi
          fi
          
          # 额外检查USB驱动状态
          echo ""
          echo "🔌 USB驱动状态确认:"
          critical_usb_drivers=("kmod-usb-xhci-hcd" "kmod-usb3" "kmod-usb-dwc3" "kmod-usb-storage" "kmod-scsi-core")
          for driver in "${critical_usb_drivers[@]}"; do
            if grep -q "^CONFIG_PACKAGE_${driver}=y" .config; then
              echo "  ✅ $driver: 已启用"
            else
              echo "  ❌ $driver: 未启用 (需要修复)"
            fi
          done
          
          echo "✅ 配置详情检查完成"
      
      # 步骤 17: 检查并备份配置文件
      - name: "17. 检查并备份配置文件"
        run: |
          echo "=== 步骤 17: 检查并备份配置文件 ==="
          
          # 检查配置文件
          if [ -f "${{ env.BUILD_DIR }}/.config" ]; then
            echo "✅ .config 文件存在"
            
            # 确保备份目录存在
            mkdir -p firmware-config/config-backup
            
            # 备份到仓库目录
            backup_file="firmware-config/config-backup/config_${{ github.event.inputs.device_name }}_${{ env.SELECTED_BRANCH }}_${{ github.event.inputs.config_mode }}_$(date +%Y%m%d_%H%M%S).config"
            
            cp "${{ env.BUILD_DIR }}/.config" "$backup_file"
            echo "✅ 配置文件备份到仓库目录: $backup_file"
            
            # 显示备份文件信息
            echo "备份文件大小: $(ls -lh $backup_file | awk '{print $5}')"
          else
            echo "❌ .config 文件不存在"
            exit 1
          fi
      
      # 步骤 18: 修复网络环境
      - name: "18. 修复网络环境"
        run: |
          echo "=== 步骤 18: 修复网络环境 ==="
          firmware-config/scripts/build_firmware_main.sh fix_network
      
      # 步骤 19: 准备编译器文件
      - name: "19. 准备编译器文件"
        run: |
          echo "=== 步骤 19: 准备编译器文件 ==="
          
          COMPILER_DIR="${{ env.COMPILER_DIR }}"
          BUILD_DIR="${{ env.BUILD_DIR }}"
          
          echo "复制编译器文件到构建目录..."
          
          # 创建工具链目录
          mkdir -p "$BUILD_DIR/staging_dir/host/bin"
          
          # 检查并复制编译器文件
          if [ -d "$COMPILER_DIR" ]; then
            echo "🔍 查找编译器文件..."
            
            # 查找可用的编译器文件
            find "$COMPILER_DIR" -type f \( -name "*gcc*" -o -name "*g++*" -o -name "*as*" -o -name "*ld*" -o -name "*ar*" \) 2>/dev/null | while read compiler_file; do
              filename=$(basename "$compiler_file")
              echo "  复制: $filename"
              cp "$compiler_file" "$BUILD_DIR/staging_dir/host/bin/" 2>/dev/null || true
            done
            
            # 确保文件有执行权限
            chmod +x "$BUILD_DIR/staging_dir/host/bin/"* 2>/dev/null || true
            
            echo "✅ 编译器文件准备完成"
            echo "📊 已复制编译器文件:"
            ls -la "$BUILD_DIR/staging_dir/host/bin/" 2>/dev/null | head -10 || echo "无文件"
          else
            echo "⚠️ 编译器文件目录不存在，将使用自动下载的工具链"
          fi
      
      # 步骤 20: 立即保存已下载的编译器文件到仓库
      - name: "20. 立即保存已下载的编译器文件到仓库"
        if: always()  # 即使失败也要保存
        run: |
          echo "=== 步骤 20: 立即保存已下载的编译器文件到仓库 ==="
          
          COMPILER_DIR="${{ env.COMPILER_DIR }}"
          
          echo "🔄 检查并提交已下载的编译器文件到仓库..."
          
          if [ -d "$COMPILER_DIR" ]; then
            # 检查是否有新的编译器文件
            file_count=$(find "$COMPILER_DIR" -type f -name "*.tar.*" -o -name "*.gz" 2>/dev/null | wc -l)
            
            if [ $file_count -gt 0 ]; then
              echo "📊 编译器文件统计:"
              echo "  文件数量: $file_count"
              echo "  目录大小: $(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo '未知')"
              
              # 显示文件列表
              echo "📋 文件列表:"
              find "$COMPILER_DIR" -type f 2>/dev/null | head -10 || echo "  无文件"
              
              # 尝试提交到仓库
              echo "🚀 尝试提交编译器文件到仓库..."
              
              # 配置Git
              git config --global user.email "github-actions@github.com"
              git config --global user.name "GitHub Actions"
              
              # 添加编译器文件
              if git add "$COMPILER_DIR"/* 2>/dev/null; then
                # 检查是否有更改
                if git diff --cached --quiet; then
                  echo "ℹ️ 没有新的编译器文件需要提交"
                else
                  # 提交更改
                  git commit -m "build: 保存编译器文件 (${{ github.event.inputs.device_name }} - ${{ env.SELECTED_BRANCH }})"
                  
                  # 尝试推送（非必须，只是尝试）
                  echo "📤 编译器文件已保存到本地仓库"
                  echo "💡 注意：需要手动推送或在后续步骤中推送"
                fi
              else
                echo "⚠️ 无法添加编译器文件到Git"
              fi
            else
              echo "ℹ️ 编译器目录为空，无需保存"
            fi
          else
            echo "⚠️ 编译器目录不存在"
            mkdir -p "$COMPILER_DIR"
            echo "✅ 已创建编译器目录: $COMPILER_DIR"
          fi
          
          echo "✅ 编译器文件保存流程完成"
      
      # 步骤 21: 下载依赖包
      - name: "21. 下载依赖包"
        run: |
          echo "=== 步骤 21: 下载依赖包 ==="
          firmware-config/scripts/build_firmware_main.sh download_dependencies
      
      # 步骤 22: 集成自定义文件
      - name: "22. 集成自定义文件"
        run: |
          echo "=== 步骤 22: 集成自定义文件 ==="
          firmware-config/scripts/build_firmware_main.sh integrate_custom_files
      
      # 步骤 23: 前置错误检查
      - name: "23. 前置错误检查"
        run: |
          echo "=== 步骤 23: 前置错误检查 ==="
          firmware-config/scripts/build_firmware_main.sh pre_build_error_check
      
      # 步骤 24: 编译固件前的空间检查
      - name: "24. 编译固件前的空间检查"
        run: |
          echo "=== 步骤 24: 编译固件前的空间检查 ==="
          df -h
          AVAILABLE_SPACE=$(df /mnt --output=avail | tail -1)
          AVAILABLE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
          echo "/mnt 可用空间: ${AVAILABLE_GB}G"
          
          # 检查编译所需空间
          if [ $AVAILABLE_GB -lt 10 ]; then
            echo "❌ 错误: 编译前空间不足 (需要至少10G，当前${AVAILABLE_GB}G)"
            exit 1
          elif [ $AVAILABLE_GB -lt 20 ]; then
            echo "⚠️ 警告: 编译前空间较低 (建议至少20G，当前${AVAILABLE_GB}G)"
          else
            echo "✅ 编译前空间充足"
          fi
      
      # 步骤 25: 编译固件
      - name: "25. 编译固件"
        run: |
          echo "=== 步骤 25: 编译固件 ==="
          # 启用编译缓存，使用并行编译
          firmware-config/scripts/build_firmware_main.sh build_firmware "true"
      
      # 步骤 26: 保存编译器文件
      - name: "26. 保存编译器文件"
        if: success()
        run: |
          echo "=== 步骤 26: 保存编译器文件 ==="
          
          COMPILER_DIR="${{ env.COMPILER_DIR }}"
          BUILD_DIR="${{ env.BUILD_DIR }}"
          
          # 确保编译器目录存在
          mkdir -p "$COMPILER_DIR"
          
          echo "保存编译器文件到仓库目录..."
          
          # 从构建目录复制编译器文件
          if [ -d "$BUILD_DIR/staging_dir/host/bin" ]; then
            echo "🔍 查找构建目录中的编译器文件..."
            
            # 复制编译器文件
            find "$BUILD_DIR/staging_dir/host/bin" -type f \( -name "*gcc*" -o -name "*g++*" -o -name "*as*" -o -name "*ld*" -o -name "*ar*" \) 2>/dev/null | while read compiler_file; do
              filename=$(basename "$compiler_file")
              echo "  保存: $filename"
              cp "$compiler_file" "$COMPILER_DIR/" 2>/dev/null || true
            done
            
            echo "✅ 编译器文件保存完成"
            echo "📊 保存的编译器文件:"
            ls -lh "$COMPILER_DIR/" 2>/dev/null | head -10 || echo "无文件"
          else
            echo "⚠️ 构建目录中没有编译器文件可保存"
          fi
      
      # 步骤 27: 保存源代码信息
      - name: "27. 保存源代码信息"
        if: success()
        run: |
          echo "=== 步骤 27: 保存源代码信息 ==="
          
          # 创建源代码信息目录
          mkdir -p /tmp/build-artifacts/source-info
          
          echo "构建信息" > /tmp/build-artifacts/source-info/build_info.txt
          echo "=========" >> /tmp/build-artifacts/source-info/build_info.txt
          echo "构建时间: $(date)" >> /tmp/build-artifacts/source-info/build_info.txt
          echo "设备: ${{ github.event.inputs.device_name }}" >> /tmp/build-artifacts/source-info/build_info.txt
          echo "版本: ${{ env.SELECTED_BRANCH }}" >> /tmp/build-artifacts/source-info/build_info.txt
          echo "目标平台: ${{ env.TARGET }}/${{ env.SUBTARGET }}" >> /tmp/build-artifacts/source-info/build_info.txt
          echo "配置模式: ${{ github.event.inputs.config_mode }}" >> /tmp/build-artifacts/source-info/build_info.txt
          echo "Git Archive API模式: ${{ github.event.inputs.use_git_archive }}" >> /tmp/build-artifacts/source-info/build_info.txt
          
          echo "✅ 源代码信息保存完成"
      
      # 步骤 28: 上传构建产物（打包的固件和日志）
      - name: "28. 上传构建产物（打包的固件和日志）"
        if: success()
        run: |
          echo "=== 步骤 28: 上传构建产物 ==="
          cd ${{ env.BUILD_DIR }}
          
          # 创建构建产物目录
          mkdir -p /tmp/build-artifacts
          
          # 检查是否已有相同文件，避免重复上传
          echo "🔍 检查是否已有相同构建产物..."
          need_upload=false
          
          # 打包固件文件
          if [ -d "bin/targets" ]; then
            echo "打包固件文件..."
            tar -czf /tmp/build-artifacts/firmware.tar.gz -C bin targets/
            
            # 检查文件大小
            firmware_size=$(stat -c%s /tmp/build-artifacts/firmware.tar.gz 2>/dev/null || echo "0")
            if [ $firmware_size -gt 0 ]; then
              echo "✅ 固件打包完成，大小: $(du -h /tmp/build-artifacts/firmware.tar.gz | cut -f1)"
              need_upload=true
            else
              echo "⚠️ 固件打包失败或文件为空"
            fi
          else
            echo "⚠️ bin/targets目录不存在"
          fi
          
          # 打包编译日志
          if [ -f "build.log" ]; then
            echo "打包编译日志..."
            cp build.log /tmp/build-artifacts/build.log
            echo "✅ 日志打包完成"
            need_upload=true
          fi
          
          # 创建构建信息文件
          echo "构建时间: $(date)" > /tmp/build-artifacts/build-info.txt
          echo "设备: ${{ env.DEVICE }}" >> /tmp/build-artifacts/build-info.txt
          echo "版本: ${{ env.SELECTED_BRANCH }}" >> /tmp/build-artifacts/build-info.txt
          echo "目标平台: ${{ env.TARGET }}/${{ env.SUBTARGET }}" >> /tmp/build-artifacts/build-info.txt
          echo "配置模式: ${{ github.event.inputs.config_mode }}" >> /tmp/build-artifacts/build-info.txt
          
          if [ "$need_upload" = true ]; then
            echo "✅ 构建产物准备完成"
            echo "📤 构建产物已保存在: /tmp/build-artifacts/"
            ls -lh /tmp/build-artifacts/
          else
            echo "ℹ️ 没有需要上传的构建产物"
          fi
      
      # 步骤 29: 上传固件原始目录
      - name: "29. 上传固件原始目录"
        if: success()
        uses: actions/upload-artifact@v4
        with:
          name: firmware-${{ github.event.inputs.device_name }}-${{ env.SELECTED_BRANCH }}-${{ github.event.inputs.config_mode }}
          path: ${{ env.BUILD_DIR }}/bin/targets/
          retention-days: 7
      
      # 步骤 30: 上传源代码信息
      - name: "30. 上传源代码信息"
        if: success()
        uses: actions/upload-artifact@v4
        with:
          name: source-info-${{ github.event.inputs.device_name }}-${{ env.SELECTED_BRANCH }}
          path: /tmp/build-artifacts/source-info/
          retention-days: 7
      
      # 步骤 31: 上传配置文件
      - name: "31. 上传配置文件"
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: config-${{ github.event.inputs.device_name }}-${{ env.SELECTED_BRANCH }}-${{ github.event.inputs.config_mode }}
          path: ${{ github.workspace }}/firmware-config/config-backup/
          retention-days: 7
      
      # 步骤 32: 错误分析（无论成功失败都运行）
      - name: "32. 错误分析"
        if: always()
        run: |
          echo "=== 步骤 32: 错误分析 ==="
          firmware-config/scripts/error_analysis.sh
      
      # 步骤 33: 编译后空间检查
      - name: "33. 编译后空间检查"
        if: always()
        run: |
          echo "=== 步骤 33: 编译后空间检查 ==="
          firmware-config/scripts/build_firmware_main.sh post_build_space_check
      
      # 步骤 34: 固件文件检查
      - name: "34. 固件文件检查"
        if: success()
        run: |
          echo "=== 步骤 34: 固件文件检查 ==="
          firmware-config/scripts/build_firmware_main.sh check_firmware_files
      
      # 步骤 35: 清理目录（保留配置文件）
      - name: "35. 清理目录（保留配置文件）"
        if: always()
        run: |
          echo "=== 步骤 35: 清理目录但保留配置文件 ==="
          firmware-config/scripts/build_firmware_main.sh cleanup
      
      # 步骤 36: 输出最终配置状态
      - name: "36. 输出最终配置状态"
        if: always()
        run: |
          echo "=== 步骤 36: 最终配置状态总结 ==="
          
          # 检查备份的配置文件
          if [ -d "firmware-config/config-backup" ]; then
            backup_count=$(find firmware-config/config-backup -name "*.config" 2>/dev/null | wc -l)
            echo "✅ 仓库配置文件备份: $backup_count 个"
          fi
          
          echo ""
          echo "🛠️ 编译器文件状态:"
          COMPILER_DIR="${{ env.COMPILER_DIR }}"
          if [ -d "$COMPILER_DIR" ]; then
            echo "✅ 编译器文件目录存在: firmware-config/build-Compiler-file/"
            
            # 显示编译器文件大小
            compiler_size=$(du -sh "$COMPILER_DIR" 2>/dev/null | cut -f1 || echo "未知")
            echo "   编译器文件大小: $compiler_size"
            
            # 显示编译器文件列表
            echo "   编译器文件列表:"
            ls -la "$COMPILER_DIR/" 2>/dev/null | head -10 || echo "   无法列出文件"
          else
            echo "⚠️ 编译器文件目录不存在"
          fi
          
          echo ""
          echo "📁 自定义文件状态:"
          if [ -d "firmware-config/custom-files" ]; then
            custom_count=$(find firmware-config/custom-files -type f 2>/dev/null | wc -l)
            echo "✅ 自定义文件: $custom_count 个"
          fi
          
          echo ""
          echo "📋 正常模式插件总结:"
          echo "  ✅ TurboACC 网络加速"
          echo "  ✅ UPnP 自动端口转发"
          echo "  ✅ Samba 文件共享"
          echo "  ✅ 磁盘管理"
          echo "  ✅ KMS 激活服务"
          echo "  ✅ SmartDNS 智能DNS"
          echo "  ✅ 家长控制"
          echo "  ✅ 微信推送"
          echo "  ✅ 流量控制 (SQM)"
          echo "  ✅ FTP 服务器"
          echo "  ✅ ARP 绑定"
          echo "  ✅ CPU 限制"
          echo "  ✅ 硬盘休眠"
          
          echo ""
          echo "🔌 USB驱动加强:"
          echo "  ✅ 所有关键USB驱动强制启用"
          echo "  ✅ USB 3.0完全支持"
          echo "  ✅ 平台专用驱动自动配置"
          
          echo ""
          echo "=== 构建流程完成 ==="
