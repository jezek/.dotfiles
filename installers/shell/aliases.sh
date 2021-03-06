alias l='ls -aF --group-directories-first'
alias ll='ls -lF --group-directories-first'
alias lla='ls -lFA --group-directories-first'

is(){
	type $1 >/dev/null 2>&1
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

#TODO find this alias a propper place, or check for git command
alias gsba='git show-branch -a'
