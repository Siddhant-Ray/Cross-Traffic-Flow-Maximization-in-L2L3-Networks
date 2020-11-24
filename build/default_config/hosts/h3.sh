#!/bin/bash

ip link set ssh down

ip link set S3router down
ip link set S3router name S3switch
ip link set S3switch up

ip address add 3.0.0.1/24 dev S3switch
ip link set S3switch address 00:00:03:00:00:01
ip route add default via 3.0.0.2

# disable offloading
ethtool -K S3switch rx off tx off sg off &> /dev/null
