#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi
#TODO make it, so we can do it via one wget (goinup)
.needCommand select case while uname awk ls tar tee chown mkdir

#TODO upgrade golang version (inpiration: https://github.com/udhos/update-golang
if ! .isCmd go; then
	echo -e "${cCmd}go${cNone} not installed"
	goInstallSources=("latest from golang.org" "apt install golang gcc" "don't install")
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
				exit 0
				;;
			"${goInstallSources[2]}")
				[ "$1" = plugin ] && return
				exit 0
				;;
		esac
	done
else
	#TODO check if upgrade avalable, if yes, ask if upgrade
	if ! .check_yes_no "Go already installed. Continue and possibly upgrade?"; then
		[ "$1" = plugin ] && return
		exit 0
	fi
	#TODO only upgrade, don't ask any questions
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
.runRes goInstallVersion "curl https://golang.org/dl/ 2>/dev/null | grep -oP 'go\d+(\.\d+(\.\d+)?)?\s' | sort -V --reverse | head -1 | sed -e 's/\s\+$//'"
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

# home directories
if [ ! -d $HOME/.go/bin ]; then 
	.run "mkdir -p ${HOME}/.go/bin"
fi
if [ ! -d $HOME/.go/src ]; then 
	.run "mkdir -p ${HOME}/.go/src"
fi

#TODO check if allready in path, upgrade if outdated
# paths to profiles
profileEtc=()
profileHome=()
if [ "${goRoot}" = ${choices[0]} ]; then 
	profileEtc+=('PATH='$goRoot'/bin:$PATH')
else
	profileHome+=('GOROOT='$goRoot)
fi
profileHome=('PATH='$HOME'/.go/bin:$PATH')
profileHome+=('export GOPATH='$HOME'/.go:'$HOME'/Programy/go')


if [ ${#profileEtc[@]} -ne 0 ]; then
	profileEtcFile="/etc/profile.d/golang.sh"
	echo -e "writing to ${cFile}${profileEtcFile}${cNone}:"
	echo -en "${cYellow}"
	.toLines "${profileEtc[@]}"
	echo -en "${cNone}"
	.toLines "${profileEtc[@]}" | ${goSudo} tee ${profileEtcFile} >/dev/null
	res=$?
	if [ $res = 0 ]; then
		echo -e $cGreen"ok"$cNone
	else
		echo -e $cErr"failed!"$cNone
	fi
	source <(.toLines "${profileEtc[@]}")
	profileChanged=1
fi
if [ ${#profileHome[@]} -ne 0 ]; then
	if [ ! -d "$dotfilesDir/shell/profile.d" ]; then
		.run "mkdir -p '$dotfilesDir/shell/profile.d'"
	fi
	profileHomeFile="${dotfilesDir}/shell/profile.d/golang.sh"
	echo -e "writing to ${cFile}${profileHomeFile}${cNone}:"
	echo -en "${cYellow}"
	.toLines "${profileHome[@]}" | tee ${profileHomeFile}
	res=$?
	if [ $res = 0 ]; then
		echo -e $cGreen"ok"$cNone
	else
		echo -e $cErr"failed!"$cNone
	fi
	source <(.toLines "${profileHome[@]}")
	profileChanged=1
fi

if [ "$profileChanged" = 1 ]; then
	echo "logout/login needed for changes to be applied, or copy/paste yellow text to apply to this sesion"
	read
fi

.run $SUDO" apt install gcc"
