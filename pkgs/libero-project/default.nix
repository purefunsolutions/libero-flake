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
#     cores = [ {                        # IP cores from Libero's catalog
#       vlnv = "Actel:SgCore:FCCC:2.0.201";
#       name = "FCCC_C0";                # the module the HDL instantiates
#       params = { GL0_IS_USED = true; GL0_OUT_0_FREQ = 200; };
#     } ];
#     testbenches = [ {                  # for the runner's --simulate
#       name = "chip";                   # --testbench chip; the first is
#       hdl = [ ./blinky_tb.v ];         # the default. hdl as above, or
#       top = "blinky_tb";               # Clash's testbench
#       instance = "dut";                # the design's instance in it
#     } ];
#   }
#
# The bundle holds the HDL, the constraints, and Tcl that creates the
# project, configures the IP cores, runs synthesis, place and route and
# timing analysis, and exports the programming files (tcl/build.tcl).
# Building it needs no vendor tools; running it needs Libero and a license.
# With IP cores, Libero also derives their clock constraints (CCC outputs,
# oscillators), so the timing constraints need not repeat them. The same
# Tcl simulates a testbench, with QuestaSim or ModelSim, before synthesis,
# after it, or after place and route with the routed timing.
#
# passthru.runner: `nix run` target that builds the bundle with Libero
# outside the Nix sandbox, where the license server is reachable (see
# runner.sh), or simulates it. Null until a `libero` package is in scope,
# and for designs with IP cores until `libero-megavault` is too. For
# designs with testbenches it brings the simulators in scope,
# `libero-questasim` and `libero-modelsim`.
#
# passthru.tests: a dry run of the Tcl with every Libero command stubbed
# (compared against `liberoCalls` if given), the runner against a stub
# libero, and Yosys synthesis for the families Yosys supports, for designs
# without IP cores.
{
  lib,
  runCommand,
  writeShellApplication,
  writeShellScript,
  coreutils,
  findutils,
  flock,
  gnugrep,
  gnused,
  tcl,
  yosys,
  libero ? null,
  libero-megavault ? null,
  libero-modelsim ? null,
  libero-questasim ? null,
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
  # IP cores: { vlnv, name, params }, params being the core's configuration
  # (strings, integers or booleans) as Libero's create_and_configure_core
  # takes them. They come from libero-megavault, never downloaded.
  cores ? [],
  # Testbenches, the first being the runner's default:
  # { name, hdl, top, instance ? "<top>_0", time ? "-all" }. name for
  # --testbench, hdl as above, top its top module, instance the design's
  # instance name in it (post-layout simulation annotates that with the
  # routed timing), time how long to run ("-all": until the testbench
  # calls $finish). A testbench fails with $error or $fatal, a VHDL
  # assertion of severity error or failure, or a mismatch of Clash's
  # outputVerifier.
  testbenches ? [],
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
  # The same without spaces, for the elements of Tcl lists.
  safeWord = what: value:
    if builtins.match "[A-Za-z0-9_.:+-]+" value != null
    then value
    else throw "mkLiberoProject: unsupported characters in ${what}: '${value}'";

  # Each core as a Tcl list: vlnv, component name, and its KEY:VALUE
  # parameters.
  coreParam = name: key: value:
    safeWord "parameter ${key} of core ${name}" "${key}:${
      if builtins.isBool value
      then lib.boolToString value
      else toString value
    }";
  coresTcl =
    lib.concatMapStringsSep " " (core: "{${
      lib.concatStringsSep " " [
        (safeWord "core vlnv" core.vlnv)
        (safeWord "core name" core.name)
        "{${toString (lib.mapAttrsToList (coreParam core.name) (core.params or {}))}}"
      ]
    }}")
    cores;

  # Interpolated, not passed to toString: that copies a path to the store
  # and makes the bundle depend on it, so remote builders get it too.
  shellPaths = paths: lib.escapeShellArgs (map (path: "${path}") paths);

  testbenchNames = let
    names = map (tb: safeWord "testbench name" tb.name) testbenches;
  in
    if lib.allUnique names
    then names
    else throw "mkLiberoProject: testbench names repeat: ${toString names}";

  params =
    {
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
    }
    // {
      testbenches = toString testbenchNames;
    }
    // lib.listToAttrs (lib.concatMap (tb: [
        (lib.nameValuePair "testbench(${tb.name},top)" (safe "top of testbench ${tb.name}" tb.top))
        (lib.nameValuePair "testbench(${tb.name},instance)"
          (safe "instance of testbench ${tb.name}" (tb.instance or "${top}_0")))
        (lib.nameValuePair "testbench(${tb.name},time)"
          (safe "time of testbench ${tb.name}" (tb.time or "-all")))
      ])
      testbenches);

  # The simulators a runner offers, the default first: for designs with
  # testbenches, those in scope.
  simulators = lib.optionals (testbenches != []) (lib.filter (sim: sim.package != null) [
    {
      name = "questasim";
      package = libero-questasim;
    }
    {
      name = "modelsim";
      package = libero-modelsim;
    }
  ]);

  bundle =
    runCommand "${pname}-libero-project-${version}" {
      passthru = {
        inherit device top mkRunner;
        runner =
          if libero == null || (cores != [] && libero-megavault == null)
          then null
          else
            mkRunner {
              liberoPackage = libero;
              vault =
                if cores == []
                then null
                else libero-megavault.vault;
              inherit simulators;
            };
        tests =
          {
            libero-calls = dryRun;
            runner = runnerTest;
          }
          # Not with IP cores: Libero generates their HDL, Yosys never sees it.
          // lib.optionalAttrs (yosysSynth ? ${device.family} && hdlLanguage == "VERILOG" && cores == []) {
            yosys = synth;
          };
      };
    } ''
      mkdir -p $out/hdl $out/constraints/{io,fp,timing} $out/testbench $out/tcl/family

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
      ${lib.concatMapStrings (tb: ''
          mkdir $out/testbench/${tb.name}
          add_all $out/testbench/${tb.name} ${shellPaths tb.hdl}
        '')
        testbenches}

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
        ${lib.concatMapStrings (name: ''
          echo "set files(stimulus,${name}) {$(list testbench/${name})}"
        '')
        testbenchNames}
        echo ${lib.escapeShellArg "set cores {${coresTcl}}"}
      } >$out/tcl/params.tcl
    '';

  # The Tcl flow with every Libero command replaced by a stub that prints
  # its arguments: the build, then each testbench before synthesis without
  # a VCD, and the first after synthesis with its signals in one and after
  # place and route in the GUI with every signal in one, with the do
  # files.
  dryRun =
    runCommand "${pname}-libero-calls" {
      nativeBuildInputs = [tcl];
    } ''
      mkdir work
      cd work
      export LIBERO_VAULT=/vault
      tclsh ${./tests/libero-stub.tcl} ${bundle}/tcl/build.tcl >calls.log
      ${lib.optionalString (testbenches != []) ''
        export LIBERO_SIMULATOR=/simulator/bin/vsim LIBERO_SIMULATOR_TOOL="QuestaSim ME"
        for run in ${lib.escapeShellArgs (map (name: "presynth LIBERO_TESTBENCH=${name}") testbenchNames
          ++ [
            "postsynth LIBERO_TESTBENCH=${lib.head testbenchNames} LIBERO_SIMULATION_VCD=testbench"
            "postlayout LIBERO_TESTBENCH=${lib.head testbenchNames} LIBERO_SIMULATION_GUI=1 LIBERO_SIMULATION_VCD=all"
          ])}; do
          rm -rf project
          echo "# LIBERO_SIMULATE=$run" >>calls.log
          env LIBERO_SIMULATE=$run tclsh ${./tests/libero-stub.tcl} ${bundle}/tcl/build.tcl >>calls.log
          for do in vcd.do gui.do; do
            if [ -e project/simulation/$do ]; then
              sed "s/^/# $do: /" project/simulation/$do >>calls.log
            fi
          done
        done
      ''}
      sed -e "s|${bundle}|@bundle@|g" -e "s|$(pwd -P)|@work@|g" calls.log >$out
      ${lib.optionalString (liberoCalls != null) ''
        diff -u ${liberoCalls} $out
      ''}
    '';

  # The runner takes the libero package, the IP core vault and the
  # simulators as arguments, so the test can use stubs.
  mkRunner = {
    liberoPackage,
    vault ? null,
    simulators ? [],
  }:
    writeShellApplication {
      name = pname;
      runtimeInputs = [liberoPackage coreutils findutils flock gnugrep];
      runtimeEnv = {
        BUNDLE = bundle;
        NAME = pname;
        PROJECT = params."project(name)";
        EXPORTS = toString exports;
        VAULT =
          if vault == null
          then ""
          else "${vault}";
        TESTBENCHES = lib.concatMapStringsSep "\n" (tb: "${tb.name}|${tb.top}") testbenches;
        LIBERO_FHS =
          if liberoPackage ? fhs
          then "${liberoPackage.fhs}/bin/libero-fhs"
          else "";
        SIMULATORS =
          lib.concatMapStringsSep "\n" (sim: "${sim.name}|${sim.package.bin}/vsim|${sim.package.profileTool}")
          simulators;
      };
      text = builtins.readFile ./runner.sh;
      meta = {
        description = "Build or simulate ${pname} with Libero";
        platforms = liberoPackage.meta.platforms or lib.platforms.all;
      };
    };

  stubLibero = writeShellApplication {
    name = "libero";
    runtimeInputs = [coreutils gnused];
    text = builtins.readFile ./tests/libero-stub.sh;
  };

  # A vault with nothing but its index, read-only like libero-megavault's.
  stubVault = runCommand "${pname}-stub-vault" {} ''
    mkdir -p $out/Components
    echo '<repositoryIndex/>' >$out/index.xml
  '';

  # Simulators whose vsim is a stand-in for the GUI: it records how it was
  # run and writes a clean log.
  stubSimulators = let
    vsim = writeShellScript "vsim" ''
      echo "$(basename "$PWD")|$*" >"$STUB_STATE/gui"
      while [ "$1" != -l ]; do shift; done
      echo '# Errors: 0, Warnings: 0' >"$2"
    '';
    bins = runCommand "${pname}-stub-simulators" {} ''
      mkdir -p $out/questasim $out/modelsim
      ln -s ${vsim} $out/questasim/vsim
      ln -s ${vsim} $out/modelsim/vsim
    '';
  in
    lib.optionals (testbenches != []) [
      {
        name = "questasim";
        package = {
          bin = "${bins}/questasim";
          profileTool = "QuestaSim ME";
        };
      }
      {
        name = "modelsim";
        package = {
          bin = "${bins}/modelsim";
          profileTool = "ModelSim Pro Edition";
        };
      }
    ];

  runnerTest = runCommand "${pname}-runner-test" {} ''
    run=${lib.getExe (mkRunner {
      liberoPackage = stubLibero;
      vault =
        if cores == []
        then null
        else stubVault;
      simulators = stubSimulators;
    })}
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

    expect 2 env STUB_SCENARIO=ok $run --gui -o gui-without-simulate
    ${
      if testbenches == []
      then ''
        expect 2 env STUB_SCENARIO=ok $run --simulate -o no-testbench
      ''
      else let
        tb = lib.head testbenches;
        log = stage: "${tb.top}_${stage}_simulation.log";
      in ''
        # Simulations: the default testbench, stage, simulator and output
        # directory.
        mkdir default && cd default
        expect 0 env STUB_SCENARIO=ok $run --simulate
        cd ..
        sim=default/out/${pname}-${tb.name}-presynth-questasim
        test -f $sim/${log "presynth"}
        test ! -e $sim/${tb.top}.vcd
        grep -qx 'testbench: ${tb.name} (${tb.top})' $sim/manifest.txt
        grep -qx 'simulator: questasim (${(lib.head stubSimulators).package.bin}/vsim)' $sim/manifest.txt
        test "$(cut -d '|' -f 1,2,4- state/simulation)" = \
          '${tb.name}|presynth|QuestaSim ME|batch|no VCD|1702@licenses.example.org'

        # The other testbenches.
        ${lib.concatMapStrings (other: ''
          expect 0 env STUB_SCENARIO=ok $run --simulate --testbench ${other.name} -o ${other.name}
          test -f ${other.name}/${other.top}_presynth_simulation.log
          test "$(cut -d '|' -f 1 state/simulation)" = ${other.name}
        '') (lib.tail testbenches)}
        expect 2 env STUB_SCENARIO=ok $run --simulate --testbench nonesuch -o unknown-testbench
        expect 2 env STUB_SCENARIO=ok $run --testbench ${tb.name} -o testbench-without-simulate

        # VCDs, the other simulator and the GUI.
        expect 0 env STUB_SCENARIO=ok $run --simulate --vcd -o vcd
        test -f vcd/${tb.top}.vcd
        test "$(cut -d '|' -f 6 state/simulation)" = testbench
        expect 2 env -u DISPLAY STUB_SCENARIO=ok $run --simulate --gui -o no-display
        expect 0 env DISPLAY=:1 SALT_LICENSE_SERVER=1717@salt.example.org STUB_SCENARIO=ok \
          $run --simulate=postlayout --simulator modelsim --gui --vcd-all -o gui
        test "$(cut -d '|' -f 1,2,4- state/simulation)" = \
          '${tb.name}|postlayout|ModelSim Pro Edition|gui|all|1717@salt.example.org'
        test "$(cat state/gui)" = 'simulation|-gui -do gui.do -l ${log "postlayout"}'

        # Failing testbenches keep their outputs.
        expect 5 env STUB_SCENARIO=testbench-error $run --simulate=postsynth -o error
        test -f error/${log "postsynth"}
        expect 5 env STUB_SCENARIO=clash-mismatch $run --simulate -o mismatch

        expect 2 env STUB_SCENARIO=ok $run --simulate=gates -o unknown-stage
        expect 2 env STUB_SCENARIO=ok $run --simulate --simulator verilator -o unknown-simulator
      ''
    }
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
