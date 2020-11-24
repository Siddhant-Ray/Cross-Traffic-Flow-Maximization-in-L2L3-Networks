#!/bin/bash

ip link set ssh down

ip link set S5router down
ip link set S5router name S5switch
ip link set S5switch up

ip address add 5.0.0.1/24 dev S5switch
ip link set S5switch address 00:00:05:00:00:01
ip route add default via 5.0.0.2

# disable offloading
ethtool -K S5switch rx off tx off sg off &> /dev/null
