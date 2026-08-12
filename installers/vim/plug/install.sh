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
	if .needCommand make; then
		.run "vim +PlugInstall +qall"
	else
		echo -e $cErr"Vim plugins require ${cCmd}make${cErr}; plugin installation skipped."$cNone
	fi
fi
unset installed

if ! .isCmd python3; then
	echo -e $cWarn"Using deoplete in Vim requires Python 3 and pynvim."$cNone
	return 0 2>/dev/null || exit 0
fi

if ! python3 -c 'import pynvim' >/dev/null 2>&1; then
	case "$(.packageManager)" in
		apt) .installPkg python3-pynvim ;;
		pacman) .installPkg python-pynvim ;;
	esac
fi

if ! python3 -c 'import pynvim' >/dev/null 2>&1; then
	pynvimVenv="$HOME/.local/share/vim/pynvim-venv"
	if python3 -m venv "$pynvimVenv" && "$pynvimVenv/bin/python" -m pip install --upgrade pynvim; then
		echo -e "Installed pynvim into isolated environment ${cFile}${pynvimVenv}${cNone}."
	else
		echo -e $cWarn"Could not install pynvim; deoplete completion will be unavailable."$cNone
	fi
	unset pynvimVenv
fi
