#!/usr/bin/env bash

error() {
    local parent_lineno="$1"
    local message="$2"
    local code="${3:-1}"
    if [[ -n "$message" ]]; then
        echo "Error on or near line ${parent_lineno}: ${message}"
    else
        echo "Error on or near line ${parent_lineno}"
    fi
}
dkill() {
    echo "killing the docker container "
    docker kill ${container_id}
    exit 1
}

trap 'error ${LINENO}' ERR
pmID=${pmID-"1"}
pmNet=${pmNet-"10.0.9"}
container_id=$(docker run -it -d --rm --privileged --name "packetMirror$pmID" ahmetozer/bypass-isp-udp-proxy)
NSPID=$(docker inspect --format='{{ .State.Pid }}' "$container_id")

if [ $? -eq 0 ]; then

    ###
    # Input interface
    ###

    ip link add pm-in$((${pmID})) type veth peer pm0 netns "${NSPID}"
    if [ $? != 0 ]; then
        echo "error while creating pm-in$((${pmID}))"
        dkill
    fi

    ip link set "pm-in${pmID}" up

    if [ $? != 0 ]; then
        echo "error while interface pm-in$((${pmID})) up"
        dkill
    fi

    ip addr add "${pmNet}.$((${pmID} * 4 - 3))/32" dev "pm-in$((${pmID}))"
    if [ $? != 0 ]; then
        echo "error while interface pm-in$((${pmID})) address allocation"
        dkill
    fi

    ip ro add "${pmNet}.$((${pmID} * 4 - 2))/32" dev "pm-in$((${pmID}))"
    if [ $? != 0 ]; then
        echo "error while route setting  ${pmNet}.$((${pmID} * 4 - 3))/32 dev pm-in$((${pmID}))"
        dkill
    fi

    docker exec -it --privileged "$container_id" ip link set pm0 up
    if [ $? != 0 ]; then
        echo "error while interface pm0 up in container $(echo $container_id | cut -c1-12)"
        dkill
    fi

    docker exec -it --privileged "$container_id" ip addr add ${pmNet}.$((${pmID} * 4 - 2))/32 dev pm0
    if [ $? != 0 ]; then
        echo "error while interface pm0 address allocation in container $(echo $container_id | cut -c1-12)"
        dkill
    fi

    docker exec -it --privileged "$container_id" ip ro add ${pmNet}.$((${pmID} * 4 - 3)) dev pm0
    if [ $? != 0 ]; then
        echo "error while route setting in container $(echo $container_id | cut -c1-12)"
        dkill
    fi

    docker exec -it --privileged "$container_id" sysctl -w net.ipv4.ip_forward=0
    if [ $? != 0 ]; then
        echo "error while disabling ip forward $(echo $container_id | cut -c1-12)"
        dkill
    fi

    ip rule s lookup "$((${pmID} + 400))" | grep " "
    if [ "$?" == "0" ]; then
        ip rule add fwmark "$((${pmID} + 400))" lookup "$((${pmID} + 400))"
        ip ro add default via 10.0.9.2 dev "pm-in${pmID}" table "$((${pmID} + 400))"
    else
        echo "lookup $((${pmID} + 400)) is not empty"
    fi

    ###
    # Output interface
    ###

    ip link add pm-out$((${pmID})) type veth peer pm1 netns $NSPID
    if [ $? != 0 ]; then
        echo "error while creating pm-out$((${pmID}))"
        dkill
    fi

    ip link set pm-out$((${pmID})) up

    if [ $? != 0 ]; then
        echo "error while interface pm-out$((${pmID})) up"
        dkill
    fi

    ip addr add ${pmNet}.$((${pmID} * 4 - 1))/32 dev "pm-out$((${pmID}))"
    if [ $? != 0 ]; then
        echo "error while interface pm-out$((${pmID})) address allocation"
        dkill
    fi

    ip ro add ${pmNet}.$((${pmID} * 4))/32 dev "pm-out$((${pmID}))"
    if [ $? != 0 ]; then
        echo "error while route setting  ${pmNet}.$((${pmID}))/32 dev pm-out$((${pmID}))"
        dkill
    fi

    docker exec -it --privileged "$container_id" ip link set pm1 up
    if [ $? != 0 ]; then
        echo "error while interface pm0 up in container $(echo $container_id | cut -c1-12)"
        dkill
    fi

    docker exec -it --privileged "$container_id" ip addr add ${pmNet}.$((${pmID} * 4))/32 dev pm1
    if [ $? != 0 ]; then
        echo "error while interface pm0 address allocation in container $(echo $container_id | cut -c1-12)"
        dkill
    fi

    docker exec -it --privileged "$container_id" ip ro add "${pmNet}.$((${pmID} * 4 - 1))" dev pm1
    if [ $? != 0 ]; then
        echo "error while route setting in container $(echo $container_id | cut -c1-12)"
        dkill
    fi

    ###
    #   Routing
    ###
    default_route="$(docker exec -it --privileged $container_id bash -c 'ip ro | grep default')"
    if [ $? != 0 ]; then
        echo "error while getting default route in container $(echo $container_id | cut -c1-12)"
        dkill
    fi

    docker exec -it --privileged "$container_id" bash -c "ip ro re default via ${pmNet}.$((${pmID} * 4 - 1)) dev pm1"
    if [ $? != 0 ]; then
        echo "error while change default route in $(echo $container_id | cut -c1-12)"
        dkill
    fi

fi

docker attach "$container_id"
