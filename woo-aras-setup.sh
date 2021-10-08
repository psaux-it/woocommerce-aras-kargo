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
  TPUT_GREEN=""; TPUT_CYAN=""; TPUT_DIM=""; TPUT_BOLD=""
  if command -v tput > /dev/null 2>&1; then
    if [[ $(($(tput colors 2> /dev/null))) -ge 8 ]]; then
      green="$(tput setaf 2)"; red="$(tput setaf 1)"; reset="$(tput sgr0)"; cyan="$(tput setaf 6)"
      magenta="$(tput setaf 5)"; yellow="$(tput setaf 3)"; TPUT_RESET="$(tput sgr 0)"
      TPUT_GREEN="$(tput setaf 2)"; TPUT_CYAN="$(tput setaf 6)"; TPUT_DIM="$(tput dim)"
      TPUT_BOLD="$(tput bold)"
      return 0
    fi
  fi
  m_tab='  '; BC=$'\e[32m'; EC=$'\e[0m'
}
setup_terminal || echo > /dev/null

# @EARLY CRITICAL CONTROLS --> means that no spend cpu time anymore
# =====================================================================
# Prevent errors cause by uncompleted upgrade
# Detect to make sure the entire script is available, fail if the script is missing contents
if [[ "$(tail -n 1 "${0}" | head -n 1 | cut -c 1-7)" != "exit \$?" ]]; then
  echo -e "\n${red}*${reset} ${red}Script is incomplete, please force upgrade manually${reset}"
  echo -e "${cyan}${m_tab}#####################################################${reset}\n"
  exit 1
fi

# Check OS is supported
if [[ "${OSTYPE}" != "linux-gnu"* ]]; then
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

# Check git installed
if ! command -v git > /dev/null 2>&1; then
  echo -e "\n${yellow}*${reset} ${yellow}git not found!${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo -e "${yellow}${m_tab}Install necessary package and re-start setup.${reset}\n"
  exit 1
fi

# Global Variables
# =====================================================================
export new_user="wooaras"
export setup_key="gajVVK2zXo"
export working_path="/home/${new_user}/scripts/woocommerce-aras-kargo"
git_repo="https://github.com/hsntgm/woocommerce-aras-kargo.git"
sudoers_file="/etc/sudoers"
pass_file="/etc/passwd"

# Ugly die
die () {
  echo "$@" >&2
  userdel "${new_user}" >/dev/null 2>&1
  rm -r "/home/${new_user:?}" >/dev/null 2>&1
  exit 1
}

spinner () {
  sleep 3 &
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
    woo_aras="WooCommerce-Aras Cargo" start end msg="${*}" chartcolor="${TPUT_DIM}"

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
  echo "${green}Sudoer: Yes${reset}"
  [[ "${password}" ]] && echo "${green}Password: ${password}${reset}" || echo "${green}Password: HIDDEN${reset}"
  echo "${green}Working_Path: ${working_path}${reset}"
  echo "${green}Setup_Script: ${working_path}/woo-aras-setup.sh${reset}"
  echo "${green}Main_Script: ${working_path}/woocommerce-aras-cargo.sh${reset}"
  } | column -t -s ' ' | sed 's/^/  /' # End redirection
  echo ""
}

# Determine Script path
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
export temporary_path_x="${this_script_path}"


# Install required packages
# =====================================================================
unsupported_os () {
	error message
	exit 1
}

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
my_apt_get=$(command -v apt-get 2> /dev/null)
my_dnf=$(command -v dnf 2> /dev/null)
my_emerge=$(command -v emerge 2> /dev/null)
my_pacman=$(command -v pacman 2> /dev/null)
my_yum=$(command -v yum 2> /dev/null)
my_zypper=$(command -v zypper 2> /dev/null)

# Determine package manager
declare -a pm=( "${my_apt_get}" "${my_dnf}" "${my_emerge}"
                "${my_pacman}" "${my_yum}" "${my_zypper}" )

for i in "${pm[@]}"
do
  if [[ "${i}" ]]; then
    package_installer="${i}"
  fi
done

release2lsb_release() {
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

  [ -z "${distribution}" ] && return 1
  detection="${file}"
  return 0
}

get_os_release() {
  os_release_file=
  if [ -s "/etc/os-release" ]; then
    os_release_file="/etc/os-release"
  elif [ -s "/usr/lib/os-release" ]; then
    os_release_file="/usr/lib/os-release"
  else
    return 1
  fi
  local x
  eval "$(grep -E "^(NAME|ID|ID_LIKE|VERSION|VERSION_ID)=" "${os_release_file}")"
  for x in "${ID}" ${ID_LIKE}; do
    case "${x,,}" in
      arch | centos | debian | fedora | gentoo | opensuse-leap | rhel | suse | ubuntu)
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
  [ -z "${distribution}" ] && return 1
  return 0
}

get_lsb_release() {
  if [ -f "/etc/lsb-release" ]; then
    local DISTRIB_ID="" DISTRIB_RELEASE="" DISTRIB_CODENAME=""
    eval "$(grep -E "^(DISTRIB_ID|DISTRIB_RELEASE|DISTRIB_CODENAME)=" /etc/lsb-release)"
    distribution="${DISTRIB_ID}"
    version="${DISTRIB_RELEASE}"
    codename="${DISTRIB_CODENAME}"
    detection="/etc/lsb-release"
  fi

  if [ -z "${distribution}" ] && [ -n "${lsb_release}" ]; then
    eval "declare -A release=( $(lsb_release -a 2> /dev/null | sed -e "s|^\(.*\):[[:space:]]*\(.*\)$|[\1]=\"\2\"|g") )"
    distribution="${release["Distributor ID"]}"
    version="${release[Release]}"
    codename="${release[Codename]}"
    detection="lsb_release"
  fi

  [ -z "${distribution}" ] && return 1
  return 0
}

find_etc_any_release() {
  if [ -f "/etc/arch-release" ]; then
    release2lsb_release "/etc/arch-release" && return 0
  fi

  if [ -f "/etc/centos-release" ]; then
    release2lsb_release "/etc/centos-release" && return 0
  fi

  if [ -f "/etc/redhat-release" ]; then
    release2lsb_release "/etc/redhat-release" && return 0
  fi

  if [ -f "/etc/SuSe-release" ]; then
    release2lsb_release "/etc/SuSe-release" && return 0
  fi

  return 1
}

autodetect_distribution () {
  # Autodetection of distribution/OS
  case "$(uname -s)" in
    "Linux")
      get_os_release || get_lsb_release || find_etc_any_release
      ;;
    *)
      return 1
      ;;
  esac
}

# Check hard dependencies that not in bash built-in or pre-installed commonly
declare -a dependencies=("curl" "openssl" "jq" "php" "perl" "whiptail" "logrotate" "git")
check_deps () {
  missing_deps=()
  for dep in "${dependencies[@]}"
  do
    if ! command -v "${dep}" >/dev/null 2>&1; then
      missing_deps+=( "${dep} )"
    elif [[ "${dep}" == "php" ]]; then
	  if ! php -m | grep -q "soap"; then
        missing_deps+=( "php-soap" )
      fi
    elif [[ "${dep}" == "perl" ]]; then
      if ! perl -e 'use Text::Fuzzy;' >/dev/null 2>&1; then
        missing_deps+=( "Perl Text::Fuzzy" )
      fi
    fi
  done
}
check_deps

if (( ${#missing_deps[@]} )); then
  autodetect_distribution || unsupported_os

  cat <<-EOF
  We detected these:
  Distribution    : ${distribution}
  Version         : ${version}
  Codename        : ${codename}
  Package Manager : ${package_installer}
  Detection Method: ${detection}
  EOF

  declare -A pkg_build=(
    ['centos']="groupinstall 'Development Tools'"
    ['fedora']="groupinstall 'Development Tools'"
    ['rhel']="groupinstall 'Development Tools'"
    ['ubuntu']="build-essential"
    ['debian']="build-essential"
    ['arch']="base-devel"
    ['suse']="--type pattern devel_basis"
    ['opensuse-leap']="--type pattern devel_basis"
  )

  declare -A pkg_curl=(
    ['gentoo']="net-misc/curl"
    ['default']="curl"
  )

  declare -A pkg_openssl=(
    ['gentoo']="dev-libs/openssl"
    ['default']="openssl"
  )

  declare -A pkg_jq=(
    ['gentoo']="app-misc/jq"
    ['default']="jq"
  )

  declare -A pkg_php=(
    ['gentoo']="dev-lang/php"
    ['default']="php"
  )

  declare -A pkg_php_soap=(
    ['gentoo']="dev-lang/php"
    ['default']="php-soap"
  )

  declare -A pkg_perl_fuzzy=(
    ['gentoo']="sys-devel/autogen"
    ['default']="autogen"
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

  # Install build essential for all oses for text-fuzzy compile

  # Install missing dependencies
  for dep in "${missing_deps[@]}"
  do
    eval "p=\${pkg_${dep}['${distribution,,}']}"
    [[ -z "${p}" ]] && eval "p=\${pkg_${dep}['default']}"

    if [[ "${distribution}" = "centos" ]]; then
      opts="-yq install"
      $my_yum "${opts}" "${p}"
    elif [[ "${distribution}" = "debian" ]]; then
      opts="-yq install"
      $my_apt_get "${opts}" "${p}"
    elif [[ "${distribution}" = "ubuntu" ]]; then
      opts="-yq install"
      $my_apt_get "${opts}" "${p}"
    elif [[ "${distribution}" = "gentoo" ]]; then
      opts="--ask=n --quiet --quiet-build --quiet-fail"
      $my_emerge "${opts}" "${p}"
    fi
  done
fi

# Create new user with home, grant privileges
# =====================================================================
# Check user exist, if not create
if ! grep -qE "^${new_user}" "${pass_file}"; then
  echo -e "\n${green}*${reset} ${magenta}Setting ${new_user} user password, type q for quit${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  read -r -p "${m_tab}${BC}Enter new system user password:${EC} " password < /dev/tty
  if [[ "${password}" == "q" || "${password}" == "quit" ]]; then exit 1; fi
  echo "${cyan}${m_tab}#####################################################${reset}"

  # Encrypt password
  enc_pass=$(perl -e 'print crypt($ARGV[0], "password")' $password || die "Could not encrypt password")
  # Create user
  useradd -m -p "${enc_pass}" -s /bin/bash "${new_user}" >/dev/null 2>&1 || die "Could not create user ${new_user}"
  # Limited sudoer for only execute this script
  echo "${new_user} ALL=(ALL) NOPASSWD: ${working_path}/woocommerce-aras-cargo.sh,${working_path}/woocommerce-aras-cargo.sh" |
  sudo EDITOR='tee -a' visudo >/dev/null 2>&1 || die "Could not grant sudo privileges"
fi

# Prepare the environment if not set
# =====================================================================
# Create working path
if [[ ! -d "${working_path%/*}" ]]; then
  mkdir -p "${working_path%/*}" || die "Could not create directory ${working_path}"
fi

# Clone repo to working path & change ownership
if ! [[ -d "${working_path}" ]]; then
  cd "${working_path%/*}" || die "Could not change directory to ${working_path%/*}"
  git clone --quiet "${git_repo}" || die "Could not git clone into ${working_path%/*}"
  chown -R "${new_user}":"${new_user}" "${working_path%/*}" >/dev/null 2>&1 || die "Could not change ownership of ${working_path%/*}"
  chmod 750 "${working_path}"/woocommerce-aras-cargo.sh >/dev/null 2>&1 || die "Could not change mod woocommerce-aras-cargo.sh" || die "Could not change permission woocommerce-aras-cargo.sh"
fi

# Change directory to working path
if [[ "$(pwd)" != "${working_path}" ]]; then
  cd "${working_path}" || die "Could not change directory to ${working_path}"
fi

# This prints once when env created first time
if [[ "${password}" ]]; then
  wooaras_banner "Environment ready.."
  env_info
  read -n 1 -s -r -p "${green}> When ready press any key to continue..${reset}" reply < /dev/tty; echo
fi

# Finally start the setup
# =====================================================================
if [[ "$(whoami)" != "${new_user}" ]]; then
  if [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
    if ! [[ -f "${working_path}"/.lck/.env.ready ]]; then
      sudo -u "${new_user}" -s /bin/bash -c 'sudo --preserve-env=new_user,setup_key,working_path,temporary_path_x ./woocommerce-aras-cargo.sh --setup'
    else
      env_info; exit 1
    fi
  elif ! [[ -f "${working_path}/.two.way.set" ]]; then
    if ! [[ -f "${working_path}"/.lck/.env.ready ]]; then
      sudo -u "${new_user}" -s /bin/bash -c 'sudo --preserve-env=new_user,setup_key,working_path,temporary_path_x ./woocommerce-aras-cargo.sh --setup'
    else
     env_info; exit 1
    fi
  else
    setup_info
  fi
elif [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
  sudo --preserve-env=new_user,setup_key,working_path,temporary_path_x ./woocommerce-aras-cargo.sh --setup
elif ! [[ -f "${working_path}/.two.way.set" ]]; then
  sudo --preserve-env=new_user,setup_key,working_path,temporary_path_x ./woocommerce-aras-cargo.sh --setup
else
  setup_info
fi

# And lastly we exit
exit $?
