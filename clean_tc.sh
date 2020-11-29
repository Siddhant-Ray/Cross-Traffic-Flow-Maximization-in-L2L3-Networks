#!/usr/bin/env bash

#S1
./cli.sh access s1 tc qdisc del root dev port_R1
./cli.sh access s1 tc qdisc del root dev port_R4
./cli.sh access s1 tc qdisc del root dev port_S6

#S2
./cli.sh access s2 tc qdisc del root dev port_R1
./cli.sh access s2 tc qdisc del root dev port_R2

#S3
./cli.sh access s3 tc qdisc del root dev port_R2
./cli.sh access s3 tc qdisc del root dev port_R3
./cli.sh access s3 tc qdisc del root dev port_S4

#S4
./cli.sh access s4 tc qdisc del root dev port_R2
./cli.sh access s4 tc qdisc del root dev port_S3
./cli.sh access s4 tc qdisc del root dev port_R3

#S5
./cli.sh access s5 tc qdisc del root dev port_R3
./cli.sh access s5 tc qdisc del root dev port_R4

#S6
./cli.sh access s6 tc qdisc del root dev port_R1
./cli.sh access s6 tc qdisc del root dev port_R4
./cli.sh access s6 tc qdisc del root dev port_S1

#R1
./cli.sh access r1 tc qdisc del root dev port_R2
./cli.sh access r1 tc qdisc del root dev port_R3
./cli.sh access r1 tc qdisc del root dev port_R4
./cli.sh access r1 tc qdisc del root dev port_S1
./cli.sh access r1 tc qdisc del root dev port_S2
./cli.sh access r1 tc qdisc del root dev port_S6

#R2
./cli.sh access r2 tc qdisc del root dev port_R1
./cli.sh access r2 tc qdisc del root dev port_R3
./cli.sh access r2 tc qdisc del root dev port_R4
./cli.sh access r2 tc qdisc del root dev port_S2
./cli.sh access r2 tc qdisc del root dev port_S3
./cli.sh access r2 tc qdisc del root dev port_S4

#R3
./cli.sh access r3 tc qdisc del root dev port_R1
./cli.sh access r3 tc qdisc del root dev port_R2
./cli.sh access r3 tc qdisc del root dev port_R4
./cli.sh access r3 tc qdisc del root dev port_S3
./cli.sh access r3 tc qdisc del root dev port_S4
./cli.sh access r3 tc qdisc del root dev port_S5

#R4
./cli.sh access r4 tc qdisc del root dev port_R1
./cli.sh access r4 tc qdisc del root dev port_R2
./cli.sh access r4 tc qdisc del root dev port_R3
./cli.sh access r4 tc qdisc del root dev port_S1
./cli.sh access r4 tc qdisc del root dev port_S5
./cli.sh access r4 tc qdisc del root dev port_S6