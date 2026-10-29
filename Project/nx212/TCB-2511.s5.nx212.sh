#!/bin/bash

#Name: Evgeni Genchev
#Student code: s5
#Class code: TCB-2511
#Lecture's name: Ivan Blagoev
#
#
#The functionalities, that I added are:
# - Support for folder analyze
# - Credentials dump if it is a windows image

# The tools for installation
TOOLS="foremost bulk_extractor strings impacket-secretsdump"
# The download link for vol2
VOL_URL="https://github.com/volatilityfoundation/volatility/releases/download/2.6.1/volatility_2.6_lin64_standalone.zip"
#String search words
STR_WRD="exe http @ password username"


# A function for search of human readable by a keyword
function STR(){
	for i in $STR_WRD
	do
		strings "$1" | grep -i "$i" > "$2/strings/strings_$i"
	done
}

# A function to carve the data from a file usin bulk and foremost
function CARVE(){
	foremost -i "$1" -t all -o "$2/carve" > /dev/null
	bulk_extractor -o "$2/carve" "$1" > /dev/null
	
	if [ -f "$2/carve/packets.pcap" ]
	then
		echo "[+] Network traffic extracted to $2/carve/packets.pcap [size: $(ls $2/carve/packets.pcap -lh | awk '{print $5}')]"
	fi
}

# A function that uses vol to get the active connections, processes and registries
function VOL(){
	profile=$(/usr/local/bin/vol2 -f "$1" imageinfo 2> /dev/null | grep "Suggested Profile")
	if [ -z "$(echo "$profile" | grep "No suggestion")" ]
	then
		profile=$(echo "$profile" | awk '{print $4}' | tr -d ',')
		/usr/local/bin/vol2 -f "$1" --profile="$profile" pslist 2> /dev/null | tee -a "$2/volatility/processes"
		/usr/local/bin/vol2 -f "$1" --profile="$profile" connections 2> /dev/null | tee -a "$2/volatility/connections"
		/usr/local/bin/vol2 -f "$1" --profile="$profile" dumpregistry -D "$2/volatility/registryies" 2> /dev/null
	else
		echo "[-] Volatility failed no profile"
	fi
	
}
# Function which installs dependency
# It takes the name of the dependency as an argument
function install(){
	echo "Installing missing dependency: $1"
	sudo apt install "$1" -y > /dev/null 2>&1
	if [ $? -ne 0 ]
	then
		echo "Unable to install missing dependency: $1"
		exit 1
	else
		echo "Missing dependency installed: $1"
	fi
}
# Checks for missing tools and installs them if there are any
function MISS_DPDNC(){
	for tool in $TOOLS; do
		if ! command -v "$tool" > /dev/null 2>&1
		then
			if [ "$tool" == "impacket-secretsdump" ]
			then
				install "python3-impacket"
			else
				install "$tool"
			fi	
		fi
	done
	if [ -z "$(vol2 2>&1)" ] 
	then
		wget "$VOL_REF" -q -P /tmp > /dev/null 2>&1
		unzip /tmp/volatility_2.6_lin64_standalone.zip -d /tmp/ > /dev/null 2>&1
		sudo mv /tmp/volatility_2.6_lin64_standalone/volatility_2.6_lin64_standalone /usr/local/bin/vol2 > /dev/null 2>&1
		sudo rm -rf /tmp/volatility_2.6_lin64_standalone* > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			echo "Unable to install missing dependency: vol2"
			exit 1
		else
			echo "Missing dependency installed: vol2"
		fi
	fi
}

#Asks for a directory and creates it if it doesn't exist
function VLDT_DIR(){
	read -p "[?] Choose directory for the results: " DIR
	if [ ! -d "$DIR" ];
	then
		echo "[+] Directory created"
		mkdir -p "$DIR"
	fi
}

# Creates the necessary directories for every file
function CRT_DIR(){
	mkdir "$1"
	mkdir "$1/creds"
	mkdir "$1/strings"
	mkdir "$1/volatility"
}

# The main functions that calls the other functions and also tries to extract secrets
function MAIN(){
	CRT_DIR $2
	echo "[*] Starting to carve..."
	CARVE "$1" "$2"
	echo "[*] Starting to search for human readable..."
	STR "$1" "$2"
	echo "[*] Starting to extract with volatility..."
	VOL "$1" "$2"
	if [ -f "$2/volatility/registryies/SAM" ] || [ -f "$2/volatility/registryies/SYSTEM" ]
	then
		echo "[+] Dumping SAM secrets: " 
		impacket-secretsdump -sam "$2/volatility/registryies/SAM" -system "$2/volatility/registryies/SYSTEM" | tee -a "$2/creds/secrets"
	fi
}

# Checks if the program was ran as root
if [ "$(whoami)" != "root" ]
then
	echo "[-] Run as root to continue"
	exit 0
fi

MISS_DPDNC
# Gets the current UTC time
date=$(date -u)
read -p "[?] Select a file or a folder: " REF
# Checks if the referece is a file or a folder
if [ -d "$REF" ]
then
	VLDT_DIR
	for i in $(find "$REF" -maxdepth 1 -type f)
	do
		MAIN "$i" "$DIR/$(basename $i | tr '.' '_')"
	done
elif [ -f "$REF" ]
then
	VLDT_DIR
	MAIN "$REF" "$DIR/$(basename $REF | tr '.' '_')"
else
	echo "[-] The file or folder doesn't exist"
	exit
fi
# Cleans the empty directories and files
echo "[*] Cleaning..."
find "$DIR" -empty -delete
# Gives permissions to the regular user for the folder
chmod 664 -R "$DIR"
file_tree=$(find "$DIR" -type f)
files_count=$(echo "$file_tree" | wc -l)

echo "[*] Analyze completed"
# Creates the report.txt
echo "Date: $date" | tee -a "$DIR/report.txt"
echo "Total file count: $files_count" | tee -a "$DIR/report.txt"
echo >> "$DIR/report.txt"
echo "File Tree:" >> "$DIR/report.txt"
echo "$file_tree" >> "$DIR/report.txt"
echo "Archiving the data to $DIR.zip"
# Zips the folder and gives permissions
zip "$DIR.zip" -r "$DIR" > /dev/null
chmod 664 "$DIR.zip"
exit 0
