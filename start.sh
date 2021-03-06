#!/usr/bin/env bash

error() {
    if [ "$HIDE_ERR" != "true" ]; then
        EXIT_ON_ERR="true"
        local parent_lineno="$1"
        local message="$2"
        local code="${3:-1}"
        if [[ -n "$message" ]]; then
            echo "Error on or near line ${parent_lineno}: ${message}"
        else
            echo "Error on or near line ${parent_lineno}"
        fi
    fi
}

exit_function() {
    echo "Exiting..."
    if [ "$EXIT_ON_ERR" != "false" ]; then
        # Restore and clean
        echo -e "\nKilling the docker container "
        docker kill ${container_id} 2> /dev/null
        if [ "$STAT_IP_RULE_FWMARK" == "true" ]; then
            echo "Cleaning ip rule"
            ip rule del table "$((${serviceID} + 400))"
        fi
    fi
    echo "Good BYE"
}

trap 'error ${LINENO} ' ERR
trap 'exit_function' EXIT INT
latestCont=$(docker ps -a --filter "name=bispudp" --format {{.Names}} | cut -c8- | sort -n -r | head -1)
if [ "$latestCont" == "" ]; then
    latestCont=0
fi
serviceID=${serviceID-$((${latestCont} + 1))}
serviceNet=${serviceNet-"10.0.9"}
container_id=$(docker run -it -d --rm --privileged -e ipv4_port="$ipv4_port" -e ipv4_dst="$ipv4_dst" --name "bispudp$serviceID" ghcr.io/ahmetozer/bypass-isp-udp-proxy:latest)
if [ "$?" != "0" ]; then
    echo "Error while creating bispudp$serviceID "
    exit 1
fi
#docker attach "$container_id" &
NSPID=$(docker inspect --format='{{ .State.Pid }}' "$container_id")

echo -e "
FWMARK=$((${serviceID} + 400)) and Table=$((${serviceID} + 400))
container name bispudp$serviceID
container id $(echo $container_id | cut -c1-12)
container in interface\tpm-in${serviceID} ${serviceNet}.$((${serviceID} * 4 - 3)) \t-->\tpm0 ${serviceNet}.$((${serviceID} * 4 - 2))
container out interface\tpm-out${serviceID} ${serviceNet}.$((${serviceID} * 4 - 1))\t<--\tpm1 ${serviceNet}.$((${serviceID} * 4 ))
"
if [ $? -eq 0 ]; then

    ###
    # Input interface
    ###

    ip link add "pm-in$((${serviceID}))" type veth peer pm0 netns "${NSPID}"
    if [ $? != 0 ]; then
        echo "error while creating pm-in$((${serviceID}))"
        exit 1
    fi

    ip link set "pm-in${serviceID}" up

    if [ $? != 0 ]; then
        echo "error while interface pm-in$((${serviceID})) up"
        exit 1
    fi

    ip addr add "${serviceNet}.$((${serviceID} * 4 - 3))/32" dev "pm-in$((${serviceID}))" > /dev/null
    if [ $? != 0 ]; then
        echo "error while interface pm-in$((${serviceID})) address allocation"
        exit 1
    fi

    ip ro add "${serviceNet}.$((${serviceID} * 4 - 2))/32" dev "pm-in$((${serviceID}))" > /dev/null
    if [ $? != 0 ]; then
        echo "error while route setting  ${serviceNet}.$((${serviceID} * 4 - 3))/32 dev pm-in$((${serviceID}))"
        exit 1
    fi

    docker exec -it --privileged "$container_id" ip link set pm0 up > /dev/null
    if [ $? != 0 ]; then
        echo "error while interface pm0 up in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    docker exec -it --privileged "$container_id" ip addr add "${serviceNet}.$((${serviceID} * 4 - 2))/32" dev pm0 > /dev/null
    if [ $? != 0 ]; then
        echo "error while interface pm0 address allocation in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    docker exec -it --privileged "$container_id" ip ro add "${serviceNet}.$((${serviceID} * 4 - 3))" dev pm0 > /dev/null
    if [ $? != 0 ]; then
        echo "error while route setting in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    docker exec -it --privileged "$container_id" sysctl -w net.ipv4.ip_forward=0 > /dev/null
    if [ $? != 0 ]; then
        echo "error while disabling ip forward $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    HIDE_ERR="true"
    echo -n $(ip rule s lookup "$((${serviceID} + 400))") | grep "$((${serviceID} + 400))" >/dev/null
    if [ "$?" != "0" ]; then
        HIDE_ERR="false"
        ip rule add fwmark "$((${serviceID} + 400))" lookup "$((${serviceID} + 400))" && STAT_IP_RULE_FWMARK=true
        ip ro add default via "${serviceNet}.$((${serviceID} * 4 - 2))" dev "pm-in${serviceID}" table "$((${serviceID} + 400))" && STAT_IP_RO_NS_MAIN=true
    else
        HIDE_ERR="false"
        STAT_IP_RULE_FWMARK=true
        echo "lookup $((${serviceID} + 400)) is not empty"
        exit 1
    fi

    ###
    # Output interface
    ###

    ip link add "pm-out$((${serviceID}))" type veth peer pm1 netns "$NSPID" > /dev/null
    if [ $? != 0 ]; then
        echo "error while creating pm-out$((${serviceID}))"
        exit 1
    fi

    ip link set pm-out$((${serviceID})) up
    if [ $? != 0 ]; then
        echo "error while interface pm-out$((${serviceID})) up"
        exit 1
    fi

    ip addr add "${serviceNet}.$((${serviceID} * 4 - 1))/32" dev "pm-out$((${serviceID}))" > /dev/null
    if [ $? != 0 ]; then
        echo "error while interface pm-out$((${serviceID})) address allocation"
        exit 1
    fi

    ip ro add "${serviceNet}.$((${serviceID} * 4))/32" dev "pm-out$((${serviceID}))" > /dev/null
    if [ $? != 0 ]; then
        echo "error while route setting  ${serviceNet}.$((${serviceID}))/32 dev pm-out$((${serviceID}))"
        exit 1
    fi

    docker exec -it --privileged "$container_id" ip link set pm1 up > /dev/null
    if [ $? != 0 ]; then
        echo "error while interface pm0 up in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    docker exec -it --privileged "$container_id" ip addr add "${serviceNet}.$((${serviceID} * 4))/32" dev pm1 > /dev/null
    if [ $? != 0 ]; then
        echo "error while interface pm0 address allocation in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    docker exec -it --privileged "$container_id" ip ro add "${serviceNet}.$((${serviceID} * 4 - 1))" dev pm1 > /dev/null
    if [ $? != 0 ]; then
        echo "error while route setting in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    ###
    #   Routing
    ###
    default_route="$(docker exec -it --privileged $container_id bash -c 'ip ro | grep default')" 2> /dev/null
    if [ $? != 0 ]; then
        echo "error while getting default route in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    docker exec -it --privileged "$container_id" bash -c "ip ro re default via ${serviceNet}.$((${serviceID} * 4 - 1)) dev pm1" > /dev/null
    if [ $? != 0 ]; then
        echo "error while change default route in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

    docker exec -it --privileged "$container_id" ip addr flush dev eth0  > /dev/null
    if [ $? != 0 ]; then
        echo "error while flushing interface eth0 in container $(echo $container_id | cut -c1-12)"
        exit 1
    fi

fi

echo "Init is done."
#EXIT_ON_ERR="false"
docker attach "$container_id"
