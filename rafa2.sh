#!/bin/bash

function purgeOldInstallation() {
    # terminate wallet daemon
    systemctl stop ${COIN_NAME}.service &>/dev/null
    killall ${COIN_DAEMON} &>/dev/null
    killall ${COIN_DAEMON} &>/dev/null
    killall ${COIN_DAEMON} &>/dev/null

    killall ${COIN_CLI} &>/dev/null
    killall ${COIN_CLI} &>/dev/null
    killall ${COIN_CLI} &>/dev/null

	# save old masternode priv key
	OLD_KEY=$(awk -F'=' '/masternodeprivkey/ {print $2}' ${CONFIG_FOLDER}/${CONFIG_FILE} 2> /dev/null | head -n 1)

	if [ ${#OLD_KEY} -ge "15"  ]; then
        echo
        echo -e "${CYAN}* Saving previously used ${GREEN}${COIN_NAME}${CYAN} Masternode Private Key...${NC}"; sleep 0.5s
        echo -e "${GREEN}  MN PK: ${YELLOW}${OLD_KEY}${NC}"; sleep 0.5s
	fi

    echo
    echo -e "${CYAN}* Removing previous/old ${GREEN}${COIN_NAME}${CYAN} files/folders...${NC}"; sleep 0.5s

    # disable previous port on ufw
    ufw delete allow ${COIN_OLD_PORT}/tcp &>/dev/null

    # remove old files
    rm -- "$0" &>/dev/null
    rm -rf ${CONFIG_FOLDER} &>/dev/null
    rm -rf /usr/local/bin/${COIN_CLI} /usr/local/bin/${COIN_DAEMON} &>/dev/null
    rm -rf /usr/bin/${COIN_CLI} /usr/bin/${COIN_DAEMON} &>/dev/null
    rm -rf /tmp/*
}

function download_node() {
    echo
    echo -e "${CYAN}* Downloading and installing ${GREEN}${COIN_NAME}${CYAN} daemon...${NC}"; sleep 0.5s

    mkdir -p ${TMP_FOLDER}
    cd ${TMP_FOLDER}

    wget_parameters="-q --read-timeout 30 --waitretry 10 --tries 15 -c --retry-connrefused --no-dns-cache --no-check-certificate"

    rm -rf ${COIN_ZIP} &>/dev/null

    echo -e "    ${YELLOW}> Download started...${NC}"; sleep 0.5s

    wget ${wget_parameters} ${COIN_LINK} &>/dev/null || wget ${wget_parameters} ${COIN_LINK} &>/dev/null || { echo -e "${RED}Error: A problem occured while downloading daemon. Restart script to try again please."; exit 1; }

    echo -e "    ${GREEN}> Download complete.${NC}"; sleep 0.5s

    echo -e "    ${YELLOW}> Extracting files...${NC}"; sleep 0.5s

    unzip -q ${COIN_ZIP} || { echo -e "${RED}Error: A problem occured while extracting files. Restart script to try again please."; exit 1; }
    chmod +x ${COIN_DAEMON} ${COIN_CLI}
    mv ${COIN_DAEMON} ${COIN_CLI} ${COIN_PATH}

    echo -e "    ${GREEN}> Extraction complete.${NC}"; sleep 0.5s

    cd ${HOME}

    rm -rf ${TMP_FOLDER} &>/dev/null
}

function configure_systemd() {
    cat << EOF > /etc/systemd/system/${COIN_NAME}.service
[Unit]
Description=${COIN_NAME} service
After=network.target

[Service]
User=root
Group=root

Type=forking
#PIDFile=${CONFIG_FOLDER}/${COIN_NAME}.pid

ExecStart=${COIN_PATH}${COIN_DAEMON} -daemon -conf=${CONFIG_FOLDER}/${CONFIG_FILE} -datadir=${CONFIG_FOLDER}
ExecStop=-${COIN_PATH}${COIN_CLI} -conf=${CONFIG_FOLDER}/${CONFIG_FILE} -datadir=${CONFIG_FOLDER} stop

Restart=always
PrivateTmp=true
TimeoutStopSec=60s
TimeoutStartSec=10s
StartLimitInterval=120s
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    sleep 3
    systemctl enable ${COIN_NAME}.service &>/dev/null
    systemctl start ${COIN_NAME}.service

    if [[ -z "$(ps axo cmd:100 | egrep ${COIN_DAEMON})" ]]; then
        echo
        echo -e "${RED}${COIN_NAME} is not running${NC}, please investigate. You should start by running the following commands as root:"
        echo -e "${GREEN}systemctl start ${COIN_NAME}.service"
        echo -e "systemctl status ${COIN_NAME}.service"
        echo -e "less /var/log/syslog${NC}"
        echo
        exit 1
    fi
}

function create_config() {
    echo
    echo -e "${CYAN}* Creating masternode configuration file...${NC}"; sleep 0.5s

    mkdir -p ${CONFIG_FOLDER} &>/dev/null
    cd ${CONFIG_FOLDER}

    ipcheck_url="ipinfo.io/ip"
    NODEIP="$(curl -s ${ipcheck_url})"

    RPCUSER=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w10 | head -n1)
    RPCPASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w22 | head -n1)

    echo "#Bitcoin Incognito (XBI) configuration file" >> ${CONFIG_FILE}
    echo "#first of all, let's start in the background" >> ${CONFIG_FILE}
    echo "daemon=1" >> ${CONFIG_FILE}
    echo "" >> ${CONFIG_FILE}
    echo "#RPC server settings" >> ${CONFIG_FILE}
    echo "server=1" >> ${CONFIG_FILE}
    echo "rpcuser=${RPCUSER}" >> ${CONFIG_FILE}
    echo "rpcpassword=${RPCPASSWORD}" >> ${CONFIG_FILE}
    echo "" >> ${CONFIG_FILE}
    echo "#network settings" >> ${CONFIG_FILE}
    echo "listen=1" >> ${CONFIG_FILE}
    echo "port=${COIN_PORT}" >> ${CONFIG_FILE}
    echo "#bind=${NODEIP}" >> ${CONFIG_FILE}
    echo "externalip=${NODEIP}" >> ${CONFIG_FILE}
    echo "maxconnections=512" >> ${CONFIG_FILE}
    echo "logtimestamps=1" >> ${CONFIG_FILE}

    GENERATE_NEW_KEY="false"

    if [ -z "${OLD_KEY}" ]; then
        GENERATE_NEW_KEY="true"
    fi

    if [ "${OLD_KEY}" == " " ] || [ "${OLD_KEY}" == "  " ] || [ "${OLD_KEY}" == "   " ]; then
        GENERATE_NEW_KEY="true"
    fi

    if [ ${GENERATE_NEW_KEY} == "true" ]; then

        echo
        echo -e "${CYAN}* Generating a new masternode private key...${NC}"; sleep 0.5s

        ${COIN_PATH}${COIN_DAEMON} -daemon &>/dev/null
        sleep 5s

        unset COINKEY

        count="1"
        while true
        do
            COINKEY="$(${COIN_PATH}${COIN_CLI} masternode genkey 2> /dev/null)"

            if [ ${#COINKEY} -lt "15" ]; then
                echo -e "    ${YELLOW}> Waiting for daemon to start...${NC}"; sleep 0.5s
                sleep 6s
                ((count++))

                if [ "${count}" -ge "10" ]; then
                    echo
                    echo -e "${RED}Error: A problem occured while starting daemon. Restart script to try again please.${NC}"
                    echo

                    exit 1
                fi
            else
                echo -e "    ${YELLOW}> Daemon is running...${NC}"; sleep 0.5s
                echo -e "    ${GREEN}> Generated a new Masternode Private Key.${NC}"; sleep 0.5s
                break
            fi
        done

        ${COIN_PATH}${COIN_CLI} stop &>/dev/null
    else
        COINKEY="${OLD_KEY}"
    fi

    echo "" >> ${CONFIG_FILE}
    echo "#masternode settings" >> ${CONFIG_FILE}
    echo "masternode=1" >> ${CONFIG_FILE}
    echo "masternodeaddr=${NODEIP}" >> ${CONFIG_FILE}
    echo "masternodeprivkey=${COINKEY}" >> ${CONFIG_FILE}
    echo "" >> ${CONFIG_FILE}
}

function enable_firewall() {
    echo
    echo -e "${CYAN}* Configuring firewall to allow port ${PURPLE}${COIN_PORT}${NC}"; sleep 0.5s

    ufw allow ${COIN_PORT}/tcp comment "${COIN_NAME} MN port" &>/dev/null
    ufw allow ssh comment "SSH" &>/dev/null
    ufw limit ssh/tcp &>/dev/null
    ufw default allow outgoing &>/dev/null
    ufw logging on &>/dev/null
    ufw --force enable &>/dev/null

    systemctl daemon-reload &>/dev/null
    systemctl enable ufw &>/dev/null
    systemctl start ufw &>/dev/null
}

function checks() {
    if [ $EUID -ne 0 ]; then
       echo
       echo -e "${RED}Error: This script ${YELLOW}($0)${RED} must be run as root. Terminating setup...${NC}"
       echo

       exit 1
    fi

    if [ -z "$(lsb_release -d | grep -i 'ubuntu.*16.04')" ]; then
        echo
        echo -e "${RED}Error: ${YELLOW}($0)${RED} needs ${YELLOW}Ubuntu 16.04${RED} to run properly. Terminating setup...${NC}"
        echo

        exit 1
    fi
}

function prepare_system() {
    echo
    echo -e "${CYAN}* Preparing to setup ${GREEN}${COIN_NAME}${NC} ${CYAN}Masternode...${NC}"; sleep 0.5s

    export DEBIAN_FRONTEND=noninteractive
    aptget_parameters='--quiet -y'

    echo -e "    ${GREEN}> ${YELLOW}add Bitcoin PPA repository${NC}"; sleep 0.5s

    apt-get ${aptget_parameters} install software-properties-common &>/dev/null
    add-apt-repository -y ppa:bitcoin/bitcoin &>/dev/null

    echo -e "    ${GREEN}> ${YELLOW}apt-get update${NC}"; sleep 0.5s

    dpkg --clear-avail &>/dev/null
    apt-get ${aptget_parameters} update &>/dev/null
    apt-get --quiet -f install &>/dev/null
    dpkg --configure -a &>/dev/null

    echo -e "    ${GREEN}> ${YELLOW}apt-get upgrade${NC}"; sleep 0.5s

    # intentional duplicate to avoid some errors
    apt-get ${aptget_parameters} update &>/dev/null
    apt-get ${aptget_parameters} upgrade &>/dev/null

    echo -e "    ${GREEN}> ${YELLOW}install necessary packages${NC}"; sleep 0.5s

    package_list="build-essential libtool curl autotools-dev automake pkg-config libssl-dev libevent-dev bsdmainutils python3 ufw libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev libboost-dev libevent-1.4-2 libdb4.8-dev libdb4.8++-dev autoconf libboost-all-dev libqt5gui5 libqt5core5a libqt5dbus5 qttools5-dev qttools5-dev-tools libprotobuf-dev protobuf-compiler libqrencode-dev libminiupnpc-dev git multitail vim unzip unrar htop ntpdate"

    apt-get ${aptget_parameters} install ${package_list} &>/dev/null || apt-get ${aptget_parameters} install ${package_list} &>/dev/null

    echo -e "    ${GREEN}> ${YELLOW}synchronize time${NC}"; sleep 0.5s

    ntpdate -s time.nist.gov
}

function create_swap() {
    # ideal amount of RAM
    IDEAL_RAM="1900"

    # swap file path
    SWAPFILE="/xbi_swap"

    echo
    echo -e "${CYAN}* Checking current total ${PURPLE}RAM${CYAN} and ${PURPLE}Swap${CYAN} sizes...${NC}"; sleep 0.5s

    RAM_SIZE=`free -m | grep -i "mem:" | awk '{print $2}'`
	SWAP_SIZE=`swapon -se | grep -vi 'size' | awk '{s+=$3}END{print s}'`

	if [ -z "${SWAP_SIZE}" ]; then
		SWAP_SIZE="0"
	fi

	SWAP_SIZE=$(( ${SWAP_SIZE} / 1024 ))

	NECESSARY_SWAP_SIZE="$((${IDEAL_RAM}-(${RAM_SIZE}+${SWAP_SIZE})))"

	if [ "${NECESSARY_SWAP_SIZE}" -lt 100 ]; then
		NECESSARY_SWAP_SIZE="0"
	fi

    echo -e "    ${GREEN}> ${YELLOW}You have ${PURPLE}${RAM_SIZE} MB${YELLOW} of total RAM.${NC}"; sleep 0.5s
    echo -e "    ${GREEN}> ${YELLOW}You have ${PURPLE}${SWAP_SIZE} MB${YELLOW} of total swap file/partition."; sleep 0.5s

	if [ "${NECESSARY_SWAP_SIZE}" -gt 0 ]; then
		echo -e "    ${GREEN}> ${YELLOW}Creating a ${CYAN}${NECESSARY_SWAP_SIZE} MB${YELLOW} swap file..."; sleep 0.5s

		swapoff ${SWAPFILE} &>/dev/null
		rm -rf ${SWAPFILE} &>/dev/null

		fallocate -l ${NECESSARY_SWAP_SIZE}M ${SWAPFILE} &>/dev/null
		chmod 600 ${SWAPFILE} &>/dev/null
		mkswap ${SWAPFILE} &>/dev/null
		swapon ${SWAPFILE} &>/dev/null

        # remove old line for old swap file
		echo "$(grep -v ${SWAPFILE} /etc/fstab)" > /etc/fstab

        # add new line for new swap file
		echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
	else
		echo -e "    ${GREEN}> Skipping swap file creation (you have enough RAM/Swap)...${NC}"; sleep 0.5s

		return 0
	fi
}

function final_report() {
    clear

    echo
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${GREEN}XBI ${CYAN}Masternode Setup Script by ${GREEN}Dias${NC}"
    echo -e "${YELLOW}--> XBI      : ${PURPLE}BPdwk8QC24TULM3CYkp7MJJr8gLe8S7U8o${NC}"
    echo -e "${YELLOW}--> Vultr ref: ${PURPLE}https://www.vultr.com/?ref=7893667${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${GREEN}${COIN_NAME} ${CYAN}Masternode is up and running, listening on port ${GREEN}${COIN_PORT}${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${CYAN}Configuration file: ${YELLOW}${CONFIG_FOLDER}/${CONFIG_FILE}${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${CYAN}Masternode commands:${NC}"
    echo -e "${CYAN}  Start masternode:              ${YELLOW}systemctl start ${COIN_NAME}.service${NC}"
    echo -e "${CYAN}  Stop masternode:               ${YELLOW}systemctl stop ${COIN_NAME}.service${NC}"
    echo -e "${CYAN}  Check masternode status:       ${YELLOW}xbi-cli masternode status${NC}"
    echo -e "${CYAN}  Check synchronization status:  ${YELLOW}xbi-cli getinfo${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo -e "${RED}Copy/paste these to your desktop wallet configuration:${NC}"
    echo -e "${CYAN}VPS IP: ${GREEN}${NODEIP}:${COIN_PORT}${NC}"
    echo -e "${CYAN}Masternode Private Key: ${GREEN}${COINKEY}${NC}"
    echo -e "${BLUE}=============================================================================${NC}"
    echo
}

TMP_FOLDER="/var/tmp/xbi"
CONFIG_FILE="xbi.conf"
CONFIG_FOLDER="/root/.XBI"
COIN_DAEMON="xbid"
COIN_CLI="xbi-cli"
COIN_PATH="/usr/local/bin/"
COIN_REPO="https://github.com/XBIncognito/xbi-4.3.2.1/releases/download/4.3.2.1/"
COIN_ZIP="xbi-linux-daemon-4.3.2.1.zip"
COIN_LINK="${COIN_REPO}${COIN_ZIP}"
COIN_NAME="XBI"
COIN_PORT="7339"
RPC_PORT="6259"
RPC_OLD_PORT="6250"
COIN_OLD_PORT="7332"

# color codes for echo commands
NC=$'\e[0m'
RED=$'\e[31;01m'
GREEN=$'\e[32;01m'
YELLOW=$'\e[33;01m'
BLUE=$'\e[34;01m'
PURPLE=$'\e[35;01m'
CYAN=$'\e[36;01m'

cd ${HOME}
clear

##### Main #####

checks
purgeOldInstallation
create_swap
prepare_system
download_node
create_config
enable_firewall
configure_systemd
final_report

exit 0