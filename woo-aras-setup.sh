#!/bin/bash
#
# Copyright (C) 2021 Hasan CALISIR <hasan.calisir@psauxit.com>
# Distributed under the GNU General Public License, version 2.0.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# What is doing this script exactly?
# -This is a wrapper/helper script for woocommerce and ARAS cargo integration setup.
# -This script prepares environment for ARAS cargo integration.

# Set color
# =====================================================================
setup_terminal () {
  green=""; red=""; reset=""; cyan=""; magenta=""; yellow=""; TPUT_RESET="";
  TPUT_GREEN=""; TPUT_CYAN=""; TPUT_DIM=""; TPUT_BOLD=""; m_tab='  '; BC=$'\e[32m'
  EC=$'\e[0m'; TPUT_BGRED=""; TPUT_WHITE=""; TPUT_BGGREEN=""
  test -t 2 || return 1
  if command -v tput > /dev/null 2>&1; then
    if [[ $(($(tput colors 2> /dev/null))) -ge 8 ]]; then
      green="$(tput setaf 2)"; red="$(tput setaf 1)"; reset="$(tput sgr0)"; cyan="$(tput setaf 6)"
      magenta="$(tput setaf 5)"; yellow="$(tput setaf 3)"; TPUT_RESET="$(tput sgr 0)"
      TPUT_GREEN="$(tput setaf 2)"; TPUT_CYAN="$(tput setaf 6)"; TPUT_DIM="$(tput dim)"
      TPUT_BOLD="$(tput bold)"; TPUT_BGRED="$(tput setab 1)"; TPUT_RESET="$(tput sgr 0)"
      TPUT_WHITE="$(tput setaf 7)"; TPUT_BGGREEN="$(tput setab 2)"; TPUT_RESET="$(tput sgr 0)"
    fi
  fi
  return 0
}
setup_terminal || echo > /dev/null

# @EARLY CRITICAL CONTROLS
# =====================================================================
# Early check bash exists and met version requirement
# This function written in POSIX for portability but rest of script is bashify
detect_bash5 () {
  local my_bash
  my_bash="$(command -v bash 2> /dev/null)"
  if [ -z "${BASH_VERSION}" ]; then
    # we don't run under bash
    if [ -n "${my_bash}" ] && [ -x "${my_bash}" ]; then
      # shellcheck disable=SC2016
      bash_ver=$(${my_bash} -c 'echo "${BASH_VERSINFO[0]}"')
    fi
  else
    # we run under bash
    bash_ver="${BASH_VERSINFO[0]}"
  fi

  if [ -z "${bash_ver}" ]; then
    return 1
  elif [ $((bash_ver)) -lt 5 ]; then
    return 1
  fi
  return 0
}

# Test connection for package installation
test_connection () {
  if ! : >/dev/tcp/8.8.8.8/53; then
    echo -e "\n${red}*${reset} ${red}There is no internet connection.${reset}"
    echo "${cyan}${m_tab}#####################################################${reset}"
    echo -e "\n${m_tab}${red}These are the missing packages I need:${reset}"
    echo -e "\n${m_tab}${magenta}${#missing_deps[*]}${reset}"
    exit 1
  fi
}

if ! detect_bash5; then
  echo -e "\n${red}*${reset} ${red}FATAL ERROR: Need BASH v5+${reset}"
  echo -e "${cyan}${m_tab}#####################################################${reset}\n"
  exit 1
fi

# Prevent errors cause by uncompleted upgrade
# Detect to make sure the entire script is available, fail if the script is missing contents
if [[ "$(tail -n 1 "${0}" | head -n 1 | cut -c 1-7)" != "exit \$?" ]]; then
  echo -e "\n${red}*${reset} ${red}Script is incomplete${reset}"
  echo -e "${cyan}${m_tab}#####################################################${reset}\n"
  exit 1
fi

# Check OS is supported
if [[ "$(uname -s)" != "Linux" ]]; then
  echo -e "\n${red}*${reset} ${red}Unsupported operating system: $OSTYPE${reset}"
  echo -e "${cyan}${m_tab}#####################################################${reset}\n"
  exit 1
fi

usage () {
  echo -e "\n${red}*${reset} ${red}Try to run script with root or sudo privileged user.${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo -e "${m_tab}${magenta}sudo ./woo-aras-setup.sh${reset}\n"
}

# Display usage for necessary privileges
[[ ! $SUDO_USER && $EUID -ne 0 ]] && { usage; exit 1; }

# @GLOBAL VARIABLES
# =====================================================================
export new_user="wooaras"
export setup_key="gajVVK2zXo"
export working_path="/home/${new_user}/scripts/woocommerce-aras-kargo"
git_repo="https://github.com/hsntgm/woocommerce-aras-kargo.git"
sudoers_file="/etc/sudoers"
pass_file="/etc/passwd"
portage_php="/etc/portage/package.use/woo_php"

# Use for env operations errors
die () {
  printf >&2 "%s ABORTED %s %s \n\n" "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD}" "${TPUT_RESET}" "${*}"
  userdel "${new_user}" >/dev/null 2>&1
  rm -r "${working_path:?}"
  exit 1
}

# Use for other errors
fatal () {
  echo ""
  printf >&2 "${m_tab}%s ABORTED %s %s \n\n" "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD}" "${TPUT_RESET}" "${*}"
  echo ""
  exit 1
}

# Use for completed tasks
done_ () {
  echo ""
  printf >&2 "${m_tab}%s DONE %s %s" "${TPUT_BGGREEN}${TPUT_WHITE}${TPUT_BOLD}" "${TPUT_RESET}" "${*}"
  echo ""
}

# Fake progress
spinner () {
  sleep 2 &
  sleep_pid=$!
  spin='-\|/'

  i=0
  while kill -0 $sleep_pid 2>/dev/null
  do
    i=$(( (i+1) %4 ))
    printf "\r${m_tab}${green}${spin:$i:1}${reset}"
    sleep .1
  done
  echo ""
}

wooaras_banner () {
  local l1="  ^" \
    l2="  |.-.   .-.   .-.   .-.   .-.   .-.   .-.   .-.   .-.   .-.   .-.   .-.   .-" \
    l3="  |   '-'   '-'   '-'   '-'   '-'   '-'   '-'   '-'   '-'   '-'   '-'   '-'  " \
    l4="  +----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+--->" \
    sp="                                                                              " \
    woo_aras="WooCommerce-Aras Cargo Setup" start end msg="${*}" chartcolor="${TPUT_DIM}"

  [ ${#msg} -lt ${#woo_aras} ] && msg="${msg}${sp:0:$((${#woo_aras} - ${#msg}))}"
  [ ${#msg} -gt $((${#l2} - 20)) ] && msg="${msg:0:$((${#l2} - 23))}..."

  start="$((${#l2} / 2 - 4))"
  [ $((start + ${#msg} + 4)) -gt ${#l2} ] && start=$((${#l2} - ${#msg} - 4))
  end=$((start + ${#msg} + 4))

  echo >&2
  echo >&2 "${chartcolor}${l1}${TPUT_RESET}"
  echo >&2 "${chartcolor}${l2:0:start}${sp:0:2}${TPUT_RESET}${TPUT_BOLD}${TPUT_GREEN}${woo_aras}${TPUT_RESET}${chartcolor}${sp:0:$((end - start - 2 - ${#woo_aras}))}${l2:end:$((${#l2} - end))}${TPUT_RESET}"
  echo >&2 "${chartcolor}${l3:0:start}${sp:0:2}${TPUT_RESET}${TPUT_BOLD}${TPUT_CYAN}${msg}${TPUT_RESET}${chartcolor}${sp:0:2}${l3:end:$((${#l2} - end))}${TPUT_RESET}"
  echo >&2 "${chartcolor}${l4}${TPUT_RESET}"
  echo >&2
  spinner
}

setup_info () {
  echo -e "\n${yellow}*${reset} ${green}Setup already completed.${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo "${m_tab}${yellow}If you want to re-start setup use --force or -f${reset}"
  echo -e "${m_tab}${magenta}sudo ./woo-aras-setup.sh --force${reset}\n"
  exit 1
}

env_info () {
  echo -e "\n${m_tab}${cyan}# WOOCOMMERCE - ARAS CARGO INTEGRATION ENVIRONMENT DETAILS${reset}"
  echo "${m_tab}${cyan}# ---------------------------------------------------------------------${reset}"
  echo -e "${m_tab}${magenta}# ATTENTION: Always run under system user --> ${new_user}${reset}\n"
  { # Start redirection
  echo "${green}System_User: ${new_user}${reset}"
  echo "${green}Home_Folder: /home/${new_user}${reset}"
  echo "${green}Sudoer: Limited${reset}"
  [[ "${password}" ]] && echo "${green}Password: ${password}${reset}" || echo "${green}Password: HIDDEN${reset}"
  echo "${green}Working_Path: ${working_path}${reset}"
  echo "${green}Setup_Script: ${working_path}/woo-aras-setup.sh${reset}"
  echo "${green}Main_Script: ${working_path}/woocommerce-aras-cargo.sh${reset}"
  } | column -t -s ' ' | sed 's/^/  /' # End redirection
  echo ""
}

# @DETERMINE SCRIPT PATH
# =====================================================================
script_path_pretty_error () {
  echo -e "\n${red}*${reset} ${red}Could not determine script name and fullpath${reset}"
  echo -e "${cyan}${m_tab}#####################################################${reset}\n"
  exit 1
}

this_script_full_path="${BASH_SOURCE[0]}"
if command -v dirname >/dev/null 2>&1 && command -v readlink >/dev/null 2>&1 && command -v basename >/dev/null 2>&1; then
  # Symlinks
  while [[ -h "${this_script_full_path}" ]]; do
    this_script_path="$( cd -P "$( dirname "${this_script_full_path}" )" >/dev/null 2>&1 && pwd )"
    this_script_full_path="$(readlink "${this_script_full_path}")"
    # Resolve
    if [[ "${this_script_full_path}" != /* ]] ; then
      this_script_full_path="${this_script_path}/${this_script_full_path}"
    fi
  done
  this_script_path="$( cd -P "$( dirname "${this_script_full_path}" )" >/dev/null 2>&1 && pwd )"
  this_script_name="$(basename "${this_script_full_path}")"
else
  script_path_pretty_error
fi

if [[ ! "${this_script_full_path}" || ! "${this_script_path}" || ! "${this_script_name}" ]]; then
  script_path_pretty_error
fi

# Enable extglob
# Remove trailing / (removes / and //) from script path
shopt -s extglob
this_script_path="${this_script_path%%+(/)}"

# Export for main executable
export temporary_path_x="${this_script_path}"

# STAGE-1 @PACKAGE INSTALLATION
# =====================================================================
# Add /usr // /usr/local to PATH
export PATH="${PATH}:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
uniquepath () {
  local path
  path=""
  while read -r
  do
    if [[ ! "${path}" =~ (^|:)"${REPLY}"(:|$) ]]; then
      [[ "${path}" ]] && path="${path}:"
      path="${path}${REPLY}"
    fi
  done < <(echo "${PATH}" | tr ":" "\n")
  [[ "${path}" ]] && [[ "${PATH}" =~ /bin ]] && [[ "${PATH}" =~ /sbin ]] && export PATH="${path}"
}
uniquepath

# Unsupported os&pm pretty error
un_supported () {
  if [[ "${1}" == "--pm" ]]; then
    fatal "Unsupported Linux distribution"
  elif [[ "${1}" == "--os" ]]; then
    fatal "Could not identify your Linux distribution"
  fi
}

# Distribution based variables
lsb_release=$(command -v lsb_release 2> /dev/null)

  distribution=
  release=
  version=
  codename=
  detection=
  NAME=
  ID=
  ID_LIKE=
  VERSION=
  VERSION_ID=

# Check which package managers are available
autodetect_package_manager () {
  my_apt_get=$(command -v apt-get 2> /dev/null)
  my_dnf=$(command -v dnf 2> /dev/null)
  my_emerge=$(command -v emerge 2> /dev/null)
  my_pacman=$(command -v pacman 2> /dev/null)
  my_yum=$(command -v yum 2> /dev/null)
  my_zypper=$(command -v zypper 2> /dev/null)

  # Determine package manager
  package_installer=()
  declare -a my_pm=("${my_apt_get}" "${my_dnf}" "${my_emerge}"
                    "${my_pacman}" "${my_yum}" "${my_zypper}")

  for i in "${my_pm[@]}"
  do
   if [[ "${i}" ]]; then
     package_installer+=( "${i}" )
   fi
  done

  ! (( ${#package_installer[@]} )) && return 1

  return 0
}

release2lsb_release () {
  local file="${1}" x DISTRIB_ID="" DISTRIB_RELEASE="" DISTRIB_CODENAME=""
  x="$(grep -v "^$" "${file}" | head -n 1)"

  if [[ "${x}" =~ ^.*[[:space:]]+Linux[[:space:]]+release[[:space:]]+.*[[:space:]]+(.*)[[:space:]]*$ ]]; then
    eval "$(echo "${x}" | sed "s|^\(.*\)[[:space:]]\+Linux[[:space:]]\+release[[:space:]]\+\(.*\)[[:space:]]\+(\(.*\))[[:space:]]*$|DISTRIB_ID=\"\1\"\nDISTRIB_RELEASE=\"\2\"\nDISTRIB_CODENAME=\"\3\"|g" | grep "^DISTRIB")"
  elif [[ "${x}" =~ ^.*[[:space:]]+Linux[[:space:]]+release[[:space:]]+.*[[:space:]]+$ ]]; then
    eval "$(echo "${x}" | sed "s|^\(.*\)[[:space:]]\+Linux[[:space:]]\+release[[:space:]]\+\(.*\)[[:space:]]*$|DISTRIB_ID=\"\1\"\nDISTRIB_RELEASE=\"\2\"|g" | grep "^DISTRIB")"
  elif [[ "${x}" =~ ^.*[[:space:]]+release[[:space:]]+.*[[:space:]]+(.*)[[:space:]]*$ ]]; then
    eval "$(echo "${x}" | sed "s|^\(.*\)[[:space:]]\+release[[:space:]]\+\(.*\)[[:space:]]\+(\(.*\))[[:space:]]*$|DISTRIB_ID=\"\1\"\nDISTRIB_RELEASE=\"\2\"\nDISTRIB_CODENAME=\"\3\"|g" | grep "^DISTRIB")"
  elif [[ "${x}" =~ ^.*[[:space:]]+release[[:space:]]+.*[[:space:]]+$ ]]; then
    eval "$(echo "${x}" | sed "s|^\(.*\)[[:space:]]\+release[[:space:]]\+\(.*\)[[:space:]]*$|DISTRIB_ID=\"\1\"\nDISTRIB_RELEASE=\"\2\"|g" | grep "^DISTRIB")"
  fi

  distribution="${DISTRIB_ID}"
  version="${DISTRIB_RELEASE}"
  codename="${DISTRIB_CODENAME}"

  [[ -z "${distribution}" ]] && return 1
  detection="${file}"
  return 0
}

get_os_release () {
  os_release_file=
  if [[ -s "/etc/os-release" ]]; then
    os_release_file="/etc/os-release"
  elif [[ -s "/usr/lib/os-release" ]]; then
    os_release_file="/usr/lib/os-release"
  else
    return 1
  fi
  local x
  eval "$(grep -E "^(NAME|ID|ID_LIKE|VERSION|VERSION_ID)=" "${os_release_file}")"
  for x in "${ID}" ${ID_LIKE}; do
    case "${x,,}" in
      arch | centos | debian | fedora | gentoo | opensuse-leap | rhel | suse | ubuntu | opensuse-tumbleweed | manjaro | alpine)
        distribution="${x}"
        version="${VERSION_ID}"
        codename="${VERSION}"
        detection="${os_release_file}"
        break
        ;;
      *)
        echo >&2 "Unknown distribution ID: ${x}"
        ;;
    esac
  done
  [[ -z "${distribution}" ]] && return 1
  return 0
}

get_lsb_release () {
  if [[ -f "/etc/lsb-release" ]]; then
    local DISTRIB_ID="" DISTRIB_RELEASE="" DISTRIB_CODENAME=""
    eval "$(grep -E "^(DISTRIB_ID|DISTRIB_RELEASE|DISTRIB_CODENAME)=" /etc/lsb-release)"
    distribution="${DISTRIB_ID}"
    version="${DISTRIB_RELEASE}"
    codename="${DISTRIB_CODENAME}"
    detection="/etc/lsb-release"
  fi

  if [[ -z "${distribution}" ]] && [[ -n "${lsb_release}" ]]; then
    eval "declare -A release=( $(lsb_release -a 2> /dev/null | sed -e "s|^\(.*\):[[:space:]]*\(.*\)$|[\1]=\"\2\"|g") )"
    distribution="${release["Distributor ID"]}"
    version="${release[Release]}"
    codename="${release[Codename]}"
    detection="lsb_release"
  fi

  [[ -z "${distribution}" ]] && return 1
  return 0
}

find_etc_any_release () {
  if [[ -f "/etc/arch-release" ]]; then
    release2lsb_release "/etc/arch-release" && return 0
  fi

  if [[ -f "/etc/centos-release" ]]; then
    release2lsb_release "/etc/centos-release" && return 0
  fi

  if [[ -f "/etc/redhat-release" ]]; then
    release2lsb_release "/etc/redhat-release" && return 0
  fi

  if [[ -f "/etc/SuSe-release" ]]; then
    release2lsb_release "/etc/SuSe-release" && return 0
  fi

  return 1
}

# Autodetection of distribution/OS
autodetect_distribution () {
  case "$(uname -s)" in
    "Linux")
      get_os_release || get_lsb_release || find_etc_any_release
      ;;
    *)
      return 1
      ;;
  esac
}

# It is best to get needed version of jq manually instead of relying distro repos
# It is portable, doesn't need any runtime dependencies.
# If something goes wrong here script will try package manager to install it
get_jq () {
  if ! command -v jq >/dev/null 2>&1; then
    local jq_url
    local my_jq
    local jq_sha256sum

    if [[ $(uname -m) == "x86_64" ]]; then
      jq_url="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
      jq_sha256sum="af986793a515d500ab2d35f8d2aecd656e764504b789b66d7e1a0b727a124c44"
    else
      jq_url="https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux32"
      jq_sha256sum="319af6123aaccb174f768a1a89fb586d471e891ba217fe518f81ef05af51edd9"
    fi

    if command -v wget >/dev/null 2>&1; then
      {
      cd /tmp
      wget -q --no-check-certificate -O jq ${jq_url}
      chmod +x jq
      mkdir -p /usr/local/bin
      mv jq /usr/local/bin/jq
      } >/dev/null 2>&1
    elif command -v curl >/dev/null 2>&1; then
      {
      cd /tmp
      curl -sLk ${jq_url} -o jq
      chmod +x jq
      mkdir -p /usr/local/bin
      mv jq /usr/local/bin/jq
      } >/dev/null 2>&1
    fi

    if command -v jq >/dev/null 2>&1; then
      if command -v sha256sum >/dev/null 2>&1; then
        [[ "$(sha256sum $(which jq) | awk '{print $1}')" != "${jq_sha256sum}" ]] && { return 1; rm -f /usr/local/bin/jq >/dev/null 2>&1; }
      else
        return 1
        rm -f /usr/local/bin/jq >/dev/null 2>&1
      fi
    else
      return 1
    fi
  fi

  return 0
}

# Wait for bg process stylish also get exit code of the bg process
my_wait () {
  local my_pid=$!
  local result
  # Force kill bg process if script exits
  trap "kill -9 $my_pid 2>/dev/null" EXIT
  # Wait stylish while process is alive
  spin='-\|/'
  mi=0
  while kill -0 $my_pid 2>/dev/null # (ps | grep $my_pid) is alternative
  do
    mi=$(( (mi+1) %4 ))
    printf "\r${m_tab}${green}[ ${spin:$mi:1} ]${magenta} ${1}${reset}"
    sleep .1
  done
  # Get bg process exit code
  wait $my_pid
  [[ $? -eq 0 ]] && result=ok
  # Need for tput cuu1
  echo ""
  # Reset trap to normal exit
  trap - EXIT
  # Return status of function according to bg process status
  [[ "${result}" ]] && return 0
  return 1
}

# Validate installed packages silently
# =====================================================================
validate_centos () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if ! $my_yum list installed ${packagename} >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_rhel () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if [[ "${my_yum}" ]]; then
      if ! $my_yum list installed ${packagename} >/dev/null 2>&1; then
        fail+=( "${packagename}" )
      fi
    elif ! $my_dnf list installed ${packagename} >/dev/null 2>&1; then
        fail+=( "${packagename}" )
    fi
  done
}

validate_fedora () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if ! $my_dnf list installed ${packagename} >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_debian () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if ! dpkg -l | grep -qw "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_ubuntu () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if ! dpkg -l | grep -qw "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}


validate_gentoo () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if command -v qlist >/dev/null 2>&1; then
      if ! qlist -I | grep -qw "$packagename" >/dev/null 2>&1; then
        fail+=( "${packagename}" )
      fi
    elif command -v eix-installed >/dev/null 2>&1; then
      if ! eix-installed -a | grep -q "$packagename" >/dev/null 2>&1; then
        fail+=( "${packagename}" )
      fi
    fi
  done
}

validate_arch () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if ! pacman -Qqs | grep -q "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_suse () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if [[ "${packagename}" == "php" ]]; then
      if ! rpm -qa "$packagename"* >/dev/null 2>&1; then
        fail+=( "${packagename}" "php-soap" )
      fi
    elif [[ "${packagename}" == "php-soap" ]]; then
      if ! rpm -qa php* | grep -q "soap" >/dev/null 2>&1; then
        fail+=( "php-soap" )
      fi
    elif ! rpm -q "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_opensuse-leap () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if [[ "${packagename}" == "php" ]]; then
      if ! rpm -qa "$packagename"* >/dev/null 2>&1; then
        fail+=( "${packagename}" "php-soap" )
      fi
    elif [[ "${packagename}" == "php-soap" ]]; then
      if ! rpm -qa php* | grep -q "soap" >/dev/null 2>&1; then
        fail+=( "php-soap" )
      fi
    elif ! rpm -q "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_opensuse-tumbleweed () {
  fail=()
  for packagename in "${packages[@]}"
  do
    if [[ "${packagename}" == "php" ]]; then
      if ! rpm -qa "$packagename"* >/dev/null 2>&1; then
        fail+=( "${packagename}" "php-soap" )
      fi
    elif [[ "${packagename}" == "php-soap" ]]; then
      if ! rpm -qa php* | grep -q "soap" >/dev/null 2>&1; then
        fail+=( "php-soap" )
      fi
    elif ! rpm -q "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}
# =====================================================================

# Merge ops.
post_ops () {
  my_wait "${1}"
  validate_${distribution}
}

# Replace previous line in terminal
replace_suc () {
  tput cuu 1
  echo "${m_tab}${TPUT_BOLD}${green}[ ✓ ] ${cyan}${1}${reset}"
}

replace_fail () {
  tput cuu 1
  echo "${m_tab}${TPUT_BOLD}${red}[ x ] ${cyan}${1}${reset}"
}

fake_progress () {
  sleep 3 &
  my_wait "${1}"
}

# Check hard dependencies that not in bash built-in or pre-installed commonly
check_deps () {
  declare -a dependencies=("curl" "openssl" "php" "perl" "whiptail" "logrotate" "git" "make" "gawk")
  if ! get_jq; then
    dependencies+=( "jq" )
  fi

  missing_deps=()
  for dep in "${dependencies[@]}"
  do
    if ! command -v "${dep}" >/dev/null 2>&1; then
      missing_deps+=( "${dep}" )
      if [[ "${dep}" == "php" ]]; then
        missing_deps+=( "php_soap" )
      elif [[ "${dep}" == "perl" ]]; then
        missing_deps+=( "perl_text_fuzzy" "perl_app_cpanminus" )
      fi
    elif [[ "${dep}" == "php" ]]; then
      if ! php -m | grep -q "soap"; then
        missing_deps+=( "php_soap" )
      fi
    elif [[ "${dep}" == "perl" ]]; then
      if ! perl -e 'use Text::Fuzzy;' >/dev/null 2>&1; then
        if ! perl -e 'use App::cpanminus;' >/dev/null 2>&1; then
          missing_deps+=( "perl_app_cpanminus" "perl_text_fuzzy" )
        else
          missing_deps+=( "perl_text_fuzzy" )
        fi
      fi
    fi
  done
}
check_deps

if (( ${#missing_deps[@]} )); then
  # Check distribution & package_manager are supported
  autodetect_distribution &&
  {
  autodetect_package_manager || un_supported --pm
  } ||
  un_supported --os

  # Test connection for package installation
  test_connection

  # STAGE-1
  wooaras_banner "STAGE-1: PACKAGE INSTALLATION"

  echo -e "\n${green}* ${magenta}OS Information${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  printf "${green}"

	cat <<-EOF | sed 's/^/  /'
	Distribution    : ${distribution}
	Version         : ${version}
	Codename        : ${codename}
	Package Manager : ${package_installer}
	Detection Method: ${detection}
	EOF

  printf "${reset}"

  # Package lists for distributions
  declare -A pkg_make=(
    ['centos']="@'Development Tools'"
    ['fedora']="@'Development Tools'"
    ['rhel']="@'Development Tools'"
    ['ubuntu']="build-essential"
    ['debian']="build-essential"
    ['arch']="base-devel"
    ['suse']=""
    ['opensuse-leap']=""
    ['opensuse-tumbleweed']=""
    ['gentoo']=""
  )

  declare -A pkg_curl=(
    ['gentoo']="net-misc/curl"
    ['default']="curl"
  )

  declare -A pkg_openssl=(
    ['gentoo']="dev-libs/openssl"
    ['default']="openssl"
  )

  declare -A pkg_gawk=(
    ['gentoo']="sys-apps/gawk"
    ['default']="gawk"
  )

  declare -A pkg_jq=(
    ['gentoo']="app-misc/jq"
    ['default']="jq"
  )

  declare -A pkg_perl_app_cpanminus=(
    ['centos']="perl-App-cpanminus"
    ['fedora']="perl-App-cpanminus"
    ['rhel']="perl-App-cpanminus"
    ['ubuntu']="cpanminus"
    ['debian']="cpanminus"
    ['arch']="cpanminus"
    ['gentoo']="dev-perl/App-cpanminus"
    ['suse']="perl-App-cpanminus"
    ['opensuse-leap']="perl-App-cpanminus"
    ['opensuse-tumbleweed']="perl-App-cpanminus"
  )

  declare -A pkg_perl_text_fuzzy=(
    ['default']=""
  )

  declare -A pkg_php=(
    ['gentoo']="dev-lang/php"
    ['default']="php"
  )

  declare -A pkg_php_soap=(
    ['gentoo']=""
    ['default']="php-soap"
  )

  declare -A pkg_git=(
    ['gentoo']="dev-vcs/git"
    ['default']="git"
  )

  declare -A pkg_logrotate=(
    ['gentoo']="app-admin/logrotate"
    ['default']="logrotate"
  )

  declare -A pkg_whiptail=(
    ['gentoo']="dev-util/dialog"
    ['ubuntu']="whiptail"
    ['debian']="whiptail"
    ['arch']="libnewt"
    ['default']="newt"
  )

  # Collect missing dependencies for distribution
  for dep in "${missing_deps[@]}"
  do
    eval "p=\${pkg_${dep}['${distribution,,}']}"
    [[ ! "${p}" ]] && eval "p=\${pkg_${dep}['default']}"
    [[ "${p}" ]] && packages+=( "${p}" )
  done

  echo -e "\n${green}*${reset}${green} I'm about to install following packages for you.${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  if [[ "${missing_deps[@]}" =~ "perl_text_fuzzy" ]]; then
    echo "${m_tab}${magenta}${packages[*]} Text::Fuzzy${reset}"
  else
    echo "${m_tab}${magenta}${packages[*]}${reset}"
  fi

  # User approval
  while :; do
    echo -e "\n${cyan}${m_tab}#####################################################${reset}"
    read -r -n 1 -p "${m_tab}${BC}Do you want to continue? --> (Y)es | (N)o${EC} " yn < /dev/tty
    echo ""
    case "${yn}" in
      [Yy]* ) break;;
      [Nn]* ) exit 1;;
      * ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}";;
    esac
  done

  echo -e "\n${m_tab}${magenta}${TPUT_BOLD}< THIS MAY TAKE A WHILE >${reset}"
  echo -e "${m_tab}${cyan}-------------------------${reset}\n"

  # Lets start package installation
  if [[ "${distribution}" = "centos" ]]; then
    opts="-yq install"
    repo="update"
    echo n | $my_yum ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_yum ${opts} "${packages[@]}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  elif [[ "${distribution}" = "debian" ]]; then
    opts="-yq install"
    repo="update"
    $my_apt_get ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_apt_get ${opts} "${packages[@]}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  elif [[ "${distribution}" = "ubuntu" ]]; then
    opts="-yq install"
    repo="update"
    $my_apt_get ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_apt_get ${opts} "${packages[@]}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  elif [[ "${distribution}" = "gentoo" ]]; then
    if [[ "${packages[*]}" =~ "^php" ]]; then
      echo 'dev-lang/php soap' > "${portage_php}"
    fi
    opts="--ask=n --quiet --quiet-build --quiet-fail"
    repo="--sync"
    $my_emerge ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_emerge ${opts} "${packages[@]}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  elif [[ "${distribution}" = "arch" ]]; then
    opts="--noconfirm --quiet --needed -S"
    repo="-Syy"
    $my_pacman ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_pacman ${opts} "${packages[@]}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  elif [[ "${distribution}" = "suse" || "${distribution}" = "opensuse-leap" || "${distribution}" = "opensuse-tumbleweed" ]]; then
    if [[ "${missing_deps[@]}" =~ "make" ]]; then
      suse_type="devel_basis"
      opts="--ignore-unknown --non-interactive --no-gpg-checks --quiet install pattern:${suse_type}"
    else
      opts="--ignore-unknown --non-interactive --no-gpg-checks --quiet install"
    fi
    repo="refresh"
    $my_zypper ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_zypper ${opts} "${packages[@]}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  elif [[ "${distribution}" = "fedora" ]]; then
    opts="-yq --setopt=strict=0 install"
    repo="distro-sync"
    echo n | $my_dnf ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_dnf ${opts} "${packages[@]}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  elif [[ "${distribution}" = "rhel" ]]; then
    if [[ "${my_yum}" ]]; then
      opts="-yq install"
      repo="update"
      echo n | $my_yum ${repo} &>/dev/null &
      my_wait "SYNCING REPOSITORY"
      replace_suc "REPOSITORIES SYNCED"
      $my_yum ${opts} "${packages[@]}" &>/dev/null &
      post_ops "INSTALLING PACKAGES"
    else
      opts="-yq --setopt=strict=0 install"
      repo="distro-sync"
      echo n | $my_dnf ${repo} &>/dev/null &
      my_wait "SYNCING REPOSITORY"
      replace_suc "REPOSITORIES SYNCED"
      $my_dnf ${opts} "${packages[@]}" &>/dev/null &
      post_ops "INSTALLING PACKAGES"
    fi
  fi

  # Check package installation completed without error &
  # Installing Text::Fuzzy perl module needs ( App::cpanminus ( make ))
  if ! (( ${#fail[@]} )); then
    replace_suc "PACKAGES INSTALLED"
    if [[ "${missing_deps[*]}" =~ "fuzzy" ]]; then
        cpanm -Sq Text::Fuzzy &>/dev/null &
        my_wait "INSTALLING PERL MODULES" && replace_suc "PERL MODULES INSTALLED" || replace_fail "INSTALLING PERL MODULES FAILED"
    fi
  else
    replace_fail "INSTALLING PACKAGES FAILED"
    fake_progress "INSTALLING PERL MODULES"
    replace_fail "INSTALLING PERL MODULES FAILED"
  fi

  # Re-check deps to validate whole package installation
  check_deps

  if ! (( ${#missing_deps[@]} )); then
    done_ "STAGE-1 | PACKAGE INSTALLATION"
  else
    fixed_missing=( "${missing_deps[@]//_/-}" )
    fatal "STAGE-1 | FAIL --> CANNOT INSTALL: ${fixed_missing[*]/perl-text-fuzzy/Text::Fuzzy}"
  fi
else
  done_ "STAGE-1 | PACKAGE INSTALLATION"
fi

# STAGE-2 @USER OPERATIONS
# =====================================================================
# Check user exist, if not create
if ! grep -qE "^${new_user}" "${pass_file}"; then
  wooaras_banner "STAGE-2: USER OPERATIONS"
  echo -e "\n${green}*${reset} ${magenta}Setting ${new_user} user password, type q for quit${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  read -r -p "${m_tab}${BC}Enter new system user password:${EC} " password < /dev/tty
  if [[ "${password}" == "q" || "${password}" == "quit" ]]; then exit 1; fi
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo -e "\n${m_tab}${magenta}${TPUT_BOLD}< THIS MAY TAKE A WHILE >${reset}"
  echo -e "${m_tab}${cyan}-------------------------${reset}\n"
  fake_progress "USER OPERATIONS"
  # Encrypt password
  enc_pass=$(perl -e 'print crypt($ARGV[0], "password")' $password || { replace_fail "USER OPERATIONS FAILED"; error=enc; })
  # Create user
  useradd -m -p "${enc_pass}" -s /bin/bash "${new_user}" >/dev/null 2>&1 || { replace_fail "USER OPERATIONS FAILED"; error=add; }
  # Limited sudoer for only execute setup and main
  echo "${new_user} ALL=(ALL) NOPASSWD: ${working_path}/woocommerce-aras-cargo.sh,${working_path}/woo-aras-setup.sh" | sudo EDITOR='tee -a' visudo >/dev/null 2>&1 || { replace_fail "USER OPERATIONS FAILED"; error=sudo; }
  if [[ "${error}" ]]; then
    if [[ "${error}" == "enc" ]]; then
      fatal "STAGE-2 | FAIL --> PASSWORD ENCRYPTION ERROR"
    elif [[ "${error}" == "add" ]]; then
      fatal "STAGE-2 | FAIL --> CANNOT CREATE USER"
    elif [[ "${error}" == "sudo" ]]; then
      fatal "STAGE-2 | FAIL --> CANNOT GRANT SUDO"
    fi
  else
    replace_suc "USER OPERATIONS COMPLETED"
    done_ "STAGE-2 | USER OPERATIONS"
  fi
else
  done_ "STAGE-2 | USER OPERATIONS"
fi

# STAGE-3 @ENVIRONMENT OPERATIONS
# =====================================================================
if ! [[ -d "${working_path}" ]]; then
  wooaras_banner "STAGE-3: ENVIRONMENT OPERATIONS"
  echo -e "\n${m_tab}${magenta}${TPUT_BOLD}< THIS MAY TAKE A WHILE >${reset}"
  echo -e "${m_tab}${cyan}-------------------------${reset}\n"
  if [[ ! -d "${working_path%/*}" ]]; then
    mkdir -p "${working_path%/*}" || die "STAGE-3 | FAIL --> Could not create directory ${working_path}"
  fi

  # Clone repo to working path & change permissions
  cd "${working_path%/*}" || die "STAGE-3 | FAIL --> Could not change directory to ${working_path%/*}"
  git clone --quiet "${git_repo}" &>/dev/null &
  my_wait "ENVIRONMENT OPERATIONS" || die "STAGE-3 | FAIL --> Could not git clone into ${working_path%/*}"
  chown -R "${new_user}":"${new_user}" "${working_path%/*}" >/dev/null 2>&1 || die "STAGE-3 | FAIL --> Could not change ownership of ${working_path%/*}"
  chmod 750 "${working_path}"/woocommerce-aras-cargo.sh >/dev/null 2>&1 || die "STAGE-3 | FAIL --> Could not change mod woocommerce-aras-cargo.sh"
  env_info
  done_ "STAGE-3 | ENVIRONMENT OPERATIONS"
else
  done_ "STAGE-3 | ENVIRONMENT OPERATIONS"
fi

# This prints once when env created first time
if [[ "${password}" ]]; then
  read -n 1 -s -r -p "${green}> Pre operations completed press any key to start setup..${reset}" reply < /dev/tty; echo
fi

# @START THE SETUP
# =====================================================================
# Change directory to working path
my_env="new_user,setup_key,working_path,temporary_path_x"
if [[ "$(pwd)" != "${working_path}" ]]; then
  cd "${working_path}" || fatal "FINAL STAGE | FAIL --> Could not change directory to ${working_path}"
fi

echo ""

if [[ "$(whoami)" != "${new_user}" ]]; then
  if [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
    if ! [[ -f "${working_path}"/.lck/.env.ready ]]; then
      sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'sudo --preserve-env='"${my_env}"' ./woocommerce-aras-cargo.sh --setup'
    else
      env_info; exit 1
    fi
  elif ! [[ -f "${working_path}/.two.way.set" ]]; then
    if ! [[ -f "${working_path}"/.lck/.env.ready ]]; then
      sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'sudo --preserve-env='"${my_env}"' ./woocommerce-aras-cargo.sh --setup'
    else
     env_info; exit 1
    fi
  else
    setup_info
  fi
elif [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
  sudo --preserve-env="${my_env}" ./woocommerce-aras-cargo.sh --setup
elif ! [[ -f "${working_path}/.two.way.set" ]]; then
  sudo --preserve-env="${my_env}" ./woocommerce-aras-cargo.sh --setup
else
  setup_info
fi

# And lastly we exit
exit $?
