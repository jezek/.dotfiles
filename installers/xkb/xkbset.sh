#! /bin/bash
# try to set sticky keys, more times, log results
xkbset a sticky -twokey -latchlock
sleep 1
xkbset exp =sticky
xkbset a sticky -twokey -latchlock
#dconf write /org/mate/desktop/accessibility/keyboard/enable false
xkbset q | grep -A 2 "Sticky-Keys " > $HOME/.dotfiles/installers/xkb/xkbsettings
dconf read /org/mate/desktop/accessibility/keyboard/enable >> $HOME/.dotfiles/installers/xkb/xkbsettings


