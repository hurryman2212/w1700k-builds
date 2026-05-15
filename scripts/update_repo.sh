#!/bin/bash

#=================================================
# https://github.com/tete1030/openwrt-fastbuild-actions
# Description: FAST building OpenWrt with Github Actions and Docker!
# Lisence: MIT
# Author: Texot
#=================================================

set -eo pipefail

link_bin() {
  local BIN_DIR="${OPENWRT_COMPILE_DIR}/bin"
  local BIN_MOUNT_POINT="${BUILDER_BIN_DIR}"

  if mountpoint "${BIN_MOUNT_POINT}" ; then
    if [[ ! -L "${BIN_DIR}" || ! -d "${BIN_DIR}" || "$(readlink "${BIN_DIR}")" != "${BIN_MOUNT_POINT}" ]]; then
      echo "'bin' link does not exist, creating"
      rm -rf "${BIN_DIR}" || true
      ln -sf "${BIN_MOUNT_POINT}" "${BIN_DIR}"
    fi
  else
    echo "::error::'${BIN_MOUNT_POINT}' not mounted!" >&2
    exit 1
  fi
}

write_build_info() {
  mkdir -p files

  if git fetch --no-tags https://github.com/openwrt/openwrt.git \
      "+refs/heads/main:refs/remotes/openwrt/main" &&
     git rev-parse --verify refs/remotes/openwrt/main >/dev/null 2>&1; then
    git log --oneline --no-decorate \
      refs/remotes/openwrt/main.."${REPO_BRANCH}" > files/build_info
  else
    echo "(failed to fetch openwrt/main for build info)" > files/build_info
  fi

  if [ ! -s files/build_info ]; then
    echo "(no commits ahead of openwrt/main)" > files/build_info
  fi

  cp files/build_info "${BUILDER_BIN_DIR}" 2>/dev/null || true
}

if [ -z "${OPENWRT_COMPILE_DIR}" ] || [ -z "${OPENWRT_CUR_DIR}" ] || [ -z "${OPENWRT_SOURCE_DIR}" ]; then
  echo "::error::'OPENWRT_COMPILE_DIR', 'OPENWRT_CUR_DIR' or 'OPENWRT_SOURCE_DIR' is empty" >&2
  exit 1
fi

if [ -z "${REPO_URL}" ] || [ -z "${REPO_BRANCH}" ]; then
  echo "::error::'REPO_URL' or 'REPO_BRANCH' is empty" >&2
  exit 1
fi

if [ "x${TEST}" = "x1" ]; then
  mkdir -p "${OPENWRT_COMPILE_DIR}" || true
  link_bin
  exit 0
fi

# The following will reset all non-building changes,
# including some not managed by git, preseve timestamps
# of unchanged files (even if their timestamp changed)
# and make changed files' timestamps most recent

if [ "x${OPENWRT_CUR_DIR}" != "x${OPENWRT_COMPILE_DIR}" ] && [ -d "${OPENWRT_COMPILE_DIR}/.git" ] && [ "x${OPT_UPDATE_REPO}" != "x1" ]; then
  git clone "${OPENWRT_COMPILE_DIR}" "${OPENWRT_CUR_DIR}"
  git -C "${OPENWRT_CUR_DIR}" remote set-url origin "${REPO_URL}"
  git -C "${OPENWRT_CUR_DIR}" config remote.origin.tagOpt --no-tags
  git -C "${OPENWRT_CUR_DIR}" fetch --no-tags origin "${REPO_BRANCH}"
  git -C "${OPENWRT_CUR_DIR}" checkout -B "${REPO_BRANCH}" "origin/${REPO_BRANCH}"
  git -C "${OPENWRT_CUR_DIR}" reset --hard "origin/${REPO_BRANCH}"
  cd "${OPENWRT_CUR_DIR}"
  write_build_info
 else
#  git clone -b "${REPO_BRANCH}" "${REPO_URL}" "${OPENWRT_CUR_DIR}"
  mkdir -p "${OPENWRT_CUR_DIR}"
  cd "${OPENWRT_CUR_DIR}"
  git init
  git remote add origin "${REPO_URL}" 2>/dev/null || git remote set-url origin "${REPO_URL}"
  git config remote.origin.tagOpt --no-tags
  git fetch --no-tags origin "${REPO_BRANCH}"
  git checkout -B "${REPO_BRANCH}" "origin/${REPO_BRANCH}"
  git reset --hard "origin/${REPO_BRANCH}"
  write_build_info
fi

link_bin
