# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# The on-chip 50 MHz RC oscillator, at its instance in nixos_logo.v.
create_clock -name clk -period 20 [get_pins {rcosc/CLKOUT}]
