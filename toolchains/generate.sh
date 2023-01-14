#!/usr/bin/env bash
set -xeu

script_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ct_version=$(cat "${script_dir}/ct-ng-version")
time=$(cat "${script_dir}/time")
directory=.

positional_args=()

while [[ $# -gt 0 ]]; do
  case $1 in
  -C | --directory)
    directory="$2"
    shift # past argument
    shift # past value
    ;;
  -*)
    echo "Unknown option $1"
    exit 1
    ;;
  *)
    positional_args+=("$1") # save positional arg
    shift                   # past argument
    ;;
  esac
done

set -- "${positional_args[@]}" # restore positional parameters

directory=$(realpath "${directory}")

"${script_dir}/../ct-ng-manager" -C "${directory}" "${ct_version}"
# shellcheck source=/dev/null
. "${directory}/installs/crosstool-ng-${ct_version}/activate"

_ct_ng() {
    echo ${directory}/installs/crosstool-ng-${ct_version}/bin/ct-ng
}

_extend_path() {
    local path=${1}
    local to_add=${2}
    [[ ":${path}:" != *":${to_add}:"* ]] && path="${path}:${to_add}"
    echo "${path}"
}

_extend_path_for_canadian() {
    local path=${1}
    local toolchain=${2}
    local tuple
    local host_toolchain
    if [[ "${toolchain}" != *~* ]]; then
        echo "${path}"
        return
    fi
    IFS='~' read -ra tuple <<< "${toolchain}"
    host_toolchain=${tuple[0]}
    host_toolchain_bindir=$(_toolchain_dir "${host_toolchain}")/bin
    _extend_path "${path}" "${host_toolchain_bindir}"
}

_defconfig_path() {
    local name=${1}
    echo "${script_dir}/${name}.defconfig"
}

_toolchain_prefix() {
    local name=${1}
    echo "${directory}/builds/${name}"
}

_toolchain_dir() {
    local name=${1}
    toolchain_prefix=$(_toolchain_prefix ${name})
    echo "${toolchain_prefix}/${name}"
}

_generate() {
    local config=${1}
    local DEFCONFIG
    local CT_PREFIX=${directory}/builds/${config}
    local CT_LOCAL_TARBALLS_DIR
    local target_dir
    local workdir
    local path
    target_dir=$(_toolchain_prefix "${config}")
    DEFCONFIG=$(_defconfig_path "${config}")
    mkdir -p "${target_dir}"
    rm -f ./tgt
    ln -s "${target_dir}"  ./tgt
    CT_PREFIX=$(realpath ./tgt)
    CT_LOCAL_TARBALLS_DIR=$(realpath "${directory}/external")
    workdir=$(pwd)
    path=$(_extend_path_for_canadian "${PATH}" "${config}")
    mkdir -p "${CT_PREFIX}"
    cd "${CT_PREFIX}"
    DEFCONFIG="${DEFCONFIG}" \
        $(_ct_ng) defconfig
    # hack
    sed -i 's/CT_ZLIB_VERSION="1.2.12"/CT_ZLIB_VERSION="1.2.13"/' "${CT_PREFIX}/.config"
    CT_PREFIX="${CT_PREFIX}" \
        CT_LOCAL_TARBALLS_DIR="${CT_LOCAL_TARBALLS_DIR}" \
        PATH="${path}" \
        $(_ct_ng) -j "$(nproc)" build
    cd "${workdir}"
    rm -f ./tgt
}

_pack() {
    local name=${1}
    local time=${2}
    local toolchain
    toolchain=$(_toolchain_dir "${name}")
    tar -c \
        --sort=name \
        --mtime="UTC ${time}" \
        --owner=0 \
        --group=0 \
        --numeric-owner \
        -C "${toolchain}" . \
        | gzip -n > "${directory}/${name}.tar.gz"
}

_generate "${1}"
_pack "${1}" "${time}"