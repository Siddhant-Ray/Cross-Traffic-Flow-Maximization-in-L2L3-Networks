"""Orchestrate traffic and failure events."""

import argparse
import csv
import shutil
import signal
import time
from os import path
from tempfile import mkdtemp

from p4utils.utils.topology import Topology

from generate_failures import Failures
from generate_traffic import Receivers, Senders
from utils import NODE_TO_CONTAINER


class Orchestrator(object):
    """Load the traffic matrix and generate everything."""
    fieldnames = ["src_name", "dst_name", "src", "dst", "sport", "tos",
                  "dport", "rate", "duration", "packet_size", "start_time"]

    def __init__(self, traffic, failures, db):
        self.topo = Topology(db)
        self.traffic_spec = traffic
        self.failure_spec = failures
        self.failures = {}
        self.senders = {}
        self.receivers = {}

    def start(self):
        """Start senders, receivers, and failures."""
        # We need to parse now, to give everything the same t0 == now
        current_time = time.time()
        self._parse_traffic(self.traffic_spec, current_time)
        self._parse_failures(self.failure_spec, current_time)

        tempdir = mkdtemp()
        sender_configs, receiver_configs = self._create_files(tempdir)

        senders = Senders(sender_configs)
        receivers = Receivers(receiver_configs)
        failures = Failures(self.topo, self.failures)
        try:
            failures.start()
            receivers.start()
            senders.start()

            # Keep track of what we need to kill in case of interrupt etc.
            senders_done = False
            senders.wait()
            senders_done = True
            failures.wait()
        except KeyboardInterrupt:
            # Ignore interrupts while cleaning up.
            handler = signal.signal(signal.SIGINT, signal.SIG_IGN)
            # Cleanup.
            if not senders_done:
                senders.kill()
            failures.kill()
            signal.signal(signal.SIGINT, handler)
        finally:
            # Ignore interrupts while cleaning up.
            handler = signal.signal(signal.SIGINT, signal.SIG_IGN)
            # Receivers do not stop on their own.
            receivers.kill()
            # Clean up files afterwards
            shutil.rmtree(tempdir)
            signal.signal(signal.SIGINT, handler)

    def _parse_traffic(self, matrix, current_time):
        """Parse the traffic matrix into sub-dicts for senders and receivers."""
        self.senders = {}
        self.receivers = {}

        with open(matrix, 'rb') as csvfile:
            dialect = csv.Sniffer().sniff(csvfile.read(1024))
            csvfile.seek(0)
            reader = csv.DictReader(csvfile, dialect=dialect)
            for row in reader:
                # Re-format rows
                row['src_name'] = row['src']
                row['dst_name'] = row['dst']
                row['src'] = self.topo.get_host_ip(row['src'])
                row['dst'] = self.topo.get_host_ip(row['dst'])
                row['start_time'] = current_time + \
                    float(row['start_time'])
                self.senders.setdefault(row['src_name'], []).append(row)
                self.receivers.setdefault(row['dst_name'], []).append(row)

    def _parse_failures(self, failures, current_time):
        """Parse the failure spec file."""
        with open(failures, 'rb') as csvfile:
            dialect = csv.Sniffer().sniff(csvfile.read(1024))
            csvfile.seek(0)
            reader = csv.DictReader(csvfile, dialect=dialect)
            self.failures = next(reader)  # all further lines are ignored.

            # Synchronize time
            self.failures['start_time'] = (
                float(self.failures['start_time']) + current_time)
            self.failures['end_time'] = (
                float(self.failures['end_time']) + current_time)

    def _create_files(self, directory):
        """Create sender and receiver files.

        The files will simply have enumerated names: s0, s1, ...; r0, r1, ... .

        Args:
            directory(str): Directory for all files.
        Returns:
            dict, dict: Mappings of senders/receivers to config files.
        """
        sender_configs = {}
        receiver_configs = {}
        for data, config, prefix in [
            (self.senders, sender_configs, 's'),
            (self.receivers, receiver_configs, 'r')
        ]:
            for index, (host, rows) in enumerate(data.items()):
                filename = path.join(directory, "%s%s" % (prefix, index))
                with open(filename, 'w') as csvfile:
                    writer = csv.DictWriter(
                        csvfile, fieldnames=self.fieldnames)
                    writer.writeheader()
                    writer.writerows(rows)
                config[NODE_TO_CONTAINER[host]] = filename
        return sender_configs, receiver_configs


if __name__ == "__main__":
    # pylint: disable=invalid-name
    parser = argparse.ArgumentParser()
    parser.add_argument('--topo', help='Topo path name',
                        type=str, required=False,
                        default="../build/topology.db")
    parser.add_argument('--traffic-spec',
                        help='Traffic generation specification',
                        type=str, required=True)
    parser.add_argument('--failure-spec',
                        help='Failure generation specification',
                        type=str, required=True)
    args = parser.parse_args()

    orchestrator = Orchestrator(
        args.traffic_spec,
        args.failure_spec,
        args.topo,
    )
    orchestrator.start()
