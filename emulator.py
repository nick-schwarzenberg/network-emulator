#!/usr/bin/python3

# (C) 2022 Nick Schwarzenberg
# nick.schwarzenberg@tu-dresden.de
#
# A stupid simple UDP traffic shaper with blocking I/O.
# The latter makes it a half-duplex FIFO with bad jitter.


import sys
from socket import socket, AF_INET, SOCK_DGRAM
from time import sleep, monotonic
from random import random

start_time = monotonic()


## Configuration ##

config = {
    'in': None,
    'out': None,
    'delay': 0.0,
    'per': 0.0,
}


## Command Line Interface ##

# parse command line options
for argument in sys.argv:
    parts = argument.split('=')
    if len(parts) > 1:
        (key, value) = parts
        if key in config:
            config[key] = value

def printUsage():
    print("Usage:   "+sys.argv[0]+" in=value out=value [key=value ...]")
    print("         in     Local UDP port to receive packets from (mandatory)")
    print("         out    Local UDP port to send packets to (mandatory)")
    print("         delay  Forwarding delay in seconds >=0 (default: 0.0)")
    print("         per    Packet error rate 0...1 (default: 0.0)")
    print("Example: "+sys.argv[0]+" in=1111 out=2222 delay=0.1")

# ensure mandatory configuration options are set
if config['in'] == None or config['out'] == None:
    printUsage()
    exit(1)

def printWithTime(message):
    print("[%.3f]" % (monotonic()-start_time), message)


## Emulation / Manipulation ##

def handlePacket( data ):

    printWithTime("Received %d bytes" % len(data))

    delay = float(config['delay'])
    printWithTime("Waiting %.3f seconds" % delay)
    sleep(delay)

    if random() >= float(config['per']):
        printWithTime("Forwarding packet")
        return data
    else:
        printWithTime("Dropping packet")
        return None


## Main Loop with UDP Payload Interface ##

# create UDP listening socket
udp = socket( AF_INET, SOCK_DGRAM )
udp.bind(('127.0.0.1', int(config['in'])))
printWithTime("Listening on port %d" % int(config['in']))

while True:
    data = None
    try:
        # try to receive datagram (blocking)
        incomingData = udp.recv(2048)
    except KeyboardInterrupt:
        printWithTime("Closing socket")
        udp.close()
        exit(0)
    if incomingData:
        outgoingData = handlePacket( incomingData )
        if outgoingData:
            udp.sendto(outgoingData, ('127.0.0.1', int(config['out'])))
