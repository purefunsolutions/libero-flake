# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Stand-in for `libero` in the runner tests. STUB_SCENARIO selects the
# behaviour: ok; busy-twice (the license seat is busy twice, then ok);
# fail. It exports a file for each of the runner's EXPORTS, and counts
# its calls in $STUB_STATE/calls.

script=
log=
for arg; do
  case $arg in
  SCRIPT:*) script=${arg#SCRIPT:} ;;
  LOGFILE:*) log=${arg#LOGFILE:} ;;
  esac
done

# Designs with IP cores: Libero writes into the vault, so it must be a
# writable copy of the read-only one.
if [ -n "${LIBERO_VAULT:-}" ]; then
  test -f "$LIBERO_VAULT/index.xml"
  touch "$LIBERO_VAULT/Components/unpacked"
fi

calls=$(($(cat "$STUB_STATE/calls" 2>/dev/null || echo 0) + 1))
echo "$calls" >"$STUB_STATE/calls"
name=$(sed -n 's/^set project(name) {\(.*\)}$/\1/p' "$(dirname "$script")/params.tcl")

case $STUB_SCENARIO in
busy-twice)
  if [ "$calls" -le 2 ]; then
    echo 'FlexNet Licensing error:-4,132.  System Error: 0 ""' >"$log"
    exit 1
  fi
  ;;
fail)
  echo "Error: synthesis failed" >"$log"
  exit 1
  ;;
esac

mkdir -p export project/designer/top
for format in $EXPORTS; do
  touch "export/$name.${format,,}"
done
touch project/designer/top/top_report.rpt
echo "ok" >"$log"
