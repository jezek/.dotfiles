#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

#TODO git credentials helper?
#[credential]
#	helper = /usr/share/doc/git/contrib/credential/gnome-keyring/git-credential-gnome-keyring

if ! .isCmd git; then
	exit
fi

.hardlink "$dotfilesDir/git/gitconfig" "$HOME/.gitconfig"

