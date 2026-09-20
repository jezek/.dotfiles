#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi
dotWallpaperChangerInstallDir=${dotfilesDir}"/installers/wallpaper-changer"

wallpaperChangerArgs=()
dotWallpaperChangerDir=${dotfilesDir}"/wallpaper-changer"
dotWallpaperChangerConfigFile=${dotWallpaperChangerDir}"/wallpaper-changer.conf"

if [ "$#" -gt 1 ]; then
	echo "Usage: $0 [IMAGE]" >&2
	exit 2
elif [ "$#" -eq 1 ]; then
	if ! .isCmd realpath; then
		1>&2 echo -e $cErr"Cannot select a wallpaper without realpath"$cNone
		exit 1
	fi

	if ! wallpaperChangerImage=$(realpath -e -- "$1" 2>/dev/null); then
		1>&2 echo -e $cErr"Wallpaper image does not exist or is not readable: "$cFile"$1"$cNone
		exit 2
	fi
	if [ ! -f "$wallpaperChangerImage" ] || [ ! -r "$wallpaperChangerImage" ]; then
		1>&2 echo -e $cErr"Wallpaper image does not exist or is not readable: "$cFile"$1"$cNone
		exit 2
	fi

	wallpaperChangerImageExtension=${wallpaperChangerImage##*.}
	wallpaperChangerImageExtension=${wallpaperChangerImageExtension,,}
	case "$wallpaperChangerImageExtension" in
		jpg | jpeg | gif | png | webp) ;;
		*)
			1>&2 echo -e $cErr"Unsupported wallpaper image type: "$cFile"$1"$cNone
			exit 2
			;;
	esac

	wallpaperChangerArgs=("$wallpaperChangerImage")
elif [ -f "${dotWallpaperChangerConfigFile}" ]; then
	unset wallpaperChangerArgs
	if ! .loadConfig "$dotWallpaperChangerConfigFile" wallpaperChangerArgs; then
		exit 1
	fi
	wallpaperChangerArgsConfig="$wallpaperChangerArgs"
	read -r -a wallpaperChangerArgs <<< "$wallpaperChangerArgsConfig"
	unset wallpaperChangerArgsConfig
else
	echo $cWarn"No config file found: "$cFile$dotWallpaperChangerConfigFile$cNone
fi

de=$(.getDE)
wallpaperChangerScriptVariant=""
case $de in
	gnome | unity)
		wallpaperChangerScriptVariant="gnome"
		if [ ${#wallpaperChangerArgs[@]} = 0 ]; then
			wallpaperChangerArgs=(/usr/share/backgrounds/gnome /usr/share/backgrounds)
		fi
		;;
	*)
		echo "Unknown DE: ${de}"
		exit 1
		;;
esac

printf 'Known DE: %s, using script variant: %s with arguments:' "$de" "$wallpaperChangerScriptVariant"
printf ' %q' "${wallpaperChangerArgs[@]}"
printf '\n'
"$dotWallpaperChangerInstallDir/wallpaper-changer.${wallpaperChangerScriptVariant}.sh" "${wallpaperChangerArgs[@]}"
