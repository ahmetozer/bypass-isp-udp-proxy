#!/usr/bin/env python3
import sys
import socket
import codecs
import threading
import ipaddress
import os
import netifaces

from random import randrange
from scapy.all import *


def check_interface(interface):
    try:
        # is exist and up
        addr = netifaces.ifaddresses(interface)
        return netifaces.AF_INET in addr
    except:
        return False


def main():
    print('Starting program...')
    err_on_exit = False
    # IPv4
    # Mirror port IPv4
    ipv4_port = os.environ.get('ipv4_port')

    if ipv4_port == None or ipv4_port == "":
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
            print("ipv4_port variable '" +
                  str(ipv4_port) + "' is not a integer.")
            err_on_exit = True

    # Mirror addr IPv4
    ipv4_dst = os.environ.get('ipv4_dst')

    if ipv4_dst == None or ipv4_dst == "":
        print("ipv4_dst is not defined. The fake packet destinatination address will be the same as the original.")
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
        print("Exiting program...")
        exit(1)

    if check_interface("pm0") == False:
        print("Waiting pm0 interface")
        while True:
            time.sleep(1)
            if check_interface("pm0"):
                break

    if check_interface("pm1") == False:
        print("Waiting pm1 interface")
        while True:
            time.sleep(1)
            if check_interface("pm1"):
                break

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
                send(IP(src=ip_src, dst=fake_dst_ip, ttl=pkt[IP].ttl) / UDP(dport=ipv4_port_func(),
                                                                            sport=udp_sport) / pkt[UDP].payload, verbose=False)
                # And after send the actual data
                send(IP(src=ip_src, dst=ip_dst, ttl=pkt[IP].ttl)/UDP(dport=udp_dport,
                                                                     sport=udp_sport) / pkt[UDP].payload, verbose=False)

    sniff(filter="ip and udp and not broadcast and not multicast",
          prn=send_packetIPv4, iface="pm0")


if __name__ == "__main__":
    main()
