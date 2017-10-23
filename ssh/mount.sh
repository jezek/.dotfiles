#! /bin/bash

cErr='\e[91m'
cNone='\e[0m'

# Yes/no dialog. Default answer (if pressing enter) is Yes (can be changed)
# The first argument is the message that the user will see.
# Second argumenti is optional, and if "n", then default will be No
# If the user enters n/N, send exit 1.
.check_yes_no(){
	while true; do
		local default="y"
		local hint="[Y/n]"
		local yn=""
		if [ "$2" = n ]; then
			default="n"
			hint="[y/N]"
		fi
		echo -e -n "$1 $hint: "
		read -n1 yn
		if [ "$yn" = "" ]; then
			yn="$default"
		else
			echo ""
		fi
		case "$yn" in
			[Yy] )
				break;;
			[Nn] )
				echo "No"
				return 1;;
			* )
				echo -e "${cErr}Please answer y or n for yes or no, or Enter for default.${cNone}";;
		esac
	done;
	echo "Yes"
}
mountDir=/home/jezek/pripojenia/jEzHoMe_sever/jezek
if [ ! "$(ls -A $mountDir)" ]
then
  echo "Not mounted"
  echo -n "Mounting ... "
  sshfs jezek@192.168.88.132:/home/jezek $mountDir -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3
  echo "[OK]"
else
  echo "Allready mounted"
	if .check_yes_no "Unmount?" n ; then
		echo -n "Unmountng ... "
		fusermount -u $mountDir
		echo "[OK]"
	fi
fi
