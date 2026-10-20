#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
"""Turn the NixOS rainbow snowflake into constants for the Clash renderer.

Reads nix-snowflake-rainbow.svg from NixOS/nixos-artwork and writes
Geometry.hs: the edges of its six lambdas as integer edge functions and
their linear gradients as integer ramps, at pixel centres of the LCD. The
logo is placed as `rsvg-convert --page-width W --page-height H --left L
--top T -w S -h S` places it, so the two renderings can be compared.

Edge e of a lambda is E = stepX*x + stepY*y + start at the centre of pixel
(x, y), in 1/4096 pixel: the distance to the edge's line, oriented so that
E >= 0 when the edge crosses row y left of the pixel. It crosses the rows
[firstRow, endRow). A pixel is inside a lambda when an odd number of its
edges count, the even-odd rule of the SVG. Edges that cross no row are left
out.

The gradient parameter of a lambda is t = stepX*x + stepY*y + start in
1/65536, clamped to [0, 1]. Each of its two segments has a start and, per
channel, a base colour and a slope: colour = base + (d*slope + 2^(n-1)) >> n
with d = t - start and n the slope shift.

Only what this SVG uses is supported, and anything else is refused: paths
of straight lines, similarity transforms, linear gradients with three opaque
stops, opaque fills.
"""

import argparse
import hashlib
import math
import re
import sys
import xml.etree.ElementTree as ET

SVG = "{http://www.w3.org/2000/svg}"
XLINK = "{http://www.w3.org/1999/xlink}href"

EDGE_ONE = 1 << 12  # edge functions: 1/4096 pixel
FILL_ONE = 1 << 16  # gradient parameter: 1/65536
SLOPE_BITS = 18  # signed slopes, one SmartFusion 2 math block operand


class GeometryError(Exception):
    pass


def check(condition, message):
    if not condition:
        raise GeometryError(message)


# Affine maps (a, b, c, d, e, f) as in SVG's matrix(): x' = a*x + c*y + e.
IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def compose(m, n):
    """The map that applies n first, then m."""
    a, b, c, d, e, f = m
    p, q, r, s, t, u = n
    return (
        a * p + c * q,
        b * p + d * q,
        a * r + c * s,
        b * r + d * s,
        a * t + c * u + e,
        b * t + d * u + f,
    )


def apply(m, point):
    a, b, c, d, e, f = m
    x, y = point
    return (a * x + c * y + e, b * x + d * y + f)


def parse_transform(text):
    result = IDENTITY
    text = (text or "").strip()
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", text):
        v = [float(x) for x in re.split(r"[\s,]+", args.strip())]
        if name == "matrix" and len(v) == 6:
            m = tuple(v)
        elif name == "translate" and len(v) in (1, 2):
            m = (1.0, 0.0, 0.0, 1.0, v[0], v[1] if len(v) == 2 else 0.0)
        elif name == "scale" and len(v) in (1, 2):
            m = (v[0], 0.0, 0.0, v[1] if len(v) == 2 else v[0], 0.0, 0.0)
        elif name == "rotate" and len(v) in (1, 3):
            angle = math.radians(v[0])
            cos, sin = math.cos(angle), math.sin(angle)
            m = (cos, sin, -sin, cos, 0.0, 0.0)
            if len(v) == 3:
                m = compose(
                    compose((1.0, 0.0, 0.0, 1.0, v[1], v[2]), m),
                    (1.0, 0.0, 0.0, 1.0, -v[1], -v[2]),
                )
        else:
            raise GeometryError(f"unsupported transform: {name}({args})")
        result = compose(result, m)
    check(
        re.fullmatch(r"(\s*\w+\s*\([^)]*\)\s*,?)*\s*", text),
        f"unparsed transform: {text!r}",
    )
    return result


def check_similarity(m, what):
    """Rotations, uniform scales and translations keep gradients linear."""
    a, b, c, d, _, _ = m
    scale = math.hypot(a, b)
    check(
        math.isclose(math.hypot(c, d), scale, rel_tol=1e-9)
        and abs(a * c + b * d) <= 1e-9 * scale * scale,
        f"{what}: not a similarity transform",
    )


def style(element):
    """The element's style attribute as a dict."""
    items = (item.split(":", 1) for item in (element.get("style") or "").split(";"))
    return {k.strip(): v.strip() for k, v in (i for i in items if len(i) == 2)}


def check_opaque(element, what):
    s = style(element)
    for key in ("opacity", "fill-opacity", "stop-opacity"):
        value = s.get(key, element.get(key, "1"))
        check(float(value) == 1, f"{what}: {key} {value}")
    check(s.get("display", "inline") != "none", f"{what}: hidden")


def path_polygon(d, what):
    """The vertices of a path made of one closed run of straight lines."""
    check(re.fullmatch(r"[MmLlZz0-9eE.,+\-\s]*", d), f"{what}: not straight lines")
    tokens = re.findall(r"[MmLlZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", d)
    points, current, command, closed = [], (0.0, 0.0), None, False
    i = 0
    while i < len(tokens):
        check(not closed, f"{what}: data after the closepath")
        token = tokens[i]
        if token in "MmLlZz":
            check(token in "Mm" or points, f"{what}: must start with a moveto")
            check(token not in "Mm" or not points, f"{what}: more than one subpath")
            command = token
            i += 1
            if token in "Zz":
                closed = True
            continue
        check(command is not None and i + 1 < len(tokens), f"{what}: bad path data")
        x, y = float(tokens[i]), float(tokens[i + 1])
        i += 2
        if command in "ml":
            current = (current[0] + x, current[1] + y)
        else:
            current = (x, y)
        points.append(current)
        # Coordinates after a moveto are linetos.
        command = {"m": "l", "M": "L"}.get(command, command)
    check(closed, f"{what}: path not closed")
    if math.dist(points[0], points[-1]) < 1e-9:
        points.pop()
    check(len(points) >= 3, f"{what}: fewer than three vertices")
    return points


def segments_cross(p, q, r, s):
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])

    return (
        orient(p, q, r) * orient(p, q, s) < 0 and orient(r, s, p) * orient(r, s, q) < 0
    )


def contains(polygon, point):
    inside = False
    for (x0, y0), (x1, y1) in zip(polygon, polygon[1:] + polygon[:1]):
        if (y0 > point[1]) != (y1 > point[1]):
            if point[0] < x0 + (point[1] - y0) * (x1 - x0) / (y1 - y0):
                inside = not inside
    return inside


def edges_of(polygon):
    return list(zip(polygon, polygon[1:] + polygon[:1]))


class Svg:
    def __init__(self, path):
        self.root = ET.parse(path).getroot()
        check(self.root.tag == SVG + "svg", "not an SVG document")
        self.gradients = {
            g.get("id"): g for g in self.root.iter(SVG + "linearGradient")
        }

    def screen(self, width, height, left, top, size):
        """User space of the root to screen pixels, as rsvg-convert places it."""
        root = self.root
        check(
            root.get("preserveAspectRatio") in (None, "xMidYMid meet", "xMidYMid"),
            "unsupported preserveAspectRatio",
        )
        doc_w = float(root.get("width").removesuffix("px"))
        doc_h = float(root.get("height").removesuffix("px"))
        vx, vy, vw, vh = (float(v) for v in root.get("viewBox").split())
        meet = min(doc_w / vw, doc_h / vh)
        view = (
            meet,
            0.0,
            0.0,
            meet,
            (doc_w - meet * vw) / 2 - meet * vx,
            (doc_h - meet * vh) / 2 - meet * vy,
        )
        page = (size / doc_w, 0.0, 0.0, size / doc_h, float(left), float(top))
        m = compose(page, view)
        check_similarity(m, "the placement")
        return m

    def attribute(self, gradient, name):
        """A gradient's attribute, inherited through its xlink:href chain."""
        while gradient is not None:
            if gradient.get(name) is not None:
                return gradient.get(name)
            href = gradient.get(XLINK)
            gradient = self.gradients[href[1:]] if href else None
        return None

    def stops(self, gradient):
        while not gradient.findall(SVG + "stop"):
            href = gradient.get(XLINK)
            check(href, f"gradient {gradient.get('id')} has no stops")
            gradient = self.gradients[href[1:]]
        stops = []
        for stop in gradient.findall(SVG + "stop"):
            check_opaque(stop, f"stop {stop.get('id')}")
            offset = stop.get("offset")
            offset = float(offset[:-1]) / 100 if offset.endswith("%") else float(offset)
            colour = style(stop).get("stop-color", stop.get("stop-color"))
            check(
                re.fullmatch(r"#[0-9a-fA-F]{6}", colour or ""),
                f"stop colour {colour}",
            )
            stops.append((offset, tuple(int(colour[i : i + 2], 16) for i in (1, 3, 5))))
        return stops

    def lambdas(self, screen):
        """(name, polygon, gradient start, gradient end, stops), in screen pixels."""
        found = []

        def walk(element, ctm):
            check_opaque(element, element.get("id") or element.tag)
            ctm = compose(ctm, parse_transform(element.get("transform")))
            if element.tag == SVG + "path":
                found.append(self.lambda_of(element, ctm))
            for child in element:
                if child.tag in (SVG + "g", SVG + "path"):
                    walk(child, ctm)

        walk(self.root, screen)
        return found

    def lambda_of(self, path, ctm):
        name = path.get("id")
        s = style(path)
        check(s.get("stroke", "none") == "none", f"{name}: stroked")
        fill = re.fullmatch(r"url\(#([^)]+)\)", s.get("fill", ""))
        check(fill, f"{name}: not filled with a gradient")
        gradient = self.gradients[fill.group(1)]
        check(
            self.attribute(gradient, "gradientUnits") == "userSpaceOnUse",
            f"{name}: gradient not in user space",
        )
        check(
            self.attribute(gradient, "spreadMethod") in (None, "pad"),
            f"{name}: gradient does not pad",
        )
        check_similarity(ctm, name)
        polygon = [apply(ctm, p) for p in path_polygon(path.get("d"), name)]
        to_screen = compose(
            ctm, parse_transform(self.attribute(gradient, "gradientTransform"))
        )
        check_similarity(to_screen, f"{name}'s gradient")
        g1, g2 = (
            apply(
                to_screen,
                (
                    float(self.attribute(gradient, f"x{i}")),
                    float(self.attribute(gradient, f"y{i}")),
                ),
            )
            for i in (1, 2)
        )
        return name, polygon, g1, g2, self.stops(gradient)


def check_shapes(lambdas):
    polygons = [polygon for _, polygon, _, _, _ in lambdas]
    for k, polygon in enumerate(polygons):
        sides = edges_of(polygon)
        for i, (p, q) in enumerate(sides):
            for r, s in sides[i + 2 :] if i else sides[2:-1]:
                check(not segments_cross(p, q, r, s), f"lambda {k} is not simple")
        for other in polygons[k + 1 :]:
            for p, q in sides:
                for r, s in edges_of(other):
                    check(not segments_cross(p, q, r, s), "lambdas overlap")
            check(
                not contains(other, polygon[0]) and not contains(polygon, other[0]),
                "lambdas overlap",
            )


def signed_bits(values):
    """Bits of the smallest signed type holding all values."""
    bits = 1
    while not all(-(1 << (bits - 1)) <= v < (1 << (bits - 1)) for v in values):
        bits += 1
    return bits


def linear_extremes(step_x, step_y, start, width, height):
    """A linear function's values at the screen's corners, one row past the
    last: the renderer steps once more after the last pixel."""
    return [
        step_x * x + step_y * y + start for x in (0, width - 1) for y in (0, height)
    ]


def edge_function(p, q, height):
    """Edge function and row span of the edge p -> q, or None if it crosses
    no row's pixel centres."""
    dx, dy = q[0] - p[0], q[1] - p[1]
    first = min(height, max(0, math.ceil(min(p[1], q[1]) - 0.5)))
    end = min(height, max(0, math.ceil(max(p[1], q[1]) - 0.5)))
    if first >= end:
        return None
    length = math.hypot(dx, dy)
    sign = 1 if dy > 0 else -1
    step_x = round(EDGE_ONE * sign * dy / length)
    step_y = round(-EDGE_ONE * sign * dx / length)
    check(step_x != 0, "an edge crossing rows is horizontal after rounding")
    # Anchored at the edge's midpoint with the rounded steps, so that the
    # rounding tilts the line about the edge instead of about pixel (0, 0).
    mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
    start = round(step_x * (0.5 - mx) + step_y * (0.5 - my))
    return step_x, step_y, start, first, end


def fill_function(polygon, g1, g2, stops):
    vx, vy = g2[0] - g1[0], g2[1] - g1[1]
    norm = vx * vx + vy * vy
    step_x = round(FILL_ONE * vx / norm)
    step_y = round(FILL_ONE * vy / norm)
    # Anchored at the lambda's centroid, for the same reason.
    cx = sum(x for x, _ in polygon) / len(polygon)
    cy = sum(y for _, y in polygon) / len(polygon)
    t = ((cx - g1[0]) * vx + (cy - g1[1]) * vy) / norm
    start = round(FILL_ONE * t + step_x * (0.5 - cx) + step_y * (0.5 - cy))
    check(len(stops) == 3, "gradients need three stops")
    offsets = [round(FILL_ONE * o) for o, _ in stops]
    check(
        offsets[0] == 0 and 0 < offsets[1] < FILL_ONE and offsets[2] == FILL_ONE,
        "gradient stops must be at 0, between, and 1",
    )
    colours = [c for _, c in stops]
    segments = [
        (
            offsets[i],
            offsets[i + 1] - offsets[i],
            colours[i],
            [b - a for a, b in zip(colours[i], colours[i + 1])],
        )
        for i in range(2)
    ]
    return step_x, step_y, start, segments


def slope_shift(fills):
    """The largest shift whose slopes all fit SLOPE_BITS signed bits."""
    ratios = [
        abs(delta) / length
        for _, _, _, segments in fills
        for _, length, _, deltas in segments
        for delta in deltas
    ]
    limit = (1 << (SLOPE_BITS - 1)) - 1
    shift = 0
    while shift < 32 and all(round(r * (1 << (shift + 1))) <= limit for r in ratios):
        shift += 1
    return shift


def haskell_int(value):
    return f"({value})" if value < 0 else str(value)


def haskell_vec(items, indent):
    pad = " " * indent
    return (
        "\n" + pad + ("\n" + pad + ":> ").join(items) + "\n" + pad + ":> Nil"
        if items
        else "Nil"
    )


def compute(svg_path, width, height, left, top, size):
    """The lambdas, their edges and fills, the slope shift and the widths."""
    svg = Svg(svg_path)
    lambdas = svg.lambdas(svg.screen(width, height, left, top, size))
    check(len(lambdas) == 6, f"expected six lambdas, found {len(lambdas)}")
    check_shapes(lambdas)

    edges, fills = [], []
    for k, (_, polygon, g1, g2, stops) in enumerate(lambdas):
        for p, q in edges_of(polygon):
            edge = edge_function(p, q, height)
            if edge is not None:
                edges.append((k,) + edge)
        fills.append(fill_function(polygon, g1, g2, stops))

    shift = slope_shift(fills)
    edge_values = [
        v
        for _, sx, sy, start, _, _ in edges
        for v in linear_extremes(sx, sy, start, width, height)
        + [sx, sy, sy - (width - 1) * sx, start]
    ]
    fill_values = [
        v
        for sx, sy, start, segments in fills
        for v in linear_extremes(sx, sy, start, width, height)
        + [sx, sy, sy - (width - 1) * sx, start, FILL_ONE]
        + [o for o, _, _, _ in segments]
    ]
    edge_bits, fill_bits = signed_bits(edge_values), signed_bits(fill_values)
    return lambdas, edges, fills, shift, edge_bits, fill_bits


def generate(svg_path, width, height, left, top, size):
    lambdas, edges, fills, shift, edge_bits, fill_bits = compute(
        svg_path, width, height, left, top, size
    )

    def segment(o, length, base, deltas):
        slopes = [round(delta * (1 << shift) / length) for delta in deltas]
        check(signed_bits(slopes) <= SLOPE_BITS, "slope too large")
        return (
            f"Segment {o} ({' :> '.join(map(str, base))} :> Nil)"
            f" ({' :> '.join(map(haskell_int, slopes))} :> Nil)"
        )

    edge_lines = [
        f"Edge {k} {haskell_int(sx)} {haskell_int(sy)}"
        f" {haskell_int(sy - (width - 1) * sx)} {haskell_int(start)} {first} {end}"
        for k, sx, sy, start, first, end in edges
    ]
    fill_lines = [
        f"Fill {haskell_int(sx)} {haskell_int(sy)}"
        f" {haskell_int(sy - (width - 1) * sx)} {haskell_int(start)}"
        f" ({' :> '.join(segment(*s) for s in segments)} :> Nil)"
        for sx, sy, start, segments in fills
    ]
    with open(svg_path, "rb") as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    names = ", ".join(name for name, _, _, _, _ in lambdas)
    return f"""\
-- Generated by flake-geometry.py from nix-snowflake-rainbow.svg (sha256
-- {digest}), the NixOS logo, placed at
-- left {left:g}, top {top:g}, size {size:g} on a {width}x{height} screen.
-- Lambdas, in SVG order: {names}.
{{-# LANGUAGE DataKinds #-}}
{{-# LANGUAGE NoImplicitPrelude #-}}

module Geometry where

import Clash.Prelude

type Width = {width}

type Height = {height}

-- | Wide enough for every edge function and gradient parameter on the
-- screen, and one row past it.
type EdgeValue = Signed {edge_bits}

type FillValue = Signed {fill_bits}

-- | Edges that cross a row, of all six lambdas.
type EdgeCount = {len(edges)}

-- | An edge of lambda 'lambda': E = stepX * x + stepY * y + start at the
-- centre of pixel (x, y), in 1/4096 pixel, E >= 0 when the edge crosses
-- row y left of the pixel. 'rowStep' takes E from the end of a row to the
-- start of the next. The edge crosses rows [firstRow, endRow).
data Edge = Edge
  {{ lambda :: Index 6,
    stepX :: EdgeValue,
    stepY :: EdgeValue,
    rowStep :: EdgeValue,
    start :: EdgeValue,
    firstRow :: Unsigned 9,
    endRow :: Unsigned 9
  }}

-- | A gradient segment from t = 'from' (1/65536) on: per channel,
-- colour = base + (d * slope + 2^(slopeShift - 1)) >> slopeShift with
-- d = t - from.
data Segment = Segment
  {{ from :: FillValue,
    base :: Vec 3 (Unsigned 8),
    slope :: Vec 3 (Signed {SLOPE_BITS})
  }}

-- | A lambda's gradient parameter t = fillStepX * x + fillStepY * y +
-- fillStart, in 1/65536, which the renderer clamps to [0, 65536], and its
-- two segments.
data Fill = Fill
  {{ fillStepX :: FillValue,
    fillStepY :: FillValue,
    fillRowStep :: FillValue,
    fillStart :: FillValue,
    segments :: Vec 2 Segment
  }}

slopeShift :: Int
slopeShift = {shift}

edges :: Vec EdgeCount Edge
edges ={haskell_vec(edge_lines, 2)}

fills :: Vec {len(fills)} Fill
fills ={haskell_vec(fill_lines, 2)}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("svg")
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--left", type=float, required=True)
    parser.add_argument("--top", type=float, required=True)
    parser.add_argument("--size", type=float, required=True)
    args = parser.parse_args()
    try:
        sys.stdout.write(
            generate(args.svg, args.width, args.height, args.left, args.top, args.size)
        )
    except GeometryError as e:
        sys.exit(f"flake-geometry: {e}")


if __name__ == "__main__":
    main()
