#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

de=$(.getDE)
case $de in
	gnome | unity) ;;
	*)
		echo -e $cErr"Unknown DE for wallpaper-changer:"$cNone" ${de}"
		[ "$1" = plugin ] && return 1 || exit 1
		;;
esac

if ! .isCmd "systemctl"; then
	echo -e "Systemd not detected, will not install wallpaper-changer"
	[ "$1" = plugin ] && return 1 || exit 1
fi

dotWallpaperChangerDir=${dotfilesDir}"/wallpaper-changer"
dotWallpaperChangerConfigFile=${dotWallpaperChangerDir}"/wallpaper-changer.conf"
dotWallpaperChangerInstallDir=${dotfilesDir}"/installers/wallpaper-changer"
templateName="wallpaper-changer.conf.template"
if [ ! -f $dotWallpaperChangerConfigFile ]; then
	if ! .check_yes_no "Setup wallpaper changer for this user?" ; then
		[ "$1" = plugin ] && return 1 || exit 1
	fi

	[ ! -d "${dotWallpaperChangerDir}" ] && .run "mkdir ${dotWallpaperChangerDir}"
	.run "cp ${dotWallpaperChangerInstallDir}/${templateName} ${dotWallpaperChangerConfigFile}"
	echo -e $cOk"Created"$cNone" a configuration file "$cFile$dotWallpaperChangerConfigFile$cNone"."
	echo -e "Edit it's content to set up directories from which the wallpapers will be taken."
	read
fi

systemdUserDir=$HOME"/.config/systemd/user"
[ ! -d "${systemdUserDir}" ] && .run "mkdir -p ${systemdUserDir}"

timerFileName="wallpaper-changer.timer"
serviceFileName="wallpaper-changer.service"

linkWallpaperChangerSystemdTimer=$systemdUserDir"/"$timerFileName
if .hardlink "${dotWallpaperChangerInstallDir}/${timerFileName}" $linkWallpaperChangerSystemdTimer; then
	echo -e $cOk"Created"$cNone" timer file "$cFile$(basename ${linkWallpaperChangerSystemdTimer})$cNone" in systemd user dir "$cFile$systemdUserDir$cNone
fi

linkWallpaperChangerSystemdService=$systemdUserDir"/"$serviceFileName
if .hardlink "${dotWallpaperChangerInstallDir}/${serviceFileName}" $linkWallpaperChangerSystemdService; then
	echo -e $cOk"Created"$cNone" service file "$cFile$(basename ${linkWallpaperChangerSystemdService})$cNone" in systemd user dir "$cFile$systemdUserDir$cNone
fi

linkWallpaperChangeBin="${dotfilesBin}/.wallpaper-change"
if .hardlink "${dotWallpaperChangerInstallDir}/wallpaper-change.sh" $linkWallpaperChangeBin; then
	echo -e "Executable "$cCmd"$(basename ${linkWallpaperChangeBin})"$cNone" created."
fi

if .runRes enabled "systemctl --user is-enabled wallpaper-changer.timer"; then
	if [ "enabled" = "${enabled}" ]; then
		.runRes active "systemctl --user is-active wallpaper-changer.timer"
		if [ "active" = "${active}" ]; then
			echo -e $cOk"Wallpaper changer timer"$cNone" already configured"
			[ "$1" = plugin ] && return 0 || exit 0
		fi
	fi
fi

if ! .run "systemctl --user enable wallpaper-changer.timer --now"; then
	echo -e $cErr"Failed"$cNone" to install wallpaper-changer timer"
	[ "$1" = plugin ] && return 1 || exit 1
fi
