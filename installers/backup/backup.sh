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

unset backupSourceDirectory backupDestRemote backupDestDirectory backupDepth
if ! .loadConfig "$backupConfigFile" backupSourceDirectory backupDestRemote backupDestDirectory backupDepth; then
	exit 2
fi

for requiredVariable in backupSourceDirectory backupDestRemote backupDestDirectory; do
	if [[ ! -v "$requiredVariable" ]]; then
		echo -e "$cErr""Missing variable after config load: "$cNone"\$$requiredVariable"
		exit 2
	fi
done
unset requiredVariable

if [[ -v backupDepth ]]; then
	if [[ ! "$backupDepth" =~ ^[1-9][0-9]*$ ]]; then
		echo -e "$cErr""Invalid backup config: "$cNone"\$backupDepth must be a positive integer"
		exit 2
	fi
	export backupDepth
fi

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
			"$backupSourceDirectory" "$backupDestRemote" "$backupDestDirectory" "${backupDepth-<default>}"
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

stateFile="${dotBackupDir}/.btrfs-backup.state"
runtimeExcludesFile="${dotBackupDir}/.exclude.runtime"
runtimeExclusionFileName="${runtimeExcludesFile##*/}"
trap 'rm -f -- "$runtimeExcludesFile"' EXIT

declare -A backupState=()
load_backup_state() {
	local line key value
	backupState=()
	while IFS=$'\t' read -r key value || [ -n "$key$value" ]; do
		case "$key" in
			version|status|fingerprint|source|dest_remote|dest_directory|subvolume_root|subvolume_uuid|source_relative|snapshot_path|snapshot_uuid) ;;
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
	if [ "${backupState[version]}" != 1 ] || [[ ! "${backupState[status]}" =~ ^(creating|ready|cleanup_pending)$ ]]; then
		echo -e "$cErr""Unsupported or invalid Btrfs backup state"$cNone
		return 1
	fi
}

write_backup_state() {
	local status="$1" snapshotUuid="${2:--}" tmp="${stateFile}.tmp.$$"
	if ! (umask 077; {
		printf 'version\t1\n'
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
	if ! details="$(sudo btrfs subvolume show "$path")"; then
		return 1
	fi
	case "$field" in
		uuid) awk '$1 == "UUID:" { print $2; exit }' <<< "$details" ;;
		parent_uuid) awk '$1 == "Parent" && $2 == "UUID:" { print $3; exit }' <<< "$details" ;;
		*) return 1 ;;
	esac
}

find_btrfs_subvolume_root() {
	local candidate="$backupSourceDirectory" inode parent
	btrfsMountTarget="$(findmnt -T "$backupSourceDirectory" -n -o TARGET)" || return 1
	btrfsMountFsRoot="$(findmnt -T "$backupSourceDirectory" -n -o FSROOT)" || return 1

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

	if ! btrfsSubvolumeUuid="$(btrfs_show_value "$btrfsSubvolumeRoot" uuid)" || [ -z "$btrfsSubvolumeUuid" ]; then
		return 1
	fi

	local snapshotKey
	snapshotKey="$(printf '%s' "$dotBackupDir" | sha256sum)" || return 1
	snapshotKey="${snapshotKey%% *}"
	snapshotKey="${snapshotKey:0:16}"
	btrfsSnapshotPath="$(join_path "$btrfsSubvolumeRoot" ".dotfiles-backup-snapshot-$(id -u)-${snapshotKey}")"
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
	if ! output="$(sudo btrfs subvolume list "$btrfsSubvolumeRoot")"; then
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
		[ "$nestedPath" = "$btrfsSnapshotPath" ] && continue
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
	sudo test -e "$btrfsSnapshotPath"
}

verify_btrfs_snapshot() {
	local parentUuid readonly
	if ! parentUuid="$(btrfs_show_value "$btrfsSnapshotPath" parent_uuid)" || [ "$parentUuid" != "$btrfsSubvolumeUuid" ]; then
		echo -e "$cErr""Existing snapshot does not belong to the configured source: "$cFile"${btrfsSnapshotPath}"$cNone
		return 1
	fi
	if ! readonly="$(sudo btrfs property get -ts "$btrfsSnapshotPath" ro)" || [ "$readonly" != ro=true ]; then
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
		[ "${backupState[source_relative]}" != "$btrfsSourceRelative" ] || \
		[ "${backupState[snapshot_path]}" != "$btrfsSnapshotPath" ]; then
		echo -e "$cErr""Btrfs layout no longer matches the pending snapshot state."$cNone
		return 1
	fi
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
	if [ -n "$backupDestRemote" ]; then
		command+=("$backupDestRemote")
	fi
	printf '%b' "$cRun" >&2
	printf '%q ' "${command[@]}" >&2
	printf '%b\n' "$cNone" >&2
	"${command[@]}"
}

if ! sourceFilesystem="$(findmnt -T "$backupSourceDirectory" -n -o FSTYPE)" || [ -z "$sourceFilesystem" ]; then
	echo -e "$cErr""Could not detect source filesystem: "$cFile"${backupSourceDirectory}"$cNone
	exit 4
fi
btrfsBackup=0
backupRunSource="$backupSourceDirectory"

if [ "$sourceFilesystem" = btrfs ]; then
	btrfsBackup=1
	if ! command -v btrfs >/dev/null 2>&1; then
		echo -e "$cErr""Required command not found: "$cCmd"btrfs"$cNone
		exit 4
	fi
	if ! sudo -v; then
		echo -e "$cErr""Btrfs backup requires sudo for snapshot operations"$cNone
		exit 6
	fi
	if ! find_btrfs_subvolume_root; then
		echo -e "$cErr""Could not locate the Btrfs subvolume containing: "$cFile"${backupSourceDirectory}"$cNone
		exit 6
	fi
elif [ -f "$stateFile" ]; then
	echo -e "$cErr""A pending Btrfs backup state exists, but the configured source is no longer on Btrfs:"$cNone
	echo -e "$cFile""${stateFile}"$cNone
	exit 6
fi

if [ "$btrfsBackup" = 1 ]; then
	if [ -f "$stateFile" ]; then
		if ! load_backup_state || ! validate_loaded_state; then
			exit 6
		fi
		case "${backupState[status]}" in
			cleanup_pending)
				if snapshot_exists; then
					if ! verify_btrfs_snapshot; then
						echo -e "$cErr""Could not clean up completed snapshot: "$cFile"${btrfsSnapshotPath}"$cNone
						exit 6
					fi
					if [ "${backupState[snapshot_uuid]}" != "$btrfsSnapshotUuid" ]; then
						echo -e "$cErr""Completed Btrfs snapshot UUID does not match saved state"$cNone
						exit 6
					fi
					if ! sudo btrfs subvolume delete "$btrfsSnapshotPath"; then
						echo -e "$cErr""Could not clean up completed snapshot: "$cFile"${btrfsSnapshotPath}"$cNone
						exit 6
					fi
				fi
				if ! rm -f -- "$stateFile"; then
					echo -e "$cErr""Could not remove completed Btrfs backup state: "$cFile"${stateFile}"$cNone
					exit 6
				fi
				backupState=()
				;;
			creating)
				if snapshot_exists; then
					if ! verify_btrfs_snapshot; then
						exit 6
					fi
				else
					if ! check_nested_btrfs_subvolumes || ! sudo btrfs subvolume snapshot -r "$btrfsSubvolumeRoot" "$btrfsSnapshotPath"; then
						echo -e "$cErr""Could not create Btrfs snapshot"$cNone
						exit 6
					fi
					if ! verify_btrfs_snapshot; then
						exit 6
					fi
				fi
				if ! write_backup_state ready "$btrfsSnapshotUuid"; then
					echo -e "$cErr""Could not persist ready Btrfs snapshot state"$cNone
					exit 6
				fi
				;;
			ready)
				if ! snapshot_exists || ! verify_btrfs_snapshot; then
					echo -e "$cErr""Pending Btrfs snapshot is missing or invalid"$cNone
					exit 6
				fi
				if [ "${backupState[snapshot_uuid]}" != "$btrfsSnapshotUuid" ]; then
					echo -e "$cErr""Pending Btrfs snapshot UUID does not match saved state"$cNone
					exit 6
				fi
				;;
		esac
	fi

	if [ ! -f "$stateFile" ]; then
		if snapshot_exists; then
			echo -e "$cErr""An untracked snapshot already exists; refusing to reuse or delete it:"$cNone
			echo -e "$cFile""${btrfsSnapshotPath}"$cNone
			exit 6
		fi
		if ! check_nested_btrfs_subvolumes; then
			exit 6
		fi
		if ! write_backup_state creating -; then
			echo -e "$cErr""Could not persist Btrfs snapshot creation state"$cNone
			exit 6
		fi
		if ! sudo btrfs subvolume snapshot -r "$btrfsSubvolumeRoot" "$btrfsSnapshotPath"; then
			echo -e "$cErr""Could not create Btrfs snapshot: "$cFile"${btrfsSnapshotPath}"$cNone
			exit 6
		fi
		if ! verify_btrfs_snapshot || ! write_backup_state ready "$btrfsSnapshotUuid"; then
			echo -e "$cErr""Could not verify or persist Btrfs snapshot state"$cNone
			exit 6
		fi
	fi

	backupRunSource="$(join_path "$btrfsSnapshotPath" "$btrfsSourceRelative")"
	if ! sudo test -d "$backupRunSource"; then
		echo -e "$cErr""Source path is missing from Btrfs snapshot: "$cFile"${backupRunSource}"$cNone
		exit 6
	fi
fi

if ! prepare_runtime_excludes; then
	echo -e "$cErr""Could not prepare runtime exclude file: "$cFile"${runtimeExcludesFile}"$cNone
	exit 2
fi

export ownFolderName=".dotfiles/backup"
export exclusionFileName="$runtimeExclusionFileName"
export interactiveMode="yes"

if ! run_backup_backend "$backupRunSource"; then
	echo -e "$cErr""Error executing "$cFile"${ribs}"$cNone
	exit 255
fi

if [ "$btrfsBackup" = 1 ]; then
	if ! write_backup_state cleanup_pending "$btrfsSnapshotUuid"; then
		echo -e "$cErr""Backup succeeded, but cleanup state could not be persisted."$cNone
		exit 6
	fi
	if ! verify_btrfs_snapshot || ! sudo btrfs subvolume delete "$btrfsSnapshotPath"; then
		echo -e "$cErr""Backup succeeded, but snapshot cleanup failed; the next run will retry it:"$cNone
		echo -e "$cFile""${btrfsSnapshotPath}"$cNone
		exit 6
	fi
	if ! rm -f -- "$stateFile"; then
		echo -e "$cErr""Snapshot was deleted, but completed Btrfs backup state could not be removed: "$cFile"${stateFile}"$cNone
		exit 6
	fi
fi

exit 0
