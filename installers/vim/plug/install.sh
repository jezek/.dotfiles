#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if ! .isCmd vim; then
	[ "$1" = plugin ] && return
	exit 0
fi

vimplug="$HOME/.vim/autoload/plug.vim"
vimplugUrl="https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim"

if [ ! -f $vimplug ]; then
	if .check_yes_no "download vim-plug ($vimplugUrl) to ${cFile}$vimplug${cNone}?"; then
		.run "curl -fLo $vimplug --create-dirs $vimplugUrl"
		installed=1
		if [ ! -f $vimplug ]; then
			echo -e $cErr"download failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi

if [ ! -f $vimplug ]; then
	[ "$1" = plugin ] && return
	exit 0
fi

.hardlink "$dotfilesDir/installers/vim/plug/vimrc" "$HOME/.vimrc"
if [ "$installed" = "1" ]; then
	.run "vim +PlugInstall +qall"
fi
