import os
import sys
import time
import psutil
import argparse
import subprocess as sp

NODE_TO_CONTAINER = {
    "R1" : "1_R1router",
    "R2" : "1_R2router",
    "R3" : "1_R3router",
    "R4" : "1_R4router",
    "S1" : "1_S1router",
    "S2" : "1_S2router",
    "S3" : "1_S3router",
    "S4" : "1_S4router",
    "S5" : "1_S5router",
    "S6" : "1_S6router",
    "h1" : "1_S1host",
    "h2" : "1_S2host",
    "h3" : "1_S3host",
    "h4" : "1_S4host",
    "h5" : "1_S5host",
    "h6" : "1_S6host"
}

LINKS = {
    ('h1', 'S1') : 0,
    ('S1', 'h1') : 0,
    ('h2', 'S2') : 0,
    ('S2', 'h2') : 0,
    ('h3', 'S3') : 0,
    ('S3', 'h3') : 0,
    ('h4', 'S4') : 0,
    ('S4', 'h4') : 0,
    ('h5', 'S5') : 0,
    ('S5', 'h5') : 0,
    ('h6', 'S6') : 0,
    ('S6', 'h6') : 0,
    ('S1', 'R1') : 0,
    ('R1', 'S1') : 0,
    ('S1', 'R4') : 0,
    ('R4', 'S1') : 0,
    ('S2', 'R1') : 0,
    ('R1', 'S2') : 0,
    ('S2', 'R2') : 0,
    ('R2', 'S2') : 0,
    ('S3', 'R2') : 0,
    ('R2', 'S3') : 0,
    ('S3', 'R3') : 0,
    ('R3', 'S3') : 0,
    ('S4', 'R2') : 0,
    ('R2', 'S4') : 0,
    ('S4', 'R3') : 0,
    ('R3', 'S4') : 0,
    ('S5', 'R3') : 0,
    ('R3', 'S5') : 0,
    ('S5', 'R4') : 0,
    ('R4', 'S5') : 0,
    ('S6', 'R1') : 0,
    ('R1', 'S6') : 0,
    ('S6', 'R4') : 0,
    ('R4', 'S6') : 0,
    ('R1', 'R2') : 0,
    ('R2', 'R1') : 0,
    ('R2', 'R3') : 0,
    ('R3', 'R2') : 0,
    ('R3', 'R4') : 0,
    ('R4', 'R3') : 0,
    ('R4', 'R1') : 0,
    ('R1', 'R4') : 0,
    ('R1', 'R3') : 0,
    ('R3', 'R1') : 0,
    ('R2', 'R4') : 0,
    ('R4', 'R2') : 0,
    ('S1', 'S6') : 0,
    ('S6', 'S1') : 0,
    ('S3', 'S4') : 0,
    ('S4', 'S3') : 0
}





topo_string="""
                                     ########################################'
                                     ########## Traffic monitoring ##########'
                                     ########################################'

                    The values are in Mbit/s. We show the bit rate for both directions of a link.



                                                          h2
                                                          |
                                                      ({}/{})
                                                          |
                                                          S2
                                                         /  \.
                                                        /    \.
                                                ({}/{})      ({}/{})
                                                  /                 \.
                                                 /                   \.
 h1------({}/{})------S1------({}/{})------R1------({}/{})------R2------({}/{})------S3------({}/{})------h3
                        |                     /| \                  /  | \                    |
                        |__({}/{})__       / |  \                /   |  \      __({}/{})__|
                        |              \    /  |   \     ({}/{})     |   \   /              |
                        |               \  /   |    \  /               |    \ /               |
                    ({}/{})            \/({}/{}) \             ({}/{}) /            ({}/{})
                        |                /\    |    / \                |    / \               |
                        |               /  \   |   /   \_({}/{})     |   /   \              |
                        |__({}/{})__ /    \  |  /                \   |  /     \ _({}/{})__|
                        |                    \ | /                  \  | /                    |
 h6------({}/{})------S6------({}/{})------R4------({}/{})------R3------({}/{})------S4------({}/{})------h4
                                                 \                   /
                                                  \                 /
                                                 ({}/{})   ({}/{})
                                                         \   /
                                                          \ /
                                                           S5
                                                           |
                                                       ({}/{})
                                                           |
                                                           h5

"""


link_intf = {}
link_traffic = {}

if not os.path.isfile("/home/adv-net/mini_internet_project/platform/groups/link_info.txt"):
    print 'You must build the virtual network before running the monitoring script.'
    sys.exit(0)

with open('/home/adv-net/mini_internet_project/platform/groups/link_info.txt', 'r') as fd:
    for line in fd.readlines():
        linetab = line.rstrip('\n').split(' ')
        node1 = linetab[1]
        node2 = linetab[4]
        send_traffic_intf1 = linetab[3]
        send_traffic_intf2 = linetab[6]

        link_intf[(node1, node2)] = send_traffic_intf2
        link_traffic[(node1, node2)] = []

        link_intf[(node2, node1)] = send_traffic_intf1
        link_traffic[(node2, node1)] = []

def print_traffic():
    tmp = sp.call('clear', shell=True)

    print topo_string.format(\
    LINKS[("h2", "S2")], LINKS[("S2", "h2")], \
    LINKS[("R1", "S2")], LINKS[("S2", "R1")], \
    LINKS[("S2", "R2")], LINKS[("R2", "S2")], \
    LINKS[("h1", "S1")], LINKS[("S1", "h1")], \
    LINKS[("S1", "R1")], LINKS[("R1", "S1")], \
    LINKS[("R1", "R2")], LINKS[("R2", "R1")], \
    LINKS[("R2", "S3")], LINKS[("S3", "R2")], \
    LINKS[("S3", "h3")], LINKS[("h3", "S3")], \
    LINKS[("S1", "R4")], LINKS[("R4", "S1")], \
    LINKS[("R3", "S3")], LINKS[("S3", "R3")], \
    LINKS[("R4", "R2")], LINKS[("R2", "R4")], \
    LINKS[("S1", "S6")], LINKS[("S6", "S1")], \
    LINKS[("R1", "R4")], LINKS[("R4", "R1")], \
    LINKS[("R2", "R3")], LINKS[("R3", "R2")], \
    LINKS[("S3", "S4")], LINKS[("S4", "S3")], \
    LINKS[("R1", "R3")], LINKS[("R3", "R1")], \
    LINKS[("S6", "R1")], LINKS[("R1", "S6")], \
    LINKS[("R2", "S4")], LINKS[("S4", "R2")], \
    LINKS[("h6", "S6")], LINKS[("S6", "h6")], \
    LINKS[("S6", "R4")], LINKS[("R4", "S6")], \
    LINKS[("R4", "R3")], LINKS[("R3", "R4")], \
    LINKS[("R3", "S4")], LINKS[("S4", "R3")], \
    LINKS[("S4", "h4")], LINKS[("h4", "S4")], \
    LINKS[("R4", "S5")], LINKS[("S5", "R4")], \
    LINKS[("S5", "R3")], LINKS[("R3", "S5")], \
    LINKS[("S5", "h5")], LINKS[("h5", "S5")])

i = 0
while True:
    try:
        net_stats = psutil.net_io_counters(pernic=True)

        for (src, dst), intf in link_intf.items():
            link_traffic[(src, dst)].append((time.time(), net_stats[intf].bytes_sent*8))
            if len(link_traffic[(src, dst)]) > 10:
                link_traffic[(src, dst)].pop(0)


        for src, dst in LINKS.keys():
            t = link_traffic[(NODE_TO_CONTAINER[src], NODE_TO_CONTAINER[dst])]

            if len(t) > 1:
                duration = float(t[-1][0] - t[0][0])
                traffic = float(t[-1][1] - t[0][1])
                # print '{} --> {}: {} Mbit/s'.format(src, dst, "{:.1f}".format((traffic/duration)/1000000))
                LINKS[(src, dst)] = "{:.1f}".format((traffic/duration)/1000000) if (traffic/duration)/1000000 < 10 else str(int((traffic/duration)/1000000))+'.'

        time.sleep(0.1)
        if i == 5:
            print_traffic()
            i = 0
        else:
            i += 1
            
    except:
        print("There is no network to monitor!")
        break
