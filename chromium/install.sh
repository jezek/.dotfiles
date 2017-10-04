#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

if ! .isCmd chromium-browser; then
	echo "${cCmd}chromium${cNone} not found"
	if .check_yes_no "install ${cPkg}chromium-browser${cNone}?"; then
		.install "chromium-browser"
		if ! type chromium-browser 2>/dev/null; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
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

