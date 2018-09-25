#!/bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

#TODO detect if an tablet is present, only then install scripts (and merge to master)

linkFile="${dotfilesBin}/.tabrot"
if .hardlink "${dotfilesDir}/installers/tablet/rotate.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" for tablet input rotation created."
fi
