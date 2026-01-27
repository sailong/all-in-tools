#!/bin/sh

# =========================================================
# sing-box 面板 v24.0 (JSON结构重构/显示修复版)
# =========================================================

# [自检] 修复环境变量
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# --- 基础配置 ---
SB_BIN="/usr/local/bin/sing-box"
CF_BIN="/usr/local/bin/cloudflared"
BASE_DIR="/etc/sing-box"
NODE_DIR="${BASE_DIR}/nodes"
CONFIG_FILE="${BASE_DIR}/config.json"
CF_TOKEN_FILE="/etc/cloudflared_token"
SHORTCUT_BIN="/usr/bin/auvsb"

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

# ---------------------------------------------------------
# [模块 1] 工具函数
# ---------------------------------------------------------

cls() { printf "\033c"; }

get_random_port() {
    awk 'BEGIN{srand(); print int(rand()*(60000-10000+1))+10000}'
}

# 提取 JSON 值 (增强版：支持多行格式)
get_json_str() {
    # 匹配 "key": "value" 格式，忽略前导空格和后续逗号
    sed -n 's/^[[:space:]]*"'$1'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$2" | head -n 1
}

get_json_int() {
    # 匹配 "key": 123 格式
    sed -n 's/^[[:space:]]*"'$1'"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$2" | head -n 1
}

# 状态检测
get_status() {
    if rc-service "$1" status >/dev/null 2>&1; then
        echo -e "${GREEN}(Running)${NC}"
    else
        echo -e "${RED}(Stopped)${NC}"
    fi
}

# 优雅重启
restart_service() {
    SVC=$1
    if [ "$SVC" = "sing-box" ]; then
        if ! $SB_BIN check -c $CONFIG_FILE >/dev/null 2>&1; then
            echo -e "${RED}配置校验失败！请检查以下错误：${NC}"
            $SB_BIN check -c $CONFIG_FILE
            return 1
        fi
    fi
    rc-service "$SVC" restart >/dev/null 2>&1
    if rc-service "$SVC" status >/dev/null 2>&1; then
        echo -e "${GREEN}$SVC 已重启 [OK]${NC}"
    else
        echo -e "${RED}$SVC 启动失败 [Error]${NC}"
        [ "$SVC" = "sing-box" ] && tail -n 5 /var/log/sing-box.err 2>/dev/null
    fi
}

# ---------------------------------------------------------
# [模块 2] 安装与更新
# ---------------------------------------------------------

install_sb() {
    cls
    echo -e "${BLUE}初始化环境...${NC}"
    if [ -f /etc/alpine-release ]; then
        apk update >/dev/null 2>&1
        apk add curl wget tar openssl util-linux ca-certificates bash >/dev/null 2>&1
    fi
    mkdir -p "$BASE_DIR" "$NODE_DIR"

    ARCH=$(uname -m)
    [ "$ARCH" = "x86_64" ] && SB_ARCH="linux-amd64" || SB_ARCH="linux-arm64"

    LATEST_VER=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | awk -F '"' '/tag_name/{print $4}' | sed 's/^v//')
    
    if [ -f "$SB_BIN" ]; then
        CUR_VER=$($SB_BIN version | grep "sing-box version" | awk '{print $3}')
        if [ "$CUR_VER" = "$LATEST_VER" ]; then
            cp "$0" "$SHORTCUT_BIN"; chmod +x "$SHORTCUT_BIN"
            return
        fi
    fi

    echo -e "${BLUE}安装 v$LATEST_VER...${NC}"
    wget -qO- "https://github.com/SagerNet/sing-box/releases/download/v${LATEST_VER}/sing-box-${LATEST_VER}-${SB_ARCH}.tar.gz" | tar -xz
    
    if [ -d "sing-box-${LATEST_VER}-${SB_ARCH}" ]; then
        rc-service sing-box stop >/dev/null 2>&1
        mv "sing-box-${LATEST_VER}-${SB_ARCH}/sing-box" $SB_BIN
        chmod +x $SB_BIN
        rm -rf "sing-box-${LATEST_VER}-${SB_ARCH}"
    fi

    cat <<EOF > /etc/init.d/sing-box
#!/sbin/openrc-run
description="sing-box service"
command="$SB_BIN"
command_args="run -c $CONFIG_FILE"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/sing-box.log"
error_log="/var/log/sing-box.err"
depend() { need net; after firewall; }
EOF
    chmod +x /etc/init.d/sing-box
    rc-update add sing-box default >/dev/null 2>&1
    cp "$0" "$SHORTCUT_BIN"; chmod +x "$SHORTCUT_BIN"
}

uninstall_sb() {
    cls
    echo -e "${RED}=== 卸载面板 ===${NC}"
    read -p "确认 (y/n): " C
    if [ "$C" = "y" ]; then
        rc-service cloudflared stop >/dev/null 2>&1
        rc-update del cloudflared default >/dev/null 2>&1
        rm -f "$CF_BIN" "$CF_TOKEN_FILE" "/etc/init.d/cloudflared"
        rc-service sing-box stop >/dev/null 2>&1
        rc-update del sing-box default >/dev/null 2>&1
        rm -rf "$SB_BIN" "$BASE_DIR" "/etc/init.d/sing-box" "$SHORTCUT_BIN"
        echo -e "${GREEN}已彻底卸载。${NC}"; exit 0
    fi
}

# ---------------------------------------------------------
# [模块 3] 核心配置逻辑
# ---------------------------------------------------------

rebuild_config() {
    cat <<EOF > $CONFIG_FILE
{
  "log": {"level": "info", "timestamp": true},
  "inbounds": [
EOF
    FIRST=1
    for file in "$NODE_DIR"/*.json; do
        if [ -e "$file" ]; then
            if [ $FIRST -eq 0 ]; then echo "," >> $CONFIG_FILE; fi
            cat "$file" >> $CONFIG_FILE
            FIRST=0
        fi
    done
    cat <<EOF >> $CONFIG_FILE
  ],
  "outbounds": [{"type": "direct"}]
}
EOF
    if [ $FIRST -eq 0 ]; then
        restart_service sing-box
    else
        rc-service sing-box stop >/dev/null 2>&1
    fi
}

# ---------------------------------------------------------
# [模块 4] 查看节点 (解析逻辑修复)
# ---------------------------------------------------------

view_node() {
    FILE=$1
    if [ ! -f "$FILE" ]; then echo "文件不存在"; return; fi

    FNAME=$(basename "$FILE")
    echo -e "\n-------------- $FNAME --------------"

    IP=$(curl -s ifconfig.me)
    # 使用新版正则提取，支持多行 JSON
    TYPE=$(get_json_str "type" "$FILE")
    PORT=$(get_json_int "listen_port" "$FILE")
    UUID=$(get_json_str "uuid" "$FILE")
    PASS=$(get_json_str "password" "$FILE")
    PATH_VAL=$(get_json_str "path" "$FILE")
    SNI=$(get_json_str "server_name" "$FILE")
    
    SNI_FILE="${FILE%.json}.sni"
    if [ -f "$SNI_FILE" ]; then
        SNI_FROM_FILE=$(cat "$SNI_FILE")
    else
        SNI_FROM_FILE=""
    fi

    case $TYPE in
        vless)
            FLOW=$(get_json_str "flow" "$FILE")
            if [ -n "$FLOW" ]; then 
                # === VLESS-REALITY ===
                SID=$(sed -n 's/.*"short_id"[[:space:]]*:[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' "$FILE" | head -n 1)
                PBK_F="${FILE%.json}.pbk"
                [ -f "$PBK_F" ] && PBK=$(cat "$PBK_F") || PBK="未知"
                
                echo "协议 (protocol)         = vless"
                echo "地址 (address)          = $IP"
                echo "端口 (port)             = $PORT"
                echo "用户ID (id)             = $UUID"
                echo "流控 (flow)             = $FLOW"
                echo "传输协议 (network)      = tcp"
                echo "传输层安全 (TLS)        = reality"
                echo "SNI (serverName)        = $SNI"
                echo "指纹 (Fingerprint)      = chrome"
                echo "公钥 (Public key)       = $PBK"
                echo "------------- 链接 (URL) -------------"
                echo "vless://$UUID@$IP:$PORT?encryption=none&security=reality&flow=$FLOW&type=tcp&sni=$SNI&pbk=$PBK&fp=chrome&sid=$SID#REALITY-$PORT"
            
            elif [ -n "$PATH_VAL" ]; then 
                # === VLESS-WS (Tunnel 修复) ===
                if [ -n "$SNI_FROM_FILE" ]; then
                    # Tunnel 模式：强制显示 443 + 域名 + TLS伪装
                    LINK_ADDR="$SNI_FROM_FILE"
                    LINK_PORT="443"
                    SHOW_SNI="$SNI_FROM_FILE"
                    
                    echo "协议 (protocol)         = vless"
                    echo "地址 (address)          = $LINK_ADDR"
                    echo "端口 (port)             = $LINK_PORT (Tunnel)"
                    echo "用户ID (id)             = $UUID"
                    echo "传输协议 (network)      = ws"
                    echo "路径 (path)             = $PATH_VAL"
                    echo "SNI (serverName)        = $SHOW_SNI"
                    echo "Host (domain)           = $SHOW_SNI"
                    echo "指纹 (Fingerprint)      = firefox"
                    echo "传输层安全 (TLS)        = tls"
                    echo "------------- 链接 (URL) -------------"
                    
                    ENC_PATH=$(echo "$PATH_VAL" | sed 's/\//%2F/g')
                    # 完美拼接
                    echo "vless://$UUID@$LINK_ADDR:$LINK_PORT?encryption=none&security=tls&sni=$SHOW_SNI&fp=firefox&type=ws&host=$SHOW_SNI&path=$ENC_PATH#VLESS-WS-Tunnel"
                else
                    # 标准 WS
                    [ -n "$SNI" ] && LINK_ADDR="$SNI" || LINK_ADDR="$IP"
                    echo "协议 (protocol)         = vless"
                    echo "地址 (address)          = $LINK_ADDR"
                    echo "端口 (port)             = $PORT"
                    echo "用户ID (id)             = $UUID"
                    echo "传输协议 (network)      = ws"
                    echo "路径 (path)             = $PATH_VAL"
                    echo "------------- 链接 (URL) -------------"
                    ENC_PATH=$(echo "$PATH_VAL" | sed 's/\//%2F/g')
                    echo "vless://$UUID@$LINK_ADDR:$PORT?encryption=none&security=none&type=ws&host=$LINK_ADDR&path=$ENC_PATH#VLESS-WS-$PORT"
                fi
            
            else 
                # === VLESS-TCP ===
                echo "协议 (protocol)         = vless"
                echo "地址 (address)          = $IP"
                echo "端口 (port)             = $PORT"
                echo "用户ID (id)             = $UUID"
                echo "传输协议 (network)      = tcp"
                echo "------------- 链接 (URL) -------------"
                echo "vless://$UUID@$IP:$PORT?encryption=none&security=tls&type=tcp#VLESS-TCP-$PORT"
            fi
            ;;
        tuic)
            echo "协议 (protocol)         = tuic"
            echo "地址 (address)          = $IP"
            echo "端口 (port)             = $PORT"
            echo "用户ID (uuid)           = $UUID"
            echo "密码 (password)         = $UUID"
            echo "------------- 链接 (URL) -------------"
            echo "tuic://$UUID:$UUID@$IP:$PORT?alpn=h3&allow_insecure=1&congestion_control=bbr#TUIC-$PORT"
            ;;
        hysteria2)
            echo "协议 (protocol)         = hysteria2"
            echo "地址 (address)          = $IP"
            echo "端口 (port)             = $PORT"
            echo "密码 (password)         = $PASS"
            echo "------------- 链接 (URL) -------------"
            echo "hysteria2://$PASS@$IP:$PORT?alpn=h3&insecure=1#Hy2-$PORT"
            ;;
        trojan)
            if [ -n "$PATH_VAL" ]; then
                echo "协议 (protocol)         = trojan"
                echo "地址 (address)          = $IP"
                echo "端口 (port)             = $PORT"
                echo "密码 (password)         = $PASS"
                echo "传输 (network)          = ws"
                echo "路径 (path)             = $PATH_VAL"
                echo "------------- 链接 (URL) -------------"
                echo "trojan://$PASS@$IP:$PORT?type=ws&security=tls&host=$IP&path=$PATH_VAL&allowInsecure=1#Trojan-WS-$PORT"
            else
                echo "协议 (protocol)         = trojan"
                echo "地址 (address)          = $IP"
                echo "端口 (port)             = $PORT"
                echo "密码 (password)         = $PASS"
                echo "传输 (network)          = tcp"
                echo "------------- 链接 (URL) -------------"
                echo "trojan://$PASS@$IP:$PORT?security=tls&allowInsecure=1#Trojan-$PORT"
            fi
            ;;
        shadowsocks)
            M=$(get_json_str "method" "$FILE")
            echo "协议 (protocol)         = shadowsocks"
            echo "地址 (address)          = $IP"
            echo "端口 (port)             = $PORT"
            echo "加密 (method)           = $M"
            echo "密码 (password)         = $PASS"
            echo "------------- 链接 (URL) -------------"
            CRED=$(echo -n "${M}:${PASS}" | base64 | tr -d '\n')
            echo "ss://${CRED}@$IP:$PORT#SS-$PORT"
            ;;
        socks)
            U=$(get_json_str "username" "$FILE")
            echo "协议 (protocol)         = socks"
            echo "地址 (address)          = $IP"
            echo "端口 (port)             = $PORT"
            echo "用户 (user)             = $U"
            echo "密码 (pass)             = $PASS"
            echo "------------- 链接 (URL) -------------"
            CRED=$(echo -n "${U}:${PASS}" | base64 | tr -d '\n')
            echo "socks://${CRED}@$IP:$PORT#Socks-$PORT"
            ;;
    esac
    echo "-----------------------------------------------------"
}

list_nodes_menu() {
    cls
    echo -e "${YELLOW}=== 节点列表 ===${NC}"
    i=1
    for f in "$NODE_DIR"/*.json; do
        if [ -e "$f" ]; then
            echo "$i. $(basename "$f")"
            eval "FILE_$i='$f'"
            i=$((i+1))
        fi
    done
    if [ $i -eq 1 ]; then echo "暂无节点"; return 1; fi
    return 0
}

# ---------------------------------------------------------
# [模块 5] 添加节点 (格式化写入修复)
# ---------------------------------------------------------

add_node() {
    cls
    if [ ! -f "$SB_BIN" ]; then install_sb; fi

    echo -e "${YELLOW}=== 添加新节点 ===${NC}"
    echo "1. VLESS-REALITY"
    echo "2. VLESS + WS (Tunnel)"
    echo "3. VLESS + TCP"
    echo "4. Shadowsocks"
    echo "5. Socks5"
    echo "6. Trojan (TCP)"
    echo "7. Trojan-WS"
    echo "8. Hysteria2"
    echo "9. TUIC"
    echo "0. 返回上一级"
    
    read -p "请选择: " OPT
    [ "$OPT" = "0" ] && return

    R_PORT=$(get_random_port)
    read -p "设置端口 [回车随机 $R_PORT]: " PORT
    [ -z "$PORT" ] && PORT=$R_PORT
    
    if grep -q "\"listen_port\":[[:space:]]*$PORT" "$NODE_DIR"/*.json 2>/dev/null; then
        echo -e "${RED}端口 $PORT 已被占用！${NC}"; read -p "按回车继续..."; return
    fi

    R_UUID=$($SB_BIN generate uuid)
    WS_PATH="/$R_UUID"

    # 使用 cat <<EOF 将 JSON 写入为多行格式，确保 sed 能正确解析
    case $OPT in
        1) # REALITY
            read -p "UUID [默认随机]: " UUID; [ -z "$UUID" ] && UUID=$R_UUID
            echo -e "\n${YELLOW}请选择回落域名 (Dest/SNI):${NC}"
            echo "1. www.amazon.com"
            echo "2. www.microsoft.com"
            echo "3. www.google.com"
            echo "4. www.apple.com"
            echo "5. www.tesla.com"
            echo "6. www.yahoo.com"
            echo "0. 手动输入"
            read -p "选择 [默认1]: " D
            case $D in 2) DEST="www.microsoft.com";; 3) DEST="www.google.com";; 4) DEST="www.apple.com";; 5) DEST="www.tesla.com";; 6) DEST="www.yahoo.com";; 0) read -p "输入域名: " DEST;; *) DEST="www.amazon.com";; esac
            [ -z "$DEST" ] && DEST="www.amazon.com"
            
            KEYS=$($SB_BIN generate reality-keypair)
            PRIV=$(echo "$KEYS" | awk -F ": " '/Private/{print $2}' | tr -d ' \r\n')
            PUB=$(echo "$KEYS" | awk -F ": " '/Public/{print $2}' | tr -d ' \r\n')
            SID=$(openssl rand -hex 8)
            
            FILE="vless-reality-$PORT"
            echo "$PUB" > "$NODE_DIR/$FILE.pbk"
            
            cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "vless",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID",
      "flow": "xtls-rprx-vision"
    }
  ],
  "tls": {
    "enabled": true,
    "server_name": "$DEST",
    "reality": {
      "enabled": true,
      "handshake": {
        "server": "$DEST",
        "server_port": 443
      },
      "private_key": "$PRIV",
      "short_id": ["$SID"]
    }
  }
}
EOF
            ;;
        
        2) # VLESS+WS (Tunnel)
            read -p "UUID [默认随机]: " UUID; [ -z "$UUID" ] && UUID=$R_UUID
            WS_PATH="/$UUID" # Update path with UUID
            echo -e "${YELLOW}Tunnel 模式需填写绑定的域名 (SNI)${NC}"
            read -p "输入域名: " DEST; [ -z "$DEST" ] && DEST="example.com"
            FILE="vless-ws-$PORT"
            
            # 写入标识文件
            echo "$DEST" > "$NODE_DIR/$FILE.sni"
            
            # 写入纯净配置 (无TLS)
            cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "vless",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID"
    }
  ],
  "transport": {
    "type": "ws",
    "path": "$WS_PATH"
  }
}
EOF
            ;;
            
        3) # VLESS+TCP
            read -p "UUID [默认随机]: " UUID; [ -z "$UUID" ] && UUID=$R_UUID
            FILE="vless-tcp-$PORT"
            cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "vless",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "uuid": "$UUID"
    }
  ],
  "tls": {
    "enabled": true
  }
}
EOF
            ;;
        4) # SS
            echo -e "\n${YELLOW}请选择 Shadowsocks 加密方式:${NC}"
            echo "1) aes-128-gcm"
            echo "2) aes-256-gcm"
            echo "3) chacha20-ietf-poly1305"
            echo "4) xchacha20-ietf-poly1305"
            echo "5) 2022-blake3-aes-128-gcm"
            echo "6) 2022-blake3-aes-256-gcm"
            echo "7) 2022-blake3-chacha20-poly1305 (默认)"
            read -p "选择 [1-7]: " SC
            case $SC in 
                1) M="aes-128-gcm"; P=$(openssl rand -base64 16) ;;
                2) M="aes-256-gcm"; P=$(openssl rand -base64 32) ;;
                3) M="chacha20-ietf-poly1305"; P=$(openssl rand -base64 32) ;;
                4) M="xchacha20-ietf-poly1305"; P=$(openssl rand -base64 32) ;;
                5) M="2022-blake3-aes-128-gcm"; P=$(openssl rand -base64 16) ;;
                6) M="2022-blake3-aes-256-gcm"; P=$(openssl rand -base64 32) ;;
                *) M="2022-blake3-chacha20-poly1305"; P=$(openssl rand -base64 32) ;;
            esac
            FILE="shadowsocks-$PORT"
            cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "shadowsocks",
  "listen": "::",
  "listen_port": $PORT,
  "method": "$M",
  "password": "$P"
}
EOF
            ;;
        5) # Socks
            FILE="socks-$PORT"
            cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "socks",
  "listen": "::",
  "listen_port": $PORT,
  "users": [
    {
      "username": "auvpua",
      "password": "auvpua"
    }
  ]
}
EOF
            ;;
        *) # 其他
            FILE="node-$PORT"
            R_UUID=$($SB_BIN generate uuid)
            WS_PATH="/$R_UUID"
            case $OPT in
                6) # Trojan TCP
                   FILE="trojan-tcp-$PORT"
                   cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "trojan",
  "listen": "::",
  "listen_port": $PORT,
  "users": [{"password": "$R_UUID"}],
  "tls": {"enabled": true}
}
EOF
                   ;;
                7) # Trojan WS
                   FILE="trojan-ws-$PORT"
                   cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "trojan",
  "listen": "::",
  "listen_port": $PORT,
  "users": [{"password": "$R_UUID"}],
  "transport": {"type": "ws", "path": "$WS_PATH"},
  "tls": {"enabled": true}
}
EOF
                   ;;
                8) # Hy2
                   FILE="hysteria2-$PORT"
                   cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "hysteria2",
  "listen": "::",
  "listen_port": $PORT,
  "password": "$R_UUID",
  "tls": {"enabled": true}
}
EOF
                   ;;
                9) # TUIC
                   FILE="tuic-$PORT"
                   cat <<EOF > "$NODE_DIR/$FILE.json"
{
  "type": "tuic",
  "listen": "::",
  "listen_port": $PORT,
  "users": [{"uuid": "$R_UUID", "password": "$R_UUID"}],
  "congestion_control": "bbr",
  "tls": {"enabled": true}
}
EOF
                   ;;
            esac
            ;;
    esac

    rebuild_config
    
    cls
    echo -e "${YELLOW}=== 节点详情 ===${NC}"
    view_node "$NODE_DIR/$FILE.json"
    read -p "按回车返回上一级..."
}

# ---------------------------------------------------------
# [模块 6] 修改配置
# ---------------------------------------------------------

modify_menu() {
    while true; do
        if list_nodes_menu; then
            echo "0. 返回上一级"
            echo "00. 返回主菜单"
            read -p "选择修改的节点: " IDX
            
            [ "$IDX" = "0" ] && return
            [ "$IDX" = "00" ] && return 99
            
            eval "TARGET=\$FILE_$IDX"
            if [ -n "$TARGET" ]; then
                while true; do
                    cls
                    echo -e "${BLUE}修改: $(basename "$TARGET")${NC}"
                    echo "1. 修改端口"
                    echo "2. 修改 UUID/密码"
                    echo "3. 修改域名"
                    echo "0. 返回节点列表"
                    echo "00. 返回主菜单"
                    read -p "请选择: " M
                    
                    case $M in
                        1) 
                            read -p "新端口: " NP
                            sed -i "s/\"listen_port\":[[:space:]]*[0-9]*/\"listen_port\": $NP/" "$TARGET"
                            NEW="${TARGET%-[0-9]*.json}-${NP}.json"
                            [ -f "${TARGET%.json}.pbk" ] && mv "${TARGET%.json}.pbk" "${NEW%.json}.pbk"
                            [ -f "${TARGET%.json}.sni" ] && mv "${TARGET%.json}.sni" "${NEW%.json}.sni"
                            mv "$TARGET" "$NEW"; TARGET="$NEW"
                            rebuild_config
                            echo "已修改并重启。"
                            ;;
                        2)
                            read -p "新 UUID/密码: " NP
                            sed -i "s/\"uuid\":[[:space:]]*\"[^\"]*\"/\"uuid\": \"$NP\"/" "$TARGET"
                            sed -i "s/\"password\":[[:space:]]*\"[^\"]*\"/\"password\": \"$NP\"/" "$TARGET"
                            rebuild_config
                            echo "已修改。"
                            ;;
                        3)
                            read -p "新域名: " ND
                            SNI_F="${TARGET%.json}.sni"
                            if [ -f "$SNI_F" ]; then
                                echo "$ND" > "$SNI_F"
                            else
                                sed -i "s/\"server_name\":[[:space:]]*\"[^\"]*\"/\"server_name\": \"$ND\"/" "$TARGET"
                            fi
                            rebuild_config
                            echo "已修改。"
                            ;;
                        0) break ;;
                        00) return 99 ;;
                    esac
                    read -p "按回车继续..."
                done
            else
                echo "无效选择"; sleep 1
            fi
        else
            read -p "无节点，回车返回..."
            return
        fi
    done
}

# ---------------------------------------------------------
# [模块 7] Cloudflared
# ---------------------------------------------------------

manage_cf() {
    while true; do
        cls
        echo -e "${BLUE}Cloudflared 隧道管理 $(get_status cloudflared)${NC}"
        echo "1. 安装/重置 Token"
        echo "2. 启动服务"
        echo "3. 停止服务"
        echo "4. 重启服务"
        echo "5. 卸载隧道"
        echo "0. 返回上一级"
        echo "00. 返回主菜单"
        read -p "请选择: " C
        
        case $C in
            1)
                read -p "输入 Token: " TK
                if [ -n "$TK" ]; then
                    echo "$TK" > $CF_TOKEN_FILE
                    if [ ! -f "$CF_BIN" ]; then
                        ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && CA="amd64" || CA="arm64"
                        wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CA}" -O $CF_BIN
                        chmod +x $CF_BIN
                    fi
                    cat <<EOF > /etc/init.d/cloudflared
#!/sbin/openrc-run
description="Cloudflared"
command="$CF_BIN"
command_args="tunnel --no-autoupdate run --token \$(cat $CF_TOKEN_FILE)"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
EOF
                    chmod +x /etc/init.d/cloudflared
                    rc-update add cloudflared default >/dev/null 2>&1
                    restart_service cloudflared
                    sleep 2
                fi
                ;;
            2) rc-service cloudflared start ;;
            3) rc-service cloudflared stop ;;
            4) restart_service cloudflared; sleep 1 ;;
            5) 
                rc-service cloudflared stop >/dev/null 2>&1
                rm -f "$CF_BIN" "$CF_TOKEN_FILE" "/etc/init.d/cloudflared"
                echo "已卸载"
                sleep 1
                ;;
            0) return ;;
            00) return 99 ;;
        esac
    done
}

# ---------------------------------------------------------
# [主菜单]
# ---------------------------------------------------------

[ ! -f "$SB_BIN" ] && install_sb

while true; do
    cls
    echo -e "${BLUE}sing-box 全能面板 v24.0 $(get_status sing-box)${NC}"
    echo "1. 添加配置"
    echo "2. 查看配置"
    echo "3. 修改配置"
    echo "4. 删除配置"
    echo "5. 运行管理"
    echo "6. 更新内核"
    echo "7. 卸载面板"
    echo "8. Cloudflared 隧道"
    echo "0. 退出"
    echo -e "${BLUE}==========================================${NC}"
    read -p "请选择: " OPT
    
    case $OPT in
        1) add_node ;;
        2) 
            if list_nodes_menu; then
                echo "0. 返回"
                read -p "选择查看: " IDX
                [ "$IDX" != "0" ] && eval "TARGET=\$FILE_$IDX" && view_node "$TARGET" && read -p "按回车返回..."
            else
                read -p "按回车返回..."
            fi
            ;;
        3) modify_menu; [ $? -eq 99 ] && continue ;;
        4) 
            if list_nodes_menu; then
                echo "0. 返回"
                read -p "选择删除: " IDX
                if [ "$IDX" != "0" ]; then
                    eval "TARGET=\$FILE_$IDX"
                    rm -f "$TARGET" "${TARGET%.json}.pbk" "${TARGET%.json}.sni"
                    rebuild_config
                fi
            else
                read -p "按回车返回..."
            fi
            ;;
        5)
            echo "1. 启动"
            echo "2. 停止"
            echo "3. 重启"
            echo "4. 状态"
            echo "0. 返回"
            read -p "选择: " S
            case $S in
                1) restart_service sing-box ;;
                2) rc-service sing-box stop ;;
                3) restart_service sing-box ;;
                4) rc-service sing-box status ;;
            esac
            read -p "按回车返回..."
            ;;
        6) install_sb ;;
        7) uninstall_sb ;;
        8) manage_cf; [ $? -eq 99 ] && continue ;;
        0) exit 0 ;;
        *) echo "无效选择"; sleep 1 ;;
    esac
done