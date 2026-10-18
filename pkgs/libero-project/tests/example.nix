# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# mkLiberoProject's own test project: its dry run, building and
# simulating, is compared against example.golden. It is never built or
# simulated with Libero, so the pin names are arbitrary and the testbench
# checks nothing.
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
  testbenches = [
    {
      name = "example";
      hdl = [
        (writeText "example_tb.v" ''
          module example_tb;
            reg clk = 0, rst_n = 0;
            wire led;
            example dut (.clk(clk), .rst_n(rst_n), .led(led));
            always #10 clk = ~clk;
            initial #100 rst_n = 1;
          endmodule
        '')
      ];
      top = "example_tb";
      instance = "dut";
      time = "1 ms";
    }
    {
      name = "other";
      hdl = [
        (writeText "other_tb.v" ''
          module other_tb;
            example example_0 (.clk(1'b0), .rst_n(1'b0), .led());
          endmodule
        '')
      ];
      top = "other_tb";
    }
  ];
  exports = ["DAT" "STP" "JOB"];
  cores = [
    {
      vlnv = "Actel:SgCore:FCCC:2.0.201";
      name = "FCCC_C0";
      params = {
        GL0_IS_USED = true;
        GL0_OUT_0_FREQ = 100;
        PLL_IN_FREQ = "50.000";
        PLL_IN_SRC = "OSC_50MHZ";
      };
    }
  ];
  liberoCalls = ./example.golden;
}
