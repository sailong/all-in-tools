# Sing-box 全能管理面板 (Alpine Linux 专用版)

> **版本**: v24.0  
> **核心**: Sing-box + Cloudflared  
> **适用系统**: Alpine Linux (Ash/Bash 兼容)

这是一个专为轻量级 **Alpine Linux** 环境设计的 Sing-box 管理脚本。它支持多节点并存、模块化配置管理，并集成了 Cloudflared 隧道的一键部署功能。

---

## 🌟 主要特性

* **多节点架构**：支持同时添加和运行多个不同协议的节点（配置独立存储）。
* **协议全覆盖**：
    * VLESS (Reality / WS-Tunnel / TCP)
    * Shadowsocks (支持 7 种主流加密方式)
    * Trojan (TCP / WS)
    * Hysteria2
    * TUIC (Quic)
    * Socks5
* **Cloudflared 隧道集成**：一键安装/管理 Cloudflared，完美配合 VLESS+WS 穿透内网。
* **智能订阅生成**：
    * **Tunnel 模式**：自动识别 `.sni` 文件，生成符合客户端标准的 HTTPS (TLS) 订阅链接。
    * **Reality 模式**：自动补全公钥 (pbk) 和指纹信息。
* **系统级服务**：基于 OpenRC 的进程守护，支持开机自启、优雅重启、防崩溃保护。
* **交互优化**：单列菜单、快捷命令 (`auvsb`)、状态实时监控。

---

## 🚀 一键运行
```bash
bash <(curl -Ls https://sl.bluu.pl/GBYJ)
```
---

## 📥 下载脚本 (示例)
```bash
wget -O auvsb.sh https://raw.githubusercontent.com/sailong/all-in-tools/refs/heads/main/auvsb/alpine/auvsb.sh
```

## 📋 赋予执行权限
```bash
chmod +x auvsb.sh
```

## 🚀 运行脚本
```bash
./auvsb.sh
```
