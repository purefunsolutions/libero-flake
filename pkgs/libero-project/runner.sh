# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Runs a mkLiberoProject bundle with Libero, outside the Nix sandbox: the
# license server is reachable from here, not from a build. Body of a
# writeShellApplication, which sets BUNDLE, NAME, PROJECT, EXPORTS, VAULT
# (the IP cores, if the design uses any), TESTBENCHES (name|top module,
# one per line), SIMULATORS (name|vsim|Libero tool, one per line) and
# LIBERO_FHS (what runs a program in Libero's FHS environment).

usage() {
  cat <<EOF
usage: $NAME [-o DIR] [--force] [--keep-work] [--retries N]
       $NAME --simulate[=STAGE] [--testbench NAME] [--simulator NAME] [--gui]
             [--vcd | --vcd-all] [...]

Builds $NAME with Libero and writes the programming files, reports and
logs to DIR (default: ./out/$NAME).

With --simulate, runs a testbench instead, at STAGE: presynth (the HDL,
the default), postsynth (the synthesized netlist) or postlayout (the
routed netlist with its timing). The simulator's log, any VCD and
Libero's logs go to DIR, also when the testbench fails; by default to
./out/$NAME-TESTBENCH-STAGE-SIMULATOR.

  -o, --output DIR    output directory
  --force             replace DIR if it exists
  --keep-work         keep the Libero work directory
  --retries N         attempts while the license seat is busy (default: 8)
  --simulate[=STAGE]  run a testbench instead of building
  --testbench NAME    one of: $(names "$TESTBENCHES")
  --simulator NAME    one of: $(names "$SIMULATORS")
  --gui               the simulator's GUI instead of batch mode; needs a
                      display (DISPLAY)
  --vcd               a VCD of the testbench's own signals
  --vcd-all           a VCD of every signal of the design
                      Either grows with the simulated time: gigabytes for
                      a second of a clock in the testbench

Exit status: 0 done; 1 Libero failed; 2 usage; 3 no license server set;
4 license error; 5 the testbench failed.

Environment:
  LM_LICENSE_FILE         license server, e.g. 1702@licenses.example.org
  SNPSLMD_LICENSE_FILE    for Synplify; defaults to LM_LICENSE_FILE
  SYNPLCTYD_LICENSE_FILE  Synplify's older name; defaults to the above
  SALT_LICENSE_SERVER     for the simulators; defaults to LM_LICENSE_FILE
  LIBERO_RETRY_DELAY      first retry delay in seconds (default: 30)
EOF
}

# The choices in a list of "name|..." lines; the first is the default.
names() { # list
  local entry rest entries=()
  while IFS='|' read -r entry rest; do
    if [ -n "$entry" ]; then
      entries+=("$entry")
    fi
  done <<<"$1"
  if [ ${#entries[@]} = 0 ]; then
    echo "none"
  else
    echo "${entries[*]} (default: ${entries[0]})"
  fi
}

# The line of a list for a choice, or for the default if none is given.
pick() { # list, name
  local line
  while IFS= read -r line; do
    if [ -n "$line" ] && { [ -z "$2" ] || [ "${line%%|*}" = "$2" ]; }; then
      echo "$line"
      return
    fi
  done <<<"$1"
  return 1
}

out=
force=0
keep_work=0
retries=8
stage=
testbench=
simulator=
gui=0
vcd=
while [ $# -gt 0 ]; do
  case $1 in
  -o | --output)
    out=${2:?}
    shift
    ;;
  --force) force=1 ;;
  --keep-work) keep_work=1 ;;
  --retries)
    retries=${2:?}
    shift
    ;;
  --simulate) stage=presynth ;;
  --simulate=*) stage=${1#--simulate=} ;;
  --testbench)
    testbench=${2:?}
    shift
    ;;
  --simulator)
    simulator=${2:?}
    shift
    ;;
  --gui) gui=1 ;;
  --vcd) vcd=testbench ;;
  --vcd-all) vcd=all ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
  esac
  shift
done

if [ -n "$stage" ]; then
  case $stage in
  presynth | postsynth | postlayout) ;;
  *)
    echo "$NAME: unknown simulation stage: $stage (presynth, postsynth or postlayout)" >&2
    exit 2
    ;;
  esac
  if [ -z "$TESTBENCHES" ]; then
    echo "$NAME: the design has no testbench" >&2
    exit 2
  fi
  if ! chosen=$(pick "$TESTBENCHES" "$testbench"); then
    echo "$NAME: unknown testbench: $testbench; have: $(names "$TESTBENCHES")" >&2
    exit 2
  fi
  IFS='|' read -r testbench testbench_top <<<"$chosen"
  if ! chosen=$(pick "$SIMULATORS" "$simulator"); then
    echo "$NAME: unknown simulator: ${simulator:-none}; have: $(names "$SIMULATORS")" >&2
    exit 2
  fi
  IFS='|' read -r simulator vsim simulator_tool <<<"$chosen"
  if [ "$gui" = 1 ] && [ -z "${DISPLAY:-}" ]; then
    echo "$NAME: --gui needs a display, and DISPLAY is not set" >&2
    exit 2
  fi
  out=${out:-./out/$NAME-$testbench-$stage-$simulator}
elif [ -n "$testbench" ] || [ -n "$simulator" ] || [ "$gui" = 1 ] || [ -n "$vcd" ]; then
  echo "$NAME: --testbench, --simulator, --gui, --vcd and --vcd-all go with --simulate" >&2
  exit 2
fi
out=${out:-./out/$NAME}

if [ -z "${LM_LICENSE_FILE:-}" ]; then
  echo "$NAME: LM_LICENSE_FILE is not set. Point it at your license server," >&2
  echo "e.g. LM_LICENSE_FILE=1702@licenses.example.org (the NixOS module" >&2
  echo "programs.libero sets it from programs.libero.licenseServer)." >&2
  exit 3
fi
export LM_LICENSE_FILE
export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-$LM_LICENSE_FILE}
export SYNPLCTYD_LICENSE_FILE=${SYNPLCTYD_LICENSE_FILE:-$SNPSLMD_LICENSE_FILE}
# QuestaSim and ModelSim read no other variable.
export SALT_LICENSE_SERVER=${SALT_LICENSE_SERVER:-$LM_LICENSE_FILE}

if [ -e "$out" ] && [ "$force" = 0 ]; then
  echo "$NAME: $out exists; use --force to replace it" >&2
  exit 2
fi
case $out in
/*) ;;
*) out=$PWD/$out ;;
esac

# One Libero at a time on this host: the free license has a single seat.
lock=${XDG_RUNTIME_DIR:-/tmp}/libero-flake.lock
work=$(mktemp -d "${TMPDIR:-/tmp}/$NAME.XXXXXX")
cleanup() {
  if [ "$keep_work" = 1 ]; then
    echo "$NAME: work directory kept: $work" >&2
  else
    rm -rf "$work"
  fi
}
trap cleanup EXIT

cp -R "$BUNDLE" "$work/bundle"
chmod -R u+w "$work/bundle"
mkdir "$work/run" "$work/home" "$work/tmp"
cd "$work/run" || exit

# The simulator's GUI finds the X server's cookie through HOME, which
# changes next.
if [ "$gui" = 1 ]; then
  export XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
fi

# Libero and FlexLM keep settings under HOME; keep them out of the user's.
export HOME=$work/home TMPDIR=$work/tmp
export XDG_CONFIG_HOME=$HOME/.config XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share XDG_STATE_HOME=$HOME/.local/state

# IP cores: Libero unpacks parts of a core into its vault the first time a
# design uses it, and the vault in the Nix store is read-only. A tree of
# real directories with symlinks to the store's files is writable, takes a
# second and no space.
if [ -n "${VAULT:-}" ]; then
  cp -rs "$VAULT" "$work/vault"
  chmod -R u+w "$work/vault"
  export LIBERO_VAULT=$work/vault
fi

# What build.tcl simulates, and with which simulator.
if [ -n "$stage" ]; then
  export LIBERO_SIMULATE=$stage LIBERO_TESTBENCH=$testbench
  export LIBERO_SIMULATOR=$vsim LIBERO_SIMULATOR_TOOL=$simulator_tool
  if [ "$gui" = 1 ]; then
    export LIBERO_SIMULATION_GUI=1
  fi
  if [ -n "$vcd" ]; then
    export LIBERO_SIMULATION_VCD=$vcd
  fi
fi

exec 9>"$lock"
if ! flock -n 9; then
  echo "$NAME: waiting for another Libero run on this host ($lock)" >&2
  flock 9
fi

exported() {
  local format files
  for format in $EXPORTS; do
    files=(export/*."${format,,}")
    [ -e "${files[0]}" ] || return 1
  done
}

# The simulator's log: Libero names it after the testbench and the stage.
simulation_log() {
  local log=project/simulation/${testbench_top}_${stage}_simulation.log
  [ -e "$log" ] && echo "$log"
}

log_matches() {
  grep -qE "$1" libero.log stdout.log 2>/dev/null
}

attempt=1
delay=${LIBERO_RETRY_DELAY:-30}
while :; do
  rm -rf project export libero.log stdout.log
  echo "$NAME: running Libero (attempt $attempt)" >&2
  status=0
  libero "SCRIPT:$work/bundle/tcl/build.tcl" "LOGFILE:$work/run/libero.log" \
    >stdout.log 2>&1 || status=$?
  # A simulation that ran is judged by its log below, whatever Libero
  # thinks of it.
  if [ -n "$stage" ]; then
    simulation_log >/dev/null && break
  elif [ "$status" = 0 ] && exported; then
    break
  fi

  # FlexLM error codes: -4 all seats in use; -15, -96, -97 server or vendor
  # daemon unreachable. Anything else is not worth retrying.
  if log_matches 'error: ?-4,|Licensed number of users already reached'; then
    reason="the license seat is busy"
  elif log_matches 'error: ?-(15|96|97),|Cannot connect to license server'; then
    reason="the license server is unreachable"
    [ "$retries" -gt 2 ] && retries=2
  elif log_matches 'FlexNet Licensing error|License checkout failed'; then
    echo "$NAME: license error:" >&2
    grep -hE 'FlexNet Licensing error|License checkout failed' libero.log stdout.log >&2 || true
    keep_work=1
    exit 4
  else
    if [ -n "$stage" ]; then
      echo "$NAME: the simulator did not run (its license comes from SALT_LICENSE_SERVER); last lines:" >&2
    elif [ "$status" = 0 ]; then
      echo "$NAME: Libero did not export all of: $EXPORTS; last lines:" >&2
    else
      echo "$NAME: Libero failed (exit status $status); last lines:" >&2
    fi
    tail -n 30 libero.log stdout.log >&2 2>/dev/null || true
    keep_work=1
    exit 1
  fi
  if [ "$attempt" -ge "$retries" ]; then
    echo "$NAME: giving up after $attempt attempts: $reason" >&2
    exit 4
  fi
  echo "$NAME: $reason, retrying in ${delay}s" >&2
  sleep "$delay"
  delay=$((delay * 2 > 600 ? 600 : delay * 2))
  attempt=$((attempt + 1))
done

# The GUI: Libero prepared the simulation (build.tcl), and gui.do runs it in
# the simulator's GUI, in Libero's environment. Its log replaces Libero's.
if [ "$gui" = 1 ]; then
  fhs=()
  if [ -n "${LIBERO_FHS:-}" ]; then
    fhs=("$LIBERO_FHS")
  fi
  echo "$NAME: running the testbench in $simulator's GUI" >&2
  if ! (cd project/simulation &&
    "${fhs[@]}" "$vsim" -gui -do gui.do -l "${testbench_top}_${stage}_simulation.log"); then
    echo "$NAME: the simulator's GUI failed" >&2
    keep_work=1
    exit 1
  fi
fi

staging=$out.tmp.$$
mkdir -p "$staging"
if [ -n "$stage" ]; then
  find project/simulation -maxdepth 1 -type f \
    \( -name '*.log' -o -name '*.vcd' -o -name '*.wlf' -o -name '*.do' \) \
    -exec cp {} "$staging/" \;
else
  mkdir "$staging/reports"
  cp export/* "$staging/"
  find project -type f \( -name '*.rpt' -o -name '*.srr' -o -name '*_report*' \) \
    -exec cp {} "$staging/reports/" \;
fi
# Libero writes its log on the way out; a crash leaves none.
for f in libero.log stdout.log; do
  if [ -e "$f" ]; then
    cp "$f" "$staging/"
  fi
done
{
  echo "project: $PROJECT"
  echo "bundle: $BUNDLE"
  echo "libero: $(command -v libero)"
  if [ -n "$stage" ]; then
    echo "testbench: $testbench ($testbench_top)"
    echo "simulation: $stage"
    echo "simulator: $simulator ($vsim)"
  fi
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "attempts: $attempt"
} >"$staging/manifest.txt"
if [ -e "$out" ]; then
  rm -rf "$out"
fi
mkdir -p "$(dirname "$out")"
mv "$staging" "$out"

# The simulator counts $error, $fatal and VHDL assertions; Clash's Verilog
# testbenches report a mismatch with $display, and stop.
if [ -n "$stage" ]; then
  log=$out/$(basename "$(simulation_log)")
  if grep -qE '^# \*\* (Error|Fatal)|^# @[0-9]+ns: .*, expected: .*, actual: ' "$log"; then
    echo "$NAME: the testbench failed:" >&2
    grep -hE '^# \*\* (Error|Fatal)|^# @[0-9]+ns: .*, expected: .*, actual: ' "$log" | head -n 20 >&2
    echo "$NAME: outputs in $out" >&2
    exit 5
  fi
fi
echo "$NAME: done, outputs in $out" >&2
