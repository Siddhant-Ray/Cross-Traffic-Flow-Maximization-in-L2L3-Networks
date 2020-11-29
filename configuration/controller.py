"""Implement your controller in this file.

The existing controller already implements L2-forwarding to ensure connectivity.
Use this code as an example to get you started.
You are free to completely change this!

Tip:
For debugging, you can start this file in interactive mode.
This will execute the whole file, but then *keep* the python interpreter open,
allowing you to inspect objects and try out things!

```
$ python2 -i controller.py --topo <path to build/topology.db>
```

The controller will be available as the variable `control`.
"""
# pylint: disable=superfluous-parens,invalid-name

import argparse
import csv

from p4utils.utils.topology import Topology
from p4utils.utils.sswitch_API import SimpleSwitchAPI


class Controller(object):
    """The central controller for your p4 switches."""

    L2_BROADCAST_GROUP_ID = 1

    def __init__(self, topo, traffic=None):
        self.topo = Topology(db=topo)
        if traffic is not None:
            # Parse traffic matrix.
            self.traffic = self._parse_traffic_file(traffic)
        else:
            self.traffic = []

        # Basic initialization. *Do not* change.
        self.controllers = {}
        self._connect_to_switches()
        self._reset_states()

        # Start main loop
        self.main()

    # Controller helpers.
    # ===================

    def _connect_to_switches(self):
        for p4switch in self.topo.get_p4switches():
            print("Connecting to %s" % p4switch)
            thrift_port = self.topo.get_thrift_port(p4switch)
            thrift_ip = self.topo.get_thrift_ip(p4switch)
            self.controllers[p4switch] = SimpleSwitchAPI(
                thrift_port, thrift_ip)

    def _reset_states(self):
        for controller in self.controllers.values():
            controller.reset_state()

    @staticmethod
    def _parse_traffic_file(trafficpath):
        with open(trafficpath, 'rb') as csvfile:
            dialect = csv.Sniffer().sniff(csvfile.read(1024))
            csvfile.seek(0)
            reader = csv.DictReader(csvfile, dialect=dialect)
            return list(reader)

    # Controller methods.
    # ===================

    def main(self):
        """Main controller method."""
        # Initialization of L2 forwarding. Feel free to modify.
        self.create_l2_multicast_group()
        self.add_l2_forwarding_rules()
        
        #Call ECMP route
        self.ECMP_route()
        #do_something()

    def add_l2_forwarding_rules(self):
        """Add L2 forwarding groups to all switches.

        We check the topology object to get all connected nodes and their
        MAC addresses, and configure static rules accordingly.
        """
        for switch, controller in self.controllers.items():
            # Add broadcast rule.
            controller.table_add("l2_forward", "broadcast",
                                 ["ff:ff:ff:ff:ff:ff"])

            # Add rule for connected host.
            my_host = self.topo.get_hosts_connected_to(switch)[0]
            host_mac = self.topo.node_to_node_mac(my_host, switch)
            host_port = self.topo.node_to_node_port_num(switch, my_host)
            controller.table_add("l2_forward", "l2_forward_action",
                                 [str(host_mac)], [str(host_port)])

            # Add rules for connected routers.
            for router in self.topo.get_routers_connected_to(switch):
                router_mac = self.topo.node_to_node_mac(router, switch)
                router_port = self.topo.node_to_node_port_num(switch, router)
                controller.table_add("l2_forward", "l2_forward_action",
                                     [str(router_mac)], [str(router_port)])

    def create_l2_multicast_group(self):
        """Create a multicast group to enable L2 broadcasting."""
        for switch, controller in self.controllers.items():
            controller.mc_mgrp_create(self.L2_BROADCAST_GROUP_ID)
            port_list = []

            # Get host port.
            my_host = self.topo.get_hosts_connected_to(switch)[0]
            port_list.append(self.topo.node_to_node_port_num(switch, my_host))

            # Get router ports.
            for router in self.topo.get_routers_connected_to(switch):
                port_list.append(
                    self.topo.node_to_node_port_num(switch, router))

            # Update group.
            controller.mc_node_create(0, port_list)
            controller.mc_node_associate(1, 0)
    
    def set_table_defaults(self):
        """Set table defaults to drop
        """
        for controller in self.controllers.values():
            controller.table_set_default("ipv4_lpm", "drop", [])
            controller.table_set_default("ecmp_group_to_nhop", "drop", [])

    def ECMP_route(self):
        """Populates the tables for ECMP"""
        switch_ecmp_groups = {sw_name:{} for sw_name in self.topo.get_p4switches().keys()}
        
        for sw_name, controller in self.controllers.items():
            for sw_dst in self.topo.get_p4switches():

                #We can create direct connections
                if  sw_name == sw_dst:
                    for host in self.topo.get_hosts_connected_to(sw_name):
                        sw_port = self.topo.node_to_node_port_num(sw_name, host)
                        host_ip = self.topo.get_host_ip(host) + "/24"
                        host_mac = self.topo.get_host_mac(host)

                        #add ECMP table rules
                        print "table_add at {}:".format(sw_name)
                        self.controllers[sw_name].table_add("ipv4_lpm", "set_nhop", [str(host_ip)], [str(host_mac), str(sw_port)])
                
                #Check if there are directly connected hosts
                else:
                    if self.topo.get_hosts_connected_to(sw_dst):
                        paths = self.topo.get_shortest_paths_between_nodes(sw_name, sw_dst)
                        for host in self.topo.get_hosts_connected_to(sw_dst):
                            
                            #Next hop is the destination
                            if len(paths) == 1:
                                next_hop = paths[0][1]

                                host_ip = self.topo.get_host_ip(host) + "/24"
                                sw_port = self.topo.node_to_node_port_num(sw_name, next_hop)
                                dst_sw_mac = self.topo.node_to_node_mac(next_hop, sw_name)

                                #add ECMP table rules
                                print "table_add at {}:".format(sw_name)
                                self.controllers[sw_name].table_add("ipv4_lpm", "set_nhop", [str(host_ip)], [str(dst_sw_mac), str(sw_port)])
                            
                            #Multiple next hops are possible to reach the destination
                            elif len(paths) > 1:
                                next_hops = [x[1] for x in paths]
                                dst_macs_ports = [(self.topo.node_to_node_mac(next_hop, sw_name), self.topo.node_to_node_port_num(sw_name, next_hop)) for next_hop in next_hops]
                                host_ip = self.topo.get_host_ip(host) + "/24"

                                
                                #Check if the ecmp group already exists. The ecmp group is defined by the number of next ports used, thus we can use dst_macs_ports as the key

                                if switch_ecmp_groups[sw_name].get(tuple(dst_macs_ports), None):
                                    ecmp_group_id = switch_ecmp_groups[sw_name].get(tuple(dst_macs_ports), None)
                                    print "table_add at {}:".format(sw_name)
                                    self.controllers[sw_name].table_add("ipv4_lpm", "ecmp_group", [str(host_ip)], [str(ecmp_group_id), str(len(dst_macs_ports))])
                                
                                #Create a new ECMP group for this switch
                                else:
                                    new_ecmp_group_id = len(switch_ecmp_groups[sw_name]) + 1
                                    switch_ecmp_groups[sw_name][tuple(dst_macs_ports)] = new_ecmp_group_id
                                    #add group
                                    for i, (mac, port) in enumerate(dst_macs_ports):
                                        print "table_add at {}:".format(sw_name)
                                        self.controllers[sw_name].table_add("ecmp_group_to_nhop", "set_nhop", [str(new_ecmp_group_id), str(i)], [str(mac), str(port)])

                                    #add forwarding rule
                                    print "table_add at {}:".format(sw_name)
                                    self.controllers[sw_name].table_add("ipv4_lpm", "ecmp_group", [str(host_ip)],[str(new_ecmp_group_id), str(len(dst_macs_ports))])




if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--topo', help='Path of topology.db.',
                        type=str, required=False,
                        default="../build/topology.db")
    parser.add_argument('--traffic', help='Path of traffic scenario.',
                        type=str, required=False,
                        default=None)
    args = parser.parse_args()

    control = Controller(args.topo, args.traffic)
