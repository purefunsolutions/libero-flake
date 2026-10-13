// SPDX-FileCopyrightText: 2026 Mika Tammi
// SPDX-License-Identifier: MIT
//
// Top level of the blinky: the SmartFusion 2's on-chip 50 MHz RC
// oscillator clocking blinky_core, the Clash design. The kit's external
// 50 MHz oscillator (X1 on N8) is not used: on one kit it stopped running
// after power-ups, and Microchip's own demo designs for the kit clock
// from the on-chip oscillator as well.

// Microchip primitives from the SmartFusion 2 macro library, declared as
// black boxes for synthesis only: simulators use the library's models of
// them, which these empty modules would hide.
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

module blinky (
    input  SW1,
    output LED1,
    output LED2,
    output LED3
);
  wire osc, osc_fab, clk;

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

  blinky_core core (
      .CLK (clk),
      .SW1 (SW1),
      .LED1(LED1),
      .LED2(LED2),
      .LED3(LED3)
  );
endmodule
