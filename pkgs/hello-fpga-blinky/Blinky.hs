-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE NoImplicitPrelude #-}

-- | Blinky for the Microchip Hello FPGA kit: a counter on a 50 MHz clock,
-- with three of its bits on the SmartFusion 2's debug LEDs. SW1 resets
-- it. The clock comes from the SmartFusion 2's on-chip oscillator, which
-- @blinky.v@ instantiates around this module.
module Blinky where

import Clash.Prelude

-- | The on-chip 25/50 MHz RC oscillator runs at 50 MHz with a 1.2 V core.
-- SW1 pulls its input low while pressed, so it serves as an active-low
-- asynchronous reset.
createDomain
  vSystem
    { vName = "Dom50",
      vPeriod = 20000,
      vResetKind = Asynchronous,
      vResetPolarity = ActiveLow
    }

topEntity :: Clock Dom50 -> Reset Dom50 -> Signal Dom50 (Bit, Bit, Bit)
topEntity clk rst = withClockResetEnable clk rst enableGen leds

-- | Bits 25 to 27 of a 28-bit counter: LED1 toggles about every 0.7 s.
-- The LEDs light when their pin is driven low.
leds :: (HiddenClockResetEnable dom) => Signal dom (Bit, Bit, Bit)
leds = fmap (\c -> (complement (c ! 25), complement (c ! 26), complement (c ! 27))) counter
  where
    counter = register (0 :: Unsigned 28) (counter + 1)

{-# ANN
  topEntity
  ( Synthesize
      { t_name = "blinky_core",
        t_inputs = [PortName "CLK", PortName "SW1"],
        t_output = PortProduct "" [PortName "LED1", PortName "LED2", PortName "LED3"]
      }
  )
  #-}
