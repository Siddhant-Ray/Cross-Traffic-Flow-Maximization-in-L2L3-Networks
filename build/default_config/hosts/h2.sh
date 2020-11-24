#!/bin/bash

ip link set ssh down

ip link set S2router down
ip link set S2router name S2switch
ip link set S2switch up

ip address add 2.0.0.1/24 dev S2switch
ip link set S2switch address 00:00:02:00:00:01
ip route add default via 2.0.0.2

# disable offloading
ethtool -K S2switch rx off tx off sg off &> /dev/null
