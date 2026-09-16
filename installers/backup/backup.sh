#! /bin/bash

if [ -z "${dotfilesDir+x}" ]; then
	source "$HOME/.dotfiles/installers/install.sh" essentials "$@"
fi

dotBackupDir="${dotfilesDir}/backup"
if [ ! -d "$dotBackupDir" ]; then
	echo -e "$cErr""Backup config directory does not exist: "$cFile"${dotBackupDir}"$cNone
	echo -e "Run backup install, to configure: "$cFile"${dotfilesDir}/installers/backup/install.sh"$cNone
	exit 1
fi

backupConfigFile="${dotBackupDir}/config"
if [ ! -f "$backupConfigFile" ]; then
	echo -e "$cErr""Backup config file does not exist: "$cFile"${backupConfigFile}"$cNone
	exit 1
fi

unset backupSourceDirectory backupDestRemote backupDestDirectory backupDepth backupRunAsRoot backupLargeFileThresholdBytes
if ! .loadConfig "$backupConfigFile" backupSourceDirectory backupDestRemote backupDestDirectory backupDepth backupRunAsRoot backupLargeFileThresholdBytes; then
	exit 2
fi

for requiredVariable in backupSourceDirectory backupDestRemote backupDestDirectory; do
	if [[ ! -v "$requiredVariable" ]]; then
		echo -e "$cErr""Missing variable after config load: "$cNone"\$$requiredVariable"
		exit 2
	fi
done
unset requiredVariable

backupRunAsRoot="${backupRunAsRoot:-no}"
backupDepthIdentity="${backupDepth-<default>}"
backupDepth="${backupDepth:-0}"
backupLargeFileThresholdBytes="${backupLargeFileThresholdBytes:-5368709120}"

if [[ ! "$backupRunAsRoot" =~ ^(yes|no)$ ]]; then
	echo -e "$cErr""Invalid backup config: "$cNone"\$backupRunAsRoot must be yes or no"
	exit 2
fi

if [[ ! "$backupDepth" =~ ^[0-9]+$ ]]; then
	echo -e "$cErr""Invalid backup config: "$cNone"\$backupDepth must be a non-negative integer"
	exit 2
fi
export backupDepth

if [[ ! "$backupLargeFileThresholdBytes" =~ ^[1-9][0-9]*$ ]]; then
	echo -e "$cErr""Invalid backup config: "$cNone"\$backupLargeFileThresholdBytes must be a positive integer"
	exit 2
fi

backupInvokerUser="${SUDO_USER:-$(id -un)}"
backupInvokerGroup="$(id -gn "$backupInvokerUser" 2>/dev/null || id -gn)"
backupTargetOwner="${backupInvokerUser}:${backupInvokerGroup}"

if ! backupSourceDirectory="$(realpath -e -- "$backupSourceDirectory")" || [ ! -d "$backupSourceDirectory" ]; then
	echo -e "$cErr""Source directory does not exist: "$cFile"${backupSourceDirectory}"$cNone
	exit 1
fi

for requiredCommand in flock findmnt realpath sha256sum; do
	if ! command -v "$requiredCommand" >/dev/null 2>&1; then
		echo -e "$cErr""Required command not found: "$cCmd"${requiredCommand}"$cNone
		exit 4
	fi
done
unset requiredCommand

backupLockFile="${dotBackupDir}/.backup.lock"
exec {backupLockFd}>"$backupLockFile"
if ! flock -n "$backupLockFd"; then
	echo -e "$cErr""Backup is already running for config: "$cFile"${backupConfigFile}"$cNone
	exit 5
fi

backupExcludes=()
backupExcludesFile="${dotBackupDir}/exclude.txt"
if [ -f "$backupExcludesFile" ]; then
	while IFS= read -r line || [ -n "$line" ]; do
		backupExcludes+=("$line")
	done < "$backupExcludesFile"
fi

backup_identity_fingerprint() {
	local result
	result="$({
		printf 'source\0%s\0remote\0%s\0destination\0%s\0depth\0%s\0' \
			"$backupSourceDirectory" "$backupDestRemote" "$backupDestDirectory" "$backupDepthIdentity"
		if [ -f "$backupExcludesFile" ]; then
			printf 'excludes\0present\0'
			cat -- "$backupExcludesFile"
		else
			printf 'excludes\0missing\0'
		fi
	} | sha256sum)" || return 1
	printf '%s' "${result%% *}"
}

if ! backupFingerprint="$(backup_identity_fingerprint)"; then
	echo -e "$cErr""Failed to fingerprint backup config and excludes"$cNone
	exit 2
fi

backupMountpointsNotExcluded=()
while read -r i; do
	fields=($i)
	src=${fields[0]}
	dst=${fields[1]}

	if [ "$backupSourceDirectory" = / ] && [[ "$dst" == /* ]] && [ "$dst" != / ]; then
		relativeMountpoint="${dst#/}"
	elif [[ "$dst" == "$backupSourceDirectory"/* ]]; then
		relativeMountpoint="${dst#"$backupSourceDirectory"/}"
	else
		continue
	fi

	if [ -n "$relativeMountpoint" ]; then
		found=0
		for exclude in "${backupExcludes[@]}"; do
			excludePath="${exclude#- /}"
			excludePath="${excludePath%/}"
			if [ "$relativeMountpoint" = "$excludePath" ] || [[ "$relativeMountpoint" == "$excludePath"/* ]]; then
				found=1
				break
			fi
		done
		if [ "$found" = 0 ]; then
			backupMountpointsNotExcluded+=("- /${relativeMountpoint%/}/")
		fi
	fi
done < /proc/mounts
unset fields src dst exclude excludePath relativeMountpoint found i

if [ ${#backupMountpointsNotExcluded[@]} -gt 0 ]; then
	echo -e "$cErr""Not excluded mount points:"$cNone
	.toLines "${backupMountpointsNotExcluded[@]}"
	exit 3
fi

ribs="${dotfilesDir}/installers/backup/rsync-incremental-backup/rsync-incremental-backup-local"
if [ -n "$backupDestRemote" ]; then
	ribs="${dotfilesDir}/installers/backup/rsync-incremental-backup/rsync-incremental-backup-remote"
	if ! .needCommand rsync scp ssh; then
		exit 4
	fi
elif ! .needCommand rsync; then
	exit 4
fi

if [ ! -f "$ribs" ]; then
	echo -e "$cErr""External backup script file not found: "$cFile"${ribs}"$cNone
	exit 1
elif [ ! -x "$ribs" ]; then
	echo -e "$cErr""External backup script file is not executable: "$cFile"${ribs}"$cNone
	exit 1
fi

path_relative_to() {
	local base="$1" path="$2"
	if [ "$path" = "$base" ]; then
		printf ''
	elif [ "$base" = / ] && [[ "$path" == /* ]]; then
		printf '%s' "${path#/}"
	elif [[ "$path" == "$base"/* ]]; then
		printf '%s' "${path#"$base"/}"
	else
		return 1
	fi
}

join_path() {
	if [ "$1" = / ]; then
		printf '/%s' "$2"
	elif [ -z "$2" ]; then
		printf '%s' "$1"
	else
		printf '%s/%s' "${1%/}" "$2"
	fi
}

path_is_excluded() {
	local relative="${1#/}" candidate controlRelative rule pattern directory anchored
	if controlRelative="$(path_relative_to "$backupSourceDirectory" "$dotBackupDir")"; then
		controlRelative="${controlRelative%/}"
		if [ -n "$controlRelative" ] && \
			{ [ "$relative" = "$controlRelative" ] || [[ "$relative" == "$controlRelative"/* ]]; }; then
			return 0
		fi
	fi

	for rule in "${backupExcludes[@]}"; do
		rule="${rule#"${rule%%[![:space:]]*}"}"
		rule="${rule%"${rule##*[![:space:]]}"}"
		[[ "$rule" == '- '* ]] || continue

		pattern="${rule#- }"
		anchored=0
		if [[ "$pattern" == /* ]]; then
			anchored=1
			pattern="${pattern#/}"
		fi
		directory=0
		if [[ "$pattern" == */ ]]; then
			directory=1
			pattern="${pattern%/}"
		fi

		if [ "$directory" = 1 ]; then
			candidate="$relative"
			while [ -n "$candidate" ]; do
				if { [ "$anchored" = 1 ] && [[ "$candidate" == $pattern ]]; } || \
					{ [ "$anchored" = 0 ] && { [[ "$candidate" == $pattern ]] || [[ "$candidate" == */$pattern ]]; }; }; then
					return 0
				fi
				[[ "$candidate" == */* ]] || break
				candidate="${candidate%/*}"
			done
		elif { [ "$anchored" = 1 ] && [[ "$relative" == $pattern ]]; } || \
			{ [ "$anchored" = 0 ] && { [[ "$relative" == $pattern ]] || [[ "$relative" == */$pattern ]]; }; }; then
			return 0
		fi
	done
	return 1
}

build_find_prune_arguments() {
	local controlRelative rule pattern anchored findPattern
	backupFindPruneArguments=()
	if controlRelative="$(path_relative_to "$backupSourceDirectory" "$dotBackupDir")"; then
		controlRelative="${controlRelative%/}"
		if [ -n "$controlRelative" ]; then
			backupFindPruneArguments+=(
				-path "$(join_path "$backupSourceDirectory" "$controlRelative")"
				-prune -o
			)
		fi
	fi
	for rule in "${backupExcludes[@]}"; do
		rule="${rule#"${rule%%[![:space:]]*}"}"
		rule="${rule%"${rule##*[![:space:]]}"}"
		[[ "$rule" == '- '* ]] || continue
		pattern="${rule#- }"
		anchored=0
		if [[ "$pattern" == /* ]]; then
			anchored=1
			pattern="${pattern#/}"
		fi
		[[ "$pattern" == */ ]] || continue
		pattern="${pattern%/}"
		[[ "$pattern" != *'*'* && "$pattern" != *'?'* && "$pattern" != *'['* ]] || continue
		[ -n "$pattern" ] || continue
		if [ "$anchored" = 1 ]; then
			findPattern="$(join_path "$backupSourceDirectory" "$pattern")"
		else
			findPattern="$(join_path "$backupSourceDirectory" "*/$pattern")"
		fi
		backupFindPruneArguments+=(
			-path "$findPattern"
			-prune -o
		)
	done
}

stateFile="${dotBackupDir}/.btrfs-backup.state"
runtimeExcludesFile="${dotBackupDir}/.exclude.runtime"
runtimeExclusionFileName="${runtimeExcludesFile##*/}"
largeFilesScanFile="${dotBackupDir}/.large-files.scan"
trap 'rm -f -- "$runtimeExcludesFile" "$largeFilesScanFile"' EXIT

# Questions are local to backup: never consume piped input as an answer.
ask_backup_source() {
	local answer
	if [ ! -t 0 ]; then
		printf '%s [Y/n/q]: Yes (no TTY)\n' "$1"
		return 0
	fi
	while :; do
		printf '%s [Y/n/q]: ' "$1"
		if ! IFS= read -r -n1 answer; then
			printf '\nInput closed; backup cancelled.\n'
			exit 130
		fi
		printf '\n'
		case "$answer" in
			''|y|Y) return 0 ;;
			n|N) return 1 ;;
			q|Q)
				if [ -f "$stateFile" ]; then
					discard_pending_snapshot || exit 6
				fi
				echo 'Backup cancelled; temporary backup files cleaned up.'
				exit 130
				;;
			*) echo 'Please answer y, n, or q to quit.' ;;
		esac
	done
}

backup_privileged() {
	if [ "$EUID" = 0 ]; then
		"$@"
	elif [ -t 0 ]; then
		sudo "$@"
	else
		sudo -n "$@"
	fi
}

detect_inaccessible_paths() {
	local path relative
	local -a findArguments
	backupInaccessiblePaths=()
	build_find_prune_arguments
	findArguments=("$backupSourceDirectory" -xdev "${backupFindPruneArguments[@]}")
	findArguments+=(
		\( -type l -prune \) -o
		\( -type d \( ! -readable -o ! -executable \) -print0 -prune \) -o
		\( ! -readable -print0 \)
	)
	while IFS= read -r -d '' path; do
		relative="$(path_relative_to "$backupSourceDirectory" "$path")" || continue
		[ -n "$relative" ] || continue
		if ! path_is_excluded "$relative"; then
			backupInaccessiblePaths+=("$relative")
		fi
	done < <(find "${findArguments[@]}" 2>/dev/null)
}

format_backup_size() {
	if command -v numfmt >/dev/null 2>&1; then
		numfmt --to=iec-i --suffix=B "$1"
	else
		printf '%s B' "$1"
	fi
}

scan_large_files() {
	local size path relative
	local -a findArguments
	backupLargeFiles=()
	backupLargeFileSizes=()
	: > "$largeFilesScanFile" || return 1
	build_find_prune_arguments
	findArguments=("$backupSourceDirectory" -xdev "${backupFindPruneArguments[@]}" -type f \
		-size "+${backupLargeFileThresholdBytes}c" -printf '%s\0%p\0')

	if [ "${backupContentRequiresRoot:-0}" = 1 ]; then
		if ! backup_privileged find "${findArguments[@]}" > "$largeFilesScanFile"; then
			return 1
		fi
	else
		if ! find "${findArguments[@]}" > "$largeFilesScanFile" 2>/dev/null; then
			return 1
		fi
	fi

	while IFS= read -r -d '' size && IFS= read -r -d '' path; do
		relative="$(path_relative_to "$backupSourceDirectory" "$path")" || continue
		[ -n "$relative" ] || continue
		if ! path_is_excluded "$relative"; then
			backupLargeFiles+=("$relative")
			backupLargeFileSizes+=("$size")
		fi
	done < "$largeFilesScanFile"
}

ask_backup_large_files() {
	local answer
	if [ ! -t 0 ]; then
		printf 'Large non-excluded files found; backup cancelled because there is no TTY.\n'
		return 1
	fi
	while :; do
		printf 'Continue despite these large files? [y/N/q]: '
		if ! IFS= read -r -n1 answer; then
			printf '\nInput closed; backup cancelled.\n'
			return 1
		fi
		printf '\n'
		case "$answer" in
			y|Y) return 0 ;;
			''|n|N) return 1 ;;
			q|Q) exit 130 ;;
			*) echo 'Please answer y, n, or q to quit.' ;;
		esac
	done
}

snapshotKind=owned
snapshotFsUuid=''
snapshotRelativePath=''

declare -A backupState=()
load_backup_state() {
	local line key value
	backupState=()
	while IFS=$'\t' read -r key value || [ -n "$key$value" ]; do
		case "$key" in
			version|status|fingerprint|source|dest_remote|dest_directory|subvolume_root|subvolume_uuid|source_relative|snapshot_path|snapshot_uuid|snapshot_kind|snapshot_fs_uuid|snapshot_relative_path) ;;
			*)
				echo -e "$cErr""Invalid Btrfs backup state key: "$cNone"$key"
				return 1
				;;
		esac
		if [[ -n "${backupState[$key]+x}" ]]; then
			echo -e "$cErr""Duplicate Btrfs backup state key: "$cNone"$key"
			return 1
		fi
		backupState[$key]="$value"
	done < "$stateFile"

	for key in version status fingerprint source dest_remote dest_directory subvolume_root subvolume_uuid source_relative snapshot_path snapshot_uuid; do
		if [[ -z "${backupState[$key]+x}" ]]; then
			echo -e "$cErr""Missing Btrfs backup state key: "$cNone"$key"
			return 1
		fi
	done
	if [[ ! "${backupState[version]}" =~ ^[12]$ ]] || [[ ! "${backupState[status]}" =~ ^(creating|ready|cleanup_pending)$ ]]; then
		echo -e "$cErr""Unsupported or invalid Btrfs backup state"$cNone
		return 1
	fi
	if [ "${backupState[version]}" = 1 ]; then
		backupState[snapshot_kind]=owned
		backupState[snapshot_fs_uuid]="$btrfsSourceFsUuid"
		backupState[snapshot_relative_path]=''
	else
		for key in snapshot_kind snapshot_fs_uuid snapshot_relative_path; do
			[[ -n "${backupState[$key]+x}" ]] || return 1
		done
		[[ "${backupState[snapshot_kind]}" =~ ^(owned|timeshift)$ ]] || return 1
		[ "${backupState[snapshot_fs_uuid]}" = "$btrfsSourceFsUuid" ] || return 1
		if [ "${backupState[snapshot_kind]}" = timeshift ]; then
			[[ "${backupState[snapshot_relative_path]}" =~ ^timeshift-btrfs/snapshots/[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}/(@|@home)$ ]] || return 1
			[ "${backupState[status]}" != creating ] || return 1
		fi
	fi
}

write_backup_state() {
	local status="$1" snapshotUuid="${2:--}" tmp="${stateFile}.tmp.$$"
	if ! (umask 077; {
		printf 'version\t2\n'
		printf 'status\t%s\n' "$status"
		printf 'fingerprint\t%s\n' "$backupFingerprint"
		printf 'source\t%s\n' "$backupSourceDirectory"
		printf 'dest_remote\t%s\n' "$backupDestRemote"
		printf 'dest_directory\t%s\n' "$backupDestDirectory"
		printf 'subvolume_root\t%s\n' "$btrfsSubvolumeRoot"
		printf 'subvolume_uuid\t%s\n' "$btrfsSubvolumeUuid"
		printf 'source_relative\t%s\n' "$btrfsSourceRelative"
		printf 'snapshot_path\t%s\n' "$btrfsSnapshotPath"
		printf 'snapshot_uuid\t%s\n' "$snapshotUuid"
		printf 'snapshot_kind\t%s\n' "$snapshotKind"
		printf 'snapshot_fs_uuid\t%s\n' "$snapshotFsUuid"
		printf 'snapshot_relative_path\t%s\n' "$snapshotRelativePath"
	} > "$tmp"); then
		rm -f -- "$tmp"
		return 1
	fi
	if ! mv -f -- "$tmp" "$stateFile"; then
		rm -f -- "$tmp"
		return 1
	fi
}

btrfs_show_value() {
	local path="$1" field="$2" details
	if ! details="$(backup_privileged btrfs subvolume show "$path")"; then
		return 1
	fi
	case "$field" in
		uuid) awk '$1 == "UUID:" { print $2; exit }' <<< "$details" ;;
		parent_uuid) awk '$1 == "Parent" && $2 == "UUID:" { print $3; exit }' <<< "$details" ;;
		id) awk '$1 == "Subvolume" && $2 == "ID:" { print $3; exit }' <<< "$details" ;;
		*) return 1 ;;
	esac
}

find_btrfs_subvolume_root() {
	local candidate="$backupSourceDirectory" inode parent
	btrfsMountTarget="$(findmnt -T "$backupSourceDirectory" -n -o TARGET)" || return 1
	btrfsMountFsRoot="$(findmnt -T "$backupSourceDirectory" -n -o FSROOT)" || return 1
	btrfsSourceFsUuid="$(findmnt -T "$backupSourceDirectory" -n -o UUID)" || return 1
	[ -n "$btrfsSourceFsUuid" ] || return 1

	while :; do
		inode="$(stat -c '%i' -- "$candidate")" || return 1
		if [ "$inode" = 256 ]; then
			btrfsSubvolumeRoot="$candidate"
			break
		fi
		if [ "$candidate" = "$btrfsMountTarget" ] || [ "$candidate" = / ]; then
			return 1
		fi
		parent="${candidate%/*}"
		[ -n "$parent" ] || parent=/
		candidate="$parent"
	done

	btrfsSourceRelative="$(path_relative_to "$btrfsSubvolumeRoot" "$backupSourceDirectory")" || return 1
	btrfsRootRelativeToMount="$(path_relative_to "$btrfsMountTarget" "$btrfsSubvolumeRoot")" || return 1
	btrfsSubvolumeTopPath="${btrfsMountFsRoot#/}"
	if [ -n "$btrfsRootRelativeToMount" ]; then
		btrfsSubvolumeTopPath="${btrfsSubvolumeTopPath%/}/${btrfsRootRelativeToMount}"
	fi
	btrfsSubvolumeTopPath="${btrfsSubvolumeTopPath#/}"

	local snapshotKey
	snapshotKey="$(printf '%s' "$dotBackupDir" | sha256sum)" || return 1
	snapshotKey="${snapshotKey%% *}"
	snapshotKey="${snapshotKey:0:16}"
	btrfsSnapshotPath="$(join_path "$btrfsSubvolumeRoot" ".dotfiles-backup-snapshot-$(id -u)-${snapshotKey}")"
	ownedSnapshotPath="$btrfsSnapshotPath"
	snapshotFsUuid="$btrfsSourceFsUuid"
}

exclude_covers_path() {
	local relative="${1#/}" rule pattern
	relative="${relative%/}"
	for rule in "${backupExcludes[@]}"; do
		rule="${rule#"${rule%%[![:space:]]*}"}"
		rule="${rule%"${rule##*[![:space:]]}"}"
		[[ "$rule" == '- /'* ]] || continue
		pattern="${rule#- /}"
		pattern="${pattern%/}"
		if [[ "$pattern" == *'*'* || "$pattern" == *'?'* || "$pattern" == *'['* ]]; then
			continue
		fi
		if [ "$relative" = "$pattern" ] || [[ "$relative" == "$pattern"/* ]]; then
			return 0
		fi
	done
	return 1
}

check_nested_btrfs_subvolumes() {
	local output line topPath relativeToRoot nestedPath relativeToSource
	local -a missing=()
	if ! output="$(backup_privileged btrfs subvolume list "$btrfsSubvolumeRoot")"; then
		echo -e "$cErr""Failed to list nested Btrfs subvolumes"$cNone
		return 1
	fi

	while IFS= read -r line; do
		[[ "$line" == *' path '* ]] || continue
		topPath="${line#* path }"
		if [ -z "$btrfsSubvolumeTopPath" ]; then
			relativeToRoot="$topPath"
		elif [[ "$topPath" == "$btrfsSubvolumeTopPath"/* ]]; then
			relativeToRoot="${topPath#"$btrfsSubvolumeTopPath"/}"
		else
			continue
		fi
		nestedPath="$(join_path "$btrfsSubvolumeRoot" "$relativeToRoot")"
		[ "$nestedPath" = "$ownedSnapshotPath" ] && continue
		if ! relativeToSource="$(path_relative_to "$backupSourceDirectory" "$nestedPath")"; then
			continue
		fi
		[ -z "$relativeToSource" ] && continue
		if ! exclude_covers_path "$relativeToSource"; then
			missing+=("- /${relativeToSource%/}/")
		fi
	done <<< "$output"

	if [ ${#missing[@]} -gt 0 ]; then
		echo -e "$cErr""Nested Btrfs subvolumes are not covered by exclude.txt:"$cNone
		.toLines "${missing[@]}"
		echo "Btrfs snapshots are not recursive; add exact directory exclusions before retrying."
		return 1
	fi
}

snapshot_exists() {
	backup_privileged test -e "$btrfsSnapshotPath"
}

verify_btrfs_snapshot() {
	local parentUuid readonly
	if ! parentUuid="$(btrfs_show_value "$btrfsSnapshotPath" parent_uuid)" || [ "$parentUuid" != "$btrfsSubvolumeUuid" ]; then
		echo -e "$cErr""Existing snapshot does not belong to the configured source: "$cFile"${btrfsSnapshotPath}"$cNone
		return 1
	fi
	if ! readonly="$(backup_privileged btrfs property get -ts "$btrfsSnapshotPath" ro)" || [ "$readonly" != ro=true ]; then
		echo -e "$cErr""Existing snapshot is not read-only: "$cFile"${btrfsSnapshotPath}"$cNone
		return 1
	fi
	btrfsSnapshotUuid="$(btrfs_show_value "$btrfsSnapshotPath" uuid)" || return 1
	[ -n "$btrfsSnapshotUuid" ]
}

validate_loaded_state() {
	if [ "${backupState[fingerprint]}" != "$backupFingerprint" ] || \
		[ "${backupState[source]}" != "$backupSourceDirectory" ] || \
		[ "${backupState[dest_remote]}" != "$backupDestRemote" ] || \
		[ "${backupState[dest_directory]}" != "$backupDestDirectory" ]; then
		echo -e "$cErr""Backup config or exclude.txt changed while a Btrfs snapshot is pending."$cNone
		echo "Restore the previous configuration or inspect and remove the pending snapshot manually:"
		echo -e "$cFile""${backupState[snapshot_path]}"$cNone
		return 1
	fi
	if [ "${backupState[subvolume_root]}" != "$btrfsSubvolumeRoot" ] || \
		[ "${backupState[subvolume_uuid]}" != "$btrfsSubvolumeUuid" ] || \
		[ "${backupState[source_relative]}" != "$btrfsSourceRelative" ]; then
		echo -e "$cErr""Btrfs layout no longer matches the pending snapshot state."$cNone
		return 1
	fi
	if [ "${backupState[snapshot_kind]}" = owned ] && [ "${backupState[snapshot_path]}" != "$ownedSnapshotPath" ]; then
		echo 'Pending snapshot path does not match the managed backup path.'
		return 1
	fi
}

# Use mounted filesystem roots only; never invoke Timeshift or mount devices.
load_timeshift_mounts() {
	local mounts target uuid
	timeshiftMountPaths=()
	timeshiftMountUuids=()
	if ! command -v jq >/dev/null 2>&1; then
		echo 'Cannot search Timeshift snapshots: jq is not installed.'
		return 1
	fi
	if ! mounts="$(findmnt --json --list -t btrfs -o TARGET,UUID,FSROOT)"; then
		echo 'Cannot list mounted Btrfs filesystems for Timeshift.'
		return 1
	fi
	if ! jq -e '.filesystems | type == "array"' >/dev/null <<< "$mounts"; then
		return 1
	fi
	while IFS= read -r -d '' target && IFS= read -r -d '' uuid; do
		timeshiftMountPaths+=("$target")
		timeshiftMountUuids+=("$uuid")
	done < <(jq -j '.filesystems[] | select(.fsroot == "/" and (.uuid | type == "string")) |
		.target, "\u0000", .uuid, "\u0000"' <<< "$mounts")
}

find_timeshift_snapshot() {
	local mount info stamp record created fsUuid subvolId index candidate repositoryFound=0
	local newest=-1 selected='' selectedRelative='' selectedId=''
	load_timeshift_mounts || return 1
	for mount in "${timeshiftMountPaths[@]}"; do
		[ -d "${mount%/}/timeshift-btrfs/snapshots" ] || continue
		repositoryFound=1
		for info in "${mount%/}"/timeshift-btrfs/snapshots/*/info.json; do
			[ -e "$info" ] || continue
			if ! jq -e 'type == "object"' "$info" >/dev/null 2>&1; then
				printf 'Skipping unreadable or invalid Timeshift metadata: %s\n' "$info"
				continue
			fi
			stamp="${info%/info.json}"
			stamp="${stamp##*/}"
			[[ "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || continue
			[ ! -e "${info%/info.json}/delete" ] || continue
			if ! record="$(jq -er --arg name "$btrfsSubvolumeTopPath" '
				select(.type == "btrfs" and .comments == "backup") |
				select($name == "@" or $name == "@home") |
				select(.subvolumes[$name][0] == $name) |
				select((.created | tostring) | test("^[0-9]{1,12}$")) |
				select((.subvolumes[$name][1] | tostring) | test("^[0-9]+$")) |
				[(.created | tonumber), .subvolumes[$name][4], .subvolumes[$name][1]] | @tsv
			' "$info")"; then
				continue
			fi
			IFS=$'\t' read -r created fsUuid subvolId <<< "$record"
			[ "$fsUuid" = "$btrfsSourceFsUuid" ] || continue
			local available=0
			for index in "${!timeshiftMountPaths[@]}"; do
				[ "${timeshiftMountUuids[$index]}" = "$fsUuid" ] || continue
				candidate="${timeshiftMountPaths[$index]%/}/timeshift-btrfs/snapshots/$stamp/$btrfsSubvolumeTopPath"
				[ -d "$(join_path "$candidate" "$btrfsSourceRelative")" ] || continue
				available=1
				if (( created > newest )); then
					newest="$created"
					selected="$candidate"
					selectedRelative="timeshift-btrfs/snapshots/$stamp/$btrfsSubvolumeTopPath"
					selectedId="$subvolId"
				fi
			done
			if [ "$available" = 0 ]; then
				printf 'Skipping Timeshift snapshot %s: source directory is not available.\n' "$stamp"
			fi
		done
	done
	if [ -z "$selected" ]; then
		if [ "$repositoryFound" = 0 ]; then
			echo 'Timeshift is not running or its snapshot repository is not mounted.'
		else
			echo 'No available Timeshift snapshot with comment "backup" contains the configured source.'
		fi
		return 1
	fi
	btrfsSnapshotPath="$selected"
	snapshotRelativePath="$selectedRelative"
	timeshiftCandidateId="$selectedId"
	printf 'Found Timeshift snapshot: %s\nSource: %s\n' "$selectedRelative" "$(join_path "$selected" "$btrfsSourceRelative")"
}

verify_timeshift_snapshot() {
	local fsUuid
	fsUuid="$(findmnt -T "$btrfsSnapshotPath" -n -o UUID)" || return 1
	[ "$fsUuid" = "$snapshotFsUuid" ] || return 1
	[ -d "$(join_path "$btrfsSnapshotPath" "$btrfsSourceRelative")" ] || return 1
	btrfsSnapshotUuid="$(btrfs_show_value "$btrfsSnapshotPath" uuid)" || return 1
	[ -n "$btrfsSnapshotUuid" ]
}

resolve_timeshift_snapshot() {
	local index candidate
	load_timeshift_mounts || return 1
	[ "${snapshotRelativePath##*/}" = "$btrfsSubvolumeTopPath" ] || return 1
	for index in "${!timeshiftMountPaths[@]}"; do
		[ "${timeshiftMountUuids[$index]}" = "$snapshotFsUuid" ] || continue
		candidate="${timeshiftMountPaths[$index]%/}/$snapshotRelativePath"
		[ -d "$candidate" ] || continue
		btrfsSnapshotPath="$candidate"
		if verify_timeshift_snapshot && [ "$btrfsSnapshotUuid" = "${backupState[snapshot_uuid]}" ]; then
			return 0
		fi
	done
	echo 'Pending Timeshift snapshot is unavailable or its UUID changed; state retained.'
	return 1
}

snapshot_tools_ready() {
	command -v btrfs >/dev/null 2>&1 || { echo 'Btrfs snapshot operations require btrfs.'; return 1; }
	btrfsSubvolumeUuid="$(btrfs_show_value "$btrfsSubvolumeRoot" uuid)" || return 1
	[ -n "$btrfsSubvolumeUuid" ]
}

# Only owned snapshots can reach deletion. Persist cleanup before deleting so
# an interrupted cleanup cannot turn into another run of the old backup.
cleanup_snapshot() {
	local expectedUuid="$btrfsSnapshotUuid"
	if [ "$snapshotKind" = owned ]; then
		[ "$btrfsSnapshotPath" = "$ownedSnapshotPath" ] || return 1
		backup_privileged test -d "$btrfsSubvolumeRoot" || return 1
		if snapshot_exists; then
			verify_btrfs_snapshot || return 1
			if [ "$expectedUuid" != "$btrfsSnapshotUuid" ]; then
				echo 'Snapshot UUID changed; refusing to delete it.'
				return 1
			fi
			backup_privileged btrfs subvolume delete "$btrfsSnapshotPath" || return 1
			printf 'Removed temporary Btrfs snapshot: %s\n' "$btrfsSnapshotPath"
		fi
	fi
	rm -f -- "$stateFile" || return 1
	backupState=()
}

discard_pending_snapshot() {
	# A crash after creation but before recording the UUID leaves status creating.
	if [ "$snapshotKind" = owned ] && [ "${backupState[status]-}" = creating ]; then
		if snapshot_exists; then
			verify_btrfs_snapshot || return 1
		fi
	fi
	write_backup_state cleanup_pending "$btrfsSnapshotUuid" && cleanup_snapshot
}

prepare_owned_snapshot() {
	if ! snapshot_exists; then
		check_nested_btrfs_subvolumes || return 1
		backup_privileged btrfs subvolume snapshot -r "$btrfsSubvolumeRoot" "$btrfsSnapshotPath" || return 1
	fi
	verify_btrfs_snapshot && write_backup_state ready "$btrfsSnapshotUuid"
}

prepare_runtime_excludes() {
	local relativeOwnFolder
	if [ -f "$backupExcludesFile" ]; then
		cp -- "$backupExcludesFile" "$runtimeExcludesFile" || return 1
	else
		: > "$runtimeExcludesFile" || return 1
	fi
	if relativeOwnFolder="$(path_relative_to "$backupSourceDirectory" "$dotBackupDir")"; then
		printf '\n- /%s/\n' "${relativeOwnFolder%/}" >> "$runtimeExcludesFile" || return 1
	fi
}

run_backup_backend() {
	local sourceDirectory="$1"
	local -a command=("$ribs" "$sourceDirectory" "$backupDestDirectory")
	local -a backendEnvironment=(
		"HOME=$HOME"
		"ownFolderName=.dotfiles/backup"
		"exclusionFileName=$runtimeExclusionFileName"
		"interactiveMode=$interactiveMode"
		"backupTargetOwner=$backupTargetOwner"
	)
	if [ -n "$backupDestRemote" ]; then
		command+=("$backupDestRemote")
	fi
	if [[ -v backupDepth ]]; then
		backendEnvironment+=("backupDepth=$backupDepth")
	fi
	if [ -n "${SSH_AUTH_SOCK:-}" ]; then
		backendEnvironment+=("SSH_AUTH_SOCK=$SSH_AUTH_SOCK")
	fi
	printf '%b' "$cRun" >&2
	printf '%q ' "${command[@]}" >&2
	printf '%b\n' "$cNone" >&2
	if [ "${backupContentRequiresRoot:-0}" = 1 ]; then
		backup_privileged env "${backendEnvironment[@]}" "${command[@]}"
	else
		"${command[@]}"
	fi
}

restore_backup_control_ownership() {
	[ "${backupContentRequiresRoot:-0}" = 1 ] || return 0
	backup_privileged chown -R -- "$backupTargetOwner" "$dotBackupDir"
}

if ! sourceFilesystem="$(findmnt -T "$backupSourceDirectory" -n -o FSTYPE)" || [ -z "$sourceFilesystem" ]; then
	echo -e "$cErr""Could not detect source filesystem: "$cFile"${backupSourceDirectory}"$cNone
	exit 4
fi

backupContentRequiresRoot=0

if [ "$backupRunAsRoot" = yes ]; then
	backupContentRequiresRoot=1
	if [ "$EUID" != 0 ] && ! command -v sudo >/dev/null 2>&1; then
		echo -e "$cErr""Root privileges are required, but sudo is not installed."$cNone
		exit 4
	fi
else
	printf 'Scanning source for content requiring root privileges...\n'
	detect_inaccessible_paths
	if [ -f "$stateFile" ]; then
		backupInaccessiblePaths+=("<pending Btrfs snapshot state: $stateFile>")
	fi
	if [ ${#backupInaccessiblePaths[@]} -gt 0 ]; then
		echo -e "$cErr""Root privileges are required for non-excluded backup content:"$cNone
		.toLines "${backupInaccessiblePaths[@]}"
		echo 'Set backupRunAsRoot=yes or add only intentionally omitted paths to exclude.txt.'
		exit 6
	fi
fi

printf 'Scanning source for large non-excluded files...\n'
if ! scan_large_files; then
	echo -e "$cErr""Could not scan for large non-excluded files"$cNone
	exit 2
fi
if [ ${#backupLargeFiles[@]} -gt 0 ]; then
	echo "Non-excluded files larger than $(format_backup_size "$backupLargeFileThresholdBytes") were found:"
	for largeFileIndex in "${!backupLargeFiles[@]}"; do
		printf '  %s\t%s\n' "$(format_backup_size "${backupLargeFileSizes[$largeFileIndex]}")" "${backupLargeFiles[$largeFileIndex]}"
	done
	if ! ask_backup_large_files; then
		echo 'Backup cancelled because large non-excluded files were found.'
		exit 130
	fi
fi

btrfsBackup=0
backupRunSource="$backupSourceDirectory"

if [ "$sourceFilesystem" = btrfs ] && [ "$backupContentRequiresRoot" = 1 ]; then
	if ! find_btrfs_subvolume_root; then
		echo -e "$cErr""Could not locate the Btrfs subvolume containing: "$cFile"${backupSourceDirectory}"$cNone
		exit 6
	fi
elif [ -f "$stateFile" ]; then
	echo -e "$cErr""A pending Btrfs backup state exists, but the configured source is no longer on Btrfs:"$cNone
	echo -e "$cFile""${stateFile}"$cNone
	exit 6
fi

if [ "$sourceFilesystem" = btrfs ] && [ "$backupContentRequiresRoot" = 1 ]; then
	if [ -f "$stateFile" ]; then
		if ! snapshot_tools_ready || ! load_backup_state || ! validate_loaded_state; then
			echo 'Could not validate pending Btrfs backup state; state retained.'
			exit 6
		fi
		snapshotKind="${backupState[snapshot_kind]}"
		snapshotFsUuid="${backupState[snapshot_fs_uuid]}"
		snapshotRelativePath="${backupState[snapshot_relative_path]}"
		btrfsSnapshotPath="${backupState[snapshot_path]}"
		btrfsSnapshotUuid="${backupState[snapshot_uuid]}"
		if [ "${backupState[status]}" = cleanup_pending ]; then
			cleanup_snapshot || exit 6
		elif ask_backup_source "Continue pending backup from $btrfsSnapshotPath? (n discards it; q discards it and quits)"; then
			if [ "$snapshotKind" = timeshift ]; then
				resolve_timeshift_snapshot || exit 6
			elif [ "${backupState[status]}" = creating ]; then
				prepare_owned_snapshot || exit 6
			elif ! snapshot_exists || ! verify_btrfs_snapshot || [ "$btrfsSnapshotUuid" != "${backupState[snapshot_uuid]}" ]; then
				echo 'Pending Btrfs snapshot is missing, invalid, or has a different UUID; state retained.'
				exit 6
			fi
			check_nested_btrfs_subvolumes || exit 6
			btrfsBackup=1
			printf 'Continuing backup from %s snapshot: %s\n' "$snapshotKind" "$btrfsSnapshotPath"
		else
			discard_pending_snapshot || exit 6
		fi
	fi

	if [ "$btrfsBackup" = 0 ]; then
		if find_timeshift_snapshot; then
			if ask_backup_source 'Use this Timeshift snapshot?'; then
				snapshotKind=timeshift
				snapshotFsUuid="$btrfsSourceFsUuid"
				if ! snapshot_tools_ready || ! verify_timeshift_snapshot || \
					[ "$(btrfs_show_value "$btrfsSnapshotPath" id)" != "$timeshiftCandidateId" ]; then
					echo 'Selected Timeshift snapshot could not be verified; backup stopped.'
					exit 6
				fi
				check_nested_btrfs_subvolumes || exit 6
				write_backup_state ready "$btrfsSnapshotUuid" || exit 6
				btrfsBackup=1
				printf 'Using Timeshift snapshot: %s\n' "$btrfsSnapshotPath"
			fi
		fi
		if [ "$btrfsBackup" = 0 ] && ask_backup_source 'Create a temporary read-only Btrfs snapshot for this backup?'; then
			snapshotKind=owned
			snapshotFsUuid="$btrfsSourceFsUuid"
			snapshotRelativePath=''
			btrfsSnapshotPath="$ownedSnapshotPath"
			snapshot_tools_ready || exit 6
			if snapshot_exists; then
				echo "Untracked snapshot already exists; refusing to reuse or delete it: $btrfsSnapshotPath"
				exit 6
			fi
			check_nested_btrfs_subvolumes || exit 6
			write_backup_state creating - || exit 6
			prepare_owned_snapshot || exit 6
			btrfsBackup=1
			printf 'Using temporary Btrfs snapshot: %s\n' "$btrfsSnapshotPath"
		fi
	fi
fi

if [ "$btrfsBackup" = 1 ]; then
	backupRunSource="$(join_path "$btrfsSnapshotPath" "$btrfsSourceRelative")"
	if ! [ -d "$backupRunSource" ]; then
		echo -e "$cErr""Source path is missing from Btrfs snapshot: "$cFile"${backupRunSource}"$cNone
		exit 6
	fi
else
	printf 'Backing up directly without a snapshot: %s\n' "$backupRunSource"
fi

if ! prepare_runtime_excludes; then
	echo -e "$cErr""Could not prepare runtime exclude file: "$cFile"${runtimeExcludesFile}"$cNone
	exit 2
fi

export ownFolderName=".dotfiles/backup"
export exclusionFileName="$runtimeExclusionFileName"
export interactiveMode="no"
[ ! -t 0 ] || export interactiveMode="yes"

if ! run_backup_backend "$backupRunSource"; then
	if ! restore_backup_control_ownership; then
		echo -e "$cErr""Backup failed and backup control files could not be returned to "$cFile"$backupTargetOwner"$cNone
	fi
	echo -e "$cErr""Error executing "$cFile"${ribs}"$cNone
	exit 255
fi

if ! restore_backup_control_ownership; then
	echo -e "$cErr""Backup succeeded, but backup control files could not be returned to "$cFile"$backupTargetOwner"$cNone
	exit 6
fi

if [ "$btrfsBackup" = 1 ]; then
	if ! write_backup_state cleanup_pending "$btrfsSnapshotUuid"; then
		echo -e "$cErr""Backup succeeded, but cleanup state could not be persisted."$cNone
		exit 6
	fi
	if ! cleanup_snapshot; then
		echo -e "$cErr""Backup succeeded, but snapshot cleanup failed; the next run will retry it:"$cNone
		echo -e "$cFile""${btrfsSnapshotPath}"$cNone
		exit 6
	fi
fi

exit 0
