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

sshconn="ssh -t -o ControlPath=$HOME/.ssh/connection_pipe_%h_%p_%r -o ControlMaster=auto -o ControlPersist=60"
.backup_checkDest() {
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr"Backup error:  .backup_checkDest function need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local remote=$1
	local directory=$2

	if [ "$remote" = "" ]; then
		if [ ! -d "$directory" ]; then
			if .check_yes_no "Remote \"$remote\" destination directory \"$cFile${directory}$cNone\" does not exist. Create?"; then
				if ! .run "mkdir -p \""$directory"\""; then
					(>&2 echo -e $cErr"Backup destination check error: creating local destination directory \"$cFile${directory}$cErr\" failed"$cNone)
					return 255
				fi
			else
				(>&2 echo -e $cErr"Backup destination check error: destination directory does not exist: "$cFile${directory}$cNone)
				return 255
			fi
		fi
	else
		if .run "$sshconn $remote 'exit'"; then
			if ! .run "$sshconn $remote '[ -d \""$directory"\" ]'"; then
				if .check_yes_no "Remote \"$remote\" destination directory \"$cFile${directory}$cNone\" does not exist. Create?"; then
					if ! .run "$sshconn $remote 'mkdir -p \""$directory"\" ]'"; then
						(>&2 echo -e $cErr"Backup destination check error: creating remote \"$cNone${remote}$cErr\" destination directory \"$cFile${directory}$cErr\" failed"$cNone)
						return 255
					fi
				else
					(>&2 echo -e $cErr"Backup destination check error: remote \"$cNone${remote}$cErr\" destination directory does not exist: "$cFile${directory}$cNone)
					return 255
				fi
			fi
		else 
			(>&2 echo -e $cErr"Backup destination check error: ssh connection to \"$cNone${remote}$cErr\" failed"$cNone)
			return 255
		fi
	fi
	return
}



defaultRemote="127.0.0.1"
defaulDestDirectory="/home/jezek/Zálohy/rribs/$(id -un)@$(hostname)"

backupDestDirectory=""
backupDestRemote=""
while true; do # ask for backup destination [[user@]hostname:]path/to/backup/directory
	echo -e $cInput"1"$cNone" - \"$defaultRemote:$defaulDestDirectory\""
	echo -e $cInput"2"$cNone" - \"$defaulDestDirectory\""
	echo -e $cInput"<enter>"$cNone" - type nothing for exit"
	echo -e $cInput"[[user@]hostname:]path/to/backup/directory"$cNone" - backup destination. If path is local, will be converted to absolute path."
	echo -n "Backup destination: "
	dest=""
	read dest
	case "$dest" in
		1 ) 
			dest="$defaultRemote:$defaulDestDirectory"
			;; 
		2 ) 
			dest="$defaulDestDirectory"
			;; 
		"" ) 
			echo -e $cErr"User exited"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
			;;
	esac

	prefix=${dest%%":"*} # everything before ":"
	suffix=${dest#*":"} # everything after ":"
	#TODO bug if dest == "jezek.sk:jezek.sk"

	backupDestDirectory=$suffix
	if [ ! "${prefix}" = ${suffix} ]; then # ":" in dest, $prefix is remote host
		if .check_yes_no "Do you want to send your ssh keys to remote host fo key-based authentication?"; then 
			# send keys to remote
			if ! .run "ssh-copy-id -n $prefix"; then
				echo -e $cErr"Failed to send ssh keys to remote: "$cNone${prefix}
				echo
				continue
			fi
		else
			# check for host ssh conn can be opened and if yes, create master connection
			if ! .run "$sshconn $prefix 'exit'"; then
				echo -e $cErr"Failed to connect with ssh to remote: "$cNone${prefix}
				echo
				continue
			fi
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
	echo -e $cInput"1"$cNone" - \"$HOME/pripojenia\""
	echo -e $cInput"<enter>"$cNone" - type nothing for exit"
	echo -e $cInput"path/to/directory/to/backup"$cNone" - source directory to backup from. Will be cnverted to absolute path"
	echo -n "Backup source: "
	src=""
	read src
	case "$src" in
		1 ) 
			src="$HOME/pripojenia"
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


# create exclude directories array
backupExcludes=()

if .check_yes_no "Add mounted points in \"$cFile${backupSourceDirectory}$cNone\" into exclude file?"; then
	echo -e "Mounted points in backup source directory:"
	while read -r i; do # loop though all mountpoints
		fields=($i)
		src=${fields[0]}
		dst=${fields[1]}

		case "$dst" in ${backupSourceDirectory}*) # if mount destination is inside our source directory
			# add to excludes array
			echo -e $cFile${dst}$cNone" -> "$src
			backupExcludes+=("- ""${dst#$backupSourceDirectory}""/")
		esac
	done < /proc/mounts
	unset fields src dst
	echo
fi


if .check_yes_no "Search for \".cache\" directories in backup source directory and add them into exclude file?"; then
	# search for ".cache" in source excluding mounted points in excludes
	if ! .runRes caches "find '${backupSourceDirectory}' -mount -type d \( -not -perm -g+r,u+r,o+r -prune -or -name '*.cache*' -prune -print \)"; then # do not descend to other filesystems, do not descen do dirs, you have not permissions for, print ".cache" dirs and do not descend
		printf $cErr"Some errors occured in search"$cNone"\n"
	fi
	if [ "$caches" = "" ]; then 
		printf "No \".cache\" directories\n"
	else
		printf "Found \".cache\" directories:\n"
		while read -r line; do # loop though all findings
			# add to excludes array
			printf "$cFile${line}$cNone\n"
			backupExcludes+=("- ""${line#$backupSourceDirectory}""/")
		done <<< $caches
	fi
	unset caches line
	echo
fi

echo -e "Deploying backup configuration:"

.run "mkdir -p '${dotBackupDir}'"

# deploy exclude file
excludeFile="${dotBackupDir}/exclude.txt"
.run "touch '$excludeFile'"
printf "%s\n" "${backupExcludes[@]}" | tee "$excludeFile"
echo

# create & deploy backup config
configFile="${dotBackupDir}/config"
.run "touch '$configFile'"
printf "backupSourceDirectory=\"%s\"\n\
backupDestRemote=\"%s\"\n\
backupDestDirectory=\"%s\"\n" "$backupSourceDirectory" "$backupDestRemote" "$backupDestDirectory" | tee "$configFile"
echo

linkFile="${dotfilesBin}/.backup"
if .hardlink "${dotfilesDir}/installers/backup/backup.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" created."
fi
