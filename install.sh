#! /bin/bash

SUDO=''
if (( $EUID != 0 )); then
    SUDO='sudo'
fi

# colors
cDefault='\e[0m'
cRed='\e[91m'
cGreen='\e[92m'
cYellow='\e[93m'

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
		read -p "$1 $hint: " yn
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
	echo -e $cGreen$1$cDefault
	$1
	res=$?
	echo -e $cYellow"Result: $res"$cDefault
	return $res
}

# update & upgrade
##if check_yes_no "update & upgrade?" "n"; then
##	$SUDO apt update
##	$SUDO apt upgrade
##fi
##
##if check_yes_no "turn on sticky keys?" "n"; then
##	if ! type xkbset 2>/dev/null; then
##		echo "xkbset not installed"
##		run "$SUDO apt install xkbset"
##	fi
##	if type xkbset 2>/dev/null; then
##		echo ""
##		run "xkbset a sticky -twokey -latchlock"
##		run "xkbset exp =sticky"
##		echo "you should add theese somewhere to startup, or turn on in settings..."
##		read
##	else
##		echo -e $cRed"xkbset install failed!"$cDefault
##	fi
##fi

cd $HOME


if ! type git 2>/dev/null; then
	echo "need git and git not installed"
	run "$SUDO apt install git"
	if ! type git 2>/dev/null; then
		echo -e $cRed"git install failed!"$cDefault
		exit 1
	fi
fi

run "ssh -qT git@github.com"
echo $?
if [ "$?" = 1 ]; then
	echo "can connect to git via ssh"
else
	echo "can NOT connect to git via ssh"
fi
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

if ! type vim 2>/dev/null; then
	echo "vim not installed"
	if check_yes_no "install vim?"; then
		run "$SUDO apt install vim"
	fi
fi

if type vim 2>/dev/null; then
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

if ! type gvim 2>/dev/null; then
	echo "gvim not installed"
	if check_yes_no "install vim-gtk3?"; then
		run "$SUDO apt install vim-gtk3"
		if ! type gvim 2>/dev/null; then
			echo "failed"
			exit 1
		fi
	fi
fi


if ! type mc 2>/dev/null; then
	echo "mc not installed"
	if check_yes_no "install mc?"; then
		run "$SUDO apt install mc"
		if ! type mc 2>/dev/null; then
			echo "failed"
			exit 1
		fi
	fi
fi

if type mc 2>/dev/null; then
MCFILES="$DOTFILES/mc/files"
	if [ -d $MCFILES ]; then
		if check_yes_no "configure mc from $MCFILES?"; then
			run "cp -vibr $MCFILES/.config ."
		fi
	fi
fi


if ! type audacious 2>/dev/null; then
	echo "audacious not found"
	if check_yes_no "install audacious?"; then
		run "$SUDO apt install audacious audacious-plugins"
		if ! type audacious 2>/dev/null; then
			echo "failed"
			exit 1
		fi
		if type rhythmbox 2>/dev/null; then
			echo "rhythmbox found"
			if check_yes_no "purge rhythmbox?"; then
				run "$SUDO apt purge rhythmbox"
			fi
			if type rhythmbox 2>/dev/null; then
				echo "purge failed, uninstall manualy"
				read
			fi
		fi
	fi
fi

if type audacious 2>/dev/null; then
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
		run "$SUDO apt install chromium-browser"
		if ! type chromium-browser 2>/dev/null; then
			echo "failed"
			exit 1
		fi
	fi
fi

if type firefox 2>/dev/null; then
	echo "firefox found"
	if check_yes_no "purge firefox?"; then
		run "$SUDO apt purge firefox"
	fi
	if type firefox 2>/dev/null; then
		echo "purge failed, uninstall manualy"
		read
	fi
fi
