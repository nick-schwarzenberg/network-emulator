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
from math import inf

start_time = monotonic()


## Configuration ##

config = {
    'in': None,
    'out': None,
    'speed': inf,
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
    print("         speed  Bandwidth in bit per second > 0 (default: inf)")
    print("         delay  Additional delay in seconds >= 0 (default: 0.0)")
    print("         per    Packet error rate 0...1 (default: 0.0)")
    print("Example: "+sys.argv[0]+" in=1111 out=2222 speed=56e3 delay=0.05")

# ensure mandatory configuration options are set
if config['in'] == None or config['out'] == None:
    printUsage()
    exit(1)

# enforce parameter types and check bounds
try:
    config['in'] = int(config['in'])
    config['out'] = int(config['out'])
except ValueError:
    print("UDP ports must be integer values")
    exit(1)
try:
    config['speed'] = float(config['speed'])
    config['delay'] = float(config['delay'])
    config['per'] = float(config['per'])
except ValueError:
    print("speed, delay and per must be parsable as float")
    exit(1)
if not config['speed'] > 0:
    print("speed must be greater than zero")
    exit(1)
if not config['delay'] >= 0:
    print("delay must be greater or equal than zero")
    exit(1)
if not (config['per'] >= 0 and config['per'] <= 1):
    print("per must be between 0 and 1 (inclusive)")
    exit(1)

def printWithTime(message):
    print("[%.3f]" % (monotonic()-start_time), message)


## Emulation / Manipulation ##

def handlePacket( data ):

    printWithTime("Received packet of %d Bytes" % len(data))

    delay = config['delay']
    if config['speed'] < inf:
        # speed limit = delay depending on payload size
        delay = delay + len(data)*8 / config['speed']
    if delay > 0:
        printWithTime("Waiting %.3f seconds" % delay)
        sleep(delay)

    if config['per'] > 0:
        if random() >= config['per']:
            printWithTime("Forwarding packet")
            return data
        else:
            printWithTime("Dropping packet")
            return None
    else:
        return data


## Main Loop with UDP Payload Interface ##

# create UDP listening socket
udp = socket(AF_INET, SOCK_DGRAM)
udp.bind(('127.0.0.1', config['in']))
printWithTime("Listening on port %d" % config['in'])

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
            udp.sendto(outgoingData, ('127.0.0.1', config['out']))
