// SPDX-FileCopyrightText: 2026 Mika Tammi
// SPDX-License-Identifier: MIT
//
// Top level of the 400 MHz blinky: the SmartFusion 2's on-chip 50 MHz RC
// oscillator feeds FCCC_C0, a clock conditioning circuit whose PLL makes
// 400 MHz on GL0 for blinky_pll_core, the Clash design. Libero generates
// FCCC_C0 from its configuration in package.nix, and derives the clock
// constraints. The counter stays in reset until the PLL locks.

// The oscillator primitive, from the Libero macro library. Declared as a
// black box for synthesis; it has no RTL model.
(* blackbox *)
module RCOSC_25_50MHZ (
    CLKOUT
)  /* synthesis syn_black_box */;
  output CLKOUT;
endmodule

module blinky_pll (
    input  SW1,
    output LED1,
    output LED2,
    output LED3
);
  wire osc, clk, lock;

  RCOSC_25_50MHZ rcosc (.CLKOUT(osc));
  FCCC_C0 ccc (
      .RCOSC_25_50MHZ(osc),
      .GL0(clk),
      .LOCK(lock)
  );

  blinky_pll_core core (
      .CLK (clk),
      .SW1 (SW1 & lock),
      .LED1(LED1),
      .LED2(LED2),
      .LED3(LED3)
  );
endmodule
