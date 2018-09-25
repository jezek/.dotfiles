#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

#TODO detect if finger touch is present, only then install scripts (and merge to master)

linkFile="${dotfilesBin}/.finger_toggle"
if .hardlink "${dotfilesDir}/installers/touch/finger_toggle.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" for finger touch toggle created."
fi
