#!/bin/bash

ip link set ssh down

ip link set S6router down
ip link set S6router name S6switch
ip link set S6switch up

ip address add 6.0.0.1/24 dev S6switch
ip link set S6switch address 00:00:06:00:00:01
ip route add default via 6.0.0.2

# disable offloading
ethtool -K S6switch rx off tx off sg off &> /dev/null
