#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi


if .isCmd tlp; then
	echo -e "Power saving manager - tlp, allready installed."
	[ "$1" = plugin ] && return
	exit
fi

if ! .check_yes_no "Install and run power saving manager - tlp?"; then
	[ "$1" = plugin ] && return
	exit
fi


if .installCommand tlp "tlp/tlp-rdw"; then
	echo -e "Command ${cCmd}tlp${cNone} installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

.run $SUDO" tlp start"
