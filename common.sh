#!/bin/bash

# 公共函数库
# Common Functions Library
# IPTables Manager 共享函数定义

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========== 日志函数 ==========
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

# ========== 权限检查 ==========
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# ========== 环境检测函数 ==========

# 检测系统类型
detect_system() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测系统类型: /etc/os-release 不存在"
        log_info "支持的系统: Ubuntu, Debian, CentOS/RHEL"
        exit 1
    fi

    source /etc/os-release
    case "$ID" in
        "ubuntu")
            SYSTEM="ubuntu"
            PACKAGE_MANAGER="apt"
            ;;
        "debian")
            SYSTEM="debian"
            PACKAGE_MANAGER="apt"
            ;;
        "centos"|"rhel"|"fedora"|"rocky"|"almalinux")
            SYSTEM="centos"
            PACKAGE_MANAGER="yum"
            ;;
        *)
            log_error "不支持的系统类型: $ID"
            log_info "支持的系统: Ubuntu, Debian, CentOS/RHEL"
            exit 1
            ;;
    esac

    log_info "检测到系统类型: $SYSTEM"
}

# ========== Gum TUI 支持函数 ==========

# 获取脚本所在目录
get_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [[ -L "$source" ]]; do
        local dir
        dir=$(cd -P "$(dirname "$source")" && pwd)
        source=$(readlink "$source")
        [[ $source != /* ]] && source="$dir/$source"
    done
    cd -P "$(dirname "$source")" && pwd
}

# 检查 Gum 是否已安装
has_gum() {
    command -v gum >/dev/null 2>&1
}

# 安装 Gum（从本地 bin/ 目录复制）
install_gum() {
    log_info "安装 Gum TUI 工具..."

    local arch=$(uname -m)
    local bin_name=""

    case $arch in
        x86_64) bin_name="gum-linux-amd64" ;;
        aarch64) bin_name="gum-linux-arm64" ;;
        *)
            log_error "不支持的架构: $arch (仅支持 x86_64 和 aarch64)"
            return 1
            ;;
    esac

    local script_dir
    script_dir="$(get_script_dir)"
    local gum_bin="$script_dir/bin/$bin_name"

    if [[ ! -f "$gum_bin" ]]; then
        log_error "Gum 二进制文件不存在: $gum_bin"
        return 1
    fi

    if ! cp "$gum_bin" /usr/local/bin/gum; then
        log_error "Gum 安装失败：无法复制文件"
        return 1
    fi

    chmod +x /usr/local/bin/gum
    log_success "Gum 安装完成"
    return 0
}

# 确保 Gum 可用（如果没有则安装）
ensure_gum() {
    if ! has_gum; then
        log_warn "Gum 未安装，正在安装..."
        if ! install_gum; then
            log_error "Gum 安装失败，请手动安装后重试"
            exit 1
        fi
    fi
}

# Gum 选择菜单（带图标）
gum_choose() {
    local header="$1"
    shift
    gum choose \
        --cursor "→ " \
        --selected.foreground 212 \
        --header "$header" \
        --height 15 \
        "$@"
}

# Gum 输入框
gum_input() {
    local prompt="$1"
    local placeholder="$2"
    gum input \
        --placeholder "$placeholder" \
        --prompt "$prompt > " \
        --width 50
}

# Gum 确认对话框
gum_confirm() {
    local message="$1"
    local default="${2:-true}"

    if [[ "$default" == "false" ]]; then
        gum confirm --default=false "$message"
    else
        gum confirm "$message"
    fi
}

# Gum 成功提示框
gum_success() {
    local title="$1"
    shift
    gum style \
        --border double \
        --border-foreground 212 \
        --padding "1 2" \
        --margin "1 0" \
        "✓ $title" \
        "" \
        "$@"
}

# Gum 错误提示框
gum_error() {
    local message="$1"
    gum style \
        --foreground 196 \
        --border rounded \
        --border-foreground 196 \
        --padding "1 2" \
        "✗ $message"
}

# Gum 信息提示框
gum_info() {
    local title="$1"
    shift
    gum style \
        --foreground 33 \
        --border rounded \
        --border-foreground 33 \
        --padding "1 2" \
        "$title" \
        "" \
        "$@"
}

# Gum 暂停（等待用户按键）
gum_pause() {
    echo ""
    gum style --foreground 240 "按任意键继续..."
    read -n 1 -s -r
    echo ""
}
