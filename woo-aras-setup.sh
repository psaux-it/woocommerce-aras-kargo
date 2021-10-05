#!/bin/bash

# Global Variables
# =====================================================================
export new_user="wooaras"
export installation_path="/home/${new_user}/scripts/woocommerce-aras-cargo"
sudoers_file="/etc/sudoers"
sudoers_d_file="/etc/sudoers.d/wooaras"
pass_file="/etc/passwd"

# My style
# =====================================================================
green=$(tput setaf 2); red=$(tput setaf 1); reset=$(tput sgr0); cyan=$(tput setaf 6)
magenta=$(tput setaf 5); yellow=$(tput setaf 3); BC=$'\e[32m'; EC=$'\e[0m'
m_tab='  '; m_tab_3=' '; m_tab_4='    '

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

# Create new group/user with home, grant sudo&cron privileges if not set
# =====================================================================
if ! grep -qE "^${new_user}" "${pass_file}"
  if grep -qE '%sudo.*ALL' "${sudoers_file}"; then
    if ! grep -q "#" < <(grep -E '%sudo.*ALL' "${sudoers_file}"); then
       useradd -m -s /bin/bash "${new_user}" >/dev/null 2>&1
       usermod -a -G "${new_user}",cron,sudo "${new_user}" >/dev/null 2>&1
    fi
  elif grep -qE '%sudo.*ALL' "${sudoers_file}"; then
    if ! grep -q "#" < <(grep -E '%wheel.*ALL' "${sudoers_file}" | grep -v "NOPASSWD"); then
      useradd -m -s /bin/bash "${new_user}" >/dev/null 2>&1
      usermod -a -G "${new_user}",cron,wheel "${new_user}" >/dev/null 2>&1
    fi
  else
    useradd -m -s /bin/bash "${new_user}" >/dev/null 2>&1
    usermod -a -G "${new_user}",cron "${new_user}" >/dev/null 2>&1
    if ! [[ -d "${sudoers_d_file%/*}" ]]; then
      mkdir "${sudoers_d_file%/*}"
      if ! [[ -e "${sudoers_d_file}" ]]; then
        echo -e "${new_user}\tALL=(ALL:ALL) ALL" > "${sudoers_d_file}"
      fi
    fi
  fi
fi

# Prepeare the installation environment if not set
# =====================================================================
# Create installation path
mkdir -p "${installation_path}"
# Copy files to installation path
cp -rT "${this_script_path}" "${installation_path}"
# Change ownership of installation path&files
chown -R "${new_user}":"${new_user}" "${installation_path%/*}"
# Change user
su - "${new_user}"
# Change directory to installation path
cd "${installation_path}"

# Finally start the setup
# =====================================================================
if [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
  export aras_setup_key="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')"
  sudo ./woocommerce-aras-cargo.sh --setup
elif ! [[ -f "${this_script_path}/.two.way.set" ]]; then
  export aras_setup_key="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 13 ; echo '')"
  sudo ./woocommerce-aras-cargo.sh --setup
else
  echo -e "\n${yellow}*${reset} ${green}Setup already completed.${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo "${m_tab}${yellow}If you want to re-start setup use --force or -f${reset}"
  echo -e "${m_tab}${magenta}sudo ./woo-aras-setup.sh --force${reset}\n"
  exit 1
fi
