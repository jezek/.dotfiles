#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if ! .isCmd wmctrl; then
	echo -e "${cCmd}wmctrl${cNone} not installed"
	if .check_yes_no "install ${cPkg}wmctrl?${cNone}"; then
		.install "wmctrl"
		if ! .isCmd wmctrl; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi

if ! .isCmd wmctrl; then
	[ "$1" = plugin ] && return
	exit
fi

#TODO make as .linkToBin function to use it elsewhere
dotfilesBinDir="$dotfilesDir/bin"
maximizedScriptFile="$dotfilesDir/installers/wmctrl/maximized.sh"


if [ ! -f $maximizedScriptFile ]; then
	echo -e $cErr"file not found: $maximizedScriptFile"$cNone
	[ "$1" = plugin ] && return 1
	exit 1
fi

.hardlink "$maximizedScriptFile" "$dotfilesBinDir/.maximized"
