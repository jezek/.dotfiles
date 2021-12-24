#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

.needCommand xinput grep

.runRes touchIds "xinput list | grep -iP 'finger touch|elan9008:00 04f3:2bb1\\s*id' | grep -oP '(?<=id=)\d+'"
res=$?
touchIds=($touchIds)
if [ $res -ne 0 ] || [ ${#touchIds[@]} = 0 ]; then
	echo -e $cErr"failed to find finger touch screen"$cNone
	[ "$1" = plugin ] && return 1 || exit 1
fi
echo "${#touchIds[@]} finger touch screen id(s) found: ${touchIds[@]}"

for id in ${touchIds[@]}; do
	echo "toggling device id: ${id}"
	.runRes enabled "xinput list-props ${id} | grep 'Device Enabled' | grep -oP '(?<=:\t)\d'"
	res=$?
	if [ $res -ne 0 ]; then
		echo -e $cErr"failed to find out if device is enabled"$cNone
		continue
	fi
	echo "device enabled: ${enabled}"
	cmd="enable"
	if [ "${enabled}" = "1" ]; then
		cmd="disable"
	fi

	.run "xinput ${cmd} ${id}"
	res=$?
	if [ $res -ne 0 ]; then
		echo -e $cErr"failed to ${cmd}"$cNone
	else
		echo "device ${cmd}d"
	fi
done

