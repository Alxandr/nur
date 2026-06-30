{
  pkgs,
  packages,
}:

let
  inherit (pkgs) lib;

in
{
  crate2nix-package-update-script = {
    __functor =
      self:
      {
        extraArgs ? [ ],
      }:
      [ (lib.getExe packages.update-crate2nix-package) ] ++ extraArgs;

    mkUpdateSource =
      attrs@{
        name,
        src,
        version,
      }:
      pkgs.stdenvNoCC.mkDerivation {
        pname = "${name}-src";
        inherit version src;

        dontUnpack = true;
        installPhase = "mkdir -p $out";
      }
      // attrs;
  };

  nuget-global-tool-update-script = {
    __functor =
      self:
      {
        extraArgs ? [ ],
      }:
      [ (lib.getExe packages.update-nuget-global-tool) ] ++ extraArgs;
  };
}
