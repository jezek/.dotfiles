#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

echo -e "Installing window manager control utility "$cCmd"wmctrl"$cNone"."

if .installCommand wmctrl; then
	echo -e "Command ${cCmd}wmctrl${cNone} installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

maximizedScriptFile="$dotfilesDir/installers/wmctrl/maximized.sh"
if .hardlink "$maximizedScriptFile" "$dotfilesBin/.maximized"; then
	echo -e "Executable "$cCmd".maximized"$cNone" created."
fi
