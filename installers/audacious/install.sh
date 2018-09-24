#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

echo -e "Installing audacious music player with plugins"

if .installCommand audacious 'audacious/audacious-plugins'; then
	echo -e "${cCmd}audacious${cNone} with plugins installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

audaConfig="$HOME/.config/audacious/config"
dotAudaConfig="$dotfilesDir/installers/audacious/config"
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
	unset installed
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
