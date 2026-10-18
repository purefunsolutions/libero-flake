// SPDX-FileCopyrightText: 2026 Mika Tammi
// SPDX-License-Identifier: MIT
//
// Testbench of the blinky, for every simulation stage (the runner's
// --simulate). It releases SW1 and checks that LED1 lights after 2^25
// periods of the on-chip oscillator, whose simulation model runs at
// exactly 50 MHz: bit 25 of the counter, the carry out of all the bits
// below it. Then it presses SW1 again, which resets the counter. That is
// 0.67 s of simulated time: about a minute before synthesis; with
// QuestaSim 8 minutes for the synthesized netlist and half an hour for the
// routed one, with ModelSim 6 and 14 minutes.
`timescale 1ns / 1ps

module blinky_tb;
  reg SW1 = 1'b0;  // pressed: the counter is held in reset
  wire LED1, LED2, LED3;

  blinky dut (
      .SW1 (SW1),
      .LED1(LED1),
      .LED2(LED2),
      .LED3(LED3)
  );

  // The oscillator's rising edges are at multiples of the period. SW1 goes
  // up between two of them, and the counter counts from the next one. The
  // LEDs light when driven low; the routed design's outputs follow the
  // clock within a period.
  localparam real Period = 20.0;
  localparam real Release = 1010.0;
  localparam real Led1 = 1020.0 + ((1 << 25) - 1) * Period;

  initial begin
    #Release;
    if ({LED3, LED2, LED1} !== 3'b111) $error("LEDs lit while SW1 is pressed");
    SW1 = 1'b1;

    @(negedge LED1);
    $display("LED1 lit at %0.1f ns", $realtime);
    if ($realtime < Led1 || $realtime > Led1 + Period)
      $error("LED1 lit at %0.1f ns, expected %0.1f ns", $realtime, Led1);
    if ({LED3, LED2} !== 2'b11) $error("LED2 or LED3 lit with LED1");

    #100 SW1 = 1'b0;
    #100;
    if ({LED3, LED2, LED1} !== 3'b111) $error("LEDs still lit after SW1 was pressed");
    $finish;
  end

  // The oscillator never stops, so the simulation only ends by $finish.
  initial begin
    #(Led1 + 1000.0);
    $fatal(1, "LED1 did not light");
  end
endmodule
