#!/bin/bash

# IPTables Manager 快速设置脚本
# Quick Setup Script for IPTables Manager

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示横幅
show_banner() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                IPTables Manager 快速设置                     ║"
    echo "║                   Quick Setup Script                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# 设置执行权限
set_permissions() {
    log_info "设置脚本执行权限..."

    chmod +x *.sh

    log_info "权限设置完成"
}

# 验证脚本文件
verify_scripts() {
    log_info "验证脚本文件..."

    local required_scripts=(
        "iptables-manager.sh"
        "common.sh"
        "install.sh"
    )

    local missing_scripts=()

    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$script" ]]; then
            missing_scripts+=("$script")
        fi
    done

    if [[ ${#missing_scripts[@]} -gt 0 ]]; then
        log_error "缺少以下脚本文件:"
        for script in "${missing_scripts[@]}"; do
            echo "  - $script"
        done
        exit 1
    fi

    log_info "所有脚本文件验证通过"
}

# 检查系统兼容性
check_system_compatibility() {
    log_info "检查系统兼容性..."

    # 检查操作系统
    if [[ ! -f /etc/redhat-release ]] && [[ ! -f /etc/debian_version ]]; then
        log_error "不支持的操作系统"
        log_info "支持的系统: Ubuntu, Debian, CentOS, RHEL"
        exit 1
    fi

    # 检查架构
    local arch=$(uname -m)
    case $arch in
        x86_64|aarch64|armv7l)
            log_info "系统架构: $arch (支持)"
            ;;
        *)
            log_error "不支持的系统架构: $arch"
            log_info "支持的架构: x86_64, aarch64, armv7l"
            exit 1
            ;;
    esac

    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        log_error "需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi

    log_info "系统兼容性检查通过"
}

# 显示下一步操作
show_next_steps() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      设置完成！                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}下一步操作:${NC}"
    echo ""
    echo -e "${YELLOW}1. 安装到系统 (推荐):${NC}"
    echo "   sudo bash install.sh"
    echo ""
    echo -e "${YELLOW}2. 或者直接运行:${NC}"
    echo "   sudo bash iptables-manager.sh"
    echo ""
    echo -e "${YELLOW}3. 快速命令 (安装后可用):${NC}"
    echo "   ipm             # 交互式菜单"
    echo "   ipm add         # 添加转发规则"
    echo "   ipm remove      # 删除转发规则"
    echo "   ipm list        # 显示当前规则"
    echo ""
    echo -e "${BLUE}主程序:${NC} iptables-manager.sh"
    echo -e "${BLUE}安装脚本:${NC} install.sh"
    echo ""
}

# 主函数
main() {
    show_banner
    check_system_compatibility
    verify_scripts
    set_permissions
    show_next_steps
}

# 运行主函数
main "$@"
