#!/bin/bash

#1. Identify the system's public IP.
echo "[*] Public IP Found:"
curl -s ifconfig.co

#2. Identify the private IP address assigned to the system's network interface.
echo "[*] Private IP Address Found:"
ifconfig | grep broadcast | awk '{print $2}'

#3. Display the MAC address (masking sensitive portions for security).
echo "[*] MAC Address found:"
echo "$(ifconfig | grep ether | awk '{print $2}'|awk -F ':' '{print $1,$2,$3}' | tr ' ' ':'):xx:xx:xx"

#4. Display the percentage of CPU usage for the top 5 processes.
echo "[*] Top Processes:"
ps -eo "pid,%cpu,comm" --sort=-%cpu | head -n6

#Display memory usage statistics: total and available memory.
echo "[*] Memmory:"
memmory=$(free -h | grep Mem)
echo " Total: $(echo $memmory | awk '{print $2}')"
echo " Available: $(echo $memmory | awk '{print $NF}')"

#6.List active system services with their status.
echo "[*] Active services:"
service --status-all | grep -F '[ + ]'

#7. Locate the Top 10 Largest Files in /home.
echo "[*] Top Files:"
du -ha /home 2>/dev/null | sort -n | tail -n10
