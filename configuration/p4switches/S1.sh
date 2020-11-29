#!/bin/bash

set -eu  # Exit on error (-e), treat unset variables as errors (-u).

############################################################################### 
# You can use this file to use unix commands in the switch container.
# For example, you could use tc here.
#
# Write your configuration below. This script will be executed on the container.
###############################################################################
####  commmands
# tcpdump -ni S1switch
# iperf3 -c 6.0.0.1 -p 5001 -u --length 147
# tc -s -d -p qdisc show dev

# R1 
## add back the mtu field? 
tc qdisc add dev port_R1 handle 1: root htb default 14
tc class add dev port_R1 parent 1: classid 1:1 htb rate 6Mbit ceil 6Mbit burst 15k

    # gold
    tc class add dev port_R1 parent 1:1 classid 1:11 htb rate 1Mbit ceil 6Mbit burst 15k cburst 15K prio 1 
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11

    #silver
    tc class add dev port_R1 parent 1:1 classid 1:12 htb rate 4Mbit ceil 6Mbit burst 15k cburst 15K prio 2
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12

    # bronze
    tc class add dev port_R1 parent 1:1 classid 1:13 htb rate 6Mbit ceil 6Mbit burst 15k cburst 15K prio 3
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    # other
    tc class add dev port_R1 parent 1:1 classid 1:14 htb rate 450Kbit ceil 6Mbit burst 15k cburst 15K prio 4

    tc qdisc add dev port_R1 parent 1:11 handle 10: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R1 parent 1:12 handle 20: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R1 parent 1:13 handle 30: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R1 parent 1:14 handle 40: sfq perturb 10 limit 64 quantum 10000






# R4
## add back the mtu field? 
tc qdisc add dev port_R4 handle 1: root htb default 14
tc class add dev port_R4 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k

    # gold
    tc class add dev port_R4 parent 1:1 classid 1:11 htb rate 1Mbit ceil 4Mbit burst 15k cburst 15K prio 1 
    tc filter add dev port_R4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11

    #silver
    tc class add dev port_R4 parent 1:1 classid 1:12 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K prio 2
    tc filter add dev port_R4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12

    # bronze
    tc class add dev port_R4 parent 1:1 classid 1:13 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K prio 3
    tc filter add dev port_R4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    # other
    tc class add dev port_R4 parent 1:1 classid 1:14 htb rate 450Kbit ceil 4Mbit burst 15k cburst 15K prio 4

    tc qdisc add dev port_R4 parent 1:11 handle 10: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R4 parent 1:12 handle 20: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R4 parent 1:13 handle 30: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R4 parent 1:14 handle 40: sfq perturb 10 limit 64 quantum 10000

# S6
## add back the mtu field? 
tc qdisc add dev port_S6 handle 1: root htb default 14
tc class add dev port_S6 parent 1: classid 1:1 htb rate 6Mbit ceil 6Mbit burst 15k

    # gold
    tc class add dev port_S6 parent 1:1 classid 1:11 htb rate 1Mbit ceil 6Mbit burst 15k cburst 15K prio 1 
    tc filter add dev port_S6 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11

    #silver
    tc class add dev port_S6 parent 1:1 classid 1:12 htb rate 4Mbit ceil 6Mbit burst 15k cburst 15K prio 2
    tc filter add dev port_S6 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12

    # bronze
    tc class add dev port_S6 parent 1:1 classid 1:13 htb rate 6Mbit ceil 6Mbit burst 15k cburst 15K prio 3
    tc filter add dev port_S6 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    # other
    tc class add dev port_S6 parent 1:1 classid 1:14 htb rate 450Kbit ceil 6Mbit burst 15k cburst 15K prio 4

    tc qdisc add dev port_S6 parent 1:11 handle 10: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_S6 parent 1:12 handle 20: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_S6 parent 1:13 handle 30: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_S6 parent 1:14 handle 40: sfq perturb 10 limit 64 quantum 10000