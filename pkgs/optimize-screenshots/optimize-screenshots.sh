# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Shrinks the docs' screenshots in place. Body of a writeShellApplication
# (package.nix).

usage() {
  cat <<EOF
usage: optimize-screenshots [--fast] FILE.png...

Shrinks PNG screenshots in place, all at once. Each is quantized to 256
colours with pngquant, without dithering, which keeps text crisp, unless
it has a palette already: quantizing again would only lose more. pngquant
leaves the colours alone if 256 would show (quality below 95; GUI
screenshots reach 98 or 99). Then oxipng recompresses the image with all
its filters and Zopfli, about 15 s for a 1920x1080 screenshot. A file is
only replaced by a smaller one.

  --fast  oxipng without Zopfli: about a second, files about 5 % bigger
EOF
}

fast=0
files=()
for arg; do
  case $arg in
  --fast) fast=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    usage >&2
    exit 2
    ;;
  *) files+=("$arg") ;;
  esac
done
if [ ${#files[@]} = 0 ]; then
  usage >&2
  exit 2
fi

# More Zopfli iterations than its 15 hardly pay: 255 took 30 times as
# long for 0.2 % less.
zopfli=(-Z)
if [ "$fast" = 1 ]; then
  zopfli=()
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

optimize() { # file, scratch file
  local file=$1 scratch=$2 status=0 before after
  before=$(stat -c %s "$file")
  cp "$file" "$scratch"
  # Byte 25 of a PNG is its colour type; 3 is a palette.
  if [ "$(od -An -tu1 -j25 -N1 "$file" | tr -d ' ')" != 3 ]; then
    pngquant --speed 1 --strip --nofs --quality 95-100 --force \
      --output "$scratch" 256 "$file" || status=$?
    case $status in
    0) ;;
    99) echo "$file: keeps its colours, 256 would show" ;;
    *) return "$status" ;;
    esac
  fi
  oxipng -q -o max --strip safe "${zopfli[@]}" "$scratch"
  after=$(stat -c %s "$scratch")
  if [ "$after" -lt "$before" ]; then
    mv "$scratch" "$file"
    echo "$file: $before -> $after bytes"
  else
    echo "$file: left alone, nothing smaller than its $before bytes"
  fi
}

pids=()
for i in "${!files[@]}"; do
  optimize "${files[$i]}" "$work/$i.png" &
  pids+=("$!")
done
failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || failed=1
done
exit "$failed"
