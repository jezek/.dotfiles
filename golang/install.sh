#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

.needCommand select case while uname awk ls tar tee

if ! .isCmd go; then
	echo -e "${cCmd}go${cNone} not installed"
	goInstallSources=("latest from golang.org" "apt install golang" "don't install")
	select src in "${goInstallSources[@]}"; do
		case $src in
			"${goInstallSources[0]}") 
				#continue the script 
				break
				;;
			"${goInstallSources[1]}")
				.run $SUDO"${goInstallSources[1]}"
				if ! .isCmd go; then
					echo -e $cErr"failed"$cNone
					[ "$1" = plugin ] && return 1
					exit 1
				fi
				[ "$1" = plugin ] && return
				exit
				;;
			"${goInstallSources[2]}")
				[ "$1" = plugin ] && return
				exit 0
				;;
		esac
	done
fi

#TODO uninstall apt installed golang for sure
# go not installed, install latest from golang.org
choices=("/usr/local/go" "$HOME/.go")
goSudo=""
while [ -z ${goRoot+x} ]; do
	echo "Select golang root dir:"
	select choice in "${choices[@]}"; do
		case $choice in
			"${choices[0]}")
				goSudo=$SUDO
				break
				;;
			"${choices[1]}")
				break
				;;
		esac
	done
	if [ -d "$choice" ] && [ "$(ls -A $choice)" ]; then
		# is dir and not empty
		if .check_yes_no "backup ${cDir}$choice${cNone}?"; then
			.run $goSudo" mv $choice ${choice}~"
		else
			.run $goSudo" rm -rf $choice"
		fi
	fi
	if [ -d "$choice" ] && [ "$(ls -A $choice)" ]; then
		# is dir and not empty
		echo -e $cErr"failed to remove ${cDir}${choice}"$cNone
		[ "$1" = plugin ] && return 1
		exit 1
	fi
	if [ ! -d "$choice" ]; then 
		.run $goSudo" mkdir -p $choice"
	fi
	if [ -d $choice ]; then
		goRoot="$choice"
	fi
done

# got $goRoot created
.runRes goInstallVersion "curl https://golang.org/dl/ 2>/dev/null | grep -oP 'go\d+(\.\d+(\.\d+)?)?\s' | sort --reverse | head -1 | sed -e 's/\s\+$//'"
if [ -z "$goInstallVersion" ]; then
	echo -e $cErr"fetching latest golang version failed"$cNone
	[ "$1" = plugin ] && return 2
	exit 2
fi

.runRes goInstallArchitecture "uname -m"
if [[ "${goInstallArchitecture}" =~ arm ]]; then
	goInstallArchitecture="armv6l"
elif [[ "${goInstallArchitecture}" =~ 64 ]]; then
	goInstallArchitecture="amd64"
else
	goInstallArchitecture="386"
fi
goInstallFile="https://storage.googleapis.com/golang/${goInstallVersion}.linux-${goInstallArchitecture}.tar.gz"
echo "latest go file: $goInstallFile"

if ! .run "curl --head -sf ${goInstallFile} >/dev/null"; then
	echo -e $cErr"file ${cFile}${goInstallFile}${cErr} not found"$cNone
	#TODO if backup, revert
	[ "$1" = plugin ] && return 3
	exit 3
fi
if ! .run "curl -f ${goInstallFile} | ${goSudo} tar -C ${goRoot} --strip-components=1 -vxzf - go"; then
	echo -e $cErr"failed to extract go files from ${cFile}${goInstallFile}${cErr} to ${cDir}${goRoot}"$cNone
	#TODO if backup, revert
	[ "$1" = plugin ] && return 4
	exit 4
fi
# go extracted to $goRoot
.runRes og "ls -ld $(dirname ${goRoot}) | awk '{print \$3\":\"\$4}'"
echo "$goRoot parent owner:group = $og"
.run "${goSudo} chown -R ${og} ${goRoot}"

profileDir=""
if [ "${goRoot}" = ${choices[0]} ]; then 
	.run "echo \"PATH=${goRoot}/bin:\\\$PATH\" | ${goSudo} tee /etc/profile.d/golang.sh"
	.run "export PATH=${goRoot}/bin:$PATH"
fi
.run "echo \"PATH=${HOME}/.go/bin:\\\$PATH\" | tee ${dotfilesDir}/shell/profile.d/golang.sh"
.run "export PATH=${HOME}/.go/bin:$PATH"
