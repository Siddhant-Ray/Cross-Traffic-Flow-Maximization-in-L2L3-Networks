#!/bin/bash

set -eu  # Exit on error (-e), treat unset variables as errors (-u).

############################################################################### 
# You can use this file to use unix commands in the switch container.
# For example, you could use tc here.
#
# Write your configuration below. This script will be executed on the container.
###############################################################################

# R1 
## add back the mtu field? 
tc qdisc add dev port_R1 handle 1: root htb default 14
tc class add dev port_R1 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k

    ## classes 

    # gold
    tc class add dev port_R1 parent 1:1 classid 1:11 htb rate 1Mbit ceil 4Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_R1 parent 1:1 classid 1:12 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_R1 parent 1:1 classid 1:13 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_R1 parent 1:1 classid 1:14 htb rate 450Kbit ceil 4Mbit burst 15k cburst 15K prio 4

    ## filters

    # gold
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_R1 parent 1:11 handle 10: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R1 parent 1:12 handle 20: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R1 parent 1:13 handle 30: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R1 parent 1:14 handle 40: sfq perturb 10 limit 64 quantum 10000






# R2
## add back the mtu field? 
tc qdisc add dev port_R2 handle 1: root htb default 14
tc class add dev port_R2 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k

    ## classes

    # gold
    tc class add dev port_R2 parent 1:1 classid 1:11 htb rate 1Mbit ceil 4Mbit burst 15k cburst 15K prio 1 

    #silver
    tc class add dev port_R2 parent 1:1 classid 1:12 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_R2 parent 1:1 classid 1:13 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_R2 parent 1:1 classid 1:14 htb rate 450Kbit ceil 4Mbit burst 15k cburst 15K prio 4

    ## filters 

    # gold
    tc filter add dev port_R2 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11

    # silver
    tc filter add dev port_R2 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12

    # bronze
    tc filter add dev port_R2 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_R2 parent 1:11 handle 10: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R2 parent 1:12 handle 20: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R2 parent 1:13 handle 30: sfq perturb 10 limit 64 quantum 10000
    tc qdisc add dev port_R2 parent 1:14 handle 40: sfq perturb 10 limit 64 quantum 10000