#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

lscript="$dotfilesDir/wmctrl/sendPidToPipeAndExec.sh"
if [ ! -f $lscript ]; then
	echo "script not found: $lscript"
	exit 1
fi

.needCommand cat tr fold head mkfifo wmctrl

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
	exit 2
fi

echo "got pid: $pid"

if [ "$pid" = "" ]; then
	echo "empty pid"
	exit 3
fi

interval=.5
maxCount=10 # 5s
count=0
wid=""
while [ "$wid" = "" ] && [ $count -lt $maxCount ]; do
	.runRes wid "wmctrl -lp | grep ' $pid ' | awk '{print \$1}'"
	res=$?
	if [ $res -ne 0 ]; then
		echo "error getting wid"
		exit
	fi
	if [ "$wid" = "" ]; then
		sleep $interval
	fi
done


if [ "$wid" = "" ]; then
	echo "empty wid"
	exit 4
fi

echo "got wid: $wid"
.run "wmctrl -i -r $wid -b add,maximized_horz,maximized_vert"

