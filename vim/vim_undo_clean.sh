#! /bin/bash
if [ -z ${dotfilesDir+x} ]; then
	source "$HOME/.dotfiles/install.sh" essentials "$@"
fi

.needCommand ls wc realpath sed rm

vimundoDir="$HOME/.vim/undo/"

if [ ! -d "$vimundoDir" ]; then
	[ "$1" = plugin ] && return
	exit
fi

if [ $# = 0 ]; then
	.runRes fileCount "ls -1A ${vimundoDir} | wc -l"
	if [ ! "$fileCount" = "0" ]; then
		if .check_yes_no "remove all ${fileCount} vim undo files?"; then
			.run "rm ${vimundoDir}*"
			echo "removed"
		fi
	fi

	[ "$1" = plugin ] && return
	exit
fi


for arg in $@; do
	if [ -f "$arg" ]; then
		.runRes argFullpath "realpath vim_undo_clean.sh | sed 's/\\//%/g'"
		undofile=$vimundoDir$argFullpath
		if [ -f "$undofile" ]; then
			.run "rm ${undofile}"
			echo -e "removed "$cFile$undofile$cNone
		fi
	fi
done
