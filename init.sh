#!/bin/bash

THIS_DIR=`dirname $(readlink -f $0)`

main() 
{
	if ! cmd_exists /usr/bin/node; then
		log "installing nodejs"
		curl -sL https://deb.nodesource.com/setup_7.x | sudo -E bash -
		check_apt nodejs
	fi

	if ! cmd_exists /usr/bin/npm; then
		log "installing npm"
		check_apt npm
	fi

	if ! cmd_exists /usr/bin/uglifyjs; then
		npm install uglify-js -g
	fi

	cd $THIS_DIR

	npm install
}

#-------------------------------------------------------
#		basic functions
#-------------------------------------------------------

maintain()
{
	[ "$1" = "update" ] && git_update_exit
	[ "$1" = "checkout" ] && checkout_target_exit $2

	check_update
}

checkout_target_exit()
{
	. $THIS_DIR/config.sh

	local codesName=$1

	if [ "$codesName" = "" ]; then
		echo 'Please input source dirname to checkout'
		exit 1
	fi	

	local source_dir=$THIS_DIR/$codesName
	local checkout_dir=$THIS_DIR/public

	if [ ! -d "$source_dir" ]; then
		echo 'The input is invalid: '$source_dir
		exit 1
	fi	

	check_apt ecryptfs-utils 

	local options="no_sig_cache,ecryptfs_cipher=aes,ecryptfs_key_bytes=32,ecryptfs_passthrough=no,ecryptfs_enable_filename_crypto=yes"

	if test $ECRYPTFS_PASS; then
		options="$options,key=passphrase:passphrase_passwd=$ECRYPTFS_PASS"
	fi

	echo $options
	echo "source: $source_dir"
	echo "checkout: $checkout_dir"

	umount $checkout_dir
	mount -t ecryptfs -o $options $source_dir $checkout_dir
	exit 0
}

git_update_exit()
{
	. $THIS_DIR/config.sh

	local user=$(git config --global --get user.name)
	[ -z $user ] && git config --global --add user.name $GIT_USER_NAME

	local email=$(git config --global --get user.email)
	[ -z $email ] && git config --global --add user.email $GIT_USER_EMAIL

	local push=$(git config --global --get push.default)
	[ -z $push ] && git config --global --add push.default $GIT_PUSH_DEFAULT

	local push_url=$(git remote get-url --push origin)

	if ! echo $push_url | grep -q "${GIT_PUSH_USER}@"; then
		local new_url=$(echo $push_url | sed -e "s/\/\//\/\/${GIT_PUSH_USER}@/g")
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
