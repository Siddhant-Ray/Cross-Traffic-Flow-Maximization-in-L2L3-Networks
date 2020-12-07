#!/bin/bash

set -eu  # Exit on error (-e), treat unset variables as errors (-u).

###############################################################################
# Write your router configuration commands below.
# Every line between the two "EOM" tokens will be redirected (entered) into the
# router vtysh, just as if you'd type them line after line.
#
# If you have not seen this syntax for multiline strings in bash before:
# It is called "heredoc" and you can find a short tutorial here:
# https://linuxhint.com/bash-heredoc-tutorial/
###############################################################################

vtysh << EOM
conf t
bfd
peer 2.0.0.1 interface port_S2
receive-interval 50
transmit-interval 50
exit
peer 3.0.0.1 interface port_S3
receive-interval 50
transmit-interval 50
exit
peer 4.0.0.1 interface port_S4
receive-interval 50
transmit-interval 50
exit
peer 10.1.0.1 interface port_R1
receive-interval 50
transmit-interval 50
exit
peer 10.5.0.2 interface port_R3
receive-interval 50
transmit-interval 50
exit
peer 10.4.0.2 interface port_R4
receive-interval 50
transmit-interval 50
exit
exit

router ospf 10
interface port_R1
ip ospf cost 5
ip ospf bfd
exit
interface port_R3
ip ospf cost 5
ip ospf bfd
exit
interface port_R4
ip ospf cost 10
ip ospf bfd
exit
interface port_S2
exit
interface port_S3
exit
interface port_S4
exit



exit


exit
EOM

###############################################################################
# You can also use this file to use unix commands in the router container.
# For example, you could use tc here.
#
# Write your configuration below. This script will be executed on the container.
###############################################################################

# R4 
tc qdisc add dev port_R4 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_R4 parent 1: classid 1:1 htb rate 6Mbit ceil 6Mbit burst 15k cburst 15k

    # gold
    tc class add dev port_R4 parent 1:1 classid 1:11 htb rate 5.9Mbit ceil 6Mbit burst 15k cburst 15K prio 1 
    tc filter add dev port_R4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11

    #silver
    tc class add dev port_R4 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 2
    tc filter add dev port_R4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12

    # bronze
    tc class add dev port_R4 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 3
    tc filter add dev port_R4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    # other
    tc class add dev port_R4 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 6Mbit burst 15k cburst 15K prio 4

    tc qdisc add dev port_R4 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R4 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R4 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R4 parent 1:14 handle 40: sfq limit 16256 quantum 1500

# R1 
tc qdisc add dev port_R1 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_R1 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15k

    ## classes 

    # gold
    tc class add dev port_R1 parent 1:1 classid 1:11 htb rate 3.9Mbit ceil 4Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_R1 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_R1 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_R1 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 4Mbit burst 15k cburst 15K prio 4

    ## filters

    # gold
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_R1 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R1 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R1 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R1 parent 1:14 handle 40: sfq limit 16256 quantum 1500



# R3 
tc qdisc add dev port_R3 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_R3 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15k

    ## classes 

    # gold
    tc class add dev port_R3 parent 1:1 classid 1:11 htb rate 3.9Mbit ceil 4Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_R3 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_R3 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_R3 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 4Mbit burst 15k cburst 15K prio 4

    ## filters

    # gold
    tc filter add dev port_R3 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_R3 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_R3 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_R3 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R3 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R3 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_R3 parent 1:14 handle 40: sfq limit 16256 quantum 1500


# S3
tc qdisc add dev port_S3 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_S3 parent 1: classid 1:1 htb rate 6Mbit ceil 6Mbit burst 15k cburst 15k

    # gold
    tc class add dev port_S3 parent 1:1 classid 1:11 htb rate 5.9Mbit ceil 6Mbit burst 15k cburst 15K prio 1 
    tc filter add dev port_S3 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11

    #silver
    tc class add dev port_S3 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 2
    tc filter add dev port_S3 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12

    # bronze
    tc class add dev port_S3 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 6Mbit burst 15k cburst 15K prio 3
    tc filter add dev port_S3 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    # other
    tc class add dev port_S3 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 6Mbit burst 15k cburst 15K prio 4

    tc qdisc add dev port_S3 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S3 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S3 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S3 parent 1:14 handle 40: sfq limit 16256 quantum 1500


# S2
tc qdisc add dev port_S2 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_S2 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15k

    ## classes 

    # gold
    tc class add dev port_S2 parent 1:1 classid 1:11 htb rate 3.9Mbit ceil 4Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_S2 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_S2 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_S2 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 4Mbit burst 15k cburst 15K prio 4

    ## filters

    # gold
    tc filter add dev port_S2 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_S2 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_S2 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_S2 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S2 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S2 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S2 parent 1:14 handle 40: sfq limit 16256 quantum 1500




# S4
tc qdisc add dev port_S4 handle 1: root htb default 14 direct_qlen 1000000
tc class add dev port_S4 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15k

    ## classes 

    # gold
    tc class add dev port_S4 parent 1:1 classid 1:11 htb rate 3.9Mbit ceil 4Mbit burst 15k cburst 15K prio 1 

    # silver
    tc class add dev port_S4 parent 1:1 classid 1:12 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 2

    # bronze
    tc class add dev port_S4 parent 1:1 classid 1:13 htb rate 0.04Mbit ceil 4Mbit burst 15k cburst 15K prio 3

    # other
    tc class add dev port_S4 parent 1:1 classid 1:14 htb rate 0.02Mbit ceil 4Mbit burst 15k cburst 15K prio 4

    ## filters

    # gold
    tc filter add dev port_S4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 128 0xff flowid 1:11
    
    # silver
    tc filter add dev port_S4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 64 0xff flowid 1:12
    
    # bronze
    tc filter add dev port_S4 parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip tos 32 0xff flowid 1:13

    ## leaves

    tc qdisc add dev port_S4 parent 1:11 handle 10: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S4 parent 1:12 handle 20: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S4 parent 1:13 handle 30: sfq limit 16256 quantum 1500
    tc qdisc add dev port_S4 parent 1:14 handle 40: sfq limit 16256 quantum 1500
