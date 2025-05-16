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

# 配置和启动Xray
xray() {
    # 安装Xray内核
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
    # 生成所需参数
    path=$(openssl rand -hex 6)
    uuid1=$(/usr/local/bin/xray uuid)
    uuid2=$(/usr/local/bin/xray uuid)
    X25519Key=$(/usr/local/bin/xray x25519)
    shortIds=$(openssl rand -hex 8)
    PrivateKey=$(echo "${X25519Key}" | head -1 | awk '{print $3}')
    PublicKey=$(echo "${X25519Key}" | tail -n 1 | awk '{print $3}')

    # 配置config.json
    cat >/usr/local/etc/xray/config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "dokodemo-in",
      "port": 443,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1",
        "port": 4431,
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "tls"
        ],
        "routeOnly": true
      }
    },
    {
      "listen": "127.0.0.1",
      "port": "4431",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid1}",
            "flow": "xtls-rprx-vision",
            "fallbacks": [
              {
                "dest": "@xhttp"
              }
            ]
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.nvidia.com:443",
          "serverNames": [
            "www.nvidia.com"
          ],
          "privateKey": "${PrivateKey}",
          "shortIds": [
            "${shortIds}"
          ]
        }
      }
    },
    {
      "listen": "@xhttp",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${uuid2}",
            "flow": ""
          }
        ],
        "decryption": "none",
        "fallbacks": []
      },
      "streamSettings": {
        "network": "xhttp",
        "xhttpSettings": {
          "path": "${path}"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blockhole",
      "tag": "block"
    }
  ],
  "routing": {
    "rules": [
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "domain": [
          "www.nvidia.com"
        ],
        "outboundTag": "direct"
      },
      {
        "inboundTag": [
          "dokodemo-in"
        ],
        "outboundTag": "block"
      }
    ]
  }
}
EOF

    # 启动Xray服务
    systemctl enable xray.service && systemctl restart xray.service
    
    # 获取IP并生成客户端配置
    HOST_IP=$(curl -s -4 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    if [[ -z "${HOST_IP}" ]]; then
        HOST_IP=$(curl -s -6 http://www.cloudflare.com/cdn-cgi/trace | grep "ip" | awk -F "[=]" '{print $2}')
    fi
    
    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)
    
    # 生成并保存客户端配置
    cat << EOF > /usr/local/etc/xray/config.txt

vless+tcp+reality
vless://${uuid1}@${HOST_IP}:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.nvidia.com&fp=chrome&pbk=${PublicKey}&sid=${shortIds}&type=tcp&headerType=none#${IP_COUNTRY}-reality

vless+xhttp+reality
vless://${uuid2}@${HOST_IP}:443?encryption=none&security=reality&sni=www.nvidia.com&fp=chrome&pbk=${PublicKey}&sid=${shortIds}&type=xhttp&path=%2F${path}&mode=auto#${IP_COUNTRY}-xhttp-reality
EOF

    echo "Xray 安装完成"
    cat /usr/local/etc/xray/config.txt
}

# 主函数
main() {
    root
    xray
}

# 执行脚本
main
