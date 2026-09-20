#! /bin/sh
if [ "$#" -eq 0 ]; then
	exec systemctl --user start wallpaper-changer
fi

# The systemd unit has no parameterized path, so explicit images run directly.
if [ "$#" -ne 1 ]; then
	echo "Usage: $0 [IMAGE]" >&2
	exit 2
fi

exec "$HOME/.dotfiles/installers/wallpaper-changer/wallpaper-changer.sh" "$1"
