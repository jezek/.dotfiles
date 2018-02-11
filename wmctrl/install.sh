#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

#TODO ask for install
.needCommand wmctrl

if ! .isCmd wmctrl; then
	[ "$1" = plugin ] && return
	exit
fi

dotfilesBinDir="$dotfilesDir/bin"
maximizedScriptFile="$dotfilesDir/wmctrl/maximized.sh"


if [ ! -f $maximizedScriptFile ]; then
	echo -e $cErr"file not found: $maximizedScriptFile"$cNone
	[ "$1" = plugin ] && return 1
	exit 1
fi

.hardlink "$maximizedScriptFile" "$dotfilesBinDir/.maximized"
#TODO chmod??
