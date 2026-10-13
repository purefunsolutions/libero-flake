# shellcheck shell=bash
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Runs a mkLiberoProject bundle with Libero, outside the Nix sandbox: the
# license server is reachable from here, not from a build. Body of a
# writeShellApplication, which sets BUNDLE, NAME, PROJECT and EXPORTS.

usage() {
  cat <<EOF
usage: $NAME [-o DIR] [--force] [--keep-work] [--retries N]

Builds $NAME with Libero and writes the programming files, reports and
logs to DIR (default: ./out/$NAME).

  -o, --output DIR  output directory
  --force           replace DIR if it exists
  --keep-work       keep the Libero work directory
  --retries N       attempts while the license seat is busy (default: 8)

Environment:
  LM_LICENSE_FILE         license server, e.g. 1702@licenses.example.org
  SNPSLMD_LICENSE_FILE    for Synplify; defaults to LM_LICENSE_FILE
  SYNPLCTYD_LICENSE_FILE  Synplify's older name; defaults to the above
  LIBERO_RETRY_DELAY      first retry delay in seconds (default: 30)
EOF
}

out=./out/$NAME
force=0
keep_work=0
retries=8
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

if [ -z "${LM_LICENSE_FILE:-}" ]; then
  echo "$NAME: LM_LICENSE_FILE is not set. Point it at your license server," >&2
  echo "e.g. LM_LICENSE_FILE=1702@licenses.example.org (the NixOS module" >&2
  echo "programs.libero sets it from programs.libero.licenseServer)." >&2
  exit 3
fi
export LM_LICENSE_FILE
export SNPSLMD_LICENSE_FILE=${SNPSLMD_LICENSE_FILE:-$LM_LICENSE_FILE}
export SYNPLCTYD_LICENSE_FILE=${SYNPLCTYD_LICENSE_FILE:-$SNPSLMD_LICENSE_FILE}

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

# Libero and FlexLM keep settings under HOME; keep them out of the user's.
export HOME=$work/home TMPDIR=$work/tmp
export XDG_CONFIG_HOME=$HOME/.config XDG_CACHE_HOME=$HOME/.cache
export XDG_DATA_HOME=$HOME/.local/share XDG_STATE_HOME=$HOME/.local/state

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
  if [ "$status" = 0 ] && exported; then
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
    if [ "$status" = 0 ]; then
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

staging=$out.tmp.$$
mkdir -p "$staging/reports"
cp export/* "$staging/"
find project -type f \( -name '*.rpt' -o -name '*.srr' -o -name '*_report*' \) \
  -exec cp {} "$staging/reports/" \;
cp libero.log stdout.log "$staging/"
cat >"$staging/manifest.txt" <<EOF
project: $PROJECT
bundle: $BUNDLE
libero: $(command -v libero)
date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
attempts: $attempt
EOF
if [ -e "$out" ]; then
  rm -rf "$out"
fi
mkdir -p "$(dirname "$out")"
mv "$staging" "$out"
echo "$NAME: done, outputs in $out" >&2
