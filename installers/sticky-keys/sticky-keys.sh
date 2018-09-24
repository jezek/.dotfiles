#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if ! .isCmd xkbset; then
	echo -e "need ${cCmd}xkbset${cNone}, which is not installed"
	echo -e "install using package manager or run:"
	echo -e $cCmd"${dotfilesDir}/installers/sticky-keys/install.sh"$cNone
	exit
fi

.run "xkbset q | grep -A2 Sticky-Keys"

.run "xkbset a sticky -twokey -latchlock"
.run "xkbset exp =sticky"

.run "xkbset q | grep -A2 Sticky-Keys"

