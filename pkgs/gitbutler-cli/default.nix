{
  pkgs,
  nurLib,
  lib,
  fetchFromGitHub,
  libgit2,
  openssl,
  pkg-config,
  zlib,
}:

let
  version = "0.22.0";

  src = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    tag = "release/${version}";
    hash = "sha256-iiUgqpoLixyBG+MKQZBQbt4aCsRPrM8lPmwJHReAgPk=";
  };

  libgit2Experimental = libgit2.override {
    withExperimentalSha256 = true;
  };

  defaultCrateOverrides = pkgs.defaultCrateOverrides // {
    but = previousAttrs: {
      VERSION = version;
    };

    libgit2-sys = previousAttrs: {
      LIBGIT2_SYS_USE_PKG_CONFIG = true;
      nativeBuildInputs = (previousAttrs.nativeBuildInputs or [ ]) ++ [ pkg-config ];
      buildInputs = (previousAttrs.buildInputs or [ ]) ++ [
        libgit2Experimental
        openssl
        zlib
      ];
    };

    openssl-sys =
      previousAttrs:
      (pkgs.defaultCrateOverrides.openssl-sys previousAttrs)
      // {
        OPENSSL_NO_VENDOR = true;
      };

    rmcp = previousAttrs: {
      CARGO_CRATE_NAME = "rmcp";
    };

    tauri = previousAttrs: {
      postInstall = (previousAttrs.postInstall or "") + ''
        # Tauri uses ':' in some Cargo metadata keys. buildRustCrate writes
        # these to an env file, but ':' is not valid in shell identifiers.
        if [[ -f "$lib/env" ]]; then
          sed -i '/^export [^=]*:/d' "$lib/env"
        fi
      '';
    };
  };

in
nurLib.crate2nix {
  inherit
    src
    defaultCrateOverrides
    ;
  pname = "gitbutler-cli";
  workspaceMember = "but";
  versionOverride = version;
  resolvedJson = ./Cargo.json;

  updateScriptExtraArgs = [
    "--use-github-releases"
    "--version-regex"
    "release/(.*)"
    "--"
    "--default-features"
  ];

  meta = {
    description = "Command-line interface for GitButler";
    homepage = "https://gitbutler.com";
    license = lib.licenses.fsl11Mit;
    platforms = lib.platforms.linux;
    mainProgram = "but";
  };
}
