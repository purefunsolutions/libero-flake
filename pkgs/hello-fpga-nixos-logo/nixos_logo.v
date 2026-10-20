// SPDX-FileCopyrightText: 2026 Mika Tammi
// SPDX-License-Identifier: MIT
//
// Top level of the NixOS logo: the SmartFusion 2's on-chip 50 MHz RC
// oscillator clocks nixos_logo_core, the Clash design, which draws the
// NixOS rainbow snowflake on the kit's LCD. SYSRESET holds it in reset from
// power-up until the device is ready, and so does SW1 while pressed.

// Microchip primitives from the SmartFusion 2 macro library, declared as
// black boxes for synthesis only: simulators use the library's models of
// them, which these empty modules would hide. Synplify and Yosys know
// CLKINT and SYSRESET themselves.
`ifdef SYNTHESIS
(* blackbox *)
module RCOSC_25_50MHZ (
    CLKOUT
)  /* synthesis syn_black_box */;
  output CLKOUT;
endmodule

(* blackbox *)
module RCOSC_25_50MHZ_FAB (
    A,
    CLKOUT
)  /* synthesis syn_black_box */;
  input A;
  output CLKOUT;
endmodule
`endif

module nixos_logo (
    input DEVRST_N,
    input SW1,
    output LCD_RST,
    output LCD_CS,
    output LCD_RS,
    output LCD_WR,
    output LCD_RD,
    output [7:0] LCD_D,
    output LED1,
    output LED2,
    output LED3
);
  wire osc, osc_fab, clk, por_n;

  // The oscillator, its fabric interface and a global clock buffer.
  RCOSC_25_50MHZ rcosc (.CLKOUT(osc));
  RCOSC_25_50MHZ_FAB rcosc_fab (
      .A(osc),
      .CLKOUT(osc_fab)
  );
  CLKINT clkint (
      .A(osc_fab),
      .Y(clk)
  );

  // Low from power-up, or from DEVRST_N, until the device is ready: the
  // fabric's flip-flops have no power-up value of their own.
  SYSRESET sysreset (
      .DEVRST_N(DEVRST_N),
      .POWER_ON_RESET_N(por_n)
  );

  nixos_logo_core core (
      .CLK(clk),
      .RESET_N(SW1 & por_n),
      .LCD_RST(LCD_RST),
      .LCD_CS(LCD_CS),
      .LCD_RS(LCD_RS),
      .LCD_WR(LCD_WR),
      .LCD_RD(LCD_RD),
      .LCD_D(LCD_D),
      .LED1(LED1),
      .LED2(LED2),
      .LED3(LED3)
  );
endmodule
