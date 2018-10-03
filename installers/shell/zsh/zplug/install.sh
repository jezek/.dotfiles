#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi


if .installCommand zsh; then
	echo -e "Shell ${cCmd}zsh${cNone} installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
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

.hardlink "$dotfilesDir/installers/shell/zsh/zprofile" "$HOME/.zprofile"
.hardlink "$dotfilesDir/installers/shell/profile" "$HOME/.profile"
.hardlink "$dotfilesDir/installers/shell/zsh/zplug/zshrc" "$HOME/.zshrc"
.hardlink "$dotfilesDir/installers/shell/aliases.sh" "$HOME/.zsh_aliases"
