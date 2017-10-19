#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

if ! .isCmd tlp; then
	echo -e "${cCmd}tlp${cNone} not installed"
	if .check_yes_no "install ${cPkg}tlp tlp-rdw?${cNone}"; then
		.install "tlp tlp-rdw"
		if ! .isCmd tlp; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi

if ! .isCmd tlp; then
	[ "$1" = plugin ] && return
	exit
fi

.run $SUDO" tlp start"
