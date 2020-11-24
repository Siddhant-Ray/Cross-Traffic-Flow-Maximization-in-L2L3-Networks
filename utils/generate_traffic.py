"""Start senders and receivers on hosts."""

import sys
import signal
import subprocess
from random import randint

from utils import NODE_TO_CONTAINER


class Hosts(object):
    """A class that manages host subprocesses."""
    cmd = None
    suffix = ""

    workers = []

    def __init__(self, host_configs, expt_id=None):
        """Prepare the hosts.
        Args:
            host_configs (dict):
                Key: hostname, value: file_path
            expt_id (str):
                Id that is used to identify all files belonging
                to this experiment on the host.
        """
        if expt_id is None:
            expt_id = randint(0, 424242)
        self.expt_id = str(expt_id)
        self.host_configs = host_configs

        # Path on the host to use for config files.
        self.config_path = "/var/run/{id}_{suffix}.cfg".format(
            id=self.expt_id, suffix=self.suffix
        )

        # Path for PID files so we can kill the processes.
        self.pid_path = "/var/run/{id}_{suffix}.pid".format(
            id=self.expt_id, suffix=self.suffix
        )

        # Format the command with config path.
        formatted = self.cmd.format(config=self.config_path)

        # Wrap the command to run in bash and save the bash PID first,
        # so we can kill the whole process group later. Killing the group
        # is important, as otherwise child processes can remain.
        self.cmd = "bash -c 'echo $$ > {pid} && {cmd}'".format(
            cmd=formatted,
            pid=self.pid_path
        )
        self.kill_cmd = "bash -c 'kill -- -`cat {pid}`'".format(
            pid=self.pid_path
        )

    def start(self):
        """Copt config files to hosts, start sender script, and wait."""
        self._copy_files()
        if self.workers:
            raise RuntimeError("Processes are already started!")
        args = [(host, self.cmd) for host in self.host_configs]
        self.workers = _exec_parallel(args)

    def wait(self):
        """Wait on all workers, raise for problems."""
        _wait_for_all(self.workers, check=True)
        self._cleanup()

    def kill(self):
        """Kill all processes."""
        # Kill in parallel to avoid wait time.
        args = [(host, self.kill_cmd) for host in self.host_configs]
        workers = _exec_parallel(args)
        _wait_for_all(workers)  # Immediately wait
        self._cleanup()

    def _copy_files(self):
        """Copy files to hosts."""
        args = [(host, config_file_path, self.config_path)
                for host, config_file_path in self.host_configs.items()]
        workers = _copy_parallel(args)
        _wait_for_all(workers)  # Immediately wait

    def _cleanup(self):
        """Remove all config and pid files."""
        # Clean in parallel
        args = [(host, "rm %s" % path)
                for host in self.host_configs
                for path in (self.config_path, self.pid_path)]
        workers = _exec_parallel(args)
        _wait_for_all(workers)  # Immediately wait
        self.workers = []


class Senders(Hosts):
    """Sender Manager."""
    cmd = "python3 /home/schedule_flows.py --config {config} --type sender"
    suffix = "sender"


class Receivers(Hosts):
    """Receiver Manager."""
    cmd = "python3 /home/schedule_flows.py --config {config} --type receiver"
    suffix = "receiver"


# Helpers.
# ========

def _exec_parallel(all_cmds):
    final_cmds = []
    for host, cmd in all_cmds:
        if host in NODE_TO_CONTAINER:
            host = NODE_TO_CONTAINER[host]
        final_cmd = "sudo docker exec {container} {cmd}".format(
            container=host, cmd=cmd,
        )
        final_cmds.append(final_cmd)
    return _start_parallel(final_cmds)


def _copy_parallel(all_cmds):
    final_cmds = []
    for host, source, destination in all_cmds:
        if host in NODE_TO_CONTAINER:
            host = NODE_TO_CONTAINER[host]
        final_cmd = "sudo docker cp {source} {container}:{dest}".format(
            container=host, source=source, dest=destination,
        )
        final_cmds.append(final_cmd)
    return _start_parallel(final_cmds)


def _start_parallel(cmds):
    """Start parallel processes that cannot be interrupted by sigint."""
    original_sigint_handler = signal.signal(signal.SIGINT, signal.SIG_IGN)
    workers = []
    for cmd in cmds:
        worker = subprocess.Popen(cmd, shell=True)
        workers.append(worker)
    signal.signal(signal.SIGINT, original_sigint_handler)
    return workers


def _wait_for_all(workers, check=False):
    """Wait for all workers."""
    for worker in workers:
        worker.wait()
        if check and (worker.returncode != 0):
            # Exit with error, but avoid printing stacktrace.
            sys.exit(1)
