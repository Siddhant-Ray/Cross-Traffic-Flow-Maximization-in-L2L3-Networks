#!/bin/bash

set -eu  # Exit on error (-e), treat unset variables as errors (-u).

############################################################################### 
# You can use this file to use unix commands in the switch container.
# For example, you could use tc here.
#
# Write your configuration below. This script will be executed on the container.
###############################################################################

# R3 
tc qdisc add dev port_R3 handle 1: root htb default 1 direct_qlen 1000000
    tc class add dev port_R3 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K
        # not changing the perturb as chance that we have a collision is quite low and the documentation says
        # perturbing might cause losses.

        # increasing the limit of a single queue to a very high value (although it seems that depth is responsible to
        # to limit the packets per flow and can only be lowered)

        # setting quantum to the MTU which is advised in the documentation 

        tc qdisc add dev port_R3 parent 1:1 handle 10: sfq limit 16256 quantum 1500


# R4 
tc qdisc add dev port_R4 handle 1: root htb default 1 direct_qlen 1000000
    tc class add dev port_R4 parent 1: classid 1:1 htb rate 4Mbit ceil 4Mbit burst 15k cburst 15K
        # not changing the perturb as chance that we have a collision is quite low and the documentation says
        # perturbing might cause losses.

        # increasing the limit of a single queue to a very high value (although it seems that depth is responsible to
        # to limit the packets per flow and can only be lowered)

        # setting quantum to the MTU which is advised in the documentation 

        tc qdisc add dev port_R4 parent 1:1 handle 10: sfq limit 16256 quantum 1500