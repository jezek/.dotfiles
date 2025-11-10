#! /bin/bash
# startup sway on login on terminal 1
#if [ "$(tty)" = "/dev/tty1" ] || [ "$(tty)" = "/dev/ttyv0" ] ; then
source /home/jezek/.profile
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export LC_MESSAGES=en_US.UTF-8
export LC_ALL=sk_SK.UTF-8
export LC_TIME=sk_SK.UTF-8

if [ -z "$XDG_RUNTIME_DIR" ]; then
	export XDG_RUNTIME_DIR="$HOME/.config/xdg"
	rm -rf $XDG_RUNTIME_DIR
	mkdir -p $XDG_RUNTIME_DIR
fi
export QT_QPA_PLATFORMTHEME=gtk2
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=sway
export WLR_NO_HARDWARE_CURSORS=1
XDG_CURRENT_DESKTOP=sway dbus-run-session sway
#exec sway
#fi
#  
