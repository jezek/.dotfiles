#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

dotBackupDir="${dotfilesDir}/backup"
if [ ! -d $dotBackupDir ]; then
	if ! .check_yes_no "Setup backup for this user?" ; then
		.run "mkdir -p '${dotBackupDir}'"
		echo -e "If you want backup in future, delete "$cFile${dotBackupDir}$cNone" and run backup install file again"
		read
		[ "$1" = plugin ] && return 1
		exit 1
	fi
else
	echo -e "Backup allready configured for this user. To reconfigure, delete "$cFile${dotBackupDir}$cNone" and run backup install file again"
	[ "$1" = plugin ] && return 0
	exit 0
fi

if ! .needCommand rsync; then
	[ "$1" = plugin ] && return 1
	exit 1
fi

.run "mkdir -p '${dotBackupDir}'"

linkFile="${dotfilesBin}/.backup"
if .hardlink "${dotfilesDir}/installers/backup/backup.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" created."
fi
