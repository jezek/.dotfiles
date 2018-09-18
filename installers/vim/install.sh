#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if ! .isCmd vim; then
	echo -e "${cCmd}vim${cNone} not installed"
	if .check_yes_no "install ${cPkg}vim?${cNone}"; then
		.install "vim"
		if ! .isCmd vim; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi

if ! .isCmd vim; then
	[ "$1" = plugin ] && return
	exit
fi

#TODO link installers/vim/.vim_undo_clean.sh to bin
linkFile=$dotfilesDir"/bin/.vimUndoClean"
vimUndoCleanFile=$dotfilesDir"/installers/vim/vim_undo_clean.sh"
if [ ! $vimUndoCleanFile -ef $linkFile ]; then
	if ! .hardlink $vimUndoCleanFile $linkFile; then
		echo -e $cErr"Linking "$cFile"${vimUndoCleanFile}"$cErr" to "$cFile"${linkFile}"$cErr" failed."$cNone
	else
		echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" created."
	fi
fi

if ! .isCmd gvim; then
	echo -e "${cCmd}gvim${cNone} not installed"
	if .check_yes_no "install ${cPkg}vim-gtk3${cNone}?"; then
		.install "vim-gtk3"
		if ! .isCmd gvim; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi

