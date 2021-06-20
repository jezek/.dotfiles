#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

#TODO git credentials helper?
#[credential]
#	helper = /usr/share/doc/git/contrib/credential/gnome-keyring/git-credential-gnome-keyring

if .installCommand git; then
	echo -e "Command ${cCmd}git${cNone} installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

.hardlink "$dotfilesDir/installers/git/gitconfig" "$HOME/.gitconfig"
if .needCommand gawk; then
	.hardlink "$dotfilesDir/installers/git/git-summary/git-summary" "$dotfilesBin/gsum"
else
	echo -e $cWarn"git-summary will not be available"$cNone
fi
:
