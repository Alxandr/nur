# crate2nix JSON workflow work

## Goal

Use crate2nix's experimental pre-resolved JSON workflow for `gitbutler-cli`, while keeping the generic implementation in the vendored `lib/crate2nix.nix` usable by existing packages such as `nil` and `crate2nix` itself.

The current implementation is functionally working. The main remaining task is reducing duplicate compilation/linking introduced by the unit/integration test split.

## Working-tree state

The relevant local changes are in:

- `lib/crate2nix.nix` — vendored JSON builder changes.
- `lib/default.nix` — NUR helper changes and workspace-test dependency closure.
- `TODO.md` — this handoff.

At the time this file was written, `lib/crate2nix.nix` had both staged and unstaged changes (`MM`), while `lib/default.nix` was staged (`M `). Do not assume the index and working tree contain identical versions.

The repository has an `AGENTS.md` safety rule: if a file unexpectedly becomes zero-length during editing, stop immediately and tell the user. Do not try to recover it automatically.

## Implemented changes

### Vendored `lib/crate2nix.nix`

The header directly after `# vendored from crate2nix` records the local deviations:

- Fixed non-root Git dependency source resolution. A Git checkout can contain multiple crates; the implementation locates the `Cargo.toml` whose package name matches the JSON crate.
- Git dependencies fetch required submodules.
- Replaced the old root-specific `binRootPackageId` / `testRootPackageId` graph construction with one canonical library graph.
- Every canonical crate derivation exposes `tests` and, when `crateBin` is non-empty, `bins`.
- Workspace-member and root-crate targets expose `buildLib`, `buildTests`, and conditional `buildBins`.
- Set `CARGO = lib.getExe cratePkgs.cargo` on every crate derivation. This is the workaround discussed in crate2nix issue #409: <https://github.com/nix-community/crate2nix/issues/409>.
- Filter direct self-referential dev dependencies from the external dependency list. Cargo uses patterns such as:

  ```toml
  [dev-dependencies]
  but-ctx = { path = ".", features = ["legacy"] }
  ```

  The feature is already present in `resolvedDefaultFeatures`; treating the self-reference as an external crate produced duplicate `but_ctx` rlibs.
- Split library-crate tests into two derivations:
  - `unitTests` hides the top-level `tests/` directory and compiles the local library test harness with dev dependencies.
  - `integrationTests` hides the local library source, adds canonical `buildLib` as an external dependency, and depends on `unitTests` through `nativeBuildInputs`.
  - Public `tests` points at `integrationTests` for library crates.

The unit/integration split fixes transitive dev-dependency cycles such as:

```text
but-graph integration tests
  -> but-testsupport
  -> canonical but-graph
```

Previously, the integration test also compiled a local `but-graph`, so Rust saw two different `but_graph::Graph` types. Integration tests now use the same canonical `but-graph` artifact as `but-testsupport`.

### `lib/default.nix`

- The helper accepts `workspaceMember ? pname`.
- The helper accepts `versionOverride ? null`; keep this name. The explicit GitButler release version is cleaner than attempting to repair it with an outer `overrideAttrs` alone.
- The old `updateResolvedJson` transformation was removed; checked-in JSON is consumed directly.
- `dependencyPackageIdsFor` computes the normal/build dependency closure with `builtins.genericClosure`.
- `workspaceDependenciesFor` filters that closure to workspace members.
- For the selected workspace member, `allTestMembers` contains its test target plus test targets for transitive workspace dependencies.
- Those test derivations are added to the final package's `nativeBuildInputs`, making successful test compilation a prerequisite of the package build.

Important: `buildRustCrate` test derivations compile test executables but do not execute them. The current wiring therefore checks test compilation, not test results.

## Failure history and fixes

1. Git dependencies below the repository root could not be resolved from JSON.
   - Fixed by finding the matching package inside the fetched Git tree.
2. `gix-testtools` failed at `env!("CARGO")`.
   - Fixed generically with `CARGO = lib.getExe cratePkgs.cargo`.
3. `but-ctx` tests failed with `E0464`, two `but_ctx` rlib candidates.
   - Cause: direct self dev-dependency.
   - Fixed by filtering `dep.packageId == packageId` from dev dependencies.
4. `but-graph` tests then failed with incompatible `but_graph::Graph` types.
   - Cause: transitive cycle through `but-testsupport`, with a local test library and canonical library in one process.
   - Fixed by the unit/integration split described above.

## Validation completed

All of the following succeeded with the current working-tree implementation:

```sh
nix-build -A gitbutler-cli --no-out-link
nix-build -A crate2nix -A nil --no-out-link
```

Smoke checks succeeded:

```text
but 0.22.0
crate2nix 0.15.0
nil unknown
```

The specific `but-graph` public test derivation also built independently before the full package build.

Formatting and whitespace checks succeeded:

```sh
nixfmt --check lib/crate2nix.nix lib/default.nix pkgs/gitbutler-cli/default.nix
git diff --check
```

No files were truncated.

## Remaining problem: duplicate work

The split is correct but expensive, especially for crates with large binaries such as `but`.

Current behavior includes:

1. `buildLib` compiles the canonical ordinary library.
2. `unitTests` compiles an ordinary local library and then its `--test` library harness.
3. `integrationTests`, when given `crateBin`, builds:
   - a normal binary for `CARGO_BIN_EXE_<name>`;
   - a binary `--test` harness;
   - integration-test executables.
4. `buildBins` builds the final ordinary binary again.

For `but`, the large CLI is therefore linked multiple times. The successful validation took long enough to make this very noticeable.

## Optimization plan

### 1. Reuse `buildBins` for `CARGO_BIN_EXE_*`

This is the best first optimization that may remain entirely inside `lib/crate2nix.nix`.

Have the integration-test derivation depend on the existing `bins` derivation. In `preBuild`, create:

```text
target/cargo-bin-exe/<name> -> ${bins}/bin/<name>
```

`buildRustCrate` already scans `target/cargo-bin-exe` and populates its `CARGO_BIN_EXE_ENV` array, so integration tests should be able to use the final binary instead of relinking a normal test-time copy.

Be careful about Nix recursion:

- `bins` depends on canonical `buildLib`.
- `integrationTests` may depend on `bins`.
- `bins` must never depend on `tests`.

### 2. Preserve binary unit-test harnesses

Simply passing `crateBin = [ ]` to integration tests prevents both the redundant normal binary and the binary `--test` harness. That is fast but silently stops compiling binary unit tests, so it is not a good final solution.

The desired behavior is:

- reuse `${bins}/bin/<name>` for `CARGO_BIN_EXE_*`;
- still compile each binary target once with `--test`;
- do not compile another normal binary inside the test derivation.

Unfortunately, nixpkgs `buildRustCrate` currently couples those two operations when `buildTests = true` and `crateBin` is non-empty.

Possible approaches:

- Preferred robust approach: add an upstream `buildRustCrate` option such as `buildBinsForTests ? true`, or a supplied `cargoBinExe` mapping, allowing the normal test-time binary build to be disabled while retaining binary test harnesses.
- File-local but brittle approach: use `overrideAttrs` to transform the generated `buildPhase`, removing only the `buildBinForTests` section. If doing this, assert that the expected source fragment exists so a nixpkgs update cannot silently make the replacement ineffective.

### 3. Avoid the ordinary local library in `unitTests`

`buildRustCrate` always runs its normal `build_lib` before `build_lib_test`. The ordinary local rlib is not needed when the derivation only exists to compile the unit-test harness.

The robust fix is another small upstream switch, conceptually:

```nix
buildLibrary ? true
buildLibraryTests ? buildTests
```

Then `unitTests` could set `buildLibrary = false` while keeping `buildLibraryTests = true`.

A local workaround again requires transforming the generated `buildPhase`. This should only be done with a guarded/asserted replacement because it depends on nixpkgs's `buildRustCrate` shell layout.

### 4. Avoid generating useless test derivations

`lib/default.nix` currently requests tests for every transitive workspace member. Some members may have neither inline unit tests nor integration tests, but the current JSON does not reliably describe inline `#[cfg(test)]` modules.

Do not use an unverified source heuristic that could silently omit tests. A future JSON schema extension recording Cargo test targets could safely reduce this work, but inline unit tests still require explicit metadata or conservative compilation.

## Suggested next steps

1. Re-run the three package builds on the faster machine to establish the same baseline.
2. Inspect the exact `buildPhase` produced for a binary integration-test derivation and confirm when `target/cargo-bin-exe` is scanned relative to `preBuild`.
3. Prototype reusing `bins` through symlinks in `target/cargo-bin-exe`.
4. Verify `CARGO_BIN_EXE_but` points to the reused binary during integration-test compilation.
5. Retain binary `--test` harness compilation; do not settle on `crateBin = [ ]` unless explicitly accepting lost coverage.
6. Decide whether the remaining two switches belong in nixpkgs `buildRustCrate`, crate2nix, or a guarded local `buildPhase` transformation.
7. Rebuild:

   ```sh
   nix-build -A gitbutler-cli --no-out-link
   nix-build -A crate2nix -A nil --no-out-link
   ```

8. Repeat smoke, formatting, evaluation, and `git diff --check` checks.

## Useful implementation details

In the nixpkgs version used during this work, the relevant implementation was under:

```text
pkgs/build-support/rust/build-rust-crate/build-crate.nix
pkgs/build-support/rust/build-rust-crate/lib.sh
```

Behavior observed there:

- `build_lib` sets `EXTRA_LIB` to the newly compiled local rlib.
- `build_lib_test` calls `build_lib` with `--test`.
- With `buildTests`, real binaries are first written to `target/cargo-bin-exe`.
- That directory is then scanned to populate `CARGO_BIN_EXE_ENV`.
- Binary test harnesses and integration tests are compiled afterward.

This ordering is why hiding the local library for integration tests works, and why pre-populating `target/cargo-bin-exe` appears promising.
