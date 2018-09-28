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

if ! .needCommand rsync ssh ssh-copy-id; then
	[ "$1" = plugin ] && return 1
	exit 1
fi

echo

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
	echo -e $cInput"1"$cNone" - \"192.168.88.132:/home/jezek\""
	echo -e $cInput"<enter>"$cNone" - type nothing for exit"
	echo -e $cInput"[[user@]hostname:]path/to/backup/directory"$cNone" - backup destination. If path is local, will be converted to absolute path."
	echo -n "Backup destination: "
	dest=""
	read dest
	case "$dest" in
		1 ) 
			dest="192.168.88.132:/home/jezek"
			;; 
		"" ) 
			echo -e $cErr"User exited"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
			;;
	esac

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
	if ! .backup_checkDest "$backupDestRemote" "$backupDestDirectory"; then
		echo -e "Try again"
		echo
		continue
	fi

	if [ "$backupDestRemote" = "" ]; then
		# set destinat directory to absolute path
		backupDestDirectory="$( cd "${backupDestDirectory}" ; pwd -P )"
	fi

	# all is valid, break from loop
	break
done
unset dest prefix suffix

echo
echo -n "Backup destination entered: "
if [ ! "$backupDestRemote" = "" ]; then 
	echo -n $backupDestRemote":"
fi
echo -e $cFile${backupDestDirectory}$cNone
echo

backupSourceDirectory=""
while true; do # ask for backup source & check
	echo -e $cInput"1"$cNone" - \"$HOME\""
	echo -e $cInput"<enter>"$cNone" - type nothing for exit"
	echo -e $cInput"path/to/directory/to/backup"$cNone" - source directory to backup from. Will be cnverted to absolute path"
	echo -n "Backup source: "
	src=""
	read src
	case "$src" in
		1 ) 
			src="$HOME"
			;; 
		"" ) 
			echo -e $cErr"User exited"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
			;;
	esac


	if [ ! -d "$src" ]; then
		echo -e $cErr"Source directory does not exist: "$cFile${src}$cNone
		echo -e "Try again"
		echo
		continue
	fi

	# set destinat directory to absolute path
	backupSourceDirectory="$( cd "${src}" ; pwd -P )"

	# all is valid, break from loop
	break
done
unset src

echo
echo -e "Backup source entered: "$cFile${backupSourceDirectory}$cNone
echo

#TODO create & deploy exclude file
.run "mkdir -p '${dotBackupDir}'"

# create & deploy backup config
configFile="${dotBackupDir}/config"
.run "touch '$configFile'"
.run "echo 'backupSourceDirectory=\"$backupSourceDirectory\"' >> '$configFile'"
.run "echo 'backupDestRemote=\"$backupDestRemote\"' >> '$configFile'"
.run "echo 'backupDestDirectory=\"$backupDestDirectory\"' >> '$configFile'"

linkFile="${dotfilesBin}/.backup"
if .hardlink "${dotfilesDir}/installers/backup/backup.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" created."
fi
