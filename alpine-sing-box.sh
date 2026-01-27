#!/bin/sh

# =========================================================
# sing-box 面板 v9.0 (Alpine Ash/Busybox 深度兼容版)
# =========================================================

# [自检 1] 强制修复系统环境变量 (解决 rm/cat/ls not found)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 核心变量
SB_BIN="/usr/local/bin/sing-box"
CF_BIN="/usr/local/bin/cloudflared"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
PBK_FILE="${CONFIG_DIR}/pbk.txt"
CF_TOKEN_FILE="/etc/cloudflared_token"

# ---------------------------------------------------------
# [功能模块 1] 核心工具函数 (不依赖外部非标命令)
# ---------------------------------------------------------

# 替代 clear 命令
cls() {
    printf "\033c"
}

# 替代 shuf 命令 (生成随机端口)
get_random_port() {
    awk 'BEGIN{srand(); print int(rand()*(60000-10000+1))+10000}'
}

# 提取 JSON 字符串值 (兼容 key: "val" 和 key : "val")
get_json_str() {
    key=$1
    file=$2
    if [ ! -f "$file" ]; then return; fi
    sed -n 's/.*"'$key'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -n 1
}

# 提取 JSON 数字值
get_json_int() {
    key=$1
    file=$2
    if [ ! -f "$file" ]; then return; fi
    sed -n 's/.*"'$key'"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$file" | head -n 1
}

# ---------------------------------------------------------
# [功能模块 2] 环境检查与安装
# ---------------------------------------------------------

check_deps() {
    # 检查是否为 Alpine
    if [ -f /etc/alpine-release ]; then
        # 这一步至关重要：静默安装核心依赖
        apk update >/dev/null 2>&1
        apk add curl wget tar openssl util-linux ca-certificates >/dev/null 2>&1
    fi

    # 二次验证
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}致命错误：curl 安装失败，无法继续。请手动执行 apk add curl${NC}"
        exit 1
    fi
}

install_sb() {
    cls
    echo -e "${BLUE}正在初始化环境...${NC}"
    check_deps
    
    mkdir -p "$CONFIG_DIR"
    
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) SB_ARCH="linux-amd64" ;;
        aarch64) SB_ARCH="linux-arm64" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
    esac

    echo -e "${BLUE}正在获取最新版本...${NC}"
    # 使用 awk 提取版本号，比 sed 更稳
    VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
    
    if [ -z "$VERSION" ]; then
        echo -e "${RED}获取版本失败，请检查网络连接。${NC}"
        return
    fi

    echo -e "${GREEN}下载 sing-box v$VERSION...${NC}"
    wget -qO- "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/sing-box-${VERSION}-${SB_ARCH}.tar.gz" | tar -xz
    
    # 移动文件并清理
    if [ -d "sing-box-${VERSION}-${SB_ARCH}" ]; then
        mv "sing-box-${VERSION}-${SB_ARCH}/sing-box" $SB_BIN
        chmod +x $SB_BIN
        rm -rf "sing-box-${VERSION}-${SB_ARCH}"
    else
        echo -e "${RED}下载解压失败！${NC}"
        exit 1
    fi

    # 配置 OpenRC 服务 (解决 crashed 问题)
    cat <<EOF > /etc/init.d/sing-box
#!/sbin/openrc-run
description="sing-box proxy service"
command="$SB_BIN"
command_args="run -c $CONFIG_FILE"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"

start_pre() {
    # 强杀旧进程，防止端口占用
    killall sing-box >/dev/null 2>&1
    rm -f /run/sing-box.pid
    return 0
}

depend() {
    need net
    after firewall
}
EOF
    chmod +x /etc/init.d/sing-box
    
    # 尝试加入自启
    if command -v rc-update >/dev/null 2>&1; then
        rc-update add sing-box default >/dev/null 2>&1
    fi
    
    echo -e "${GREEN}安装完成！${NC}"
    sleep 1
}

# ---------------------------------------------------------
# [功能模块 3] 生成配置 (逻辑严密版)
# ---------------------------------------------------------

gen_config() {
    cls
    # 检查安装
    if [ ! -f "$SB_BIN" ]; then install_sb; fi

    echo -e "${YELLOW}请选择协议类型:${NC}"
    echo "1) VLESS-REALITY"
    echo "2) VLESS-WS"
    echo "3) TUIC"
    echo "4) Trojan"
    echo "5) Hysteria2"
    echo "6) Shadowsocks"
    echo "7) Trojan-WS"
    echo "8) Socks"
    
    read -p "请输入选项 [1-8]: " OPT
    if [ -z "$OPT" ]; then OPT=1; fi

    # 端口设置
    read -p "设置端口 (回车随机 10000-60000): " PORT
    if [ -z "$PORT" ]; then PORT=$(get_random_port); fi
    
    # 基础参数
    IP=$(curl -s ifconfig.me)
    UUID=$($SB_BIN generate uuid)
    WS_PATH="/$UUID"
    
    # 清理旧数据
    rm -f "$PBK_FILE"

    echo -e "${BLUE}正在生成配置...${NC}"

    case $OPT in
        1) # VLESS-REALITY
            KEYS=$($SB_BIN generate reality-keypair)
            # 兼容处理：有些版本输出 PrivateKey: 有些是 Private key:
            PRIV=$(echo "$KEYS" | awk -F ": " '/Private/{print $2}' | tr -d ' \r\n')
            PUB=$(echo "$KEYS" | awk -F ": " '/Public/{print $2}' | tr -d ' \r\n')
            SID=$(openssl rand -hex 8)
            
            # 持久化保存公钥
            echo "$PUB" > "$PBK_FILE"
            
            cat <<EOF > $CONFIG_FILE
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [{
    "type": "vless",
    "listen": "::",
    "listen_port": $PORT,
    "users": [{"uuid": "$UUID", "flow": "xtls-rprx-vision"}],
    "tls": {
      "enabled": true,
      "server_name": "www.amazon.com",
      "reality": {
        "enabled": true,
        "handshake": {"server": "www.amazon.com", "server_port": 443},
        "private_key": "$PRIV",
        "short_id": ["$SID"]
      }
    }
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
        2) # VLESS-WS
            cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "type": "vless", "listen": "::", "listen_port": $PORT,
    "users": [{"uuid": "$UUID"}],
    "transport": {"type": "ws", "path": "$WS_PATH"},
    "tls": {"enabled": true}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
        3) # TUIC
            cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "type": "tuic", "listen": "::", "listen_port": $PORT,
    "users": [{"uuid": "$UUID", "password": "$UUID"}],
    "congestion_control": "bbr",
    "tls": {"enabled": true}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
        4) # Trojan
            cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "type": "trojan", "listen": "::", "listen_port": $PORT,
    "users": [{"password": "$UUID"}],
    "tls": {"enabled": true}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
        5) # Hysteria2
            cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "type": "hysteria2", "listen": "::", "listen_port": $PORT,
    "password": "$UUID",
    "tls": {"enabled": true}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
        6) # Shadowsocks
            echo -e "${YELLOW}选择加密方式:${NC}"
            echo "1) aes-128-gcm"
            echo "2) aes-256-gcm"
            echo "3) chacha20-ietf-poly1305"
            echo "4) xchacha20-ietf-poly1305"
            echo "5) 2022-blake3-aes-128-gcm"
            echo "6) 2022-blake3-aes-256-gcm"
            echo "7) 2022-blake3-chacha20-poly1305 (默认)"
            read -p "选择: " SS_OPT
            case $SS_OPT in
                1) M="aes-128-gcm"; P=$(openssl rand -base64 16) ;;
                2) M="aes-256-gcm"; P=$(openssl rand -base64 32) ;;
                3) M="chacha20-ietf-poly1305"; P=$(openssl rand -base64 32) ;;
                4) M="xchacha20-ietf-poly1305"; P=$(openssl rand -base64 32) ;;
                5) M="2022-blake3-aes-128-gcm"; P=$(openssl rand -base64 16) ;;
                6) M="2022-blake3-aes-256-gcm"; P=$(openssl rand -base64 32) ;;
                *) M="2022-blake3-chacha20-poly1305"; P=$(openssl rand -base64 32) ;;
            esac
            
            cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "type": "shadowsocks", "listen": "::", "listen_port": $PORT,
    "method": "$M", "password": "$P"
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
        7) # Trojan-WS
            cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "type": "trojan", "listen": "::", "listen_port": $PORT,
    "users":[{"password": "$UUID"}],
    "transport": {"type": "ws", "path": "$WS_PATH"},
    "tls": {"enabled": true}
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
        8) # Socks
            cat <<EOF > $CONFIG_FILE
{
  "inbounds": [{
    "type": "socks", "listen": "::", "listen_port": $PORT,
    "users": [{"username": "a", "password": "a"}]
  }],
  "outbounds": [{"type": "direct"}]
}
EOF
            ;;
    esac

    # 重启服务
    if command -v rc-service >/dev/null 2>&1; then
        rc-service sing-box restart >/dev/null 2>&1
    else
        # Docker 兼容模式
        killall sing-box >/dev/null 2>&1
        nohup $SB_BIN run -c $CONFIG_FILE >/dev/null 2>&1 &
    fi

    echo -e "${GREEN}配置已生成并尝试启动！${NC}"
    # 自动跳转查看
    view_config
}

# ---------------------------------------------------------
# [功能模块 4] 查看配置 (完美解析版)
# ---------------------------------------------------------

view_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}未找到配置文件！${NC}"
        return
    fi
    
    IP=$(curl -s ifconfig.me)
    # 强制获取第一个 type 字段，避免读取到 outbound 的 type
    TYPE=$(grep -m 1 '"type"' "$CONFIG_FILE" | cut -d '"' -f4)
    PORT=$(get_json_int "listen_port" "$CONFIG_FILE")
    PATH_VAL=$(get_json_str "path" "$CONFIG_FILE")
    
    # 修正显示名称
    SHOW_TYPE=$(echo "$TYPE" | tr 'a-z' 'A-Z')
    if [ "$TYPE" = "vless" ] && [ -n "$PATH_VAL" ]; then SHOW_TYPE="VLESS-WS"; fi
    if [ "$TYPE" = "trojan" ] && [ -n "$PATH_VAL" ]; then SHOW_TYPE="TROJAN-WS"; fi
    
    echo -e "\n-------------- ${SHOW_TYPE}-${PORT}.json --------------"
    
    case $TYPE in
        vless)
            UUID=$(get_json_str "uuid" "$CONFIG_FILE")
            FLOW=$(get_json_str "flow" "$CONFIG_FILE")
            
            if [ -n "$FLOW" ]; then
                # REALITY
                SNI=$(get_json_str "server_name" "$CONFIG_FILE")
                # 提取 short_id 数组中的第一个值
                SID=$(sed -n 's/.*"short_id"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' "$CONFIG_FILE" | head -n 1)
                # 读取保存的公钥
                if [ -f "$PBK_FILE" ]; then PBK=$(cat "$PBK_FILE"); else PBK="缺失(需重置)"; fi
                
                echo -e "协议 (protocol)         = vless"
                echo -e "地址 (address)          = $IP"
                echo -e "端口 (port)             = $PORT"
                echo -e "用户ID (uuid)           = $UUID"
                echo -e "流控 (flow)             = $FLOW"
                echo -e "公钥 (pbk)              = $PBK"
                echo "------------- 链接 (URL) -------------"
                echo "vless://$UUID@$IP:$PORT?encryption=none&security=reality&flow=$FLOW&type=tcp&sni=$SNI&fp=chrome&sid=$SID&pbk=$PBK#REALITY-$IP"
            else
                # WS
                echo -e "协议 (protocol)         = vless"
                echo -e "地址 (address)          = $IP"
                echo -e "端口 (port)             = $PORT"
                echo -e "用户ID (uuid)           = $UUID"
                echo -e "路径 (path)             = $PATH_VAL"
                echo "------------- 链接 (URL) -------------"
                # URL 编码 path
                ENC_PATH=$(echo "$PATH_VAL" | sed 's/\//%2F/g')
                echo "vless://$UUID@$IP:$PORT?encryption=none&security=tls&type=ws&host=$IP&path=$ENC_PATH#VLESS-WS-$IP"
            fi
            ;;
        tuic)
            UUID=$(get_json_str "uuid" "$CONFIG_FILE")
            echo -e "协议 (protocol)         = tuic"
            echo -e "地址 (address)          = $IP"
            echo -e "端口 (port)             = $PORT"
            echo -e "用户ID (uuid)           = $UUID"
            echo -e "密码 (password)         = $UUID"
            echo "------------- 链接 (URL) -------------"
            echo "tuic://$UUID:$UUID@$IP:$PORT?alpn=h3&allow_insecure=1&congestion_control=bbr#TUIC-$IP"
            ;;
        trojan)
            PASS=$(get_json_str "password" "$CONFIG_FILE")
            if [ -z "$PATH_VAL" ]; then
                # TCP
                echo -e "协议 (protocol)         = trojan"
                echo -e "地址 (address)          = $IP"
                echo -e "端口 (port)             = $PORT"
                echo -e "密码 (password)         = $PASS"
                echo "------------- 链接 (URL) -------------"
                echo "trojan://$PASS@$IP:$PORT?security=tls&allowInsecure=1#Trojan-$IP"
            else
                # WS
                echo -e "协议 (protocol)         = trojan"
                echo -e "地址 (address)          = $IP"
                echo -e "端口 (port)             = $PORT"
                echo -e "密码 (password)         = $PASS"
                echo -e "路径 (path)             = $PATH_VAL"
                echo "------------- 链接 (URL) -------------"
                echo "trojan://$PASS@$IP:$PORT?type=ws&security=tls&host=$IP&path=$PATH_VAL&allowInsecure=1#Trojan-WS-$IP"
            fi
            ;;
        hysteria2)
            PASS=$(get_json_str "password" "$CONFIG_FILE")
            echo -e "协议 (protocol)         = hysteria2"
            echo -e "地址 (address)          = $IP"
            echo -e "端口 (port)             = $PORT"
            echo -e "密码 (password)         = $PASS"
            echo "------------- 链接 (URL) -------------"
            echo "hysteria2://$PASS@$IP:$PORT?alpn=h3&insecure=1#Hy2-$IP"
            ;;
        shadowsocks)
            M=$(get_json_str "method" "$CONFIG_FILE")
            P=$(get_json_str "password" "$CONFIG_FILE")
            echo -e "协议 (protocol)         = shadowsocks"
            echo -e "地址 (address)          = $IP"
            echo -e "端口 (port)             = $PORT"
            echo -e "加密 (method)           = $M"
            echo -e "密码 (password)         = $P"
            echo "------------- 链接 (URL) -------------"
            # Base64 编码 (手动实现 tr 处理换行)
            CRED=$(echo -n "${M}:${P}" | base64 | tr -d '\n')
            echo "ss://${CRED}@$IP:$PORT#SS-$IP"
            ;;
        socks)
            U=$(get_json_str "username" "$CONFIG_FILE")
            P=$(get_json_str "password" "$CONFIG_FILE")
            echo -e "协议 (protocol)         = socks"
            echo -e "地址 (address)          = $IP"
            echo -e "端口 (port)             = $PORT"
            echo -e "用户 (user)             = $U"
            echo -e "密码 (pass)             = $P"
            echo "------------- 链接 (URL) -------------"
            CRED=$(echo -n "${U}:${P}" | base64 | tr -d '\n')
            echo "socks://${CRED}@$IP:$PORT#Socks-$IP"
            ;;
    esac
    echo "-----------------------------------------------------"
    read -p "按回车键返回菜单..."
}

# ---------------------------------------------------------
# [功能模块 5] Cloudflared 隧道
# ---------------------------------------------------------

manage_cf() {
    while true; do
        cls
        echo -e "${BLUE}>>> Cloudflared 固定隧道管理 <<<${NC}"
        echo "1) 安装/设置 Token"
        echo "2) 运行管理"
        echo "3) 卸载"
        echo "0) 返回"
        read -p "选择: " CO
        case $CO in
            1)
                read -p "请输入 Token: " TK
                if [ -n "$TK" ]; then
                    echo "$TK" > $CF_TOKEN_FILE
                    ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && CA="amd64" || CA="arm64"
                    wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CA}" -O $CF_BIN
                    chmod +x $CF_BIN
                    
                    cat <<EOF > /etc/init.d/cloudflared
#!/sbin/openrc-run
description="Cloudflared Tunnel"
command="$CF_BIN"
command_args="tunnel --no-autoupdate run --token \$(cat $CF_TOKEN_FILE)"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
EOF
                    chmod +x /etc/init.d/cloudflared
                    rc-update add cloudflared default >/dev/null 2>&1
                    echo "安装成功"
                    sleep 1
                fi
                ;;
            2)
                echo "1) 启动 2) 停止 3) 状态"
                read -p "选择: " SS
                if [ "$SS" = "1" ]; then rc-service cloudflared start; fi
                if [ "$SS" = "2" ]; then rc-service cloudflared stop; fi
                if [ "$SS" = "3" ]; then rc-service cloudflared status; fi
                read -p "按回车继续..."
                ;;
            3)
                rc-service cloudflared stop >/dev/null 2>&1
                rm -f $CF_BIN $CF_TOKEN_FILE /etc/init.d/cloudflared
                echo "已卸载"
                sleep 1
                ;;
            0) return ;;
        esac
    done
}

# ---------------------------------------------------------
# [主程序] 菜单循环
# ---------------------------------------------------------

check_deps # 启动前自检

while true; do
    cls
    echo -e "${BLUE}========== sing-box Panel (Alpine v9.0) ==========${NC}"
    echo " 1) 添加配置"
    echo " 2) 更改配置"
    echo " 3) 查看配置"
    echo " 4) 删除配置"
    echo " 5) 运行管理"
    echo " 6) 更新内核"
    echo " 7) 卸载面板"
    echo " 8) 其他功能"
    echo " 0) 退出"
    echo -e "${BLUE}==================================================${NC}"
    read -p "请选择 [0-8]: " OPT
    
    case "$OPT" in
        1|2) gen_config ;;
        3) view_config ;;
        4) 
            rm -f $CONFIG_FILE $PBK_FILE
            rc-service sing-box stop >/dev/null 2>&1
            echo "配置已删除"
            sleep 1
            ;;
        5) 
            echo "1) 启动 2) 停止 3) 重启 4) 状态"
            read -p "选择: " SS
            if [ "$SS" = "1" ]; then rc-service sing-box start; fi
            if [ "$SS" = "2" ]; then rc-service sing-box stop; fi
            if [ "$SS" = "3" ]; then rc-service sing-box restart; fi
            if [ "$SS" = "4" ]; then rc-service sing-box status; fi
            read -p "按回车继续..."
            ;;
        6) install_sb ;;
        7) 
            rc-service sing-box stop >/dev/null 2>&1
            rc-update del sing-box default >/dev/null 2>&1
            rm -rf $SB_BIN $CONFIG_DIR /etc/init.d/sing-box
            echo "已卸载"
            exit 0
            ;;
        8) manage_cf ;;
        0) exit 0 ;;
        *) echo "无效选项" ; sleep 1 ;;
    esac
done
