import subprocess
import json
import ipdb
import re

from utils import check_output_cmd_docker, NODE_TO_CONTAINER

class MiniInternetTopoBuilder(object):
    def __init__(self, mini_internet_conf_path):
        self.mini_internet_conf_path = mini_internet_conf_path

    def load_router_conf(self, file):
        """Loads FRR and P4 switches configuration

        Args:
            file ([type]): [description]
        """

        router_confs = {}
        with open(file, "r") as f:
            for line in f:
                name, node_type, _, host_type, bw_host, delay_host = line.split()

                has_host = True if host_type.endswith("_host") else False
                router_confs[name] = {
                    'type': node_type, 'has_host': has_host, "host_bw": bw_host, "host_delay": delay_host}
        return router_confs

    def load_internal_links_conf(self, file):
        """Loads Internal links pairings

        Args:
            file ([type]): [description]
        """

        link_confs = {}
        with open(file, "r") as f:
            for line in f:
                node1, node2, bw, delay = line.split()
                link_confs[(node1, node2)] = (bw, delay)
        return link_confs

    def load_configs(self):
        """Loads mini internet relevant configurations
        """

        path = self.mini_internet_conf_path
        self.router_confs = self.load_router_conf(
            path + "/router_config_tmp.txt")
        self.links_confs = self.load_internal_links_conf(
            path + "/internal_links_config.txt")

    def get_switches(self):
        """gets all switches in the network

        Returns:
            [type]: [description]
        """

        return {name: {} for name, setting in self.router_confs.items() if "switch" in setting["type"]}

    def get_routers(self):
        """gets all routers in the network

        Returns:
            [type]: [description]
        """
        return {name: {} for name, setting in self.router_confs.items() if "frr" in setting["type"]}

    def build_hosts(self):
        """uses conf info and already configured interfaces to parse relevant data

        Returns:
            [type]: [description]
        """

        hosts = {}
        # first we find them
        for router, setting in self.router_confs.items():
            if setting["has_host"]:
                host_name = "h{}".format(
                    int(re.search(r'\d+', router).group()))
                router_type = "router" if setting["type"] == "frr" else "switch"
                # get interface name
                intf_name = "{}{}".format(router, router_type)
                # get interface metadata
                ip_addr = check_output_cmd_docker(
                    host_name, "ip -f inet addr show {} | awk '/inet / {{print $2}}'".format(intf_name)).strip()
                gateway_addr = check_output_cmd_docker(
                    host_name, "ip r | grep default | awk '{print $3}'").strip()
                mac_addr = check_output_cmd_docker(
                    host_name, "cat /sys/class/net/{}/address".format(intf_name)).strip()
                delay = int(setting["host_delay"])
                bw = int(setting["host_bw"])/1000
                loss = None
                weight = 1
                queue_length = None
                hosts[host_name] = {router:
                                    {'bw': bw,
                                     'delay': delay,
                                     'intf': intf_name,
                                     'ip': ip_addr,
                                     'loss': loss,
                                     'mac': mac_addr,
                                     'queue': queue_length,
                                     'weight': weight},
                                    'type': 'host',
                                    'gateway': gateway_addr,
                                    'interfaces_to_node': {intf_name: router},
                                    'interfaces_to_port': {intf_name: 0}
                                    }

        return hosts

    def build_forwarding_nodes(self):
        """uses conf info and already configured interfaces to parse relevant data

        Args:
            node_type ([type]): [description]
        """

        switches = self.get_switches()
        routers = self.get_routers()
        nodes = {}
        nodes.update(switches)
        nodes.update(routers)
        device_id = 1
        thrift_port = 9090

        for node in nodes.keys():

            # set node type
            if node in switches:
                node_type = "switch"
            elif node in routers:
                node_type = "router"

            intf_index = 1
            interfaces_to_node = {}
            interfaces_to_port = {}

            if node_type == "switch":
                nodes[node]["type"] = "switch"
                nodes[node]["subtype"] = "p4switch"
                nodes[node]["sw_id"] = device_id
                nodes[node]["thrift_port"] = thrift_port
                device_id += 1
                thrift_port += 1
                # add addresses and api info
                nodes[node]["ctl_cpu_intf"] = "1-{}-cpu".format(node)
                thrift_ip = check_output_cmd_docker(
                    node, "ip -f inet addr show {} | awk '/inet / {{print $2}}'".format("switch-api")).strip().split("/")[0]
                nodes[node]["thrift_ip"] = thrift_ip

            elif node_type == "router":
                nodes[node]["type"] = "router"
                # get router id
                router_id = [x for x in check_output_cmd_docker(
                    node, "ip -f inet addr show lo | awk '/inet / {print $2}'").split() if not x.startswith("127.0.0.1")]
                if router_id:
                    router_id = router_id[0]
                nodes[node]["router_id"] = router_id

            # if there is a directly connected node
            if self.router_confs[node]['has_host']:
                setting = self.router_confs[node]
                host_name = "h{}".format(int(re.search(r'\d+', node).group()))
                intf_name = 'host'
                ip_addr = check_output_cmd_docker(
                    node, "ip -f inet addr show {} | awk '/inet / {{print $2}}'".format(intf_name)).strip()
                mac_addr = check_output_cmd_docker(
                    node, "cat /sys/class/net/{}/address".format(intf_name)).strip()
                delay = int(setting["host_delay"])
                bw = int(setting["host_bw"])/1000
                loss = None
                weight = 1
                queue_length = None
                nodes[node][host_name] = {'bw': bw,
                                          'delay': delay,
                                          'intf': intf_name,
                                          'ip': ip_addr,
                                          'loss': loss,
                                          'mac': mac_addr,
                                          'queue': queue_length,
                                          'weight': weight}

                # simple connectivity object
                interfaces_to_port[intf_name] = intf_index
                intf_index += 1
                interfaces_to_node[intf_name] = host_name

            # add other links info
            for (src, dst), setting in self.links_confs.items():
                # if we are in any of the links
                if src == node or dst == node:
                    # internal links, thus its a router or a switch
                    host_name = src if node == dst else dst
                    intf_name = "port_{}".format(host_name)
                    ip_addr = check_output_cmd_docker(
                        node, "ip -f inet addr show {} | awk '/inet / {{print $2}}'".format(intf_name)).strip()
                    mac_addr = check_output_cmd_docker(
                        node, "cat /sys/class/net/{}/address".format(intf_name)).strip()
                    delay = int(setting[1])
                    bw = int(setting[0])/1000
                    loss = None
                    weight = 1
                    queue_length = None
                    nodes[node][host_name] = {'bw': bw,
                                              'delay': delay,
                                              'intf': intf_name,
                                              'ip': ip_addr,
                                              'loss': loss,
                                              'mac': mac_addr,
                                              'queue': queue_length,
                                              'weight': weight}

                    # simple connectivity object
                    interfaces_to_port[intf_name] = intf_index
                    intf_index += 1
                    interfaces_to_node[intf_name] = host_name

            if node_type == "switch":
                interfaces_to_port[nodes[node]["ctl_cpu_intf"]] = intf_index

            nodes[node]["interfaces_to_port"] = interfaces_to_port
            nodes[node]["interfaces_to_node"] = interfaces_to_node

        return nodes

    def build(self):
        self.load_configs()
        self.hosts = self.build_hosts()
        self.nodes = self.build_forwarding_nodes()
        self.topo = {}
        self.topo.update(self.hosts)
        self.topo.update(self.nodes)

    def save_topology(self, out_file="topology.db"):
        with open(out_file, 'w') as f:
            json.dump(self.topo, f)


if __name__ == "__main__":

    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--config_dir', help='Path to topology configuration',
                        type=str, required=True)
    parser.add_argument('--out_dir', help='Output path name',
                        type=str, required=False, default="topology.db")

    args = parser.parse_args()

    p = MiniInternetTopoBuilder(args.config_dir)
    p.build()
    p.save_topology(args.out_dir)
