#!/bin/bash

# Global Variables
# =====================================================================
export new_user="wooaras"
export setup_key=wooaras
export installation_path="/home/${new_user}/scripts/woocommerce-aras-cargo"
export password="Tech5self9pack"
enc_pass=$(perl -e 'print crypt($ARGV[0], "password")' $password)
sudoers_file="/etc/sudoers"
sudoers_d_file="/etc/sudoers.d/${new_user}"
pass_file="/etc/passwd"

# My style
# =====================================================================
green=$(tput setaf 2); red=$(tput setaf 1); reset=$(tput sgr0); cyan=$(tput setaf 6)
magenta=$(tput setaf 5); yellow=$(tput setaf 3); m_tab='  '

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
modified=0
if ! grep -qE "^${new_user}" "${pass_file}"; then
  if grep -qE '%sudo.*ALL' "${sudoers_file}"; then
    if ! grep -q "#" < <(grep -E '%sudo.*ALL' "${sudoers_file}"); then
       useradd -m -p "${enc_pass}" -s /bin/bash "${new_user}" >/dev/null 2>&1
       usermod -a -G "${new_user}",cron,sudo "${new_user}" >/dev/null 2>&1
       modified=1
    fi
  fi
  if grep -qE '%sudo.*ALL' "${sudoers_file}"; then
    if ! grep -q "#" < <(grep -E '%wheel.*ALL' "${sudoers_file}" | grep -v "NOPASSWD"); then
      useradd -m -p "${enc_pass}" -s /bin/bash "${new_user}" >/dev/null 2>&1
      usermod -a -G "${new_user}",cron,wheel "${new_user}" >/dev/null 2>&1
      modified=1
    fi
  fi
  if [[ "${modified}" -eq 0 ]]; then
    useradd -m -p "${enc_pass}" -s /bin/bash "${new_user}" >/dev/null 2>&1
    usermod -a -G "${new_user}",cron "${new_user}" >/dev/null 2>&1
    if ! [[ -d "${sudoers_d_file%/*}" ]]; then
      mkdir "${sudoers_d_file%/*}"
      if ! [[ -e "${sudoers_d_file}" ]]; then
        echo -e "${new_user}\tALL=(ALL:ALL) ALL" > "${sudoers_d_file}"
      fi
    fi
  fi
fi

# Prepeare the installation environment, if not set
# =====================================================================
# Create installation path
mkdir -p "${installation_path}"

# Copy files from temporary path to installation path & change ownership
if ! [[ "$(ls -A ${installation_path})" ]]; then
  cp -rT "${this_script_path}" "${installation_path}"
  chmod +x "${installation_path}"/woo-aras-setup.sh
  chmod +x "${installation_path}"/woocommerce-aras-cargo.sh
  if [[ "$(stat --format "%U" "${installation_path}/woo-aras-setup.sh" 2>/dev/null)" != "${new_user}" ]]; then
    # Change ownership of installation path&files
    chown -R "${new_user}":"${new_user}" "${installation_path%/*}"
  fi
fi

# Change directory to installation path
if [[ "$(pwd)" != "${installation_path}" ]]; then
  cd "${installation_path}"
fi

# Finally start the setup
# =====================================================================
if [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
  su -s /bin/bash -c 'sudo --preserve-env=new_user,setup_key,installation_path,password -S <<< '"${password}"' ./woocommerce-aras-cargo.sh --setup' "${new_user}"
elif ! [[ -f "${this_script_path}/.two.way.set" ]]; then
  su -s /bin/bash -c 'sudo --preserve-env=new_user,setup_key,installation_path,password -S <<< '"${password}"' ./woocommerce-aras-cargo.sh --setup' "${new_user}"
else
  echo -e "\n${yellow}*${reset} ${green}Setup already completed.${reset}"
  echo "${cyan}${m_tab}#####################################################${reset}"
  echo "${m_tab}${yellow}If you want to re-start setup use --force or -f${reset}"
  echo -e "${m_tab}${magenta}sudo ./woo-aras-setup.sh --force${reset}\n"
  exit 1
fi
