#! /bin/bash

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 IMAGE DOMINANT_COLOR" >&2
	exit 1
fi

image=$1
dominantColor=$2

if [ ! -f "$image" ]; then
	echo "Image does not exist: $image" >&2
	exit 1
fi

if [[ ! $dominantColor =~ ^#[[:xdigit:]]{6}$ ]]; then
	echo "Invalid dominant color: $dominantColor" >&2
	exit 1
fi

accentRange=$(gsettings range org.gnome.desktop.interface accent-color 2>/dev/null) || exit 2

colorLab() {
	convert "xc:$1" -colorspace Lab \
		-format '%[fx:100*r] %[fx:255*(g-0.5)] %[fx:255*(b-0.5)]\n' info: \
		2>/dev/null
}

read -r dominantL dominantA dominantB < <(colorLab "$dominantColor") || exit 2
dominantChroma=$(awk -v a="$dominantA" -v b="$dominantB" \
	'BEGIN { print sqrt(a * a + b * b) }')
accentSource=$dominantColor

# A single dominant color is often nearly grey even when an image contains a
# significant vivid area. In that case, prefer a color which is both common
# and vivid, while ignoring small colorful details.
if ! awk -v chroma="$dominantChroma" 'BEGIN { exit !(chroma >= 15) }'; then
	histogram=$(convert "$image" -auto-orient -thumbnail '50x50>' -alpha off \
		-colors 16 -depth 8 -format %c histogram:info:- 2>/dev/null | \
		sed -n 's/^[[:space:]]*\([0-9][0-9]*\):.*#\([[:xdigit:]]\{6\}\).*/\1 #\2/p')
	totalPixels=$(printf '%s\n' "$histogram" | awk '{ total += $1 } END { print total + 0 }')
	bestScore=0
	bestColor=

	while read -r pixels color; do
		[ -n "$pixels" ] && [ -n "$color" ] || continue
		if ! awk -v pixels="$pixels" -v total="$totalPixels" \
			'BEGIN { exit !(total > 0 && pixels * 100 / total >= 5) }'; then
			continue
		fi

		read -r colorL colorA colorB < <(colorLab "$color") || continue
		colorChroma=$(awk -v a="$colorA" -v b="$colorB" \
			'BEGIN { print sqrt(a * a + b * b) }')
		score=$(awk -v pixels="$pixels" -v chroma="$colorChroma" \
			'BEGIN { if (chroma >= 15) print pixels * chroma; else print 0 }')

		if awk -v score="$score" -v best="$bestScore" 'BEGIN { exit !(score > best) }'; then
			bestScore=$score
			bestColor=$color
		fi
	done <<< "$histogram"

	[ -z "$bestColor" ] || accentSource=$bestColor
fi

read -r sourceL sourceA sourceB < <(colorLab "$accentSource") || exit 2
bestDistance=
bestAccent=

# Standard GNOME accent colors. Distribution-specific additions are
# intentionally ignored even if the local schema advertises them.
while read -r accent referenceColor; do
	case $accentRange in
		*"'$accent'"*) ;;
		*) continue ;;
	esac

	read -r referenceL referenceA referenceB < <(colorLab "$referenceColor") || continue
	distance=$(awk \
		-v l1="$sourceL" -v a1="$sourceA" -v b1="$sourceB" \
		-v l2="$referenceL" -v a2="$referenceA" -v b2="$referenceB" \
		'BEGIN {
			dl = l1 - l2
			da = a1 - a2
			db = b1 - b2
			print dl * dl + da * da + db * db
		}')

	if [ -z "$bestDistance" ] || \
		awk -v distance="$distance" -v best="$bestDistance" \
			'BEGIN { exit !(distance < best) }'; then
		bestDistance=$distance
		bestAccent=$accent
	fi
done <<'EOF'
blue #3584e4
teal #2190a4
green #3a944a
yellow #c88800
orange #ed5b00
red #e62d42
pink #d56199
purple #9141ac
slate #6f8396
EOF

[ -n "$bestAccent" ] || exit 2
printf '%s\n' "$bestAccent"
