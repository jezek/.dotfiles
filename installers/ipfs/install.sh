#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

if ! .check_yes_no "Install and configure a Kubo IPFS node?" n; then
	[ "$1" = plugin ] && return 0
	exit 0
fi

if ! .needCommand curl tar sha512sum sort uname mktemp grep head tail chmod; then
	[ "$1" = plugin ] && return 1
	exit 1
fi

ipfsCommand=""
if .isCmd ipfs; then
	ipfsCommand=$(command -v ipfs)
	echo -e "Found ${cCmd}$($ipfsCommand version)${cNone}."
else
	packageAvailable=0
	case "$(.packageManager)" in
		apt) apt-cache show ipfs-kubo >/dev/null 2>&1 && packageAvailable=1 ;;
		pacman) pacman -Si kubo >/dev/null 2>&1 && packageAvailable=1 ;;
	esac

	ipfsInstallChoices=("official binary")
	[ "$packageAvailable" -eq 1 ] && ipfsInstallChoices+=("package manager")
	ipfsInstallChoices+=("don't install")
	echo "Select Kubo installation source:"
	select ipfsInstallSource in "${ipfsInstallChoices[@]}"; do
		case "$ipfsInstallSource" in
			"official binary")
				case "$(uname -m)" in
					x86_64 | amd64) ipfsArchitecture=amd64 ;;
					aarch64 | arm64) ipfsArchitecture=arm64 ;;
					riscv64) ipfsArchitecture=riscv64 ;;
					*)
						echo -e $cErr"No official Kubo binary for architecture $(uname -m)."$cNone
						[ "$1" = plugin ] && return 1
						exit 1
						;;
				esac

				ipfsVersion=$(curl -fsSL https://dist.ipfs.tech/kubo/versions | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
				ipfsDistribution=$(curl -fsSL "https://dist.ipfs.tech/kubo/${ipfsVersion}/dist.json")
				ipfsFile="kubo_${ipfsVersion}_linux-${ipfsArchitecture}.tar.gz"
				ipfsChecksum=$(printf '%s\n' "$ipfsDistribution" | awk -v architecture="$ipfsArchitecture" '
					/"linux":/ { linux=1; next }
					linux && $0 ~ "\"" architecture "\":" { found=1; next }
					found && /"sha512":/ { gsub(/[",]/, "", $2); print $2; exit }
				')
				if [ -z "$ipfsVersion" ] || [ "${#ipfsChecksum}" -ne 128 ]; then
					echo -e $cErr"Could not determine the latest Kubo archive and checksum."$cNone
					[ "$1" = plugin ] && return 1
					exit 1
				fi

				ipfsTempDirectory=$(mktemp -d)
				ipfsArchive="$ipfsTempDirectory/$ipfsFile"
				if ! curl -fL "https://dist.ipfs.tech/kubo/${ipfsVersion}/$ipfsFile" -o "$ipfsArchive" ||
					! printf '%s  %s\n' "$ipfsChecksum" "$ipfsArchive" | sha512sum -c - ||
					! tar -C "$ipfsTempDirectory" -xzf "$ipfsArchive" ||
					[ ! -x "$ipfsTempDirectory/kubo/ipfs" ]; then
					echo -e $cErr"Downloading or verifying Kubo failed."$cNone
					rm -rf -- "$ipfsTempDirectory"
					[ "$1" = plugin ] && return 1
					exit 1
				fi

				ipfsCommand="$HOME/.local/bin/ipfs"
				.copyConfig "$ipfsTempDirectory/kubo/ipfs" "$ipfsCommand"
				ipfsCopyResult=$?
				if [ "$ipfsCopyResult" -ne 0 ] && [ "$ipfsCopyResult" -ne 2 ]; then
					rm -rf -- "$ipfsTempDirectory"
					[ "$1" = plugin ] && return "$ipfsCopyResult"
					exit "$ipfsCopyResult"
				fi
				chmod +x "$ipfsCommand"
				rm -rf -- "$ipfsTempDirectory"
				break
				;;
			"package manager")
				case "$(.packageManager)" in
					apt) .install ipfs/ipfs-kubo ;;
					pacman) .install ipfs/kubo ;;
				esac
				ipfsCommand=$(command -v ipfs)
				[ -n "$ipfsCommand" ] && break
				;;
			"don't install")
				[ "$1" = plugin ] && return 0
				exit 0
				;;
		esac
	done
fi

if [ ! -f "$HOME/.ipfs/config" ]; then
	if ! "$ipfsCommand" init; then
		echo -e $cErr"Initializing the Kubo repository failed."$cNone
		[ "$1" = plugin ] && return 1
		exit 1
	fi
fi

ipfsApiAddress=$("$ipfsCommand" config Addresses.API 2>/dev/null)
case "$ipfsApiAddress" in
	/ip4/127.0.0.1/* | /ip6/::1/*) ;;
	*)
		echo -e $cWarn"Kubo RPC API is not restricted to loopback: ${ipfsApiAddress}"$cNone
		if .check_yes_no "Restrict the RPC API to 127.0.0.1:5001?"; then
			"$ipfsCommand" config Addresses.API /ip4/127.0.0.1/tcp/5001
		fi
		;;
esac

ipfsServiceSource="$dotfilesDir/installers/ipfs/ipfs.service"
ipfsServiceTarget="$HOME/.config/systemd/user/ipfs.service"
if .isCmd systemctl; then
	.run "mkdir -p '$HOME/.config/systemd/user'"
	.hardlink "$ipfsServiceSource" "$ipfsServiceTarget"
	ipfsServiceResult=$?
	if [ "$ipfsServiceResult" -eq 0 ] || [ "$ipfsServiceResult" -eq 2 ]; then
		.run "systemctl --user daemon-reload"
		if .check_yes_no "Enable and start the Kubo user service now?" n; then
			.run "systemctl --user enable --now ipfs.service"
		fi
	fi
fi

if .check_yes_no "Open Kubo swarm port 4001/TCP and 4001/UDP in the local firewall?" n; then
	if .isCmd ufw; then
		.run "$SUDO ufw allow 4001/tcp"
		.run "$SUDO ufw allow 4001/udp"
	elif .isCmd firewall-cmd; then
		.run "$SUDO firewall-cmd --permanent --add-port=4001/tcp"
		.run "$SUDO firewall-cmd --permanent --add-port=4001/udp"
		.run "$SUDO firewall-cmd --reload"
	else
		echo "No supported firewall manager found; no firewall rules were changed."
	fi
fi

echo -e "Kubo is configured. Use ${cCmd}ipfs update check${cNone} to check official-binary updates."
