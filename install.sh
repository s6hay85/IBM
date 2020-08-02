#!/bin/bash
SH_PATH=$(cd "$(dirname "$0")";pwd)
cd ${SH_PATH}

create_mainfest_file(){
    echo "Configuring"
    read -p "Please enter your app name:" IBM_APP_NAME
    echo "App name:${IBM_APP_NAME}"
    read -p "Please enter your memory size(default: 256MB):" IBM_MEM_SIZE
    if [ -z "${IBM_MEM_SIZE}" ];then
    IBM_MEM_SIZE=256
    fi
    echo "Memory size:${IBM_MEM_SIZE}"
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "Generating random UUID:${UUID}"
    WSPATH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    echo "Generating random WebSocket path:${WSPATH}"
    
    cat >  ${SH_PATH}/IBM/v2ray-cloudfoundry/manifest.yml  << EOF
    applications:
    - path: .
      name: ${IBM_APP_NAME}
      random-route: true
      memory: ${IBM_MEM_SIZE}M
EOF

    cat >  ${SH_PATH}/IBM/v2ray-cloudfoundry/v2ray/config.json  << EOF
    {
        "inbounds": [
            {
                "port": 8080,
                "protocol": "vmess",
                "settings": {
                    "clients": [
                        {
                            "id": "${UUID}",
                            "alterId": 4
                        }
                    ]
                },
                "streamSettings": {
                    "network":"ws",
                    "wsSettings": {
                        "path": "${WSPATH}"
                    }
                }
            }
        ],
        "outbounds": [
            {
                "protocol": "freedom",
                "settings": {}
            }
        ]
    }
EOF
    echo "Configuration done."
}

clone_repo(){
    echo "Initializing"
    git clone https://github.com/s6hay85/IBM
    cd IBM
    git submodule update --init --recursive
    cd v2ray-cloudfoundry/v2ray
    # Upgrade V2Ray to the latest version
    rm v2ray v2ctl
    
    # Script from https://github.com/v2fly/fhs-install-v2ray/blob/master/install-release.sh
    # Get V2Ray release version number
    TMP_FILE="$(mktemp)"
    if ! curl -s -o "$TMP_FILE" 'https://api.github.com/repos/v2fly/v2ray-core/releases/latest'; then
        rm "$TMP_FILE"
        echo 'error: Failed to get the latest version number of V2Ray.'
        exit 1
    fi
    RELEASE_LATEST="$(sed 'y/,/\n/' "$TMP_FILE" | grep 'tag_name' | awk -F '"' '{print $4}')"
    rm "$TMP_FILE"
    echo "Latest V2Ray version: $RELEASE_LATEST"
    # Download latest release
    DOWNLOAD_LINK="https://github.com/v2fly/v2ray-core/releases/download/$RELEASE_LATEST/v2ray-linux-64.zip"
    if ! curl -L -H 'Cache-Control: no-cache' -o "latest-v2ray.zip" "$DOWNLOAD_LINK"; then
        echo 'error: Failed to download V2Ray.'
        return 1
    fi
    unzip latest-v2ray.zip v2ray v2ctl geoip.dat geosite.dat
    rm latest-v2ray.zip
    
    chmod 0755 ./*
    cd ${SH_PATH}/IBM/v2ray-cloudfoundry
    echo "Initialization done"
}

install(){
    echo "Installing:"
    cd ${SH_PATH}/IBM/v2ray-cloudfoundry
    ibmcloud target --cf
    ibmcloud cf install
    ibmcloud cf push
    echo "Installation done"
    echo "Random UUID generated:${UUID}"
    echo "Random WebSocket path generated:${WSPATH}"
    VMESSCODE=$(base64 -w 0 << EOF
    {
      "v": "2",
      "ps": "ibmtunnel",
      "add": "ibmtunnel.us-south.cf.appdomain.cloud",
      "port": "443",
      "id": "${UUID}",
      "aid": "4",
      "net": "ws",
      "type": "none",
      "host": "",
      "path": "${WSPATH}",
      "tls": "tls"
    }
EOF
    )
	echo "Configuration:"
    echo vmess://${VMESSCODE}

}

clone_repo
create_mainfest_file
install
exit 0
