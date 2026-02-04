# sing-box 全能面板 (Debian/Ubuntu)

这是一个功能强大的 Bash 脚本，专为 Debian 和 Ubuntu 系统设计，用于一键部署和管理 [sing-box](https://github.com/SagerNet/sing-box) 服务。它提供了一个交互式的菜单界面，支持多种代理协议的配置、节点管理以及 Cloudflare Tunnel 的集成。

## ✨ 主要功能

*   **自动安装与更新**: 自动检测并安装最新版本的 sing-box 核心。
*   **多协议支持**:
    *   **VLESS**: 支持 Reality (XTLS-Vision), WS (Tunnel), TCP。
    *   **Shadowsocks**: 支持多种加密方式 (AES-GCM, Chacha20-Poly1305, 2022-Blake3 等)。
    *   **Trojan**: 支持 TCP 和 WS 传输模式。
    *   **Hysteria2**: 基于 UDP 的高速协议。
    *   **TUIC**: 基于 QUIC 的协议。
    *   **Socks5**: 基础代理支持。
*   **节点管理**:
    *   支持添加多个节点，每个节点独立存储。
    *   自动合并所有节点配置生成主配置文件 (`config.json`)。
    *   支持查看节点详细链接信息 (URL) 和配置参数。
    *   支持修改现有节点的端口、UUID/密码、域名等。
    *   支持删除节点。
*   **服务管理**: 集成 systemd，支持启动、停止、重启和查看运行状态。
*   **Cloudflare Tunnel 集成**: 内置 Cloudflared 管理功能，支持 Token 设置、服务启停及卸载，方便搭建内网穿透。
*   **便捷指令**: 安装后自动创建 `auvsb` 全局快捷指令。

## 🛠️ 环境要求

*   **操作系统**: Debian 或 Ubuntu
*   **架构**: AMD64 (x86_64) 或 ARM64
*   **权限**: 需要 Root 权限运行

## 🚀 快速开始

1.  **下载脚本**
    将 `auvsb.sh` 下载到您的服务器。

2.  **赋予执行权限**
    ```bash
    chmod +x auvsb.sh
    ```

3.  **运行脚本**
    ```bash
    ./auvsb.sh
    ```
    *(首次运行会自动进行环境初始化和依赖安装)*

4.  **快捷命令**
    首次安装成功后，你可以直接在终端输入以下命令启动面板：
    ```bash
    auvsb
    ```

## 📖 菜单说明

### 主菜单
1.  **添加配置**: 新增一个代理节点。
2.  **查看配置**: 查看已添加节点的详细信息和分享链接。
3.  **修改配置**: 修改现有节点的参数（端口、UUID、域名等）。
4.  **删除配置**: 删除指定的节点。
5.  **运行管理**: 控制 sing-box 服务的启动、停止和重启。
6.  **更新内核**: 检查并更新 sing-box 到 GitHub 最新 Release 版本。
7.  **卸载面板**: 彻底清除 sing-box 及相关配置。
8.  **Cloudflared 隧道**: 进入 Cloudflare Tunnel 管理子菜单。

### 支持的协议详情

*   **VLESS-REALITY**: 推荐使用。无需域名，伪装性强。支持自定义回落域名（Dest）。
*   **VLESS + WS (Tunnel)**: 配合 Cloudflare Tunnel 使用，支持内网穿透。
*   **Shadowsocks**: 经典协议，支持 2022 新标准。
*   **Hysteria2 / TUIC**: 适合网络环境较差的情况，基于 UDP/QUIC 优化拥塞控制。

## 📂 目录结构

*   基础目录: `/etc/sing-box`
*   节点存储: `/etc/sing-box/nodes` (每个节点一个 JSON 文件)
*   配置文件: `/etc/sing-box/config.json` (自动生成)
*   执行程序: `/usr/local/bin/sing-box`

## ⚠️ 注意事项

*   脚本修改了 Systemd 服务配置，卸载时会尝试清理。
*   请确保服务器端口未被防火墙拦截（Cloudflare Tunnel 模式除外）。
*   脚本中部分功能依赖 `curl`, `wget`, `openssl` 等工具，会自动尝试安装。
