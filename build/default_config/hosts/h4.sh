#!/bin/bash

ip link set ssh down

ip link set S4router down
ip link set S4router name S4switch
ip link set S4switch up

ip address add 4.0.0.1/24 dev S4switch
ip link set S4switch address 00:00:04:00:00:01
ip route add default via 4.0.0.2

# disable offloading
ethtool -K S4switch rx off tx off sg off &> /dev/null
