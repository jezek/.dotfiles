#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

if ! .isCmd bash; then
	if .check_yes_no "install ${cPkg}bash${cNone}?"; then
		.install bash
		if ! .isCmd bash; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi
if ! .isCmd bash; then
	[ "$1" = plugin ] && return
	exit
fi

.hardlink "$dotfilesDir/shell/profile" "$HOME/.profile"
.hardlink "$dotfilesDir/shell/bash/bashrc" "$HOME/.bashrc"
.hardlink "$dotfilesDir/shell/aliases" "$HOME/.bash_aliases"
