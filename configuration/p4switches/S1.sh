#!/bin/bash

set -eu  # Exit on error (-e), treat unset variables as errors (-u).

############################################################################### 
# You can use this file to use unix commands in the switch container.
# For example, you could use tc here.
#
# Write your configuration below. This script will be executed on the container.
###############################################################################

# R1 
tc qdisc add dev port_R1 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_R1 parent 1: classid 1:1 htb rate 6Mbit ceil 6Mbit burst 15k cburst 15k

    ## classes

    # gold
    tc class add dev port_R1 parent 1:1 classid 1:11 htb rate 5.9Mbit ceil 6Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_R1 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_R1 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_R1 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 6Mbit burst 15k cburst 15K prio 4

    ## filters

    # not changing the perturb as chance that we have a collision is quite low and the documentation says
    # perturbing might cause losses.

    # increasing the limit of a single queue to a very high value (although it seems that depth is responsible to
    # to limit the packets per flow and can only be lowered)

    # setting quantum to the MTU which is advised in the documentation 

    # gold
    tc filter add dev port_R1 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_R1 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_R1 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_R1 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R1 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R1 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R1 parent 1:14 handle 40: sfq limit 16256 quantum 1500


# R4 
tc qdisc add dev port_R4 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_R4 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15k

    ## classes 

    # gold
    tc class add dev port_R4 parent 1:1 classid 1:11 htb rate 3.9Mbit ceil 4Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_R4 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_R4 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_R4 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 4Mbit burst 15k cburst 15K prio 4

    ## filters

    # not changing the perturb as chance that we have a collision is quite low and the documentation says
    # perturbing might cause losses.

    # increasing the limit of a single queue to a very high value (although it seems that depth is responsible to
    # to limit the packets per flow and can only be lowered)

    # setting quantum to the MTU which is advised in the documentation 

    # gold
    tc filter add dev port_R4 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_R4 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_R4 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_R4 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R4 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R4 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R4 parent 1:14 handle 40: sfq limit 16256 quantum 1500


# S6 
tc qdisc add dev port_S6 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_S6 parent 1: classid 1:1 htb rate 6Mbit ceil 6Mbit burst 15k cburst 15k

    ## classes

    # gold
    tc class add dev port_S6 parent 1:1 classid 1:11 htb rate 5.9Mbit ceil 6Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_S6 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_S6 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_S6 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 6Mbit burst 15k cburst 15K prio 4

    ## filters

    # not changing the perturb as chance that we have a collision is quite low and the documentation says
    # perturbing might cause losses.

    # increasing the limit of a single queue to a very high value (although it seems that depth is responsible to
    # to limit the packets per flow and can only be lowered)

    # setting quantum to the MTU which is advised in the documentation 

    # gold
    tc filter add dev port_S6 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_S6 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_S6 parent 1: protocol all prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_S6 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S6 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S6 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S6 parent 1:14 handle 40: sfq limit 16256 quantum 1500