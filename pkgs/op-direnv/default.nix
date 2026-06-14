{
  lib,
  writeTextFile,
  shellcheck-minimal,
  ...
}:

writeTextFile {
  name = "op-direnv";
  executable = false;
  destination = "/share/op-direnv/direnvrc";
  allowSubstitutes = true;
  preferLocalBuild = false;

  text = builtins.readFile ./direnvrc;

  checkPhase = ''
    runHook preCheck
    ${lib.getExe shellcheck-minimal} $out/share/op-direnv/direnvrc
    runHook postCheck
  '';
}
