#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi
dotWallpaperChangerDir=${dotfilesDir}"/wallpaper-changer"
dotWallpaperChangerInstallDir=${dotfilesDir}"/installers/wallpaper-changer"

# The $DBUS_SESSION_BUS_ADDRESS variable is needed for gsettings.
if [ -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
	DBUS_SESSION_BUS_ADDRESS=$($dotWallpaperChangerInstallDir"/getDbusSessionBusAddress.sh")
	res=$?
	if [ ! $res = 0 ]; then
		1>&2 echo -e $cErr"Dbus session bus address not found"$cNone;
		exit 1
	fi
fi

# From every argument passed to this script.
for arg in "$@"; do
	# Get a picture from directory passed in argument.
	arg="$arg"
	picToUse=$($dotWallpaperChangerInstallDir"/getRandomWallpaper.sh" $arg)
	res=$?
	if [ $res -ne 0 ]; then
		1>&2 echo -e $cErr"No picture returned from directory: "$cFile"${arg}"$cNone
	else
		# If a picture was returned (there was no error), break the cycle.
		break
	fi
done

if [ -z "${picToUse}" ]; then
	1>&2 echo -e $cErr"No pictures found in directory(ies): "$cFile"$@"$cNone
	exit 2
fi

echo Setting picture as wallpaper: $picToUse

# Create or update link to current wallpaper in dotfiles wallpaper-changer directory.
[ -d "${dotWallpaperChangerDir}" ] && .run "ln -sf \"${picToUse}\" ${dotWallpaperChangerDir}/current-wallpaper.link"

# Set the background image options to "centered".
#gsettings set org.gnome.desktop.background picture-options centered

# Set the background image for light/day mode.
gsettings set org.gnome.desktop.background picture-uri file://"$picToUse"
# Set the background image for dark/night mode.
gsettings set org.gnome.desktop.background picture-uri-dark file://"$picToUse"

# Get picture dominant color.
dominantColor=$($dotWallpaperChangerInstallDir"/dcolors.sh" -k 1 -f hex "${picToUse}")
echo "Setting dash-to-dock background-color to picture's dominant color: "${dominantColor}
gsettings set org.gnome.shell.extensions.dash-to-dock background-color "${dominantColor}"

# Set the closest standard GNOME accent color. Failure is non-fatal because
# older GNOME versions do not provide the accent-color setting.
if gnomeAccent=$($dotWallpaperChangerInstallDir"/getGnomeAccent.sh" \
		"${picToUse}" "${dominantColor}"); then
	currentGnomeAccent=$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null)
	currentGnomeAccent=${currentGnomeAccent#\'}
	currentGnomeAccent=${currentGnomeAccent%\'}
	if [ "$currentGnomeAccent" != "$gnomeAccent" ]; then
		echo "Setting GNOME accent color to: ${gnomeAccent}"
		if ! gsettings set org.gnome.desktop.interface accent-color "$gnomeAccent"; then
			1>&2 echo -e $cErr"Failed to set GNOME accent color"$cNone
		fi
	fi
else
	1>&2 echo "GNOME accent color is unavailable; leaving it unchanged"
fi

# Darken dominant color if needed.
darkenediDominantColor=$($dotWallpaperChangerInstallDir"/darken.sh" 20 "${dominantColor}")
echo "Darkened dominat color: $darkenediDominantColor"

# Set the background primary color to black.
gsettings set org.gnome.desktop.background primary-color "#000000"
# Set the background secondary color to darkenediDominantColor.
gsettings set org.gnome.desktop.background secondary-color "${darkenediDominantColor}"
