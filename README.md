# Network Emulator

This repository contains tools for emulation of network imperfections using Linux. Emulation works on IP packets (Layer 3) and is intended to be run on a host acting as a router between two or more other hosts.

It consists of two parts:
- The routing to redirect packets through the emulator
- The actual emulator that shapes the incoming traffic

For separation of concerns and privileges, these parts are separate programs. Routing needs elevated privileges while the emulator does not.


## Routing

The Bash script [routing.sh](routing.sh) uses [`socat`](http://www.dest-unreach.org/socat/) and Linux [`iproute2`](https://en.wikipedia.org/wiki/Iproute2) commands and to create a temporary TUN device, redirect IP traffic to it, and send these IP packets wrapped in UDP to the emulator. Packets returned from the emulator are injected back into the network stack to reach their original target.

### Network Topology

An applicable network topology where Alice and Bob are connected via a router in the middle may look as follows:

```
                             Router
                       +----------------+
                       |    Emulator    |
                       |   ↑↓ UDP/IP    |
 Alice                 |  emueth0eth1   |                  Bob
+-----+                |    ↑↓ IP ↑↓    |                +-----+
|     O--- Ethernet ---O  eth0    eth1  O--- Ethernet ---O     |
+-----+                +----------------+                +-----+
```

The script will create a TUN device `emueth0eth1` and route any packets received from `eth0` or `eth1` through that device, where the packets are wrapped in another UDP/IP packet and sent to a local port. Routing is set up conditionally to prevent a loop, i.e., packets traveling the opposite way from the TUN device to `eth0` or `eth1` do not get redirected again but can leave the system and reach the intended target.

### Usage

Running the script without arguments yields the following usage info:

```
Usage:   ./routing.sh INTERFACE IN_PORT OUT_PORT
         INTERFACES  Redirect packets coming in from these comma-separated network interfaces.
         IN_PORT     Local UDP port where incoming IP packets are sent to.
         OUT_PORT    Local UDP port where outgoing IP packets must be sent to.
Example: ./routing.sh eth0,eth1 1111 2222
```

### Example

Assuming the emulator listens for packets on local UDP port 1111 and returns packets to port 2222, invoking the routing script would look similar to the following:

```
$ sudo ./routing.sh eth0,eth1 1111 2222
IPv4 forwarding is enabled.
Creating TUN device emueth0eth1 for local packet manipulation...
socat running in background with PID 738321.
IP in UDP/IP is passed to local port 1111 and expected back on local port 2222.
Adding rule to handle packets from eth0...
Adding rule to handle packets from eth1...
Adding route to pass packets to emueth0eth1...
Ready. Running until SIGINT (Ctrl+C) is received.
```

Let's say `eth0` has the subnet `10.0.1.0/24` assigned and `eth1` has subnet `10.0.2.0/24`. Alice is reachable by address `10.0.1.10` and Bob by `10.0.2.10`. The router in the middle uses addresses `10.0.1.1` and `10.0.2.1`. If Alice and Bob have set the router's addresses as their default gateway, a packet from Alice to Bob or from Bob to Alice will end up at the router. Now, if Alice pings Bob, her ICMP packets would arrive at the router on `eth0` and get passed through the TUN device to local UDP port 1111. If `socat` receives Alice's packets back on UDP port 2222, they will finally leave the router through `eth1` and reach Bob. The reverse path from Bob to Alice works the same way; packets come in on `eth1`, reach the emulator on port 1111, should be returned to port 2222 and leave through `eth0`.

Pressing Ctrl+C will cause the script to undo the routing configuration and exit.

### Internals

The script performs some environment and parameter checks at the beginning to avoid errors along the way. It will:

1. check if it is run as root (future versions may use Linux capabilities instead);
2. check that `socat` is available (or more precisely, can be found on $PATH);
3. check if IPv4 forwarding is enabled (which will already be the case on machines set up as a router) and enable it if required;
4. check that at least one network interface name to redirect traffic from is set, and that the specified interfaces do exist; and
5. check that ports for incoming and outgoing packets are set.

The name for the temporary TUN device is constructed from the inbound interface names (and truncated to 15 characters), providing some degree of uniqueness per interface configuration. Yet, currently, it is not possible to run multiple instances of the routing script concurrently because of a hard-coded routing table ID. This might be addressed in future versions.

On exit, the script will reverse any routing changes made. However, if that fails due to an error in between, a blank state can always be reached by rebooting as the changes made by this script are not persistent.


## Emulator

The emulator is meant to be run in a separate terminal after the routing has been set up. As of now, fixed per-packet delays, limited bandwidth and packet errors can be emulated. Note that the currently included Python3 script [emulator.py](emulator.py) serves as a minimal application example and placeholder for more sophisticated model-based emulation. Since asynchronous I/O using `asyncio` is a pain in Python and voids the purpose of providing an easy-to-understand example, the script reads and writes packets synchronously. Beware that this effectively creates a half-duplex first-in first-out link where incoming packets are only processed once the previous has left the emulator. Not being able to read a packet right when it arrives adds load-dependent delays (jitter); this will limit suitability for emulating low-latency connections. Improved asynchronous implementations may be included in the future.

### Usage

Running the emulator script without arguments yields the following usage info:

```
Usage:   ./emulator.py in=value out=value [key=value ...]
         in     Local UDP port to receive packets from (mandatory)
         out    Local UDP port to send packets to (mandatory)
         speed  Bandwidth in bit per second > 0 (default: inf)
         delay  Additional delay in seconds >= 0 (default: 0.0)
         per    Packet error rate 0...1 (default: 0.0)
Example: ./emulator.py in=1111 out=2222 speed=56e3 delay=0.05

```

The UDP ports should of course match those specified for [routing.sh](routing.sh). The parameters speed, delay and per are parsed as float. If speed is configured, a total bandwidth budget is enforced by delaying packets according to their size. This limit counts traffic in any direction and includes any protocol overhead starting with IP. Bitrates can be specified using exponential notation, e.g., `56e3` for 56 kbit/s. Packet errors are realized by randomly dropping (i.e., not forwarding) packets; the desired rate is met by comparing a random number uniformly distributed between 0 and 1 to the configured value.

### Example

Given the following baseline ICMP ping statistics between to virtual machines:

```
100 packets transmitted, 100 received, 0% packet loss, time 19890ms
rtt min/avg/max/mdev = 0.444/1.087/1.672/0.176 ms
```

...the following invocation of the emulator with 50 milliseconds delay and a packet error rate of 0.3:

```
$ ./emulator.py in=1111 out=2222 delay=0.05 per=0.3
[0.000] Listening on port 1111
[2.113] Received 84 bytes
[2.113] Waiting 0.050 seconds
[2.163] Forwarding packet
[2.164] Received 84 bytes
[2.164] Waiting 0.050 seconds
[2.214] Forwarding packet
```

...produces these statistics:

```
100 packets transmitted, 47 received, 53% packet loss, time 20005ms
rtt min/avg/max/mdev = 101.249/102.601/103.261/0.381 ms
```

Note that ICMP ping requests involve a round trip between two machines and pass the emulator twice. This is why the observed round trip time is about twice the configured emulator delay, and the observed loss is about equal to `1-(1-per)^2` since errors in either direction occur independently.

### Caveats

Bandwidth limits can be tested using [`iperf`](https://iperf.fr/), for example. Note that the configured bandwidth limit represents the sum bitrate of traffic in either direction. In other words, the bandwidth budget is split among all hosts communicating through the emulator. Considering two hosts, the actual achieved bitrate at the application level (which is what `iperf` reports) can be lower than the configured limit by about 10% mainly because of the protocol overhead (also remember that TCP sends ACKs in the opposite direction), but also because any other unwanted execution delays in the emulator are not being compensated.

Further note that if a delay is configured, this will affect the achievable bandwidth (even if no bandwidth limit is set) because the emulator blocks incoming packets if another packet is waiting to be forwarded.
