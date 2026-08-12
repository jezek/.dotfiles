#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

touchscreenFound=0
if .isCmd udevadm; then
	for inputEvent in /sys/class/input/event*; do
		if udevadm info --query=property --path="$inputEvent" 2>/dev/null | grep -qx 'ID_INPUT_TOUCHSCREEN=1'; then
			touchscreenFound=1
			break
		fi
	done
fi
if [ "$touchscreenFound" -ne 1 ]; then
	echo "No touchscreen input device detected; touchscreen helper skipped."
	unset touchscreenFound inputEvent
	return 0 2>/dev/null || exit 0
fi
unset touchscreenFound inputEvent

linkFile="${dotfilesBin}/.finger_toggle"
if .hardlink "${dotfilesDir}/installers/touch/finger_toggle.sh" $linkFile; then
	echo -e "Executable "$cCmd"$(basename ${linkFile})"$cNone" for finger touch toggle created."
fi
