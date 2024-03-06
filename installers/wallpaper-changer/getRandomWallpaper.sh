#!/bin/bash

# Output of this script is a full path to a random image file (.jpg .jpeg .gif .png) from a directory and it's descendants provided in input.
# If there are multiple directories as arguments, the search is done in all of them.
# If there are no directories in input arguments, the script results in error 1
# If no images are found, the script results in error 2.
dirs=()
for dir in "$@"; do
	if [ -d "${dir}" ]; then
		dirs+=("${dir}")
	fi
done

[ 0 -eq ${#dirs[@]} ] && exit 1

images=()
# read images into array. find uses \0 separator, read reads till separator.
while IFS= read -r -d $'\0'
do
	images+=("${REPLY}")
done < <(find "${dirs[@]}" \( -name \*.jpg -or -name \*.jpeg -or -name \*.gif -or -name \*.png -or -name \*.webp \) -print0)

element_count=${#images[*]}
# echo "choosing from ${element_count} images"
[ 0 -eq ${element_count} ] && exit 2

arrayPos=$RANDOM
# get a random number less than length of array
let "arrayPos%=${element_count}"
picToUse=${images[$arrayPos]}
echo $picToUse
