# Go compiler and user-installed commands.
export GOPATH="$HOME/.go"

for goBinDirectory in "$GOPATH/bin" /usr/local/go/bin "$HOME/.local/share/go/bin"; do
	if [ -d "$goBinDirectory" ]; then
		case ":$PATH:" in
			*:"$goBinDirectory":*) ;;
			*) PATH="$goBinDirectory:$PATH" ;;
		esac
	fi
done
unset goBinDirectory
export PATH
