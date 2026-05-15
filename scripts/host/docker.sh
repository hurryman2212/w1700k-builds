#!/usr/bin/env bash

#=================================================
# https://github.com/tete1030/openwrt-fastbuild-actions
# Description: FAST building OpenWrt with Github Actions and Docker!
# Lisence: MIT
# Author: Texot
#=================================================

_exit_if_empty() {
  local var_name="${1}"
  local var_value="${2}"
  local hint="${3:-}"

  if [ -n "${var_value}" ]; then
    return
  fi

  if [ -n "${hint}" ]; then
    echo "::error::Missing input ${var_name}: ${hint}" >&2
  else
    echo "::error::Missing input ${var_name}" >&2
  fi
  exit 1
}

check_required_input() {
  _exit_if_empty DK_REGISTRY "${DK_REGISTRY:-}"
  _exit_if_empty DK_USERNAME "${DK_USERNAME:-}"
  _exit_if_empty DK_PASSWORD "${DK_PASSWORD:-}" \
    "set secrets.GHCR_TOKEN with access to ghcr.io/${DK_USERNAME}/${BUILDER_NAME:-w1700k-builders}"
}

configure_docker() {
  echo '{
    "max-concurrent-downloads": 50,
    "max-concurrent-uploads": 50,
    "experimental": true
  }' | sudo tee /etc/docker/daemon.json
  sudo service docker restart
}

login_to_registry() {
  check_required_input
  echo "${DK_PASSWORD}" | docker login -u "${DK_USERNAME}" --password-stdin "${DK_REGISTRY}"
}

pull_image() {
  local IMAGE_TO_PULL="${1}"
  if [ -n "${IMAGE_TO_PULL}" ]; then
    (
      set +eo pipefail
      docker pull "${IMAGE_TO_PULL}" 2> >(tee /tmp/dockerpull_stderr.log >&2)
      ret_val=$?
      if [ ${ret_val} -ne 0 ] && ( grep -q "max depth exceeded" /tmp/dockerpull_stderr.log ) ; then
        echo "::error::Your image has exceeded maximum layer limit. Normally this should have already been automatically handled, but obviously haven't. You need to manually rebase or rebuild this builder, or delete it on the Docker Hub website." >&2
        exit 1
      fi
      exit $ret_val
    )
  else
    echo "No argument for pulling" >&2
    exit 1
  fi
}

docker_exec() {
  (
    local exec_envs=()
    IFS=$'\x20'
    for env_name in ${DK_EXEC_ENVS}; do
      exec_envs+=( -e "${env_name}=${!env_name}" )
    done
    docker exec -u 0 -i "${exec_envs[@]}" "$@"
  )
}

append_docker_exec_env() {
  for env_name in "$@"; do
    DK_EXEC_ENVS="${DK_EXEC_ENVS} ${env_name}"
  done
  DK_EXEC_ENVS="$(tr ' ' '\n' <<< "${DK_EXEC_ENVS}" | sort -u | tr '\n' ' ')"
}

create_remote_tag_alias() {
  docker buildx imagetools create -t "${2}" "${1}"
}

logout_from_registry() {
  docker logout "${DK_REGISTRY}"
}
