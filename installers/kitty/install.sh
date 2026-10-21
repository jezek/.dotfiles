#!/bin/bash
if [ -z "${dotfilesDir+x}" ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@" || exit 1
fi

.installKitty() (
	.installCommand kitty || return 1
	if ! .isCmd python3; then
		case "$(.packageManager)" in
			pacman) .needCommand python3/python || return 1 ;;
			*) .needCommand python3 || return 1 ;;
		esac
	fi
	.needCommand fc-match/fontconfig fc-query/fontconfig fc-cache/fontconfig || return 1

	local kittyFontStage kittyFontResult kittyFontDirectory kittyConfigDirectory
	kittyFontStage=$(mktemp -d) || return 1
	# This subshell keeps cleanup local when sourced by the main installer.
	trap 'rm -rf -- "$kittyFontStage"' EXIT
	if python3 "$dotfilesDir/installers/kitty/source-code-pro.py" "$kittyFontStage"; then
		kittyFontResult=0
	else
		kittyFontResult=$?
	fi

	# The helper stages missing/newer faces only: 2 = current, 3 = ask first.
	case "$kittyFontResult" in
		0|2) ;;
		3)
			if ! .check_yes_no "Install the offered Source Code Pro font update?"; then
				echo "Source Code Pro was left unchanged."
				kittyFontResult=2
			fi
			;;
		*) return 1 ;;
	esac
	if [ "$kittyFontResult" -ne 2 ]; then
		# Upgrading a system-installed font adds a user copy; the package-owned
		# files stay under the control of the system package manager.
		kittyFontDirectory="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/source-code-pro"
		mkdir -p -- "$kittyFontDirectory" || return 1
		# All downloads and their Git blob checksums are verified before copying.
		install -m 644 -- "$kittyFontStage"/*.otf "$kittyFontStage/LICENSE.md" "$kittyFontDirectory/" || return 1
		fc-cache -f "$kittyFontDirectory" || return 1
		echo "Source Code Pro installed in $kittyFontDirectory."
	fi

	kittyConfigDirectory="${KITTY_CONFIG_DIRECTORY:-${XDG_CONFIG_HOME:-$HOME/.config}/kitty}"
	if .copyConfig "$dotfilesDir/installers/kitty/kitty.conf" "$kittyConfigDirectory/kitty.conf"; then
		:
	else
		local kittyConfigResult=$?
		[ "$kittyConfigResult" -eq 2 ] || return "$kittyConfigResult"
	fi
	echo "Kitty configured. Open a new Kitty window to use the settings."
)

if .installKitty; then
	kittyInstallResult=0
else
	kittyInstallResult=$?
fi
unset -f .installKitty
[ "${1:-}" = plugin ] && return "$kittyInstallResult"
exit "$kittyInstallResult"
