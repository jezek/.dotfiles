#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

#NOTE Try ip detection & try ssh to all ips (find out which are my devices) & mount/remount all devices
#IPs=sudo arp-scan --localnet --numeric --quiet --ignoredups | grep -E '([a-f0-9]{2}:){5}[a-f0-9]{2}' | awk '{print $1}'

dotRemotesDir="${dotfilesDir}/remotes"
dotRemotesInstallDir="${dotfilesDir}/installers/remotes"
if [ ! -d $dotRemotesDir ]; then
	if ! .check_yes_no "Setup remotes for this user?" ; then
		.run "mkdir -p '${dotRemotesDir}'"
		echo -e "If you want set-up remotes in future, delete "$cFile${dotRemotesDir}$cNone" and run remotes install file again"
		read
		[ "$1" = plugin ] && return 1 || exit 1
	fi
#else
#	echo -e "Remotes are already configured for this user. To reconfigure, delete "$cFile${dotRemotesDir}$cNone" and run remotes install file again"
#	[ "$1" = plugin ] && return 0 || exit 0
fi

if [ ! -d "${dotRemotesDir}" ]; then
	if ! .run "mkdir -p '${dotRemotesDir}'"; then
		echo -e $cErr"Error creating directory: "$cFile${dotRemotesDir}$cNone
		[ "$1" = plugin ] && return 1 || exit 1
	fi
fi

if ! .needCommand sshfs fusermount; then
	[ "$1" = plugin ] && return 1 || exit 1
fi

templateName="user@address.conf.template"
dotRemotesTemplate="${dotRemotesDir}/${templateName}"
if [ ! -f "$dotRemotesTemplate" ]; then
	.run "cp ${dotRemotesInstallDir}/${templateName} ${dotRemotesTemplate}"
fi

linkRemotesBin="${dotfilesBin}/.remotes"
if .hardlink "${dotRemotesInstallDir}/remotes.sh" $linkRemotesBin; then
	echo -e "Executable "$cCmd"$(basename ${linkRemotesBin})"$cNone" created."
fi
