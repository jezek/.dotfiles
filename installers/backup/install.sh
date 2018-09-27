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

.backup_checkDest() {
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr"Backup error:  .backup_checkDest function need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local remote=$1
	local directory=$2

	if [ "$remote" = "" ]; then
		if [ ! -d "$directory" ]; then
			(>&2 echo -e $cErr"Backup destination check error: destination directory does not exist: "$cFile${directory}$cNone)
			return 255
		fi
	else
		if ! .run "ssh $remote '[ -d \""$directory"\" ]'"; then
			(>&2 echo -e $cErr"Backup destination check error: ssh connection to \"$remote\" failed, or destination directory does not exist: "$cFile${directory}$cNone)
			return 255
		fi
	fi
	return
}

backupDestDirectory=""
backupDestRemote=""
while true; do # ask for backup destination [[user@]hostname:]path/to/backup/directory
	echo -e "Backup destination in format: [[user@]hostname:]path/to/backup/directory"
	dest=""
	read dest
	if [ "${dest}" = "" ]; then
		echo -e $cErr"User exited"$cNone
		[ "$1" = plugin ] && return 1
		exit 1
	fi

	prefix=${dest%%":"*} # everything before ":"
	suffix=${dest#*":"} # everything after ":"

	backupDestDirectory=$suffix
	if [ ! "${prefix}" = ${suffix} ]; then # ":" in dest, $prefix is remote host
		#TODO check for host ssh conn is open
		
		# send keys to remote
		if ! .run "ssh-copy-id -n $prefix"; then
			echo -e $cErr"Failed to send ssh keys to remote: "$cNone${prefix}
		fi
		backupDestRemote=$prefix
	fi

	echo -e "Checking if destination input is valid: remote=$backupDestRemote,dir=$backupDestDirectory"
	if .backup_checkDest "$backupDestRemote" "$backupDestDirectory"; then
		if [ "$backupDestRemote" = "" ]; then
			# set destinat directory to absolute path
			backupDestDirectory="$( cd "${backupDestDirectory}" ; pwd -P )"
		fi
		echo -e "Destination is valid: $backupDestRemote:"$cFile${backupDestDirectory}$cNone
		break
	fi
done

#TODO ask for backup source
#TODO create & deploy exclude file
#TODO create & deploy backup config
.run "mkdir -p '${dotBackupDir}'"

linkFile="${dotfilesBin}/.backup"
if .hardlink "${dotfilesDir}/installers/backup/backup.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" created."
fi
