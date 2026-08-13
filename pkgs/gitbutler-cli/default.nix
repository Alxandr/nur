{
  pkgs,
  nurLib,
  lib,
  fetchFromGitHub,
  fetchgit,
  libgit2,
  openssl,
  pkg-config,
  runCommand,
  zlib,
}:

let
  version = "0.22.0";

  updateSrc = fetchFromGitHub {
    owner = "gitbutlerapp";
    repo = "gitbutler";
    tag = "release/${version}";
    hash = "sha256-iiUgqpoLixyBG+MKQZBQbt4aCsRPrM8lPmwJHReAgPk=";
  };

  rawResolved = builtins.fromJSON (builtins.readFile ./Cargo.json);

  fetchGitSource =
    url:
    let
      crateInfo = lib.findFirst (
        crateInfo: (crateInfo.source.type or "local") == "git" && crateInfo.source.url == url
      ) (throw "Missing Git crate source: ${url}") (lib.attrValues rawResolved.crates);
    in
    fetchgit {
      inherit url;
      inherit (crateInfo.source) rev;
      inherit (crateInfo) sha256;
    };

  gitSources = {
    gitoxide = fetchGitSource "https://github.com/GitoxideLabs/gitoxide";
    git2 = fetchGitSource "https://github.com/gitbutlerapp/git2-rs";
    gitMeta = fetchGitSource "https://github.com/git-meta/git-meta";
    minus = fetchGitSource "https://github.com/arijit79/minus";
    notify = fetchGitSource "https://github.com/notify-rs/notify";
    posthog = fetchGitSource "https://github.com/gitbutlerapp/posthog-rs";
    trafficlights = fetchGitSource "https://github.com/gitbutlerapp/tauri-plugin-trafficlights-positioner";
  };

  src = runCommand "gitbutler-${version}-crate2nix-source" { } ''
    cp -a ${updateSrc} "$out"
    chmod u+w "$out"
    mkdir "$out/.crate2nix-git"
    cp -a ${gitSources.gitoxide} "$out/.crate2nix-git/gitoxide"
    cp -a ${gitSources.git2} "$out/.crate2nix-git/git2"
    cp -a ${gitSources.gitMeta} "$out/.crate2nix-git/git-meta"
    cp -a ${gitSources.minus} "$out/.crate2nix-git/minus"
    cp -a ${gitSources.notify} "$out/.crate2nix-git/notify"
    cp -a ${gitSources.posthog} "$out/.crate2nix-git/posthog"
    cp -a ${gitSources.trafficlights} "$out/.crate2nix-git/trafficlights"
  '';

  gitCratePath =
    crateInfo:
    let
      url = crateInfo.source.url;
      crateName = crateInfo.crateName;
    in
    if url == "https://github.com/GitoxideLabs/gitoxide" then
      ".crate2nix-git/gitoxide/${if crateName == "gix-testtools" then "tests/tools" else crateName}"
    else if url == "https://github.com/gitbutlerapp/git2-rs" then
      ".crate2nix-git/git2${if crateName == "git2" then "" else "/${crateName}"}"
    else if url == "https://github.com/git-meta/git-meta" then
      ".crate2nix-git/git-meta/crates/${crateName}"
    else if url == "https://github.com/arijit79/minus" then
      ".crate2nix-git/minus"
    else if url == "https://github.com/notify-rs/notify" then
      ".crate2nix-git/notify/${crateName}"
    else if url == "https://github.com/gitbutlerapp/posthog-rs" then
      ".crate2nix-git/posthog"
    else if url == "https://github.com/gitbutlerapp/tauri-plugin-trafficlights-positioner" then
      ".crate2nix-git/trafficlights"
    else
      throw "Unknown Git crate source: ${url}";

  resolvedJson = builtins.toFile "gitbutler-${version}-Cargo.json" (
    builtins.toJSON (
      rawResolved
      // {
        crates = lib.mapAttrs (
          packageId: crateInfo:
          crateInfo
          // {
            # The vendored builder compiles every declared binary. Cargo only
            # builds binaries for the selected workspace package here.
            crateBin = if packageId == rawResolved.workspaceMembers.but then crateInfo.crateBin or [ ] else [ ];
          }
          // lib.optionalAttrs ((crateInfo.source.type or "local") == "git") {
            source = {
              type = "local";
              path = gitCratePath crateInfo;
            };
          }
        ) rawResolved.crates;
      }
    )
  );

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
    updateSrc
    version
    defaultCrateOverrides
    resolvedJson
    ;
  pname = "gitbutler-cli";
  workspaceMember = "but";

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
