#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

if .check_yes_no "turn on sticky keys?" "n"; then
	xkbsetinstall=0
	if ! .isCmd xkbset; then
		echo "need ${cCmd}xkbset${cNone}, which is not installed"
		if .check_yes_no "install ${cPkg}xkbset${cNone}?"; then
			xkbsetinstall=1
			.install "xkbset"
		fi
	fi
	if .isCmd xkbset; then
		echo ""
		.run "xkbset a sticky -twokey -latchlock"
		.run "xkbset exp =sticky"
		echo "you should add theese somewhere to startup, or turn on in settings..."
		read
	elif [ "$xkbsetinstall" = 1 ]; then
		echo -e $cErr"xkbset install failed!"$cNone
	fi
fi