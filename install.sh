#! /bin/bash

# colors
cDefault='\e[0m'
cRed='\e[91m' # errors
cGreen='\e[92m' # commands
cBlue='\e[94m' # packages
cYellow='\e[93m' # results

debug=0
for arg in $@; do
	case "$arg" in
		debug ) debug=1;;
		* )
			echo -e $cRed"Unknown argument: $arg"$cDefault
			exit 1
			;;
	esac
done

# sudo
SUDO=''
if (( $EUID != 0 )); then
	SUDO='sudo'
fi


# Yes/no dialog. The first argument is the message that the user will see.
# If the user enters n/N, send exit 1.
check_yes_no(){
	while true; do
		default="y"
		hint="[Y/n]"
		if [ "$2" = n ]; then
			default="n"
			hint="[y/N]"
		fi
		echo -e -n "$1 $hint: "
		read yn
		if [ "$yn" = "" ]; then
			yn="$default"

		fi
		case "$yn" in
			[Yy] )
				break;;
			[Nn] )
				echo "No"
				return 1;;
			* )
				echo -e "${cRed}Please answer y or n for yes or no.${cDefault}";;
		esac
	done;
	echo "Yes"
}

run(){
	if [ ! $# = 1 ]; then
		(>&2 echo -e $cRed"run: need 1 argument, got $#: "$cDefault$@)
		return 255
	fi
	(>&2 echo -e $cGreen$1$cDefault)
	eval $1
	local res=$?
	if [ "$debug" = 1 ]; then
		local rc=$cGreen
		if [ ! $res = 0 ]; then
			local rc=$cRed
		fi
		(>&2 echo -e "Result: "$rc$res$cDefault)
	fi
	return $res
}
runRes(){
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cRed"runRes: need 2 argument, got $#: "$cDefault$@)
		return 255
	fi
	local resVar=$1
	local cmd=$2
	resVal=`run "$cmd"`
	local r=$?
	eval $resVar="'$resVal'"
	if [ "$debug" = 1 ]; then
		(>&2 echo -e Result Value: $cYellow$resVal$cDefault)
	fi
	return $r
}

install(){
	run $SUDO" apt install "$1
	return $?
}

isCmd(){
	type $1 >/dev/null 2>&1
	return $?
}

installedPpa() {
 run "find /etc/apt/ -name '*.list' -print0 | xargs -0 grep -ho '^deb http://ppa.launchpad.net/[a-z0-9\\-]\\+/[a-z0-9\\-]\\+'"
}

#echo "testing:"
#echo "done"
#exit

# update & upgrade
if check_yes_no "update & upgrade?" "n"; then
	$SUDO apt update
	$SUDO apt upgrade
fi

if check_yes_no "turn on sticky keys?" "n"; then
	xkbsetinstall=0
	if ! isCmd xkbset; then
		echo "need xkbset, which is not installed"
		if check_yes_no "install xkbset?"; then
			xkbsetinstall=1
			install "xkbset"
		fi
	fi
	if isCmd xkbset; then
		echo ""
		run "xkbset a sticky -twokey -latchlock"
		run "xkbset exp =sticky"
		echo "you should add theese somewhere to startup, or turn on in settings..."
		read
	elif [ "$xkbsetinstall" = 1 ]; then
		echo -e $cRed"xkbset install failed!"$cDefault
	fi
fi

cd $HOME


essentials=(apt add-apt-repository git curl ssh sed)
missing=()
for cmd in "${essentials[@]}"; do
	if ! isCmd $cmd; then
		missing+=($cmd)
	fi
done

if [ ! ${#missing[@]} = 0 ]; then
	echo "we need theese essential programs for this script:"
	echo -e $cBlue${missing[@]}$cDefault
	if check_yes_no "install and continue?"; then
		installed=()
		for pkg in ${missing[@]}; do
			install $pkg
			if ! isCmd $pkg; then
				echo -e $cRed"$pkg install failed!"$cDefault
				#revert installed missing?
				if [ ! ${#installed[@]} = 0 ]; then
					echo "reverting installed missing: ${installed[@]}"
					run $SUDO" apt remove ${installed[@]}"
				fi
				exit 255
			fi
			installed+=($pkg)
		done
		unset installed
	else #check_yes_no "install and continue?"
		exit 1
	fi #check_yes_no "install and continue?"
fi
unset missing
unset essentials

githubName="jezek"
github="https://github.com/$githubName"
githubSsh=0
run "ssh -qT git@github.com"
res=$?
if [ ! "$res" = 1 ]; then
	if check_yes_no "do you want use your github with ssh on this device?"; then
		pubKeyFile=""
		sshDir="$HOME/.ssh"
		sshPubKeyFile=$sshDir"/id_rsa.pub"
		if [ -e $sshPubKeyFile ]; then
			pubKeyFile=$sshPubKeyFile
		fi
		if [ -z $pubKeyFile ]; then
			if check_yes_no "no public key ($sshPubKeyFile) found. create new?"; then
				if ! isCmd "ssh-keygen"; then
					if check_yes_no "this operation needs ${cBlue}ssh-keygen${cDefault}. install?"; then
						install "ssh-keygen"
					fi
				fi
				if isCmd "ssh-keygen"; then
					comment=$HOSTNAME
					if check_yes_no "ssh key will be generated with comment \"$comment\". change it?" "n"; then
						read -p "ssh key comment: " comment
					fi
					if [ ! -z $comment ]; then
						commentAttr=" -C \"$comment\""
					fi
					run "ssh-keygen -t rsa -b 4096 $commentAttr"
				else
					echo -e $cRed"generating ssh key failed"$cDefault
				fi
				if [ -e $sshPubKeyFile ]; then
					pubKeyFile=$sshPubKeyFile
				fi
			fi
		fi
		if [ ! -z $pubKeyFile ] && check_yes_no "do you want to add your public key to github through api?"; then
			githubKeyTitle=$HOSTNAME
			if [ ! -z $comment ]; then
				githubKeyTitle=$comment
			fi
			runRes pubKey "cat $pubKeyFile"
			res=$?
			if [ $res = 0 ]; then
				run "curl -u \"$githubName\" -X POST -H \"Content-type: application/json\" -d \"{\\\"title\\\": \\\"$githubKeyTitle\\\",\\\"key\\\": \\\"$pubKey\\\"}\" \"https://api.github.com/user/keys\""
				res=$?
				if [ $res = 0 ]; then
					run "ssh -qT git@github.com"
					res=$?
					if [ "$res" = 1 ]; then
						githubSsh=1
					else
						echo -e $cRed"someting failed, github with ssh access not configured"$cDefault
					fi
				else
					echo -e $cRed"Can not set key to gitHub as $githubName"$cDefault
				fi
			else
				echo -e $cRed"Can not load key from "$cDefault$pubKeyFile
			fi
			unset pubKey
		else
			echo -e $cRed"no public key found, github with ssh access not configured"$cDefault
		fi
	fi
else
	githubSsh=1
fi
unset res

if [ $githubSsh = 1 ]; then
	github="git@github.com:$githubName"
fi

dotfilesDir=".dotfiles"
if [ ! -d $dotfilesDir ]; then
	gitdotfiles=""
	run "git clone $github/.dotfiles.git"
	if [ ! -d $dotfilesDir ]; then
		echo "clonning $dotfilesDir from git failed"
		exit 1
	fi
fi

GITFILES="$dotfilesDir/git/files"
GITCONFIG=".gitconfig"
if [ -e "$GITFILES/$GITCONFIG" ]; then
	if check_yes_no "configure $GITCONFIG from $GITFILES/$GITCONFIG?"; then
		if [ -e $GITCONFIG ]; then
			echo "$GITCONFIG exists"
			if check_yes_no "backup $GITCONFIG?"; then
				GITCONFIGBACKUP="$GITCONFIG.bak"
				echo "backing up to $GITCONFIGBACKUP"
				run "mv $GITCONFIG $GITCONFIGBACKUP"
			else
				run "rm $GITCONFIG"
			fi
			if [ -e $GITCONFIG ]; then
				echo "failed"
				exit 1
			fi
		fi
		run "cp -vibl $GITFILES/$GITCONFIG $GITCONFIG"
	fi
fi

PROFILE=".profile"
DOTPROFILE="$dotfilesDir/shell/profile"
if [ -e $DOTPROFILE ]; then
	if check_yes_no "use $DOTPROFILE as $PROFILE?"; then
		if [ -e $PROFILE ]; then
			echo "$PROFILE exists"
			if check_yes_no "backup $PROFILE?"; then
				PROFILEBACKUP="$PROFILE.bak"
				echo "backing up to $PROFILEBACKUP"
				run "mv $PROFILE $PROFILEBACKUP"
			else
				run "rm $PROFILE"
			fi
			if [ -e $PROFILE ]; then
				echo "failed"
				exit 1
			fi
		fi
		run "cp -vilb $DOTPROFILE $PROFILE"
	fi
fi

if ! isCmd vim; then
	echo "vim not installed"
	if check_yes_no "install vim?"; then
		install "vim"
	fi
fi

if isCmd vim; then
	if check_yes_no "configure vim?"; then

		VIMFILES="$dotfilesDir/vim/files"
		if [ ! -d $VIMFILES ]; then
			echo "directory $VIMFILES does not exists"
			exit 1
		fi

		VIMDIR=".vim"
		if [ -d $VIMDIR ]; then
			echo "$VIMDIR directory exists"
			if check_yes_no "backup $VIMDIR?"; then
				VIMBACKUP="$VIMDIR.bak"
				echo "backing up to $VIMBACKUP"
				run "mv $VIMDIR $VIMBACKUP"
			else
				run "rm -rf $VIMDIR"
			fi
			if [ -d $VIMDIR ]; then
				echo "failed"
				exit 1
			fi
		fi
		run "cp -vilbr $VIMFILES/.vim ."

		VIMRC=".vimrc"
		if [ ! -e "$VIMFILES/$VIMRC" ]; then
			echo "file $VIMFILES/$VIMRC does not exists"
			exit 1
		fi

		if [ -e $VIMRC ]; then
			echo "$VIMRC exists"
			if check_yes_no "backup $VIMRC?"; then
				VIMRCBACKUP="$VIMRC.bak"
				echo "backing up to $VIMRCBACKUP"
				run "mv $VIMRC $VIMRCBACKUP"
			else
				run "rm $VIMRC"
			fi
			if [ -e $VIMRC ]; then
				echo "failed"
				exit 1
			fi
		fi
		run "cp -vilb $VIMFILES/$VIMRC ./$VIMRC"

		VIMPLUG="$VIMDIR/autoload/plug.vim"
		if [ -e $VIMPLUG ]; then
			#TODO fonnt for airline
			run "vim +PlugInstall +qall"
		else
			echo "no $VIMPLUG"
		fi

	fi #check_yes_no "install an configure vim?"
fi #type vim 2>/dev/null

if ! isCmd gvim; then
	echo "gvim not installed"
	if check_yes_no "install vim-gtk3?"; then
		install "vim-gtk3"
		if ! isCmd gvim; then
			echo "failed"
			exit 1
		fi
	fi
fi


if ! isCmd mc; then
	echo "mc not installed"
	if check_yes_no "install mc?"; then
		install "mc"
		if ! isCmd mc; then
			echo "failed"
			exit 1
		fi
	fi
fi

if isCmd mc; then
	MCFILES="$dotfilesDir/mc/files"
	if [ -d $MCFILES ]; then
		if check_yes_no "configure mc from $MCFILES?"; then
			run "cp -vibr $MCFILES/.config ."
		fi
	fi
fi


if ! isCmd audacious; then
	echo "audacious not found"
	if check_yes_no "install audacious?"; then
		install "audacious audacious-plugins"
		if ! isCmd audacious; then
			echo "failed"
			exit 1
		fi
		if isCmd rhythmbox; then
			echo "rhythmbox found"
			if check_yes_no "purge rhythmbox?"; then
				run "$SUDO apt purge rhythmbox"
			fi
			if isCmd rhythmbox; then
				echo "purge failed, uninstall manualy"
				read
			fi
		fi
	fi
fi

if isCmd audacious; then
	AUDACIOUSFILES="$dotfilesDir/audacious/files"
	if [ -d $AUDACIOUSFILES ]; then
		if check_yes_no "configure audacious from $AUDACIOUSFILES?"; then
			run "cp -vibr $AUDACIOUSFILES/.config ."
		fi
		#TODO mimeapps.list text replace to .config/mimeapps.list
		echo "associate audacious with audio files (from $AUDACIOUSFILES/mimeapps.list to .config/mimeapps.list"
		read
	fi
fi


if ! isCmd chromium-browser; then
	echo "chromium not found"
	if check_yes_no "install chromium?"; then
		install "chromium-browser"
		if ! type chromium-browser 2>/dev/null; then
			echo "failed"
			exit 1
		fi
	fi
fi

if isCmd firefox; then
	echo "firefox found"
	if check_yes_no "purge firefox?"; then
		run "$SUDO apt purge firefox"
	fi
	if isCmd firefox; then
		echo "purge failed, uninstall manualy"
		read
	fi
fi

fingerprintPpaUrl="https://launchpad.net/~fingerprint/+archive/ubuntu/fingerprint-gui"
runRes fingerprintSupportedDevices "curl $fingerprintPpaUrl | sed -e 's/<[^>]*>//g' | grep -o '[0-9a-f]\\{4\\}:[0-9a-f]\\{4\}'"
res=$?
if [ $res = 0 ]; then
	runRes usbDevices "lsusb | grep -o '[0-9a-f]\\{4\\}:[0-9a-f]\\{4\}'"
	res=$?
	if [ $res = 0 ]; then
		fingerprintSupported=0
		for device in $usbDevices; do
			for supported in $fingerprintSupportedDevices; do
				if [ "$device" = $supported ]; then
					fingerprintSupported=1
					break 2
				fi
			done
		done
		unset device
		unset supported

	else
		echo -e $cRed"can not fetch usb devices"$cDefault
	fi
else
	echo -e $cRed"can not fetch supported fprint devices"$cDefault
fi

if [ ! -z ${fingerprintSupported+x} ]; then
	if [ ! $fingerprintSupported = 0 ]; then
		echo "fingerprint supported"

		fingerprintPpa="ppa:fingerprint/fingerprint-gui"
		found=0
		while read -r ppa; do
			runRes ppaUser "echo $ppa | cut -d/ -f4"
			runRes ppaName "echo $ppa | cut -d/ -f5"
			if [ "ppa:$ppaUser/$ppaName" = $fingerprintPpa ]; then
				found=1
				break
			fi
		done <<< $(installedPpa)
		if [ $found = 0 ]; then
			run $SUDO" add-apt-repository $fingerprintPpa"
			run $SUDO" apt update"
		fi
		if ! isCmd "fingerprint-gui"; then
		  run $SUDO" apt install libbsapi policykit-1-fingerprint-gui fingerprint-gui"
			if isCmd "fingerprint-gui"; then
				echo "fingerprint support installed"
				echo -e "to configure fingerprint run ${cGreen}fingerprint-gui${cDefault}"
				echo -e $cRed"GNOME and KDE users WARNING:"$cDefault
				echo "if uninstalling, see Uninstall section at: $fingerprintPpaUrl"
				echo ""

				if check_yes_no "run ${cGreen}fingerprint-gui${cDefault}?"; then
					run "fingerprint-gui"
				fi
			else
				echo -e $cRed"fingerprint not installed"$cDefault
			fi
		fi
		unset ppaName
		unset ppaUser
		unset ppa
		unset found
	else
		echo "fingerprint NOT supported"
	fi
else
	echo "don't know, if fingerprint supported"
fi
