#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

type=$1
device1=$2
device2=$3
linkname="$2--$3"

function tstr
{
    printf "$(date +%T)"
}

print_help () {
    echo "Usage: ./failure.sh [up/down/upall] [DEVICE1] [DEVICE2]"
    echo ""
    echo "This script turns up or down the link between DEVICE1 and DEVICE2. "
    echo "To restore *all* the links, use upall. In this case you must not specify DEVICE1 and DEVICE2."
    echo "Devices can be R1 R2 R3 R4 S1 S2 S3 S4 S5 S6."
    exit
}

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
platform_dir=$HOME/mini_internet_project/platform/

if [ "$type" == "down" ]; then

    if [ "$#" -ne 3 ]; then
        print_help
    fi

    failed=0
    while IFS=" " read -r ovsname d1 d1_intfname ovs1_intfname d2 d2_intfname ovs2_intfname
    do
        if ([ "1_${device1}router" == "$d1" ] && [ "1_${device2}router" == "$d2" ]) || ([ "1_${device2}router" == "$d1" ] && [ "1_${device1}router" == "$d2" ]);then
            port_id1=$(ovs-vsctl get Interface ${ovs1_intfname} ofport)
            port_id2=$(ovs-vsctl get Interface ${ovs2_intfname} ofport)

            sudo ovs-ofctl del-flows $ovsname in_port=$port_id1
            sudo ovs-ofctl del-flows $ovsname in_port=$port_id2
            sudo ovs-ofctl add-flow $ovsname in_port=$port_id1,actions=drop
            sudo ovs-ofctl add-flow $ovsname in_port=$port_id2,actions=drop
            failed=1
        fi
    done < ${platform_dir}/groups/link_info.txt

    if [ "$failed" == "0" ]; then
        echo "$(tstr) No link was failed: the link $linkname does not exist."
    else
        echo "$(tstr) Link $linkname failed"
    fi

elif [ "$type" == "up" ]; then

    if [ "$#" -ne 3 ]; then
        print_help
    fi

    up=0
    while IFS=" " read -r ovsname d1 d1_intfname ovs1_intfname d2 d2_intfname ovs2_intfname
    do
        if ([ "1_${device1}router" == "$d1" ] && [ "1_${device2}router" == "$d2" ]) || ([ "1_${device2}router" == "$d1" ] && [ "1_${device1}router" == "$d2" ]);then
            port_id1=$(ovs-vsctl get Interface ${ovs1_intfname} ofport)
            port_id2=$(ovs-vsctl get Interface ${ovs2_intfname} ofport)

            sudo ovs-ofctl del-flows $ovsname in_port=$port_id1
            sudo ovs-ofctl del-flows $ovsname in_port=$port_id2
            sudo ovs-ofctl add-flow $ovsname in_port=$port_id1,actions=output:$port_id2
            sudo ovs-ofctl add-flow $ovsname in_port=$port_id2,actions=output:$port_id1
            up=1
        fi
    done < ${platform_dir}/groups/link_info.txt

    if [ "$up" == "0" ]; then
        echo "$(tstr) No link was restored: the link $linkname does not exist."
    else
        echo "$(tstr) Link $linkname restored"
    fi

elif [ "$type" == "upall" ]; then

    if [ "$#" -ne 1 ]; then
        print_help
    fi

    while IFS=" " read -r ovsname d1 d1_intfname ovs1_intfname d2 d2_intfname ovs2_intfname
    do
        port_id1=$(ovs-vsctl get Interface ${ovs1_intfname} ofport)
        port_id2=$(ovs-vsctl get Interface ${ovs2_intfname} ofport)

        sudo ovs-ofctl del-flows $ovsname in_port=$port_id1
        sudo ovs-ofctl del-flows $ovsname in_port=$port_id2
        sudo ovs-ofctl add-flow $ovsname in_port=$port_id1,actions=output:$port_id2
        sudo ovs-ofctl add-flow $ovsname in_port=$port_id2,actions=output:$port_id1
    done < ${platform_dir}/groups/link_info.txt

    echo "All links are up"

else
    print_help
fi
