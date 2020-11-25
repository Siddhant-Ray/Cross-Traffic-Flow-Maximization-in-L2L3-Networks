import sys
import multiprocessing
import threading
import time
from datetime import datetime as dt
import csv
from udp import *


class Scheduler(object):

    def __init__(self, config_file, scheduler_type, log_path="/home/"):

        self.config_file = config_file
        self.scheduler_type = scheduler_type
        self.log_path = log_path

    def load_flows_file(self):
        """[summary]

        Returns:
            [type]: [description]
        """
        flows = []
        with open(self.config_file, 'r') as csvfile:
            dialect = csv.Sniffer().sniff(csvfile.read(1024))
            csvfile.seek(0)
            reader = csv.DictReader(csvfile, dialect=dialect)
            return list(reader)

    def sender_task(self, **kwargs):
        """[summary]
        """

        # sleep until we have to start
        start_time = float(kwargs['start_time'])
        if time.time() > start_time:
            # Note: Do not raise to avoid stacktrace etc.
            print("\033[31mWarning: Invalid start time in the past. This flow won't start. Rerun the experiment\033[31m")
            sys.exit(1)
            return
            
        # wait before starting
        time.sleep(start_time - time.time())

        # sender
        out_file = "{}/sender_{}_{}_{}_{}.txt".format(
            self.log_path, kwargs["src_name"], kwargs["dst_name"], kwargs["sport"], kwargs["dport"])

        print("{time} Flow from {src} to {dst} starting (TOS: {tos}, Volume: {tput})".format(
            time=dt.now().strftime("%T"),
            src=kwargs["src_name"], dst=kwargs["dst_name"],
            tput=kwargs["rate"], tos=kwargs["tos"],
        ), flush=True)
        send_udp_flow(out_file=out_file, **kwargs)
        print("{time} Flow from {src} to {dst} ending".format(
            time=dt.now().strftime("%T"),
            src=kwargs["src_name"], dst=kwargs["dst_name"],
        ), flush=True)

    def receiver_task(self, **kwargs):
        """[summary]
        """

        # start inmediately
        # sender
        out_file = "{}/receiver_{}_{}_{}_{}.txt".format(
            self.log_path, kwargs["src_name"], kwargs["dst_name"], kwargs["sport"], kwargs["dport"])
        recv_udp_flow(kwargs["src"], int(kwargs["dport"]), out_file)

    def main(self):
        """[summary]
        """
        # read flows to schedule
        flows = self.load_flows_file()

        self.processes = []

        if self.scheduler_type == "sender":
            for flow in flows:
                # check if we are indeed the sender
                process = multiprocessing.Process(
                    target=self.sender_task, args=(), kwargs=(flow))
                process.start()
                self.processes.append(process)

        elif self.scheduler_type == "receiver":
            for flow in flows:
                # check if we are indeed the sender
                process = multiprocessing.Process(
                    target=self.receiver_task, args=(), kwargs=(flow))
                process.start()
                self.processes.append(process)

        else:
            print("Wrong scheduler type {}".format(self.scheduler_type))

        for process in self.processes:
            process.join()
            exitcode = process.exitcode
            if exitcode != 0:
                sys.exit(1)


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', help='Path to configuration',
                        type=str, required=False, default='./flows.txt')
    parser.add_argument('--type', help='Sender or receiver',
                        type=str, required=False, default='sender')
    return parser.parse_args()


if __name__ == "__main__":
    import os
    import argparse
    args = get_args()

    # starts the flow scheduling task
    scheduler = Scheduler(args.config, args.type)
    scheduler.main()
