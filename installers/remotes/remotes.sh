#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

dotRemotesDir="${dotfilesDir}/remotes"
dotRemotesInstallDir="${dotfilesDir}/installers/remotes"
if [ ! -d $dotRemotesDir ]; then
	echo -e $cErr"Remotes config directory does not exist: "$cFile${dotRemotesDir}$cNone
	echo -e "Install remotes to configure: "$cFile${dotRemotesInstallDir}"/install.sh"$cNone
	exit 1
fi

declare -A mounts
while read -r i; do # loop though all mountpoints
	fields=($i)
	mounts["${fields[0]}"]="${fields[1]}"
done < /proc/mounts
#echo ${!mounts[@]}
#echo ${mounts[@]}

remoteFiles=( $dotRemotesDir"/*.conf" )
remoteFiles=( ${remoteFiles[@]} )
#echo ${remoteFiles[@]}
loadRemote() {
	unset remoteName remoteMountDir remoteMountStatus remoteAddress remoteAddressPort
	remoteFile=$1
	if [ ! -f "${remoteFile}" ]; then
		#echo -e $cErr"Remote config file does not exist: "$cFile${remoteFile}$cNone
		return 1
	fi
	export $(grep -v '#.*' "${remoteFile}" | xargs)
	#export -p|grep remote
	if [ -z ${remoteName+x} ]; then
		remoteName=$(basename $remoteFile)
		remoteName=${remoteName%.conf}
	fi
	if [ -z ${remoteMountDir+x} ]; then
		return 2
	fi

	if [ -z ${remoteAddress+x} ]; then
		return 3
	fi

	local mountPoints
	local point
	remoteMountStatus=0
	mountPoints=( ${mounts[@]} )
	for point in "${mountPoints[@]}"; do
		if [ "${remoteMountDir}" = "${point}" ]; then
			if [ "$remoteMountDir" = "${mounts["${remoteAddress}"]}" ]; then
				remoteMountStatus=1
			else
				remoteMountStatus=2
			fi
			break
		fi
	done

	return 0
}
loadRemoteError() {
	case $1 in
		0)
			unset port
			if [ ! -z ${remoteAddressPort+x} ]; then
				port=" (port: 222)"
			fi
			echo $remoteName": "$remoteAddress$port" -> "$remoteMountDir" - "$remoteMountStatus
			;;
		1)
			echo -e $cErr"Remote config file does not exist: "$cFile${remoteFile}$cNone
			;;
		2)
			echo -e $cErr"Missing \$remoteMountDir variable after remote config load: "$cFile${remoteFile}$cNone
			;;
		3)
			echo -e $cErr"Missing \$remoteAddress variable after remote config load: "$cFile${remoteFile}$cNone
			;;
		*)
			echo -e $cErr"Unknown load error: "$cFile${remoteFile}$cNone
			;;
	esac
}

if [ -z $1 ]; then
	for remote in "${remoteFiles[@]}"; do
		loadRemote "${remote}"
		loadRemoteError $?
	done
	exit 0
fi

if ! loadRemote "${dotRemotesDir}/${1}"; then
	found=()
	for remote in "${remoteFiles[@]}"; do
		if loadRemote "${remote}"; then
			if [[ "${remoteName}" =~ ${1} ]]; then
				found+=($remote)
				break
			fi
		fi
	done
	if [ ${#found[@]} -ne 1 ]; then
		if [ ${#found[@]} -eq 0 ]; then
			echo -e $cErr"No match for: "$cNone${1}
			for remote in "${remoteFiles[@]}"; do
				loadRemote "${remote}"
				loadRemoteError $?
			done
		else
			echo -e $cErr"Too many matches for: "$cNone${1}" - "${found[@]}
		fi
		exit 2
	fi
	loadRemote "${found[0]}"
fi

echo $remoteName": "$remoteAddress" -> "$remoteMountDir" - "$remoteMountStatus
if [ "$remoteMountStatus" = 0 ]; then
	echo "Not mounted"
	echo "Mounting ... "
	if [ ! -d "${remoteMountDir}" ]; then
		if ! .run "mkdir -p ${remoteMountDir}"; then
			echo -e $cErr"Error creating mount directory: "$cFile${remoteMountDir}$cNone
			exit 3
		fi
	fi
	unset port
	if [ ! -z ${remoteAddressPort+x} ]; then
		port=" -p 222"
	fi
	.run "sshfs $remoteAddress$port $remoteMountDir -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3" && echo -e $cGreen"[OK]"$cNone || { echo -e $cErr"[FAIL]"$cNone; exit 4; }
elif [ "$remoteMountStatus" = 1 ]; then
	echo "Allready mounted"
	if .check_yes_no "Unmount?" n ; then
		echo "Unmountng ... "
		.run "fusermount -u $remoteMountDir" && echo -e $cGreen"[OK]"$cNone || { echo -e $cErr"[FAIL]"$cNone; exit 5; }

	fi
else
	echo "Something else is already mounted on: "$cFile${remoteMountDir}$cNone
	exit 6
fi
