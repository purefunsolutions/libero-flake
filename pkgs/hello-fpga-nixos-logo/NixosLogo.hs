-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE NoStarIsType #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Extra.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.KnownNat.Solver #-}
{-# OPTIONS_GHC -fplugin GHC.TypeLits.Normalise #-}

-- | The NixOS rainbow snowflake on the Hello FPGA kit's LCD, a 3.5" ILI9488
-- panel on an 8-bit MIPI DBI Type B bus. The design draws one frame and
-- then rests with LED1 lit; SW1 draws it again.
--
-- The logo is not stored as a picture: the renderer works it out pixel by
-- pixel, in the order the panel takes them. Each edge of the six lambdas is
-- a linear function of the pixel position, stepped by one addition per
-- pixel, and a pixel is inside a lambda when an odd number of its edges lie
-- to its left on its row (the even-odd rule of the SVG). The colour is the
-- lambda's linear gradient at the pixel. @flake-geometry.py@ turns the
-- official SVG into these functions (the module @Geometry@).
--
-- @nixos_logo.v@ clocks this module from the SmartFusion 2's on-chip 50 MHz
-- oscillator and resets it at power-up and with SW1.
module NixosLogo where

import Clash.Prelude
import Geometry

-- | The on-chip 25/50 MHz RC oscillator at 50 MHz. The reset is active
-- low and asynchronous: the power-on reset and SW1.
createDomain
  vSystem
    { vName = "Dom50",
      vPeriod = 20000,
      vResetKind = Asynchronous,
      vResetPolarity = ActiveLow
    }

-- | The panel's bus and the debug LEDs, straight from registers: the
-- strobes are active low, and so are the LEDs.
data Lcd = Lcd
  { -- | RESX
    lcdReset :: Bit,
    -- | CSX
    lcdSelect :: Bit,
    -- | D/CX: 0 for commands, 1 for parameters and pixels
    lcdData :: Bit,
    -- | WRX: the panel takes the bus on its rising edge
    lcdWrite :: Bit,
    -- | RDX
    lcdRead :: Bit,
    lcdBus :: BitVector 8,
    led1 :: Bit,
    led2 :: Bit,
    led3 :: Bit
  }
  deriving (Generic, NFDataX, Eq, Show)

-- | The waits of the start-up sequence, in clock cycles.
data Timing = Timing
  { -- | RESX low
    resetPulse :: Unsigned 23,
    -- | From RESX high to the first command
    resetWait :: Unsigned 23,
    -- | From Sleep Out to the next command
    sleepOutWait :: Unsigned 23
  }

-- | 10 ms, 150 ms and 150 ms at 50 MHz. The ILI9488 needs 10 us, 120 ms and
-- 120 ms; the on-chip oscillator is only about 1 % accurate.
hardware :: Timing
hardware =
  Timing
    { resetPulse = 500_000,
      resetWait = 7_500_000,
      sleepOutWait = 7_500_000
    }

-- | Memory Access Control: rows and columns exchanged for the landscape
-- panel, and its BGR colour filter. Microchip's demos for the kit mirror the
-- picture too (0x68 or 0xA8); seen on the kit, 0x28 is upright.
madctl :: BitVector 8
madctl = 0x28

-- | One step of the start-up sequence.
data Op
  = SetReset Bit
  | -- | At least one cycle
    Wait (Unsigned 23)
  | Command (BitVector 8)
  | Parameter (BitVector 8)
  | -- | The frame, after Memory Write
    Pixels
  | Done

type ProgramLength = 24

-- | Reset the panel, set it up, wake it, write the frame into its memory
-- and only then turn the display on, so the old memory never shows.
program :: Timing -> Vec ProgramLength Op
program t =
  SetReset 0
    :> Wait (resetPulse t)
    :> SetReset 1
    :> Wait (resetWait t)
    :> Command 0x36 -- Memory Access Control
    :> Parameter madctl
    :> Command 0x3A -- Interface Pixel Format
    :> Parameter 0x66 -- 18 bits per pixel, as three bytes
    :> Command 0x11 -- Sleep Out
    :> Wait (sleepOutWait t)
    :> Command 0x2A -- Column Address Set: 0 to Width - 1
    :> Parameter 0
    :> Parameter 0
    :> Parameter lastColumnHigh
    :> Parameter lastColumnLow
    :> Command 0x2B -- Page Address Set: 0 to Height - 1
    :> Parameter 0
    :> Parameter 0
    :> Parameter lastRowHigh
    :> Parameter lastRowLow
    :> Command 0x2C -- Memory Write
    :> Pixels
    :> Command 0x29 -- Display On
    :> Done
    :> Nil
  where
    (lastColumnHigh, lastColumnLow) = split (natToNum @(Width - 1) :: BitVector 16)
    (lastRowHigh, lastRowLow) = split (natToNum @(Height - 1) :: BitVector 16)

-- | Red, green and blue. The panel takes the six upper bits of each.
type Colour = Vec 3 (Unsigned 8)

white :: Colour
white = repeat 255

-- | The sequencer's state. 'out' is the register driving the pins.
data State = State
  { pc :: Index ProgramLength,
    -- | Clock of the byte being written
    slot :: Index 4,
    -- | Clocks left of a wait
    count :: Unsigned 23,
    -- | Pixels left of the frame, this one included
    pixelsLeft :: Unsigned 18,
    -- | Byte of the pixel being written
    byteOfPixel :: Index 3,
    pixel :: Vec 3 (BitVector 8),
    -- | Tells the renderer to move on to the next pixel
    advance :: Bool,
    out :: Lcd
  }
  deriving (Generic, NFDataX)

-- | The panel in reset, selected, the strobes and the LEDs off.
initial :: State
initial =
  State
    { pc = 0,
      slot = 0,
      count = 0,
      pixelsLeft = 0,
      byteOfPixel = 0,
      pixel = repeat 0,
      advance = False,
      out =
        Lcd
          { lcdReset = 0,
            lcdSelect = 0,
            lcdData = 0,
            lcdWrite = 1,
            lcdRead = 1,
            lcdBus = 0,
            led1 = 1,
            led2 = 1,
            led3 = 1
          }
    }

-- | One clock of the sequencer, given the renderer's colour.
--
-- A byte takes four clocks, 80 ns: WR stays high while D/CX and the bus
-- change, goes low for two clocks and rises in the fourth, when the panel
-- takes the byte. That leaves 60 ns of setup and 20 ns of hold; the
-- ILI9488 needs 10 ns of each, a 40 ns cycle and 15 ns pulses.
step :: Vec ProgramLength Op -> State -> Colour -> State
step prog state colour = case prog !! pc s of
  SetReset _ -> next
  Wait _
    | count s > 1 -> s {count = count s - 1}
    | otherwise -> next
  Command _ -> byte next
  Parameter _ -> byte next
  Pixels -> byte nextPixelByte
  Done -> s
  where
    s = state {advance = False}
    next = enter prog colour (satSucc SatBound (pc s)) s
    byte done = case slot s of
      0 -> s {slot = 1, out = (out s) {lcdWrite = 0}}
      1 -> s {slot = 2}
      2 -> s {slot = 3, out = (out s) {lcdWrite = 1}}
      _ -> done
    nextPixelByte
      | byteOfPixel s < 2 =
          let i = byteOfPixel s + 1
           in s {slot = 0, byteOfPixel = i, out = write 1 (pixel s !! i) (out s)}
      | pixelsLeft s > 1 = latch colour s {pixelsLeft = pixelsLeft s - 1}
      | otherwise = next

-- | Start step i of the program.
enter :: Vec ProgramLength Op -> Colour -> Index ProgramLength -> State -> State
enter prog colour i s = case prog !! i of
  SetReset b -> s' {out = (out s) {lcdReset = b}}
  Wait n -> s' {count = n}
  Command b -> s' {out = write 0 b (out s)}
  Parameter b -> s' {out = write 1 b (out s)}
  Pixels -> latch colour s' {pixelsLeft = natToNum @(Width * Height)}
  Done -> s' {out = (out s) {led1 = 0}}
  where
    s' = s {pc = i, slot = 0}

-- | Take the renderer's colour, start writing it, and move the renderer
-- on to the next pixel.
latch :: Colour -> State -> State
latch colour s =
  s
    { slot = 0,
      byteOfPixel = 0,
      pixel = bytes,
      advance = True,
      out = write 1 (head bytes) (out s)
    }
  where
    bytes = map pack colour

write :: Bit -> BitVector 8 -> Lcd -> Lcd
write dc b o = o {lcdData = dc, lcdBus = b, lcdWrite = 1}

-- | The colour of the pixel the renderer is at. It starts at pixel (0, 0)
-- and moves on, in rows, at every advance; the colour of the new pixel is
-- there six clocks later.
renderer :: (HiddenClockResetEnable dom) => Signal dom Bool -> Signal dom Colour
renderer advance' = colour
  where
    x = register (0 :: Index Width) (mux advance' (satSucc SatWrap <$> x) x)
    y = register (0 :: Index Height) (mux (advance' .&&. endOfRow) (satSucc SatWrap <$> y) y)
    endOfRow = (== maxBound) <$> x
    edgeValues = stepped advance' endOfRow (map start edges) (map stepX edges) (map rowStep edges)
    fillValues = stepped advance' endOfRow (map fillStart fills) (map fillStepX fills) (map fillRowStep fills)
    inside = register (repeat False) (insideOf <$> y <*> edgeValues)
    picked = register Nothing (pick <$> inside <*> fillValues)
    segment = register Nothing (segmentOf <$> picked)
    product' = register Nothing (products <$> segment)
    colour = register white (finish <$> product')

-- | Linear functions of the pixel position, from their values at pixel
-- (0, 0). At every advance, each adds its step along the row or, at the
-- end of a row, its step to the start of the next.
stepped ::
  (HiddenClockResetEnable dom, KnownNat n, Num a, NFDataX a) =>
  Signal dom Bool ->
  Signal dom Bool ->
  Vec n a ->
  Vec n a ->
  Vec n a ->
  Signal dom (Vec n a)
stepped advance' endOfRow values0 alongRow toNextRow = values
  where
    values = register values0 (mux advance' (next <$> values <*> endOfRow) values)
    next vs atEnd = evaluated (zipWith3 (\v a r -> v + if atEnd then r else a) vs alongRow toNextRow)
    -- A register evaluates the vector but not its elements; evaluating them
    -- too keeps the simulation from piling up sums nobody looked at. In
    -- hardware this is nothing.
    evaluated vs = foldr seq vs vs

-- | The lambdas a pixel of row y is in, from its edge functions: those
-- with an odd number of edges crossing the row left of it.
insideOf :: Index Height -> Vec EdgeCount EdgeValue -> Vec 6 Bool
insideOf y values = map inLambda indicesI
  where
    row = fromIntegral y :: Unsigned 9
    counts = zipWith (\e v -> firstRow e <= row && row < endRow e && v >= 0) edges values
    inLambda k = foldr xor False (zipWith (\e c -> lambda e == k && c) edges counts)

-- | The lambda a pixel is in, the last in SVG order as the SVG paints
-- them, and its gradient parameter clamped to [0, 1].
pick :: Vec 6 Bool -> Vec 6 FillValue -> Maybe (Index 6, FillValue)
pick inside ts = foldl choose Nothing (zip3 indicesI inside ts)
  where
    choose found (k, isIn, t) = if isIn then Just (k, max 0 (min 65536 t)) else found

-- | The gradient segment and the distance into it.
segmentOf :: Maybe (Index 6, FillValue) -> Maybe (Index 6, Index 2, Signed 18)
segmentOf = fmap $ \(k, t) ->
  let ss = segments (fills !! k)
      i = if t >= from (ss !! (1 :: Index 2)) then 1 else 0
   in (k, i, resize (t - from (ss !! i)))

-- | The segment's base colour and the products of its slopes with the
-- distance, one math block each.
products :: Maybe (Index 6, Index 2, Signed 18) -> Maybe (Colour, Vec 3 (Signed 36))
products = fmap $ \(k, i, d) ->
  let s = segments (fills !! k) !! i
   in (base s, map (mul d) (slope s))

finish :: Maybe (Colour, Vec 3 (Signed 36)) -> Colour
finish Nothing = white
finish (Just (bases, ps)) = zipWith channel bases ps
  where
    channel b p =
      let v = fromIntegral b + shiftR (p + bit (slopeShift - 1)) slopeShift :: Signed 36
       in if v < 0 then 0 else if v > 255 then 255 else fromIntegral v

-- | The sequencer and the renderer, with the given waits.
core :: (HiddenClockResetEnable dom) => Timing -> Signal dom Lcd
core t = lcd
  where
    (lcd, advance') = unbundle (moore (step (program t)) (\s -> (out s, advance s)) initial colour)
    colour = renderer advance'

topEntity :: Clock Dom50 -> Reset Dom50 -> Signal Dom50 Lcd
topEntity clk rst = withClockResetEnable clk (resetSynchronizer clk rst) enableGen (core hardware)
{-# ANN
  topEntity
  ( Synthesize
      { t_name = "nixos_logo_core",
        t_inputs = [PortName "CLK", PortName "RESET_N"],
        t_output =
          PortProduct
            ""
            [ PortName "LCD_RST",
              PortName "LCD_CS",
              PortName "LCD_RS",
              PortName "LCD_WR",
              PortName "LCD_RD",
              PortName "LCD_D",
              PortName "LED1",
              PortName "LED2",
              PortName "LED3"
            ]
      }
  )
  #-}
