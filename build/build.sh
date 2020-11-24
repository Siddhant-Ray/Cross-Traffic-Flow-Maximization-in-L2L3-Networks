#!/bin/bash

p4_opt=${1:-"false"}

# Get the current script directory, no matter where we are called from.
# https://stackoverflow.com/questions/59895/how-to-get-the-source-directory-of-a-bash-script-from-within-the-script-itself
cur_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
platform_dir=$HOME/mini_internet_project/platform/

# Use the p4 branch
echo "Checkout the p4 branch"
git -C $platform_dir checkout .
git -C $platform_dir fetch -u origin p4:p4
git -C $platform_dir checkout p4

# Pull the latest version of the platform
echo "Pull the mini-Internet repository"
git -C $platform_dir pull origin p4

# Pull the latest version of p4-utils
echo "Pull p4-utils repository"
git -C /home/adv-net/p4-tools/p4-utils pull

# Modifying router_config.txt based on whether to use optimized switches or not
if [ "$1" == "--opt" ];then
    echo "Using optimized p4 switch image"
    sed 's/p4switch_container_name/bmv2_simple_switch_opt/g' $cur_dir/topo/router_config_tmp.txt > $cur_dir/topo/router_config.txt
else
    echo "Using non-optimized p4 switch image"
    sed 's/p4switch_container_name/bmv2_simple_switch/g' $cur_dir/topo/router_config_tmp.txt > $cur_dir/topo/router_config.txt
fi

# Building the topology
echo "Copy the configuration files"
cp -r $cur_dir/topo/* $platform_dir/config/

echo "Reset shared directory"
sudo rm -rf /home/adv-net/infrastructure/shared/
mkdir /home/adv-net/infrastructure/shared/

echo "Ensure all images are up to date"
docker pull thomahol/d_adv_net_host
docker pull thomahol/d_router
docker pull thomahol/d_p4
docker pull thomahol/d_p4_opt

echo "Clean-up the mini-Internet currently running (if any)"
(cd $platform_dir; sudo $platform_dir/cleanup/hard_reset.sh)
echo "Run the new mini-Internet"
(cd $platform_dir; sudo $platform_dir/startup.sh)

# Run the default configuration
for c in \
1_R1router:R1.sh \
1_R2router:R2.sh \
1_R3router:R3.sh \
1_R4router:R4.sh
do
    cname=$(echo $c | cut -f 1 -d ':')
    cscript=$(echo $c | cut -f 2 -d ':')

    echo "Configuring $cname using $cscript..."
    sudo docker cp $cur_dir/default_config/routers/$cscript $cname:/home/
    sudo docker exec -it $cname chmod 755 /home/$cscript
    sudo docker exec -it $cname /home/$cscript
    sudo docker exec -it $cname rm /home/$cscript

    sudo docker cp $cur_dir/../utils/udp.py $cname:/home/
done

# Run the default configuration
for c in \
1_S1host:h1.sh \
1_S2host:h2.sh \
1_S3host:h3.sh \
1_S4host:h4.sh \
1_S5host:h5.sh \
1_S6host:h6.sh
do
    cname=$(echo $c | cut -f 1 -d ':')
    cscript=$(echo $c | cut -f 2 -d ':')

    echo "Configuring $cname using $cscript..."
    sudo docker cp $cur_dir/default_config/hosts/$cscript $cname:/home/
    sudo docker exec -it $cname chmod 755 /home/$cscript
    sudo docker exec -it $cname /home/$cscript
    sudo docker exec -it $cname rm /home/$cscript

    # Copy dummy sender/receiver
    sudo docker cp $cur_dir/../utils/schedule_flows.py $cname:/home/
    sudo docker cp $cur_dir/../utils/udp.py $cname:/home/

done

# Run the default configuration
for c in \
1_S1router:S1.sh \
1_S2router:S2.sh \
1_S3router:S3.sh \
1_S4router:S4.sh \
1_S5router:S5.sh \
1_S6router:S6.sh
do
    cname=$(echo $c | cut -f 1 -d ':')
    cscript=$(echo $c | cut -f 2 -d ':')

    echo "Configuring $cname using $cscript..."
    sudo docker cp $cur_dir/default_config/p4switches/$cscript $cname:/home/
    sudo docker exec -it $cname chmod 755 /home/$cscript
    sudo docker exec -it $cname /home/$cscript
    sudo docker exec -it $cname rm /home/$cscript
    sudo docker cp $cur_dir/../utils/udp.py $cname:/home/
done

# Load the topology db
echo "Building Topology.db object..."
(cd $cur_dir ; python ../utils/topodb-build.py --config_dir $cur_dir/topo/)

sudo docker kill 1_ssh >/dev/null
sudo docker rm 1_ssh >/dev/null
