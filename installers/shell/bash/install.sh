#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if .installCommand bash; then
	echo -e "Shell ${cCmd}bash${cNone} installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

if [ ! -d "$dotfilesDir/shell/profile.d" ]; then
	.run "mkdir -p '$dotfilesDir/shell/profile.d'"
fi
.hardlink "$dotfilesDir/installers/shell/profile" "$HOME/.profile"
.hardlink "$dotfilesDir/installers/shell/profile.d/readme.txt" "$dotfilesDir/shell/profile.d/readme.txt"
.hardlink "$dotfilesDir/installers/shell/bash/bashrc" "$HOME/.bashrc"
.hardlink "$dotfilesDir/installers/shell/aliases.sh" "$HOME/.bash_aliases"
