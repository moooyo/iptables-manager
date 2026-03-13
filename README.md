# IPTables Manager

基于 Bash + [Gum](https://github.com/charmbracelet/gum) TUI 的 Linux iptables 端口转发管理工具。

## 功能

- 添加 / 删除 / 修改端口转发规则（DNAT + SNAT + FORWARD，TCP & UDP）
- 基于 Gum 的交互式终端界面，支持键盘操作
- 规则自动持久化，重启不丢失
- 自动备份 iptables 规则（保留最近 5 份）
- 支持 Ubuntu / Debian / CentOS / RHEL

## 安装

```bash
git clone <repo-url> && cd iptables-manager

# 验证文件完整性和设置权限
sudo bash setup.sh

# 安装到系统（创建 ipm 命令）
sudo bash install.sh
```

安装后的路径：

| 路径 | 用途 |
|------|------|
| `/opt/iptables-manager/` | 脚本安装目录 |
| `/etc/iptables-manager/` | 规则记录和配置 |
| `/etc/iptables-manager/backup/` | iptables 备份 |
| `/usr/local/bin/ipm` | 命令符号链接 |
| `/usr/local/bin/gum` | Gum TUI 工具 |

## 使用

```bash
ipm                # 交互式菜单
ipm add            # 交互式添加端口转发
ipm remove         # 交互式删除端口转发
ipm modify         # 交互式修改端口转发
ipm list           # 显示当前转发规则
ipm clear          # 清空所有转发规则
ipm backup         # 显示备份文件
```

## 工作原理

每条转发规则写入 8 条 iptables 规则：

| 链 | 协议 | 作用 |
|----|------|------|
| PREROUTING (DNAT) | TCP / UDP | 将入站流量目标地址转换为转发目标 |
| POSTROUTING (MASQUERADE) | TCP / UDP | 源地址伪装，确保回包正确返回 |
| FORWARD (ACCEPT) | TCP / UDP | 允许双向转发流量通过 |

规则同时记录在 `/etc/iptables-manager/port-forward-rules.txt`，格式为 `本地端口:目标IP:目标端口`。

持久化方式根据系统自动选择：

- **Ubuntu / Debian** — `iptables-persistent` + `/etc/iptables/rules.v4`
- **CentOS / RHEL** — `/etc/sysconfig/iptables`

## 系统要求

- **OS**: Ubuntu, Debian, CentOS/RHEL（及 Rocky, AlmaLinux, Fedora）
- **架构**: x86_64, aarch64
- **权限**: root
- **依赖**: iptables（安装脚本自动安装）

Gum TUI 工具已内置于 `bin/` 目录，无需联网下载。

## 卸载

```bash
sudo bash uninstall.sh
# 安装后也可以：
sudo bash /opt/iptables-manager/uninstall.sh
```

> 卸载不会清除已生效的 iptables 规则。如需清除：`iptables -F && iptables -t nat -F`

## 文件结构

```
├── iptables-manager.sh  # 主脚本：端口转发管理核心逻辑
├── common.sh            # 公共函数库（日志、系统检测、Gum TUI 封装）
├── install.sh           # 安装脚本
├── setup.sh             # 快速设置脚本（验证文件、设置权限）
├── uninstall.sh         # 卸载脚本
└── bin/
    ├── gum-linux-amd64  # Gum 二进制（x86_64）
    └── gum-linux-arm64  # Gum 二进制（aarch64）
```
