#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

# SSH remotes are preferred by this configuration. Do not enable plaintext
# credential storage globally; HTTPS users can opt into an installed secure
# libsecret or OAuth helper through `git config --global credential.helper`.

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
