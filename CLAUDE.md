# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication Guidelines

**IMPORTANT: Always respond in Chinese (中文) when working in this repository.**

## Project Overview

IPTables Manager 是一个基于 Bash 的 iptables 端口转发管理工具，提供交互式 TUI 界面和命令行两种操作方式，用于管理 Linux 服务器上的端口转发规则。

**核心功能：**
- 添加、删除、修改端口转发规则（DNAT + SNAT + FORWARD）
- 自动持久化 iptables 规则
- 规则备份和恢复
- 基于 Gum 的现代终端 UI

## Development Environment

- 这是一个**开发仓库**，代码变更在此进行和测试
- 实际生产部署运行在远程 Linux 服务器上
- 使用 `git push` 同步变更到远程仓库，然后在生产服务器上拉取部署

## Key Commands

### 安装和设置
```bash
# 快速设置（验证文件和权限）
sudo bash setup.sh

# 安装到 /opt/iptables-manager 并创建 'ipm' 命令
sudo bash install.sh
```

### 主要操作
```bash
ipm                # 交互式菜单
ipm add            # 交互式添加端口转发
ipm remove         # 交互式删除端口转发
ipm modify         # 交互式修改端口转发
ipm list           # 显示当前转发规则
ipm clear          # 清空所有转发规则
ipm backup         # 显示备份文件
```

### 命令行模式
```bash
ipm add 8080 192.168.1.100:9090      # 添加转发规则
ipm remove 8080                       # 删除转发规则
ipm modify 8080 192.168.1.200:9090   # 修改转发规则
```

## Architecture

### 文件结构

```
iptables-manager/
├── iptables-manager.sh  # 主脚本：端口转发管理核心逻辑
├── common.sh            # 公共函数库（日志、系统检测、Gum TUI）
├── install.sh           # 安装脚本
├── setup.sh             # 快速设置脚本
├── uninstall.sh         # 卸载脚本
├── CLAUDE.md            # 项目文档
└── README.md            # 项目说明
```

### 核心脚本：iptables-manager.sh

**配置和初始化：**
- `init_config_dir()` - 初始化配置目录 `/etc/iptables-manager/`
- `get_iptables_paths()` - 根据系统类型获取 iptables 持久化路径

**验证函数：**
- `validate_ip()` - 验证 IP 地址格式
- `validate_port()` - 验证端口号（1-65535）
- `parse_ip_port()` - 解析 ip:port 格式

**规则管理（核心）：**
- `add_port_forward()` - 添加端口转发规则（DNAT + SNAT + FORWARD）
- `remove_port_forward()` - 删除端口转发规则
- `modify_port_forward()` - 修改端口转发规则
- `persist_iptables()` - 持久化 iptables 规则
- `clear_all_forwards()` - 清空所有转发规则

**备份和恢复：**
- `backup_iptables()` - 备份当前规则（保留最近 5 个）
- `restore_iptables()` - 从备份恢复规则

**交互式界面（Gum TUI）：**
- `interactive_add_forward()` - 交互式添加
- `interactive_remove_forward()` - 交互式删除
- `interactive_modify_forward()` - 交互式修改
- `show_forward_rules()` - 显示当前规则
- `show_menu()` - 主菜单

### 公共函数库：common.sh

- 颜色定义和日志函数（log_info, log_warn, log_error, log_success）
- `check_root()` - root 权限检查
- `detect_system()` - 系统类型检测（Ubuntu/Debian/CentOS）
- `get_current_ip()` - 获取当前 IP 地址
- Gum TUI 函数（gum_choose, gum_input, gum_confirm 等）

### 安装路径

```
/opt/iptables-manager/           # 脚本安装目录
/etc/iptables-manager/           # 配置和规则文件
/etc/iptables-manager/backup/    # iptables 备份文件
/usr/local/bin/ipm               # 符号链接
/usr/local/bin/gum               # Gum TUI 工具
```

### 规则存储格式

规则记录在 `/etc/iptables-manager/port-forward-rules.txt`，每行格式：
```
本地端口:目标IP:目标端口
```
例如：`8080:192.168.1.100:9090`

### 端口转发实现

每条转发规则包含 8 条 iptables 规则：
- 2 条 DNAT（TCP/UDP PREROUTING）
- 2 条 SNAT（TCP/UDP POSTROUTING MASQUERADE）
- 4 条 FORWARD（双向 TCP/UDP ACCEPT）

### 持久化方式

根据系统类型自动选择：
- Ubuntu/Debian: `iptables-persistent` + `/etc/iptables/rules.v4`
- CentOS: `/etc/sysconfig/iptables`
- 其他: `/etc/iptables.rules`

## Development Guidelines

### 系统兼容性
- 支持: Ubuntu, Debian, CentOS/RHEL
- 不支持: Alpine, Arch Linux

### 脚本规范
- 所有脚本使用 `set -e`
- 使用 `common.sh` 中的日志函数
- 使用 Gum TUI 提供现代终端交互体验

### Gum TUI 集成
- 所有交互式操作使用 Gum（gum_choose, gum_input, gum_confirm）
- 自动安装 Gum（如未安装）
- 支持键盘操作（方向键、删除键等）
