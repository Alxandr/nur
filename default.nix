# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `overlays`,
# `nixosModules`, `homeModules`, `darwinModules` and `flakeModules`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage

{
  pkgs ? import <nixpkgs> { },
}:

let
  inherit (pkgs) lib;

  packageDirs = lib.filterAttrs (
    dirName: type: type == "directory" && builtins.pathExists (./pkgs + "/${dirName}/default.nix")
  ) (builtins.readDir ./pkgs);

  discoveredPackages = lib.fix (
    self:
    lib.mapAttrs' (
      dirName: _:
      let
        pkg = lib.callPackageWith (pkgs // self) (./pkgs + "/${dirName}") { };
      in
      lib.nameValuePair dirName pkg
    ) packageDirs
  );

  specialAttrs = {
    # The `lib`, `overlays`, `nixosModules`, `homeModules`,
    # `darwinModules` and `flakeModules` names are special
    lib = import ./lib { inherit pkgs; }; # functions
    nixosModules = import ./nixos-modules; # NixOS modules
    # homeModules = { }; # Home Manager modules
    # darwinModules = { }; # nix-darwin modules
    # flakeModules = { }; # flake-parts modules
    overlays = import ./overlays; # nixpkgs overlays
  };
in
specialAttrs // discoveredPackages
