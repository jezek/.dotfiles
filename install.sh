#! /bin/bash

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

debug=0
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

# Yes/no dialog. Default answer (if pressing enter) is Yes (can be changed)
# The first argument is the message that the user will see.
# Second argumenti is optional, and if "n", then default will be No
# If the user enters n/N, send exit 1.
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
		(>&2 echo -e Result Value: $cYellow$resVal$cNone)
	fi
	return $r
}

.install(){
	.run $SUDO" apt install $1"
	return $?
}

.isCmd(){
	type $1 >/dev/null 2>&1
	return $?
}

.installedPpa() {
 .run "find /etc/apt/ -name '*.list' -print0 | xargs -0 grep -ho '^deb http://ppa.launchpad.net/[a-z0-9\\-]\\+/[a-z0-9\\-]\\+'"
}

.backup() {
	local i
	for i in $*; do 
		echo $i 
		if [ -e $i ]; then 
			echo -e "${cFile}$i${cNone} exists"
			if .check_yes_no "backup ${cFile}$i${cNone}?"; then
				local backup="$i~"
				echo -e "backing up to ${cFile}$backup${cNone}"
				.run "mv -ib $i $backup"
			else
				.run "rm $i"
			fi
		fi
	done
}

.hardlink() {
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr".hardlink: need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local source=$1
	local target=$2

	if [ -f "$source" ]; then
		if [ ! $target -ef $source ]; then
			if .check_yes_no "use ${cFile}$source${cNone} as ${cFile}$target${cNone}?"; then
				.backup $target
				.run "cp -vibl $source $target"
			fi
		fi
	fi
}

.needCommand() {
local missing=()
for cmd in $*; do
	if ! .isCmd $cmd; then
		missing+=($cmd)
	fi
done

if [ ! ${#missing[@]} = 0 ]; then
	echo "we need theese essential programs for this script:"
	echo -e $cCmd${missing[@]}$cNone
	if .check_yes_no "install and continue?"; then
		local installed=()
		for pkg in ${missing[@]}; do
			.install $pkg
			if ! .isCmd $pkg; then
				echo -e $cErr"$pkg install failed!"$cNone
				#revert installed missing?
				if [ ! ${#installed[@]} = 0 ]; then
					echo "reverting installed missing: ${installed[@]}"
					.run $SUDO" apt remove ${installed[@]}"
				fi
				exit 255
			fi
			installed+=($pkg)
		done
	else #.check_yes_no "install and continue?"
		exit 1
	fi #.check_yes_no "install and continue?"
fi
}

.needCommand apt add-apt-repository git curl ssh sed

dotfilesDir="$HOME/.dotfiles"
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
				if ! .isCmd "ssh-keygen"; then
					if .check_yes_no "this operation needs ${cPkg}ssh-keygen${cNone}. install?"; then
						.install "ssh-keygen"
					fi
				fi
				if .isCmd "ssh-keygen"; then
					comment=$HOSTNAME
					if .check_yes_no "ssh key will be generated with comment \"$comment\". change it?" "n"; then
						read -p "ssh key comment: " comment
					fi
					if [ ! -z $comment ]; then
						commentAttr=" -C \"$comment\""
					fi
					.run "ssh-keygen -t rsa -b 4096 $commentAttr"
				else
					echo -e $cErr"generating ssh key failed"$cNone
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
	gitdotfiles=""
	.run "git clone $github$githubName/.dotfiles.git"
	if [ ! -d $dotfilesDir ]; then
		echo "clonning ${cFile}$dotfilesDir${cNone} from github failed"
		exit 1
	fi
fi

plugins=(\
	sticky-keys git \
	shell/bash shell/zsh/zplug \
	vim vim/plug \
	golang \
	mc audacious chromium \
	fingerprint)



for plugin in "${plugins[@]}"; do
	pluginInstallFile="$dotfilesDir/$plugin/install.sh"
	if [ -f $pluginInstallFile ]; then
		source $pluginInstallFile plugin
	fi
done;


