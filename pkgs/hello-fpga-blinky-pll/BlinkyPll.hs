-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | The blinky at 400 MHz, the most a SmartFusion 2 clock conditioning
-- circuit (CCC) puts out: a counter with three of its bits on the debug
-- LEDs. SW1 resets it. @blinky_pll.v@ instantiates the on-chip oscillator
-- and the CCC, whose PLL makes 400 MHz of its 50 MHz.
module BlinkyPll where

import Clash.Explicit.Testbench
import Clash.Prelude

-- | The CCC's GL0 output. SW1 pulls its input low while pressed, so it
-- serves as an active-low asynchronous reset; @blinky_pll.v@ also holds it
-- until the PLL locks.
createDomain
  vSystem
    { vName = "Dom400",
      vPeriod = 2500,
      vResetKind = Asynchronous,
      vResetPolarity = ActiveLow
    }

topEntity :: Clock Dom400 -> Reset Dom400 -> Signal Dom400 (Bit, Bit, Bit)
topEntity clk rst = withClockResetEnable clk rst enableGen leds

-- | Bits 28 to 30 of a 31-bit counter: LED1 toggles about every 0.7 s, as
-- in the 50 MHz blinky. The LEDs light when their pin is driven low.
leds :: (HiddenClockResetEnable dom) => Signal dom (Bit, Bit, Bit)
leds = fmap (\c -> (complement (c ! 28), complement (c ! 29), complement (c ! 30))) counter
  where
    counter = register (0 :: Unsigned 31) (counter + 1)

{-# ANN
  topEntity
  ( Synthesize
      { t_name = "blinky_pll_core",
        t_inputs = [PortName "CLK", PortName "SW1"],
        t_output = PortProduct "" [PortName "LED1", PortName "LED2", PortName "LED3"]
      }
  )
  #-}

-- | The testbench of the core, which Clash generates as Verilog (the
-- runner's --simulate; before synthesis only, the netlists have no core).
-- SW1 is pressed for the first cycles; from its release on, a counter of
-- the testbench's own predicts the LEDs, compared every cycle, until LED1
-- lights at cycle 2^28. That is 0.67 s of simulated time.
testBench :: Signal Dom400 Bool
testBench = done
  where
    clk = tbClockGen (not <$> done)
    rst = resetGenN (SNat @8)
    cycles = withClockResetEnable clk rst enableGen (register (0 :: Unsigned 32) (cycles + 1))
    expected = (\c -> (complement (c ! 28), complement (c ! 29), complement (c ! 30))) <$> cycles
    done = assert clk rst "LEDs" (topEntity clk rst) expected ((== bit 28 + 4) <$> cycles)
{-# ANN testBench (TestBench 'topEntity) #-}
