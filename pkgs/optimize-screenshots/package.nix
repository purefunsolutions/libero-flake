# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# optimize-screenshots, for the PNGs in docs/ (see its --help):
# `nix run .#optimize-screenshots -- docs/new.png`. Its build tests it, after
# shellcheck, on images drawn for the purpose; no flake check builds it.
{
  writeShellApplication,
  coreutils,
  imagemagick,
  oxipng,
  pngquant,
}:
writeShellApplication {
  name = "optimize-screenshots";
  runtimeInputs = [coreutils oxipng pngquant];
  text = builtins.readFile ./optimize-screenshots.sh;
  # Flat colours with anti-aliased edges, like a GUI, get a palette and
  # still look the same; noise keeps its colours; a second run changes
  # nothing.
  derivationArgs = {
    nativeBuildInputs = [imagemagick];
    postCheck = ''
      magick -size 320x160 xc:white \
        -fill navy -draw 'circle 80,80 80,20' \
        -fill red -draw 'rectangle 180,40 300,120' \
        -stroke black -draw 'line 0,150 320,10' gui.png
      magick -seed 1 -size 64x64 xc:white -channel RGB +noise Random +channel noise.png
      cp gui.png gui-before.png

      "$target" gui.png noise.png

      colour_type() { od -An -tu1 -j25 -N1 "$1" | tr -d ' '; }
      test "$(colour_type gui.png)" = 3
      test "$(colour_type noise.png)" != 3
      test "$(stat -c %s gui.png)" -lt "$(stat -c %s gui-before.png)"
      psnr=$(magick compare -metric PSNR gui-before.png gui.png null: 2>&1 | cut -d ' ' -f 1 || true)
      echo "PSNR: $psnr dB"
      awk -v p="$psnr" 'BEGIN { exit !(p == "inf" || p + 0 >= 40) }'

      cp gui.png gui-once.png
      "$target" --fast gui.png
      cmp gui.png gui-once.png
    '';
  };
  meta.description = "Shrink PNG screenshots in place";
}
