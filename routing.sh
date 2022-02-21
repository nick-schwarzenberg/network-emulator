#!/bin/bash

# (C) 2022 Nick Schwarzenberg
# nick.schwarzenberg@tu-dresden.de
#
# Use iproute2 commands and socat to pass IP packets as UDP payloads through the emulator.


## Parameter check ##

print_usage()
{
	echo "Usage:   $0 INTERFACE IN_PORT OUT_PORT"
	echo "         INTERFACES  Redirect packets coming in from these comma-separated network interfaces."
	echo "         IN_PORT     Local UDP port where incoming IP packets are sent to."
	echo "         OUT_PORT    Local UDP port where outgoing IP packets must be sent to."
	echo "Example: $0 eth0,eth1 1111 2222"
}

# check if run as root
EFFECTIVE_USER_ID=$(id -u)
if [[ $EFFECTIVE_USER_ID != "0" ]]; then
	if [[ $1 == "" ]]; then  # no other parameters given?
		print_usage  # don't require root to print usage info
	else
		echo "This script must be run as root."
	fi
	exit 1
fi

# check that socat is available
SOCAT_PATH=$(which socat)
if [[ $SOCAT_PATH == "" ]]; then
	echo "socat not found, probably not installed?"
	exit 1
fi

# check that inbound interface names are set and valid
INTERFACES=$1
if [[ $INTERFACES == "" ]]; then
	print_usage
	exit 1
fi
INTERFACES_ARRAY=(${INTERFACES//,/ })  # replace commas by spaces and interpret as array
for INTERFACE in ${INTERFACES_ARRAY[@]}; do
	ip link show $INTERFACE 2>&1 >/dev/null
	if [[ $? != 0 ]]; then
		echo "$INTERFACE does not seem to be a valid network interface."
		echo "Available interfaces:"
		ip link show
		exit 1
	fi
done

# check that input port is set
IN_PORT=$2
if [[ $IN_PORT == "" ]]; then
	print_usage
	exit 1
fi

# check that output port is set
OUT_PORT=$3
if [[ $OUT_PORT == "" ]]; then
	print_usage
	exit 1
fi

# ensure that IP forwarding is enabled
IP_FORWARD_ORIGINAL=$(sysctl --values net.ipv4.ip_forward)
IP_FORWARD_CHANGED=0
if [[ $IP_FORWARD_ORIGINAL != "1" ]]; then
	echo "Enabling IPv4 forwarding..."
	sysctl -w net.ipv4.ip_forward=1 >/dev/null
	IP_FORWARD_CHANGED=1
else
	echo "IPv4 forwarding is enabled."
fi


## Actual routing setup ##

# create TUN device
TUN_PREFIX="emu"
TUN_DEVICE="$TUN_PREFIX${INTERFACES//,/}"  # make joint name, removing commas from interface list
TUN_DEVICE="${TUN_DEVICE:0:14}"  # truncate to 15 characters (IFNAMSIZ is 16 in Linux)
echo "Creating TUN device $TUN_DEVICE for local packet manipulation..."
socat tun,tun-name=$TUN_DEVICE,iff-up,iff-no-pi udp4-sendto:127.0.0.1:$IN_PORT,bind=127.0.0.1,sourceport=$OUT_PORT &
SOCAT_PID=$!
echo "socat running in background with PID $SOCAT_PID."
echo "IP in UDP/IP is passed to local port $IN_PORT and expected back on local port $OUT_PORT."

# create policy route for packets coming in from the specified interfaces
TABLE_ID=123
for INTERFACE in ${INTERFACES_ARRAY[@]}; do
	echo "Adding rule to handle packets from $INTERFACE..."
	ip rule add iif $INTERFACE lookup $TABLE_ID
done
echo "Adding route to pass packets to $TUN_DEVICE..."
ip route add default dev $TUN_DEVICE table $TABLE_ID

# handle SIGINT signal (e.g., from pressing Ctrl+C)
trap handle_sigint SIGINT
handle_sigint()
{
	echo "Caught SIGINT, cleaning up..."
	kill $SOCAT_PID  # this removes $TUN_DEVICE, automatically removing the default route through it
	for INTERFACE in ${INTERFACES_ARRAY[@]}; do
		ip rule del iif $INTERFACE lookup $TABLE_ID
	done
	if [[ $IP_FORWARD_CHANGED == 1 ]]; then
		sysctl -w net.ipv4.ip_forward=$IP_FORWARD_ORIGINAL >/dev/null
	fi
	echo "Done."
	exit 0
}

echo "Ready. Running until SIGINT (Ctrl+C) is received."
while true; do read -n 1 -r -s key; done
