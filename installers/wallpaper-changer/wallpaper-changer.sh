#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi
dotWallpaperChangerInstallDir=${dotfilesDir}"/installers/wallpaper-changer"

wallpaperChangerArgs=()
dotWallpaperChangerDir=${dotfilesDir}"/wallpaper-changer"
dotWallpaperChangerConfigFile=${dotWallpaperChangerDir}"/wallpaper-changer.conf"
if [ -f "${dotWallpaperChangerConfigFile}" ]; then
	unset wallpaperChangerArgs
	export "$(grep -v '#.*' "${dotWallpaperChangerConfigFile}" | xargs)"
	wallpaperChangerArgs=( ${wallpaperChangerArgs[@]} )
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

echo "Known DE: ${de}, using script variant: ${wallpaperChangerScriptVariant} with arguments: ${wallpaperChangerArgs[@]}"
$dotWallpaperChangerInstallDir"/wallpaper-changer.${wallpaperChangerScriptVariant}.sh" "${wallpaperChangerArgs[@]}"
