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
chromaticChromaThreshold=5
dominantChromaThreshold=15
detailChromaThreshold=15

colorLab() {
	convert "xc:$1" -colorspace Lab \
		-format '%[fx:100*r] %[fx:255*(g-0.5)] %[fx:255*(b-0.5)]\n' info: \
		2>/dev/null
}

availableAccents=()
declare -A accentL accentA accentB accentHue

# Standard GNOME accent colors. Distribution-specific additions are
# intentionally ignored even if the local schema advertises them.
while read -r accent referenceColor; do
	case $accentRange in
		*"'$accent'"*) ;;
		*) continue ;;
	esac

	read -r accentL[$accent] accentA[$accent] accentB[$accent] \
		< <(colorLab "$referenceColor") || continue
	accentHue[$accent]=$(awk \
		-v a="${accentA[$accent]}" -v b="${accentB[$accent]}" \
		'BEGIN {
			hue = atan2(b, a) * 180 / atan2(0, -1)
			if (hue < 0) hue += 360
			print hue
		}')
	availableAccents+=("$accent")
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

[ "${#availableAccents[@]}" -gt 0 ] || exit 2

closestAccent() {
	local sourceL=$1 sourceA=$2 sourceB=$3
	local sourceChroma sourceHue chromatic=0 accent score bestScore bestAccent

	sourceChroma=$(awk -v a="$sourceA" -v b="$sourceB" \
		'BEGIN { print sqrt(a * a + b * b) }')

	# Slate represents an achromatic wallpaper, rather than a dark version of a
	# chromatic accent. Prefer it directly for grey sources when it is available.
	if awk -v chroma="$sourceChroma" -v threshold="$chromaticChromaThreshold" \
		'BEGIN { exit !(chroma >= threshold) }'; then
		chromatic=1
	else
		for accent in "${availableAccents[@]}"; do
			if [ "$accent" = slate ]; then
				printf '%s\n' "$accent"
				return 0
		fi
	done
	fi

	if [ "$chromatic" = 1 ]; then
		sourceHue=$(awk -v a="$sourceA" -v b="$sourceB" \
			'BEGIN {
				hue = atan2(b, a) * 180 / atan2(0, -1)
				if (hue < 0) hue += 360
				print hue
			}')
	fi

	for accent in "${availableAccents[@]}"; do
		if [ "$chromatic" = 1 ]; then
			# Accent colors represent hue families. Comparing only their hue keeps
			# a dark, weak red from appearing closer to a less saturated teal.
			[ "$accent" = slate ] && continue
			score=$(awk -v source="$sourceHue" -v accent="${accentHue[$accent]}" \
				'BEGIN {
					difference = source - accent
					if (difference < 0) difference = -difference
					if (difference > 180) difference = 360 - difference
					print -(difference * difference)
				}')
		else
			score=$(awk \
				-v l1="$sourceL" -v a1="$sourceA" -v b1="$sourceB" \
				-v l2="${accentL[$accent]}" \
				-v a2="${accentA[$accent]}" \
				-v b2="${accentB[$accent]}" \
				'BEGIN {
					dl = l1 - l2
					da = a1 - a2
					db = b1 - b2
					print -(dl * dl + da * da + db * db)
				}')
		fi

		if [ -z "$bestScore" ] || \
			awk -v score="$score" -v best="$bestScore" \
				'BEGIN { exit !(score > best) }'; then
			bestScore=$score
			bestAccent=$accent
		fi
	done

	[ -n "$bestAccent" ] || return 1
	printf '%s\n' "$bestAccent"
}

read -r dominantL dominantA dominantB < <(colorLab "$dominantColor") || exit 2
dominantChroma=$(awk -v a="$dominantA" -v b="$dominantB" \
	'BEGIN { print sqrt(a * a + b * b) }')
accentSource=$dominantColor

# A single dominant color is often nearly grey even when an image contains a
# vivid detail. Inspect the thumbnail pixels directly so small accent colors
# are not lost through palette quantization. Group their chroma by hue family,
# allowing even a very small but vivid detail to supply the accent.
if ! awk -v chroma="$dominantChroma" -v threshold="$dominantChromaThreshold" \
	'BEGIN { exit !(chroma >= threshold) }'; then
	chromaticAccentNames=
	chromaticAccentHues=
	for accent in "${availableAccents[@]}"; do
		[ "$accent" = slate ] && continue
		chromaticAccentNames+="${chromaticAccentNames:+ }$accent"
		chromaticAccentHues+="${chromaticAccentHues:+ }${accentHue[$accent]}"
	done

	bestAccent=$(
		convert "$image" -auto-orient -thumbnail '100x100>' -alpha off \
			-colorspace Lab -depth 8 txt:- 2>/dev/null | \
		awk -v names="$chromaticAccentNames" -v hues="$chromaticAccentHues" \
			-v threshold="$detailChromaThreshold" '
			BEGIN {
				accentCount = split(names, accentName, " ")
				split(hues, accentHue, " ")
				pi = atan2(0, -1)
			}
			/^[[:digit:]]+,[[:digit:]]+:/ {
				pixel = $0
				sub(/^[^(]*\(/, "", pixel)
				sub(/\).*/, "", pixel)
				split(pixel, channel, ",")
				a = channel[2] - 127.5
				b = channel[3] - 127.5
				chroma = sqrt(a * a + b * b)
				if (chroma < threshold) next

				hue = atan2(b, a) * 180 / pi
				if (hue < 0) hue += 360
				bestDistance = 181
				bestAccent = 0
				for (i = 1; i <= accentCount; i++) {
					difference = hue - accentHue[i]
					if (difference < 0) difference = -difference
					if (difference > 180) difference = 360 - difference
					if (difference < bestDistance) {
						bestDistance = difference
						bestAccent = i
					}
				}

				accentScore[bestAccent] += chroma - threshold
			}
			END {
				bestAccent = 0
				bestScore = -1
				for (i = 1; i <= accentCount; i++) {
					if (accentScore[i] > bestScore) {
						bestScore = accentScore[i]
						bestAccent = i
					}
				}
				if (bestAccent) print accentName[bestAccent]
			}'
	)

	if [ -n "$bestAccent" ]; then
		printf '%s\n' "$bestAccent"
		exit 0
	fi
fi

read -r sourceL sourceA sourceB < <(colorLab "$accentSource") || exit 2
closestAccent "$sourceL" "$sourceA" "$sourceB"
