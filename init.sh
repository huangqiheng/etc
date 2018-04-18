#!/bin/bash

THIS_DIR=`dirname $(readlink -f $0)`

main() 
{
	if [ -f package.json ]; then
		if ! cmd_exists /usr/bin/node; then
			log "installing nodejs"
			curl -sL https://deb.nodesource.com/setup_7.x | sudo -E bash -
			check_apt nodejs
		fi

		if ! cmd_exists /usr/bin/npm; then
			log "installing npm"
			check_apt npm
		fi

		if ! cmd_exists uglifyjs; then
			npm install uglify-js -g
		fi

		cd $THIS_DIR

		npm install
	fi

	help
}

#-------------------------------------------------------
#		basic functions
#-------------------------------------------------------

help()
{
	cat << EOL
---------------------------------------------------
  Now you can:

  (1) First checkout the code: 
	sh init.sh checkout ACode 

  (2) Then start the server: 
	sh init.sh run

  (3) Or stop the server: 
	sh init.sh kill

  (4) Final close the mounted content: 
	sh init.sh close
---------------------------------------------------
EOL
	echo $help
}

maintain()
{
	[ "$1" = "update" ] && git_update_exit
	[ "$1" = "checkout" ] && checkout_target_exit $2
	[ "$1" = "close" ] && umount_target_exit
	[ "$1" = "kill" ] && kill_exit
	[ "$1" = "run" ] && run_exit

	check_update
}

kill_exit()
{
	local pids=$(ps aux | grep '[n]ode main.js' | awk '{print $2}')
	test $pids && kill $pids
	exit 0
}

run_exit()
{
	cd $THIS_DIR/public

	if [ -f main.js ]; then
		node main.js 
		exit 0
	fi

	if [ -f index.js ]; then
		node index.js 
		exit 0
	fi
}

include_config()
{
	[ -f $THIS_DIR/config.sh ] &&  . $THIS_DIR/config.sh
}

umount_target_exit()
{
	local checkout_dir=$THIS_DIR/public
	umount $checkout_dir
	exit 0
}

checkout_target_exit()
{
	include_config

	local codesName=$1

	if [ "$codesName" = "" ]; then
		echo 'Please input source dirname to checkout'
		exit 1
	fi	

	local source_dir=$THIS_DIR/$codesName
	local checkout_dir=$THIS_DIR/public
	mkdir -p $source_dir
	mkdir -p $checkout_dir 

	if [ ! -d "$source_dir" ]; then
		echo 'The input is invalid: '$source_dir
		exit 1
	fi	

	check_apt ecryptfs-utils 

	local options="no_sig_cache,ecryptfs_cipher=aes,ecryptfs_key_bytes=32,ecryptfs_passthrough=no,ecryptfs_enable_filename_crypto=yes"

	if test $ECRYPTFS_PASS; then
		options="$options,key=passphrase:passphrase_passwd=$ECRYPTFS_PASS"
	else
		read -r -p "Please input PASSWORD: " inputpass <&2
		if test $inputpass; then
			options="$options,key=passphrase:passphrase_passwd=$inputpass"
		else
			echo "Error exit, password must be set."
			exit 1
		fi
	fi

	echo $options
	echo "source: $source_dir"
	echo "checkout: $checkout_dir"

	umount $checkout_dir
	yes "" | mount -t ecryptfs -o $options $source_dir $checkout_dir
	exit 0
}

check_git()
{
	local key="$1"
	local defautVal="$2"
	local value=$(git config --global --get ${key})

	if [ -z "$value" ]; then
		if [ -z $defautVal ]; then
			read -p "Please input git config of \"${key}\": " GIT_CONFIG_INPUT
		else
			GIT_CONFIG_INPUT=$defautVal
		fi

		if [ -z "$GIT_CONFIG_INPUT" ]; then
			echo "The input value is empty, exit"
			exit 1;
		fi
		git config --global --add ${key} ${GIT_CONFIG_INPUT}
	fi
}

git_update_exit()
{
	check_git user.name 
	check_git user.email
	check_git push.default simple
	check_git user.githubUserName 

	local push_url=$(git remote get-url --push origin)
	local githubUserName=$(git config --global --get user.githubUserName)

	if ! echo $push_url | grep -q "${githubUserName}@"; then
		local new_url=$(echo $push_url | sed -e "s/\/\//\/\/${githubUserName}@/g")
		git remote set-url origin $new_url
		echo "update remote url: $new_url"
	fi

	local input_msg=$1
	input_msg=${input_msg:="update"}

	cd $THIS_DIR
	git add .
	git commit -m "${input_msg}"
	git push

	exit 0
}


check_update()
{
	if [ $(whoami) != 'root' ]; then
	    echo "This script should be executed as root or with sudo:"
	    echo "	sudo $0"
	    exit 1
	fi

	local last_update=`stat -c %Y  /var/cache/apt/pkgcache.bin`
	local nowtime=`date +%s`
	local diff_time=$(($nowtime-$last_update))

	local repo_changed=0

	if [ $# -gt 0 ]; then
		for the_param in "$@"; do
			the_ppa=$(echo $the_param | sed 's/ppa:\(.*\)/\1/')

			if [ ! -z $the_ppa ]; then 
				if ! grep -q "^deb .*$the_ppa" /etc/apt/sources.list /etc/apt/sources.list.d/*; then
					add-apt-repository -y $the_param
					repo_changed=1
					break
				else
					log "repo ${the_ppa} has already exists"
				fi
			fi
		done
	fi 

	if [ $repo_changed -eq 1 ] || [ $diff_time -gt 604800 ]; then
		apt update -y
	fi

	if [ $diff_time -gt 6048000 ]; then
		apt upgrade -y
	fi 
}

check_apt()
{
	for package in "$@"; do
		if [ $(dpkg-query -W -f='${Status}' ${package} 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
			apt install -y "$package"
		else
			log "${package} has been installed"
		fi
	done
}

log() 
{
	echo "$@"
	#logger -p user.notice -t install-scripts "$@"
}

cmd_exists() 
{
    type "$1" > /dev/null 2>&1
}

maintain "$@"
main "$@"; exit $?
