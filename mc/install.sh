#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

if ! .isCmd mc; then
	echo "${cCmd}mc${cNone} not installed"
	if .check_yes_no "install ${cPkg}mc${cNone}?"; then
		.install "mc"
		if ! .isCmd mc; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi

if ! .isCmd mc; then
	[ "$1" = plugin ] && return
	exit
fi

dotMcini="$dotfilesDir/mc/mc.ini"
mcini="$HOME/.config/mc/ini"

if [ -f $dotMcini ]; then
	.run "cp -uvib $dotMcini $mcini"
fi

