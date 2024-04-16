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

# Be nice on production
renice 19 $$ > /dev/null 2> /dev/null

# Set color
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

# Early check bash exists and met version requirement
# This function written in POSIX for portability but rest of script is bashify
detect_bash () {
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
  elif [ $((bash_ver)) -lt 4 ]; then
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

if ! detect_bash; then
  echo -e "\n${red}*${reset} ${red}FATAL ERROR: Need BASH v4+${reset}"
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

# Container extras for github action workflow
container_extras () {
  {
  apt update
  pacman -Syy
  zypper refresh
  echo n | dnf distro-sync
  echo n | yum update
  apk update
  eix-sync 
  apt-get -yq install curl iproute2 
  yum -yq install curl iproute
  dnf -yq --setopt=strict=0 install curl iproute
  pacman --noconfirm --quiet --needed -S curl iproute2
  apk -q add curl iprote2
  emerge --ask=n --quiet --quiet-build --quiet-fail net-misc/curl sys-apps/iproute2
  } >/dev/null 2>&1
}
[[ "${github_test}" ]] && { export github_test=1; container_extras; }

export new_user="wooaras"
export setup_key="$(cat /sys/class/net/$(ip route show default | awk '/default/ {print $5}')/address | tr -d ':')"
export working_path="/home/${new_user}/scripts/woocommerce-aras-kargo"
git_repo="https://github.com/psaux-it/woocommerce-aras-kargo.git"
sudoers_file="/etc/sudoers"
pass_file="/etc/passwd"
portage_php="/etc/portage/package.use/woo_php"

# Fatal exit
fatal () {
  printf >&2 "\n${m_tab}%s ABORTED %s %s \n\n" "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD}" "${TPUT_RESET}" "${*}"
  exit 1
}

get_column () {
  if command -v curl > /dev/null 2>&1; then
    cd /tmp
    curl -sLk https://psaux-it.github.io/column2 -o column2
  elif command -v wget > /dev/null 2>&1; then
    cd /tmp
    wget -q --no-check-certificate -O column2 https://psaux-it.github.io/column2
  fi
  
  [[ -f "/tmp/column2" ]] && chmod +x column2
  [[ ! -d "/usr/local/bin" ]] && mkdir -p /usr/local/bin
  mv /tmp/column2 /usr/local/bin/
  
  [[ -f "/usr/local/bin/column2" ]] && my_column="/usr/local/bin/column2"
}

# We need column command from util-linux package, not from bsdmainutils
# Debian based distributions affected by this bug
# https://bugs.launchpad.net/ubuntu/+source/util-linux/+bug/1705437
util_linux () {
  if command -v column > /dev/null 2>&1; then
    if ! column -V 2>/dev/null | grep -q "util-linux"; then
      get_column
    else
      my_column=$(command -v column 2>/dev/null)
    fi
  else
    get_column  
  fi
}

done_ () {
  printf >&2 "\n${m_tab}${TPUT_BGGREEN}${TPUT_WHITE}${TPUT_BOLD} DONE ${TPUT_RESET} ${*}\n"
}

# Collected errors
error () {
  printf >&2 "\n${m_tab}%s ABORTED %s %s \n\n" "${TPUT_BGRED}${TPUT_WHITE}${TPUT_BOLD}" "${TPUT_RESET}" "${*}"
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

script_path_pretty_error () {
  echo -e "\n${red}*${reset} ${red}Could not determine script name and fullpath${reset}"
  echo -e "${cyan}${m_tab}#####################################################${reset}\n"
  exit 1
}

version () {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }';
}

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
    fatal "FAIL --> UNSUPPORTED LINUX DISTRIBUTION"
  elif [[ "${1}" == "--os" ]]; then
    fatal "FAIL --> CANNOT IDENTIFY YOUR LINUX DISTRIBUTION"
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

check_locale () {
  if command -v locale >/dev/null 2>&1; then
    m_ctype=$(locale | grep LC_CTYPE | cut -d= -f2 | cut -d_ -f1 | tr -d '"')
    if [[ "${m_ctype}" != "en" ]]; then
      if ! locale -a | grep -iq "en_US.utf8"; then
        locale_missing=1
        return 1
      fi
    fi
  else
    return 1
  fi
  return 0
}

# Container extras for github action workflow
container_extras () {
  {
  apt update
  pacman -Syy
  zypper refresh
  echo n | dnf distro-sync
  echo n | yum update
  apk update
  eix-sync 
  apt-get -yq install curl iproute2 
  yum -yq install curl iproute2
  dnf -yq --setopt=strict=0 install curl iproute2
  pacman --noconfirm --quiet --needed -S curl iproute2
  apk -q add curl iprote2
  emerge --ask=n --quiet --quiet-build --quiet-fail net-misc/curl sys-apps/iproute2
  } >/dev/null 2>&1
}

# Package lists for distributions
get_package_list () {
  declare -A pkg_make=(
    ['ubuntu']="build-essential"
    ['debian']="build-essential"
    ['arch']="base-devel"
    ['manjaro']="base-devel"
    ['gentoo']="sys-devel/make"
    ['default']=""
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

  declare -A pkg_perl=(
    ['gentoo']="dev-lang/perl"
    ['default']="perl"
  )

  declare -A pkg_perl_app_cpanminus=(
    ['centos']="perl-App-cpanminus"
    ['fedora']="perl-App-cpanminus"
    ['rhel']="perl-App-cpanminus"
    ['ubuntu']="cpanminus"
    ['debian']="cpanminus"
    ['arch']="cpanminus"
    ['manjaro']="cpanminus"
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
    ['arch']=""
    ['manjaro']=""
    ['centos']="php-soap"
    ['fedora']="php-soap"
    ['rhel']="php-soap"
    ['ubuntu']="php-soap"
    ['debian']="php-soap"
    ['suse']="php-soap"
    ['opensuse-leap']="php-soap"
    ['opensuse-tumbleweed']="php-soap"
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
    ['manjaro']="libnewt"
    ['default']="newt"
  )

  declare -A pkg_sudo=(
    ['gentoo']="app-admin/sudo"
    ['default']="sudo"
  )

  declare -A pkg_locale_gen=(
    ['debian']="locales"
    ['ubuntu']="locales"
  )

  declare -A pkg_column=(
    ['gentoo']="sys-apps/util-linux"
    ['debian']="bsdmainutils"
    ['ubuntu']="bsdmainutils"
    ['default']="util-linux"
  )

  declare -A pkg_lang=(
    ['debian']="locales-all"
    ['ubuntu']="locales-all"
    ['fedora']="glibc-langpack-en"
    ['centos']="glibc-langpack-en"
    ['rhel']="glibc-langpack-en"
    ['opensuse-tumbleweed']="glibc-locale"
    ['opensuse-leap']="glibc-locale"
  )

  declare -A pkg_gzip=(
    ['gentoo']="app-arch/gzip"
    ['default']="gzip"
  )
  
  declare -A pkg_systemctl=(
    ['gentoo']="sys-apps/systemd"
    ['default']="systemd"
  )

  # Get package names from missing dependencies for running distribution
  for dep in "${missing_deps[@]}"
  do
    if [[ "${dep}" == "locale-gen" ]]; then
      dep="locale_gen"
    fi

    eval "p=\${pkg_${dep}['${distribution,,}']}"
    [[ ! "${p}" ]] && eval "p=\${pkg_${dep}['default']}"
    [[ "${p}" ]] && packages+=( "${p}" )
  done

  if ! check_locale; then
    eval "p=\${pkg_lang['${distribution,,}']}"
    [[ "${p}" ]] && packages+=( "${p}" )
  fi
}

pre_start () {
  if [[ ! "$(id -u $new_user 2>/dev/null)" || "${#missing_deps[@]}" -ne 0 || ! -d "${working_path}" || -n "${locale_missing}" ]]; then
    wooaras_banner "GETTING THINGS READY :)"

    if [[ "${distribution}" ]]; then
      echo -e "\n${green}* ${magenta}OS INFORMATION${reset}"
      echo "${cyan}${m_tab}+----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+--->${reset}"
      {
      echo "${green}Operating_System: $(uname -o 2>/dev/null || uname -rs)${reset}"
      echo "${green}Distribution: ${distribution}${reset}"
      echo "${green}Version: ${version}${reset}"
      echo "${green}Codename: ${codename// /_}${reset}"
      echo "${green}Package_Manager: ${package_installer}${reset}"
      echo "${green}Detection_Method: ${detection}${reset}"
      } | $my_column -o '       ' -t -s ' ' | sed 's/^/  /'
    fi

    if (( ${#missing_deps[@]} )); then
      shopt -s extglob
      get_package_list
      echo -e "\n${green}* ${magenta}STAGE-1 > PACKAGE INSTALLATION${reset}"
      echo "${cyan}${m_tab}+----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+--->${reset}"
      fixed_packages=( "${packages[@]}" )
      if [[ "${missing_deps[@]}" =~ "make" ]]; then
        if [[ "${distribution}" != @(ubuntu|debian|arch|manjaro) ]]; then
          fixed_packages+=( "make" )
        fi
      fi
      my_fixed_packages="${fixed_packages[@]}"
      {
      if [[ "${missing_deps[@]}" =~ "perl_text_fuzzy" ]]; then
        echo "${green}Missing_Packages: ${my_fixed_packages//${IFS:0:1}/,},Text::Fuzzy${reset}"
      else
        echo "${green}Missing_Packages: ${my_fixed_packages//${IFS:0:1}/,}${reset}"
      fi
      } | $my_column -o '       ' -t -s ' ' | sed 's/^/  /'
    else
      done_ "STAGE-1 > PACKAGE INSTALLATION"
    fi

    if ! grep -qE "^${new_user}:" "${pass_file}"; then
      echo -e "\n${green}* ${magenta}STAGE-2 > USER OPERATIONS${reset}"
      echo "${cyan}${m_tab}+----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+--->${reset}"
      {
      echo "${green}New_System_User: ${new_user}${reset}"
      echo "${green}Default_User_Password: ${new_user}${reset}"
      echo "${green}User_Home_Folder: /home/${new_user}${reset}"
      echo "${green}Home_Permission: 700${reset}"
      echo "${green}UserWillBeSudoerFor: woo-aras-setup.sh,woocommerce-aras-cargo.sh${reset}"
      } | $my_column -t -s ' ' | sed 's/^/  /'
    else
      done_ "STAGE-2 > USER OPERATIONS"
    fi

    if ! [[ -d "${working_path}" ]]; then
      echo -e "\n${green}* ${magenta}STAGE-3 > ENVIRONMENT OPERATIONS${reset}"
      echo "${cyan}${m_tab}+----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+--->${reset}"
      {
      echo "${green}New_Working_Path: ${working_path}${reset}"
      echo "${green}Setup_Script_Path: ${working_path}/woo-aras-setup.sh${reset}"
      echo "${green}Main_Script_Path: ${working_path}/woocommerce-aras-cargo.sh${reset}"
      } | $my_column -o '      ' -t -s ' ' | sed 's/^/  /'
    else
      done_ "STAGE-3 > ENVIRONMENT OPERATIONS"
    fi

    if [[ "${locale_missing}" ]]; then
      echo -e "\n${green}* ${magenta}STAGE-4 > LOCALIZATION OPERATIONS${reset}"
      echo "${cyan}${m_tab}+----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+-----+--->${reset}"
      {
      echo "${green}New_Locale: en_US.UTF-8${reset}"
      } | $my_column -o '             ' -t -s ' ' | sed 's/^/  /'
    else
      done_ "STAGE-4 > LOCALIZATION OPERATIONS"
    fi

    while :; do
      echo -e "\n${cyan}${m_tab}###################################################${reset}"
      read -r -n 1 -p "${m_tab}${BC}Do you want to continue pre-setup? --> (Y)es | (N)o${EC} " yn
      echo ""
      case "${yn}" in
        [Yy]* ) break;;
        [Nn]* ) exit 1;;
        * ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}";;
      esac
    done

    echo -e "\n${m_tab}${magenta}${TPUT_BOLD}< THIS MAY TAKE A WHILE >${reset}"
    echo -e "${m_tab}${cyan}--+--+--+--+--+--+--+--->${reset}\n"
  fi
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
      [[ ! -d "/usr/local/bin" ]] && mkdir -p /usr/local/bin
      mv jq /usr/local/bin/jq
      } >/dev/null 2>&1
    elif command -v curl >/dev/null 2>&1; then
      {
      cd /tmp
      curl -sLk ${jq_url} -o jq
      chmod +x jq
      [[ ! -d "/usr/local/bin" ]] && mkdir -p /usr/local/bin
      mv jq /usr/local/bin/jq
      } >/dev/null 2>&1
    fi

    if command -v jq >/dev/null 2>&1; then
      if command -v sha256sum >/dev/null 2>&1; then
        [[ "$(sha256sum $(type jq | awk '{print $3}'))" != "${jq_sha256sum}" ]] && { return 1; rm -f /usr/local/bin/jq >/dev/null 2>&1; }
      elif command -v shasum >/dev/null 2>&1; then
        [[ "$(shasum -a 256 $(type jq | awk '{print $3}'))" != "${jq_sha256sum}" ]] && { return 1; rm -f /usr/local/bin/jq >/dev/null 2>&1; }
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
validate_centos () {
  fail=()
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    packages+=( "make" )
  fi

  for packagename in "${packages[@]}"
  do
    if ! $my_yum list installed ${packagename} >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_rhel () {
  fail=()
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    packages+=( "make" )
  fi

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
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    packages+=( "make" )
  fi

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
  # In arch, soap extension is builtin
  # Soap extension is missing?
  if [[ "${missing_deps[@]}" =~ "soap" ]]; then
    # Check php is installed first
    if pacman -Qqs | grep -q "php" >/dev/null 2>&1; then
      # Enable soap extension
      sed -i 's/;extension=soap/extension=soap/g' /etc/php/php.ini
    fi
  fi

  # Base-devel is a group and cannot validate its own name
  if [[ "${packages[@]}" =~ "base-devel" ]]; then
    packages=( "${packages[@]/base-devel/make}" )
  fi

  for packagename in "${packages[@]}"
  do
    if ! pacman -Qqs | grep -q "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_manjaro () {
  fail=()
  # In arch based distros, soap extension is builtin
  # Soap extension is missing?
  if [[ "${missing_deps[@]}" =~ "soap" ]]; then
    # Check php is installed first
    if pacman -Qqs | grep -q "php" >/dev/null 2>&1; then
      # Enable soap extension
      sed -i 's/;extension=soap/extension=soap/g' /etc/php/php.ini
    fi
  fi

  # Base-devel is a group and cannot validate its own name in arch based
  if [[ "${packages[@]}" =~ "base-devel" ]]; then
    packages=( "${packages[@]/base-devel/make}" )
  fi

  for packagename in "${packages[@]}"
  do
    if ! pacman -Qqs | grep -q "$packagename" >/dev/null 2>&1; then
      fail+=( "${packagename}" )
    fi
  done
}

validate_suse () {
  fail=()
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    packages+=( "make" )
  fi

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
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    packages+=( "make" )
  fi

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
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    packages+=( "make" )
  fi

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
  declare -a dependencies=("curl" "openssl" "php" "perl" "whiptail" "logrotate" "git" "make" "gawk" "sudo" "locale-gen" "column" "gzip" "systemctl")
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

# +-----+-----+--->
check_deps
check_locale
autodetect_distribution &&
{
autodetect_package_manager || un_supported --pm
} ||
un_supported --os
export distribution
util_linux
pre_start
# +-----+-----+--->

install_centos () {
  local group
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    group=@'Development Tools'
  fi
  opts="-yq install"
  repo="update"
  echo n | $my_yum ${repo} &>/dev/null &
  my_wait "SYNCING REPOSITORY"
  replace_suc "REPOSITORIES SYNCED"
  $my_yum ${opts} "${packages[@]}" "$(echo $group)" &>/dev/null &
  post_ops "INSTALLING PACKAGES"
}

install_debian () {
  opts="-yq install"
  repo="update"
  $my_apt_get ${repo} &>/dev/null &
  my_wait "SYNCING REPOSITORY"
  replace_suc "REPOSITORIES SYNCED"
  DEBIAN_FRONTEND=noninteractive $my_apt_get ${opts} "${packages[@]}" &>/dev/null &
  post_ops "INSTALLING PACKAGES"
}

properties_common () {
  if ! command -v add-apt-repository; then
    apt-get -yq install software-properties-common &>/dev/null &
    my_wait "INSTALLING PROPERTIES COMMON" && replace_suc "PROPERTIES COMMON INSTALLED  " || fatal "FAIL_STAGE-1 --> PROPERTIES COMMON CANNOT INSTALLED"
  fi
}

install_ubuntu () {
  # These are ubuntu extra repositories
  local multiverse_enabled universe_enabled restricted_enabled
  multiverse_enabled=0
  universe_enabled=0
  restricted_enabled=0
  opts="-yq install"
  repo="update"
  if ! grep -r --include '*.list' '^deb ' /etc/apt/sources.list* | grep -q "multiverse"; then
    properties_common
    add-apt-repository multiverse &>/dev/null &
    my_wait "ADDING MULTIVERSE REPOSITORY" && { replace_suc "MULTIVERSE REPOSITORY ADDED  "; multiverse_enabled=1; } ||
    { replace_fail "ADDING MULTIVERSE REPOSITORY FAILED"; i_error+=( "multiverse" ); }
  fi
  if ! grep -r --include '*.list' '^deb ' /etc/apt/sources.list* | grep -q "universe"; then
    properties_common
    add-apt-repository universe &>/dev/null &
    my_wait "ADDING UNIVERSE REPOSITORY" && { replace_suc "UNIVERSE REPOSITORY ADDED  "; universe_enabled=1; } ||
    { replace_fail "ADDING UNIVERSE REPOSITORY FAILED"; i_error+=( "universe" ); }
  fi
  if ! grep -r --include '*.list' '^deb ' /etc/apt/sources.list* | grep -q "restricted"; then
    properties_common
    add-apt-repository restricted &>/dev/null &
    my_wait "ADDING RESTRICTED REPOSITORY" && { replace_suc "RESTRICTED REPOSITORY ADDED  "; restricted_enabled=1; } ||
    { replace_fail "ADDING RESTRICTED REPOSITORY FAILED"; i_error+=( "restricted" ); }
  fi
  if (( ${#i_error[@]} )); then
    fatal "ADDING REPOSITORIES FAILED --> ${i_error[*]}"
  fi
  $my_apt_get ${repo} &>/dev/null &
  my_wait "SYNCING REPOSITORY"
  replace_suc "REPOSITORIES SYNCED"
  DEBIAN_FRONTEND=noninteractive $my_apt_get ${opts} "${packages[@]}" &>/dev/null &
  post_ops "INSTALLING PACKAGES"
  if [[ "${multiverse_enabled}" -eq 1 ]]; then
    add-apt-repository --remove multiverse &>/dev/null
  fi
  if [[ "${universe_enabled}" -eq 1 ]]; then
    add-apt-repository --remove universe &>/dev/null
  fi
  if [[ "${restricted_enabled}" -eq 1 ]]; then
    add-apt-repository --remove restricted &>/dev/null
  fi
}

install_gentoo () {
  if [[ "${packages[@]}" =~ "^php" ]]; then
    echo 'dev-lang/php soap' > "${portage_php}"
  fi
  opts="--ask=n --quiet --quiet-build --quiet-fail"
  repo="--sync"
  $my_emerge ${repo} &>/dev/null &
  my_wait "SYNCING REPOSITORY"
  replace_suc "REPOSITORIES SYNCED"
  $my_emerge ${opts} "${packages[@]}" &>/dev/null &
  post_ops "INSTALLING PACKAGES"
}

install_arch () {
  opts="--noconfirm --quiet --needed -S"
  repo="-Syy"
  $my_pacman ${repo} &>/dev/null &
  my_wait "SYNCING REPOSITORY"
  replace_suc "REPOSITORIES SYNCED"
  $my_pacman ${opts} "${packages[@]}" &>/dev/null &
  post_ops "INSTALLING PACKAGES"
}

install_manjaro () {
  opts="--noconfirm --quiet --needed -S"
  repo="-Syy"
  pacman-mirrors --fasttrack 5 &>/dev/null &
  my_wait "SEARCHING FASTEST MIRRORS" && replace_suc "FASTEST MIRROR SELECTED"
  $my_pacman ${repo} &>/dev/null &
  my_wait "SYNCING REPOSITORY"
  replace_suc "REPOSITORIES SYNCED"
  $my_pacman ${opts} "${packages[@]}" &>/dev/null &
  post_ops "INSTALLING PACKAGES"
}

install_suse () {
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
}

install_opensuse-leap () {
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
}

install_opensuse-tumbleweed () {
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
}

install_fedora () {
  local group
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    group=@'Development Tools'
  fi
  opts="-yq --setopt=strict=0 install"
  repo="distro-sync"
  echo n | $my_dnf ${repo} &>/dev/null &
  my_wait "SYNCING REPOSITORY"
  replace_suc "REPOSITORIES SYNCED"
  $my_dnf ${opts} "${packages[@]}" "$(echo $group)" &>/dev/null &
  post_ops "INSTALLING PACKAGES"
}

install_rhel () {
  local group
  if [[ "${missing_deps[@]}" =~ "make" ]]; then
    group=@'Development Tools'
  fi
  if [[ "${my_yum}" ]]; then
    opts="-yq install"
    repo="update"
    echo n | $my_yum ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED"
    $my_yum ${opts} "${packages[@]}" "$(echo $group)" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  else
    opts="-yq --setopt=strict=0 install"
    repo="distro-sync"
    echo n | $my_dnf ${repo} &>/dev/null &
    my_wait "SYNCING REPOSITORY"
    replace_suc "REPOSITORIES SYNCED "
    $my_dnf ${opts} "${packages[@]}" "${group}" &>/dev/null &
    post_ops "INSTALLING PACKAGES"
  fi
}

# STAGE-1 @PACKAGE INSTALLATION
# =====================================================================
if (( ${#missing_deps[@]} )); then
  # Test connection for package installation
  test_connection

  install_${distribution}

  # Check package installation completed without error &
  # Installing Text::Fuzzy perl module needs ( App::cpanminus ( make ))
  if ! (( ${#fail[@]} )); then
    replace_suc "PACKAGES INSTALLED "
    if [[ "${missing_deps[@]}" =~ "fuzzy" ]]; then
        cpanm -Sq Text::Fuzzy &>/dev/null &
        my_wait "INSTALLING PERL MODULES" && replace_suc "PERL MODULES INSTALLED " || replace_fail "INSTALLING PERL MODULES FAILED"
    fi
  else
    replace_fail "INSTALLING PACKAGES FAILED"
    fake_progress "INSTALLING PERL MODULES"
    replace_fail "INSTALLING PERL MODULES FAILED"
  fi

  # Re-check deps to validate whole package installation
  check_deps
  # Get column from util-linux if we have bsdmainutils
  util_linux

  ###################################################################################
  # NOT TRY TO REMOVE ELEMENTS FROM ARRAY THIS WAY
  # LEAVES EMPTY STRING -- NOT REFLECTING TO ARRAY LENGHT
  ###################################################################################
  # if [[ "${distribution}" == @(opensuse-leap|opensuse-tumbleweed|opensuse) ]]; then
  #   if [[ "${missing_deps[@]}" =~ "locale-gen" ]]; then
  #     missing_deps=( "${missing_deps[@]/locale-gen}" )
  #   fi
  # fi
  
  ###################################################################################
  # YOU CAN WALK IN ARRAY, FIND TARGET ELEMENT AND UNSET IT, BUT
  # CAUSES INDICES SEQUENCE BROKEN YOU NEED TO RECREATE ARRAY FOR GAPS !
  ###################################################################################
  # locale-gen breaks these distros
  if [[ "${distribution}" == @(opensuse-leap|opensuse-tumbleweed|opensuse|fedora) ]]; then
    if [[ "${missing_deps[@]}" =~ "locale-gen" ]]; then
      for i in "${!missing_deps[@]}"; do
        if [[ ${missing_deps[i]} = "locale-gen" ]]; then
          unset 'missing_deps[i]'
        fi
      done
    fi
  fi

  if (( ${#missing_deps[@]} )); then
    fixed_missing=( "${missing_deps[@]//_/-}" )
    fatal "FAIL_STAGE-1 --> CANNOT INSTALL: ${fixed_missing[*]/perl-text-fuzzy/Text::Fuzzy}"
  fi
fi

# STAGE-2 @USER OPERATIONS
# =====================================================================
# Check user exist, if not create
if ! grep -qE "^${new_user}:" "${pass_file}"; then
  u_error=()
  fake_progress "USER OPERATIONS"
  #Encrypt password
  enc_pass=$(perl -e 'print crypt($ARGV[0], "password")' $new_user || { replace_fail "USER OPERATIONS FAILED"; u_error+=( "enc" ); })
  # Create user
  useradd -K UMASK=0077 -U -m -p "${enc_pass}" -s /bin/bash "${new_user}" >/dev/null 2>&1 || { replace_fail "USER OPERATIONS FAILED"; u_error+=( "add" ); }
  # Grant sudo priv. for only execute setup and main script
  [[ ! -d /etc/sudoers.d ]] && mkdir /etc/sudoers.d
  if [[ $(version $(sudo -V | head -n1 | awk '{print $3}')) -ge $(version "1.9.1") ]]; then
    if grep -q "@includedir.*/etc/sudoers.d" /etc/sudoers; then
      if grep '^ *#' /etc/sudoers | grep -q "@includedir.*/etc/sudoers.d"; then
        sed -i '/@includedir \/etc\/sudoers.d/s/^#*\s*//g' /etc/sudoers || { replace_fail "USER OPERATIONS FAILED"; u_error+=( "sed" ); }
      fi
    else
      echo "@includedir /etc/sudoers.d" >> /etc/sudoers
    fi
  elif ! grep -q "#includedir.*/etc/sudoers.d" /etc/sudoers && ! grep -q "#include.*/etc/sudoers.d" /etc/sudoers; then
    echo "#includedir /etc/sudoers.d" >> /etc/sudoers
  fi
  d_umask=$(umask)
  umask 226 && echo "${new_user} ALL=(ALL) NOPASSWD:SETENV: ${working_path}/woocommerce-aras-cargo.sh,${working_path}/woo-aras-setup.sh" | (sudo su -c 'EDITOR="tee" visudo -f /etc/sudoers.d/wooaras') >/dev/null 2>&1 ||
  { replace_fail "USER OPERATIONS FAILED"; u_error+=( "sudo" ); }
  umask "${d_umask}"
  if (( ${#u_error[@]} )); then
    for err in "${u_error[@]}"
    do
      if [[ "${err}" == "enc" ]]; then
        error "FAIL_STAGE-2 --> USER PASSWORD ENCRYPTION ERROR"
      elif [[ "${err}" == "add" ]]; then
        error "FAIL_STAGE-2 --> CANNOT CREATE USER"
      elif [[ "${err}" == "sudo" ]]; then
        error "FAIL_STAGE-2 --> CANNOT GRANT SUDO"
      elif [[ "${err}" == "sed" ]]; then
        error "FAIL_STAGE-2 --> CANNOT GRANT SUDO"
      fi
    done
    exit 1
  else
    replace_suc "USER OPERATIONS COMPLETED"
  fi
fi

# STAGE-3 @ENVIRONMENT OPERATIONS
# =====================================================================
if ! [[ -d "${working_path}" ]]; then
  e_error=()
  fake_progress "ENVIRONMENT OPERATIONS"
  if [[ ! -d "${working_path%/*}" ]]; then
    mkdir -p "${working_path%/*}" >/dev/null 2>&1 || { replace_fail "ENVIRONMENT OPERATIONS FAILED"; e_error+=( "mdir" ); }
  fi
  # Clone repo to working path
  cd "${working_path%/*}" >/dev/null 2>&1 || { replace_fail "ENVIRONMENT OPERATIONS FAILED"; e_error+=( "cdir" ); }
  git clone --quiet "${git_repo}" >/dev/null 2>&1 || { replace_fail "ENVIRONMENT OPERATIONS FAILED"; e_error+=( "git" ); }
  grep -q "${working_path}" /home/"${new_user}"/.bashrc || echo "cd ${working_path}" >> /home/"${new_user}"/.bashrc
  # Set permissions
  chown -R "${new_user}":"${new_user}" "${working_path%/*}" >/dev/null 2>&1 || { replace_fail "ENVIRONMENT OPERATIONS FAILED"; e_error+=( "own" ); }
  chmod 700 "${working_path}"/woocommerce-aras-cargo.sh >/dev/null 2>&1 || { replace_fail "ENVIRONMENT OPERATIONS FAILED"; e_error+=( "mod" ); }
  if (( ${#e_error[@]} )); then
    for err in "${e_error[@]}"
    do
      if [[ "${err}" == "mdir" ]]; then
        error "FAIL_STAGE-3 --> CANNOT MAKE DIRECTORY"
      elif [[ "${err}" == "cdir" ]]; then
        error "FAIL_STAGE-3 --> CANNOT CHANGE DIRECTORY"
      elif [[ "${err}" == "git" ]]; then
        error "FAIL_STAGE-3 --> CANNOT CLONE REPOSITORY"
      elif [[ "${err}" == "own" ]]; then
        error "FAIL_STAGE-3 --> CANNOT OWN DIRECTORY"
      elif [[ "${err}" == "mod" ]]; then
        error "FAIL_STAGE-3 --> CANNOT SET PERMISSION"
      fi
    done
    exit 1
  else
    replace_suc "ENVIRONMENT OPERATIONS COMPLETED"
  fi
fi

# STAGE-4 @LOCALIZATION OPERATIONS
# =====================================================================
locale_gen () {
  locale-gen &>/dev/null &
  my_wait "INSTALLING LOCALE"
  if ! locale -a | grep -iq "en_US.utf8"; then
    replace_fail "INSTALLING LOCALE FAILED"
    fatal "FAIL_STAGE-4 --> CANNOT INSTALL en_US.UTF-8 LOCALE"
  else
    replace_suc "LOCALE INSTALLED "
  fi
}

# Try to generate needed locale kindly
if ! check_locale; then
  if command -v locale-gen >/dev/null 2>&1; then
    if grep -iq "en_US.UTF-8" /etc/locale.gen; then
      sed -i -e 's/^# en_US\.UTF-8/en_US\.UTF-8/' /etc/locale.gen
      sed -i -e 's/^#en_US\.UTF-8/en_US\.UTF-8/' /etc/locale.gen
      locale_gen
    else
      echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
      locale_gen
    fi
  else  
    fake_progress "INSTALLING LOCALE"
    replace_fail "INSTALLING LOCALE FAILED"
    fatal "FAIL_STAGE-4 --> CANNOT INSTALL en_US.UTF-8 LOCALE"
  fi
else
  fake_progress "INSTALLING LOCALE"
  replace_suc "LOCALE INSTALLED "
fi

# @START THE SETUP
# =====================================================================
my_env="new_user,setup_key,working_path,distribution"
env_info () {
  echo -e "\n${yellow}* ENVIRONMENT IS ALREADY SET !${reset}"
  echo "${m_tab}${magenta}Working under user ${new_user} is highly recommended${reset}"
  echo "${m_tab}${cyan}^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^${reset}"
  echo "${m_tab}${green}User:              ${new_user}${reset}"
  echo "${m_tab}${green}Working Path:      ${working_path}${reset}"
  echo "${m_tab}${green}Setup_Script Path: ${working_path}/woo-aras-setup.sh${reset}"
  echo -e "${m_tab}${green}Main_Script Path:  ${working_path}/woocommerce-aras-cargo.sh${reset}\n"
  echo "${m_tab}${magenta}SIMPLY: su - ${new_user}; sudo ./woo-aras-setup.sh${reset}"
  echo -e "${m_tab}${cyan}^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^${reset}\n"
  spinner
}

# Test done?
[[ "${github_test}" ]] && { env_info; exit $?; }

# Let's continue setup
if [[ "$SUDO_USER" ]]; then
  if [[ "$SUDO_USER" != "${new_user}" ]]; then
    if [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
      if ! [[ -f "${working_path}/.env.ready" ]]; then
        sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'exec < /dev/tty; sudo --preserve-env='"${my_env}"' '"${working_path}"'/woocommerce-aras-cargo.sh --setup'
      else
        env_info
        sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'exec < /dev/tty; sudo --preserve-env='"${my_env}"' '"${working_path}"'/woocommerce-aras-cargo.sh --setup'
      fi
    elif ! [[ -f "${working_path}/.woo.aras.set" ]]; then
      if ! [[ -f "${working_path}/.env.ready" ]]; then
        sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'exec < /dev/tty; sudo --preserve-env='"${my_env}"' '"${working_path}"'/woocommerce-aras-cargo.sh --setup'
      else
        env_info
        sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'exec < /dev/tty; sudo --preserve-env='"${my_env}"' '"${working_path}"'/woocommerce-aras-cargo.sh --setup'
      fi
    else
      setup_info
    fi
  elif [[ "${1}" == "--force" || "${1}" == "-f" ]]; then
    "${working_path}"/woocommerce-aras-cargo.sh --setup
  elif ! [[ -f "${working_path}/.woo.aras.set" ]]; then
    "${working_path}"/woocommerce-aras-cargo.sh --setup
  else
    setup_info
  fi
elif ! [[ -f "${working_path}/.env.ready" ]]; then # Pure root
  sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'exec < /dev/tty; sudo --preserve-env='"${my_env}"' '"${working_path}"'/woocommerce-aras-cargo.sh --setup'
else
  env_info
  sudo -u "${new_user}" --preserve-env="${my_env}" -s /bin/bash -c 'exec < /dev/tty; sudo --preserve-env='"${my_env}"' '"${working_path}"'/woocommerce-aras-cargo.sh --setup'
fi

# And lastly we exit..
exit $?
