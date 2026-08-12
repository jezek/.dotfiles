#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if ! .needCommand curl tar sha256sum sort sed awk uname mktemp mv mkdir readlink; then
	[ "$1" = plugin ] && return 1
	exit 1
fi

goProfileSource="$dotfilesDir/installers/golang/profile.sh"
goProfileTarget="$dotfilesDir/shell/profile.d/golang.sh"
.run "mkdir -p '$dotfilesDir/shell/profile.d'"
.hardlink "$goProfileSource" "$goProfileTarget"

goMetadata=$(curl -fsSL 'https://go.dev/dl/?mode=json')
if [ -z "$goMetadata" ]; then
	echo -e $cErr"Fetching Go release metadata failed."$cNone
	[ "$1" = plugin ] && return 1
	exit 1
fi

goInstallVersion=$(printf '%s\n' "$goMetadata" | sed -n 's/^[[:space:]]*"version": "\(go[0-9.]*\)",$/\1/p' | head -n 1)
if [ -z "$goInstallVersion" ]; then
	echo -e $cErr"Could not determine the latest stable Go version."$cNone
	[ "$1" = plugin ] && return 1
	exit 1
fi

case "$(uname -m)" in
	x86_64 | amd64) goInstallArchitecture=amd64 ;;
	i386 | i486 | i586 | i686) goInstallArchitecture=386 ;;
	aarch64 | arm64) goInstallArchitecture=arm64 ;;
	armv6* | armv7*) goInstallArchitecture=armv6l ;;
	ppc64le | s390x | riscv64) goInstallArchitecture=$(uname -m) ;;
	*)
		echo -e $cErr"Unsupported Go architecture: $(uname -m)"$cNone
		[ "$1" = plugin ] && return 1
		exit 1
		;;
esac

goInstallFile="${goInstallVersion}.linux-${goInstallArchitecture}.tar.gz"
goInstallChecksum=$(printf '%s\n' "$goMetadata" | awk -v filename="$goInstallFile" '
	index($0, "\"filename\": \"" filename "\"") { found=1; next }
	found && /"sha256":/ { gsub(/[",]/, "", $2); print $2; exit }
')
unset goMetadata
if [ -z "$goInstallChecksum" ]; then
	echo -e $cErr"No checksum found for ${goInstallFile}."$cNone
	[ "$1" = plugin ] && return 1
	exit 1
fi

currentGoVersion=""
goPackage=""
if .isCmd go; then
	currentGoVersion=$(go env GOVERSION 2>/dev/null)
	goExecutable=$(readlink -f "$(command -v go)")
	case "$(.packageManager)" in
		apt) goPackage=$(dpkg-query -S "$goExecutable" 2>/dev/null | head -n 1 | cut -d: -f1) ;;
		pacman) goPackage=$(pacman -Qoq "$goExecutable" 2>/dev/null | head -n 1) ;;
	esac

	if [ "$currentGoVersion" = "$goInstallVersion" ]; then
		echo -e "${cCmd}Go ${currentGoVersion}${cNone} is already current."
		source "$goProfileTarget"
		[ "$1" = plugin ] && return 0
		exit 0
	fi
	if [ "$(printf '%s\n%s\n' "$goInstallVersion" "$currentGoVersion" | sort -V | tail -n 1)" = "$currentGoVersion" ]; then
		echo -e "Installed ${cCmd}${currentGoVersion}${cNone} is newer than offered ${goInstallVersion}; leaving it unchanged."
		source "$goProfileTarget"
		[ "$1" = plugin ] && return 0
		exit 0
	fi

	if [ -n "$goPackage" ]; then
		echo -e "Go ${currentGoVersion} is managed by package ${cPkg}${goPackage}${cNone}."
		if .check_yes_no "Upgrade it through the system package manager?"; then
			.install "$goPackage"
		else
			echo "Package-managed Go was left unchanged."
		fi
		[ "$1" = plugin ] && return 0
		exit 0
	fi

	goCurrentRoot=$(go env GOROOT 2>/dev/null)
	echo -e "Go ${currentGoVersion} is installed in ${cDir}${goCurrentRoot}${cNone}; latest is ${goInstallVersion}."
	if ! .check_yes_no "Replace this Go installation with ${goInstallVersion}?"; then
		[ "$1" = plugin ] && return 0
		exit 0
	fi
fi

goTargets=("/usr/local/go" "$HOME/.local/share/go")
goTarget=""
if [ -n "$goCurrentRoot" ] && { [ "$goCurrentRoot" = "${goTargets[0]}" ] || [ "$goCurrentRoot" = "${goTargets[1]}" ]; }; then
	goTarget="$goCurrentRoot"
else
	echo "Select Go installation directory:"
	select goTarget in "${goTargets[@]}" "install through package manager" "don't install"; do
		case "$goTarget" in
			"${goTargets[0]}" | "${goTargets[1]}") break ;;
			"install through package manager")
				case "$(.packageManager)" in
					apt) .install go/golang-go ;;
					pacman) .install go ;;
					*) echo -e $cErr"No supported package manager found."$cNone ;;
				esac
				goInstallResult=$?
				[ "$1" = plugin ] && return "$goInstallResult"
				exit "$goInstallResult"
				;;
			"don't install")
				[ "$1" = plugin ] && return 0
				exit 0
				;;
		esac
	done
fi

goSudo=""
if [ "$goTarget" = "/usr/local/go" ]; then
	goSudo=$SUDO
fi
goTargetParent=$(dirname "$goTarget")
goStage="${goTarget}.new.$$"
goBackup="${goTarget}.backup.$(date +%Y%m%d%H%M%S)"
goTempDir=$(mktemp -d)
goArchive="$goTempDir/$goInstallFile"

if ! curl -fL "https://go.dev/dl/$goInstallFile" -o "$goArchive"; then
	echo -e $cErr"Downloading ${goInstallFile} failed."$cNone
	rm -rf -- "$goTempDir"
	[ "$1" = plugin ] && return 1
	exit 1
fi
if ! printf '%s  %s\n' "$goInstallChecksum" "$goArchive" | sha256sum -c -; then
	echo -e $cErr"Checksum verification failed for ${goInstallFile}."$cNone
	rm -rf -- "$goTempDir"
	[ "$1" = plugin ] && return 1
	exit 1
fi
if ! tar -C "$goTempDir" -xzf "$goArchive" || [ ! -x "$goTempDir/go/bin/go" ]; then
	echo -e $cErr"Extracting ${goInstallFile} failed."$cNone
	rm -rf -- "$goTempDir"
	[ "$1" = plugin ] && return 1
	exit 1
fi

if ! .run "$goSudo mkdir -p '$goTargetParent'" || ! .run "$goSudo mv '$goTempDir/go' '$goStage'"; then
	echo -e $cErr"Could not stage Go in ${goTargetParent}."$cNone
	rm -rf -- "$goTempDir"
	[ "$1" = plugin ] && return 1
	exit 1
fi

if [ -e "$goTarget" ] && ! .run "$goSudo mv '$goTarget' '$goBackup'"; then
	echo -e $cErr"Could not back up existing Go installation."$cNone
	rm -rf -- "$goTempDir"
	[ "$1" = plugin ] && return 1
	exit 1
fi
if ! .run "$goSudo mv '$goStage' '$goTarget'"; then
	echo -e $cErr"Could not activate the new Go installation."$cNone
	[ -e "$goBackup" ] && .run "$goSudo mv '$goBackup' '$goTarget'"
	rm -rf -- "$goTempDir"
	[ "$1" = plugin ] && return 1
	exit 1
fi
rm -rf -- "$goTempDir"

source "$goProfileTarget"
echo -e "Installed ${cCmd}$($goTarget/bin/go version)${cNone}."
if [ -e "$goBackup" ]; then
	echo -e "Previous installation retained at ${cDir}${goBackup}${cNone}."
fi
echo "Start a new login shell to apply PATH changes everywhere."
