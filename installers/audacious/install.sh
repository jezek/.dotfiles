#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

if ! .isCmd audacious; then
	echo "${cCmd}audacious${cNone} not installed"
	if .check_yes_no "install ${cPkg}audacious audacious-plugins${cNone}?"; then
		.install "audacious audacious-plugins"
		if ! .isCmd audacious; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi

if ! .isCmd audacious; then
	[ "$1" = plugin ] && return
	exit
fi

audaConfig="$HOME/.config/audacious/config"
dotAudaConfig="$dotfilesDir/audacious/config"
if [ -f $dotAudaConfig ]; then
	if [ ! -f $audaConfig ]; then
		installed=1
	fi
	.run "cp -uvib $dotAudaConfig $audaConfig"

	if [ "$installed" = "1" ]; then
		#TODO mimeapps.list text replace to .config/mimeapps.list
		echo "associate audacious with audio files (from ${cFile}$dotfilesDir/audacious/mimeapps.list${cNone} to ${cFile}$HOME/.config/mimeapps.list${cNone}"
		read
	fi
fi

if .isCmd rhythmbox; then
	echo -e "${cCmd}rhythmbox${cNone} found"
	if .check_yes_no "purge ${cPkg}rhythmbox${cNone}?"; then
		.run $SUDO" apt purge rhythmbox"
	fi
	if .isCmd rhythmbox; then
		echo "purge failed, uninstall manualy"
		read
	fi
fi
