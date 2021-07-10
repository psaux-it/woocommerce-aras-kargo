#!/bin/bash
#
# Copyright 2021 Hasan ÇALIŞIR
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
# WOOCOMMERCE - ARAS CARGO INTEGRATION
# ---------------------------------------------------------------------
# Written by : Hasan ÇALIŞIR - hasan.calisir@psauxit.com
# Version    : 1.0.5
# Bash       : 5.1.8
# Year       : 2021
# ---------------------------------------------------------------------
#
# The aim of this script is integration woocommerce and ARAS cargo.
# What is doing this script exactly?
#  -Updates woocomerce order status from processing to completed,
#  -when the matching tracking code is generated on the ARAS Cargo end.
#  -Attachs cargo information(tracking number, track link etc.) to
#  -order completed e-mail with the help of AST plugin.
#  -You can modify woocommerce completed e-mail templaete as shipped.
#
# Follow detailed installation instructions on github.
# =====================================================================

# Need for upgrade - DON'T EDIT MANUALLY
# =====================================================================
script_version="1.0.5"
# =====================================================================

# EDITABLE VARIABLES
# =====================================================================
# Logging paths
error_log="/var/log/woocommerce_aras.err"
access_log="/var/log/woocommerce_aras.log"

# Need for html mail template
company_name="E-Commerce Company"
company_domain="mycompany.com"

# Set 1 if you want to get error mails (recommended)
send_mail_err="1"

# Set notify mail info
mail_to="order_updates@${company_domain}.com"
mail_from="From: ${company_name} <aras@${company_domain}.com>"
mail_subject_suc="ORDER UPDATED: WooCommerce - ARAS Cargo Summary"
mail_subject_err="ERROR: WooCommerce - ARAS Cargo Integration Error"

# Set ARAS cargo request date range --> last 10 days
# Supports Max 30 days.
# Keep date format!
t_date=$(date +%d/%m/%Y)
e_date=$(date +%d-%m-%Y -d "+1 days")
s_date=$(date +%d-%m-%Y -d "-10 days")
# =====================================================================

# Log timestamp
timestamp () {
        date +"%Y-%m-%d %T"
}

# Check dependencies
# =====================================================================
if ! command -v curl > /dev/null 2>&1; then
	echo "curl not found."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): curl not found." >> "${error_log}"
	exit 1
fi

if ! command -v iconv > /dev/null 2>&1; then
	echo "iconv not found."
	echo "$(timestamp): iconv not found." >> "${error_log}"
	exit 1
fi

if ! command -v openssl > /dev/null 2>&1; then
	echo "openssl not found."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): openssl not found." >> "${error_log}"
	exit 1
fi

if ! command -v jq > /dev/null 2>&1; then
	echo "jq not found."
	echo "https://github.com/stedolan/jq"
	echo "Check first in distro repo otherwise compile manually."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): jq not found." >> "${error_log}"
	exit 1
fi

if ! command -v logrotate > /dev/null 2>&1; then
	echo "logrotate not found, logrotation skipped."
	echo "$(timestamp): logrotate not found, logrotation skipped." >> "${error_log}"
fi

if ! command -v php > /dev/null 2>&1; then
	echo "php not found."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): php not found." >> "${error_log}"
	exit 1
fi

if ! command -v perl > /dev/null 2>&1; then
	echo "perl not found."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): perl not found." >> "${error_log}"
	exit 1
fi

if ! perl -e 'use Text::Fuzzy;' >/dev/null 2>&1; then
	echo "perl Text::Fuzzy module not found."
	echo "Use distro repo or CPAN (https://metacpan.org/pod/Text::Fuzzy) to install"
	echo "$(timestamp): Use distro repo or CPAN (https://metacpan.org/pod/Text::Fuzzy) to install" >> "${error_log}"
	exit 1
fi

if ! command -v pstree > /dev/null 2>&1; then
	echo "pstree not found. This is not fatal error but may breaks functionality."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): pstree not found." >> "${error_log}"
fi

if ! command -v "awk" > /dev/null 2>&1; then
	echo "awk not found."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): awk not found." >> "${error_log}"
	exit 1
fi

if ! command -v "sed" > /dev/null 2>&1; then
	echo "sed not found."
	echo "If binary installed locally set installation path as system environment."
	echo "$(timestamp): sed not found." >> "${error_log}"
	exit 1
fi

if ! command -v stat > /dev/null 2>&1; then
        echo "stat not found."
        echo "If binary installed locally set installation path as system environment."
        echo "$(timestamp): stat not found." >> "${error_log}"
        exit 1
fi
# =====================================================================

# Explicit paths for specific binaries used by script.
# Best practise to avoid cron errors is declare full path of binaries.
# I expect bash-builtin commands will not cause any cron errors.
# If you use specific linux distro and face cron errors please open issue.
m_jq="$(command -v jq 2>/dev/null)"
m_pstree="$(command -v pstree 2>/dev/null)"
m_php="$(command -v php 2>/dev/null)"
m_awk="$(command -v awk 2>/dev/null)"
m_curl="$(command -v curl 2>/dev/null)"
m_sed="$(command -v sed 2>/dev/null)"
m_paste="$(command -v paste 2>/dev/null)"
m_perl="$(command -v perl 2>/dev/null)"

# Discover
this_script_full_path="${BASH_SOURCE[0]}"
# Symlinks
while [ -h "$this_script_full_path" ]; do
	this_script_path="$( cd -P "$( dirname "$this_script_full_path" )" >/dev/null 2>&1 && pwd )"
	this_script_full_path="$(readlink "$this_script_full_path")"
	# Resolve
	if [[ $this_script_full_path != /* ]] ; then
		this_script_full_path="$this_script_path/$this_script_full_path"
	fi
done

this_script_path="$( cd -P "$( dirname "$this_script_full_path" )" >/dev/null 2>&1 && pwd )"
this_script_name="$(basename "$this_script_full_path")"

if [ -z "$this_script_full_path" ] || [ -z "$this_script_path" ] || [ -z "$this_script_name" ]; then
	echo -e "\n${red}*${reset} Could not determine script name and fullpath"
	echo "${cyan}${m_tab}#####################################################${reset}"
	echo "$(timestamp): Could not determine script name and fullpath." >> "${error_log}"
	exit 1
fi

# Listen exit signals to destroy temporary files
my_tmp=$(mktemp)
trap "rm -rf ${my_tmp} ${this_script_path}/*.en ${this_script_path}/*.proc ${this_script_path}/*.json* ${this_script_path}/aras_request.php ${this_script_path}/.lvn* ${this_script_path}/levenshtein.pl" 0 1 2 3 15

# Global variables
user="$(whoami)"
cron_dir="/etc/cron.d"
shopt -s extglob; cron_dir="${cron_dir%%+(/)}"
cron_filename="woocommerce_aras"
# At every 30th minute past every hour from 9 through 20
cron_minute="*/30 9-20"
cron_user="${user}"
cron_script_full_path="$this_script_path/$this_script_name"
systemd_dir="/etc/systemd/system"
shopt -s extglob; systemd_dir="${systemd_dir%%+(/)}"
service_filename="woocommerce_aras.service"
timer_filename="woocommerce_aras.timer"
my_bash="$(command -v bash 2> /dev/null)"
systemd_script_full_path="$this_script_path/$this_script_name"
logrotate_dir="/etc/logrotate.d"
logrotate_conf="/etc/logrotate.conf"
logrotate_filename="woocommerce_aras"
sh_github="https://raw.githubusercontent.com/hsntgm/woocommerce-aras-kargo/main/woocommerce-aras-cargo.sh"
changelog_github="https://raw.githubusercontent.com/hsntgm/woocommerce-aras-kargo/main/CHANGELOG"
sh_output="${this_script_path}/woocommerce-aras-cargo.sh.tmp"
update_script="woocommerce-aras-update-script.sh"
levenshtein="levenshtein.pl"

# Determine script run by cron
TEST_CRON="$($m_pstree -s $$ | grep -c cron 2>/dev/null)"
TEST_CRON_2=$([ -z "$TERM" ] || [ "$TERM" = "dumb" ] && echo '1' || echo '0')
if [ "$TEST_CRON" == "1" ] || [ "$TEST_CRON_2" == "1" ]; then
	RUNNING_FROM_CRON=1
else
	RUNNING_FROM_CRON=0
fi

# Determine script run by systemd.
# Use systemd service environment variable if set.
# Otherwise pass default.
FROM_SYSTEMD="0"
RUNNING_FROM_SYSTEMD="${RUNNING_FROM_SYSTEMD:=$FROM_SYSTEMD}"

# My colors
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	green=`tput setaf 2`
	red=`tput setaf 1`
	reset=`tput sgr0`
	cyan=`tput setaf 6`
	magenta=`tput setaf 5`
	yellow=`tput setaf 3`
	BC=$'\e[32m'
	EC=$'\e[0m'
	m_tab='  '
	m_tab_2='              '
	m_tab_3=' '
fi


# Prevent upgrade errors cause by uncompleted downloads
# Detect to make sure the entire script is avilable, fail if the script is missing contents
if [ "$(tail -n 1 "${0}" | head -n 1 | cut -c 1-7)" != "exit \$?" ]; then
        echo -e "\n${red}*${reset} ${red}Script is incomplete, please redownload${reset}"
        echo "${cyan}${m_tab}#####################################################${reset}"
        echo "$(timestamp): Script is incomplete, please re-download" >> "${error_log}"
        exit 1
fi

# Test connection
grep -q "200" < <($m_curl -sL -w "%{http_code}\\n" "http://www.google.com/" -o /dev/null) || w_in=1
if [[ -n $w_in ]]; then
	if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
		echo "${red}*${reset} ${red}There is no internet connection.${reset}"
		echo "$(timestamp): There is no internet connection." >> "${error_log}"
	else
		echo "$(timestamp): There is no internet connection." >> "${error_log}"
	fi

	if [ $send_mail_err -eq 1 ]; then
		echo "There is no internet connection." | mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
	fi
	exit 1
fi

# Uninstall bundles like cron, systemd, logrotate, logs
uninstall () {
	if [[ -s "${cron_dir}/${cron_filename}" ]]; then
		if [[ -w "${cron_dir}/${cron_filename}" ]]; then
			rm -f  "${cron_dir}/${cron_filename}"
			echo -e "\n${green}*${reset} ${yellow}Cron uninstalled:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${cron_dir}/${cron_filename}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Cron uninstall aborted, as file not writable: ${cron_dir}/${cron_filename}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Uninstallation error: $cron_dir/$cron_filename not writeable" >> "${error_log}"
		fi
	else
		cron_uninstall=0
	fi

	if [[ -s "${systemd_dir}/${service_filename}" || -s "${systemd_dir}/${timer_filename}" ]]; then
		if [[ -w "${systemd_dir}/${service_filename}" ]]; then
			systemctl disable "${timer_filename}" >/dev/null 2>&1
			systemctl stop "${timer_filename}" >/dev/null 2>&1
			systemctl daemon-reload >/dev/null 2>&1
			rm -rf  "${systemd_dir}/${service_filename}" "${systemd_dir}/${timer_filename}"  >/dev/null 2>&1
			echo -e "\n${green}*${reset} ${yellow}Systemd unit uninstalled: services stopped:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${systemd_dir}/${service_filename}${reset}"
			echo "${yellow}${m_tab}${systemd_dir}/${timer_filename}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Systemd uninstall aborted, as directory not writable: $systemd_dir${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Uninstallation error: $systemd_dir/$service_filename not writeable" >> "${error_log}"
		fi
	else
		systemd_uninstall=0
	fi

	if [[ -s "${logrotate_dir}/${logrotate_filename}" ]]; then
		if [[ -w "${logrotate_dir}/${logrotate_filename}" ]]; then
			rm -f "${logrotate_dir}/${logrotate_filename}"
			echo -e "\n${green}*${reset} ${yellow}Logrotate removed:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${yellow}${m_tab}${logrotate_dir}/${logrotate_filename}${reset}\n"
		else
			echo -e "\n${red}*${reset} ${red}Logrotate uninstall aborted, as file not writable: ${logrotate_dir}/${logrotate_filename}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Uninstallation error: ${logrotate_dir}/${logrotate_filename} not writeable" >> "${error_log}"
		fi
	else
		logrotate_uninstall=0
	fi

	if [[ -s "${error_log}" || -s "${access_log}" ]]; then
		if [[ -w "${access_log}" || -w "${error_log}" ]]; then
			rm -rf "${error_log}" "${access_log}" >/dev/null 2>&1
			echo "${green}*${reset} ${yellow}Log files removed:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${error_log}${reset}"
			echo -e "${yellow}${m_tab}${access_log}${reset}\n"
		else
			echo "${red}*${reset} ${red}Logs cannot removed, as files not writable${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Uninstallation error: $error_log - $access_log not writeable" >> "${error_log}"
		fi
	else
		log_uninstall=0
	fi

	if [[ -n $systemd_uninstall && -n $cron_uninstall && -n $log_uninstall && -n $logrotate_uninstall ]]; then
		echo -e "\n${yellow}*${reset} ${yellow}Nothing found.${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"
	fi
}

# Disable setup after successful installation
on_fly_disable () {
	touch "${this_script_path}/.woo.aras.set"
	touch "${this_script_path}/.woo.aras.enb"
}

# Pre-setup operations
on_fly_enable () {
		# Remove lock files to start setup and enable script
		rm -rf "${this_script_path}"/.*lck >/dev/null 2>&1
		rm -f "${this_script_path}/.woo.aras.set" >/dev/null 2>&1
		rm -f "${this_script_path}/.woo.aras.enb" >/dev/null 2>&1

		# Check absolute files from previous setup
		if [[ -e "${cron_dir}/${cron_filename}" ||
			-e "${systemd_dir}/${service_filename}" ||
			-e "${logrotate_dir}/${logrotate_filename}" ||
			-e "${error_log}" ||
			-e "${access_log}" ||
			-e "${systemd_dir}/${timer_filename}" ]]; then

			echo -e "\n${green}*${reset} ${green}Found absolute files from old installation..${reset}"
			echo -ne "${cyan}${m_tab}########                                             [20%]\r${reset}"
			sleep 1
			echo -ne "${cyan}${m_tab}##################                                   [40%]\r${reset}"
			echo -ne "${cyan}${m_tab}#################################                    [60%]\r${reset}"
			sleep 2
			echo -ne "${cyan}${m_tab}#####################################                [75%]\r${reset}"
			echo -ne "${cyan}${m_tab}##########################################           [85%]\r${reset}"
			sleep 1
			echo -ne "${cyan}${m_tab}#####################################################[100%]\r${reset}"
			echo -ne '\n'

			uninstall
		fi

		# ASCII
		echo -e  "\n${cyan}${m_tab}######################################################${reset}"
		echo  "${m_tab_3}${green} __          ________ _      _____ ____  __  __ ______ "
		echo  "${m_tab_3} \ \        / |  ____| |    / ____/ __ \|  \/  |  ____|"
		echo  "${m_tab_3}  \ \  /\  / /| |__  | |   | |   | |  | | \  / | |__   "
		echo  "${m_tab_3}   \ \/  \/ / |  __| | |   | |   | |  | | |\/| |  __|  "
		echo  "${m_tab_3}    \  /\  /  | |____| |___| |___| |__| | |  | | |____ "
		echo  "${m_tab_3}     \/  \/   |______|______\_____\____/|_|  |_|______|${reset}"
		echo ""
		echo -e "${cyan}${m_tab}######################################################${reset}\n"

		# 1
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}1${reset}${m_tab_3}${red}**${reset}${yellow} Clear wordpress cache before starting the setup${reset} ${red}**${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		# 2
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}2${reset}${m_tab_3}${red}**${reset}    ${yellow}Please prepeare the following information${reset}    ${red}**${reset}"
		echo "${m_tab}${cyan}=====================================================${reset}"
		echo "${m_tab}${magenta}WooCommerce API Key (v3)"
		echo "${m_tab}WooCommerce API Secret (v3)"
		echo "${m_tab}Wordpress Domain URL"
		echo "${m_tab}ARAS SOAP API Password"
		echo "${m_tab}ARAS SOAP API Username"
		echo "${m_tab}ARAS SOAP Endpoint URL (wsdl)"
		echo "${m_tab}ARAS SOAP Merchant Code"
		echo "${m_tab}ARAS SOAP Query Type (12 or 13)${reset}"
		echo "${m_tab}${cyan}=====================================================${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		# 3
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}3${reset}${m_tab_3}${red}**${reset}${yellow}     Be sure you have WooCommerce AST Plugin${reset}     ${red}**${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		# 4
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}4${reset}${m_tab_3}${red}**${reset}${yellow} Create some test orders, If you haven't any yet${reset} ${red}**${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		read -n 1 -s -r -p "${green}> When ready press any key to continue setup, q for quit${reset}" reply < /dev/tty; echo
		if [ "$reply" == "q" ]; then
			echo
			exit 0
		fi
}

help () {
	echo -e "\n${m_tab}${cyan}# WOOCOMMERCE - ARAS CARGO INTEGRATION HELP"
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}#${m_tab}--setup        |-s      hard reset and re-starts setup"
	echo -e "${m_tab}#${m_tab}--uninstall    |-r      removes install bundles aka cron,systemd,logrotate,logs"
	echo -e "${m_tab}#${m_tab}--upgrade      |-u      upgrade script to latest version automatically"
	echo -e "${m_tab}#${m_tab}--dependencies |-d      display necessary dependencies"
	echo -e "${m_tab}#${m_tab}--version      |-v      display script version"
	echo -e "${m_tab}#${m_tab}--help         |-h      display help"
	echo -e "${m_tab}# ---------------------------------------------------------------------${reset}\n"
}

# Accept only one argument
[[ ${#} -gt 1 ]] && { help; exit 1; }

# Starts setup
if [[ "$1" == "--setup" || "$1" == "-s" ]]; then
	on_fly_enable
fi

version () {
	echo -e "\n${m_tab}${cyan}# WOOCOMMERCE - ARAS CARGO INTEGRATION VERSION"
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}# Written by : Hasan ÇALIŞIR - hasan.calisir@psauxit.com"
	echo -e "${m_tab}# Version    : 1.0.0"
	echo -e "${m_tab}# Bash       : 5.1.8"
	echo -e "${m_tab}# ---------------------------------------------------------------------${reset}\n"
}

dependencies () {
	echo -e "\n${m_tab}${cyan}# WOOCOMMERCE - ARAS CARGO INTEGRATION DEPENDENCIES"
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}# bash >= 5.1"
	echo -e "${m_tab}# curl"
	echo -e "${m_tab}# openssl"
	echo -e "${m_tab}# jq"
	echo -e "${m_tab}# php"
	echo -e "${m_tab}# iconv"
	echo -e "${m_tab}# pstree"
	echo -e "${m_tab}# gnu sed"
	echo -e "${m_tab}# gnu awk"
	echo -e "${m_tab}# stat"
	echo -e "${m_tab}# mail (mail server aka postfix)"
	echo -e "${m_tab}# woocommerce"
	echo -e "${m_tab}# woocommerce AST plugin"
	echo -e "${m_tab}# ARAS Cargo commercial account"
	echo -e "${m_tab}# ---------------------------------------------------------------------${reset}\n"
}

download () {
	$m_curl -f -s -k -R -L --compressed -z "$sh_output" -o "$sh_output" "$sh_github" >/dev/null 2>&1
	result=$?

	if [ "$result" -ne 0 ]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${red}*${reset} ${red}Upgrade failed:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Could not download: $sh_github${reset}"
			echo "$(timestamp): Upgrade failed, could not download: $sh_github" >> "${error_log}"
			exit 1
		else
			echo "$(timestamp): Upgrade failed, could not download: $sh_github" >> "${error_log}"
			exit 1
		fi
	fi

	# Test the downloaded content
	if [ "$(tail -n 1 "${sh_output}" | head -n 1 | cut -c 1-7)" != "exit \$?" ]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${red}*${reset} ${red}Upgrade failed:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Downloaded $sh_output is incomplete, please re-run${reset}"
			echo "$(timestamp): Upgrade failed, cannot verify downloaded script, please re-run." >> "${error_log}"
			exit 1
		else
			echo "$(timestamp): Upgrade failed, cannot verify downloaded script, please re-run." >> "${error_log}"
			exit 1
		fi
	fi

	# Keep user defined settings before upgrading
	u_mail_to=$(grep "^mail_to=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_mail_from=$(grep "^mail_from=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_mail_subject_suc=$(grep "^mail_subject_suc=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_mail_subject_err=$(grep "^mail_subject_err=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_e_date=$(grep "^e_date=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_s_date=$(grep "^s_date=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_error_log=$(grep "^error_log=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_access_log=$(grep "^access_log=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_send_mail_err=$(grep "^send_mail_err=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_company_name=$(grep "^company_name=" "${cron_script_full_path}" | awk -F= '{print $2}') &&
	u_company_domain=$(grep "^company_domain=" "${cron_script_full_path}" | awk -F= '{print $2}') ||
	{ echo 'Upgrade Failed. Parse error: cannot keep old user defined settings';  echo "$(timestamp): Upgrade Failed. Parse error: cannot keep old user defined settings" >> "${error_log}";  exit 1; }

	# Apply old user defined settings before upgrading
	$m_sed \
		-e "s|^mail_to=.*|mail_to=$u_mail_to|" \
		-e "s|^mail_from=.*|mail_from=$u_mail_from|" \
		-e "s|^mail_subject_suc=.*|mail_subject_suc=$u_mail_subject_suc|" \
		-e "s|^mail_subject_err=.*|mail_subject_err=$u_mail_subject_err|" \
		-e "s|^e_date=.*|e_date=$u_e_date|" \
		-e "s|^s_date=.*|s_date=$u_s_date|" \
		-e "s|^error_log=.*|error_log=$u_error_log|" \
		-e "s|^access_log=.*|access_log=$u_access_log|" \
		-e "s|^send_mail_err=.*|send_mail_err=$u_send_mail_err|" \
		-e "s|^company_name=.*|company_name=$u_company_name|" \
		-e "s|^company_domain=.*|company_domain=$u_company_domain|" \
		-i "${sh_output}" || { echo 'Upgrade Failed. Copy error: cannot copy over old user defined settings';  echo "$(timestamp): Upgrade Failed. Copy error: cannot copy over old user defined settings" >> "${error_log}";  exit 1; }

	# Copy over permissions from old version
	OCTAL_MODE="$(stat -c "%a" "${cron_script_full_path}" 2> /dev/null)"
	if [ -z "$OCTAL_MODE" ]; then
		OCTAL_MODE="$(stat -f '%p' "${cron_script_full_path}")"
	fi

	# Generate the update script
	cat > "${this_script_path}/${update_script}" <<- EOF
	#!/usr/bin/env bash

	# Overwrite old file with new
	if ! mv -f "${sh_output}" "${cron_script_full_path}"; then
		echo -e "\\n\$(tput setaf 1)*\$(tput sgr0) \$(tput setaf 1)Upgrade failed:\$(tput sgr0)"
		echo "\$(tput setaf 6)${m_tab}#####################################################\$(tput sgr0)"
		echo -e "${m_tab}\$(tput setaf 1)Failed moving ${sh_output} to ${cron_script_full_path}\$(tput sgr0)\\n"
		echo "$(timestamp): Upgrade failed: failed moving ${sh_output} to ${cron_script_full_path}" >> "${error_log}"
		rm -f \$0
		exit 1
	fi

	# Replace permission
	if ! chmod "$OCTAL_MODE" "${cron_script_full_path}"; then
		echo -e "\\n\$(tput setaf 1)*\$(tput sgr0) \$(tput setaf 1)Upgrade failed:\$(tput sgr0)"
		echo "\$(tput setaf 6)${m_tab}#####################################################\$(tput sgr0)"
		echo -e "${m_tab}\$(tput setaf 1)Unable to set permissions on ${cron_script_full_path}\$(tput sgr0)\\n"
		echo "$(timestamp): Upgrade failed: Unable to set permissions on ${cron_script_full_path}" >> "${error_log}"
		rm -f \$0
		exit 1
	fi

	echo -e "\\n\$(tput setaf 2)*\$(tput sgr0) \$(tput setaf 2)Upgrade completed.\$(tput sgr0)"
	echo "\$(tput setaf 6)${m_tab}#####################################################\$(tput sgr0)"
	echo -e "${m_tab}\$(tput setaf 2)Script updated to version ${latest_version}\$(tput sgr0)\\n"
	echo "$(timestamp): Upgrade completed. Script updated to version ${latest_version}" >> "${access_log}"
	#remove the tmp script before exit
	rm -f \$0
	EOF

	# Replaced with $0, so code will update and then call itself with the same parameters it had
	exec "$my_bash" "${this_script_path}/${update_script}"
}

upgrade () {
	latest_version=$($m_curl -s --compressed -k "$sh_github" 2>&1 | grep "^script_version=" | head -n1 | cut -d '"' -f 2)
	current_version=$(grep "^script_version=" ${cron_script_full_path} | head -n1 | cut -d '"' -f 2)
	changelog_p=$($m_curl -s --compressed -k "$changelog_github" 2>&1 | $m_sed -n "/$latest_version/,/$current_version/p" | head -n -2)

	if [ "${latest_version//./}" -gt "${current_version//./}" ]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${green}NEW UPDATE FOUND!${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${magenta}$changelog_p${reset}\n" | sed 's/^/  /'
			while true; do
				read -n 1 -p "${m_tab}${BC}Do you want to update version $latest_version? --> (Y)es | (N)o${EC} " yn < /dev/tty
				echo ""
				case "${yn}" in
					[Yy]* ) download; break;;
					[Nn]* ) exit 1;;
					* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
				esac
			done
		else
			download
		fi
	elif [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
		echo -e "\n${yellow}*${reset} ${yellow}There is no update!${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"
		echo "$(timestamp): Update process started: There is no new update." >> "${access_log}"
	else
		echo "$(timestamp): Update process started: There is no new update." >> "${access_log}"

	fi
}

while :; do
	case "${1}" in
	-u|--upgrade      ) upgrade
			  exit
			  ;;
	-r|--uninstall    ) uninstall
			  exit
			  ;;
	-d|--dependencies ) dependencies
			  exit
			  ;;
	-v|--version      ) version
			  exit
			  ;;
	-h|--help         ) help
			  exit
			  ;;
	*              )  break;;
	esac
	shift
done

# Installation
#=====================================================================
add_cron () {
	if [ ! -e "${cron_dir}/${cron_filename}" ]; then
		mkdir -p "$cron_dir" /dev/null 2>&1
		touch "${cron_dir}/${cron_filename}" /dev/null 2>&1 ||
		{ echo "could not create cron ${cron_filename}";  echo "$(timestamp): SETUP: could not create cron ${cron_filename}" >> "${error_log}";  exit 1; }
	fi

	if [ ! -w "${cron_dir}/${cron_filename}" ]; then
		echo -e "\n${red}*${reset} Cron install aborted, as file not writable: ${cron_dir}/${cron_filename}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
		echo "$(timestamp): SETUP: Cron install aborted, as file not writable: ${cron_dir}/${cron_filename}." >> "${error_log}"
		exit 1
	else
		cat <<- EOF > "${cron_dir}/${cron_filename}"
		# At every 30th minute past every hour from 9AM through 20PM
		# Via WooCommerce - ARAS Cargo Integration Script
		# Copyright 2021 Hasan ÇALIŞIR
		#MAILTO=$mail_to
		SHELL=/bin/bash
		$cron_minute * * * ${cron_user} [ -x ${cron_script_full_path} ] && ${my_bash} ${cron_script_full_path}
		EOF

		result=$?
		if [ "$result" -eq 0 ]; then
			# Set status
			on_fly_disable

			# Add logrotate
			add_logrotate

			echo -e "\n${green}*${reset} ${green}Installation completed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${green}Cron (every hour) installed to ${cyan}${cron_dir}/${cron_filename}${reset}${reset}\n"
			echo "$(timestamp): Installation completed." >> "${access_log}"
		else
			echo -e "\n${red}*${reset} ${green}Installation failed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Could not create cron {cron_dir}/${cron_filename}.${reset}"
			echo "$(timestamp): Installation failed, could not create cron {cron_dir}/${cron_filename}" >> "${error_log}"
			exit 1
		fi
	fi
	exit 0
}

add_systemd () {
	if ! command -v systemctl > /dev/null 2>&1; then
		echo -e "\n${m_tab}${red}Systemd not found. Forwarding crontab..${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		add_cron
	fi

	[ -d "/etc/systemd/system" ] || { echo -e "\n${m_tab}${yellow}Directory /etc/systemd/system does not exists. Forwarding crontab..${reset}"; add_cron; }

	touch "${systemd_dir}/${service_filename}" 2>/dev/null
	touch "${systemd_dir}/${timer_filename}" 2>/dev/null

	if [ ! -w "${systemd_dir}/${service_filename}" ]; then
		echo -e "\n${red}*${reset} ${red}Systemd install aborted, as file not writable:${reset} ${green}${systemd_dir}/${service_filename}${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
		echo "$(timestamp): Systemd install aborted, as file not writable: ${systemd_dir}/${service_filename}" >> "${error_log}"
		exit 1
	else
		cat <<- EOF > "${systemd_dir}/${service_filename}"
		[Unit]
		Description=woocommerce aras cargo integration script.

		[Service]
		Type=oneshot
		Environment=RUNNING_FROM_SYSTEMD=1
		StandardOutput=append:"${access_log}"
		StandardError=append:"${error_log}"
		ExecStart="${my_bash} ${systemd_script_full_path}"

		[Install]
		WantedBy=multi-user.target
		EOF

		cat <<- EOF > "${systemd_dir}/${timer_filename}"
		[Unit]
		Description=woocommerce-aras timer - At every 30th minute past every hour from 9AM through 20PM expect Sunday

		[Timer]
		OnCalendar=Mon..Sat 9..20:00/30:00
		Persistent=true
		Unit="${service_filename}"

		[Install]
		WantedBy=timers.target
		EOF

		systemctl daemon-reload >/dev/null 2>&1 &&
		systemctl enable "${timer_filename}" >/dev/null 2>&1 &&
		systemctl start "${timer_filename}" >/dev/null 2>&1
		result=$?

		if [ "$result" -eq 0 ]; then
			# Set status
			on_fly_disable

			# Add logrotate
			add_logrotate

			echo -e "\n${green}*${reset} ${green}Installation completed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${green}Systemd service installed to ${cyan}${systemd_dir}/${service_filename}${reset}"
			echo "${m_tab}${green}Systemd service timer installed to ${cyan}${systemd_dir}/${timer_filename}${reset}"
			echo -e "${m_tab}${green}Timer service enabled and started.${reset}\n"
			echo "$(timestamp): Installation completed." >> "${access_log}"
		else
			echo -e "\n${red}*${reset} ${green}Installation failed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Cannot start ${timer_filename} systemd service.${reset}"
			echo "$(timestamp): Installation failed, cannot start ${timer_filename} service." >> "${error_log}"
			exit 1
		fi
	fi
	exit 0
}

add_logrotate () {
	if grep -qFx "include ${logrotate_dir}" "${logrotate_conf}"; then
		if [[ ! -w "$logrotate_dir" ]]; then
			echo -e "\n${yellow}*${reset} ${yellow}WARNING: Logrotate cannot installed. $logrotate_dir is not writeable by user $user${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${yellow}You can run script as root or execute with sudo.${reset}"
			echo "$(timestamp): Logrotate cannot installed. $logrotate_dir is not writeable by user $user" >> "${error_log}"
		else
			cat <<- EOF > "${logrotate_dir}/${logrotate_filename}"
			/var/log/woocommerce_aras.* {
			weekly
			rotate 3
			size 1M
			compress
			delaycompress
			}
			EOF
		fi
	else
		cat <<- EOF >> "${logrotate_conf}"

		/var/log/woocommerce_aras.* {
		weekly
		rotate 3
		size 1M
		compress
		delaycompress
		}
		EOF
	fi
}
#=====================================================================

# WooCommerce REST & ARAS SOAP encryption/decryption operations
#=====================================================================

# Check first run of script & uncompleted setup
if [[ "$1" != "-s" && "$1" != "--setup" ]]; then
	if [[ "$(ls -1q ${this_script_path}/.*lck 2>/dev/null | wc -l)" -lt 8 ]]; then
		echo -e "\n${yellow}*${reset} ${yellow}The previous installation was not completed or${reset}"
		echo "${m_tab}${yellow}you are running the script first time without${reset}"
		echo "${m_tab}${yellow}-s parameter.${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${yellow}We can continue the installation if you wish but${reset}"
		echo "${m_tab}${yellow}If you are running the script first time please use${reset}"
		echo "${m_tab}${yellow}-s argument for guided installation. Check below table.${reset}"
		help

		read -n 1 -s -r -p "${green}>  Press any key to continue, q for quit${reset}" reply < /dev/tty; echo
		if [ "$reply" == "q" ]; then
			echo
			exit 0
		fi
	fi
fi

encrypt_wc_auth () {
	if [[ ! -s "$this_script_path/.key.wc.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your woocommerce api_key, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -p "${m_tab}${BC}Enter WooCommerce API key:${EC} " my_wc_api_key < /dev/tty
			if [ "$my_wc_api_key" == "q" ] || [ "$my_wc_api_key" == "quit" ]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_wc_api_key" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.key.wc.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.key.wc.lck/d' ~/.bash_history >/dev/null 2>&1
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .key.wc.lck. Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.key.wc.lck" >> "${error_log}"
			exit 1
		fi
	fi
	if [[ ! -s "$this_script_path/.secret.wc.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your woocommerce api_secret, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -p "${m_tab}${BC}Enter WooCommerce API secret:${EC} " my_wc_api_secret < /dev/tty
			if [ "$my_wc_api_secret" == "q" ] || [ "$my_wc_api_secret" == "quit" ]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_wc_api_secret" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.secret.wc.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.secret.wc.lck/d' ~/.bash_history >/dev/null 2>&1
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .secret.wc.lck . Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.secret.wc.lck" >> "${error_log}"
			exit 1
		fi
	fi
}

encrypt_wc_end () {
	if [[ ! -s "$this_script_path/.end.wc.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your Wordpress installation url, type q for quit${reset}"
			echo -e "${m_tab}${magenta}format --> www.example.com | www.example.com/wordpress.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -p "${m_tab}${BC}Enter Wordpress Domain URL:${EC} " my_wc_api_endpoint < /dev/tty
			if [ "$my_wc_api_endpoint" == "q" ] || [ "$my_wc_api_endpoint" == "quit" ]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_wc_api_endpoint" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.end.wc.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.end.wc.lck/d' ~/.bash_history >/dev/null 2>&1
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .end.wc.lck. Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.end.wc.lck" >> "${error_log}"
			exit 1
		fi
	fi
}

encrypt_aras_auth () {
	if [[ ! -s "$this_script_path/.key.aras.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP api_key, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -p "${m_tab}${BC}Enter ARAS SOAP API Password:${EC} " my_aras_api_pass < /dev/tty
			if [ "$my_aras_api_pass" == "q" ] || [ "$my_aras_api_pass" == "quit" ]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_aras_api_pass" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.key.aras.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.key.aras.lck/d' ~/.bash_history
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .key.aras.lck. Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.key.aras.lck" >> "${error_log}"
			exit 1
		fi
	fi
	if [[ ! -s "$this_script_path/.usr.aras.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP api_username, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -p "${m_tab}${BC}Enter ARAS SOAP API Username:${EC} " my_aras_api_usr < /dev/tty
			if [ "$my_aras_api_usr" == "q" ] || [ "$my_aras_api_usr" == "quit" ]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_aras_api_usr" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.usr.aras.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.usr.aras.lck/d' ~/.bash_history >/dev/null 2>&1
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .usr.aras.lck. Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.usr.aras.lck" >> "${error_log}"
			exit 1
		fi
	fi
	if [[ ! -s "$this_script_path/.mrc.aras.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP merchant_code, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -p "${m_tab}${BC}Enter ARAS SOAP Merchant Code:${EC} " my_aras_api_mrc < /dev/tty
			if [ "$my_aras_api_mrc" == "q" ] || [ "$my_aras_api_mrc" == "quit" ]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_aras_api_mrc" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.mrc.aras.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.mrc.aras.lck/d' ~/.bash_history >/dev/null 2>&1
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .mrc.aras.lck. Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.mrc.aras.lck" >> "${error_log}"
			exit 1
		fi
	fi
}

encrypt_aras_end () {
	if [[ ! -s "$this_script_path/.end.aras.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP endpoint_url, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -p "${m_tab}${BC}Enter ARAS SOAP endpoint URL (wsdl):${EC} " my_aras_api_end < /dev/tty
			if [ "$my_aras_api_end" == "q" ] || [ "$my_aras_api_end" == "quit" ]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_aras_api_end" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.end.aras.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.end.aras.lck/d' ~/.bash_history
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .end.aras.lck. Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.end.aras.lck" >> "${error_log}"
			exit 1
		fi
	fi
}

encrypt_aras_qry () {
	if [[ ! -s "$this_script_path/.qry.aras.lck" ]]; then
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP query_type.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			while true; do
				read -p "${m_tab}${BC}Enter ARAS SOAP query type:${EC} " my_aras_api_qry < /dev/tty
				case "${my_aras_api_qry}" in
					12) break;;
					13) break;;
				 	q) exit 1; break;;
					*) echo "${m_tab}${red}Only query type 12,13 supported. Type 'q' for exit ${reset}" ;;
				esac
			done
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "$my_aras_api_qry" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "$this_script_path/.qry.aras.lck"
			# delete sensetive data from bash history
			history -w && $m_sed -i '/.qry.aras.lck/d' ~/.bash_history
		else
			if [ $send_mail_err -eq 1 ]; then
				echo "Woocommerce-Aras Cargo integration error. Missing file .qry.aras.lck. Please re-start setup manually." |
				mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
			fi
			echo "$(timestamp): Missing file $this_script_path/.qry.aras.lck" >> "${error_log}"
			exit 1
		fi
	fi
}

encrypt_wc_auth && encrypt_wc_end && encrypt_aras_auth && encrypt_aras_end && encrypt_aras_qry ||
{ echo 'encrypt error';  echo "$(timestamp): Encrypt error." >> "${error_log}";  exit 1; }

# decrypt ARAS SOAP API credentials
decrypt_aras_auth () {
	api_key_aras=$(< "$this_script_path/.key.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	api_usr_aras=$(< "$this_script_path/.usr.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	api_mrc_aras=$(< "$this_script_path/.mrc.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
}
decrypt_aras_end () {
	api_end_aras=$(< "$this_script_path/.end.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
}
api_qry_aras=$(< "$this_script_path/.qry.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)

# decrypt WooCommerce API credentials
decrypt_wc_auth () {
	api_key=$(< "$this_script_path/.key.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	api_secret=$(< "$this_script_path/.secret.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
}
decrypt_wc_end () {
	api_endpoint=$(< "$this_script_path/.end.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
}

decrypt_aras_auth && decrypt_aras_end && decrypt_wc_auth && decrypt_wc_end ||
{ echo 'decrypt error'; echo "$(timestamp): Decrypt error." >> "${error_log}"; exit 1; }
#=====================================================================

# Controls
#=====================================================================
# Pre-defined curl functions for various tests
w_curl_s () {
	$m_curl -H "Content-Type: application/json" "https://$api_endpoint/wp-json/wc/v3/system_status" > "$this_script_path/curl.proc" 2>&1
}

w_curl_a () {
	$m_curl -X GET \
		-u "$api_key":"$api_secret" \
		-H "Content-Type: application/json" \
		"https://$api_endpoint/wp-json/wc/v3/customers" > "$this_script_path/curl.proc" 2>&1
}

# Test Wordpress domain & host connection
w_curl_s
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	try=0
	while grep -q "Could not resolve host" "$this_script_path/curl.proc"
	do
		try=$[$try+1]
		[[ $try -eq 3 ]] && { echo -e "\n${red}>${m_tab}Too many bad try. Cannot connect WooCommerce REST API.${reset}\n"; echo "$(timestamp): Too many bad try. Cannot connect WooCommerce REST API." >> "${error_log}"; exit 1; }
		echo ""
		echo -e "\n${red}*${reset} ${red}Could not resolve host${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo  "${m_tab}${red}Is your Wordpress domain correct?${reset}"
		echo "$(timestamp): Could not resolve host! Check your DNS/Web server." >> "${error_log}"
		while true
		do
			echo -e "\n${m_tab}${cyan}##################################################################${reset}"
			read -n 1 -p "${m_tab}${BC}Do you want to reset your Wordpress domain now? --> (Y)es | (N)o${EC} " yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -rf "${this_script_path}/.end.wc.lck";
					encrypt_wc_end;
					decrypt_wc_end;
					w_curl_s; break;;
					[Nn]* ) exit 1;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
			esac
		done
	done
elif grep -q "Could not resolve host" "$this_script_path/curl.proc"; then
	if [ $send_mail_err -eq 1 ]; then
		echo "Could not resolve host! Is your DNS/Web server up?" | mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
	fi
	echo "$(timestamp): Could not resolve host! Check your DNS/Web server." >> "${error_log}"
	exit 1
fi

# Test WooCommerce REST API setup
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	if grep -q  "404\|400" "$this_script_path/curl.proc"; then
		echo -e "\n${red}*${reset}${red} Is WooCommerce plugin installed and REST API enabled?.${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Is${reset} ${green}$api_endpoint${reset} ${red}is correct?${reset} ${red}Then enable WooCommerce,"
		echo "${m_tab}${red}Enable REST API and restart setup.${reset}"
		echo "$(timestamp): WooCommerce REST API Connection Error. Check WooCommerce plugin installed and REST API enabled." >> "${error_log}"
		exit 1
	fi
elif grep -q  "404\|400" "$this_script_path/curl.proc"; then
	if [ $send_mail_err -eq 1 ]; then
		echo "WooCommerce REST API Connection Error. Is WooCommerce plugin installed and REST API enabled? You can re-start setup anytime." |
		mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
	fi
	echo "$(timestamp): WooCommerce REST API Connection Error. Check WooCommerce plugin installed and REST API enabled." >> "${error_log}"
	exit 1
fi

# Test WooCommerce REST API Authorization
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	if grep -q "403" "$this_script_path/curl.proc"; then
		my_ip=$($m_curl checkip.amazonaws.com)
		echo -e "\n${red}*${reset}${red} WooCommerce REST API Authorization error.${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Cannot connect destination from $my_ip.${reset}"
		echo "${m_tab}${red}Check your firewall settings and webserver restrictions.${reset}"
		echo "${m_tab}${red}Please give allow to $my_ip on your end and restart setup.${reset}"
		echo "$(timestamp): WooCommerce REST API Authorization error. Cannot connect destination from $my_ip." >> "${error_log}"
		exit 1
	fi
elif grep -q "403" "$this_script_path/curl.proc"; then
	if [ $send_mail_err -eq 1 ]; then
		echo "WooCommerce REST API Authorization error. Cannot connect destination from $my_ip. Check your firewall settings and webserver restrictions. You can re-start setup anytime." |
		mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
	fi
	echo "$(timestamp): WooCommerce REST API Authorization error. Cannot connect destination from $my_ip." >> "${error_log}"
	exit 1
fi

# Test WooCommerce REST API Authentication
w_curl_a
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	try=0
	while grep -q "woocommerce_rest_authentication_error\|woocommerce_rest_cannot_view\|401" "$this_script_path/curl.proc"
	do
		try=$[$try+1]
		[[ $try -eq 3 ]] && { echo -e "\n${red}>${m_tab}Too many bad try. Cannot connect REST API. Check your credentials.${reset}\n"; echo "$(timestamp): Too many bad try. Cannot connect REST API. Check your credentials." >> "${error_log}"; exit 1; }
		echo -e "\n${red}*${reset} ${red}WooCommerce REST API Authentication error${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Is your WooCommerce REST API credentials correct?${reset}"
		echo -e "${m_tab}${red}Did you encrypted correct WooCommerce REST API credentials?${reset}\n"
		echo "$(timestamp): WooCommerce REST API Authentication Error. Check your WooCommerce REST API credentials." >> "${error_log}"
		while true
		do
			echo "${m_tab}${cyan}###########################################################################${reset}"
			read -n 1 -p "${m_tab}${BC}Do you want to reset your WooCommerce API credentials now? --> (Y)es | (N)o${EC} " yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -rf "${this_script_path}/.key.wc.lck" "${this_script_path}/.secret.wc.lck";
					encrypt_wc_auth;
					decrypt_wc_auth;
					w_curl_a; break;;
				[Nn]* ) exit 1;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
			esac
		done
	done
elif grep -q "woocommerce_rest_authentication_error\|woocommerce_rest_cannot_view\|401" "$this_script_path/curl.proc"; then
	if [ $send_mail_err -eq 1 ]; then
		echo "WooCommerce REST API Authentication Error. Check your WooCommerce REST API credentials. You can re-start setup anytime." |
		mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
	fi
	echo "$(timestamp): WooCommerce REST API Authentication Error. Check your WooCommerce REST API credentials." >> "${error_log}"
	exit 1
fi

# Here a important security check.
# This is the reason why you need to clean wordpress cache before execute the script.
# If you throw in this error and reading here probably your all data is leaking.
# Let me explain:
# I assume you cleaned up your wordpress cache before execute the script.
# After successful curl respond with you credentials we send a new curl request without credentials
# If we don't get 401 thats mean you are caching json request.
# Check your wordpress caching plugin configuration and be sure wp-json exluded.
# If you have server side caching setup like fastcgi cache skip caching json requests.
# This is deadly vulnerability.
w_curl_s
if ! grep -q "401" "$this_script_path/curl.proc"; then
        echo -e "\n${red}*${reset}${red} You are caching wp-json request !${reset}"
        echo "${cyan}${m_tab}#####################################################${reset}"
        echo "${m_tab}${red}Deadly security vulnerability detected.${reset}"
        echo "${m_tab}${red}Check your wordpress caching plugin configuration and be sure wp-json exluded.${reset}"
        echo "${m_tab}${red}If you have server side caching setup,${reset}"
	echo "${m_tab}${red}like fastcgi cache skip caching json requests.${reset}"
	echo "$(timestamp): You are caching wp-json requests." >> "${error_log}"
	exit 1
fi
#========================================================================

# Create SOAP client to request ARAS cargo end
cat <<- EOF > "${this_script_path}/aras_request.php"
<?php
	try {
	\$client = new SoapClient("$api_end_aras", array("trace" => 1, "exception" => 0));
	} catch (Exception \$e) {
	echo 'ErrorCode: error_4625264224 Check SOAP Endpoint URL ', "\\n";
		exit;
	}
	\$queryInfo = "<QueryInfo>".
		"<QueryType>$api_qry_aras</QueryType>".
		"<StartDate>$s_date</StartDate>".
		"<EndDate>$e_date</EndDate>".
		"</QueryInfo>";
	\$loginInfo = "<LoginInfo>".
		"<UserName>$api_usr_aras</UserName>".
		"<Password>$api_key_aras</Password>".
		"<CustomerCode>$api_mrc_aras</CustomerCode>".
		"</LoginInfo>";
	try {
	\$result = \$client->GetQueryJSON(array('loginInfo'=>\$loginInfo,'queryInfo'=>\$queryInfo));
	} catch(Exception \$e) {
		echo 'ErrorCode: error_75546475052 ',  \$e->getMessage(), "\\n";
		exit;
	}
	serialize(\$result);
	print_r(\$result->GetQueryJSONResult);
?>
EOF

# Get WC order's ID (processing status) & WC customer info
# As of 2021 max 100 orders fetchable with one query
$m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders?status=processing&per_page=100" -u "$api_key":"$api_secret" -H "Content-Type: application/json" |
	$m_jq -r '.[]|[.id,.shipping.first_name,.shipping.last_name]|join(" ")' > "$this_script_path/wc.proc"

# Make SOAP request to ARAS web service to get shipment DATA in JSON format
# We will request last 10 day data as setted before
#==========================================================================
aras_request () {
	$m_php "$this_script_path/aras_request.php" > "$this_script_path/aras.json"
}
#==========================================================================

# Test Aras SOAP Endpoint
aras_request
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	try=0
	while grep -q "error_4625264224" "$this_script_path/aras.json"
	do
		try=$[$try+1]
		[[ $try -eq 3 ]] && { echo -e "\n${red}Too many bad try. Cannot connect ARAS SOAP API.${reset}\n"; echo "$(timestamp): Too many bad try. Cannot connect ARAS SOAP API. Check your ARAS endpoint URL." >> "${error_log}";  exit 1; }
		echo ""
		echo -e "\n${red}*${reset} ${red}ARAS SOAP Endpoint error${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Is your ARAS endpoint URL correct?${reset}\n"
		echo "$(timestamp): ARAS SOAP Endpoint Error! Check your ARAS endpoint URL." >> "${error_log}"
		while true
		do
			echo "${m_tab}${cyan}###########################################################################${reset}"
			read -n 1 -p "${m_tab}${BC}Do you want to reset your ARAS SOAP endpoint URL now? --> (Y)es | (N)o${EC}" yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -f "${this_script_path}/.end.aras.lck";
					encrypt_aras_end;
					decrypt_aras_end;
					$m_sed -i -z 's!([^(]*,!("'"$api_end_aras"'",!' "$this_script_path/aras_request.php";
					aras_request; break;;
				[Nn]* ) exit 1;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${m_tab}${cyan}###########################################################################${reset}";;
			esac
		done
	done
elif grep -q "error_4625264224" "$this_script_path/aras.json"; then
	if [ $send_mail_err -eq 1 ]; then
		echo "ARAS SOAP Endpoint Error! Check your ARAS endpoint URL. Please re-start setup manually." |
		mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
	fi
	echo "$(timestamp): ARAS SOAP Endpoint Error! Check your ARAS endpoint URL." >> "${error_log}"
	exit 1
fi

# Test Aras SOAP Authentication
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	try=0
	while grep -q "error_75546475052" "$this_script_path/aras.json"
	do
		try=$[$try+1]
		[[ $try -eq 3 ]] && { echo -e "\n${red}Too many bad try. Cannot connect ARAS SOAP API.${reset}\n"; echo "$(timestamp): Too many bad try. Cannot connect ARAS SOAP API. Check your login credentials." >> "${error_log}";  exit 1; }
		echo ""
                echo -e "\n${red}*${reset} ${red}ARAS SOAP Authentication error${reset}"
                echo "${cyan}${m_tab}#####################################################${reset}"
                echo -e "${m_tab}${red}Is your ARAS SOAP API credentials correct?${reset}\n"
		echo "$(timestamp): ARAS SOAP Authentication Error! Check your login credentials." >> "${error_log}"
		while true
		do
			echo "${m_tab}${cyan}###########################################################################${reset}"
			read -n 1 -p "${m_tab}${BC}Do you want to reset your ARAS SOAP API credentials now? --> (Y)es | (N)o${EC}" yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -rf "${this_script_path}/.key.aras.lck" "${this_script_path}/.usr.aras.lck" "${this_script_path}/.mrc.aras.lck";
					encrypt_aras_auth;
					decrypt_aras_auth;
					$m_sed -i \
						-e "s|\(<Password>\).*\(<\/Password>\)|<Password>$api_key_aras<\/Password>|g" \
						-e "s|\(<CustomerCode>\).*\(<\/CustomerCode>\)|<CustomerCode>$api_mrc_aras<\/CustomerCode>|g" \
						-e "s|\(<UserName>\).*\(<\/UserName>\)|<UserName>$api_usr_aras<\/UserName>|g" \
						"$this_script_path/aras_request.php";
					aras_request; break;;
				[Nn]* ) exit 1;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
			esac
		done
	done
elif grep -q "error_75546475052" "$this_script_path/aras.json"; then
	if [ $send_mail_err -eq 1 ]; then
		echo "ARAS SOAP Authentication Error! Check your login credentials. Please re-start setup manually." |
		mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
	fi
	echo "$(timestamp): ARAS SOAP Authentication Error! Check your login credentials." >> "${error_log}"
	exit 1
fi

# Modify ARAS SOAP json response to make easily parsable with jq
< "${this_script_path}/aras.json" $m_sed 's/^[^[]*://g' | $m_awk 'BEGIN{OFS=FS="]"};{$NF="";print $0}' > "${this_script_path}/aras.json.mod" || { echo 'cannot modify aras.json'; exit 1; }

# Parse ARAS JSON data with jq to get necessary data --> status, recipient{name,surname}, tracking number
< "${this_script_path}/aras.json.mod" $m_jq -r '.[]|[.DURUM_KODU,.KARGO_TAKIP_NO,.ALICI]|join(" ")' | $m_sed '/^6/d' | cut -f2- -d ' ' > "${this_script_path}/aras.proc"

# For perfect matching with order id and tracking number we are normalizing the data.
# Translate customer info to 'en' & transform text to lowercase & remove whitespaces
iconv -f utf8 -t ascii//TRANSLIT < "${this_script_path}/aras.proc" | tr '[:upper:]' '[:lower:]' | $m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= > "${this_script_path}/aras.proc.en"
iconv -f utf8 -t ascii//TRANSLIT < "${this_script_path}/wc.proc" | tr '[:upper:]' '[:lower:]' | $m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= > "${this_script_path}/wc.proc.en"

# Create associative array and prepeare necessary data for matching operation
declare -A aras_array
declare -A wc_array

while read -r track a_customer
do
	aras_array[$track]="${a_customer}"
done < "${this_script_path}/aras.proc.en"

while read -r id w_customer
do
	wc_array[$id]="${w_customer}"
done < "${this_script_path}/wc.proc.en"

if [[ "${#aras_array[@]}" -gt 0 && "${#wc_array[@]}" -gt 0 ]]; then
	for i in "${!wc_array[@]}"; do
		for j in "${!aras_array[@]}"; do
			echo "${i}" "${wc_array[$i]}" "${j}" "${aras_array[$j]}" >> "${this_script_path}/.lvn.all.cus"
		done
	done
fi

# Create perl script for string matching via levenshtein distance function
# Perl Text::Fuzzy module is very fast in my tests.
# You can try Text::Levenshtein - Text::Levenshtein::XS if you interested in speed test (need some coding)
cat > "${this_script_path}/${levenshtein}" << EOF
#!$m_perl
use warnings;
use strict;
use Text::Fuzzy;
my \$tf = Text::Fuzzy->new ("\$ARGV[0]");
\$tf->set_max_distance (3);
print \$tf->distance ("\$ARGV[1]"), "\\n";
EOF

# Set executable
chmod +x "${this_script_path}/${levenshtein}"

# MAIN STRING MATCHING LOGIC
# Approximate string matching up to 3 characters.
# =============================================================================================
if [ -s "${this_script_path}/.lvn.all.cus" ]; then
	cat "${this_script_path}/.lvn.all.cus" | $m_awk '{print $2,$4}' | while read -r wc aras
	do
		$m_perl "${this_script_path}/${levenshtein}" "$wc" "$aras" >> "${this_script_path}/.lvn.stn"
	done
	$m_paste "${this_script_path}/.lvn.all.cus" "${this_script_path}/.lvn.stn" | $m_awk '($5 < 4 )' | $m_awk '{print $1,$3}' > "${my_tmp}"

	# Better handle multiple orders(processing) for same customer
	# Better handle multiple tracking numbers for same customer
	declare -A magic
	while read id track; do
		magic[${id}]="${magic[$id]}${magic[$id]:+ }${track}"
	done < "${my_tmp}"

	for id in "${!magic[@]}"; do
		echo "$id ${magic[$id]}" >> "${this_script_path}/.lvn.mytmp2"
	done

	if [ "$($m_awk '{print NF}' ${this_script_path}/.lvn.mytmp2 | sort -nu | tail -n 1)" -gt 2 ]; then
		$m_awk 'NF==3' "${this_script_path}/.lvn.mytmp2" > "${this_script_path}/.lvn.mytmp3"
		if [[ -n "$($m_awk 'x[$2]++ == 1 { print $2 }' ${this_script_path}/.lvn.mytmp3)" ]]; then
			for i in $($m_awk 'x[$2]++ == 1 { print $2 }' "${this_script_path}/.lvn.mytmp3"); do
				$m_sed -i "0,/$i/{s/$i//}" "${this_script_path}/.lvn.mytmp3"
			done
			cat <(cat "${this_script_path}/.lvn.mytmp3" | $m_awk '{$1=$1}1' | $m_awk '{print $1,$2}') <(cat "${this_script_path}/.lvn.mytmp2" | $m_awk 'NF<=2') > "${my_tmp}"
		else
			cat <(cat "${this_script_path}/.lvn.mytmp3" | $m_awk '{print $1,$2}') <(cat "${this_script_path}/.lvn.mytmp2" | $m_awk 'NF<=2') > "${my_tmp}"
		fi
	fi
fi
# ============================================================================================

# User must validate the data that parsed by script.
# If you haven't any orders or shipped cargo yet we cannot generate any data.
# You can simply create a test order if throw in error here.
# If data validated by user we are ready for production.
# If data is wrong open a issue.
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	if [ ! -e "${this_script_path}/.woo.aras.set" ]; then
		echo -e "\n${green}*${reset} ${green}Parsing some random data to validate.${reset}"
		echo -ne "${cyan}${m_tab}########                                             [20%]\r${reset}"
		sleep 1
		echo -ne "${cyan}${m_tab}##################                                   [40%]\r${reset}"
		echo -ne "${cyan}${m_tab}#################################                    [60%]\r${reset}"
		sleep 2
		echo -ne "${cyan}${m_tab}#####################################                [75%]\r${reset}"
		echo -ne "${cyan}${m_tab}##########################################           [85%]\r${reset}"
		sleep 1
		echo -ne "${cyan}${m_tab}#####################################################[100%]\r${reset}"
		echo -ne '\n'
		data_test=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders?per_page=5" -u "$api_key":"$api_secret" -H "Content-Type: application/json")
		if [ "$data_test" == "[]" ]; then
			echo -e "\n${red}*${reset} ${red}Couldn't find any woocommerce order data to validate.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}You can simply create a test order if throw in error here.${reset}"
			echo "${m_tab}${red}Without data validation by user we cannot go for production.${reset}"
			echo "$(timestamp): Couldn't find any woocommerce order data to validate. You can simply create a test order." >> "${error_log}"
			exit 1
		else
			echo -e "${m_tab}${green}Done${reset}"
			echo -e "\n${green}${m_tab}Please validate Order_ID & Customer_Info.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			column -t -s' ' <<< $(echo "$data_test" | $m_jq -r '.[]|[.id,.billing.first_name,.billing.last_name]|join(" ")' |
				iconv -f utf8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' |
				$m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= |
				$m_sed '1i Order_ID Customer_Name' | $m_sed '2i --------------- -------------' |
				$m_sed 's/^/ /')
			while true
 			do
				echo "${m_tab}${cyan}#####################################################${reset}"
				read -n 1 -p "${m_tab}${BC}Is data correct? --> (Y)es | (N)o${EC} " yn < /dev/tty
				echo ""
				case "${yn}" in
					[Yy]* ) break;;
					[Nn]* ) exit 1;;
                                	* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
                        	esac
                	done
		fi

		if grep "null" "$this_script_path/aras.json.mod"; then
			echo -e "\n${red}*${reset} ${red}Couldn't find any ARAS cargo data to validate${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}You can simply set wide time range to get cargo data${reset}"
			echo "${m_tab}${red}Set 'start_date' 'end_date' variables in script.${reset}"
			echo "${m_tab}${red}Without data validation by user we cannot go for production.${reset}"
			echo "$(timestamp): Couldn't find any ARAS cargo data to validate" >> "${error_log}"
			exit 1
		else
			echo -e "\n${green}${m_tab}Please validate Tracking_Number & Customer_Info.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			column -t -s' ' <<< $(cat "$this_script_path/aras.json.mod" | $m_jq -r '.[]|[.DURUM_KODU,.KARGO_TAKIP_NO,.ALICI]|join(" ")' |
				cut -f2- -d ' ' | iconv -f utf8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' |
				$m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= |
				$m_sed '1i Tracking_Number Customer_Name' | $m_sed '2i --------------- -------------' |
				$m_sed 's/^/ /' | $m_sed '8,$d')
			while true
			do
				echo "${m_tab}${cyan}#####################################################${reset}"
				read -n 1 -p "${m_tab}${BC}Is data correct? --> (Y)es | (N)o${EC} " yn < /dev/tty
				echo ""
				case "${yn}" in
					[Yy]* ) break;;
					[Nn]* ) exit 1;;
					* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
				esac
			done
		fi

		echo -e "\n${green}*${reset} ${green}Setup completed.${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"
		echo "${m_tab}${green}Please select installation method.${reset}"

		while true
		do
			echo "${m_tab}${cyan}#####################################################${reset}"
			read -n 1 -p "${m_tab}${BC}c for crontab, s for systemd, q for quit${EC} " cs < /dev/tty
			echo ""
			case "${cs}" in
				[Cc]* ) add_cron; break;;
				[Ss]* ) add_systemd; break;;
				[qQ]* ) exit 1;;
			* ) echo -e "\n${m_tab}Please answer c or s, q.";;
			esac
		done
	fi
fi

# Lets start updating woocommerce order status as completed with AST plugin.
# ARAS Tracking number will be sent to customer.
if [ -e "${this_script_path}/.woo.aras.enb" ]; then
	# Check multiple orders(processing) & tracking numbers for same customer.
	# As mentioned this is not deep integration solution. This is the biggest drawback.
	# If we have multiple orders from same customer we cannot match order with exact tracking number.

	if [ -s "$my_tmp" ]; then
			while IFS=' ' read -r id track
			do
				# Update order with AST Plugin REST API
				$m_curl -s -o /dev/null -X POST \
					-u "$api_key":"$api_secret" \
					-H "Content-Type: application/json" \
					-d '{"tracking_provider": "Aras Kargo","tracking_number": "'"${track}"'","date_shipped": "'"${t_date}"'","status_shipped": 1}' \
					"https://$api_endpoint/wp-json/wc-ast/v3/orders/$id/shipment-trackings"
				res=$?
				if test "$res" == "0"; then
					# HTML mail about order updates
					sleep 5
					c_name=$(curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders/$id" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | jq -r '[.billing.first_name,.billing.last_name]|join(" ")')
					# If you use custom order number plugins
					order_number=$(curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders/$id" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | jq -r '[.meta_data]' | awk '/_order_number/{getline; print}' | awk -F: '{print $2}' | tr -d '"' | sed -r 's/\s+//g' | tr " " "*" | tr "\t" "&")
					mail -s "$mail_subject_suc" -a "$mail_from" -a "MIME-Version: 1.0" -a "Content-Type: text/html; charset=UTF-8" "$mail_to" <<- EOF
					<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd"><html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"/></head><body><table id="v1template_container" style="background-color: #ffffff; border: 1px solid #dedede; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1); border-radius: 3px;" border="0" width="600" cellspacing="0" cellpadding="0"><tbody><tr><td align="center" valign="top"><table id="v1template_header" style="background-color: #567d46; color: #ffffff; border-bottom: 0; font-weight: bold; line-height: 100%; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; border-radius: 3px 3px 0 0;" border="0" width="100%" cellspacing="0" cellpadding="0"><tbody><tr><td id="v1header_wrapper" style="padding: 36px 48px; display: block;"><h2 style="font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 30px; font-weight: 300; line-height: 150%; margin: 0px; text-shadow: #78976b 0px 1px 0px; color: #ffffff; background-color: inherit; text-align: center;">Aras Kargo Otomatik Güncelleme: $id - $order_number</h2></td></tr></tbody></table></td></tr><tr><td align="center" valign="top"><table id="v1template_body" border="0" width="600" cellspacing="0" cellpadding="0"><tbody><tr><td id="v1body_content" style="background-color: #ffffff;" valign="top"><table border="0" width="100%" cellspacing="0" cellpadding="20"><tbody><tr><td style="padding: 48px 48px 32px;" valign="top"><div id="v1body_content_inner" style="color: #636363; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 14px; line-height: 150%; text-align: left;"><p style="margin: 0 0 16px;">Merhaba $company_name, $c_name siparişi kargoya verildi ve sipariş durumu tamamlandı olarak güncellendi: Müşteriye kargo takip kodunu da içeren bir bilgilendirme maili gönderildi.</p><h2 style="color: #567d46; display: block; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 18px; font-weight: bold; line-height: 130%; margin: 0 0 18px; text-align: left;"><a class="v1link" style="font-weight: normal; text-decoration: underline; color: #567d46;" href="#" target="_blank" rel="noreferrer">[Sipariş #$id]</a> ($t_date)</h2><div style="margin-bottom: 40px;"><table class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; width: 100%; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif;" border="1" cellspacing="0" cellpadding="6"><thead><tr><th class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; padding: 12px; text-align: left;">KARGO</th><th class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; padding: 12px; text-align: left;">İSİM</th><th class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; padding: 12px; text-align: left;">TAKİP KODU</th></tr></thead><tbody><tr class="v1order_item"><td class="v1td" style="color: #636363; border: 1px solid #e5e5e5; padding: 12px; text-align: left; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; word-wrap: break-word;">ARAS KARGO</td><td class="v1td" style="color: #636363; border: 1px solid #e5e5e5; padding: 12px; text-align: left; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif;">$c_name</td><td class="v1td" style="color: #636363; border: 1px solid #e5e5e5; padding: 12px; text-align: left; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif;">$track</td></tr></tbody></table></div></div></td></tr></tbody></table></td></tr></tbody></table></td></tr></tbody></table></body></html>
					EOF
					echo "$(timestamp): ORDER UPDATED: Order_Id=$id Order_Number=$order_number Aras_Tracking_Number=$track Customer_Info=$c_name" >> "${access_log}"
					if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
						echo "${green}*${reset} ${green}ORDER UPDATED: Order_Id=$id Order_Number=$order_number Aras_Tracking_Number=$track Customer_Info=$c_name${reset}"
					fi
					sleep 10
				elif [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
					if [ $send_mail_err -eq 1 ]; then
						echo "Cannot post data to AST Plugin REST endpoint (wp-json/wc-ast/v3/orders/$id/shipment-trackings)" |
						mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
					fi
					echo "${red}*${reset} ${red}Cannot post data to AST Plugin REST endpoint (wp-json/wc-ast/v3/orders/$id/shipment-trackings)${reset}"
					echo "$(timestamp): Cannot post data to AST Plugin REST endpoint (wp-json/wc-ast/v3/orders/$id/shipment-trackings)" >> "${error_log}"
					exit 1
				else
					if [ $send_mail_err -eq 1 ]; then
						echo "Cannot post data to AST Plugin REST endpoint (wp-json/wc-ast/v3/orders/$id/shipment-trackings)" |
						mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
					fi
					echo "$(timestamp): Cannot post data to AST Plugin REST endpoint (wp-json/wc-ast/v3/orders/$id/shipment-trackings)" >> "${error_log}"
					exit 1
				fi
			done < "${my_tmp}"
	else
		if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
			echo "${yellow}*${reset} ${yellow}Couldn't find any updateable order now.${reset}"
			echo "$(timestamp): Couldn't find any updateable order now." >> "${access_log}"
		else
			echo "$(timestamp): Couldn't find any updateable order now." >> "${access_log}"
		fi
	fi
fi

# And lastly we exit
exit $?
