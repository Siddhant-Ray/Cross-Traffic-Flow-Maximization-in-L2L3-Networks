#!/bin/bash

echo "Starts P4 switches..."
sudo python p4-run.py --config configuration.json --topo ../build/topology.db --cmd start

sleep 2

echo "Starts P4 controller..."
python basic_controller_forwarding.py
