# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Stand-in for `libero` in the runner tests. STUB_SCENARIO selects the
# behaviour: ok; busy-twice (the license seat is busy twice, then ok);
# fail; for simulations also testbench-error and clash-mismatch. It
# exports a file for each of the runner's EXPORTS, or simulates: records
# what in $STUB_STATE/simulation and writes the simulator's log. It counts
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

if [ -n "${LIBERO_SIMULATE:-}" ]; then
  mode="batch"
  if [ -n "${LIBERO_SIMULATION_GUI:-}" ]; then
    mode="gui"
  fi
  # shellcheck disable=SC2153 # LIBERO_SIMULATOR comes from the runner
  echo "$LIBERO_TESTBENCH|$LIBERO_SIMULATE|$LIBERO_SIMULATOR|$LIBERO_SIMULATOR_TOOL|$mode|${LIBERO_SIMULATION_VCD:-no VCD}|$SALT_LICENSE_SERVER" \
    >"$STUB_STATE/simulation"
  testbench=$(sed -n "s/^set testbench($LIBERO_TESTBENCH,top) {\(.*\)}\$/\1/p" "$(dirname "$script")/params.tcl")
  mkdir -p project/simulation
  simulation_log=project/simulation/${testbench}_${LIBERO_SIMULATE}_simulation.log
  case $STUB_SCENARIO in
  testbench-error) echo '# ** Error: LED1 lit too early' >"$simulation_log" ;;
  clash-mismatch) echo '# @1230ns: outputVerifier, expected: 1, actual: 0' >"$simulation_log" ;;
  *) echo '# Errors: 0, Warnings: 0' >"$simulation_log" ;;
  esac
  touch project/simulation/vsim.wlf
  if [ -n "${LIBERO_SIMULATION_VCD:-}" ]; then
    touch "project/simulation/$testbench.vcd"
  fi
  echo "ok" >"$log"
  exit 0
fi

mkdir -p export project/designer/top
for format in $EXPORTS; do
  touch "export/$name.${format,,}"
done
touch project/designer/top/top_report.rpt
echo "ok" >"$log"
