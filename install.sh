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
for arg in $@; do
	case "$arg" in
		debug ) debug=1;;
		* )
			echo -e $cErr"Unknown argument: $arg"$cNone
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
				echo -e "${cErr}Please answer y or n for yes or no.${cNone}";;
		esac
	done;
	echo "Yes"
}

run(){
	if [ ! $# = 1 ]; then
		(>&2 echo -e $cErr"run: need 1 argument, got $#: "$cNone$@)
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
runRes(){
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr"runRes: need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local resVar=$1
	local cmd=$2
	resVal=`run "$cmd"`
	local r=$?
	eval $resVar="'$resVal'"
	if [ "$debug" = 1 ]; then
		(>&2 echo -e Result Value: $cYellow$resVal$cNone)
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

essentials=(apt add-apt-repository git curl ssh sed)
missing=()
for cmd in "${essentials[@]}"; do
	if ! isCmd $cmd; then
		missing+=($cmd)
	fi
done

if [ ! ${#missing[@]} = 0 ]; then
	echo "we need theese essential programs for this script:"
	echo -e $cCmd${missing[@]}$cNone
	if check_yes_no "install and continue?"; then
		installed=()
		for pkg in ${missing[@]}; do
			install $pkg
			if ! isCmd $pkg; then
				echo -e $cErr"$pkg install failed!"$cNone
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

cd $HOME

#echo "testing:"
#
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
		echo "need ${cCmd}xkbset${cNone}, which is not installed"
		if check_yes_no "install ${cPkg}xkbset${cNone}?"; then
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
		echo -e $cErr"xkbset install failed!"$cNone
	fi
fi


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
					if check_yes_no "this operation needs ${cPkg}ssh-keygen${cNone}. install?"; then
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
					echo -e $cErr"generating ssh key failed"$cNone
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
	github="git@github.com:$githubName"
fi

dotfilesDir=".dotfiles"
if [ ! -d $dotfilesDir ]; then
	gitdotfiles=""
	run "git clone $github/.dotfiles.git"
	if [ ! -d $dotfilesDir ]; then
		echo "clonning ${cFile}$dotfilesDir${cNone} from github failed"
		exit 1
	fi
fi

#TODO git credentials helper?
#[credential]
#	helper = /usr/share/doc/git/contrib/credential/gnome-keyring/git-credential-gnome-keyring
GITFILES="$dotfilesDir/git/files"
GITCONFIG=".gitconfig"
if [ -e "$GITFILES/$GITCONFIG" ]; then
	if check_yes_no "configure ${cFile}$GITCONFIG${cNone} from ${cFile}$GITFILES/$GITCONFIG${cNone}?"; then
		if [ -e $GITCONFIG ]; then
			echo "${cFile}$GITCONFIG${cNone} exists"
			if check_yes_no "backup ${cFile}$GITCONFIG${cNone}?"; then
				GITCONFIGBACKUP="$GITCONFIG.bak"
				echo "backing up to ${cFile}$GITCONFIGBACKUP${cNone}"
				run "mv $GITCONFIG $GITCONFIGBACKUP"
			else
				run "rm $GITCONFIG"
			fi
		fi
		run "cp -vibl $GITFILES/$GITCONFIG $GITCONFIG"
	fi
fi

PROFILE=".profile"
DOTPROFILE="$dotfilesDir/shell/profile"
if [ -e $DOTPROFILE ]; then
	if check_yes_no "use ${cFile}$DOTPROFILE${cNone} as ${cFile}$PROFILE${cNone}?"; then
		if [ -e $PROFILE ]; then
			echo "${cFile}$PROFILE${cNone} exists"
			if check_yes_no "backup ${cFile}$PROFILE${cNone}?"; then
				PROFILEBACKUP="$PROFILE.bak"
				echo "backing up to ${cFile}$PROFILEBACKUP${cNone}"
				run "mv $PROFILE $PROFILEBACKUP"
			else
				run "rm $PROFILE"
			fi
		fi
		run "cp -vilb $DOTPROFILE $PROFILE"
	fi
fi

bashrc=".bashrc"
dotBashrcFile="$dotfilesDir/bash/bashrc"
if [ -e $dotBashrcFile ]; then
	if check_yes_no "use ${cFile}$dotBashrcFile${cNone} as ${cFile}$bashrc${cNone}?"; then
		if [ -e $bashrc ]; then
			echo "$bashrc exists"
			if check_yes_no "backup ${cFile}$bashrc${cNone}?"; then
				bashrcBackup="$bashrc.bak"
				echo "backing up to ${cFile}$bashrcBackup${cNone}"
				run "mv $bashrc $bashrcBackup"
			else
				run "rm $bashrc"
			fi
		fi
		run "cp -vilb $dotBashrcFile $bashrc"
	fi
fi
bashAliases=".bash_aliases"
dotBashAliasesFile="$dotfilesDir/bash/bash_aliases"
if [ -e $dotBashAliasesFile ]; then
	if check_yes_no "use ${cFile}$dotBashAliasesFile${cNone} as ${cFile}$bashAliases${cNone}?"; then
		if [ -e $bashAliases ]; then
			echo "$bashAliases exists"
			if check_yes_no "backup ${cFile}$bashAliases${cNone}?"; then
				bashAliasesBackup="$bashAliases.bak"
				echo "backing up to ${cFile}$bashAliasesBackup${cNone}"
				run "mv $bashAliases $bashAliasesBackup"
			else
				run "rm $bashAliases"
			fi
		fi
		run "cp -vilb $dotBashAliasesFile $bashAliases"
	fi
fi

if ! isCmd vim; then
	echo "${cCmd}vim${cNone} not installed"
	if check_yes_no "install ${cPkg}vim?${cNone}"; then
		install "vim"
	fi
fi

if isCmd vim; then
	if check_yes_no "configure ${cCmd}vim${cNone}?"; then

		VIMFILES="$dotfilesDir/vim/files"
		if [ ! -d $VIMFILES ]; then
			echo "directory ${cDir}$VIMFILES${cNone} does not exists"
			exit 1
		fi

		VIMDIR=".vim"
		if [ -d $VIMDIR ]; then
			echo "${cDir}$VIMDIR${cNone} directory exists"
			if check_yes_no "backup $VIMDIR?"; then
				VIMBACKUP="$VIMDIR.bak"
				echo "backing up to ${cDir}$VIMBACKUP${cNone}"
				run "mv $VIMDIR $VIMBACKUP"
			else
				run "rm -rf $VIMDIR"
			fi
			if [ -d $VIMDIR ]; then
				echo "failed"
				read
			fi
		fi
		run "cp -vilbr $VIMFILES/.vim ."

		VIMRC=".vimrc"
		if [ ! -e "$VIMFILES/$VIMRC" ]; then
			echo "file ${cFile}$VIMFILES/$VIMRC${cNone} does not exists"
			exit 1
		fi

		if [ -e $VIMRC ]; then
			echo "${cFile}$VIMRC${cNone} exists"
			if check_yes_no "backup ${cFile}$VIMRC${cNone}?"; then
				VIMRCBACKUP="$VIMRC.bak"
				echo "backing up to ${cFile}$VIMRCBACKUP${cNone}"
				run "mv $VIMRC $VIMRCBACKUP"
			else
				run "rm $VIMRC"
			fi
			if [ -e $VIMRC ]; then
				echo "failed"
				read
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
	echo "${cCmd}gvim${cNone} not installed"
	if check_yes_no "install ${cPkg}vim-gtk3${cNone}?"; then
		install "vim-gtk3"
		if ! isCmd gvim; then
			echo "failed"
			read
		fi
	fi
fi


if ! isCmd mc; then
	echo "${cCmd}mc${cNone} not installed"
	if check_yes_no "install ${cPkg}mc${cNone}?"; then
		install "mc"
		if ! isCmd mc; then
			echo "failed"
			read
		fi
	fi
fi

if isCmd mc; then
	MCFILES="$dotfilesDir/mc/files"
	if [ -d $MCFILES ]; then
		if check_yes_no "configure ${cCmd}mc${cNone} from ${cDir}$MCFILES${cNone}?"; then
			run "cp -vibr $MCFILES/.config ."
		fi
	fi
fi


if ! isCmd audacious; then
	echo "${cCmd}audacious${cNone} not found"
	if check_yes_no "install ${cPkg}audacious audacious-plugins${cNone}?"; then
		install "audacious audacious-plugins"
		if ! isCmd audacious; then
			echo "failed"
			read
		fi
		if isCmd rhythmbox; then
			echo "${cCmd}rhythmbox${cNone} found"
			if check_yes_no "purge ${cPkg}rhythmbox${cNone}?"; then
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
		if check_yes_no "configure ${cCmd}audacious${cNone} from ${cDir}$AUDACIOUSFILES${cNone}?"; then
			run "cp -vibr $AUDACIOUSFILES/.config ."
		fi
		#TODO mimeapps.list text replace to .config/mimeapps.list
		echo "associate audacious with audio files (from ${cFile}$AUDACIOUSFILES/mimeapps.list${cNone} to ${cFile}.config/mimeapps.list${cNone}"
		read
	fi
fi


if ! isCmd chromium-browser; then
	echo "${cCmd}chromium${cNone} not found"
	if check_yes_no "install ${cPkg}chromium-browser${cNone}?"; then
		install "chromium-browser"
		if ! type chromium-browser 2>/dev/null; then
			echo "failed"
			read
		fi
	fi
fi

if isCmd firefox; then
	echo "${cCmd}firefox${cNone} found"
	if check_yes_no "purge ${cPkg}firefox${cNone}?"; then
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
		echo -e $cErr"can not fetch usb devices"$cNone
	fi
else
	echo -e $cErr"can not fetch supported fprint devices"$cNone
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
				echo -e "to configure fingerprint run ${cCmd}fingerprint-gui${cNone}"
				echo -e $cWarn"GNOME and KDE users WARNING:"$cNone
				echo "if uninstalling, see Uninstall section at: $fingerprintPpaUrl"
				echo ""

				if check_yes_no "run ${cCmd}fingerprint-gui${cNone}?"; then
					run "fingerprint-gui"
				fi
			else
				echo -e $cErr"fingerprint not installed"$cNone
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
