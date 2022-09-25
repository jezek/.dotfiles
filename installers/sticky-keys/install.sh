#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if [ "wayland" = "${XDG_SESSION_TYPE}" ]; then
	1>&2 echo -e $cErr"Sticky keys"$cNone" via xkbset doesn't work on wayland"
	[ "$1" = plugin ] && return 1 || exit 1
fi

if ! .check_yes_no "Install sticky key support?"; then
	[ "$1" = plugin ] && return
	exit 0
fi

if .installCommand xkbset; then
	echo -e "Command ${cCmd}xkbset${cNone} for keyboard configuration under X installed"
else
	[ "$1" = plugin ] && return 1
	exit 1
fi

linkFile="${dotfilesBin}/.stickeys"
if .hardlink "${dotfilesDir}/installers/sticky-keys/sticky-keys.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" created."
fi

echo ""
.run "xkbset a sticky -twokey -latchlock"
.run "xkbset exp =sticky"
echo ""
echo "You should add theese somewhere to startup, or turn on in settings."
echo -e "Or use "$cCmd".stickeys"$cNone
read
