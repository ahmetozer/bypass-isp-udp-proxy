#!/usr/bin/env python3
import random
import sys
import socket
import codecs
import threading
import ipaddress
import os
from random import randrange


from scapy.all import *

err_on_exit = False
# IPv4 
## Mirror port IPv4
ipv4_port = os.environ.get('ipv4_port')

if ipv4_port == None:
    print("IPv4 port is not found, it will be randomly generated.")

    def ipv4_port_func():
        return randrange(10000)+30000
else:
    try:
        ipv4_port = int(ipv4_port)
        if 0 <= ipv4_port <= 65353:
            def ipv4_port_func():
                return ipv4_port
            print("ipv4_port=" + str(ipv4_port))
        else:
            print("ipv4_port variable '" +
                  str(ipv4_port) + "' is not in port range.")
            err_on_exit = True
    except:
        print("ipv4_port variable '" + str(ipv4_port) + "' is not a integer.")
        err_on_exit = True

## Mirror addr IPv4
ipv4_dst = os.environ.get('ipv4_dst')

if ipv4_dst == None:
    print("ipv4_dst is not defined. Fake packet destinatination address it will be the same as original.")
else:
    try:
        socket.inet_aton(ipv4_dst)
        ipv4_dst = str(ipaddress.ip_address(socket.inet_aton(ipv4_dst)))
        print("ipv4_dst="+ipv4_dst)
    except:
        print("ipv4_dst variable '" + str(ipv4_dst) +
              "' is not valid IP address.")
        err_on_exit = True

if err_on_exit:
    exit(1)


def send_packetIPv4(pkt):
    if IP in pkt:
        ip_src = pkt[IP].src
        ip_dst = pkt[IP].dst
        if UDP in pkt:
            udp_sport = pkt[UDP].sport
            udp_dport = pkt[UDP].dport

            # Open socket for different port
            if ipv4_dst == None:
                fake_dst_ip = ip_dst
            else:
                fake_dst_ip = ipv4_dst
            send(IP(src=ip_src, dst=fake_dst_ip, ttl=128) / UDP(dport=ipv4_port_func(),
                                                                sport=udp_sport) / pkt[UDP].payload, verbose=False)
            # And after send the actual data
            send(IP(src=ip_src, dst=ip_dst, ttl=128)/UDP(dport=udp_dport,
                                                         sport=udp_sport) / pkt[UDP].payload, verbose=False)


sniff(filter="ip and udp and not broadcast and not multicast",
      prn=send_packetIPv4, iface="eth0")
