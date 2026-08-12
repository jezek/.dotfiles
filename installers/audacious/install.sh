#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

echo -e "Installing audacious music player with plugins"

if .installCommand audacious && .installPkg audacious-plugins; then
	echo -e "${cCmd}audacious${cNone} with plugins installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

audaConfigDir="$HOME/.config/audacious"
if [ ! -d "${audaConfigDir}" ]; then
	.run "mkdir -p $audaConfigDir"
fi

audaConfig="${audaConfigDir}/config"
dotAudaConfig="$dotfilesDir/installers/audacious/config"
if [ -f $dotAudaConfig ]; then
	if [ ! -f $audaConfig ]; then
		installed=1
	fi
	.run "cp -uvib $dotAudaConfig $audaConfig"

	if [ "$installed" = "1" ]; then
		if .check_yes_no "Associate Audacious with the configured audio MIME types?" && .needCommand xdg-mime/xdg-utils; then
			while IFS='=' read -r mimeType desktopFile; do
				case "$mimeType" in
					audio/*) .run "xdg-mime default '$desktopFile' '$mimeType'" ;;
				esac
			done < "$dotfilesDir/installers/audacious/mimeapps.list"
		fi
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
