#!/bin/bash

# IPTables Manager 卸载脚本
# Uninstall Script for IPTables Manager

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

log_success() {
    echo -e "${BLUE}[SUCCESS]${NC} $1"
}

# 显示横幅
show_banner() {
    clear
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                IPTables Manager 卸载程序                     ║"
    echo "║                   Uninstall Script                          ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 确认卸载
confirm_uninstall() {
    echo -e "${YELLOW}警告: 这将完全卸载 IPTables Manager 及其所有配置:${NC}"
    echo "  - 脚本文件和符号链接"
    echo "  - 端口转发规则记录文件"
    echo "  - 备份文件"
    echo ""
    echo -e "${YELLOW}注意: 已生效的 iptables 规则不会被自动清除${NC}"
    echo ""

    read -p "确认卸载? (y/N): " confirm

    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        log_info "卸载已取消"
        exit 0
    fi

    echo ""
    log_warn "开始卸载，请稍候..."
    sleep 2
}

# 删除符号链接
remove_symlinks() {
    log_info "删除符号链接..."

    if [[ -L /usr/local/bin/ipm ]]; then
        rm -f /usr/local/bin/ipm
        log_info "删除符号链接: /usr/local/bin/ipm"
    fi

    log_success "符号链接删除完成"
}

# 删除安装目录
remove_install_directory() {
    log_info "删除安装目录..."

    if [[ -d /opt/iptables-manager ]]; then
        rm -rf /opt/iptables-manager
        log_info "删除目录: /opt/iptables-manager"
    fi

    log_success "安装目录删除完成"
}

# 删除配置目录
remove_config_directories() {
    log_info "删除配置目录..."

    if [[ -d /etc/iptables-manager ]]; then
        rm -rf /etc/iptables-manager
        log_info "删除目录: /etc/iptables-manager"
    fi

    log_success "配置目录删除完成"
}

# 删除 Gum 二进制
remove_gum() {
    if [[ -f /usr/local/bin/gum ]]; then
        log_info "删除 Gum TUI 工具: /usr/local/bin/gum"
        rm -f /usr/local/bin/gum
    fi

    log_success "Gum 删除完成"
}

# 显示卸载完成信息
show_completion_info() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    卸载完成！                                ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${BLUE}已完成的操作:${NC}"
    echo "  - 删除符号链接 (ipm)"
    echo "  - 删除安装目录 (/opt/iptables-manager/)"
    echo "  - 删除配置目录 (/etc/iptables-manager/)"
    echo "  - 删除 Gum TUI 工具"
    echo ""

    echo -e "${YELLOW}注意事项:${NC}"
    echo "1. 已生效的 iptables 规则不会被自动清除"
    echo "2. 如需清除 iptables 规则，请手动执行: iptables -F && iptables -t nat -F"
    echo ""

    echo -e "${BLUE}如需重新安装:${NC}"
    echo "  运行安装脚本: sudo bash install.sh"
    echo ""
}

# 主函数
main() {
    show_banner
    check_root
    confirm_uninstall

    remove_symlinks
    remove_install_directory
    remove_config_directories
    remove_gum

    show_completion_info
}

# 运行主函数
main "$@"
