# This file describes your repository contents.
# It should return a set of nix derivations
# and optionally the special attributes `lib`, `overlays`,
# `nixosModules`, `homeModules`, `darwinModules` and `flakeModules`.
# It should NOT import <nixpkgs>. Instead, you should take pkgs as an argument.
# Having pkgs default to <nixpkgs> is fine though, and it lets you use short
# commands such as:
#     nix-build -A mypackage

let
  lock = builtins.fromJSON (builtins.readFile ./flake.lock);
  crate2nix = builtins.fetchTarball {
    url = "https://github.com/nix-community/crate2nix/archive/${lock.nodes.crate2nix.locked.rev}.tar.gz";
    sha256 = lock.nodes.crate2nix.locked.narHash;
  };

in
{
  pkgs ? import <nixpkgs> { },

  # Not expected to be passed in by users
  crate2nixTools ? import "${crate2nix}/tools.nix" { inherit pkgs; },
}:

let
  inherit (pkgs) lib;
  hostSystem = pkgs.stdenv.hostPlatform.system;
  nurLib = import ./lib {
    inherit pkgs crate2nixTools;
    packages = discoveredPackages;
  };

  packageDirs = lib.filterAttrs (
    dirName: type: type == "directory" && builtins.pathExists (./pkgs + "/${dirName}/default.nix")
  ) (builtins.readDir ./pkgs);

  supportsHostPlatform = pkg: !(pkg.meta ? platforms) || builtins.elem hostSystem pkg.meta.platforms;

  candidatePackages = lib.mapAttrs' (
    dirName: _:
    let
      pkg = lib.callPackageWith (
        pkgs
        // scopedPackages
        // {
          inherit nurLib;
          inherit (nurLib) nuget-global-tool-update-script;
        }
      ) (./pkgs + "/${dirName}") { };
    in
    lib.nameValuePair dirName pkg
  ) packageDirs;

  scopedPackages = lib.mapAttrs (
    dirName: pkg:
    if supportsHostPlatform pkg then
      pkg
    else
      throw "Package '${dirName}' is not supported on ${hostSystem}"
  ) candidatePackages;

  discoveredPackages = lib.filterAttrs (_: supportsHostPlatform) candidatePackages;

  specialAttrs = {
    # The `lib`, `overlays`, `nixosModules`, `homeModules`,
    # `darwinModules` and `flakeModules` names are special
    lib = nurLib; # functions
    nixosModules = import ./nixos-modules; # NixOS modules
    # homeModules = { }; # Home Manager modules
    # darwinModules = { }; # nix-darwin modules
    # flakeModules = { }; # flake-parts modules
    overlays = import ./overlays; # nixpkgs overlays
  };
in
specialAttrs // discoveredPackages
