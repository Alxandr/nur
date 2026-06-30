{
  pkgs,
  packages,
  crate2nixTools,
}:

let
  inherit (pkgs) lib;

in
{
  inherit (crate2nixTools) generatedCargoNix;
  crate2nix-package-update-script =
    {
      extraArgs ? [ ],
    }:
    [ (lib.getExe packages.update-crate2nix-package) ] ++ extraArgs;

  nuget-global-tool-update-script =
    {
      extraArgs ? [ ],
    }:
    [ (lib.getExe packages.update-nuget-global-tool) ] ++ extraArgs;
}
