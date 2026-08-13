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

    # Matches GitButler's [profile.dev.package] override, inherited by tests.
    gix-merge = previousAttrs: {
      extraRustcOpts = (previousAttrs.extraRustcOpts or [ ]) ++ [ "-C debug-assertions=no" ];
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
  testInputs = [ pkgs.git ];
  testEnvironment.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

  # These suites rely on Git repositories or build layouts unavailable in the
  # Nix sandbox. Keep this list aligned with nixpkgs' GitButler package.
  disabledTestCrates = [
    "but-core"
    "but-rebase"
    "but-workspace"
    "but-hunk-dependency"
    "gitbutler-branch-actions"
    "gitbutler-stack"
    "gitbutler-edit-mode"
    "gitbutler-operating-modes"
    "gitbutler-project"
    "but-cherry-apply"
    "but-worktrees"
  ];

  checkFlags = lib.concatMap (test: [ "--skip=${test}" ]) [
    "test_is_network_error"
    "git_editor_takes_precedence"
    "migrations_in_parallel_with_processes"
    "pre_push_ignores_husky_core_hooks_path_when_disabled"
    "merge_first_branch_into_gb_local_and_verify_rebase"
    "json_output_with_dangling_commits"
    "two_dangling_commits_different_branches"
    "new_from_project_handle_uses_repo_gitdir"
    "new_from_project_handle_keeps_repo_cached"
    "track_directory_changes_after_rename"
  ];

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
