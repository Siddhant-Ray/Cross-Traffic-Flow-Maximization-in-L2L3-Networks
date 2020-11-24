#!/bin/bash

ip link set ssh down

vtysh << EOM
conf t
interface lo
ip address 1.151.0.1/32
exit
router ospf
ospf router-id 1.151.0.1
network 1.151.0.1/32 area 0
exit

interface port_R2
ip address 10.1.0.1/24
ip ospf cost 1
exit
router ospf
network 10.1.0.1/24 area 0
exit

interface port_R3
ip address 10.2.0.1/24
ip ospf cost 1
exit
router ospf
network 10.2.0.1/24 area 0
exit

interface port_R4
ip address 10.3.0.1/24
ip ospf cost 1
exit
router ospf
network 10.3.0.1/24 area 0
exit

interface port_S1
ip address 1.0.0.2/24
ip ospf cost 1
exit
router ospf
network 1.0.0.2/24 area 0
exit

interface port_S2
ip address 2.0.0.2/24
ip ospf cost 1
exit
router ospf
network 2.0.0.2/24 area 0
exit

interface port_S6
ip address 6.0.0.3/24
ip ospf cost 1
exit
router ospf
network 6.0.0.3/24 area 0
exit

EOM
