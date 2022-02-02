#!/bin/bash

# (C) 2022 Nick Schwarzenberg
# nick.schwarzenberg@tu-dresden.de
#
# Use iproute2 commands and socat to pass IP packets as UDP payloads through the emulator.


## Parameter check ##

print_usage()
{
	echo "Usage:   $0 INTERFACE IN_PORT OUT_PORT"
	echo "         INTERFACE  Redirect packets coming in from this network interface."
	echo "         IN_PORT    Local UDP port where incoming IP packets are sent to."
	echo "         OUT_PORT   Local UDP port where outgoing IP packets must be sent to."
	echo "Example: $0 eth0 1111 2222"
}

# check if run as root
EFFECTIVE_USER_ID=$(id -u)
if [[ $EFFECTIVE_USER_ID != "0" ]]; then
	echo "This script must be run as root."
	exit 1
fi

# check that socat is available
SOCAT_PATH=$(which socat)
if [[ $SOCAT_PATH == "" ]]; then
	echo "socat not found, probably not installed?"
	exit 1
fi

# check that incoming device name is set
SOURCE_INTERFACE=$1
if [[ "$SOURCE_INTERFACE" == "" ]]; then
	print_usage
	exit 1
else
	ip link show $SOURCE_INTERFACE 2>&1 >/dev/null
	if [[ $? != 0 ]]; then
		echo "$SOURCE_INTERFACE does not seem to be a valid network device."
		echo "Available devices:"
		ip link show
		exit 1
	fi
fi

# check that input port is set
IN_PORT=$2
if [[ "$IN_PORT" == "" ]]; then
	print_usage
	exit 1
fi

# check that output port is set
OUT_PORT=$3
if [[ "$OUT_PORT" == "" ]]; then
	print_usage
	exit 1
fi


## Actual routing setup ##

# create TUN device
TUN_PREFIX="emu"
TUN_DEVICE="$TUN_PREFIX$SOURCE_INTERFACE"
echo "Creating TUN device $TUN_DEVICE for local packet manipulation..."
socat tun,tun-name=$TUN_DEVICE,iff-up,iff-no-pi udp4-sendto:127.0.0.1:$IN_PORT,bind=127.0.0.1,sourceport=$OUT_PORT &
SOCAT_PID=$!
echo "socat running in background with PID $SOCAT_PID."
echo "IP in UDP is passed to local port $IN_PORT and expected back on local port $OUT_PORT."

# create policy route for packets coming in from the specified interface
TABLE_ID=123
echo "Adding route to pass packets from $SOURCE_INTERFACE to $TUN_DEVICE..."
ip rule add iif $SOURCE_INTERFACE lookup $TABLE_ID
ip route add default dev $TUN_DEVICE table $TABLE_ID

# handle SIGINT signal (e.g., from pressing Ctrl+C)
trap handle_sigint SIGINT
handle_sigint()
{
	echo ""
	echo "Caught SIGINT, cleaning up..."
	kill $SOCAT_PID
	ip rule del iif $SOURCE_INTERFACE lookup $TABLE_ID
	echo "Done."
	exit 0
}

echo "Ready. Running until SIGINT (Ctrl+C) is received."
while true; do sleep 1; done
