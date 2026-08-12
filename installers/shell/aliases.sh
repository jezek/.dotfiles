alias sudo='sudo -v; sudo ' # Refresh timeout every time `sudo` is used.
alias l='ls -aF --group-directories-first'
alias la='ls -A'
alias ll='ls -lF --group-directories-first'
alias lla='ls -lFA --group-directories-first'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'


is(){
	type "$1" >/dev/null 2>&1
}

uopen() {
	if is gnome-open; then
		command gnome-open $* & 
		return
	fi
	if is xdg-open; then
		command xdg-open $* & 
		return
	fi
	echo "how???"
	return 1
}
alias o=uopen

cdls() {
  cd $1;ls -CF --group-directories-first $2
}
alias cl=cdls

mkdircd () { mkdir -p "$@" && eval cd "\"\$$#\""; }
alias md=mkdircd

if is git && is less; then
	alias gsba='git show-branch -a --color=always | less -r -X'
fi

# QR code generation
qr () {
	if ! is curl; then
		echo "qr requires curl" >&2
		return 127
	fi
	printf '%s' "$*" | curl --fail --show-error --form '-=<-' https://qrenco.de
}

# Delete to trash.
if is gio; then
	alias rmt='gio trash'
fi

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || test -r ~/.dir_colors && eval "$(dircolors -b ~/.dir_colors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# From https://blog.depau.eu/2021/07/19/btrfs-troubleshooting/
alias cp='cp --reflink=auto'
# "auto" will fallback to standard copying if reflink isn't available
