#!/bin/bash

set -u

bootstrapSource=${BASH_SOURCE[0]}
bootstrapDirectory=$(cd "$(dirname "$bootstrapSource")" 2>/dev/null && pwd -P)
if [ -n "$bootstrapDirectory" ] && [ -f "$bootstrapDirectory/installers/install.sh" ]; then
	exec bash "$bootstrapDirectory/installers/install.sh" "$@"
fi

if [ -r /dev/tty ]; then
	exec </dev/tty
fi

if ! command -v curl >/dev/null 2>&1; then
	echo "curl is required to bootstrap dotfiles." >&2
	exit 1
fi

bootstrapTemporaryDirectory=$(mktemp -d)
bootstrapInstaller="$bootstrapTemporaryDirectory/install.sh"
bootstrapUrl="https://raw.githubusercontent.com/jezek/.dotfiles/master/installers/install.sh"
if ! curl -fsSL "$bootstrapUrl" -o "$bootstrapInstaller"; then
	echo "Downloading the dotfiles installer failed." >&2
	rm -rf -- "$bootstrapTemporaryDirectory"
	exit 1
fi

bash "$bootstrapInstaller" "$@"
bootstrapResult=$?
rm -rf -- "$bootstrapTemporaryDirectory"
exit "$bootstrapResult"
