#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

lscript="$dotfilesDir/wmctrl/sendPidToPipeAndExec.sh"
if [ ! -f $lscript ]; then
	echo "script not found: $lscript"
	exit 1
fi

.needCommand cat tr fold head

pipe="/tmp/"$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

echo "creating pipe: $pipe"
mkfifo $pipe
trap "rm -f $pipe" EXIT

scmd="$lscript $pipe $@"
echo "calling script: $scmd"
exec $lscript "$pipe" "$@" &

#TODO what if no pid is comming for some time
echo "waiting for pid ..."
if ! read pid <$pipe; then
	echo "failed to read from pipe"
fi

echo "got pid: $pid"

#TODO try for a few seconds in loop
.run "wmctrl -lp" # | grep ' $pid ' | awk '{print \$1}'"
res=$?
if [ $res -ne 0 ]; then
	echo "error getting wid"
	exit
fi

echo "got wid: $wid"
