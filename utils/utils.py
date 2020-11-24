from __future__ import print_function
import sys, os
import subprocess
import json

# network mapping, this could be a conf file
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

base_docker_run = "sudo docker exec {} {} {}"

base_docker_copy = "sudo docker cp {source} {container}:{dest}"


def load_conf(conf_file):
    with open(conf_file, 'r') as f:
        config = json.load(f)
    return config

def log_error(*items):
    print(*items, file=sys.stderr)

def run_command(command):
    print(command)
    return os.WEXITSTATUS(os.system(command))

def run_cmd_docker(docker_name, cmd, flags="-it"):
    if docker_name in NODE_TO_CONTAINER:
        docker_name = NODE_TO_CONTAINER[docker_name]
    final_cmd = base_docker_run.format(flags, docker_name, cmd)
    subprocess.call(final_cmd, shell=True)


def check_output_cmd_docker(docker_name, cmd, flags="-it"):
    if docker_name in NODE_TO_CONTAINER:
        docker_name = NODE_TO_CONTAINER[docker_name]
    final_cmd = base_docker_run.format(flags, docker_name, cmd)
    res = subprocess.check_output(final_cmd, shell=True)
    return res