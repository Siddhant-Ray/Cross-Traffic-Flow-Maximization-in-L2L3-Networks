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
exit
EOM

###############################################################################
# You can also use this file to use unix commands in the router container.
# For example, you could use tc here.
#
# Write your configuration below. This script will be executed on the container.
###############################################################################

tc qdisc add dev port_R4 handle 1: root htb default 14
tc class add dev port_R4 parent 1: classid 1:1 htb rate 12Mbit ceil 12Mbit burst 15k


# high priority gold  TOS 128
sudo ip netns exec router tc class add dev port_R1 parent 1:1 classid 1:10 htb rate 1Mbit ceil 10Mbit prio 1 burst 15k cburst 15K
sudo ip netns exec router tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 3 0xff match ip dsfield 128 0xff flowid 1:10


# medium  priority silver TOS 64
sudo ip netns exec router tc class add dev port_R1 parent 1:1 classid 1:20 htb rate 4Mbit ceil 10Mbit prio 2 burst 15k cburst 15K
sudo ip netns exec router tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 1 0xff match ip dsfield 64 0xff flowid 1:20


#low  priority bronze  TOS 32
sudo ip netns exec router tc class add dev port_R1 parent 1:1 classid 1:30 htb rate 12Mbit ceil 12Mbit prio 3 burst 15k cburst 15K
sudo ip netns exec router tc filter add dev port_R1 parent 1: protocol ip prio 1 u32 match ip protocol 1 0xff match ip dsfield 32  0xff flowid 1:30

# Last qdisc
sudo ip netns exec router tc qdisc add dev port_R1 parent 1:10 handle 10: sfq perturb 10 limit 64 quantum 10000
sudo ip netns exec router tc qdisc add dev port_R1 parent 1:20 handle 20: sfq perturb 10 limit 64 quantum 10000
sudo ip netns exec router tc qdisc add dev port_R1 parent 1:30 handle 30: sfq perturb 10 limit 64 quantum 10000

