#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if .isCmd fingerprint-gui; then
	[ "$1" = plugin ] && return
	exit
fi

fingerprintPpaUrl="https://launchpad.net/~fingerprint/+archive/ubuntu/fingerprint-gui"
.runRes fingerprintSupportedDevices "curl $fingerprintPpaUrl | sed -e 's/<[^>]*>//g' | grep -o '[0-9a-f]\\{4\\}:[0-9a-f]\\{4\}'"
res=$?
if [ $res = 0 ]; then
	.runRes usbDevices "lsusb | grep -o '[0-9a-f]\\{4\\}:[0-9a-f]\\{4\}'"
	res=$?
	if [ $res = 0 ]; then
		fingerprintSupported=0
		for device in $usbDevices; do
			for supported in $fingerprintSupportedDevices; do
				if [ "$device" = $supported ]; then
					fingerprintSupported=1
					break 2
				fi
			done
		done
		unset device
		unset supported

	else
		echo -e $cErr"can not fetch usb devices"$cNone
	fi
else
	echo -e $cErr"can not fetch supported fprint devices"$cNone
fi

if [ ! -z ${fingerprintSupported+x} ]; then
	if [ ! $fingerprintSupported = 0 ]; then
		echo "fingerprint supported"

		fingerprintPpa="ppa:fingerprint/fingerprint-gui"
		found=0
		while read -r ppa; do
			.runRes ppaUser "echo $ppa | cut -d/ -f4"
			.runRes ppaName "echo $ppa | cut -d/ -f5"
			if [ "ppa:$ppaUser/$ppaName" = $fingerprintPpa ]; then
				found=1
				break
			fi
		done <<< $(.installedPpa)
		if [ $found = 0 ]; then
			.run $SUDO" add-apt-repository $fingerprintPpa"
			.run $SUDO" apt update"
		fi
		if ! .isCmd "fingerprint-gui"; then
		  .run $SUDO" apt install libbsapi policykit-1-fingerprint-gui fingerprint-gui"
			if .isCmd "fingerprint-gui"; then
				echo "fingerprint support installed"
				echo -e "to configure fingerprint .run ${cCmd}fingerprint-gui${cNone}"
				echo -e $cWarn"GNOME and KDE users WARNING:"$cNone
				echo "if uninstalling, see Uninstall section at: $fingerprintPpaUrl"
				echo ""

				if .check_yes_no ".run ${cCmd}fingerprint-gui${cNone}?"; then
					.run "fingerprint-gui"
				fi
			else
				echo -e $cErr"fingerprint not installed"$cNone
			fi
		fi
		unset ppaName
		unset ppaUser
		unset ppa
		unset found
	else
		echo "fingerprint NOT supported"
	fi
else
	echo "don't know, if fingerprint supported"
fi
