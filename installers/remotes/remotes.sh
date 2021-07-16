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

remotesConfigFile=$dotRemotesDir"/config"
if [ ! -f $remotesConfigFile ]; then
	echo -e $cErr"Remotes config file does not exist: "$cFile${remotesConfigFile}$cNone
	echo -e "Install remotes to configure: "$cFile${dotRemotesInstallDir}"/install.sh"$cNone
	#echo -e "Run "$cFile".remotes add"$cNone" to add remote point."
	exit 2
fi

source "$remotesConfigFile"

if [ -z ${remotesMountDir+x} ]; then
	echo -e $cErr"Missing variable after config load:"$cNone" \$remotesMountDir"
	exit 3
fi

if [ ! -d "${remotesMountDir}" ]; then
	echo -e "Remotes mount directory does not exist, creating: "$cFile${remotesMountDir}$cNone
	if ! .run "mkdir -p ${remotesMountDir}"; then
		echo -e $cErr"Error creating directory: "$cFile${remotesMountDir}$cNone
		exit 4
	fi
fi

declare -A mounts
while read -r i; do # loop though all mountpoints
	fields=($i)
	mounts["${fields[0]}"]="${fields[1]}"
done < /proc/mounts
#echo ${!mounts[@]}
#echo ${mounts[@]}

remoteFiles=( $dotRemotesDir"/*" )
remoteFiles=( ${remoteFiles[@]} )
remoteFiles=( ${remoteFiles[@]/$remotesConfigFile} )
#echo ${remoteFiles[@]}
loadRemote() {
	unset remoteName remoteMountDir remoteMountStatus remoteAddress
	remoteFile=$1
	if [ ! -f "${remoteFile}" ]; then
		#echo -e $cErr"Remote config file does not exist: "$cFile${remoteFile}$cNone
		return 1
	fi
	export $(grep -v '#.*' "${remoteFile}" | xargs)
	#export -p|grep remote 
	if [ -z ${remoteName+x} ]; then
		remoteName=$(basename $remoteFile)
	fi
	if [ -z ${remoteMountDir+x} ]; then
		remoteMountDir=$remotesMountDir"/"$remoteName
	fi

	if [ -z ${remoteAddress+x} ]; then
		#echo -e $cErr"Missing \$remoteAddress variable after remote config load: "$cFile${remote}$cNone
		return 2
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
			echo $remoteName": "$remoteAddress" -> "$remoteMountDir" - "$remoteMountStatus
			;;
		1)
			echo -e $cErr"Remote config file does not exist: "$cFile${remote}$cNone
			;;
		2)
			echo -e $cErr"Missing \$remoteAddress variable after remote config load: "$cFile${remote}$cNone
			;;
		*)
			echo -e $cErr"Unknown load error: "$cFile${remote}$cNone
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
		exit 5
	fi
	loadRemote "${found[0]}"
fi

echo $remoteName": "$remoteAddress" -> "$remoteMountDir" - "$remoteMountStatus
if [ "$remoteMountStatus" = 0 ]; then
  echo "Not mounted"
  echo -n "Mounting ... "
  if [ ! -d "${remoteMountDir}" ]; then
  	if ! .run "mkdir -p ${remoteMountDir}"; then
  		echo -e $cErr"Error creating mount directory: "$cFile${remoteMountDir}$cNone
  		exit 6
		fi
	fi
  sshfs $remoteAddress $remoteMountDir -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3 && echo -e $cGreen"[OK]"$cNone || { echo -e $cErr"[FAIL]"$cNone; exit 7; }
elif [ "$remoteMountStatus" = 1 ]; then
  echo "Allready mounted"
	if .check_yes_no "Unmount?" n ; then
		echo -n "Unmountng ... "
		fusermount -u $remoteMountDir && echo -e $cGreen"[OK]"$cNone || { echo -e $cErr"[FAIL]"$cNone; exit 8; }

	fi
else
  echo "Something else is already mounted on: "$cFile${remoteMountDir}$cNone
  exit 9
fi
