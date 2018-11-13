#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

echo -e "Installing vim components"

if .installCommand vim; then
	echo -e "Command ${cCmd}vim${cNone} installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

linkFile="${dotfilesBin}/.vimUndoClean"
if .hardlink "${dotfilesDir}/installers/vim/vim_undo_clean.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" created."
fi

if .installCommand gvim/vim-gtk3; then
	echo -e "Command ${cCmd}gvim${cNone} installed."
else
	echo -e $cErr"Instalation of "$cCmd"gvim"$cErr" failed."$cNone
fi

# register as default editor
.run "sudo update-alternatives --config editor"
