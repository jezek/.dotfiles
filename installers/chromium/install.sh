#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if .installCommand "chromium-browser"; then
	echo -e $cCmd"chromium-browser"$cNone" installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

if .isCmd firefox; then
	echo "${cCmd}firefox${cNone} found"
	if .check_yes_no "purge ${cPkg}firefox${cNone}?"; then
		.run $SUDO" apt purge firefox"
	fi
	if .isCmd firefox; then
		echo "purge failed, uninstall manualy"
		read
	fi
fi

