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
.hardlink "$dotfilesDir/installers/git/git-summary/git-summary" "$dotfilesBin/gsum"
#TODO will be git-summary repo allways downloaded? no need to refresh?
#TODO! git-summary repo no longer exists... fork some of it's forks

