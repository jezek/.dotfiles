#!/bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

tabletFound=0
if .isCmd udevadm; then
	for inputEvent in /sys/class/input/event*; do
		if udevadm info --query=property --path="$inputEvent" 2>/dev/null | grep -qx 'ID_INPUT_TABLET=1'; then
			tabletFound=1
			break
		fi
	done
fi
if [ "$tabletFound" -ne 1 ]; then
	echo "No tablet input device detected; tablet rotation helper skipped."
	unset tabletFound inputEvent
	return 0 2>/dev/null || exit 0
fi
unset tabletFound inputEvent

linkFile="${dotfilesBin}/.tabrot"
if .hardlink "${dotfilesDir}/installers/tablet/rotate.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" for tablet input rotation created."
fi
