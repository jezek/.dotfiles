#!/bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

.needCommand xrandr xsetwacom grep awk

rotation=$1

case "$rotation" in
	auto | a | "")
		echo "auto"
		.runRes rotation "xrandr -q --verbose | grep 'connected' | grep -Eo  '\\) (normal|left|inverted|right) \\(' | grep -Eo '(normal|left|inverted|right)'"
		echo "Detected screen rotation: ${rotation}" 
		;;
esac

case "$rotation" in
	normal | n)
		rotation="none"
		;;
	inverted | i )
		rotation="half"
		;;
	left | l)
		rotation="ccw"
		;;
	right | r)
		rotation="cw"
		;;
	* )
		echo -e $cErr"\"${rotation}\" not supported.${cNone}\nUsage:\n\t$0 [auto|normal|left|right|inverted|a|n|l|r|i]"
		[ "$1" = plugin ] && return 1 || exit 1
esac

eval devices=( $(xsetwacom --list devices | awk -F"\t" '{print "\""$1"\"";}') )
for device in "${devices[@]}"; do
	echo "Device: ${device}"
	.runRes deviceRotation "xsetwacom --get \"${device}\" Rotate"
	echo -e "current rotation: ${deviceRotation}"
	if [ ! "${deviceRotation}" == "${rotation}" ]; then
		echo "Rotating to: ${rotation}"
		.run "xsetwacom --set \"${device}\" Rotate ${rotation}"
	else
		echo "Not rotating"
	fi
done

