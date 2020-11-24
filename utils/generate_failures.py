"""Schedule failure events."""

import os
import random
import signal
import subprocess
import time
from multiprocessing import Process

import networkx as nx


class Failures(object):
    """Failure manager."""
    max_attempts = 100
    workers = []

    def __init__(self, topology, failure_spec):
        self.topo = topology
        # Parse failure spec
        self.num_failures = int(failure_spec['num_failures'])
        self.start_time = float(failure_spec['start_time'])
        self.end_time = float(failure_spec['end_time'])
        self.min_duration = float(failure_spec['min_duration'])
        self.max_duration = float(failure_spec['max_duration'])

        # set random seed
        random.seed(failure_spec['seed'])

        # sub graph with only internal nodes
        self._build_network_subgraph()

        # Plan the link events from the provided spec
        self.link_events = self._get_link_events()

    def start(self):
        """Start failure processes."""
        self.workers = []
        original_sigint_handler = signal.signal(signal.SIGINT, signal.SIG_IGN)
        for event in self.link_events:
            worker = Process(target=_schedule_event, args=(event,))
            worker.start()
            self.workers.append(worker)
        signal.signal(signal.SIGINT, original_sigint_handler)

    def wait(self):
        """Wait for failure processes to finish."""
        for worker in self.workers:
            worker.join()
        self._cleanup()

    def kill(self):
        """Kill failure processes and reset link state."""
        for worker in self.workers:
            if worker.is_alive():
                worker.terminate()
        self._cleanup()

    def _cleanup(self):
        # Ensure that everything is up at the end (if there were any events).
        if self.link_events:
            reset_links()
        self.workers = []

    def _build_network_subgraph(self):
        """Prepare a subgraph of relevant devices."""
        devices = list(self.topo.get_routers().keys()) + \
            list(self.topo.get_switches().keys())
        self.only_devices = self.topo.network_graph.subgraph(devices)
        self.only_devices = self.only_devices.copy()

    # Helpers to compute the failures from spec.
    # ==========================================

    def _get_link_events(self):
        """Get all up/down events for the provided spec."""
        scenario = self._get_failure_scenario()

        events = []
        for link, fail_time, duration in scenario:
            events.append(("down", link, fail_time))
            events.append(("up", link, fail_time+duration))

        return events

    def _get_failure_scenario(self):
        for _ in range(self.max_attempts):
            candidate = self._generate_failure_candidate()
            if self._is_valid_failure_candidate(candidate):
                return candidate
        raise RuntimeError("Could not find a valid failure scenario")

    def _generate_failure_candidate(self):
        links = list(self.only_devices.edges)
        random.shuffle(links)
        links_to_fail = links[:self.num_failures]

        failure_spec = []
        for link in links_to_fail:
            fail_time = random.uniform(self.start_time, self.end_time)
            duration_time = random.uniform(
                self.min_duration, self.max_duration)
            failure_spec.append((link, fail_time, duration_time))

        return sorted(failure_spec, key=lambda x: x[1])

    def _is_valid_failure_candidate(self, failure_spec):
        only_devices = self.only_devices.copy()
        all_events = self._get_events_and_time(failure_spec)

        # check if the network remains connected at any time
        for _, events in all_events:
            for action, edge in events:
                if action == "down":
                    only_devices.remove_edge(*edge)
                elif action == "up":
                    only_devices.add_edge(*edge)

            # check if connected
            if not nx.algorithms.components.is_connected(only_devices):
                return False
        return True

    def _get_events_and_time(self, failure_spec):
        events = {}
        for failure in failure_spec:
            edge, fail, duration = failure

            if fail in events:
                events[fail].append(('down', edge))
            else:
                events[fail] = [('down', edge)]

            if fail+duration in events:
                events[fail+duration].append(('up', edge))
            else:
                events[fail+duration] = [('up', edge)]

        return sorted(events.items(), key=lambda x: x[0])


# Failure_script_helpers.
# =======================


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FAILURE_SCRIPT = os.path.join(SCRIPT_DIR, 'failure.sh')


def set_link_state(device1, device2, state):
    """Set a link between device1 and device2 to 'up' or 'down'."""
    subprocess.check_call(["sudo", FAILURE_SCRIPT, state, device1, device2])


def reset_links():
    """Set all links to up."""
    subprocess.check_call(["sudo", FAILURE_SCRIPT, "upall"])


def _schedule_event(event):
    """Sleep (if needed) until event time, then execute it."""
    state, (device1, device2), event_time = event
    diff = event_time - time.time()
    if diff > 0:
        time.sleep(diff)
    set_link_state(device1, device2, state)
