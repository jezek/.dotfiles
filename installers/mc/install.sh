#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi


if .installCommand mc; then
	echo -e "Midnight commander installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

dotMcini="$dotfilesDir/installers/mc/mc.ini"
mcini="$HOME/.config/mc/ini"

if [ -f "$dotMcini" ]; then
	.copyConfig "$dotMcini" "$mcini"
fi
