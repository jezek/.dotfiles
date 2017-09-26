#! /bin/bash

# colors
cDefault='\e[0m'
cRed='\e[91m'
cGreen='\e[92m'
cBlue='\e[94m'
cYellow='\e[93m'

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
	if [ $# = 0 ] || [ $# -gt 2 ]; then
		return 255
	fi
	local cmd=$1
	if [ $# = 2 ]; then
		local resVar=$1
		local cmd=$2
	fi
	echo -e $cGreen$cmd$cDefault
	resVal=`$cmd`
	res=$?
	if [ "$debug" = 1 ]; then
		local rc=$cGreen
		if [ ! $res = 0 ]; then
			local rc=$cRed
		fi
		echo -e "Result: "$rc$res$cDefault
		echo -e Result Value: $cYellow$resVal$cDefault
	fi
	if [ $# = 2 ]; then
		eval $resVar="'$resVal'"
	fi
	return $res
}

install(){
	run $SUDO" apt install "$1
	return $?
}

isCmd(){
	type $1 >/dev/null 2>&1
	return $?
}

### update & upgrade
##if check_yes_no "update & upgrade?" "n"; then
##	$SUDO apt update
##	$SUDO apt upgrade
##fi
##
##if check_yes_no "turn on sticky keys?" "n"; then
##	xkbsetinstall=0
##	if ! isCmd xkbset; then
##		echo "need xkbset, which is not installed"
##		if check_yes_no "install xkbset?"; then
##			xkbsetinstall=1
##			install "xkbset"
##		fi
##	fi
##	if isCmd xkbset; then
##		echo ""
##		run "xkbset a sticky -twokey -latchlock"
##		run "xkbset exp =sticky"
##		echo "you should add theese somewhere to startup, or turn on in settings..."
##		read
##	elif [ "$xkbsetinstall" = 1 ]; then
##		echo -e $cRed"xkbset install failed!"$cDefault
##	fi
##fi
##
##cd $HOME


essentials=(apt git curl ssh)
missing=()
for cmd in "${essentials[@]}"; do
	if ! isCmd $cmd; then
		missing+=($cmd)
	fi
done
echo "missing: ${missing[@]}"
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


run "ssh -qT git@github.com"
gsa=$?
if [ ! "$gsa" = 1 ]; then
	if check_yes_no "do you want use your github with ssh on this device?"; then
		pubKey=""
		sshDir="$HOME/.ssh" 
		sshDirPubKey=$sshDir"/id_rsa.pub"
		if [ -e $sshDirPubKey ]; then
			pubKey=$sshDirPubKey
		fi
		if [ -z $pubKey ]; then
			if check_yes_no "no public key ($sshDirPubKey) found. create new?"; then
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
						comment=" -C \"$comment\""
					fi
					#TODO writing
					run "ssh-keygen -t rsa -b 4096 $comment"
				else
					echo -e $cRed"generating ssh key failed"$cDefault
				fi
				if [ -e $sshDirPubKey ]; then
					pubKey=$sshDirPubKey
				fi
			fi
		fi
		if [ ! -z $pubKey ]; then
			#TODO
			echo "got pubkey: $pubKey"
		else
			echo $cRed"no public key found, github with ssh access not configured"$cDefault
		fi
	fi
fi
unset gsa
#TODO finish this
exit

DOTFILES=".dotfiles"
if [ ! -d $DOTFILES ]; then
	GITDOTFILES="https://github.com/jezek/.dotfiles.git"
	if check_yes_no "use ssh for git .dotfiles?"; then
		#TODO check for keys, generate, forward to git
		GITDOTFILES="git@github.com:jezek/.dotfiles.git"
	fi
	run "git clone $GITDOTFILES"
	if [ ! -d $DOTFILES ]; then
		echo "clonning $DOTFILES from git failed"
		exit 1
	fi
else
	echo "$DOTFILES are present"
fi

GITFILES="$DOTFILES/git/files"
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
DOTPROFILE="$DOTFILES/shell/profile"
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

		VIMFILES="$DOTFILES/vim/files"
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
	MCFILES="$DOTFILES/mc/files"
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
	AUDACIOUSFILES="$DOTFILES/audacious/files"
	if [ -d $AUDACIOUSFILES ]; then
		if check_yes_no "configure audacious from $AUDACIOUSFILES?"; then
			run "cp -vibr $AUDACIOUSFILES/.config ."
		fi
		#TODO mimeapps.list text replace to .config/mimeapps.list
		echo "associate audacious with audio files (from $AUDACIOUSFILES/mimeapps.list to .config/mimeapps.list"
		read
	fi
fi


if ! type chromium-browser 2>/dev/null; then
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
