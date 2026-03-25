#!/bin/bash

# IPTables Manager - 端口转发管理工具
# IPTables Port Forwarding Manager

set -e

# 获取脚本实际目录（处理符号链接）
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    # 如果是符号链接，获取实际文件路径
    REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT")" && pwd)"
else
    # 如果不是符号链接，使用常规方法
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# 加载公共函数库
source "$SCRIPT_DIR/common.sh"

# 配置文件路径
IPTABLES_CONFIG_DIR="/etc/iptables-manager"
IPTABLES_RULES_FILE="$IPTABLES_CONFIG_DIR/port-forward-rules.txt"
BACKUP_DIR="/etc/iptables-manager/backup"
CONFIG_FILE="$IPTABLES_CONFIG_DIR/config"

# po0 模式全局变量
PO0_MODE="false"
LAN_IP=""

# 加载配置
load_config() {
    PO0_MODE="false"
    LAN_IP=""
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" <<EOF
PO0_MODE=$PO0_MODE
LAN_IP=$LAN_IP
EOF
}

# 获取内网IP（匹配 10. 开头）
detect_lan_ip() {
    local ip
    ip=$(ip addr show | grep -oP 'inet 10\.\S+' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    echo "$ip"
}

# 设置 po0 模式的 LAN IP（检测或手动输入）
setup_lan_ip() {
    local detected_ip
    detected_ip=$(detect_lan_ip)
    if [[ -n "$detected_ip" ]]; then
        LAN_IP="$detected_ip"
        log_success "检测到内网IP: $LAN_IP"
    else
        log_warn "未检测到 10.x 内网IP，请手动输入"
        LAN_IP=$(gum_input "内网IP" "请输入内网IP地址")
        if [[ -z "$LAN_IP" ]] || ! validate_ip "$LAN_IP"; then
            log_error "无效的IP地址"
            LAN_IP=""
            return 1
        fi
    fi
}

# 确保 IPv4 转发已开启
ensure_ip_forward() {
    local current=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    if [[ "$current" != "1" ]]; then
        log_warn "IPv4 转发未开启，正在启用..."
        sysctl -w net.ipv4.ip_forward=1 >/dev/null
        # 持久化配置
        if grep -q "^net.ipv4.ip_forward" /etc/sysctl.conf; then
            sed -i 's/^net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
        else
            echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        fi
        log_success "IPv4 转发已开启并持久化"
    fi
}

# 初始化配置目录
init_config_dir() {
    mkdir -p "$IPTABLES_CONFIG_DIR"
    mkdir -p "$BACKUP_DIR"

    if [[ ! -f "$IPTABLES_RULES_FILE" ]]; then
        touch "$IPTABLES_RULES_FILE"
        log_info "创建端口转发规则文件: $IPTABLES_RULES_FILE"
    fi
}

# 获取 iptables 持久化路径
get_iptables_paths() {
    case $SYSTEM in
        "ubuntu"|"debian")
            IPTABLES_SAVE_CMD="iptables-save > /etc/iptables/rules.v4"
            ;;
        "centos")
            IPTABLES_SAVE_CMD="iptables-save > /etc/sysconfig/iptables"
            ;;
    esac
}

# 备份当前iptables规则
backup_iptables() {
    local backup_file="$BACKUP_DIR/iptables-backup-$(date +%Y%m%d-%H%M%S).rules"

    iptables-save > "$backup_file"
    log_info "iptables规则已备份到: $backup_file"

    # 保留最近5个备份
    ls -t "$BACKUP_DIR"/iptables-backup-*.rules 2>/dev/null | tail -n +6 | xargs -r rm
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# 验证端口号
validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [[ $port -ge 1 ]] && [[ $port -le 65535 ]]; then
        return 0
    else
        return 1
    fi
}

# 解析 "IP 端口" 格式
parse_ip_port() {
    local ip="${1%% *}"
    local port="${1##* }"

    if [[ -z "$ip" || -z "$port" || "$ip" == "$port" ]]; then
        log_error "格式错误: 请使用 IP 端口 格式（例如: 1.2.3.4 8080）"
        return 1
    fi

    # 验证IP
    if ! validate_ip "$ip"; then
        log_error "无效的IP地址: $ip"
        return 1
    fi

    # 验证端口
    if ! validate_port "$port"; then
        log_error "无效的端口号: $port（有效范围: 1-65535）"
        return 1
    fi

    # 通过全局变量返回结果
    PARSED_IP="$ip"
    PARSED_PORT="$port"
    return 0
}

# 检查端口是否已被转发
check_port_exists() {
    local local_port=$1

    if grep -q "^$local_port:" "$IPTABLES_RULES_FILE"; then
        return 0
    else
        return 1
    fi
}

# 添加端口转发规则
add_port_forward() {
    local local_port=$1
    local target_ip=$2
    local target_port=$3

    log_info "添加端口转发规则: $local_port -> $target_ip:$target_port"

    # 检查端口是否已存在
    if check_port_exists "$local_port"; then
        log_error "端口 $local_port 已存在转发规则"
        return 1
    fi

    # 备份当前规则
    backup_iptables

    # 添加DNAT规则（目标地址转换）
    iptables -t nat -A PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port"
    iptables -t nat -A PREROUTING -p udp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port"

    # 添加SNAT规则（源地址转换，确保回包正确返回）
    if [[ "$PO0_MODE" == "true" && -n "$LAN_IP" ]]; then
        iptables -t nat -A POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP"
        iptables -t nat -A POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP"
    else
        iptables -t nat -A POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j MASQUERADE
        iptables -t nat -A POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j MASQUERADE
    fi

    # 添加FORWARD规则（允许转发）
    iptables -A FORWARD -p tcp -d "$target_ip" --dport "$target_port" -j ACCEPT
    iptables -A FORWARD -p udp -d "$target_ip" --dport "$target_port" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$target_ip" --sport "$target_port" -j ACCEPT
    iptables -A FORWARD -p udp -s "$target_ip" --sport "$target_port" -j ACCEPT

    # 记录规则到文件
    echo "$local_port:$target_ip:$target_port" >> "$IPTABLES_RULES_FILE"

    log_info "端口转发规则添加成功"
}

# 删除端口转发规则
remove_port_forward() {
    local local_port=$1

    log_info "删除端口转发规则: $local_port"

    # 检查端口是否存在
    if ! check_port_exists "$local_port"; then
        log_error "端口 $local_port 不存在转发规则"
        return 1
    fi

    # 获取目标信息
    local rule_info=$(grep "^$local_port:" "$IPTABLES_RULES_FILE")
    local target_ip=$(echo "$rule_info" | cut -d':' -f2)
    local target_port=$(echo "$rule_info" | cut -d':' -f3)

    # 备份当前规则
    backup_iptables

    # 删除iptables规则
    iptables -t nat -D PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port" 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port" 2>/dev/null || true
    # 同时尝试删除 MASQUERADE 和 SNAT 规则，防止模式切换后残留
    iptables -t nat -D POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j MASQUERADE 2>/dev/null || true
    if [[ -n "$LAN_IP" ]]; then
        iptables -t nat -D POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP" 2>/dev/null || true
        iptables -t nat -D POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP" 2>/dev/null || true
    fi
    iptables -D FORWARD -p tcp -d "$target_ip" --dport "$target_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p udp -d "$target_ip" --dport "$target_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p tcp -s "$target_ip" --sport "$target_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p udp -s "$target_ip" --sport "$target_port" -j ACCEPT 2>/dev/null || true

    # 从文件中删除规则记录
    sed -i "/^$local_port:/d" "$IPTABLES_RULES_FILE"

    log_info "端口转发规则删除成功"
}

# 修改端口转发规则
modify_port_forward() {
    local local_port=$1
    local new_target_ip=$2
    local new_target_port=$3

    log_info "修改端口转发规则: $local_port"

    # 检查端口是否存在
    if ! check_port_exists "$local_port"; then
        log_error "端口 $local_port 不存在转发规则"
        return 1
    fi

    # 获取旧的目标信息
    local rule_info=$(grep "^$local_port:" "$IPTABLES_RULES_FILE")
    local old_target_ip=$(echo "$rule_info" | cut -d':' -f2)
    local old_target_port=$(echo "$rule_info" | cut -d':' -f3)

    log_info "旧规则: $local_port -> $old_target_ip:$old_target_port"
    log_info "新规则: $local_port -> $new_target_ip:$new_target_port"

    # 备份当前规则
    backup_iptables

    # 删除旧的iptables规则
    iptables -t nat -D PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "$old_target_ip:$old_target_port" 2>/dev/null || true
    iptables -t nat -D PREROUTING -p udp --dport "$local_port" -j DNAT --to-destination "$old_target_ip:$old_target_port" 2>/dev/null || true
    # 同时尝试删除 MASQUERADE 和 SNAT 规则，防止模式切换后残留
    iptables -t nat -D POSTROUTING -p tcp -d "$old_target_ip" --dport "$old_target_port" -j MASQUERADE 2>/dev/null || true
    iptables -t nat -D POSTROUTING -p udp -d "$old_target_ip" --dport "$old_target_port" -j MASQUERADE 2>/dev/null || true
    if [[ -n "$LAN_IP" ]]; then
        iptables -t nat -D POSTROUTING -p tcp -d "$old_target_ip" --dport "$old_target_port" -j SNAT --to-source "$LAN_IP" 2>/dev/null || true
        iptables -t nat -D POSTROUTING -p udp -d "$old_target_ip" --dport "$old_target_port" -j SNAT --to-source "$LAN_IP" 2>/dev/null || true
    fi
    iptables -D FORWARD -p tcp -d "$old_target_ip" --dport "$old_target_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p udp -d "$old_target_ip" --dport "$old_target_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p tcp -s "$old_target_ip" --sport "$old_target_port" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p udp -s "$old_target_ip" --sport "$old_target_port" -j ACCEPT 2>/dev/null || true

    # 添加新的iptables规则
    iptables -t nat -A PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "$new_target_ip:$new_target_port"
    iptables -t nat -A PREROUTING -p udp --dport "$local_port" -j DNAT --to-destination "$new_target_ip:$new_target_port"
    if [[ "$PO0_MODE" == "true" && -n "$LAN_IP" ]]; then
        iptables -t nat -A POSTROUTING -p tcp -d "$new_target_ip" --dport "$new_target_port" -j SNAT --to-source "$LAN_IP"
        iptables -t nat -A POSTROUTING -p udp -d "$new_target_ip" --dport "$new_target_port" -j SNAT --to-source "$LAN_IP"
    else
        iptables -t nat -A POSTROUTING -p tcp -d "$new_target_ip" --dport "$new_target_port" -j MASQUERADE
        iptables -t nat -A POSTROUTING -p udp -d "$new_target_ip" --dport "$new_target_port" -j MASQUERADE
    fi
    iptables -A FORWARD -p tcp -d "$new_target_ip" --dport "$new_target_port" -j ACCEPT
    iptables -A FORWARD -p udp -d "$new_target_ip" --dport "$new_target_port" -j ACCEPT
    iptables -A FORWARD -p tcp -s "$new_target_ip" --sport "$new_target_port" -j ACCEPT
    iptables -A FORWARD -p udp -s "$new_target_ip" --sport "$new_target_port" -j ACCEPT

    # 更新文件中的规则记录
    sed -i "/^$local_port:/d" "$IPTABLES_RULES_FILE"
    echo "$local_port:$new_target_ip:$new_target_port" >> "$IPTABLES_RULES_FILE"

    log_info "端口转发规则修改成功"
}

# 持久化iptables规则
persist_iptables() {
    log_info "持久化iptables规则..."

    case $SYSTEM in
        "centos")
            mkdir -p /etc/sysconfig
            eval "$IPTABLES_SAVE_CMD"
            # 尝试启用 iptables 服务（如果存在）
            systemctl enable iptables 2>/dev/null || true
            ;;
        "ubuntu"|"debian")
            # 安装 iptables-persistent 包（如果未安装）
            if ! dpkg -l | grep -q iptables-persistent; then
                log_info "安装 iptables-persistent..."
                DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
            fi
            mkdir -p /etc/iptables
            eval "$IPTABLES_SAVE_CMD"
            ;;
    esac

    log_info "iptables规则持久化完成"
}

# 显示当前转发规则
show_forward_rules() {
    log_info "当前端口转发规则:"

    if [[ -s "$IPTABLES_RULES_FILE" ]]; then
        echo ""
        echo -e "${BLUE}本地端口 -> 目标地址:目标端口${NC}"
        echo "========================================"
        while IFS=':' read -r local_port target_ip target_port; do
            echo -e "${GREEN}$local_port${NC} -> ${YELLOW}$target_ip:$target_port${NC}"
        done < "$IPTABLES_RULES_FILE"
        echo ""
    else
        log_warn "当前没有配置端口转发规则"
    fi
}

# 交互式添加转发规则（Gum 版本 - 解决删除键问题）
interactive_add_forward() {
    echo ""
    gum style --foreground 33 "=== 添加端口转发规则 ==="
    echo ""

    # 输入本地端口（使用 Gum input，完美支持删除键）
    local local_port
    while true; do
        local_port=$(gum_input "本地端口" "请输入端口号 (1-65535)")

        # 取消输入
        if [[ -z "$local_port" ]]; then
            gum style --foreground 240 "操作已取消"
            return
        fi

        if validate_port "$local_port"; then
            if ! check_port_exists "$local_port"; then
                break
            else
                gum_error "端口 $local_port 已存在转发规则"
                echo ""
            fi
        else
            gum_error "无效的端口号，请输入1-65535之间的数字"
            echo ""
        fi
    done

    # 输入目标地址（使用 Gum input，完美支持删除键）
    local target_input
    while true; do
        echo ""
        target_input=$(gum_input "目标地址" "IP 端口，例如 1.2.3.4 8080")

        # 取消输入
        if [[ -z "$target_input" ]]; then
            gum style --foreground 240 "操作已取消"
            return
        fi

        if parse_ip_port "$target_input"; then
            break
        fi
        echo ""
    done

    local target_ip="$PARSED_IP"
    local target_port="$PARSED_PORT"

    # 确认添加
    echo ""
    gum_info "即将添加转发规则" \
        "本地端口: $local_port" \
        "目标地址: $target_ip:$target_port"
    echo ""

    if gum_confirm "确认添加?"; then
        add_port_forward "$local_port" "$target_ip" "$target_port"
        persist_iptables
        echo ""
        gum_success "端口转发规则添加并持久化完成"
    else
        gum style --foreground 240 "操作已取消"
    fi
}

# 交互式删除转发规则（Gum 版本）
interactive_remove_forward() {
    echo ""
    gum style --foreground 33 "=== 删除端口转发规则 ==="
    echo ""

    # 显示当前规则
    if [[ ! -s "$IPTABLES_RULES_FILE" ]]; then
        gum style --foreground 214 "当前没有配置端口转发规则"
        return
    fi

    show_forward_rules
    echo ""

    # 使用 Gum choose 选择要删除的规则
    local options=()
    while IFS=':' read -r local_port target_ip target_port; do
        options+=("$local_port -> $target_ip:$target_port")
    done < "$IPTABLES_RULES_FILE"
    options+=("取消")

    local choice=$(gum_choose "选择要删除的规则" "${options[@]}")

    if [[ "$choice" == "取消" ]]; then
        gum style --foreground 240 "操作已取消"
        return
    fi

    # 提取本地端口
    local local_port=$(echo "$choice" | cut -d' ' -f1)
    local rule_info=$(grep "^$local_port:" "$IPTABLES_RULES_FILE")
    local target_ip=$(echo "$rule_info" | cut -d':' -f2)
    local target_port=$(echo "$rule_info" | cut -d':' -f3)

    # 确认删除
    echo ""
    gum_info "即将删除转发规则" \
        "本地端口: $local_port" \
        "目标地址: $target_ip:$target_port"
    echo ""

    if gum_confirm "确认删除?"; then
        remove_port_forward "$local_port"
        persist_iptables
        echo ""
        gum_success "端口转发规则删除并持久化完成"
    else
        gum style --foreground 240 "操作已取消"
    fi
}

# 交互式修改转发规则（Gum 版本 - 解决删除键问题）
interactive_modify_forward() {
    echo ""
    gum style --foreground 33 "=== 修改端口转发规则 ==="
    echo ""

    # 显示当前规则
    if [[ ! -s "$IPTABLES_RULES_FILE" ]]; then
        gum style --foreground 214 "当前没有配置端口转发规则"
        return
    fi

    show_forward_rules
    echo ""

    # 使用 Gum choose 选择要修改的规则
    local options=()
    while IFS=':' read -r local_port target_ip target_port; do
        options+=("$local_port -> $target_ip:$target_port")
    done < "$IPTABLES_RULES_FILE"
    options+=("取消")

    local choice=$(gum_choose "选择要修改的规则" "${options[@]}")

    if [[ "$choice" == "取消" ]]; then
        gum style --foreground 240 "操作已取消"
        return
    fi

    # 提取本地端口
    local local_port=$(echo "$choice" | cut -d' ' -f1)
    local rule_info=$(grep "^$local_port:" "$IPTABLES_RULES_FILE")
    local old_target_ip=$(echo "$rule_info" | cut -d':' -f2)
    local old_target_port=$(echo "$rule_info" | cut -d':' -f3)

    echo ""
    gum_info "当前规则" \
        "本地端口: $local_port" \
        "目标地址: $old_target_ip:$old_target_port"
    echo ""

    # 输入新的目标地址（使用 Gum input，完美支持删除键）
    local target_input
    while true; do
        target_input=$(gum_input "新目标地址" "IP 端口，例如 1.2.3.4 8080")

        # 取消输入
        if [[ -z "$target_input" ]]; then
            gum style --foreground 240 "操作已取消"
            return
        fi

        if parse_ip_port "$target_input"; then
            break
        fi
        echo ""
    done

    local new_target_ip="$PARSED_IP"
    local new_target_port="$PARSED_PORT"

    # 确认修改
    echo ""
    gum_info "即将修改转发规则" \
        "本地端口: $local_port" \
        "旧目标: $old_target_ip:$old_target_port" \
        "新目标: $new_target_ip:$new_target_port"
    echo ""

    if gum_confirm "确认修改?"; then
        modify_port_forward "$local_port" "$new_target_ip" "$new_target_port"
        persist_iptables
        echo ""
        gum_success "端口转发规则修改并持久化完成"
    else
        gum style --foreground 240 "操作已取消"
    fi
}

# 清空所有转发规则（Gum 版本）
clear_all_forwards() {
    echo ""
    gum style --foreground 196 "⚠️  清空所有端口转发规则"
    echo ""

    if [[ ! -s "$IPTABLES_RULES_FILE" ]]; then
        gum style --foreground 214 "当前没有配置端口转发规则"
        return
    fi

    show_forward_rules
    echo ""

    if gum_confirm "确认清空所有端口转发规则?" false; then
        backup_iptables

        # 删除所有转发规则
        while IFS=':' read -r local_port target_ip target_port; do
            log_info "删除规则: $local_port -> $target_ip:$target_port"

            # 删除iptables规则
            iptables -t nat -D PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port" 2>/dev/null || true
            iptables -t nat -D PREROUTING -p udp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port" 2>/dev/null || true
            # 同时尝试删除 MASQUERADE 和 SNAT 规则，防止模式切换后残留
            iptables -t nat -D POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j MASQUERADE 2>/dev/null || true
            iptables -t nat -D POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j MASQUERADE 2>/dev/null || true
            if [[ -n "$LAN_IP" ]]; then
                iptables -t nat -D POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP" 2>/dev/null || true
                iptables -t nat -D POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP" 2>/dev/null || true
            fi
            iptables -D FORWARD -p tcp -d "$target_ip" --dport "$target_port" -j ACCEPT 2>/dev/null || true
            iptables -D FORWARD -p udp -d "$target_ip" --dport "$target_port" -j ACCEPT 2>/dev/null || true
            iptables -D FORWARD -p tcp -s "$target_ip" --sport "$target_port" -j ACCEPT 2>/dev/null || true
            iptables -D FORWARD -p udp -s "$target_ip" --sport "$target_port" -j ACCEPT 2>/dev/null || true
        done < "$IPTABLES_RULES_FILE"

        # 清空规则文件
        > "$IPTABLES_RULES_FILE"

        persist_iptables
        echo ""
        gum_success "所有端口转发规则已清空"
    else
        gum style --foreground 240 "操作已取消"
    fi
}

# 重建所有转发规则（切换模式或修改内网IP时使用）
# 参数: $1=旧PO0_MODE $2=旧LAN_IP
rebuild_all_forwards() {
    local old_mode="$1"
    local old_lan="$2"

    if [[ ! -s "$IPTABLES_RULES_FILE" ]]; then
        log_info "没有转发规则需要重建"
        return
    fi

    backup_iptables

    # 删除所有 iptables 规则（两种 SNAT 方式都尝试删除）
    # 删除时需要用旧 LAN_IP 匹配 SNAT 规则
    local del_lan="$old_lan"
    if [[ -z "$del_lan" ]]; then
        del_lan="$LAN_IP"
    fi

    while IFS=':' read -r local_port target_ip target_port; do
        iptables -t nat -D PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port" 2>/dev/null || true
        iptables -t nat -D PREROUTING -p udp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port" 2>/dev/null || true
        # 同时尝试删除 MASQUERADE 和 SNAT 规则，防止模式切换后残留
        iptables -t nat -D POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j MASQUERADE 2>/dev/null || true
        iptables -t nat -D POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j MASQUERADE 2>/dev/null || true
        if [[ -n "$del_lan" ]]; then
            iptables -t nat -D POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$del_lan" 2>/dev/null || true
            iptables -t nat -D POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$del_lan" 2>/dev/null || true
        fi
        iptables -D FORWARD -p tcp -d "$target_ip" --dport "$target_port" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p udp -d "$target_ip" --dport "$target_port" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p tcp -s "$target_ip" --sport "$target_port" -j ACCEPT 2>/dev/null || true
        iptables -D FORWARD -p udp -s "$target_ip" --sport "$target_port" -j ACCEPT 2>/dev/null || true
    done < "$IPTABLES_RULES_FILE"

    # 用当前模式重新添加所有规则
    while IFS=':' read -r local_port target_ip target_port; do
        iptables -t nat -A PREROUTING -p tcp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port"
        iptables -t nat -A PREROUTING -p udp --dport "$local_port" -j DNAT --to-destination "$target_ip:$target_port"
        if [[ "$PO0_MODE" == "true" && -n "$LAN_IP" ]]; then
            iptables -t nat -A POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP"
            iptables -t nat -A POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j SNAT --to-source "$LAN_IP"
        else
            iptables -t nat -A POSTROUTING -p tcp -d "$target_ip" --dport "$target_port" -j MASQUERADE
            iptables -t nat -A POSTROUTING -p udp -d "$target_ip" --dport "$target_port" -j MASQUERADE
        fi
        iptables -A FORWARD -p tcp -d "$target_ip" --dport "$target_port" -j ACCEPT
        iptables -A FORWARD -p udp -d "$target_ip" --dport "$target_port" -j ACCEPT
        iptables -A FORWARD -p tcp -s "$target_ip" --sport "$target_port" -j ACCEPT
        iptables -A FORWARD -p udp -s "$target_ip" --sport "$target_port" -j ACCEPT
    done < "$IPTABLES_RULES_FILE"

    persist_iptables
    log_success "所有转发规则已用新模式重建"
}

# 切换 po0 模式
toggle_po0_mode() {
    echo ""
    local old_mode="$PO0_MODE"
    local old_lan="$LAN_IP"

    if [[ "$PO0_MODE" == "true" ]]; then
        gum style --foreground 33 "=== 关闭 po0 模式 ==="
        echo ""
        if gum_confirm "确认关闭 po0 模式？将切换回 MASQUERADE"; then
            PO0_MODE="false"
            rebuild_all_forwards "$old_mode" "$old_lan"
            save_config
            echo ""
            gum_success "po0 模式已关闭"
        else
            gum style --foreground 240 "操作已取消"
        fi
    else
        gum style --foreground 33 "=== 开启 po0 模式 ==="
        echo ""
        if setup_lan_ip; then
            PO0_MODE="true"
            rebuild_all_forwards "$old_mode" "$old_lan"
            save_config
            echo ""
            gum_success "po0 模式已开启，内网IP: $LAN_IP"
        else
            gum_error "开启 po0 模式失败：无法获取内网IP"
        fi
    fi
}

# 修改内网IP
change_lan_ip() {
    echo ""
    gum style --foreground 33 "=== 修改内网IP ==="
    echo ""

    if [[ -n "$LAN_IP" ]]; then
        gum_info "当前内网IP" "$LAN_IP"
        echo ""
    fi

    local old_lan="$LAN_IP"
    local new_ip
    new_ip=$(gum_input "新内网IP" "请输入新的内网IP地址")

    if [[ -z "$new_ip" ]]; then
        gum style --foreground 240 "操作已取消"
        return
    fi

    if ! validate_ip "$new_ip"; then
        gum_error "无效的IP地址: $new_ip"
        return
    fi

    if gum_confirm "确认将内网IP从 $old_lan 修改为 $new_ip ?"; then
        LAN_IP="$new_ip"
        rebuild_all_forwards "$PO0_MODE" "$old_lan"
        save_config
        echo ""
        gum_success "内网IP已修改为: $LAN_IP"
    else
        gum style --foreground 240 "操作已取消"
    fi
}

# 主菜单（Gum 版本）
show_menu() {
    echo ""
    gum style --foreground 33 "=== IPTables端口转发管理 ==="

    # 显示 po0 模式状态
    if [[ "$PO0_MODE" == "true" ]]; then
        echo -e "    ${GREEN}po0 模式: 开启${NC}  |  ${CYAN}内网IP: $LAN_IP${NC}"
    else
        echo -e "    ${YELLOW}po0 模式: 关闭${NC}"
    fi

    echo ""

    # 构建菜单项
    local po0_label
    if [[ "$PO0_MODE" == "true" ]]; then
        po0_label="🔄 切换 po0 模式 (当前: 开启)"
    else
        po0_label="🔄 切换 po0 模式 (当前: 关闭)"
    fi

    if [[ "$PO0_MODE" == "true" ]]; then
        gum_choose "请选择操作" \
            "➕ 添加端口转发规则" \
            "❌ 删除端口转发规则" \
            "✏️  修改端口转发规则" \
            "📋 显示当前转发规则" \
            "🗑️  清空所有转发规则" \
            "$po0_label" \
            "🌐 修改内网IP (当前: $LAN_IP)" \
            "💾 显示备份文件" \
            "🔙 退出"
    else
        gum_choose "请选择操作" \
            "➕ 添加端口转发规则" \
            "❌ 删除端口转发规则" \
            "✏️  修改端口转发规则" \
            "📋 显示当前转发规则" \
            "🗑️  清空所有转发规则" \
            "$po0_label" \
            "💾 显示备份文件" \
            "🔙 退出"
    fi
}

# 显示备份文件
show_backups() {
    echo ""
    echo -e "${BLUE}=== 备份文件列表 ===${NC}"
    echo ""

    if ls "$BACKUP_DIR"/iptables-backup-*.rules >/dev/null 2>&1; then
        ls -lh "$BACKUP_DIR"/iptables-backup-*.rules
    else
        log_warn "没有找到备份文件"
    fi
    echo ""
}

# 主函数
main() {
    # 检查root权限
    check_root

    # 确保 Gum 已安装
    ensure_gum

    detect_system
    get_iptables_paths
    init_config_dir
    load_config
    ensure_ip_forward

    # 交互式菜单
    while true; do
        choice=$(show_menu)

        case "$choice" in
            *添加*)
                interactive_add_forward
                gum_pause
                ;;
            *删除*)
                interactive_remove_forward
                gum_pause
                ;;
            *修改端口*)
                interactive_modify_forward
                gum_pause
                ;;
            *显示当前*)
                show_forward_rules
                gum_pause
                ;;
            *清空*)
                clear_all_forwards
                gum_pause
                ;;
            *切换*po0*)
                toggle_po0_mode
                gum_pause
                ;;
            *修改内网IP*)
                change_lan_ip
                gum_pause
                ;;
            *备份*)
                show_backups
                gum_pause
                ;;
            *退出*)
                log_info "退出 IPTables Manager"
                break
                ;;
        esac
    done
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
