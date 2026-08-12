#!/bin/bash
# This installer predates strict-mode Bash. Keep predicate failures explicit and
# pass filenames as quoted arguments or arrays while the remaining call sites
# are migrated incrementally.

# colors
cNone='\e[0m'
# named colors
cBlack='\e[30m'
cRed='\e[31m'
cGreen='\e[32m'
cYellow='\e[33m'
cBlue='\e[34m'
cMagenta='\e[35m'
cCyan='\e[36m'
cLightGray='\e[37m'
cDarkGray='\e[90m'
cLightRed='\e[91m'
cLightGreen='\e[92m'
cLightYellow='\e[93m'
cLightBlue='\e[94m'
cLightMagenta='\e[95m'
cLightCyan='\e[96m'
cWhite='\e[97m'

# layout colors
cErr=$cRed
cWarn=$cRed
cOk=$cLightGreen
cRun=$cGreen
cCmd=$cYellow
cPkg=$cBlue
cFile=$cMagenta
cInput=$cLightYellow

# debug=0
onlyEssential=0
for arg in $@; do
	case "$arg" in
		debug ) debug=1;;
		essentials ) onlyEssential=1;;
		* )
			if [ $onlyEssential -eq 0 ]; then
				echo -e $cErr"Unknown argument: $arg"$cNone"\nAll arguments: $@"
				exit 1
			fi
			;;
	esac
done

# sudo
SUDO=''
if (( $EUID != 0 )); then
	SUDO='sudo'
fi

.dotfiles(){ return 1; }

.toLines() {
	printf '%s\n' "$@"
}

# Load literal variable assignments from a data-only config file.
# Usage: .loadConfig FILE ALLOWED_VARIABLE...
.loadConfig() {
	if [ "$#" -lt 2 ]; then
		(>&2 echo -e "$cErr"".loadConfig: expected a config file and at least one allowed variable"$cNone)
		return 255
	fi

	local configFile="$1"
	shift
	if [ ! -r "$configFile" ]; then
		(>&2 echo -e "$cErr""Config file is not readable: "$cFile"${configFile}"$cNone)
		return 1
	fi

	local configLine configTrimmed configName configRaw configValue configVariable configExport
	local configLineNumber=0
	declare -A configAllowed=()
	declare -A configSeen=()
	declare -A configValues=()
	declare -A configExports=()

	for configVariable in "$@"; do
		if [[ ! "$configVariable" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
			(>&2 echo -e "$cErr"".loadConfig: invalid allowed variable name: "$cNone"$configVariable")
			return 255
		fi
		if [[ -n "${configAllowed[$configVariable]+x}" ]]; then
			(>&2 echo -e "$cErr"".loadConfig: duplicate allowed variable: "$cNone"$configVariable")
			return 255
		fi
		configAllowed[$configVariable]=1
	done

	while IFS= read -r configLine || [ -n "$configLine" ]; do
		configLineNumber=$((configLineNumber + 1))
		configTrimmed="${configLine#"${configLine%%[![:space:]]*}"}"
		configTrimmed="${configTrimmed%"${configTrimmed##*[![:space:]]}"}"
		[ -z "$configTrimmed" ] && continue
		[[ "$configTrimmed" == \#* ]] && continue

		if [[ ! "$configTrimmed" =~ ^(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
			(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"expected a variable assignment")
			return 1
		fi

		configName="${BASH_REMATCH[2]}"
		configRaw="${BASH_REMATCH[3]}"
		configExport="${BASH_REMATCH[1]}"
		if [[ -z "${configAllowed[$configName]+x}" ]]; then
			(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"unsupported variable \$$configName")
			return 1
		fi
		if [[ -n "${configSeen[$configName]+x}" ]]; then
			(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"duplicate variable \$$configName")
			return 1
		fi

		if [[ ${#configRaw} -ge 2 && "${configRaw:0:1}" == '"' && "${configRaw: -1}" == '"' ]]; then
			configValue="${configRaw:1:${#configRaw}-2}"
			if [[ "$configValue" == *'"'* ]]; then
				(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"embedded double quote is not supported")
				return 1
			fi
		elif [[ ${#configRaw} -ge 2 && "${configRaw:0:1}" == "'" && "${configRaw: -1}" == "'" ]]; then
			configValue="${configRaw:1:${#configRaw}-2}"
			if [[ "$configValue" == *"'"* ]]; then
				(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"embedded single quote is not supported")
				return 1
			fi
		elif [[ "$configRaw" =~ ^[A-Za-z0-9_@%+=:,./-]*$ ]]; then
			configValue="$configRaw"
		else
			(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"value must be a quoted literal or a simple unquoted value")
			return 1
		fi

		if [[ "$configValue" == *'$'* || "$configValue" == *'`'* ]]; then
			(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"shell substitutions are not supported in values")
			return 1
		fi
		if [[ "$configValue" == *$'\t'* || "$configValue" == *$'\n'* ]]; then
			(>&2 echo -e "$cErr""Invalid config "$cFile"${configFile}"$cErr" at line ${configLineNumber}: "$cNone"tabs and newlines are not supported in values")
			return 1
		fi

		configSeen[$configName]=1
		configValues[$configName]="$configValue"
		if [[ -n "$configExport" ]]; then
			configExports[$configName]=1
		fi
	done < "$configFile"

	for configVariable in "${!configSeen[@]}"; do
		declare -g -- "$configVariable=${configValues[$configVariable]}"
		if [[ -n "${configExports[$configVariable]+x}" ]]; then
			export "$configVariable"
		else
			export -n "$configVariable"
		fi
	done

	return 0
}

# Yes/no dialog. Default answer (if pressing enter) is Yes (can be changed)
# The first argument is the message that the user will see.
# Second argumenti is optional, and if "n", then default will be No
# If the user enters n/N, return 1, else 0.
.check_yes_no(){
	while true; do
		local default="y"
		local hint="[Y/n]"
		local yn=""
		if [ "$2" = n ]; then
			default="n"
			hint="[y/N]"
		fi
		echo -e -n "$1 $hint: "
		read -n1 yn
		if [ "$yn" = "" ]; then
			yn="$default"
		else
			echo ""
		fi
		case "$yn" in
			[Yy] )
				break;;
			[Nn] )
				echo "No"
				return 1;;
			* )
				echo -e "${cErr}Please answer y or n for yes or no.${cNone}";;
		esac
	done;
	echo "Yes"
}

.run(){
	if [ ! $# = 1 ]; then
		(>&2 echo -e $cErr".run: need 1 argument, got $#: "$cNone$@)
		return 255
	fi
	(>&2 echo -e $cRun$1$cNone)
	eval $1
	local res=$?
	if [ "$debug" = 1 ]; then
		local rc=$cGreen
		if [ ! $res = 0 ]; then
			local rc=$cErr
		fi
		(>&2 echo -e "Result: "$rc$res$cNone)
	fi
	return $res
}
.runRes(){
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr".runRes: need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local resVar=$1
	local cmd=$2
	resVal=`.run "$cmd"`
	local r=$?
	eval $resVar="'$resVal'"
	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".runRes: result: "$cYellow${resVal}$cNone)
	fi
	return $r
}

.isCmd(){
	type "${1%%/*}" >/dev/null 2>&1 # command is everything until "/"
	return $?
}

.packageManager(){
	# package manager detect
	if .isCmd "apt"; then echo "apt"; return
	elif .isCmd "pacman"; then echo "pacman"; return
	fi
	if [ "$debug" = 1 ]; then
		(>&2 echo -e $cErr"Package manager not detected"$cNone)
	fi
	echo "unknown_package_manager"
	return 1
}

.packageManagerInstall(){
local pm=$(.packageManager)
	case $pm in
	"apt") echo $pm" install"; return ;;
	"pacman") echo $pm" -Syu"; return ;;
	*) echo $pm"_install"; return;;
esac
}

# install all packages for commands
# if command name is not the same as package name, the package name is specified as "cmd/pkg"
.install(){
local pmi=$(.packageManagerInstall)
	local packages=()
	
	local cmdPkg
	for cmdPkg in "$@"; do
		local pkg=${cmdPkg#*/} # everything after "/"
		packages+=("${pkg}")
	done
	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".install: installing packages: ${pmi} "$cYellow${packages[*]}$cNone)
	fi

	.run $SUDO" ${pmi} ${packages[*]}"
	return $?
}

.installPkg() {
	local pm=$(.packageManager)
	local toInstall=()
	local cmdPkg pkg
	for cmdPkg in "$@"; do
		pkg=${cmdPkg#*/}
		case "$pm" in
			apt)
				if apt list --installed "$pkg" 2>/dev/null | grep -q "\[installed\]"; then
					echo -e "Skipping already installed package ${cPkg}${pkg}${cNone}"
					continue
				fi
				;;
			pacman)
				if pacman -Q "$pkg" >/dev/null 2>&1; then
					echo -e "Skipping already installed package ${cPkg}${pkg}${cNone}"
					continue
				fi
				;;
		esac
		toInstall+=("$cmdPkg")
	done

	if [ ${#toInstall[@]} -eq 0 ]; then
		return 0
	fi

	.install "${toInstall[@]}"
}

.installedPpa() {
 .run "find /etc/apt/ -name '*.list' -print0 | xargs -0 grep -ho '^deb http://ppa.launchpad.net/[a-z0-9\\-]\\+/[a-z0-9\\-]\\+'"
}

.timestamp() {
	date +"%F %T.%N"
}

.backup() {
	local filename
	for fileName in "$@"; do
		if [ -e "${fileName}" ]; then # file exists
			local backup="${fileName}.$(.timestamp).bak"

			if [ -e "${backup}" ]; then
				(>&2 echo -e $cErr"Backup error: file "$cFile"${fileName}"$cErr" allready has a backup "$cFile${backup}$cNone)
				return 1 # can not backup, other backup file exists
			fi

			.run "mv '$fileName' '$backup'"
			local res=$?
			if [ ! "${res}" = 0 ]; then
				(>&2 echo -e $cErr"Backup error: move error: "$cNone${res})
				return 254 # move error
			else
				echo -e "File "$cFile"${fileName}"$cNone" backed up to "$cFile${backup}$cNone
				return
			fi
		else
			(>&2 echo -e $cErr"Backup error: file "$cFile${fileName}$cErr" does not exist"$cNone)
			return 255 # backup file not found
		fi
	done
}

.hardlink() {
	if [ ! $# = 2 ]; then
		(>&2 echo -e $cErr"Hardlinking error: .hardlink function need 2 argument, got $#: "$cNone$@)
		return 255
	fi
	local source=$1
	local target=$2

	if [ -f "$source" ]; then # source exists

		if [ $target -ef $source ]; then # source and target are equal files
			(>&2 echo -e "Hardlinking not needed, file "$cFile"${source}"$cNone" and "$cFile"${target}"$cNone" are the same (allready hardlinked).")
			return 2 # allready linked
		fi

		if [ -f "$target" ] && ! .run "cmp -s $source $target"; then # target exists and differs from source
			if .check_yes_no "File "$cFile${target}$cNone" allready exists and differs. Overwrite with "$cFile${source}$cNone"?"; then
				if .check_yes_no "Backup "$cFile${target}$cNone"?"; then
					if ! .backup "$target"; then
						if ! .check_yes_no "Backup failed. Link files anyway?"; then
							(>&2 echo -e $cErr"Hardlinking error: user decided not to link file "$cFile"${source}"$cErr" to "$cFile"${target}"$cErr"."$cNone)
							return 1 # user decided not to link
						fi
					fi
				else
					.run "rm '$target'"
				fi
			else
				(>&2 echo -e $cErr"Hardlinking error: user decided not to link file "$cFile"${source}"$cErr" to "$cFile"${target}"$cErr"."$cNone)
				return 1 # user decided not to link
			fi
		fi

		.run "cp -vfl '$source' '$target'"
		local res=$?
		if [ ! "${res}" = 0 ]; then
			(>&2 echo -e $cErr"Hardlinking error: copy error: "$cNone${res})
			return 253 # copy error
		fi
	else
		(>&2 echo -e $cErr"Hardlinking error: no source file "$cFile"${source}"$cErr" found."$cNone)
		return 254 # no source file
	fi
}

# Copy a managed configuration file without linking application writes back
# into this repository. Existing differing files can be backed up first.
.copyConfig() {
	if [ "$#" -ne 2 ]; then
		(>&2 echo -e $cErr"Copy error: .copyConfig needs 2 arguments, got $#: "$cNone"$@")
		return 255
	fi
	local source=$1
	local target=$2

	if [ ! -f "$source" ]; then
		(>&2 echo -e $cErr"Copy error: source file not found: "$cFile"${source}"$cNone)
		return 254
	fi
	if [ -f "$target" ] && cmp -s "$source" "$target"; then
		echo -e "Copy not needed; ${cFile}${target}${cNone} is current."
		return 2
	fi
	if [ -e "$target" ]; then
		if ! .check_yes_no "File ${cFile}${target}${cNone} differs. Replace it with ${cFile}${source}${cNone}?"; then
			return 1
		fi
		if .check_yes_no "Back up ${cFile}${target}${cNone}?"; then
			.backup "$target" || return 253
		fi
	fi

	local targetDirectory
	targetDirectory=$(dirname "$target")
	.run "mkdir -p '$targetDirectory'" || return 252
	.run "cp -v '$source' '$target'"
}

# to global variable missing it assigns an array of missing commands passed as other arguments 
# returns 1 if some command is missing
.missing() {
	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".missing: check "$cYellow${*}$cNone)
	fi

	missing=()
	local cmd
	for cmd in "$@"; do
		if ! .isCmd "${cmd}"; then
			missing+=("${cmd}")
		fi
	done

	if [ "$debug" = 1 ]; then
		(>&2 echo -e ".missing: results "$cYellow${missing[*]}$cNone)
	fi
	if [ "${#missing[@]}" -ne 0 ]; then
		return 1 # something is missing
	fi
	return
}

.needCommand() {
	if ! .missing "$@"; then
		echo "The following required commands are missing:"
		echo -e "$cCmd${missing[*]}$cNone"
		if .check_yes_no "install and continue?"; then
			if ! .install "${missing[@]}"; then
				echo -e $cErr"Installing required commands failed: ${missing[*]}"$cNone
				return 255 # install failed for some reason
			else
				if ! .missing "$@"; then
					echo -e $cErr"Installation completed, but commands are still unavailable: ${missing[*]}"$cNone
					return 254
				fi
				return 0
			fi
		else
			echo -e $cErr"Cannot continue without required commands: ${missing[*]}"$cNone
			return 1 # user dont want to install needed packages
		fi
	fi
	return
}

# Installs a command if missing. If its package has a different name, use the
# "command/package" form. Install command-less companion packages separately
# through .installPkg.
.installCommand() {
	if ! .missing "$@"; then
		echo "installing programs:"
		echo -e "$cCmd${missing[*]}$cNone"
		if .check_yes_no "install?"; then
			if ! .install "${missing[@]}"; then
				echo -e $cErr"Installing requested commands failed: ${missing[*]}"$cNone
				return 255 # install failed for some reason
			else
				if ! .missing "$@"; then
					echo -e $cErr"Installation completed, but commands are still unavailable: ${missing[*]}"$cNone
					return 254
				fi
				return 0
			fi
		else
			echo "Installation declined; requested commands remain unavailable."
			return 1 # user dont want to install needed packages
		fi
	fi
	return
}

# Prints the name of current Desktop Enviroment detected from environment variables.
# Detects/prints "gnome", "kde", "xfce".
# Otherwise prints "unknown" 
.getDE() {
	local desktop="unknown"
	if [ "$XDG_CURRENT_DESKTOP" = "" ]
	then
		desktop=$(echo "$XDG_DATA_DIRS" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/')
	else
		desktop=$(echo "$XDG_CURRENT_DESKTOP" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/')
	fi

	desktop=${desktop,,}  # convert to lower case
	desktop=$(echo "${desktop}" | sed 's/.*\(xfce\|kde\|gnome\).*/\1/')
	echo "$desktop"
	return
}

.checkEssentialInstallPrograms() {
	if ! .needCommand git curl ssh sed date cp mv; then
		return 1
	fi
	return
}

dotfilesDir="$HOME/.dotfiles"
dotfilesBin="${dotfilesDir}/bin"
github="https://github.com/"
githubName="jezek"

if [ $onlyEssential = 1 ]; then
	return
fi
# not essentials

if ! .checkEssentialInstallPrograms; then
	echo "Essential program are not available: "$missing
	exit 1
fi

#echo "testing:"
#
#
#echo "done"
#exit

### update & upgrade
##if .check_yes_no "update & upgrade?" "n"; then
##	$SUDO apt update
##	$SUDO apt upgrade
##fi

githubSsh=0
.run "ssh -qT git@github.com"
res=$?
if [ ! "$res" = 1 ]; then
	if .check_yes_no "do you want use your github with ssh on this device?"; then
		pubKeyFile=""
		sshDir="$HOME/.ssh"
		sshPubKeyFile=$sshDir"/id_rsa.pub"
		if [ -e $sshPubKeyFile ]; then
			pubKeyFile=$sshPubKeyFile
		fi
		if [ -z $pubKeyFile ]; then
			if .check_yes_no "no public key ($sshPubKeyFile) found. create new?"; then
				if .needCommand "ssh-keygen"; then
					comment=$HOSTNAME
					if .check_yes_no "ssh key will be generated with comment \"$comment\". change it?" "n"; then
						read -p "ssh key comment: " comment
					fi
					if [ ! -z $comment ]; then
						commentAttr=" -C \"$comment\""
					fi
					.run "ssh-keygen -t rsa -b 4096 $commentAttr"
				else
					echo -e $cErr"generating ssh key failed, no "$cCmd"ssh-keygen"$cErr" installed"$cNone
				fi
				if [ -e $sshPubKeyFile ]; then
					pubKeyFile=$sshPubKeyFile
				fi
			fi
		fi
		if [ ! -z $pubKeyFile ] && .check_yes_no "do you want to add your public key to github through api?"; then
			githubKeyTitle=$HOSTNAME
			if [ ! -z $comment ]; then
				githubKeyTitle=$comment
			fi
			.runRes pubKey "cat $pubKeyFile"
			res=$?
			if [ $res = 0 ]; then
				.run "curl -u \"$githubName\" -X POST -H \"Accept: application/vnd.github.v3+json\" -d \"{\\\"title\\\": \\\"$githubKeyTitle\\\",\\\"key\\\": \\\"$pubKey\\\"}\" \"https://api.github.com/user/keys\""
				res=$?
				if [ $res = 0 ]; then
					.run "ssh -qT git@github.com"
					res=$?
					if [ "$res" = 1 ]; then
						githubSsh=1
					else
						echo -e $cErr"someting failed, github with ssh access not configured"$cNone
					fi
				else
					echo -e $cErr"Can not set key to gitHub as $githubName"$cNone
					echo -e "Password auth to github is no longer valid. Generate token via web and press ENTER."
					read
					.run "ssh -qT git@github.com"
					res=$?
					if [ "$res" = 1 ]; then
						githubSsh=1
					else
						echo -e $cErr"someting failed, github with ssh access not configured"$cNone
					fi
				fi
			else
				echo -e $cErr"Can not load key from "$cNone$pubKeyFile
			fi
			unset pubKey
		else
			echo -e $cErr"no public key found, github with ssh access not configured"$cNone
		fi
	fi
else
	githubSsh=1
fi
unset res

if [ $githubSsh = 1 ]; then
	github="git@github.com:"
fi


if [ ! -d $dotfilesDir ]; then
	if ! .run "mkdir -p '$dotfilesDir'"; then
		echo -e $cErr"Could not create $cFile'$dotfilesDir'"$cNone
		exit 1
	fi
	.run "git clone $github$githubName/.dotfiles.git '$dotfilesDir'" 

	if [ ! -d $dotfilesDir ]; then
		echo "clonning ${cFile}$dotfilesDir${cNone} from github failed"
		exit 1
	fi

	.run "git -C '$dotfilesDir' submodule init"
	.run "git -C '$dotfilesDir' submodule update"
fi

if [ ! -d "${dotfilesBin}" ]; then
	.run "mkdir -p '$dotfilesBin'"
fi

plugins=(\
	sticky-keys git \
	shell/bash shell/zsh/zplug \
	vim vim/plug \
	golang \
	mc audacious \
	fingerprint \
	backup \
	wallpaper-changer \
)



for plugin in "${plugins[@]}"; do
	pluginInstallFile="$dotfilesDir/installers/$plugin/install.sh"
	if [ -f $pluginInstallFile ]; then
		echo -e $cBlue"Installing plugin: ${cFile}${plugin}"$cNone
		source $pluginInstallFile plugin
	fi
done;
