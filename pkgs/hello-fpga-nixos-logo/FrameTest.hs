-- SPDX-FileCopyrightText: 2026 Mika Tammi
-- SPDX-License-Identifier: MIT
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE TypeApplications #-}

-- | The check of hello-fpga-nixos-logo that needs no Microchip software:
-- the core, simulated clock by clock with short waits, writes a frame to
-- an LCD that only exists here, made of what it puts on the bus.
--
--   * The bus follows the ILI9488's DBI Type B write timing, even with the
--     oscillator 1 % fast, and the commands are the expected ones.
--   * The frame equals, bit for bit, the renderer's functions applied to
--     the edge and gradient functions evaluated directly at every pixel:
--     no stepping, rows or pipeline.
--   * As the panel shows it, the frame matches rsvg-convert's rendering of
--     the SVG, except for a few pixels on the edges, which the two sample
--     differently.
--
-- Usage: frame-test REFERENCE.ppm FRAME.ppm DIFF.ppm. It writes the frame
-- as the panel shows it, and the frame with the pixels that differ from the
-- reference in magenta.
module Main (main) where

import Clash.Prelude (Bit, sampleN, toList)
import qualified Clash.Prelude as C
import Control.Monad (unless, when)
import Data.Bits (shiftL, shiftR, (.|.))
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as BC
import Data.Word (Word8)
import Geometry
import NixosLogo
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)

-- | Short waits, all different, so that the checks can tell them apart.
short :: Timing
short = Timing {resetPulse = 3, resetWait = 5, sleepOutWait = 7}

-- | The longest a clock cycle may be shorter than 20 ns: the on-chip
-- oscillator is about 1 % accurate.
nsPerCycle :: Double
nsPerCycle = 19.8

-- | More than the frame takes: 12 clocks per pixel.
cycleLimit :: Int
cycleLimit = 2_000_000

-- | The pixels that may differ from rsvg-convert's rendering, all of them
-- on edges: 8 with librsvg 2.62.
edgeBudget :: Int
edgeBudget = 32

-- | A byte the panel took, on the rising edge of WR.
data Write = Write
  { writeFall :: !Int,
    writeRise :: !Int,
    writeData :: !Bit,
    writeByte :: !Word8
  }

data Bus = Bus
  { busCycle :: !Int,
    busPrevious :: !Lcd,
    busFall :: !Int,
    busRise :: !Int,
    busResetHigh :: !(Maybe Int),
    busWrites :: ![Write],
    busErrors :: ![String],
    busDone :: !Bool
  }

-- | Follow the bus one clock, checking it against the ILI9488's timing.
watch :: Bus -> Lcd -> Bus
watch bus lcd = bus' {busCycle = n + 1, busPrevious = lcd}
  where
    n = busCycle bus
    prev = busPrevious bus
    falls = lcdWrite prev == 1 && lcdWrite lcd == 0
    rises = lcdWrite prev == 0 && lcdWrite lcd == 1
    changed = (lcdData prev, lcdBus prev) /= (lcdData lcd, lcdBus lcd)
    ns cycles = fromIntegral cycles * nsPerCycle
    errors =
      [ "D/CX or the bus changed while WR was low or rising"
      | changed && not (lcdWrite prev == 1 && lcdWrite lcd == 1)
      ]
        <> ["RD went low" | lcdRead lcd == 0]
        <> ["WR high for under 15 ns" | falls && ns (n - busRise bus) < 15]
        <> ["WR low for under 15 ns" | rises && ns (n - busFall bus) < 15]
        <> ["write cycle under 40 ns" | rises && ns (n - busRise bus) < 40]
        <> ["write with CS high" | rises && lcdSelect lcd == 1]
        <> ["write during reset" | rises && lcdReset lcd == 0]
    bus' =
      bus
        { busFall = if falls then n else busFall bus,
          busRise = if rises then n else busRise bus,
          busResetHigh = case busResetHigh bus of
            Nothing | lcdReset lcd == 1 -> Just n
            r -> r,
          busWrites =
            if rises
              then Write (busFall bus) n (lcdData lcd) (fromIntegral (lcdBus lcd)) : busWrites bus
              else busWrites bus,
          busErrors = map (("cycle " <> show n <> ": ") <>) errors <> busErrors bus,
          busDone = lcdWrite lcd == 1 && led1 lcd == 0
        }

-- | Commands and parameters before and after the pixels, as (D/CX, byte).
expected :: ([(Bit, Word8)], [(Bit, Word8)])
expected =
  ( [ (0, 0x36),
      (1, 0x28),
      (0, 0x3A),
      (1, 0x66),
      (0, 0x11),
      (0, 0x2A),
      (1, 0x00),
      (1, 0x00),
      (1, 0x01),
      (1, 0xDF),
      (0, 0x2B),
      (1, 0x00),
      (1, 0x00),
      (1, 0x01),
      (1, 0x3F),
      (0, 0x2C)
    ],
    [(0, 0x29)]
  )

width, height :: Int
width = C.natToNum @Width
height = C.natToNum @Height

-- | The renderer's colour of pixel (x, y), its edge and gradient functions
-- evaluated directly instead of stepped from pixel to pixel.
model :: Int -> Int -> Colour
model x y = finish (products (segmentOf (pick (insideOf (fromIntegral y) es) ts)))
  where
    at sx sy s = toInteger sx * toInteger x + toInteger sy * toInteger y + toInteger s
    es = C.map (\e -> exact "edge" (at (stepX e) (stepY e) (start e))) edges
    ts = C.map (\f -> exact "fill" (at (fillStepX f) (fillStepY f) (fillStart f))) fills

-- | An Integer in a narrower type, which must hold it.
exact :: (Bounded a, Integral a) => String -> Integer -> a
exact what v
  | v >= toInteger (minBound `asTypeOf` r) && v <= toInteger (maxBound `asTypeOf` r) = r
  | otherwise = error (what <> " value " <> show v <> " out of range")
  where
    r = fromInteger v

-- | What the panel shows of a byte: its six upper bits, widened again.
shown :: Word8 -> Word8
shown b = let c = b `shiftR` 2 in (c `shiftL` 2) .|. (c `shiftR` 4)

readPpm :: FilePath -> IO B.ByteString
readPpm path = do
  bytes <- B.readFile path
  case header (4 :: Int) [] bytes of
    (["P6", w, h, "255"], rest)
      | read w == width && read h == height && B.length rest >= 3 * width * height ->
          pure (B.take (3 * width * height) rest)
    _ -> fail (path <> ": not a " <> show width <> "x" <> show height <> " PPM")
  where
    header 0 tokens rest = (reverse tokens, B.drop 1 rest)
    header k tokens s =
      let s' = BC.dropWhile isSpace s
       in case BC.uncons s' of
            Just ('#', _) -> header k tokens (BC.dropWhile (/= '\n') s')
            _ ->
              let (token, rest) = BC.break isSpace s'
               in header (k - 1) (BC.unpack token : tokens) rest
    isSpace = (`elem` (" \t\r\n" :: String))

writePpm :: FilePath -> B.ByteString -> IO ()
writePpm path pixels =
  B.writeFile path (BC.pack ("P6\n" <> show width <> " " <> show height <> "\n255\n") <> pixels)

-- | Maximum difference over the channels of two pixels.
distance :: [Word8] -> [Word8] -> Int
distance a b = maximum (zipWith (\p q -> abs (fromIntegral p - fromIntegral q)) a b)

main :: IO ()
main = do
  [referencePath, framePath, diffPath] <- getArgs
  let failWith message = hPutStrLn stderr ("frame-test: " <> message) >> exitFailure

  -- The real waits, with the oscillator 1 % fast.
  let ms cycles = fromIntegral cycles * nsPerCycle / 1e6 :: Double
  unless (ms (resetPulse hardware) >= 0.01) (failWith "RESX low for under 10 us")
  unless (ms (resetWait hardware) >= 120) (failWith "Sleep Out within 120 ms of the reset")
  unless (ms (sleepOutWait hardware) >= 120) (failWith "a command within 120 ms of Sleep Out")

  -- Edges long before the first, which the first ones are measured from.
  let never = -1_000_000
      start' = Bus 0 (out initial) never never Nothing [] [] False
      run !bus (lcd : rest)
        | not (busDone bus) && null (busErrors bus) && busCycle bus < cycleLimit = run (watch bus lcd) rest
      run bus _ = bus
      bus = run start' (sampleN @Dom50 cycleLimit (core short))
  unless (null (busErrors bus)) (failWith (unlines (busErrors bus)))
  unless (busDone bus) (failWith ("no frame within " <> show cycleLimit <> " clocks"))

  -- The waits, short here.
  let writes = reverse (busWrites bus)
      after code = case dropWhile (\w -> (writeData w, writeByte w) /= (0, code)) writes of
        w : next : _ -> writeFall next - writeRise w
        _ -> 0
  case (busResetHigh bus, writes) of
    (Just high, first : _) | high >= fromIntegral (resetPulse short) && writeFall first - high >= fromIntegral (resetWait short) -> pure ()
    _ -> failWith "the reset is too short or the first command too early"
  when (after 0x11 < fromIntegral (sleepOutWait short)) (failWith "a command too soon after Sleep Out")

  -- The commands, and the pixels between them.
  let (before, after') = expected
      bytes = [(writeData w, writeByte w) | w <- writes]
      pixelBytes = 3 * width * height
      (head', rest) = splitAt (length before) bytes
      (pixels, tail') = splitAt pixelBytes rest
  unless (head' == before) (failWith ("unexpected commands: " <> show (take 20 head')))
  unless (length pixels == pixelBytes && all ((== 1) . fst) pixels) (failWith "not a frame of pixels")
  unless (tail' == after') (failWith ("unexpected commands after the frame: " <> show (take 5 tail')))
  let frame = B.pack (map snd pixels)

  -- Bit for bit against the direct model.
  let pixelAt buffer i = [B.index buffer (3 * i + c) | c <- [0, 1, 2]]
      modelled = B.pack [fromIntegral c | y <- [0 .. height - 1], x <- [0 .. width - 1], c <- toList (model x y)]
      mismatches = [i | i <- [0 .. width * height - 1], pixelAt frame i /= pixelAt modelled i]
  case mismatches of
    [] -> pure ()
    i : _ ->
      failWith
        ( show (length mismatches)
            <> " pixels differ from the model, first ("
            <> show (i `mod` width)
            <> ", "
            <> show (i `div` width)
            <> "): "
            <> show (pixelAt frame i)
            <> " instead of "
            <> show (pixelAt modelled i)
        )

  -- Against the SVG: only edge pixels may differ, and only a few. A pixel
  -- is on an edge when one of its neighbours in the reference has another
  -- colour, which the frame shows instead.
  reference <- readPpm referencePath
  let panel = B.map shown frame
      ref x y = pixelAt reference (y * width + x)
      ours x y = pixelAt panel (y * width + x)
      neighbours x y =
        [ref x' y' | dy <- [-1, 0, 1], dx <- [-1, 0, 1], (dx, dy) /= (0, 0), let x' = x + dx, let y' = y + dy, x' >= 0, x' < width, y' >= 0, y' < height]
      verdict x y
        | distance (ours x y) (ref x y) <= 6 = Nothing
        | any (\n -> distance n (ref x y) > 12 && distance n (ours x y) <= 6) (neighbours x y) = Just True
        | otherwise = Just False
      verdicts = [((x, y), v) | y <- [0 .. height - 1], x <- [0 .. width - 1], Just v <- [verdict x y]]
      onEdges = length (filter snd verdicts)
      elsewhere = [p | (p, False) <- verdicts]
      diff =
        B.pack
          [ c
          | y <- [0 .. height - 1],
            x <- [0 .. width - 1],
            c <- case verdict x y of
              Nothing -> map (\v -> 255 - (255 - v) `div` 4) (ours x y)
              Just _ -> [255, 0, 255]
          ]
  writePpm framePath panel
  writePpm diffPath diff
  unless (null elsewhere) (failWith (show (length elsewhere) <> " pixels off the edges differ from the SVG, e.g. " <> show (take 5 elsewhere)))
  when (onEdges > edgeBudget) (failWith (show onEdges <> " edge pixels differ from the SVG, more than " <> show edgeBudget))
  putStrLn
    ( "frame-test: "
        <> show (length writes)
        <> " writes in "
        <> show (busCycle bus)
        <> " clocks; the frame equals the model; "
        <> show onEdges
        <> " edge pixels differ from the SVG"
    )
