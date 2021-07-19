#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi
#TODO make it, so we can do it via one wget (goinup)
.needCommand select case while uname awk ls tar tee chown mkdir

# Get latest golang version from net
.runRes goInstallVersion "curl https://golang.org/dl/ 2>/dev/null | grep -oP 'go\d+(\.\d+(\.\d+)?)?\s' | sort -V --reverse | head -1 | sed -e 's/\s\+$//'"
if [ -z "$goInstallVersion" ]; then
	echo -e $cErr"fetching latest golang version failed"$cNone
	[ "$1" = plugin ] && return 1
	exit 1
fi

#TODO upgrade golang version (inpiration: https://github.com/udhos/update-golang
if ! .isCmd go; then
	echo -e "${cCmd}go${cNone} not installed"
	goInstallSources=("latest from golang.org (${goInstallVersion})" "install golang via package manager" "don't install")
	select src in "${goInstallSources[@]}"; do
		case $src in
			"${goInstallSources[0]}") 
				#continue the script 
				break
				;;
			"${goInstallSources[1]}")
				.install go gcc
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

	.runRes currentGoVersion "go version"

	if ! .check_yes_no "Go already installed ${currentGoVersion}. Continue and upgrade to ${goInstallVersion}?"; then
		[ "$1" = plugin ] && return
		exit 0
	fi
	

	.runRes goRoot "go env | grep GOROOT | sed 's/GOROOT=\"\\([^\"]\\+\\)\"/\\1/'"
	backup="${goRoot}~"
	if [ ! -w "$goRoot" ]; then
		goSudo=$SUDO
	fi
	.run $goSudo" mv '$goRoot' '$backup'"
	.run $goSudo" mkdir -p '$goRoot'"
	if [ ! -d "$goRoot" ]; then 
		unset goRoot
	fi
fi

#TODO uninstall apt installed golang for sure
# go not installed, install latest from golang.org
choices=("/usr/local/go" "$HOME/.go")
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
		if [ -z ${backup+x} ]; then
			backup="${choice}~"
			.run $goSudo" mv $choice $backup"
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

restoreBackup(){
	if [ ! "$backup" = "" ]; then
		echo -e "Restoring backup"
		.run $goSudo" mv $backup $goRoot"
	fi
}

# got $goRoot created

.runRes goInstallArchitecture "uname -m"
if [[ "${goInstallArchitecture}" =~ arm ]]; then
	goInstallArchitecture="armv6l"
elif [[ "${goInstallArchitecture}" =~ aarch64 ]]; then
	goInstallArchitecture="arm64"
elif [[ "${goInstallArchitecture}" =~ 64 ]]; then
	goInstallArchitecture="amd64"
else
	goInstallArchitecture="386"
fi
goInstallFile="https://storage.googleapis.com/golang/${goInstallVersion}.linux-${goInstallArchitecture}.tar.gz"
echo "latest go file: $goInstallFile"

if ! .run "curl --head -sf ${goInstallFile} >/dev/null"; then
	echo -e $cErr"file ${cFile}${goInstallFile}${cErr} not found"$cNone
	restoreBackup
	[ "$1" = plugin ] && return 3
	exit 3
fi
if ! .run "curl -f ${goInstallFile} | ${goSudo} tar -C ${goRoot} --strip-components=1 -vxzf - go"; then
	echo -e $cErr"failed to extract go files from ${cFile}${goInstallFile}${cErr} to ${cDir}${goRoot}"$cNone
	restoreBackup
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
		echo -e $cLightGreen"ok"$cNone
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
		echo -e $cLightGreen"ok"$cNone
	else
		echo -e $cErr"failed!"$cNone
	fi
	source <(.toLines "${profileHome[@]}")
	profileChanged=1
fi

if [ ! "$backup" = "" ]; then
	if .check_yes_no "remove backup "$cFile${backup}$cNone"?"; then
		.run $goSudo" rm -rf '$backup'"
	fi
fi

if [ "$profileChanged" = 1 ]; then
	echo "logout/login needed for changes to be applied, or copy/paste yellow text to apply to this sesion"
	read
fi

.install gcc
