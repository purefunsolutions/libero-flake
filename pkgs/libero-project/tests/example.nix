# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# mkLiberoProject's own test project: its dry run is compared against
# example.golden, and Yosys synthesizes it. It is never built with Libero,
# so the pin names are arbitrary.
{
  mkLiberoProject,
  writeText,
}:
mkLiberoProject {
  pname = "libero-project-example";
  device = {
    family = "SmartFusion2";
    die = "M2S010";
    package = "256 VF";
    speed = "-1";
    dieVoltage = "1.2";
    partRange = "COM";
  };
  top = "example";
  hdl = [
    (writeText "example.v" ''
      module example (input clk, input rst_n, output reg led);
        reg [23:0] count;
        always @(posedge clk or negedge rst_n)
          if (!rst_n) begin
            count <= 0;
            led <= 0;
          end else begin
            count <= count + 1;
            if (&count)
              led <= ~led;
          end
      endmodule
    '')
  ];
  ioConstraints = [
    (writeText "example.pdc" ''
      set_io clk -pinname A1 -fixed yes -DIRECTION INPUT
      set_io rst_n -pinname A2 -fixed yes -DIRECTION INPUT
      set_io led -pinname A3 -fixed yes -DIRECTION OUTPUT
    '')
  ];
  timingConstraints = [
    (writeText "example.sdc" ''
      create_clock -name clk -period 20 [get_ports clk]
    '')
  ];
  exports = ["DAT" "STP" "JOB"];
  liberoCalls = ./example.golden;
}
