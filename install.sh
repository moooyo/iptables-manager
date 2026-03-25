#!/bin/bash

# IPTables Manager 安装脚本
# Installation Script for IPTables Manager

set -e

# 获取脚本目录并加载公共函数库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 显示横幅
show_banner() {
    clear
    echo -e "${BLUE}"
    echo "============================================================"
    echo "              IPTables Manager 安装程序                     "
    echo "                  Installation Script                       "
    echo "============================================================"
    echo -e "${NC}"
    echo ""
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."

    case $PACKAGE_MANAGER in
        yum)
            yum install -y iptables
            systemctl enable iptables 2>/dev/null || true
            ;;
        apt)
            apt update
            DEBIAN_FRONTEND=noninteractive apt install -y iptables iptables-persistent
            ;;
    esac

    log_info "系统依赖安装完成"
}

# 创建安装目录
create_directories() {
    log_info "创建安装目录..."

    mkdir -p /opt/iptables-manager
    mkdir -p /etc/iptables-manager
    mkdir -p /etc/iptables-manager/backup

    log_info "目录创建完成"
}

# 复制脚本文件
copy_scripts() {
    log_info "复制脚本文件..."

    # 复制核心脚本文件到安装目录
    cp "$SCRIPT_DIR/iptables-manager.sh" /opt/iptables-manager/
    cp "$SCRIPT_DIR/common.sh" /opt/iptables-manager/

    # 复制 Gum 二进制文件
    mkdir -p /opt/iptables-manager/bin
    cp "$SCRIPT_DIR"/bin/gum-linux-* /opt/iptables-manager/bin/

    # 设置执行权限
    chmod +x /opt/iptables-manager/*.sh

    # 创建符号链接到系统PATH
    ln -sf /opt/iptables-manager/iptables-manager.sh /usr/local/bin/ipm

    log_info "脚本文件复制完成"
}

# 配置 po0 模式
setup_po0_mode() {
    log_info "配置 po0 模式..."

    # 确保 gum 可用（从已安装的位置加载）
    source /opt/iptables-manager/common.sh
    ensure_gum

    local PO0_MODE="false"
    local LAN_IP=""

    echo ""
    if gum_confirm "是否开启 po0 模式？（用于内网 SNAT 转发）"; then
        PO0_MODE="true"
        # 检测内网 IP
        local detected_ip
        detected_ip=$(ip addr show | grep -oP 'inet 10\.\S+' | head -1 | awk '{print $2}' | cut -d'/' -f1)
        if [[ -n "$detected_ip" ]]; then
            LAN_IP="$detected_ip"
            log_success "检测到内网IP: $LAN_IP"
        else
            log_warn "未检测到 10.x 内网IP，请手动输入"
            LAN_IP=$(gum_input "内网IP" "请输入内网IP地址")
            if [[ -z "$LAN_IP" ]]; then
                log_warn "未输入内网IP，po0 模式将关闭"
                PO0_MODE="false"
            fi
        fi
    fi

    # 写入配置
    cat > /etc/iptables-manager/config <<EOF
PO0_MODE=$PO0_MODE
LAN_IP=$LAN_IP
EOF

    if [[ "$PO0_MODE" == "true" ]]; then
        log_success "po0 模式已开启，内网IP: $LAN_IP"
    else
        log_info "po0 模式未开启"
    fi
}

# 显示安装完成信息
show_completion_info() {
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}                    安装完成！                              ${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo ""
    echo -e "${BLUE}使用方法:${NC}"
    echo "  ipm             - 启动交互式菜单"
    echo "  ipm add         - 交互式添加端口转发规则"
    echo "  ipm remove      - 交互式删除端口转发规则"
    echo "  ipm list        - 显示当前转发规则"
    echo ""
    echo -e "${BLUE}命令行模式:${NC}"
    echo "  ipm add <端口> <目标IP:端口>      - 添加转发规则"
    echo "  ipm remove <端口>                 - 删除转发规则"
    echo "  ipm modify <端口> <新目标IP:端口> - 修改转发规则"
    echo ""
    echo -e "${BLUE}安装位置:${NC} /opt/iptables-manager/"
    echo -e "${BLUE}配置目录:${NC} /etc/iptables-manager/"
    echo -e "${BLUE}卸载命令:${NC} bash /opt/iptables-manager/uninstall.sh"
    echo ""
}

# 主函数
main() {
    show_banner

    # 入口检查：root 权限、系统类型
    check_root
    detect_system

    install_dependencies
    create_directories
    copy_scripts
    setup_po0_mode
    show_completion_info
}

# 运行主函数
main "$@"
