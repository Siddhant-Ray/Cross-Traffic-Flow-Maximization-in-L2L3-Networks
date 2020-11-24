#!/bin/bash

ip link set ssh down

ip link set S1router down
ip link set S1router name S1switch
ip link set S1switch up

ip address add 1.0.0.1/24 dev S1switch
ip link set S1switch address 00:00:01:00:00:01
ip route add default via 1.0.0.2

# disable offloading
ethtool -K S1switch rx off tx off  sg off &> /dev/null
