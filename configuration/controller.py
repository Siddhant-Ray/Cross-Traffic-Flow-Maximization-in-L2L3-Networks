"""Implement your controller in this file.

The existing controller already implements L2-forwarding to ensure connectivity.
Use this code as an example to get you started.
You are free to completely change this!

Tip:
For debugging, you can start this file in interactive mode.
This will execute the whole file, but then *keep* the python interpreter open,
allowing you to inspect objects and try out things!

```
$ python2 -i controller.py --topo </build/topology.db>
```

The controller will be available as the variable `control`.
"""
# pylint: disable=superfluous-parens,invalid-name

import argparse
import csv
import time
#LFA RELATED IMPORTS
from networkx.algorithms import all_pairs_dijkstra

from p4utils.utils.topology import Topology
from p4utils.utils.sswitch_API import SimpleSwitchAPI

from scapy.all import sniff, IP, Ether, UDP, sendp
from scapy.contrib.bfd import BFD
from multiprocessing import Process
import threading
import time
from random import randint


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
        # Initialize the IP lookup table.
        # This is used to match IP addresses to node names.
        self.ip_lookup_table = {}
        self.populate_ip_lookup_table()

        # This adds the mirrors to receive
        # the forwarded BFD packets from the switches.
        self.add_mirrors()

        # Initialization of L2 forwarding. Feel free to modify.
        self.create_l2_multicast_group()
        self.add_l2_forwarding_rules()

        # Use the traffic matrix (this is an alternative solution)
        self.compute_bandwidth_for_traffic_split()

        # Call MP route
        self.MP_route()

        # Installing the rewriteMac table to match ports to
        # their MAC addresses.
        self.install_macs()
        # Install nexthop indices and populate registers used to query nexthops in the P4 code (used in LFA).
        self.install_nexthop_indices_LFA()
        # Recalculates next hops and LFAs after link failure is detected and installs them in their
        # relevant registers (specifically the primaryNH and the alternativeNH registers)
        self.update_nexthops_LFA()

        # This extends the switch graph of the topology to
        # include routers. Specifically this is used so we can also
        # detect link failure between switches and routers.
        self.setup_link_map()
        # Sets up two dictionaries to track the link status.
        self.install_link_register()
        # This is changed when there was a change in status of at least one link.
        # This preserves calculation cycles.
        self.LFA_flag = 0

        # This answers to the routers so that the BFD packets will be sent at a higher rate
        # back to the switches. If a router wouldn't receive a BFD control packet it would
        # - according to RFC 5881 - only send control packets every 1s.
        self.init_bfd()

        # All these functions have to run in parallel, thus we are using Threads.
        # Otherwise each of them would block.
        sniffing = threading.Thread(target=self.sniff_bfd_packets)
        sniffing.daemon = True
        sniffing.start()

        # This sends heartbeats between the switches so we can
        # detect link failures in between switches.
        heartbeat = threading.Thread(
            target=self.send_heartbeat_between_switches)
        heartbeat.daemon = True
        heartbeat.start()

        # Waiting for one second so that the heartbeat register can
        # count some packets already so that the links won't be registerd
        # as down. This doesn't exceed the 5s initialization period.
        time.sleep(1)

        # Checking the status of our switch-switch and switch-router
        # links.
        links = threading.Thread(target=self.check_link_status)
        links.daemon = True
        links.start()

        # Converts the BFD supported heartbeat register into instructions for the
        # LFA and also triggers the LFA part of the P4 code in case of link failure.
        interfaces = threading.Thread(
            target=self.check_interface_and_trigger_lfa)
        interfaces.daemon = True
        interfaces.start()

        # Keeping main thread alive so others dont get killed
        # as they are run as daemons.
        while True:
            time.sleep(1)

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

            # Add rules for connected routers.
            for connected_switch in self.topo.get_switches_connected_to(
                    switch):
                connected_switch_mac = self.topo.node_to_node_mac(
                    connected_switch, switch)
                connected_switch_port = self.topo.node_to_node_port_num(
                    switch, connected_switch)
                controller.table_add("l2_forward", "l2_forward_action",
                                     [str(connected_switch_mac)],
                                     [str(connected_switch_port)])

    def create_l2_multicast_group(self):
        """Create a multicast group to enable L2 broadcasting.
        """
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
            controller.table_set_default("mp_group_to_nhop", "drop", [])

    def compute_bandwidth_for_traffic_split(self):
        """Reading the bandwidths of the flow to decide on which switch we do load balancing.
        """

        # Iterate over all fields of the traffic list
        for flow in self.traffic:

        # Get the switch the traffic arrives at first
            switch = "S" + flow['src'][1]

            #Extracting the numeric part of the BW
            bandwidth = flow['rate'][:-1]

            #If bandwidth > 4, update register for that switch
            if int(bandwidth) > 4:

                control = self.controllers[switch]
                index = 0
                state = 1  # means traffic splitting is necessary
                control.register_write('Bandwidth', index, state)

    def check_interface_and_trigger_lfa(self):
        """Checks the interfaces for link failures and then triggers the LFA.
        """

        while (True):
            try:
                self.check_interface_status()
                self.trigger_lfa()
            except (KeyboardInterrupt, SystemExit):
                print("Exiting...")
                break

    def MP_route(self):
        """Populates the tables for Multipath
            
            For our network we split over all egress paths irrespectively of the cost. More details on 
            this is given in the apply() section of the switch.p4 program. We use 
            the get_neighbors_connected_to method of the topology object, to determine the next hop.
            This is only used for bronze and silver traffic.
        """

        switch_mp_groups = {
            sw_name: {}
            for sw_name in self.topo.get_p4switches().keys()
        }

        for sw_name, controller in self.controllers.items():
            for sw_dst in self.topo.get_p4switches():

                # If the switch is the destination switch
                # then add the nexthop to it's connected host.
                if sw_name == sw_dst:
                    for host in self.topo.get_hosts_connected_to(sw_name):
                        sw_port = self.topo.node_to_node_port_num(
                            sw_name, host)
                        host_ip = self.topo.get_host_ip(host) + "/24"
                        host_mac = self.topo.get_host_mac(host)

                        # add MP table rules
                        print "table_add at {}:".format(sw_name)
                        self.controllers[sw_name].table_add(
                            "ipv4_lpm", "set_nhop", [str(host_ip)],
                            [str(host_mac), str(sw_port)])

                # If the switch is not the final switch in the path
                else:
                    if self.topo.get_hosts_connected_to(sw_dst):
                        all_nodes = self.topo.get_neighbors(sw_name)
                        hosts = self.topo.get_hosts_connected_to(sw_name)
                        all_nodes_without_hosts = list(
                            set(all_nodes) - set(hosts))

                        for host in self.topo.get_hosts_connected_to(sw_dst):
                            if len(all_nodes_without_hosts) == 1:
                                next_hop = all_nodes_without_hosts[0]

                                host_ip = self.topo.get_host_ip(host) + "/24"
                                sw_port = self.topo.node_to_node_port_num(
                                    sw_name, next_hop)
                                dst_sw_mac = self.topo.node_to_node_mac(
                                    next_hop, sw_name)

                                #add MP table rules
                                print "table_add at {}:".format(sw_name)
                                self.controllers[sw_name].table_add(
                                    "ipv4_lpm", "set_nhop", [str(host_ip)],
                                    [str(dst_sw_mac),
                                     str(sw_port)])

                            #Multiple next hops are possible to reach the destination
                            elif len(all_nodes_without_hosts) > 1:
                                #next_hops = [x[1] for x in paths]
                                next_hops = all_nodes_without_hosts
                                #print next_hops

                                dst_macs_ports = [
                                    (self.topo.node_to_node_mac(
                                        next_hop, sw_name),
                                     self.topo.node_to_node_port_num(
                                         sw_name, next_hop))
                                    for next_hop in next_hops
                                ]
                                host_ip = self.topo.get_host_ip(host) + "/24"

                                #Check if the ecmp group already exists. The ecmp group is defined by the number of next ports used, thus we can use dst_macs_ports as the key

                                if switch_mp_groups[sw_name].get(
                                        tuple(dst_macs_ports), None):
                                    mp_group_id = switch_mp_groups[
                                        sw_name].get(tuple(dst_macs_ports),
                                                     None)
                                    print "table_add at {}:".format(sw_name)
                                    self.controllers[sw_name].table_add(
                                        "ipv4_lpm", "mp_group",
                                        [str(host_ip)], [
                                            str(mp_group_id),
                                            str(len(dst_macs_ports))
                                        ])

                                #Create a new ECMP group for this switch
                                else:
                                    new_mp_group_id = len(
                                        switch_mp_groups[sw_name]) + 1
                                    switch_mp_groups[sw_name][tuple(
                                        dst_macs_ports)] =new_mp_group_id 
                                    #add group
                                    for i, (mac,
                                            port) in enumerate(dst_macs_ports):
                                        print "table_add at {}:".format(
                                            sw_name)
                                        self.controllers[sw_name].table_add(
                                            "mp_group_to_nhop", "set_nhop",
                                            [str(new_mp_group_id),
                                             str(i)],
                                            [str(mac), str(port)])

                                    #add forwarding rule
                                    print "table_add at {}:".format(sw_name)
                                    self.controllers[sw_name].table_add(
                                        "ipv4_lpm", "mp_group",
                                        [str(host_ip)], [
                                            str(new_mp_group_id),
                                            str(len(dst_macs_ports))
                                        ])

    ####################### LFA INSTALL ################################
    # Link management commands.
    # =========================

    def check_interface_status(
        self
    ):  #This needs to be triggered by OSPF to notice a link state is down
        #This will need to be generated somehow

        # if (self.i_test == 1):
        #     test_link = (u'S3', u'S4')
        #     self.heartbeat_register[test_link] = 0
        # if(self.i_test == 3):
        #     test_link = (u'S3', u'S4')
        #     self.heartbeat_register[test_link] = 1

        #Need to account for duplicates, especially if they disagree

        self.LFA_flag = 0  #This flag gets raised if there was a transition in the heartbeat register

        for link in self.heartbeat_register:
            status = self.heartbeat_register[link]['status']
            current_reg_value = self.links_states[link]

            heartbeat_state = "down" if status == 0 else "up"  #For now, assume that heartbeat  is 0 or 1

            if heartbeat_state == current_reg_value:
                pass
            else:
                self.LFA_flag = 1  #As soon as there is one transition, this becomes 1
                if status == 0:  #That is, if its down
                    self.update_interfaces(
                        link, "down"
                    )  # Set the self.interfaces dictionary that Pyton uses
                    self.update_linkstate(link,
                                          "down")  # Sets the P4 registers
                else:
                    self.update_interfaces(link, "up")  # See above
                    self.update_linkstate(link, "up")  # See above

        # self.i_test = self.i_test  + 1

    def trigger_lfa(self):
        """Notify controller of failures (or lack thereof)."""
        failed = self.check_all_links()
        if self.LFA_flag:  #So if there was a change
            print("Processing change in Heartbeat")
            self.failure_notification(failed)
        else:
            pass  #Otherwise, continue on as before

    # Link management helpers.
    # ========================

    def check_all_links(self):
        """Check the state for all link interfaces."""
        failed_links = []
        for link in self.accessible_links:
            if not (self.if_up(link)):  #Triggered thus by not (False)
                failed_links.append(link)
        return failed_links

    def if_up(self, link):
        """Return True if interface is up, else False."""
        status = self.links_states[link]
        if status == "up":
            return True
        else:
            return False

    def update_interfaces(self, link, state):
        """Set link to state (up or down)."""
        self.links_states[link] = state

    def get_interfaces(self, link):
        """Return tuple of interfaces on both sides of the link."""
        node1, node2 = link
        if_12 = self.topo[node1][node2]['intf']
        if_21 = self.topo[node2][node1]['intf']
        return if_12, if_21

    def get_ports(self, link):
        """Return tuple of interfaces on both sides of the link."""
        node1, node2 = link
        if1, if2 = self.get_interfaces(link)
        port1 = self.topo[node1]['interfaces_to_port'][if1]
        port2 = self.topo[node2]['interfaces_to_port'][if2]
        return port1, port2

    def update_linkstate(self, link, state):
        """Update switch linkstate register for both link interfaces.

        The register array is indexed by the port number, e.g., the state for
        port 0 is stored at index 0.
        """
        node1, node2 = link
        port1, port2 = self.get_ports(link)
        switches = self.topo.get_switches()
        _state = "1" if state == "down" else "0"

        if node1 in switches:
            self.update_switch_linkstate(node1, port1, _state)

        if node2 in switches:
            self.update_switch_linkstate(node2, port2, _state)

    def update_switch_linkstate(self, switch, port, state):
        """Update the link state register on the device. """
        control = self.controllers[switch]
        control.register_write('linkState', port, state)

    # THE LFA CONTROLLER
    def install_link_register(self):
        """install registers used to track linkstate."""
        self.links_states = {}
        self.heartbeat_register = {}
        for link in self.accessible_links:
            self.links_states[
                link] = "up"  # This register is for the controller itself
            self.heartbeat_register[link] = {
                'count': 1,
                'status': 1
            }  #This register is updated continously by the heartbeat message
        print("Registers installed")

    def setup_link_map(self):
        """Like Switchgraph, but also includes Routers"""
        self.accessible_links = []
        links_all = self.topo.network_graph.edges
        hosts = self.topo.get_hosts().keys()
        routers = self.topo.get_routers().keys()
        for link in links_all:
            if link[0] in hosts or link[1] in hosts:
                pass
            elif link[0] in routers and link[1] in routers:
                pass
            else:
                self.accessible_links.append(link)

        print("Accessible Link Map Setup")

    def get_host_net(self, host):  #Imported from Exercise
        """Return ip and subnet of a host.

        Args:
            host (str): The host for which the net will be retruned.

        Returns:
            str: IP and subnet in the format "address/mask".
        """
        gateway = self.topo.get_host_gateway_name(host)
        return self.topo[host][gateway]['ip']

    def get_nexthop_index(self, host):  #Imported from Exercise
        """Return the nexthop index for a destination.

        Args:
            host (str): Name of destination node (host).

        Returns:
            int: nexthop index, used to look up nexthop ports.
        """
        # For now, give each host an individual nexthop id.
        host_list = sorted(list(self.topo.get_hosts().keys()))
        return host_list.index(host)

    def get_port(self, node, nexthop_node):  #Imported from Exercise
        """Return egress port for nexthop from the view of node.

        Args:
            node (str): Name of node for which the port is determined.
            nexthop_node (str): Name of node to reach.

        Returns:
            int: nexthop port
        """
        return self.topo.node_to_node_port_num(node, nexthop_node)

    def failure_notification(
            self,
            failures):  # This method gets called by the check_all_links method
        """Called if a link fails.

        Args:
            failures (list(tuple(str, str))): List of failed links.
        """
        self.update_nexthops_LFA(failures=failures)

    def dijkstra(self, failures=None):  #Imported from Exercise
        """Compute shortest paths and distances.

        Args:
            failures (list(tuple(str, str))): List of failed links.

        Returns:
            tuple(dict, dict): First dict: distances, second: paths.
        """
        graph = self.topo.network_graph

        if failures is not None:
            graph = graph.copy()
            for failure in failures:
                graph.remove_edge(*failure)

        # Compute the shortest paths from switches to hosts.
        dijkstra = dict(all_pairs_dijkstra(graph, weight='weight'))

        distances = {node: data[0] for node, data in dijkstra.items()}
        paths = {node: data[1] for node, data in dijkstra.items()}

        return distances, paths

    def compute_nexthops(self, failures=None):  #Imported from Exercise
        """Compute the best nexthops for all switches to each host.

        Optionally, a link can be marked as failed. This link will be excluded
        when computing the shortest paths.

        Args:
            failures (list(tuple(str, str))): List of failed links.

        Returns:
            dict(str, list(str, str, int))):
                Mapping from all switches to subnets, MAC, port.
        """
        # Compute the shortest paths from switches to hosts.
        all_shortest_paths = self.dijkstra(failures=failures)[1]

        # Translate shortest paths to mapping from host to nexthop node
        # (per switch).
        results = {}
        for switch in self.controllers:
            switch_results = results[switch] = []
            for host in self.topo.network_graph.get_hosts():
                try:
                    path = all_shortest_paths[switch][host]
                except KeyError:
                    print "WARNING: The graph is not connected!"
                    print "'%s' cannot reach '%s'." % (switch, host)
                    continue
                nexthop = path[1]  # path[0] is the switch itself.
                switch_results.append((host, nexthop))

        return results

    def install_macs(self):
        """Install the port-to-mac map on all switches.
        """
        for switch, control in self.controllers.items():
            print "Installing MAC addresses for switch '%s'." % switch
            print "=========================================\n"
            for neighbor in self.topo.get_neighbors(switch):
                mac = self.topo.node_to_node_mac(neighbor, switch)
                port = self.topo.node_to_node_port_num(switch, neighbor)
                control.table_add('rewrite_mac', 'rewriteMac', [str(port)],
                                  [str(mac)])

    def install_nexthop_indices_LFA(self):
        """Install the mapping from prefix to nexthop ids for all switches."""
        for switch, control in self.controllers.items():
            print "Installing nexthop indices for LFA setup '%s'." % switch
            print "===========================================\n"
            control.table_clear('dst_index')
            for host in self.topo.get_hosts():
                subnet = self.get_host_net(host)
                index = self.get_nexthop_index(host)
                control.table_add('dst_index', 'query_nextLink', [subnet],
                                  [str(index)])

    def update_nexthops_LFA(self, failures=None):
        """Install nexthops in all switches."""
        nexthops = self.compute_nexthops(
            failures=failures
        )  # We need to link the ECMP here with the LFA, so that the nexthops used here are the ECMP ones
        lfas = self.compute_lfas(nexthops, failures=failures)

        for switch, destinations in nexthops.items():
            control = self.controllers[switch]
            for host, nexthop in destinations:
                nexthop_id = self.get_nexthop_index(host)
                port = self.get_port(switch, nexthop)
                # Write the port in the nexthop lookup register.
                control.register_write('primaryNH', nexthop_id, port)

        #######################################################################
        # Compute loop-free alternate nexthops and install them below.
        #######################################################################

        # LFA solution.
        # =============

            for host, nexthop in destinations:
                nexthop_id = self.get_nexthop_index(host)
                if host == nexthop:
                    continue  # Cannot do anything if host link fails.

                try:
                    lfa_nexthop = lfas[switch][host]
                except KeyError:
                    lfa_nexthop = nexthop  # Fallback to default nh.
                lfa_port = self.get_port(switch, lfa_nexthop)

                control.register_write('alternativeNH', nexthop_id, lfa_port)

    def compute_lfas(self, nexthops, failures=None):
        """Compute LFA (loop-free alternates) for all nexthops."""
        _d = self.dijkstra(failures=failures)[0]
        lfas = {}

        for switch, destinations in nexthops.items():
            switch_lfas = lfas[switch] = {}
            # connected = set(self.topo.get_switches_connected_to(switch))
            #Alternate:
            neighbours = set(self.topo.get_neighbors(switch))
            connected_hosts = self.topo.get_hosts_connected_to(switch)[
                0]  #each switch is connected to just one host
            connected = neighbours - {connected_hosts}

            for host, nexthop in destinations:
                if nexthop == host:
                    continue  # Nothing can be done if host link fails.

                others = connected - {nexthop}
                # Check with alternates are loop free
                noloop = []
                for alternate in others:
                    # The following condition needs to hold:
                    # D(N, D) < D(N, S) + D(S, D)
                    if (_d[alternate][host] <
                            _d[alternate][switch] + _d[switch][host]):
                        total_dist = _d[switch][alternate] + \
                            _d[alternate][host]
                        noloop.append((alternate, total_dist))

                    if not noloop:
                        continue  # No LFA :(

                    # Keep LFA with shortest distance
                    switch_lfas[host] = min(noloop, key=lambda x: x[1])[0]
        return lfas

    ####################### LFA INSTALL ################################

    def add_mirrors(self):
        """Add mirrors for the data plane to communicate with the control plane.
        """

        base_session_id = 100
        for switch in self.topo.get_p4switches().keys():
            cpu_port = self.topo.get_cpu_port_index(switch)
            self.controllers[switch].mirroring_add(base_session_id, cpu_port)

    def update_heartbeat_register(self, pkt):
        """Update the heartbeat register according to incoming packets.

        :param pkt: an incoming bfd packet
        :type pkt: bfd packet
        """

        try:
            # extract src and dst ip addresses
            src_address = pkt[IP].src
            dst_address = pkt[IP].dst

            if (src_address == '9.0.0.6' and pkt[BFD].flags == 32):
                raise KeyError
            elif (src_address == '9.0.0.4' and pkt[BFD].flags == 32):
                raise KeyError

            # convert addresses to names to insert into the heartbeat_register
            src_node = self.ip_lookup_table[src_address]
            dst_node = self.ip_lookup_table[dst_address]

            try:
                # increase the counter
                self.heartbeat_register[(src_node, dst_node)]['count'] += 1
                # and set the link state to up
                self.heartbeat_register[(src_node, dst_node)]['status'] = 1
            except KeyError as e:
                # if the key is the other way around
                self.heartbeat_register[(dst_node, src_node)]['count'] += 1
                self.heartbeat_register[(dst_node, src_node)]['status'] = 1
        except KeyError as e:
            pass

    def sniff_bfd_packets(self):
        """Sniff on the CPU ports for BFD packets.
        """

        try:
            # get the names of all p4 cpu interface
            cpu_port_interfaces = [
                self.topo.get_cpu_port_intf(switch)
                for switch in self.topo.get_p4switches().keys()
            ]

            # sniff on all cpu port interfaces for bfd packets
            # and invoke the update_heartbeat_register function on each packet
            sniff(
                iface=cpu_port_interfaces,
                prn=self.update_heartbeat_register,
                lfilter=lambda x: x.haslayer(BFD),
            )
        except (KeyboardInterrupt, SystemExit):
            print("Exiting...")

    def send_heartbeat_between_switches(self):
        """Send hearbeats between switch to switch links.
        """

        while (True):
            try:
                # get the source and destination mac/ip adresses
                src_mac = self.topo.node_to_node_mac('S6', 'S1')
                dst_mac = self.topo.node_to_node_mac('S1', 'S6')

                # send heartbeat between S6-S1
                sendp(Ether(dst=dst_mac, src=src_mac, type=2048) / IP(
                    version=4, tos=192, dst='9.0.0.1', proto=17, src='9.0.0.6')
                      / UDP(sport=49156, dport=3784, len=32) /
                      BFD(version=1,
                          diag=0,
                          your_discriminator=0,
                          flags=32,
                          my_discriminator=15,
                          echo_rx_interval=50000,
                          len=24,
                          detect_mult=3,
                          min_tx_interval=250000,
                          min_rx_interval=250000,
                          sta=1),
                      iface='1-S6-cpu',
                      verbose=False)

                # get the source and destination mac/ip adresses
                src_mac = self.topo.node_to_node_mac('S4', 'S3')
                dst_mac = self.topo.node_to_node_mac('S3', 'S4')

                # send heartbeat between S4-S3
                sendp(Ether(dst=dst_mac, src=src_mac, type=2048) / IP(
                    version=4, tos=192, dst='9.0.0.3', proto=17, src='9.0.0.4')
                      / UDP(sport=49155, dport=3784, len=32) /
                      BFD(version=1,
                          diag=0,
                          your_discriminator=0,
                          flags=32,
                          my_discriminator=14,
                          echo_rx_interval=50000,
                          len=24,
                          detect_mult=3,
                          min_tx_interval=250000,
                          min_rx_interval=250000,
                          sta=1),
                      iface='1-S4-cpu',
                      verbose=False)

                # send the heartbeat packets every 0.1 seconds
                time.sleep(0.1)
            except (KeyboardInterrupt, SystemExit):
                print("Exiting...")
                break

    def populate_ip_lookup_table(self):
        """Populates a table that maps IP addresses to names.
        """
        self.ip_lookup_table = {
            '9.0.0.1': u'S1',
            '9.0.0.2': u'S2',
            '9.0.0.3': u'S3',
            '9.0.0.4': u'S4',
            '9.0.0.5': u'S5',
            '9.0.0.6': u'S6',
            '1.0.0.2': u'R1',
            '6.0.0.3': u'R1',
            '2.0.0.2': u'R1',
            '2.0.0.3': u'R2',
            '3.0.0.2': u'R2',
            '4.0.0.3': u'R2',
            '3.0.0.3': u'R3',
            '4.0.0.2': u'R3',
            '5.0.0.3': u'R3',
            '1.0.0.3': u'R4',
            '6.0.0.2': u'R4',
            '5.0.0.2': u'R4',
        }

    def check_link_status(self):
        """Checks the status of each link. If there hasn't been received a packet in 2 seconds, consider the link as down.
        """

        while (True):

            try:
                # check for every link
                # if we sniffed a bfd packet
                for link in self.heartbeat_register:
                    # if not, set the link status to 0
                    if self.heartbeat_register[link]['count'] == 0:
                        print("link {} failed".format(link))
                        self.heartbeat_register[link]['status'] = 0
                    else:
                        # if, reset the count to 0 for the next epoch
                        # setting the status to 1 if its up again happens
                        # immediately in update_heartbeat_register
                        self.heartbeat_register[link]['count'] = 0

                # wait 1.5 seconds before checking again as the heartbeat is currently sent every 100ms
                #  (controller cant handle more packets )
                time.sleep(1.5)
            except (KeyboardInterrupt, SystemExit):
                print("Exiting...")
                break

    def init_bfd(self):
        """Answer to BFD control packets.
        """

        sport = 65500

        # the switches have static routes assigned
        name_to_ip = {
            'S1': '9.0.0.1',
            'S2': '9.0.0.2',
            'S3': '9.0.0.3',
            'S4': '9.0.0.4',
            'S5': '9.0.0.5',
            'S6': '9.0.0.6'
        }

        # for every switch
        for switch in self.topo.get_p4switches().keys():

            # get the cpu port interface
            interface = self.topo.get_cpu_port_intf(switch)

            # for every connected router
            for router in [
                    node for node in self.topo.get_neighbors(switch)
                    if self.topo.is_router(node)
            ]:

                # get the source and destination mac/ip adresses
                src_mac = self.topo.node_to_node_mac(switch, router)
                dst_mac = self.topo.node_to_node_mac(router, switch)

                dst_ip = self.topo.node_to_node_interface_ip(
                    router, switch).split("/")[0]
                src_ip = name_to_ip[switch]

                # choose a random discriminator
                my_discriminator = randint(1, 10000000)

                # populate the bfd control packet
                bfdpkt = Ether(dst=dst_mac, src=src_mac, type=2048) / IP(
                    version=4,
                    tos=192,
                    dst=dst_ip,
                    proto=17,
                    flags=2,
                    ttl=255,
                    src=src_ip) / UDP(sport=sport, dport=3784) / BFD(
                        version=1,
                        diag=0,
                        your_discriminator=0,
                        flags=32,
                        my_discriminator=my_discriminator,
                        echo_rx_interval=50000,
                        len=24,
                        detect_mult=3,
                        min_tx_interval=100000,
                        min_rx_interval=100000,
                        sta=1)

                sendp(bfdpkt, iface=interface, count=10, verbose=0)

                # decrement the source port (has to be unique)
                sport -= 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--topo',
        help='Path of topology.db.',
        type=str,
        required=False,
        default="/home/adv-net/infrastructure/build/topology.db")
    parser.add_argument('--traffic',
                        help='Path of traffic scenario.',
                        type=str,
                        required=False,
                        default=None)
    args = parser.parse_args()

    control = Controller(args.topo, args.traffic)
