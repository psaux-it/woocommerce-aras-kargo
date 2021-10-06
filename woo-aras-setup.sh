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
# -This script prepares necessary environment for ARAS cargo integration.

# My style
# =====================================================================
green=$(tput setaf 2); red=$(tput setaf 1); reset=$(tput sgr0); cyan=$(tput setaf 6)
magenta=$(tput setaf 5); yellow=$(tput setaf 3); m_tab='  '; BC=$'\e[32m'; EC=$'\e[0m'

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
  echo -e "\n${yellow}*${reset} {yellow}git not found!${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo -e "${yellow}${m_tab}Install necessary package and re-start setup.${reset}\n"
  exit 1
fi

# Ugly die
die () {
  echo "$@" >&2
  exit 1
}

# Global Variables
# =====================================================================
export new_user="wooaras"
export setup_key="gajVVK2zXo"
export working_path="/home/${new_user}/scripts/woocommerce-aras-cargo"
git_repo="https://github.com/hsntgm/woocommerce-aras-kargo.git"
sudoers_file="/etc/sudoers"
pass_file="/etc/passwd"

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

# Create new user with home, grant sudo&cron privileges
# =====================================================================
modified=0

# Helper function
add_user () {
  useradd -m -p "${enc_pass}" -s /bin/bash "${new_user}" >/dev/null 2>&1 || die "Could not create user ${new_user}"
  usermod -a -G "${new_user}",cron"${1}" "${new_user}" >/dev/null 2>&1 || die "Could not add ${new_user} to ${1}"
}

# Check new user exist, if not create
if ! grep -qE "^${new_user}" "${pass_file}"; then
  echo -e "\n${green}*${reset} ${magenta}Setting ${new_user} user password, type q for quit${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  read -r -p "${m_tab}${BC}Enter new system user password:${EC} " password < /dev/tty
  if [[ "${password}" == "q" || "${password}" == "quit" ]]; then exit 1; fi
  echo "${cyan}${m_tab}#####################################################${reset}"

  # Auto pass creation only support encrypted
  enc_pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)

  # Check sudo group
  if grep -qFx "%sudo ALL=(ALL) ALL" < <(< "${sudoers_file}" sed 's/[[:space:]]\+/ /g' | sed 's/^[ \t]*//') ||
     grep -qFx "%sudo ALL=(ALL:ALL) ALL" < <(< "${sudoers_file}" sed 's/[[:space:]]\+/ /g' | sed 's/^[ \t]*//'); then
     add_user ",sudo"
     modified=1
  fi

  # Check wheel group
  if grep -qFx "%wheel ALL=(ALL) ALL" < <(< "${sudoers_file}" sed 's/[[:space:]]\+/ /g' | sed 's/^[ \t]*//') ||
     grep -qFx "%wheel ALL=(ALL:ALL) ALL" < <(< "${sudoers_file}" sed 's/[[:space:]]\+/ /g' | sed 's/^[ \t]*//'); then
     if [[ "${modified}" -eq 0 ]]; then
       add_user ",wheel"
       modified=1
     fi
  fi

  # Manually grant sudo privileges
  if [[ "${modified}" -eq 0 ]]; then
    add_user
    if ! ( grep -qFx "${new_user} ALL=(ALL:ALL) ALL" < <(< "${sudoers_file}" sed 's/[[:space:]]\+/ /g' | sed 's/^[ \t]*//') ||
           grep -qFx "${new_user} ALL=(ALL) ALL" < <(< "${sudoers_file}" sed 's/[[:space:]]\+/ /g' | sed 's/^[ \t]*//') ); then
           echo "${new_user} ALL=(ALL:ALL) ALL" | sudo EDITOR='tee -a' visudo >/dev/null 2>&1 || die "Could not grant sudo privileges"
    fi
  fi
fi

# Prepeare the installation environment for the first time
# =====================================================================
# Create installation path
if [[ ! -d "${working_path}" ]]; then
  mkdir -p "${working_path}" || die "Could not create directory ${working_path}"
fi

# Clone repo to working path & change ownership
if ! [[ "$(ls -A ${working_path})" ]]; then
  cd "${working_path%/*}" || die "Could not change directory to ${working_path%/*}"
  git clone --quiet "${git_repo}" . || die "Could not git clone"
  chmod +x "${working_path}"/woo-aras-setup.sh || die "Could not change mod woo-aras-setup.sh"
  chmod +x "${working_path}"/woocommerce-aras-cargo.sh || die "Could not change mod woocommerce-aras-cargo.sh"
  chown -R "${new_user}":"${new_user}" "${working_path%/*}" || die "Could not change ownership of ${working_path%/*}"
fi

# Change directory to working path
if [[ "$(pwd)" != "${working_path}" ]]; then
  cd "${working_path}" || die "Could not change directory to ${working_path}"
fi

setup_info () {
  echo -e "\n${yellow}*${reset} ${green}Setup already completed.${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo "${m_tab}${yellow}If you want to re-start setup use --force or -f${reset}"
  echo -e "${m_tab}${magenta}sudo ./woo-aras-setup.sh --force${reset}\n"
  exit 1
}

# Finally start the setup
# =====================================================================
if [[ "$(whoami)" != "${new_user}" ]]; then
  if [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
    su -s /bin/bash -c 'sudo --preserve-env=new_user,setup_key,working_path,password,temporary_path_x -S <<< '"${password}"' ./woocommerce-aras-cargo.sh --setup' "${new_user}"
  elif ! [[ -f "${working_path}/.two.way.set" ]]; then
    su -s /bin/bash -c 'sudo --preserve-env=new_user,setup_key,working_path,password,temporary_path_x -S <<< '"${password}"' ./woocommerce-aras-cargo.sh --setup' "${new_user}"
  else
    setup_info
  fi
elif [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
  sudo --preserve-env=new_user,setup_key,working_path,password,temporary_path_x ./woocommerce-aras-cargo.sh --setup
elif ! [[ -f "${working_path}/.two.way.set" ]]; then
  sudo --preserve-env=new_user,setup_key,working_path,password,temporary_path_x ./woocommerce-aras-cargo.sh --setup
else
  setup_info
fi

# And lastly we exit
exit $?
