#!/bin/bash

set -euo pipefail

testDir="$(cd "$(dirname "$0")" && pwd)"
repoRoot="$(cd "$testDir/../../.." && pwd)"
testRoot="$(mktemp -d)"
trap 'rm -rf -- "$testRoot"' EXIT

testsRun=0

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

assert_status() {
	[ "$runStatus" = "$1" ] || fail "$2: expected status $1, got $runStatus; output: $runOutput"
}

assert_contains() {
	[[ "$runOutput" == *"$1"* ]] || fail "$2: missing '$1'; output: $runOutput"
}

assert_not_contains() {
	[[ "$runOutput" != *"$1"* ]] || fail "$2: unexpectedly found '$1'; output: $runOutput"
}

assert_file_contains() {
	[ -f "$1" ] || fail "$3: missing file $1"
	rg -Fq -- "$2" "$1" || fail "$3: missing '$2' in $1"
}

assert_absent() {
	[ ! -e "$1" ] || fail "$2: expected $1 to be absent"
}

write_fixture_commands() {
	mkdir -p "$caseRoot/fake-bin"
	cat > "$caseRoot/fake-bin/findmnt" <<'EOF'
#!/bin/bash
if [[ " $* " == *' --json '* ]]; then
	if [ "${TIMESHIFT_AVAILABLE:-1}" = 1 ]; then
		printf '{"filesystems":[{"target":"%s/live","uuid":"home-fs","fsroot":"/@home"},{"target":"%s/ts-root","uuid":"root-fs","fsroot":"/"},{"target":"%s/%s","uuid":"home-fs","fsroot":"/"}]}' \
			"$CASE_ROOT" "$CASE_ROOT" "$CASE_ROOT" "${TIMESHIFT_HOME:-ts-home}"
	else
		printf '{"filesystems":[{"target":"%s/live","uuid":"home-fs","fsroot":"/@home"}]}' "$CASE_ROOT"
	fi
	exit 0
fi
field=''
target=''
while [ "$#" -gt 0 ]; do
	case "$1" in
		-T) target="$2"; shift 2 ;;
		-o) field="$2"; shift 2 ;;
		*) shift ;;
	esac
done
case "$field" in
	FSTYPE) echo "${SOURCE_FSTYPE:-btrfs}" ;;
	TARGET) echo "$CASE_ROOT/live" ;;
	FSROOT) echo /@home ;;
	UUID) echo home-fs ;;
	*) exit 1 ;;
esac
EOF
	cat > "$caseRoot/fake-bin/stat" <<'EOF'
#!/bin/bash
path="${!#}"
if [ "$path" = "$CASE_ROOT/live" ]; then
	echo 256
else
	exec /usr/bin/stat "$@"
fi
EOF
	cat > "$caseRoot/fake-bin/sudo" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$CASE_LOG/sudo"
[ "${1:-}" != -n ] || shift
if [ "${1:-}" = find ]; then
	chmod 755 "$CASE_ROOT/live/jezek/root-only" 2>/dev/null || true
fi
exec "$@"
EOF
	cat > "$caseRoot/fake-bin/btrfs" <<'EOF'
#!/bin/bash
operation="${1:-} ${2:-}"
case "$operation" in
	'subvolume show')
		path="$3"
		case "$path" in
			*/2024-01-02_00-00-00/@home) uuid=timeshift-new-uuid; parent=-; id=302 ;;
			*/2024-01-01_00-00-00/@home) uuid=timeshift-old-uuid; parent=-; id=301 ;;
			*/.dotfiles-backup-snapshot-*) uuid=owned-uuid; parent=live-uuid; id=400 ;;
			*/live) uuid=live-uuid; parent=-; id=100 ;;
			*) exit 1 ;;
		esac
		printf 'Name: fixture\nUUID: %s\nParent UUID: %s\nSubvolume ID: %s\n' "$uuid" "$parent" "$id"
		;;
	'subvolume list') exit 0 ;;
	'subvolume snapshot')
		sourcePath="${@: -2:1}"
		snapshotPath="${@: -1}"
		mkdir -p "$snapshotPath/jezek"
		printf 'snapshot %s %s\n' "$sourcePath" "$snapshotPath" >> "$CASE_LOG/btrfs"
		;;
	'subvolume delete')
		snapshotPath="${@: -1}"
		printf 'delete %s\n' "$snapshotPath" >> "$CASE_LOG/btrfs"
		rm -rf -- "$snapshotPath"
		;;
	'property get') echo ro=true ;;
	*) exit 1 ;;
esac
EOF
	cat > "$caseRoot/fake-bin/rsync" <<'EOF'
#!/bin/bash
exit 0
EOF
	chmod +x "$caseRoot/fake-bin/"*
}

write_timeshift_info() {
	local stamp="$1" created="$2" comment="$3" id="$4"
	local infoDir="$caseRoot/ts-root/timeshift-btrfs/snapshots/$stamp"
	local sourceDir="$caseRoot/ts-home/timeshift-btrfs/snapshots/$stamp/@home/jezek"
	mkdir -p "$infoDir" "$sourceDir"
	cat > "$infoDir/info.json" <<EOF
{
  "created": "$created",
  "comments": "$comment",
  "type": "btrfs",
  "subvolumes": {"@home": ["@home", "$id", "0", "0", "home-fs"]}
}
EOF
}

setup_case() {
	caseRoot="$testRoot/$1"
	caseHome="$caseRoot/home"
	caseLog="$caseRoot/log"
	mkdir -p "$caseHome/.dotfiles/installers/backup/rsync-incremental-backup" \
		"$caseHome/.dotfiles/backup" "$caseRoot/live/jezek" "$caseLog"
	cp "$repoRoot/installers/install.sh" "$caseHome/.dotfiles/installers/install.sh"
	cp "$repoRoot/installers/backup/backup.sh" "$caseHome/.dotfiles/installers/backup/backup.sh"
	cat > "$caseHome/.dotfiles/backup/config" <<EOF
backupSourceDirectory="$caseRoot/live/jezek"
backupDestRemote=""
backupDestDirectory="$caseRoot/destination"
backupDepth="0"
backupRunAsRoot="yes"
backupLargeFileThresholdBytes="5368709120"
EOF
	: > "$caseHome/.dotfiles/backup/exclude.txt"
	cat > "$caseHome/.dotfiles/installers/backup/rsync-incremental-backup/rsync-incremental-backup-local" <<'EOF'
#!/bin/bash
printf '%s\n' "$1" >> "$CASE_LOG/backend"
exit "${BACKEND_RC:-0}"
EOF
	chmod +x "$caseHome/.dotfiles/installers/backup/backup.sh" \
		"$caseHome/.dotfiles/installers/backup/rsync-incremental-backup/rsync-incremental-backup-local"
	write_fixture_commands
	export CASE_ROOT="$caseRoot" CASE_LOG="$caseLog"
	write_timeshift_info 2024-01-01_00-00-00 100 backup 301
	write_timeshift_info 2024-01-02_00-00-00 200 backup 302
	write_timeshift_info 2024-01-03_00-00-00 300 upgrade 303
}

make_root_required() {
	mkdir -p "$caseRoot/live/jezek/root-only"
	chmod 000 "$caseRoot/live/jezek/root-only"
}

test_readable_source_does_not_use_sudo() {
	setup_case readable-no-sudo
	run_non_tty
	assert_status 0 "$FUNCNAME"
	assert_absent "$caseLog/sudo" "$FUNCNAME"
	assert_contains 'Backing up directly without a snapshot' "$FUNCNAME"
}

test_root_backend_preserves_user_environment() {
	setup_case root-backend-environment
	make_root_required
	SSH_AUTH_SOCK="$caseRoot/ssh-agent.sock" run_non_tty
	assert_status 0 "$FUNCNAME"
	assert_file_contains "$caseLog/sudo" "HOME=$caseHome" "$FUNCNAME"
	assert_file_contains "$caseLog/sudo" 'ownFolderName=.dotfiles/backup' "$FUNCNAME"
	assert_file_contains "$caseLog/sudo" 'exclusionFileName=.exclude.runtime' "$FUNCNAME"
	assert_file_contains "$caseLog/sudo" 'interactiveMode=no' "$FUNCNAME"
	assert_file_contains "$caseLog/sudo" 'backupDepth=0' "$FUNCNAME"
	assert_file_contains "$caseLog/sudo" 'backupTargetOwner=jezek:jezek' "$FUNCNAME"
	assert_file_contains "$caseLog/sudo" "SSH_AUTH_SOCK=$caseRoot/ssh-agent.sock" "$FUNCNAME"
}

test_root_required_without_permission_aborts() {
	setup_case root-without-permission
	make_root_required
	sed -i 's/backupRunAsRoot="yes"/backupRunAsRoot="no"/' "$caseHome/.dotfiles/backup/config"
	run_non_tty
	assert_status 6 "$FUNCNAME"
	assert_contains 'Root privileges are required' "$FUNCNAME"
	assert_contains 'root-only' "$FUNCNAME"
	assert_absent "$caseLog/sudo" "$FUNCNAME"
	assert_absent "$caseLog/backend" "$FUNCNAME"
}

test_large_file_without_exclude_is_rejected_non_tty() {
	setup_case large-file
	truncate -s $((6 * 1024 * 1024 * 1024)) "$caseRoot/live/jezek/large.bin"
	run_non_tty
	assert_status 130 "$FUNCNAME"
	assert_contains 'large.bin' "$FUNCNAME"
	assert_contains 'Backup cancelled because large non-excluded files were found' "$FUNCNAME"
	assert_absent "$caseLog/backend" "$FUNCNAME"
}

test_large_file_tty_can_continue() {
	setup_case large-file-tty
	truncate -s $((6 * 1024 * 1024 * 1024)) "$caseRoot/live/jezek/large.bin"
	run_tty y
	assert_status 0 "$FUNCNAME"
	assert_contains 'Continue despite these large files?' "$FUNCNAME"
	assert_file_contains "$caseLog/backend" "$caseRoot/live/jezek" "$FUNCNAME"
}

test_large_file_under_excluded_directory_is_ignored() {
	setup_case excluded-large-file
	mkdir -p "$caseRoot/live/jezek/models"
	truncate -s $((6 * 1024 * 1024 * 1024)) "$caseRoot/live/jezek/models/large.bin"
	printf '%s\n' '- /models/' > "$caseHome/.dotfiles/backup/exclude.txt"
	run_non_tty
	assert_status 0 "$FUNCNAME"
	assert_not_contains 'large non-excluded files' "$FUNCNAME"
	assert_file_contains "$caseLog/backend" "$caseRoot/live/jezek" "$FUNCNAME"
}

run_non_tty() {
	set +e
	runOutput="$(HOME="$caseHome" PATH="$caseRoot/fake-bin:$PATH" \
		TIMESHIFT_AVAILABLE="${TIMESHIFT_AVAILABLE:-1}" TIMESHIFT_HOME="${TIMESHIFT_HOME:-ts-home}" \
		SOURCE_FSTYPE="${SOURCE_FSTYPE:-btrfs}" BACKEND_RC="${BACKEND_RC:-0}" \
		"$caseHome/.dotfiles/installers/backup/backup.sh" </dev/null 2>&1)"
	runStatus=$?
	set -e
}

run_tty() {
	local answers="$1"
	set +e
	runOutput="$(printf '%s' "$answers" | HOME="$caseHome" PATH="$caseRoot/fake-bin:$PATH" \
		TIMESHIFT_AVAILABLE="${TIMESHIFT_AVAILABLE:-1}" TIMESHIFT_HOME="${TIMESHIFT_HOME:-ts-home}" \
		SOURCE_FSTYPE="${SOURCE_FSTYPE:-btrfs}" BACKEND_RC="${BACKEND_RC:-0}" script -q -e -c \
		"$caseHome/.dotfiles/installers/backup/backup.sh" /dev/null 2>&1)"
	runStatus=$?
	set -e
}

owned_snapshot_path() {
	local key
	key="$(printf '%s' "$caseHome/.dotfiles/backup" | sha256sum)"
	printf '%s/live/.dotfiles-backup-snapshot-%s-%s' "$caseRoot" "$(id -u)" "${key:0:16}"
}

write_v1_pending_state() {
	local snapshotPath fingerprint
	snapshotPath="$(owned_snapshot_path)"
	mkdir -p "$snapshotPath/jezek"
	fingerprint="$({
		printf 'source\0%s\0remote\0%s\0destination\0%s\0depth\0%s\0' \
			"$caseRoot/live/jezek" '' "$caseRoot/destination" '0'
		printf 'excludes\0present\0'
		cat "$caseHome/.dotfiles/backup/exclude.txt"
	} | sha256sum)"
	fingerprint="${fingerprint%% *}"
	cat > "$caseHome/.dotfiles/backup/.btrfs-backup.state" <<EOF
version	1
status	ready
fingerprint	$fingerprint
source	$caseRoot/live/jezek
dest_remote
dest_directory	$caseRoot/destination
subvolume_root	$caseRoot/live
subvolume_uuid	live-uuid
source_relative	jezek
snapshot_path	$snapshotPath
snapshot_uuid	owned-uuid
EOF
}

test_timeshift_default() {
	setup_case timeshift-default
	make_root_required
	run_non_tty
	assert_status 0 "$FUNCNAME"
	assert_contains 'Yes (no TTY)' "$FUNCNAME"
	assert_contains 'Using Timeshift snapshot' "$FUNCNAME"
	assert_file_contains "$caseLog/backend" '/2024-01-02_00-00-00/@home/jezek' "$FUNCNAME"
	[ ! -e "$caseLog/btrfs" ] || ! rg -q '^delete ' "$caseLog/btrfs" || fail "$FUNCNAME: deleted a Timeshift snapshot"
	assert_absent "$caseHome/.dotfiles/backup/.btrfs-backup.state" "$FUNCNAME"
}

test_enter_accepts_timeshift() {
	setup_case timeshift-enter
	make_root_required
	run_tty $'\n'
	assert_status 0 "$FUNCNAME"
	assert_contains 'Using Timeshift snapshot' "$FUNCNAME"
	assert_file_contains "$caseLog/backend" '/2024-01-02_00-00-00/@home/jezek' "$FUNCNAME"
}

test_owned_default_without_timeshift() {
	setup_case owned-default
	make_root_required
	TIMESHIFT_AVAILABLE=0 run_non_tty
	assert_status 0 "$FUNCNAME"
	assert_contains 'Timeshift is not running' "$FUNCNAME"
	assert_contains 'Using temporary Btrfs snapshot' "$FUNCNAME"
	assert_file_contains "$caseLog/btrfs" 'snapshot ' "$FUNCNAME"
	assert_file_contains "$caseLog/btrfs" 'delete ' "$FUNCNAME"
	assert_absent "$(owned_snapshot_path)" "$FUNCNAME"
}

test_decline_both_uses_live_source() {
	setup_case direct
	make_root_required
	run_tty nn
	assert_status 0 "$FUNCNAME"
	assert_contains 'Backing up directly without a snapshot' "$FUNCNAME"
	assert_file_contains "$caseLog/backend" "$caseRoot/live/jezek" "$FUNCNAME"
	[ ! -e "$caseLog/btrfs" ] || fail "$FUNCNAME: performed a Btrfs mutation"
}

test_non_btrfs_uses_live_source_without_questions() {
	setup_case non-btrfs
	SOURCE_FSTYPE=ext4 run_non_tty
	assert_status 0 "$FUNCNAME"
	assert_contains 'Backing up directly without a snapshot' "$FUNCNAME"
	assert_not_contains '[Y/n/q]' "$FUNCNAME"
	assert_file_contains "$caseLog/backend" "$caseRoot/live/jezek" "$FUNCNAME"
}

test_q_stops_before_backup() {
	setup_case quit
	make_root_required
	TIMESHIFT_AVAILABLE=0 run_tty q
	assert_status 130 "$FUNCNAME"
	assert_contains 'Backup cancelled' "$FUNCNAME"
	assert_absent "$caseLog/backend" "$FUNCNAME"
}

test_q_discards_v1_owned_snapshot() {
	setup_case quit-pending
	make_root_required
	write_v1_pending_state
	run_tty q
	assert_status 130 "$FUNCNAME"
	assert_file_contains "$caseLog/btrfs" 'delete ' "$FUNCNAME"
	assert_absent "$(owned_snapshot_path)" "$FUNCNAME"
	assert_absent "$caseHome/.dotfiles/backup/.btrfs-backup.state" "$FUNCNAME"
	assert_absent "$caseLog/backend" "$FUNCNAME"
}

test_timeshift_failure_resumes_after_mount_path_changes() {
	setup_case timeshift-resume
	make_root_required
	BACKEND_RC=42 run_non_tty
	assert_status 255 "$FUNCNAME first run"
	assert_file_contains "$caseHome/.dotfiles/backup/.btrfs-backup.state" $'snapshot_kind\ttimeshift' "$FUNCNAME"
	mv "$caseRoot/ts-home" "$caseRoot/ts-home-next"
	BACKEND_RC=0 TIMESHIFT_HOME=ts-home-next run_non_tty
	assert_status 0 "$FUNCNAME second run"
	assert_contains 'Continuing backup from timeshift snapshot' "$FUNCNAME"
	assert_file_contains "$caseLog/backend" '/ts-home-next/timeshift-btrfs/snapshots/2024-01-02_00-00-00/@home/jezek' "$FUNCNAME"
	assert_absent "$caseHome/.dotfiles/backup/.btrfs-backup.state" "$FUNCNAME"
	[ ! -e "$caseLog/btrfs" ] || ! rg -q '^delete ' "$caseLog/btrfs" || fail "$FUNCNAME: deleted a Timeshift snapshot"
}

test_owned_failure_resumes_and_deletes_after_success() {
	setup_case owned-resume
	make_root_required
	BACKEND_RC=42 TIMESHIFT_AVAILABLE=0 run_non_tty
	assert_status 255 "$FUNCNAME first run"
	assert_file_contains "$caseHome/.dotfiles/backup/.btrfs-backup.state" $'snapshot_kind\towned' "$FUNCNAME"
	[ -d "$(owned_snapshot_path)" ] || fail "$FUNCNAME: owned snapshot was not retained"
	[ "$(rg -c '^snapshot ' "$caseLog/btrfs")" = 1 ] || fail "$FUNCNAME: snapshot was created more than once"
	BACKEND_RC=0 TIMESHIFT_AVAILABLE=0 run_non_tty
	assert_status 0 "$FUNCNAME second run"
	assert_contains 'Continuing backup from owned snapshot' "$FUNCNAME"
	assert_file_contains "$caseLog/btrfs" 'delete ' "$FUNCNAME"
	assert_absent "$(owned_snapshot_path)" "$FUNCNAME"
	assert_absent "$caseHome/.dotfiles/backup/.btrfs-backup.state" "$FUNCNAME"
}

for testFunction in \
	test_readable_source_does_not_use_sudo \
	test_root_backend_preserves_user_environment \
	test_root_required_without_permission_aborts \
	test_large_file_without_exclude_is_rejected_non_tty \
	test_large_file_tty_can_continue \
	test_large_file_under_excluded_directory_is_ignored \
	test_timeshift_default \
	test_enter_accepts_timeshift \
	test_owned_default_without_timeshift \
	test_decline_both_uses_live_source \
	test_non_btrfs_uses_live_source_without_questions \
	test_q_stops_before_backup \
	test_q_discards_v1_owned_snapshot \
	test_timeshift_failure_resumes_after_mount_path_changes \
	test_owned_failure_resumes_and_deletes_after_success
do
	"$testFunction"
	testsRun=$((testsRun + 1))
	echo "ok $testsRun - $testFunction"
done

echo "All $testsRun backup tests passed."
