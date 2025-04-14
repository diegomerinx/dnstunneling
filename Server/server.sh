#!/bin/bash

[ "$UID" -eq 0 ] || exec sudo "$0" "$@"

domain="$1"

sysctl -w net.ipv4.ip_forward=1

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i dns0 -o eth0 -j ACCEPT
iptables -A FORWARD -i eth0 -o dns0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iodined -f -c -p 53 -P password 10.0.0.1 $domain
