#!/usr/bin/env sh
set -e

# Input
path="$4"
out="$5"

# Run
exec kitty --class=file_chooser -e yazi --chooser-file="$out" "$path"
