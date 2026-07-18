# w1700k builder

This project automates the process of building OpenWrt firmware images for the Gemtek W1700k

fastbuild adapted from https://github.com/tete1030/openwrt-fastbuild-actions

## Source composition

All builders read the single private `ubi2-oc-offload` branch. The source update
workflow composes it in this order:

1. Official `openwrt/openwrt` `main`
2. Patch-unique commits from OpenWRT-fanboy `offload`
3. The OpenWRT-fanboy `ubi2-oc` delta over `ubi2`
4. The contiguous commits at the source branch tip whose author email is
   `hurryman2212@gmail.com`

The updater walks backward from the source branch tip until the author email no
longer matches, then replays the discovered commits oldest-first on the newly
generated base. This keeps the personal-commit boundary self-contained in the
linear history without a mutable tag or a marker commit.

The source workflow is the only branch writer. The build workflow only fetches
the completed source branch.

## Automation

Only two manually triggered workflows are exposed in GitHub Actions:

- `update ubi2-oc-offload` only composes and updates the private source branch.
- `fastbuild ubi2-oc-offload` prepares current OpenWrt repository metadata,
  restores compile and download caches, reuses the incremental builder image,
  builds the already-composed source branch, publishes the release, and cleans
  superseded caches and images.

Fastbuild validates cache generations and the reusable-image schema/profile. It
first tries the incremental path, then retries from the public base with clean
compile state if that path fails. A final preparation retry also discards the
download cache when necessary. Only a successful build replaces the reusable
image and compile/download caches; repository metadata is validated and
repaired independently. The manual `clean_rebuild` input skips all restored
build state.

The source composition implementation remains in
`.github/scripts/sync-source.sh` so it can be syntax-checked and dry-run
outside GitHub Actions without exposing another workflow in the Actions UI.
