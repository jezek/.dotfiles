#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

if ! .isCmd zsh; then
	if .check_yes_no "install ${cPkg}zsh${cNone}?"; then
		.install zsh
		if ! .isCmd zsh; then
			echo -e $cErr"failed"$cNone
			[ "$1" = plugin ] && return 255
			exit 255
		fi
	fi
fi
if ! .isCmd zsh; then
	[ "$1" = plugin ] && return
	exit
fi

zplugDir="$HOME/.zplug"
zplugGithubUrl=$github"zplug/zplug.git"
if [ ! -d $zplugDir ]; then
	if .check_yes_no "install zplug to ${cDir}$zplugDir${cNone}?"; then
		.run "git clone $zplugGithubUrl $zplugDir"
		if [ ! -d $zplugDir ];then
			echo -e $cErr"install failed"$cNone
			[ "$1" = plugin ] && return 1
			exit 1
		fi
	fi
fi
if [ ! -d $zplugDir ]; then
	[ "$1" = plugin ] && return
	exit
fi

.hardlink "$dotfilesDir/shell/zsh/zprofile" "$HOME/.zprofile"
.hardlink "$dotfilesDir/shell/profile" "$HOME/.profile"
.hardlink "$dotfilesDir/shell/zsh/zplug/zshrc" "$HOME/.zshrc"
.hardlink "$dotfilesDir/shell/aliases" "$HOME/.zsh_aliases"
