#!/bin/bash


# 检查root权限并更新系统
root() {
    # 检查root权限
    if [[ ${EUID} -ne 0 ]]; then
        echo "Error: This script must be run as root!" 1>&2
        exit 1
    fi
    
    # 更新系统和安装基础依赖
    echo "正在更新系统和安装依赖"
    if [ -f "/usr/bin/apt-get" ]; then
        apt-get update -y && apt-get upgrade -y
        apt-get install -y gawk curl
    else
        yum update -y && yum upgrade -y
        yum install -y epel-release gawk curl
    fi
}

# 获取随机端口
port() {    
    local port1 port2    
    port1=$(shuf -i 1024-65000 -n 1)
    while ss -ltn | grep -q ":$port1"; do
        port1=$(shuf -i 1024-65000 -n 1)
    done    
    port2=$(shuf -i 1024-65000 -n 1)
    while ss -ltn | grep -q ":$port2" || [ "$port2" -eq "$port1" ]; do
        port2=$(shuf -i 1024-65000 -n 1)
    done
    
    PORT1=$port1
    PORT2=$port2    
}

# 配置和启动singbox
singbox() {
    # 安装singbox beta内核
    curl -fsSL https://sing-box.app/install.sh | sh -s -- --beta
    # 安装tcp brutal
    bash <(curl -fsSL https://tcp.hy2.sh/)
    # 生成所需参数
    anytlspw=$(openssl rand -base64 16)
    sspw=$(openssl rand -base64 16)
    uuid=$(/usr/bin/sing-box generate uuid)
    X25519Key=$(/usr/bin/sing-box generate reality-keypair)
    shortIds1=$(openssl rand -hex 8)
    shortIds2=$(openssl rand -hex 8)
    PrivateKey=$(echo "${X25519Key}" | grep "PrivateKey" | cut -d " " -f 2)
    PublicKey=$(echo "${X25519Key}" | grep "PublicKey" | cut -d " " -f 2)

    # 配置config.json
    cat >/etc/sing-box/config.json <<EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${PORT1},
      "users": [
        {
          "name": "sbsj",
          "password": "${anytlspw}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.amd.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.amd.com",
            "server_port": 443
          },
          "private_key": "${PrivateKey}",
          "short_id": [
            "${shortIds1}"
          ]
        }
      }
    },
    {
      "tag": "vless-brutal",
      "type": "vless",
      "listen": "::",
      "listen_port": 8443,
      "users": [
        {
          "uuid": "${uuid}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "www.amd.com",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "www.amd.com",
            "server_port": 443
          },
          "private_key": "${PrivateKey}",
          "short_id": [
            "${shortIds2}"
          ]
        }
      },
      "multiplex": {
        "enabled": true,
        "padding": false,
        "brutal": {
          "enabled": true,
          "up_mbps": 500,
          "down_mbps": 500
        }
      }
    },
    {
      "tag": "ss2022-brutal",
      "type": "shadowsocks",
      "listen": "::",
      "listen_port": ${PORT2},
      "method": "2022-blake3-aes-128-gcm",
      "password": "${sspw}",
      "multiplex": {
        "enabled": true,
        "padding": false,
        "brutal": {
          "enabled": true,
          "up_mbps": 500,
          "down_mbps": 500
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct-out"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF

    # 启动singbox服务
    systemctl enable sing-box.service && systemctl restart sing-box.service
    
    # 获取IP并生成客户端配置
    HOST_IP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${HOST_IP}" ]]; then
        HOST_IP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    
    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)
    
    # 生成并保存客户端配置
    cat << EOF > /etc/sing-box/config.txt

anytls-reality
{
  "type": "anytls",
  "tag": "anytls-reality",
  "server": "${HOST_IP}",
  "server_port": ${PORT1},
  "password": "${anytlspw}",
  "tls": {
    "enabled": true,
    "server_name": "www.amd.com",
    "utls": {
      "enabled": true,
      "fingerprint": "chrome"
    },
    "reality": {
      "enabled": true,
      "public_key": "${PublicKey}",
      "short_id": "${shortIds1}"
    }
  }
}

vless-brutal
{
  "type": "vless",
  "tag": "vless-brutal",
  "server": "${HOST_IP}",
  "server_port": 443,
  "uuid": "${uuid}",
  "network": "tcp",
  "tls": {
    "enabled": true,
    "server_name": "www.amd.com",
    "utls": {
      "enabled": true,
      "fingerprint": "chrome"
    },
    "reality": {
      "enabled": true,
      "public_key": "${PublicKey}",
      "short_id": "${shortIds2}"
    }
  },
  "multiplex": {
    "enabled": true,
    "protocol": "h2mux",
    "max_connections": 1,
    "min_streams": 4,
    "padding": false,
    "brutal": {
      "enabled": true,
      "up_mbps": 50,
      "down_mbps": 500
    }
  }
}

ss2022 tcp-brutal
{
  "type": "shadowsocks",
  "tag": "ss2022 tcp-brutal",
  "server": "${HOST_IP}",
  "server_port": ${PORT2},
  "method": "2022-blake3-aes-128-gcm",
  "password": "${sspw}",
  "multiplex": {
    "enabled": true,
    "protocol": "h2mux",
    "max_connections": 1,
    "min_streams": 4,
    "padding": false,
    "brutal": {
      "enabled": true,
      "up_mbps": 50,
      "down_mbps": 500
    }
  }
}
EOF

    echo "singbox 安装完成"
    cat /etc/sing-box/config.txt
}

# 主函数
main() {
    root
    port
    singbox
}

# 执行脚本
main
