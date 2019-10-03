#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

dotRemoteDir="${dotfilesDir}/remotes"
if [ ! -d $dotRemoteDir ]; then
	echo -e $cErr"No remote points found"$cNone
	echo -e $cErr"Remote config directory does not exist: "$cFile${dotRemoteDir}$cNone
	echo -e "Run "$cFile".remote-add"$cNone" to add remote point."
	exit 1
fi

#TODO use 1 argument as remote idetifier (rid), if no, print help
#TODO load variables (address, mountdir, ...) from $dotRemoteDir/$rid & validate
#TODO use loaded variables to mount/unmount
#TODO add to installers
if [ ! "$(ls -A $mountDir)" ]
then
  echo "Not mounted"
  echo -n "Mounting ... "
  sshfs $remoteAddress:$remoteFolder $mountDir -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3
  echo "[OK]"
else
  echo "Allready mounted"
	if .check_yes_no "Unmount?" n ; then
		echo -n "Unmountng ... "
		fusermount -u $mountDir
		echo "[OK]"
	fi
fi
