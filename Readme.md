# Bypass ISP UDP MiTM Proxy

This repository was created to bypass ISP's MiTM proxy. You can access blog post from [https://ahmetozer.org/Bypass-ISP-UDP-proxy.html](https://ahmetozer.org/Bypass-ISP-UDP-proxy.html)

## Work logic

The program catches incoming packets, then firstly generates a packet with the same source information but destination port and IP depends on the configuration. 
After artificial packet creation, the system re-creates the original packet and sends it out.

## Installation

System runs on docker containers but for preparing the environment, the system also requires start.sh script and runs outside of the container.

```bash
# Get init script
wget https://raw.githubusercontent.com/ahmetozer/bypass-isp-udp-proxy/master/start.sh
# Apply executable permission to bash script.
chmod +x start.sh
# Get the docker container.
docker pull ghcr.io/ahmetozer/bypass-isp-udp-proxy:latest
```

You can start service with executing the ./start.sh  file. If you don't make any configuration, by default the system uses the same destination ip address and random port between 30000 and 40000. You can define a custom destination address, port  or both by setting `ipv4_port` and `ipv4_dst` environment variables.

```bash
# Normal execution
./start.sh 

# custom destination address for first packet
ipv4_dst=”198.51.100.86” ./start.sh

# custom destination address and port for first packet
ipv4_dst=”198.51.100.86” ipv4_dst=”443” ./start.sh
```

![System ready to handle requests](/init.jpg)

After the system is ready to handle requests, you can forward packets with iptables to the system.

```bash
# Forward incoming request to container.
iptables -t mangle -A PREROUTING -i eth0 -p udp -m conntrack --ctstate NEW -m udp --dport 53 -j TEE --gateway 10.0.9.2
# Drop the first packet which is not generated from the container.
iptables -t mangle -A PREROUTING -i eth0 -p udp -m conntrack --ctstate NEW -m udp --dport 53 -j DROP
```
