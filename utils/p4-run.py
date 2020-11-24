import os
import time
import argparse
from p4utils.utils.utils import *
from utils import check_output_cmd_docker, NODE_TO_CONTAINER, run_cmd_docker, run_command
from p4utils import FAILED_STATUS, SUCCESS_STATUS
from p4utils.utils.topology import Topology

MAIN_SHARED_PATH = "/home/adv-net/infrastructure/shared/"
HOSTS_SHARED_PATH = "/home/"


class AppRunner(object):

    """Class for running P4 applications.
    """

    def __init__(self, conf_file, topology_file, log_enabled, pcap_enabled):

        self.config = load_conf(conf_file)
        self.topo = Topology(db=topology_file)

        self.already_compiled = set()

        self.switch_bin = self.config.get("switch", "simple_switch")
        self.main_shared_path = MAIN_SHARED_PATH

        self.pcap_log = pcap_enabled
        self.switch_log = log_enabled

    def compile_program(self, switch_name):

        # load default configuration
        # mandatory defaults if not defined we should complain
        default_p4 = self.config.get("program", None)
        default_options = self.config.get("options", None)
        # non mandatory defaults.
        default_compiler = self.config.get("compiler", "p4c")
        default_config = {"program": default_p4,
                          "options": default_options, "compiler": default_compiler}

        # merge with switch conf
        switch_conf = default_config.copy()
        switch_conf.update(self.config['switches'][switch_name])

        p4source_path_source = switch_conf['program']

        # generate output file name
        output_file = p4source_path_source.replace(".p4", "") + ".json"

        # check it it was compiled already
        if p4source_path_source in self.already_compiled:
            return output_file

        # compile program
        try:
            compile_p4_to_bmv2(switch_conf)
            self.last_compilation_state = True
        except CompilationError:
            print('Compilation failed\n')
            return -1

        self.already_compiled.add(p4source_path_source)
        return output_file

    def start_switch(self, switch_name):

        if switch_name not in self.topo.get_switches():
            print('Switch {} does not exist'.format(switch_name))
            return self.failed_status()

        switch_config = self.config['switches'][switch_name]

        # compile program
        compiled_program = self.compile_program(switch_name)

        # copy json to docker container
        os.system("cp {} {}".format(compiled_program,
                                    self.main_shared_path+"/" + switch_name + "/"))

        # start switch in the container
        print("Starting P4 switch {}.\n".format(switch_name))
        args = [self.switch_bin]
        for intf_name, port_num in self.topo.get_interfaces_to_port(switch_name).items():
            args.extend(["-i", str(port_num)+"@"+intf_name])

        shared_base_path = HOSTS_SHARED_PATH

        # create pcap dir even if not saving pcaps
        pcap_path = "{}/pcap".format(shared_base_path)
        run_cmd_docker(switch_name, "mkdir -p " + pcap_path)
        if self.pcap_log:
            args.append("--pcap="+pcap_path)

        args.extend(
            ["--thrift-port", str(self.topo.get_thrift_port(switch_name))])

        if self.switch_log:
            nanomsg = "ipc:///tmp/bm-{}-log.ipc".format(
                self.topo[switch_name]["sw_id"])
            args.extend(['--nanolog', nanomsg])
        args.extend(['--device-id', str(self.topo[switch_name]["sw_id"])])

        # json file
        docker_json_file = shared_base_path + compiled_program.split("/")[-1]
        args.append(docker_json_file)

        # we create the log dir even if not logging
        log_path = "{}/logs/".format(shared_base_path)
        run_cmd_docker(switch_name, "mkdir -p " + log_path)
        if self.switch_log:
            log_file = "{}/{}.txt".format(log_path, switch_name)
            args.append("--log-console")
            args.append(" > " + log_file)

        # start switch in docker and check if it started
        cmd = ' '.join(args)
        cmd = 'bash -c "{}"'.format(cmd)

        #import ipdb; ipdb.set_trace()
        print(cmd)
        run_cmd_docker(switch_name, cmd + " & ", "")

        time.sleep(2)

        # populate static tables
        commands_path = switch_config.get('cli_input', None)
        if commands_path:
            if not os.path.exists(commands_path):
                print('File Error: commands file %s does not exist\n' %
                      commands_path)
                return -1

            entries = read_entries(commands_path)
            cli_outfile = '{}/{}/logs/{}_cli_output.log'.format(
                self.main_shared_path, switch_name, switch_name)
            thrift_port = str(self.topo.get_thrift_port(switch_name))
            thrift_ip = self.topo.get_thrift_ip(switch_name)
            add_entries(thrift_port, entries, cli_outfile, thrift_ip=thrift_ip)

    def stop_switch(self, switch_name):
        run_cmd_docker(
            switch_name, '''bash -c "kill -9 \$(ps axu | grep -e simple_switch | awk '{print \$2}')"''')

    def reboot_switch(self, switch_name):
        self.stop_switch(switch_name)
        self.start_switch(switch_name)

    def start_switches(self):
        for switch in self.topo.get_switches():
            self.start_switch(switch)

    def stop_switches(self):
        # dirty way
        #run_command("sudo kill -9 $(ps aux | grep -e simple_switch | awk '{ print $2 }')")
        for switch in self.topo.get_switches():
            self.stop_switch(switch)

    def reboot_switches(switch):
        self.stop_switches()
        time.sleep(1)
        self.start_switches()


def get_args():

    parser = argparse.ArgumentParser()
    parser.add_argument('--config', help='Path to configuration',
                        type=str, required=False, default='./configuration.json')
    parser.add_argument('--topo', help='Path to topology',
                        type=str, required=False, default='./topology.db')
    parser.add_argument('--cmd', help='Command to run',
                        type=str, required=False, default='start')
    parser.add_argument('--target', help='Target Switches',
                        type=str, required=False, default='all')
    parser.add_argument('--log', action='store_true',
                        help='Enables logging if the switch allows it')
    parser.add_argument('--pcap', action='store_true',
                        help='Enables logging if the switch allows it')

    return parser.parse_args()


if __name__ == '__main__':

    args = get_args()
    runner = AppRunner(args.config, args.topo, args.log, args.pcap)

    if args.cmd == "start":
        if args.target == "all":
            runner.start_switches()
        else:
            runner.start_switch(args.target)
    elif args.cmd == "stop":
        if args.target == "all":
            runner.stop_switches()
        else:
            runner.stop_switch(args.target)
    elif args.cmd == "reboot":
        if args.target == "all":
            runner.reboot_switches()
        else:
            runner.reboot_switch(args.target)
    else:
        print("Invalid command {}".format(args.cmd))
