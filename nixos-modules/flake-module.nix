# SPDX-FileCopyrightText: 2026 Mika Tammi
# SPDX-License-Identifier: MIT
#
# NixOS modules. Each one adds overlays.default to the system's nixpkgs,
# so its packages come from the user's nixpkgs and unfree policy.
{
  self,
  inputs,
  ...
}: let
  # The `key` makes NixOS import the overlay once, however many of our
  # modules are used.
  overlay = {
    key = "libero-flake#overlay";
    nixpkgs.overlays = [self.overlays.default];
  };
  module = file: {imports = [overlay file];};
in {
  flake.nixosModules = {
    libero = module ./libero.nix;
    libero-license = module ./libero-license.nix;
    default.imports = [
      self.nixosModules.libero
      self.nixosModules.libero-license
    ];
  };

  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: {
    checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      nixos-libero = pkgs.callPackage ./tests/libero.nix {
        inherit (inputs.nixpkgs.lib) nixosSystem;
        inherit system;
        module = self.nixosModules.libero;
      };
      nixos-libero-license = pkgs.callPackage ./tests/libero-license.nix {
        inherit (inputs.nixpkgs.lib) nixosSystem;
        inherit system;
        module = self.nixosModules.libero-license;
      };
    };
  };
}
