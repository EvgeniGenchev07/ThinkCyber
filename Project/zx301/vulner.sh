#!/bin/bash

#Name: Evgeni Genchev
#Student code: s5
#Class code: TCB-2511
#Lecture's name: Ivan Blagoev
#
#
#The functionalities, that I added are:
# - Web scan with nikto
# - Scans converted to html
# - Scanning, BF and Logging into multiple threads
#Protocols fo brute-forcing

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

#Asks for a directory and creates it if it doesn't exist
function VLDT_DIR(){
	read -p "[?] Choose directory for the results: " DIR
	if [ ! -d "$DIR" ];
	then
		echo "[+] Directory created"
		mkdir -p "$DIR"
		mkdir "$DIR/creds"
		mkdir "$DIR/scan"
		mkdir "$DIR/html"
		if [[ "$SCN" == "F" ]]
		then
			mkdir "$DIR/vulns"
		fi
	fi
}
#Asks for a password file for BF, if empty default one is used, checks if the path exists otherwise it stopes
function VLDT_PASS(){
	read -p "[?] Choose password list: " PASS
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
	read -p "[?] Choose user list: " USR
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
			echo "$hdr_data" >> "$DIR/creds/$3"
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
#Checks if the host is up or down, if it is up starts the bf in basic mode or search for vulnerabilities and then starts the bf in full mode
#Parameters: $1: IP; $2: Nmap results
function HOST_CHK(){
	if [ -n "$(echo "$2" | grep "0 hosts up")" ]
	then
		echo "[*] Host $1 is down"
	else
		echo "$report"
		
		if [[ "$SCN" == "F" ]]
		then
			echo "[*] Searching for vulnerabilities in Exploit-DB..."
			#searchsploit=$(searchsploit -v -w --nmap "$DIR/scan/$1.scn" 2>&1)
			#echo "$searchsploit" 
			#echo "$searchsploit" > "$DIR/vulns/$1.vulns"
			searchsploit -v -w --nmap "$DIR/scan/$1.scn" | tee -a "$DIR/vulns/$1.vulns"
			http_ports=$(echo "$report" | grep -w "open"  | grep "http" | awk -F '/' '{print $1}')
			for i in $http_ports
			do
				echo "[*] Scaning web port: $i at $1..."
				nikto -host "$1" -port "$i" | tee -a "$DIR/vulns/$1.vulns"
			done
		fi
		BF_MAIN "$report" "$1"
	fi
}
#Converts the xml nmap scans to html
#Parameters: $1: IP
function TO_HTML(){
	xsltproc "$DIR/scan/$1.scn" > "$DIR/html/$1.html"
}
#The basic scan scans for open UDP/TCP ports and service versions every IP, exports the results to xml file, then converts to html and starts the host checking
#Parameters: $1: IP
function BSC_SCN(){
	echo "[*] Scanning $1..."
	report=$(sudo nmap "$1" -p- -sS -sU -sV -oX "$DIR/scan/$1.scn")
	TO_HTML "$1"
	HOST_CHK "$1" "$report"
}
#The full scan scans for open UDP/TCP ports, service versions and vulnerabilities every IP, exports the results to xml file, then converts to html and starts the host checking
#Parameters: $1: IP
function FULL_SCN(){
	echo "[*] Scanning $1..."
	report=$(sudo nmap "$1" -p- -sU -sS -sV -oX "$DIR/scan/$1.scn" --script=vuln --reason)
	TO_HTML "$1"
	HOST_CHK "$1" "$report"
}
#The main functions that executes the validate functions and goes throughout every ip and executes the scan function when a thread is free
#Parameters: $1: Func
function MAIN(){
	VLDT_IP
	VLDT_DIR
	VLDT_USR
	VLDT_PASS
	for ip in $resolved;do
		"$1" $ip &
		#Doesn't allow to start more threads than requested
		while (($(jobs -r | wc -l) >= 4)); do
			sleep 0.1
		done
	done
}
read -p "[?] Choose scan type [B]asic or [F]ull: " SCN
#Chooses the scan type, on wrong input the program exits
case $SCN in

B|b)
	echo "[*] Starting Basic scan..."
	MAIN BSC_SCN
;;
F|f)
	SCN="F"
	MAIN FULL_SCN
;;
*)
	echo "[-] Wrong input"
	exit 0
;;
esac

#Waits for the program to finish all threads
wait
echo "Scan completed"	

read -p "Select name for the archive ([Enter] to skip): " ARCH
#Archives the data if the user has given a name otherwise it is skipped
if [ -n "$ARCH" ] 
then
	zip "$ARCH" -r "$DIR"
fi
exit 0
