# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# mkLiberoProject: HDL and constraints -> a Libero project bundle.
#
#   mkLiberoProject {
#     pname = "blinky";
#     device = {
#       family = "SmartFusion2";
#       die = "M2S010";
#       package = "256 VF";
#       speed = "-1";
#       dieVoltage = "1.2";
#       partRange = "COM";
#     };
#     top = "blinky";
#     hdl = [ ./blinky.v ];             # files, or directories of HDL files
#     ioConstraints = [ ./blinky.pdc ];
#     timingConstraints = [ ./blinky.sdc ];
#   }
#
# The bundle holds the HDL, the constraints, and Tcl that creates the
# project, runs synthesis, place and route and timing analysis, and exports
# the programming files (tcl/build.tcl). Building it needs no vendor tools;
# running it needs Libero and a license.
#
# passthru.runner: `nix run` target that builds the bundle with Libero
# outside the Nix sandbox, where the license server is reachable (see
# runner.sh). Null until a `libero` package is in scope.
#
# passthru.tests: a dry run of the Tcl with every Libero command stubbed
# (compared against `liberoCalls` if given), the runner against a stub
# libero, and Yosys synthesis for the families Yosys supports.
{
  lib,
  runCommand,
  writeShellApplication,
  coreutils,
  findutils,
  flock,
  gnugrep,
  gnused,
  tcl,
  yosys,
  libero ? null,
}: {
  pname,
  version ? "0",
  device,
  top,
  hdl,
  hdlLanguage ? "VERILOG",
  ioConstraints ? [],
  floorplanConstraints ? [],
  timingConstraints ? [],
  # DAT, STP, JOB (see tcl/family/*.tcl)
  exports ? ["DAT" "STP"],
  programmingComponents ? ["FABRIC"],
  # Expected output of the dry run, for golden tests.
  liberoCalls ? null,
}: let
  familyScripts = {
    SmartFusion2 = "smartfusion2.tcl";
    IGLOO2 = "smartfusion2.tcl";
  };
  # SmartFusion 2 and IGLOO 2 flip-flops have no initial value, designs rely
  # on resets. Generated HDL (Clash) declares one anyway, so drop it.
  yosysSynth = {
    SmartFusion2 = "synth_sf2 -discard-ffinit";
    IGLOO2 = "synth_sf2 -discard-ffinit";
  };

  # Values end up inside Tcl braces in params.tcl. Allowing only these
  # characters keeps that safe without any quoting.
  safe = what: value:
    if builtins.match "[A-Za-z0-9_.:+ -]+" value != null
    then value
    else throw "mkLiberoProject: unsupported characters in ${what}: '${value}'";

  # Interpolated, not passed to toString: that copies a path to the store
  # and makes the bundle depend on it, so remote builders get it too.
  shellPaths = paths: lib.escapeShellArgs (map (path: "${path}") paths);

  params = {
    "project(name)" = safe "pname" (lib.replaceStrings ["-"] ["_"] pname);
    "project(top)" = safe "top" top;
    "project(hdl)" = safe "hdlLanguage" hdlLanguage;
    "project(family_script)" =
      familyScripts.${device.family}
      or (throw "mkLiberoProject: unsupported family ${device.family}");
    "device(family)" = safe "device.family" device.family;
    "device(die)" = safe "device.die" device.die;
    "device(package)" = safe "device.package" device.package;
    "device(speed)" = safe "device.speed" device.speed;
    "device(die_voltage)" = safe "device.dieVoltage" device.dieVoltage;
    "device(part_range)" = safe "device.partRange" device.partRange;
    "export(formats)" = safe "exports" (toString exports);
    "export(components)" = safe "programmingComponents" (toString programmingComponents);
  };

  bundle =
    runCommand "${pname}-libero-project-${version}" {
      passthru = {
        inherit device top mkRunner;
        runner =
          if libero == null
          then null
          else mkRunner {liberoPackage = libero;};
        tests =
          {
            libero-calls = dryRun;
            runner = runnerTest;
          }
          // lib.optionalAttrs (yosysSynth ? ${device.family} && hdlLanguage == "VERILOG") {
            yosys = synth;
          };
      };
    } ''
      mkdir -p $out/hdl $out/constraints/{io,fp,timing} $out/tcl/family

      add() { # directory, file, name
        if [[ ! $3 =~ ^[A-Za-z0-9_.+-]+$ ]]; then
          echo "mkLiberoProject: unsupported file name: $3" >&2
          exit 1
        fi
        if [ -e "$1/$3" ]; then
          echo "mkLiberoProject: duplicate file name: $3" >&2
          exit 1
        fi
        cp "$2" "$1/$3"
      }

      # Plain files keep their name; directories contribute their HDL files.
      add_all() { # directory, sources...
        local dir=$1 src f
        shift
        for src in "$@"; do
          if [ -d "$src" ]; then
            while IFS= read -r -d "" f; do
              add "$dir" "$f" "$(basename "$f")"
            done < <(find "$src" -type f \
              \( -name '*.v' -o -name '*.sv' -o -name '*.vhd' -o -name '*.vhdl' \) \
              -print0 | sort -z)
          else
            add "$dir" "$src" "$(stripHash "$src")"
          fi
        done
      }

      add_all $out/hdl ${shellPaths hdl}
      add_all $out/constraints/io ${shellPaths ioConstraints}
      add_all $out/constraints/fp ${shellPaths floorplanConstraints}
      add_all $out/constraints/timing ${shellPaths timingConstraints}

      if [ -z "$(ls -A $out/hdl)" ]; then
        echo "mkLiberoProject: no HDL files" >&2
        exit 1
      fi

      cp ${./build.tcl} $out/tcl/build.tcl
      cp ${./family}/*.tcl $out/tcl/family/

      list() {
        (cd $out && find "$1" -type f | LC_ALL=C sort | paste -sd " " -)
      }
      {
        echo "# Generated by mkLiberoProject."
        ${lib.concatStrings (lib.mapAttrsToList (name: value: ''
          echo ${lib.escapeShellArg "set ${name} {${value}}"}
        '')
        params)}
        echo "set files(hdl) {$(list hdl)}"
        echo "set files(io_pdc) {$(list constraints/io)}"
        echo "set files(fp_pdc) {$(list constraints/fp)}"
        echo "set files(sdc) {$(list constraints/timing)}"
      } >$out/tcl/params.tcl
    '';

  # The Tcl flow with every Libero command replaced by a stub that prints
  # its arguments.
  dryRun =
    runCommand "${pname}-libero-calls" {
      nativeBuildInputs = [tcl];
    } ''
      mkdir work
      cd work
      tclsh ${./tests/libero-stub.tcl} ${bundle}/tcl/build.tcl >calls.log
      sed -e "s|${bundle}|@bundle@|g" -e "s|$(pwd -P)|@work@|g" calls.log >$out
      ${lib.optionalString (liberoCalls != null) ''
        diff -u ${liberoCalls} $out
      ''}
    '';

  # The runner takes the libero package as an argument, so the test can
  # use a stub.
  mkRunner = {liberoPackage}:
    writeShellApplication {
      name = pname;
      runtimeInputs = [liberoPackage coreutils findutils flock gnugrep];
      runtimeEnv = {
        BUNDLE = bundle;
        NAME = pname;
        PROJECT = params."project(name)";
        EXPORTS = toString exports;
      };
      text = builtins.readFile ./runner.sh;
      meta = {
        description = "Build ${pname} with Libero";
        platforms = liberoPackage.meta.platforms or lib.platforms.all;
      };
    };

  stubLibero = writeShellApplication {
    name = "libero";
    runtimeInputs = [coreutils gnused];
    text = builtins.readFile ./tests/libero-stub.sh;
  };

  runnerTest = runCommand "${pname}-runner-test" {} ''
    run=${lib.getExe (mkRunner {liberoPackage = stubLibero;})}
    export STUB_STATE=$PWD/state XDG_RUNTIME_DIR=$PWD LIBERO_RETRY_DELAY=0
    mkdir state

    expect() { # status, command...
      local want=$1 status=0
      shift
      "$@" || status=$?
      if [ "$status" != "$want" ]; then
        echo "error: expected exit status $want, got $status: $*" >&2
        exit 1
      fi
    }

    expect 3 env STUB_SCENARIO=ok $run -o no-license

    export LM_LICENSE_FILE=1702@licenses.example.org
    expect 0 env STUB_SCENARIO=ok $run -o ok
    test -f ok/${params."project(name)"}.dat
    test -f ok/${params."project(name)"}.stp
    test -f ok/reports/top_report.rpt
    test -f ok/manifest.txt

    expect 2 env STUB_SCENARIO=ok $run -o ok
    expect 0 env STUB_SCENARIO=ok $run -o ok --force

    rm state/calls
    expect 0 env STUB_SCENARIO=busy-twice $run -o busy
    test "$(cat state/calls)" = 3

    expect 1 env STUB_SCENARIO=fail $run -o failed
    test ! -e failed

    touch $out
  '';

  synth =
    runCommand "${pname}-yosys" {
      nativeBuildInputs = [yosys];
    } ''
      mkdir $out
      yosys -q -l $out/synth.log -p ${lib.escapeShellArg "${yosysSynth.${device.family}} -top ${top}"} \
        ${bundle}/hdl/*
    '';
in
  bundle
