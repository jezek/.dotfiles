# Dotfiles backup

Run `.backup` to back up the configured source. Local and remote backups normally
compare file size and modification time, avoiding a full read of unchanged files.
Use `.backup --checksum` for a full content comparison, including changes that
preserve both size and modification time. This can take as long as the previous
checksum-based backups even when no files need transferring.

When root access is configured, sudo authentication happens before privileged
work starts and is refreshed every minute until the backup exits. Later sudo
commands and SSH connections never ask for another password; authentication
failures are reported instead of waiting for input. The initial SSH connection
may ask for credentials when running in a terminal. Creating or maintaining an
owned Btrfs snapshot also initializes sudo, even when the data transfer runs as
the user. An accessible Timeshift snapshot can be used without sudo.

After a successful snapshot backup, completion is recorded before restoring
working-file ownership or deleting the temporary snapshot. If either cleanup
step fails, the next `.backup` finishes cleanup and exits without another data
transfer. Run `.backup` again to start a new backup. Failed transfers retain the
snapshot for resuming. Timeshift snapshots are never deleted by this script.

Failed log uploads are reported and retained locally for a later run. They do
not make a successful data transfer fail. Existing pending states marked `ready`
are resumed normally because they do not prove that the transfer finished.

Run the fixture and local rsync tests with:

```sh
bash installers/backup/.tests/run.sh
```
