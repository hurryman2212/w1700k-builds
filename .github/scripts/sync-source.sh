#!/usr/bin/env bash

set -euo pipefail

REMOTE_REPOSITORY="${REMOTE_REPOSITORY:-hurryman2212/OpenW1700k-test}"
OPENWRT_REPOSITORY="${OPENWRT_REPOSITORY:-openwrt/openwrt}"
FANBOY_REPOSITORY="${FANBOY_REPOSITORY:-OpenWRT-fanboy/OpenW1700k}"
SOURCE_BRANCH="${SOURCE_BRANCH:-ubi2-oc-offload}"
OPENWRT_BRANCH="${OPENWRT_BRANCH:-main}"
FANBOY_OFFLOAD_BRANCH="${FANBOY_OFFLOAD_BRANCH:-offload}"
FANBOY_UBI2_BRANCH="${FANBOY_UBI2_BRANCH:-ubi2}"
FANBOY_OC_BRANCH="${FANBOY_OC_BRANCH:-ubi2-oc}"
PERSONAL_AUTHOR_EMAIL="${PERSONAL_AUTHOR_EMAIL:-hurryman2212@gmail.com}"
FORCE_RECOMPOSE="${FORCE_RECOMPOSE:-0}"
DRY_RUN="${DRY_RUN:-0}"

if [ -z "${REMOTE_URL:-}" ]; then
  : "${REPO_SECRET:?REPO_SECRET must contain a token with access to the private source repository}"
  REMOTE_URL="https://x-access-token:${REPO_SECRET}@github.com/${REMOTE_REPOSITORY}.git"
fi
OPENWRT_URL="${OPENWRT_URL:-https://github.com/${OPENWRT_REPOSITORY}.git}"
FANBOY_URL="${FANBOY_URL:-https://github.com/${FANBOY_REPOSITORY}.git}"

is_true() {
  case "${1,,}" in
    1 | true | yes) return 0 ;;
    *) return 1 ;;
  esac
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

cherry_pick_generated_commit() {
  local commit="${1}"

  printf 'Applying generated-source commit %s: %s\n' \
    "${commit}" "$(git show -s --format=%s "${commit}")"
  if ! git cherry-pick --empty=drop "${commit}"; then
    git status --short >&2
    die "generated-source commit ${commit} needs a manual conflict resolution"
  fi
}

cherry_pick_personal_commit() {
  local commit="${1}"

  printf 'Replaying personal commit %s: %s\n' \
    "${commit}" "$(git show -s --format=%s "${commit}")"
  if ! git cherry-pick --empty=drop "${commit}"; then
    git status --short >&2
    die "personal commit ${commit} needs a manual conflict resolution"
  fi
}

source_dir="$(mktemp -d)"
trap 'rm -rf "${source_dir}"' EXIT

git init -q "${source_dir}"
cd "${source_dir}"
git remote add origin "${REMOTE_URL}"
git remote add openwrt "${OPENWRT_URL}"
git remote add fanboy "${FANBOY_URL}"
git config remote.origin.tagOpt --no-tags
git config remote.openwrt.tagOpt --no-tags
git config remote.fanboy.tagOpt --no-tags
git config user.name 'github-actions[bot]'
git config user.email 'github-actions[bot]@users.noreply.github.com'

git fetch --no-tags origin \
  "+refs/heads/${SOURCE_BRANCH}:refs/remotes/origin/${SOURCE_BRANCH}"
git fetch --no-tags openwrt \
  "+refs/heads/${OPENWRT_BRANCH}:refs/remotes/openwrt/${OPENWRT_BRANCH}"
git fetch --no-tags fanboy \
  "+refs/heads/${FANBOY_OFFLOAD_BRANCH}:refs/remotes/fanboy/${FANBOY_OFFLOAD_BRANCH}" \
  "+refs/heads/${FANBOY_UBI2_BRANCH}:refs/remotes/fanboy/${FANBOY_UBI2_BRANCH}" \
  "+refs/heads/${FANBOY_OC_BRANCH}:refs/remotes/fanboy/${FANBOY_OC_BRANCH}"

origin_ref="refs/remotes/origin/${SOURCE_BRANCH}"
openwrt_ref="refs/remotes/openwrt/${OPENWRT_BRANCH}"
offload_ref="refs/remotes/fanboy/${FANBOY_OFFLOAD_BRANCH}"
ubi2_ref="refs/remotes/fanboy/${FANBOY_UBI2_BRANCH}"
oc_ref="refs/remotes/fanboy/${FANBOY_OC_BRANCH}"

origin_sha="$(git rev-parse "${origin_ref}")"
openwrt_sha="$(git rev-parse "${openwrt_ref}")"
offload_sha="$(git rev-parse "${offload_ref}")"
oc_sha="$(git rev-parse "${oc_ref}")"

: "${PERSONAL_AUTHOR_EMAIL:?PERSONAL_AUTHOR_EMAIL must not be empty}"

personal_commits_newest_first=()
cursor="${origin_sha}"
while [ "$(git show -s --format=%ae "${cursor}")" = \
  "${PERSONAL_AUTHOR_EMAIL}" ]; do
  read -r -a commit_line <<<"$(git rev-list --parents -n 1 "${cursor}")"
  [ "${#commit_line[@]}" -eq 2 ] || die \
    "personal commit suffix contains a root or merge commit ${cursor}"
  personal_commits_newest_first+=("${cursor}")
  cursor="${commit_line[1]}"
done
previous_base_sha="${cursor}"

personal_commits=()
for ((i = ${#personal_commits_newest_first[@]} - 1; i >= 0; i--)); do
  personal_commits+=("${personal_commits_newest_first[i]}")
done

printf 'Found %d contiguous personal commits authored by %s\n' \
  "${#personal_commits[@]}" "${PERSONAL_AUTHOR_EMAIL}"
printf 'Previous generated-base boundary: %s (%s)\n' \
  "${previous_base_sha}" "$(git show -s --format=%s "${previous_base_sha}")"

git merge-base "${openwrt_ref}" "${offload_ref}" >/dev/null ||
  die "OpenWrt main and fanboy offload have no merge base"
offload_base="$(git merge-base "${openwrt_ref}" "${offload_ref}")"

mapfile -t offload_merges < <(
  git rev-list --min-parents=2 "${offload_base}..${offload_ref}"
)
[ "${#offload_merges[@]}" -eq 0 ] || die \
  "fanboy offload delta contains merge commits; review its new topology manually"

declare -A unique_offload_commits=()
while read -r sign commit _subject; do
  if [ "${sign}" = + ]; then
    unique_offload_commits["${commit}"]=1
  fi
done < <(git cherry -v "${openwrt_ref}" "${offload_ref}")

mapfile -t offload_commits < <(
  git rev-list --reverse "${offload_base}..${offload_ref}"
)

git checkout -q --detach "${openwrt_ref}"
for commit in "${offload_commits[@]}"; do
  if [ -n "${unique_offload_commits[${commit}]:-}" ]; then
    cherry_pick_generated_commit "${commit}"
  fi
done

git merge-base --is-ancestor "${ubi2_ref}" "${oc_ref}" || die \
  "fanboy ${FANBOY_OC_BRANCH} is no longer based on ${FANBOY_UBI2_BRANCH}"
mapfile -t oc_commits < <(
  git rev-list --reverse --first-parent "${ubi2_ref}..${oc_ref}"
)
[ "${#oc_commits[@]}" -gt 0 ] || die \
  "fanboy ${FANBOY_OC_BRANCH} contains no OC delta over ${FANBOY_UBI2_BRANCH}"
for commit in "${oc_commits[@]}"; do
  cherry_pick_generated_commit "${commit}"
done
new_base_sha="$(git rev-parse HEAD)"

for commit in "${personal_commits[@]}"; do
  cherry_pick_personal_commit "${commit}"
done

[ -z "$(git status --porcelain=v1)" ] || die \
  "composition left uncommitted changes"
new_sha="$(git rev-parse HEAD)"

base_tree_unchanged=0
final_tree_unchanged=0
[ "$(git rev-parse "${new_base_sha}^{tree}")" = \
  "$(git rev-parse "${previous_base_sha}^{tree}")" ] && base_tree_unchanged=1
[ "$(git rev-parse 'HEAD^{tree}')" = \
  "$(git rev-parse "${origin_ref}^{tree}")" ] && final_tree_unchanged=1

printf '\nComposition complete:\n'
printf '  OpenWrt main:      %s\n' "${openwrt_sha}"
printf '  fanboy offload:    %s (%d unique commits applied)\n' \
  "${offload_sha}" "${#unique_offload_commits[@]}"
printf '  fanboy ubi2-oc:    %s (%d OC commits applied)\n' \
  "${oc_sha}" "${#oc_commits[@]}"
printf '  generated base:    %s\n' "${new_base_sha}"
printf '  previous base:     %s\n' "${previous_base_sha}"
printf '  personal author:   %s\n' "${PERSONAL_AUTHOR_EMAIL}"
printf '  personal commits:  %d\n' "${#personal_commits[@]}"
printf '  final source:      %s\n' "${new_sha}"

if [ "${base_tree_unchanged}" -eq 1 ] &&
  [ "${final_tree_unchanged}" -eq 1 ] &&
  ! is_true "${FORCE_RECOMPOSE}"; then
  printf 'Generated and final source trees are unchanged; nothing to update.\n'
  exit 0
fi

if is_true "${DRY_RUN}"; then
  printf 'Dry run requested; no refs were pushed.\n'
  exit 0
fi

git push \
  --force-with-lease="refs/heads/${SOURCE_BRANCH}:${origin_sha}" \
  origin \
  "HEAD:refs/heads/${SOURCE_BRANCH}"
