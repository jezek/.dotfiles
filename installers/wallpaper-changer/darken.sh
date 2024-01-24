#!/bin/bash

# Check if the correct number of arguments is provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 [threshold (0-100)] [hex color (e.g., #FFCCAA)]"
    exit 1
fi

# Read the threshold and hex color from the arguments
threshold=$1
hex_color=$2

# Validate threshold
if ! [[ $threshold =~ ^[0-9]+$ ]] || [ $threshold -lt 0 ] || [ $threshold -gt 100 ]; then
    echo "Threshold must be a number between 0 and 100."
    exit 1
fi

# Validate hex color
if ! [[ $hex_color =~ ^#?[0-9a-fA-F]{6}$ ]]; then
    echo "Invalid hex color format. Please provide a valid hex color (e.g., #FFCCAA)."
    exit 1
fi

# Remove '#' if present
hex_color="${hex_color/#\#/}"

# Extract Red, Green, Blue values from hex
r=$((16#${hex_color:0:2}))
g=$((16#${hex_color:2:2}))
b=$((16#${hex_color:4:2}))

# Calculate luminance
luminance=$(((r + g + b) / 3))

# Adjust color to match the threshold if luminance is higher than threshold
if [ $luminance -gt $threshold ]; then
    # Calculate the adjustment factor
    adjustment_factor=$((threshold * 3 * 100 / (r + g + b)))

    # Adjust the RGB values
    r=$(( r * adjustment_factor / 100 ))
    g=$(( g * adjustment_factor / 100 ))
    b=$(( b * adjustment_factor / 100 ))

    printf "#%02x%02x%02x\n" $r $g $b
else
    echo "#$hex_color"
fi
