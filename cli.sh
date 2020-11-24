#!/bin/bash

set -eu  # Implicit exit code 1 if a command fails, error on unset vars (-u).

helpstr=$(cat << EOM
Usage: cli.sh [FLAGS] COMMAND [ARGS...]

Main commands:
run-pipeline [t] [f]        Run everything from build over config to scenario.
run-pipeline-dry [t]        Run everything *except* traffic or failures.
list-scenarios              Show all available traffic and failure scenarios.
access [node] [cmd...]      Access node. If no cmd is given, open default shell.
monitor                     Print the bit rate of each link in real time.

Commands to run individual steps of the pipeline:
build                       Build the project topology.
cleanup                     Cleans the project topology.
install-requirements        Install python requirements.
configure-nodes             Send configuration commands to router and switch nodes.
start-switches              Compile the p4 programs and start all switches.
run-controller [t]          Run the controller.
run-scenario [t] [f]        Generate traffic and failures.

Additional management commands:
stop-switches               Stop all p4 switches.
reboot-switches             Reboot all p4 switches.

Arguments:
[t]             Traffic scenario name. See list-scenarios.
[f]             Failure scenario name. See list-scenarios.
[node]          Node name, e.g. H1, S1 or R1. Capitalization does not matter.
[cmd...]        Any command(s) and arguments.

Flags:
--no-opt        Do *not* use optimized p4 switches (build).
--pcap          Enable pcap for non-optimized p4 switches (start-switches).
--debug-conf    Configure nodes sequentially, printing output (configure-nodes).
EOM
)

# EXIT CODES
# 0 Success.
# 1 Unexpected error.
# 2 User error (bad config, controller, p4 code).
# 3 Input error (wrong paths etc.)
error=1
usererror=2
ioerror=3

# Declare a map of shortcuts for easier access.
# Associative arrays in bash: https://stackoverflow.com/a/3467959
declare -A shortcuts=(
    # Shortcut: container name
    ["r1"]="1_R1router"
    ["r2"]="1_R2router"
    ["r3"]="1_R3router"
    ["r4"]="1_R4router"
    ["s1"]="1_S1router"
    ["s2"]="1_S2router"
    ["s3"]="1_S3router"
    ["s4"]="1_S4router"
    ["s5"]="1_S5router"
    ["s6"]="1_S6router"
    ["h1"]="1_S1host"
    ["h2"]="1_S2host"
    ["h3"]="1_S3host"
    ["h4"]="1_S4host"
    ["h5"]="1_S5host"
    ["h6"]="1_S6host"
)


# Check for special flags and remove them from argument list.
p4flags="--log"
buildflags="--opt"
confflags=""
while getopts ":-:" opt; do
    # $opt can only be -, so we look at ${OPTARG}
    case ${OPTARG} in
        pcap) p4flags="$p4flags --pcap" ;;
        no-opt) buildflags="" ;;
        debug-conf) confflags="$confflags --debug" ;;
    esac
done
shift $((OPTIND -1))

# Check if enough non-opts are left.
if [ $# -lt 1 ]; then
    echo "$helpstr"
    exit $ioerror
fi

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# All config will be taken from this directory
config_dir="$cur_dir/configuration"

# Traffic and failure scenarios will be taken form this directory
scenario_dir="$cur_dir/scenarios"
default_scenario="default"

# Functions pointing the the individual scripts.

function clean
{
    $cur_dir/build/cleanup.sh
}

function build
{
    $cur_dir/build/build.sh $buildflags
}

function monitor
{
    python2 $cur_dir/utils/monitoring.py
}

function install-requirements
{
    # We know that python2.7 is soon deprecated, hide warning.
    sudo pip2 --no-cache-dir install -r $config_dir/requirements.txt 2>&1 | grep -v "DEPRECATION"
}

function p4run
{
    topo="$cur_dir/build/topology.db"
    (cd $cur_dir/utils && sudo python2 p4-run.py --cmd $1 --topo=$topo $p4flags)
}

function start-switches
{
    # Return 2 if start with user provided code causes issues.
    { p4run stop || return $error ; } && { p4run start || return $usererror ; }
}

function controller
{
    if [ $# -ne 1 ]; then
        traffic="default"
    else
        traffic=$1
    fi
    trafficpath="$scenario_dir/${traffic}.traffic"
    topo="$cur_dir/build/topology.db"

    if ! [ -f $trafficpath ]; then
        echo "Traffic scenario '$traffic' does not exist!"
        return $ioerror
    fi

    (cd $config_dir && sudo python2 controller.py --topo=$topo --traffic=$trafficpath) || return $usererror
}

function configure  # routers/p4switches RX
{
    container="1_$2router"
    script="$2.sh"
    full_script="${config_dir}/$1/$script"

    if [ -f $full_script ]; then
        echo "Configuring \`$container\` using \`$script\`"
        sudo docker cp $full_script $container:/home/
        sudo docker exec -t $container chmod 755 /home/$script
        sudo docker exec -t $container /home/$script || return $usererror
    else
        return $ioerror
    fi
}

function configure-nodes
{
    echo "Configuring nodes"
    declare -a pids
    if [[ $confflags == *"--debug"* ]]; then
        opt=""
    else
        # Run in background to avoid blocking, hide output.
        opt='> /dev/null & pids+=($!)'
    fi
    for router in R1 R2 R3 R4; do
        eval "configure routers $router $opt"
    done
    for switch in S1 S2 S3 S4 S5 S6; do
        eval "configure p4switches $switch $opt"
    done
    for pid in "${pids[@]}"; do
        # Return usererror if any command failed
        wait $pid || return $usererror
    done
}

function run
{
    if [ $# -ne 0 ] && [ $# -ne 2 ]; then
        echo "Usage: cli.sh run-scenario [traffic-spec] [failure-spec]"
        echo
        echo "Both specs can be filenames (without extension) in 'scenarios'."
        echo "Default spec 'default' uses the files 'default.traffic' and 'default.failures'."
        echo "If you provide arguments, you must provide both traffic and failure spec."
        return $ioerror
    fi
    if [ $# -eq 0 ]; then
        traffic=$default_scenario
        failure=$default_scenario
    else
        traffic=$1
        failure=$2
    fi
    trafficpath="$scenario_dir/${traffic}.traffic"
    failurepath="$scenario_dir/${failure}.failure"
    topo="$cur_dir/build/topology.db"

    if ! [ -f $trafficpath ]; then
        echo "Scenario '$traffic' does not exist!"
        return $ioerror
    fi
    if ! [ -f $failurepath ]; then
        echo "Scenario '$failure' does not exist!"
        return $ioerror
    fi

    echo "Running traffic scenario '$traffic' with failure scenario '$failure'"
    # Run orchestrate with nice -20 -> most favorable scheduling.
    (cd $cur_dir/utils && sudo nice -n -20 python2 orchestrate.py --topo=$topo --traffic-spec=$trafficpath --failure-spec=$failurepath)

    # Check run performance 
    (cd $cur_dir/utils &&  python performance.py --traffic-spec=$trafficpath)   
}

function pipeline
{
    # Preparation
    build
    install-requirements
    start-switches

    # Controller and router config is loaded at the same time as the scenario.
    # They have a few seconds to converge before traffic actually starts.
    run $@ & runpid=$!
    controller $@ & controllerpid=$!
    configure-nodes & configpid=$!

    wait $runpid || return $error
    wait $configpid || return $usererror
 
    # The controller might loop -> kill it if it's still running.
    if ! kill $controllerpid > /dev/null 2>&1; then
        # Controller was not running, check output code to see if it crashed.
        wait $controllerpid || return $usererror
    fi
}

function pipeline-dry
{
    # Preparation
    build
    install-requirements
    start-switches

    # Without traffic, we can just run things after another, and end with controller in case it keeps running in a loop.
    configure-nodes
    controller $@
}

function access
{
    if [ $# -lt 1 ]; then
        echo "Usage: cli.sh access node [cmds...]."
        echo "You must at least specify a node, and optionally commands to run."
        return 1
    fi

    # Get container name and default command
    lowercase="$(echo $1 | tr '[:upper:]' '[:lower:]')"
    container="${shortcuts[$lowercase]}"
    case $container in
        1_R*router) cmd=vtysh ;;
        1_S*router) cmd=bash ;;
        1_S*host) cmd=bash ;;
    esac

    # Fallback
    if [ -z $container ]; then
        echo "\`$1\` is not valid shortcut. Using it as container name..."
        echo "(For shortcuts, use \"R1, S1, H1, ...\")"
        container=$1
        cmd=bash
    fi

    # Execute provided or default command.
    if [ $# -lt 2 ]; then
        # Use default command
        sudo docker exec -it $container $cmd
        return
    fi

    # Use provided command instead
    sudo docker exec -it $container ${@: 2}
}

function list-scenarios
{
    echo "Traffic scenarios:"
    basename -s .traffic -a $(ls $scenario_dir/*.traffic)
    echo
    echo "Failure scenarios:"
    basename -s .failure -a $(ls $scenario_dir/*.failure)
}

# Actually do something :)

case $1 in
    "build") build ;;
    "cleanup") clean ;;
    "monitor") monitor ;;
    "install-requirements") install-requirements ;;
    "configure-nodes") configure-nodes ;;
    "start-switches") start-switches ;;
    "stop-switches") p4run stop ;;
    "reboot-switches") p4run reboot ;;
    "run-controller") controller ${@:2} ;;
    "run-scenario") run ${@:2} ;;
    "run-pipeline") pipeline ${@:2} ;;
    "run-pipeline-dry") pipeline-dry ${@:2} ;;
    "list-scenarios") list-scenarios ;;
    "access") access ${@:2} ;;
    *)
        echo "$helpstr"
        exit 1
        ;;
esac
