# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# Host CLI for the Microchip Hello FPGA kit's on-board PIC32 programmer:
# programs DirectC .dat files over the kit's USB-serial port, reads the
# core power, controls Flash*Freeze and bridges the FPGA UART.
{
  lib,
  stdenv,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication {
  pname = "hello-fpga-cli";
  version = "0.1.0-unstable-2026-10-03";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "captndo";
    repo = "hello-fpga-cli";
    rev = "ab6304d7c14618c58df932992bf17c6bfbf1a142";
    hash = "sha256-ybYA5Zu3dvqU007O7uDlSz1feKsJv0piTYXi+NbXX/Q=";
  };

  build-system = [python3Packages.hatchling];

  dependencies = with python3Packages; [
    pyserial
    typer
  ];

  nativeCheckInputs = [python3Packages.pytestCheckHook];

  disabledTests =
    [
      # These run `python -I` in a subprocess, which drops the dependencies
      # that Nix provides through PYTHONPATH.
      "test_core_without_typer_and_freeze_controller_import"
      "test_core_runs_without_importing_typer"
      "test_core_without_typer"
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [
      # These expect Linux termios flag values.
      "test_terminal_guidance_and_restoration_before_exit"
      "test_terminal_cbreak_has_immediate_input_and_restores_settings"
      "test_terminal_restores_on_errors_and_interruption"
      "test_terminal_setup_failure_restores_already_changed_settings"
    ];

  pythonImportsCheck = [
    "hello_fpga"
    "hello_fpga_cli"
  ];

  meta = {
    description = "Host CLI for the Microchip Hello FPGA kit's on-board PIC32 programmer";
    homepage = "https://github.com/captndo/hello-fpga-cli";
    # No license: upstream has none yet. Its README lists choosing one
    # among the requirements for a production-ready release.
    mainProgram = "hello-fpga";
    platforms = lib.platforms.unix;
  };
}
