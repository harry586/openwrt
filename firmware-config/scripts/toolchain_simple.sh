#!/bin/bash
set -e

# 简单工具链管理器
BUILD_DIR="/mnt/openwrt-build"
TOOLCHAIN_BASE="./firmware-config/build-tools"

log() {
    echo "【$(date '+%Y-%m-%d %H:%M:%S')】$1"
}

# 初始化目录
init() {
    log "=== 初始化工具链目录 ==="
    mkdir -p $TOOLCHAIN_BASE/{common,platforms,versions,cache,logs,archives}
    log "✅ 工具链目录初始化完成"
}

# 安装编译环境
install_build_env() {
    log "=== 安装编译环境 ==="
    
    # 更新包列表
    sudo apt-get update
    
    # 安装编译工具
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
        gettext git libncurses5-dev libssl-dev python3-distutils rsync unzip \
        zlib1g-dev file wget libelf-dev ecj fastjar java-propose-classpath \
        libpython3-dev python3-dev python3-pip python3-setuptools \
        python3-yaml xsltproc zip subversion ninja-build automake autoconf \
        libtool pkg-config help2man texinfo aria2 liblz4-dev zstd \
        libcurl4-openssl-dev groff texlive texinfo cmake jq ccache
    
    log "✅ 编译环境安装完成"
}

# 检查工具
check_tools() {
    log "=== 检查编译工具 ==="
    
    local tools=(
        "gcc" "g++" "make" "cmake" "git" "wget" "curl"
        "python3" "flex" "bison" "autoconf" "automake"
        "libtool" "pkg-config" "ccache" "jq"
    )
    
    for tool in "${tools[@]}"; do
        if command -v $tool >/dev/null 2>&1; then
            log "✅ $tool 已安装"
        else
            log "❌ $tool 未安装"
        fi
    done
}

# 主函数
main() {
    case $1 in
        "init")
            init
            ;;
        "install_env")
            install_build_env
            ;;
        "check")
            check_tools
            ;;
        *)
            log "❌ 未知命令: $1"
            echo "可用命令:"
            echo "  init - 初始化目录"
            echo "  install_env - 安装编译环境"
            echo "  check - 检查工具"
            exit 1
            ;;
    esac
}

main "$@"
