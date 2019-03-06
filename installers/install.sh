#! /bin/bash
#TODO make installer to be used in onliner with curl in any current directory

#TODO instller errors on fp2
# git-summary not found
# vim_undo_clean.sh no found 
# fingerprint - lsusb not found
# vim first plug install echoes solarize not found
# backup cant connect to jezek@192.168.88.132

# colors
cNone='\e[0m'
# named colors
cRed='\e[91m'
cGreen='\e[92m'
cYellow='\e[93m' # results
cBlue='\e[94m'
cMagenta='\e[95m'
# layout colors
cErr=$cRed
cWarn=$cRed
cCmd=$cGreen
cPkg=$cBlue
cFile=$cMagenta
cInput=$cYellow

# debug=0
onlyEssential=0
for arg in $@; do
	case "$arg" in
		debug ) debug=1;;
		essentials ) onlyEssential=1;;
		* )
			if [ $onlyEssential -eq 0 ]; then
				echo -e $cErr"Unknown argument: $arg"$cNone"\nAll arguments: $@"
				exit 1
			fi
			;;
	esac
done

# sudo
SUDO=''
if (( $EUID != 0 )); then
	SUDO='sudo'
fi

.dotfiles(){ return 1; }

.toLines() {
	printf '%s\n' "$@"
}

# Yes/no dialog. Default answer (if pressing enter) is Yes (can be changed)
# The first argument is the message that the user will see.
# Second argumenti is optional, and if "n", then default will be No
# If the user enters n/N, return 1, else 0.
.check_yes_no(){
	while true; do
		local default="y"
		local hint="[Y/n]"
		local yn=""
		if [ "$2" = n ]; then
			default="n"
			hint="[y/N]"
		fi
		echo -e -n "$1 $hint: "
		read -n1 yn
		if [ "$yn" = "" ]; then
			yn="$default"
		else
			echo ""
		fi
		case "$yn" in
			[Yy] )
				break;;
			[Nn] )
				echo "No"
				return 1;;
			* )
				echo -e "${cErr}Please answer y or n for yes or no.${cNone}";;
		esac
	done;
	echo "Yes"
}

.run(){
	if [ ! $# = 1 ]; then
		(>&2 echo -e $cErr".run: need 1 argument, got $#: "$cNone$@)
		return 255
	fi
	(>&2 echo -e $cCmd$1$cNone)
	eval $1
	local res=$?
	if [ "$debug" = 1 ]; then
		local rc=$cGreen
		if [ ! $res = 0 ]; then
			local rc=$cErr
		fi
		(>&2 echo -e "Result: "$rc$res$cNone)
	fi
	return $res
}
.runRes(){
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr".runRes: need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local resVar=$1
	local cmd=$2
	resVal=`.run "$cmd"`
	local r=$?
	eval $resVar="'$resVal'"
	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".runRes: result: "$cYellow${resVal}$cNone)
	fi
	return $r
}

# install all packages for commands
# if command name is not the same as package name, the package name is specified as "cmd/pkg"
.install(){
	local packages=()
	
	local cmdPkg
	for cmdPkg in $*; do
		local pkg=${cmdPkg#*"/"} # everything after "/"
		packages+=("${pkg}")
	done
	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".install: installing packages: "$cYellow${packages[*]}$cNone)
	fi

	.run $SUDO" apt install ${packages[*]}"
	return $?
}

.isCmd(){
	type ${1%%"/"*} >/dev/null 2>&1 # command is everything until "/"
	return $?
}

.installedPpa() {
 .run "find /etc/apt/ -name '*.list' -print0 | xargs -0 grep -ho '^deb http://ppa.launchpad.net/[a-z0-9\\-]\\+/[a-z0-9\\-]\\+'"
}

.timestamp() {
	date +"%F %T.%N"
}

.backup() {
	local filename
	for fileName in $*; do 
		if [ -e "${fileName}" ]; then # file exists
			local backup="${fileName}.$(.timestamp).bak"

			if [ -e "${backup}" ]; then
				(>&2 echo -e $cErr"Backup error: file "$cFile"${fileName}"$cErr" allready has a backup "$cFile${backup}$cNone)
				return 1 # can not backup, other backup file exists
			fi

			.run "mv '$fileName' '$backup'"
			local res=$?
			if [ ! "${res}" = 0 ]; then
				(>&2 echo -e $cErr"Backup error: move error: "$cNone${res})
				return 254 # move error
			else
				echo -e "File "$cFile"${fileName}"$cNone" backed up to "$cFile${backup}$cNone
				return
			fi
		else
			(>&2 echo -e $cErr"Backup error: file "$cFile${fileName}$cErr" does not exist"$cNone)
			return 255 # backup file not found
		fi
	done
}

.hardlink() {
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr"Hardlinking error: .hardlink function need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local source=$1
	local target=$2

	if [ -f "$source" ]; then # source exists

		if [ $target -ef $source ]; then # source and target are equal files
			(>&2 echo -e "Hardlinking not needed, file "$cFile"${source}"$cNone" and "$cFile"${target}"$cNone" are the same (allready hardlinked).")
			return 2 # allready linked
		fi

		if [ -f "$target" ]; then # target exists
			if .check_yes_no "File "$cFile${target}$cNone" allready exists. Overwrite with "$cFile${source}$cNone"?"; then
				if .check_yes_no "Backup "$cFile${target}$cNone"?"; then
					if ! .backup "$target"; then
						if ! .check_yes_no "Backup failed. Link files anyway?"; then
							(>&2 echo -e $cErr"Hardlinking error: user decided not to link file "$cFile"${source}"$cErr" to "$cFile"${target}"$cErr"."$cNone)
							return 1 # user decided not to link
						fi
					fi
				else
					.run "rm '$target'"
				fi
			else
				(>&2 echo -e $cErr"Hardlinking error: user decided not to link file "$cFile"${source}"$cErr" to "$cFile"${target}"$cErr"."$cNone)
				return 1 # user decided not to link
			fi
		fi

		.run "cp -vfl '$source' '$target'"
		local res=$?
		if [ ! "${res}" = 0 ]; then
			(>&2 echo -e $cErr"Hardlinking error: copy error: "$cNone${res})
			return 253 # copy error
		fi
	else
		(>&2 echo -e $cErr"Hardlinking error: no source file "$cFile"${source}"$cErr" found."$cNone)
		return 254 # no source file
	fi
}

# to global variable missing it assigns an array of missing commands passed as other arguments 
# returns 1 if some command is missing
.missing() {
	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".missing: check "$cYellow${*}$cNone)
	fi

	missing=()
	local cmd
	for cmd in $*; do
		if ! .isCmd "${cmd}"; then
			missing+=("${cmd}")
		fi
	done

	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".missing: results "$cYellow${missing[*]}$cNone)
	fi
	if [ ! ${#missing[*]} = 0 ]; then
		#TODO error message
		return 1 # something is missing
	fi
	return
}

.needCommand() {
	if ! .missing $*; then
		echo "we need theese essential programs for this script:"
		echo -e $cCmd${missing[*]}$cNone
		if .check_yes_no "install and continue?"; then
			if ! .install ${missing[*]}; then
				#TODO error message
				return 255 # install failed for some reason
			else
				.missing $*
				return $?
			fi
		else
			#TODO error message
			return 1 # user dont want to install needed packages
		fi
	fi
	return
}

# installs command if missing.
# if command is in package wthh different name, use "cmd/pkg" format.
#TODO provide a way to install additional packages for the command. (audacious+plugins, tlp+tlp-rdw, ...)
.installCommand() {
	if ! .missing $*; then
		echo "installing programs:"
		echo -e $cCmd${missing[*]}$cNone
		if .check_yes_no "install?"; then
			if ! .install ${missing[*]}; then
				#TODO error message
				return 255 # install failed for some reason
			else
				.missing $*
				return $?
			fi
		else
			#TODO error message
			return 1 # user dont want to install needed packages
		fi
	fi
	return
}

if ! .needCommand apt add-apt-repository git curl ssh sed date cp mv; then
	echo "Essential program are not available: "$missing
	if [ $onlyEssential = 1 ]; then
		return 1
	fi
	exit 1
fi

dotfilesDir="$HOME/.dotfiles"
dotfilesBin="${dotfilesDir}/bin"
github="https://github.com/"
githubName="jezek"

if [ $onlyEssential = 1 ]; then
	return
fi
# not essentials

#echo "testing:"
#
#
#echo "done"
#exit

### update & upgrade
##if .check_yes_no "update & upgrade?" "n"; then
##	$SUDO apt update
##	$SUDO apt upgrade
##fi

githubSsh=0
.run "ssh -qT git@github.com"
res=$?
if [ ! "$res" = 1 ]; then
	if .check_yes_no "do you want use your github with ssh on this device?"; then
		pubKeyFile=""
		sshDir="$HOME/.ssh"
		sshPubKeyFile=$sshDir"/id_rsa.pub"
		if [ -e $sshPubKeyFile ]; then
			pubKeyFile=$sshPubKeyFile
		fi
		if [ -z $pubKeyFile ]; then
			if .check_yes_no "no public key ($sshPubKeyFile) found. create new?"; then
				if .needCommand "ssh-keygen"; then
					comment=$HOSTNAME
					if .check_yes_no "ssh key will be generated with comment \"$comment\". change it?" "n"; then
						read -p "ssh key comment: " comment
					fi
					if [ ! -z $comment ]; then
						commentAttr=" -C \"$comment\""
					fi
					.run "ssh-keygen -t rsa -b 4096 $commentAttr"
				else
					echo -e $cErr"generating ssh key failed, no "$cCmd"ssh-keygen"$cErr" installed"$cNone
				fi
				if [ -e $sshPubKeyFile ]; then
					pubKeyFile=$sshPubKeyFile
				fi
			fi
		fi
		if [ ! -z $pubKeyFile ] && .check_yes_no "do you want to add your public key to github through api?"; then
			githubKeyTitle=$HOSTNAME
			if [ ! -z $comment ]; then
				githubKeyTitle=$comment
			fi
			.runRes pubKey "cat $pubKeyFile"
			res=$?
			if [ $res = 0 ]; then
				.run "curl -u \"$githubName\" -X POST -H \"Content-type: application/json\" -d \"{\\\"title\\\": \\\"$githubKeyTitle\\\",\\\"key\\\": \\\"$pubKey\\\"}\" \"https://api.github.com/user/keys\""
				res=$?
				if [ $res = 0 ]; then
					.run "ssh -qT git@github.com"
					res=$?
					if [ "$res" = 1 ]; then
						githubSsh=1
					else
						echo -e $cErr"someting failed, github with ssh access not configured"$cNone
					fi
				else
					echo -e $cErr"Can not set key to gitHub as $githubName"$cNone
				fi
			else
				echo -e $cErr"Can not load key from "$cNone$pubKeyFile
			fi
			unset pubKey
		else
			echo -e $cErr"no public key found, github with ssh access not configured"$cNone
		fi
	fi
else
	githubSsh=1
fi
unset res

if [ $githubSsh = 1 ]; then
	github="git@github.com:"
fi


if [ ! -d $dotfilesDir ]; then
	if ! .run "mkdir -p '$dotfilesDir'"; then
		echo -e $cErr"Could not create $cFile'$dotfilesDir'"$cNone
		exit 1
	fi
	#TODO test if allways clones to right directory (is running directory independent)
	.run "git clone $github$githubName/.dotfiles.git '$dotfilesDir'" 

	if [ ! -d $dotfilesDir ]; then
		echo "clonning ${cFile}$dotfilesDir${cNone} from github failed"
		exit 1
	fi
fi

if [ ! -d "${dotfilesBin}" ]; then
	.run "mkdir -p '$dotfilesBin'"
fi

plugins=(\
	sticky-keys git \
	shell/bash shell/zsh/zplug \
	vim vim/plug \
	golang \
	mc audacious chromium \
	fingerprint \
	wmctrl \
	backup)



for plugin in "${plugins[@]}"; do
	pluginInstallFile="$dotfilesDir/installers/$plugin/install.sh"
	if [ -f $pluginInstallFile ]; then
		source $pluginInstallFile plugin
	fi
done;

