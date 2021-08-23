#!/bin/bash
#
# shellcheck disable=SC2016,SC2015
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
# WOOCOMMERCE - ARAS CARGO INTEGRATION
# ---------------------------------------------------------------------
# Written by  : (hsntgm) Hasan ÇALIŞIR - hasan.calisir@psauxit.com
# Version     : 2.0.1
# --------------------------------------------------------------------
# Bash        : 5.1.8
# WooCommerce : 5.5.1
# Wordpress   : 5.7.2
# AST Plugin  : 3.2.5
# Tested On   : Ubuntu, Gentoo
# Year        : 2021
# ---------------------------------------------------------------------
#
# The aim of this script is integration woocommerce and ARAS cargo.
# What is doing this script exactly?
# -This automation updates woocomerce order status processing to completed/shipped
# -(via WC REST), when the matching cargo tracking code is generated on the ARAS
# -cargo end (SOAP). Attachs cargo information (tracking number, track link etc.)
# -to order completed/shipped e-mail with the help of AST plugin (AST REST) and
# -notify customer. If you implemented two-way fulfillment workflow, script goes
# -one layer up and updates order status shipped to delivered and notify customer
# -via second mail. Simply you don't need to add cargo tracking number manually
# -and update order status via WooCommerce orders dashboard. The aim of script is
# -automating the process fully.
#
# Follow detailed installation instructions on github.
# =====================================================================

# Need for upgrade - DON'T EDIT MANUALLY
# =====================================================================
script_version="2.0.1"
# =====================================================================

# USER DEFINED-EDITABLE VARIABLES & OPTIONS
# =====================================================================
# Set estimated delivery time (default 5 day)
# Increase this value if sent packages take longer 5 days to reach the customer.
# If holidays and special days are the case increasing the value is recommended.
delivery_time=5

# Set levenshtein distance function approx. string matching (default max 3 characters)
# Setting higher values causes unexpected matching result
# If you miss the matches too much set higher values, max recommended is 4,5 char.
max_distance=3

# Main cron job schedule timer
# At every 24th minute past every hour from 9 through 19 on every day-of-week from Monday through Saturday.
cron_minute="*/24 9-19 * * 1-6"

# Updater cron job schedule timer
# At 09:19 on Sunday.
cron_minute_update="19 9 * * 0"

# Systemd job schedule timer
# At every 30th minute past every hour from 9 through 19 on every day-of-week from Monday through Saturday.
on_calendar="Mon..Sat 9..19:00/30:00"

# Logrotate configuration
# Keeping log file size small is important for performance (kb)
maxsize="35"
l_maxsize="35k"

# Logging paths
wooaras_log="/var/log/woo-aras/woocommerce_aras.log"

# Need for html mail template
company_name="E-Commerce Company"
company_domain="mycompany.com"

# Set ARAS cargo request date range --> last 10 days
# Supports Max 30 days.
# Keep date format!
t_date=$(date +%d/%m/%Y)
e_date=$(date +%d-%m-%Y -d "+1 days")
s_date=$(date +%d-%m-%Y -d "-10 days")

# Send mail command, adjust as you wish sendmail, mutt, ssmtp
send_mail_command="mail"

# Set 1 if you want to get error&success mails (recommended)
# Properly configure your mail server and send mail command before enable
# Set 0 to disable
send_mail_err="1"

# Set notify mail info
mail_to="order_info@${company_domain}"
mail_from="From: ${company_name} <aras_woocommerce@${company_domain}>"
mail_subject_suc="SUCCESS: WooCommerce - ARAS Cargo"
mail_subject_err="ERROR: WooCommerce - ARAS Cargo"

# Send mail functions
# If you use sendmail, mutt, ssmtp etc. you can adjust here with proper properties
send_mail_err () {
	$send_mail_command -s "$mail_subject_err" -a "$mail_from" -a "MIME-Version: 1.0" -a "Content-Type: text/html; charset=UTF-8" "$mail_to"
}

send_mail_suc () {
	$send_mail_command -s "$mail_subject_suc" -a "$mail_from" -a "MIME-Version: 1.0" -a "Content-Type: text/html; charset=UTF-8" "$mail_to"
}
# END
# =====================================================================

# Script called by
called_by () {
	# Cron
	local FROM_CRON="$(pstree -s $$ | grep -c cron 2>/dev/null)"
	local FROM_CRON_2=$([[ ! "$TERM" || "$TERM" = "dumb" ]] && echo '1' || echo '0')

	if [[ "${FROM_CRON}" -eq 1 || "${FROM_CRON_2}" -eq 1 ]]; then
		RUNNING_FROM_CRON=1
	else
		RUNNING_FROM_CRON=0
	fi

	# Systemd
	local FROM_SYSTEMD="0"
	RUNNING_FROM_SYSTEMD="${RUNNING_FROM_SYSTEMD:=$FROM_SYSTEMD}"
}
called_by

if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
	# My style
	{ green=$(tput setaf 2); red=$(tput setaf 1); reset=$(tput sgr0); cyan=$(tput setaf 6); }
	{ magenta=$(tput setaf 5); yellow=$(tput setaf 3); BC=$'\e[32m'; EC=$'\e[0m'; }
	{ m_tab='  '; m_tab_3=' '; }
fi

# Display usage instruction
usage () {
        echo -e "\n${m_tab}${cyan}# BASIC USAGE${reset}"
        echo -e "${m_tab}${magenta}###############################################################################${reset}"
        echo -e "\n${m_tab}${cyan}# Clone git repository (non-root user is recommended)${reset}"
        echo -e "${m_tab}${magenta}git clone https://github.com/hsntgm/woocommerce-aras-kargo.git${reset}"
        echo -e "\n${m_tab}${cyan}# Setup needs sudo privileges${reset}"
        echo -e "${m_tab}${magenta}sudo ./woocommerce-aras-cargo.sh --setup${reset}"
        echo -e "\n${m_tab}${cyan}# Uninstalling needs sudo privileges${reset}"
        echo -e "${m_tab}${magenta}sudo ./woocommerce-aras-cargo.sh --uninstall${reset}"
        echo -e "\n${m_tab}${cyan}# For all other options you can work without sudo privileges${reset}"
        echo -e "${m_tab}${magenta}Check './woocommerce-aras-cargo.sh --help' for details.${reset}"
        echo -e "\n${m_tab}${cyan}# For detailed installation instruction please visit github page.${reset}"
        echo -e "${m_tab}${magenta}https://github.com/hsntgm/woocommerce-aras-kargo${reset}\n"
        echo -e "${m_tab}${magenta}###############################################################################${reset}\n"
}

# Display script controls
help () {
	echo -e "\n${m_tab}${cyan}# WOOCOMMERCE - ARAS CARGO INTEGRATION HELP"
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}#${m_tab}--setup            |-s      NEED SUDO! first time setup (also hard reset and re-starts setup)"
	echo -e "${m_tab}#${m_tab}--twoway-enable    |-t      enable twoway fulfillment workflow"
	echo -e "${m_tab}#${m_tab}--twoway-disable   |-y      only disable twoway fulfillment workflow without uninstall custom order status package as script will continue to work default one-way"
	echo -e "${m_tab}#${m_tab}--disable          |-i      completely disable/inactivate script without uninstallation (for debugging purpose)"
	echo -e "${m_tab}#${m_tab}--enable           |-a      enable/activate script if previously disabled"
	echo -e "${m_tab}#${m_tab}--uninstall        |-d      NEED SUDO! completely remove installed bundles aka twoway custom order status package, cron jobs, systemd services, logrotate, logs"
	echo -e "${m_tab}#${m_tab}--upgrade          |-u      upgrade script to latest version"
	echo -e "${m_tab}#${m_tab}--options          |-o      show user defined/adjustable options currently in use"
	echo -e "${m_tab}#${m_tab}--status           |-S      display automation status"
	echo -e "${m_tab}#${m_tab}--dependencies     |-p      display prerequisites & dependencies"
	echo -e "${m_tab}#${m_tab}--version          |-v      display script info"
	echo -e "${m_tab}#${m_tab}--help             |-h      display help"
	echo -e "${m_tab}# ---------------------------------------------------------------------${reset}\n"
}

# Display script hard dependencies (may not included in default linux installations)
dependencies () {
	echo -e "\n${m_tab}${magenta}# WOOCOMMERCE - ARAS CARGO INTEGRATION HARD DEPENDENCIES"
	echo -e "${m_tab}${magenta} (may not included in default linux installations)${reset}"
	echo -e "${cyan}${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}# curl"
	echo -e "${m_tab}# perl-Text::Fuzzy >= 0.29"
	echo -e "${m_tab}# jq >= 1.6"
	echo -e "${m_tab}# php"
	echo -e "${m_tab}# php-soap"
	echo -e "${m_tab}# gnu sed >= 4"
	echo -e "${m_tab}# gnu awk >= 5"
	echo -e "${m_tab}# whiptail (as also known (newt,libnewt))"
	echo -e "${m_tab}# english locale"
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "\n${m_tab}${magenta}# WOOCOMMERCE - ARAS CARGO INTEGRATION RECOMMENDED TOOLS${reset}"
	echo -e "${cyan}${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}# mail --> If you use mutt, ssmtp, sendmail etc. please edit user defined variables."
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "\n${m_tab}${magenta}# WOOCOMMERCE - ARAS CARGO INTEGRATION NEEDED APPLICATION VERSIONS${reset}"
	echo -e "${cyan}${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}# Wordpress >= 5"
	echo -e "${m_tab}# WooCommerce >= 5"
	echo -e "${m_tab}# WooCommerce AST Plugin >= 3.2.5"
	echo -e "${m_tab}# Bash >= 5"
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "\n${m_tab}${magenta}# WOOCOMMERCE - ARAS CARGO INTEGRATION REQUIREMENTS DURING SETUP${reset}"
	echo -e "${cyan}${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}# WooCommerce REST API Key (v3)"
	echo -e "${m_tab}# WooCommerce REST API Secret (v3)"
	echo -e "${m_tab}# Wordpress Site URL (format in www.my-ecommerce.com)"
	echo -e "${m_tab}# ARAS SOAP API Password"
	echo -e "${m_tab}# ARAS SOAP API Username"
	echo -e "${m_tab}# ARAS SOAP Endpoint URL (wsdl) (get from ARAS commercial user control panel)"
	echo -e "${m_tab}# ARAS SOAP Merchant Code"
	echo -e "${m_tab}# ---------------------------------------------------------------------${reset}\n"
}

# Version Info
version () {
	echo -e "\n${m_tab}${cyan}# WOOCOMMERCE - ARAS CARGO INTEGRATION VERSION"
	echo -e "${m_tab}# ---------------------------------------------------------------------"
	echo -e "${m_tab}# Written by : Hasan ÇALIŞIR - hasan.calisir@psauxit.com"
	echo -e "${m_tab}# Version    : 2.0.1"
	echo -e "${m_tab}# Bash       : 5.1.8"
	echo -e "${m_tab}# ---------------------------------------------------------------------\n"
}

# Display user defined/adjustable options currently in use
options () {
	echo ""
	while read -r opt
	do
		[[ "$opt" =~ ^#.* ]] && opt_color="${cyan}" || opt_color="${magenta}"
		echo -e "${opt_color}$(echo "$opt" | sed 's/^/  /')${reset}"
	done < <(sed -n '/^# USER DEFINED/,/^# END/p' 2>/dev/null "${0}")
	echo ""
}

# @EARLY CRITICAL CONTROLS
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

# Test connection & get public ip
if ! : >/dev/tcp/8.8.8.8/53; then
	echo -e "\n${red}*${reset} ${red}There is no internet connection.${reset}"
	echo -e "${cyan}${m_tab}#####################################################${reset}\n"
        exit 1
else
	# Get public IP
	exec 3<> /dev/tcp/checkip.amazonaws.com/80
	printf "GET / HTTP/1.1\r\nHost: checkip.amazonaws.com\r\nConnection: close\r\n\r\n" >&3
	read -r my_ip < <(tail -n1 <&3)
fi

# Accept only one argument
[[ "${#}" -gt 1 ]] && { help; exit 1; }
# =====================================================================

# Guides placed at the beginning of the script
# User able to reach them without any break immediately after critical controls passed
while :; do
	case "${1}" in
	-o|--options          ) options
				exit
				;;
	-U|--usage	      ) usage
				exit
				;;
	-p|--dependencies     ) dependencies
				exit
				;;
	-v|--version          ) version
				exit
				;;
	-h|--help             ) help
				exit
				;;
	*                     ) break;;
	esac
	shift
done

# Pretty send mail function
send_mail () {
	if [[ $send_mail_err -eq 1 ]]; then
		send_mail_err <<< "${1}" >/dev/null 2>&1
	fi
}

# Log timestamp
timestamp () {
        date +"%Y-%m-%d %T"
}

# Early add local PATHS to deal with cron errors.
# We will also set explicit paths for binaries later.
export PATH="${PATH}:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"
uniquepath () {
	local path=""
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

# Path pretty error
script_path_pretty_error () {
	echo -e "\n${red}*${reset} ${red}Could not determine script name and fullpath${reset}"
	echo -e "${cyan}${m_tab}#####################################################${reset}\n"
	send_mail "Could not determine script name and fullpath"
	exit 1
}

# Early discover script path
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

# PID File
PIDFILE="/var/run/woo-aras/woocommerce-aras-cargo.pid"

# Path pretty error
path_pretty_error () {
	echo -e "\n${red}*${reset} ${red}Path not writable: ${1}${reset}"
	echo "${cyan}${m_tab}#####################################################${reset}"
	echo -e "${red}${m_tab}Run once as root or with sudo user to create path${reset}\n"
	send_mail "Path not writable: ${1} --> run once manually as root or with sudo user to create path."
	exit 1
}

# For @SETUP && @UNINSTALL:
# Display usage for necessary privileges
if [[ "${1}" == "-s" || "${1}" == "--setup" || "${1}" == "-d" || "${1}" == "--uninstall" ]]; then
	if [[ ! $SUDO_USER && $EUID -ne 0 ]]; then
		usage
		exit 1
	fi
fi

# Check runtime path (before logrotation prerotate rules called)
# Later, For @REBOOTS:
#  -- We will create runtime folder via --> /etc/tmpfiles.d/ || rc.local for cron installation
#  -- For systemd installation we will use 'RuntimeDirectory' so no need tmpfiles installation
runtime_path="${PIDFILE#/var}"
if [[ ! -d "${runtime_path%/*}" ]]; then
	if [[ $SUDO_USER || $EUID -eq 0 ]]; then
		mkdir "${runtime_path%/*}" &&
		echo "$(timestamp): Runtime path created: ${runtime_path%/*}" >> "${wooaras_log}" ||
		{ echo "Cannot create runtime path"; echo "$(timestamp): Cannot create runtime path: ${runtime_path%/*}" >> "${wooaras_log}"; exit 1; }
		[[ $SUDO_USER ]] && chown "${user}":"${user}" "${runtime_path%/*}"
	else
		path_pretty_error "/run"
	fi
fi

# Logrotation prerotate rules
my_rotate () {
	# Not logrotate while script running
	if [[ -f "${PIDFILE}" ]]; then
		local PID="$(< "${PIDFILE}")"
		if ps -p "${PID}" > /dev/null 2>&1; then
			exit 1
		fi
	fi

	# Not logrotate until all shipped orders flagged as delivered otherwise data loss
	if [[ -f "${this_script_path}/.two.way.enb" ]]; then
		if [[ "$(grep -c "SHIPPED" "${wooaras_log}")" -ne "$(grep -c "DELIVERED" "${wooaras_log}")" ]]; then
			exit 1
		fi
	fi

	# Create dummy process only while logrotation file size condition is met
	if [[ -s "${wooaras_log}" ]]; then
		filesize="$(du -k "${wooaras_log}" | cut -f1)"
		if (( filesize > maxsize )); then
			# Create dummy background process silently (PID will kill by logrotate)
			# This will prevent executing script while logrotation triggering
			{ perl -MPOSIX -e '$0="wooaras"; pause' & } 2>/dev/null
			echo $! > "${PIDFILE}"
		else
			exit 1
		fi
	else
		exit 1
	fi

	# Send signal to start logrotation
	exit 0
}

# Reply the logrotate call
if [[ "${1}" == "--rotate" ]]; then my_rotate; fi

# Determine user
if [[ $SUDO_USER ]]; then user="${SUDO_USER}"; else user="$(whoami)"; fi

# Drop file privileges back to non-root user if we got here with sudo
depriv () {
	if [[ $SUDO_USER ]]; then
		if [[ ! -f "${1}" ]]; then
			touch "${1}"
		fi
		chown "$user":"$user" "${1}"
	elif [[ ! -f "${1}" ]]; then
		touch "${1}" || { echo "Cannot create ${1}"; exit 1; }
	fi
}

# Check & create log path
# If executed by sudo user drop ownership
if [[ ! -d "${wooaras_log%/*}" ]]; then
	if [[ $SUDO_USER || $EUID -eq 0 ]]; then
		mkdir -p "${wooaras_log%/*}" || { echo "Cannot create log path"; exit 1; }
		[[ $SUDO_USER ]] && chown "$user":"$user" "${wooaras_log%/*}"
		depriv "${wooaras_log}" && echo "$(timestamp): Log path created: Logging started..${wooaras_log%/*}" >> "${wooaras_log}"
	else
		path_pretty_error "/var/log"
	fi
fi

# Pid pretty error
pid_pretty_error () {
	echo -e "\n${red}*${reset} ${red}FATAL ERROR: Cannot create PID${reset}"
	echo -e "${cyan}${m_tab}#####################################################${reset}\n"
	echo "$(timestamp): FATAL ERROR: Cannot create PID" >> "${wooaras_log}"
	send_mail "FATAL ERROR: Cannot create PID"
}

# Create PID before long running process
# Allow only one instance running at the same time
# Check how long actual process has been running to catch hang processes
if [[ -f "${PIDFILE}" ]]; then
	PID="$(< "${PIDFILE}")"
	if ps -p "${PID}" > /dev/null 2>&1; then
		is_running=$(printf "%d" "$(($(ps -p "${PID}" -o etimes=) / 60))")
		echo -e "\n${red}*${reset} ${red}The operation cannot be performed at the moment:${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}As script already running --> ${magenta}pid=$PID${reset}${red}, please try again later${reset}\n"
		send_mail "The operation cannot be performed at the moment: as script already running --> pid=$PID, please try again later"

		# Warn about possible hang process
		if [[ "${is_running}" -gt 30 ]]; then
			echo -e "\n${red}*${reset} ${red}Possible hang process found:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}The process pid=$PID has been running for more than 30 minutes.${reset}\n"
			send_mail "Possible hang process found: The process pid=$PID has been running for more than 30 minutes."
		fi
		exit 1
	elif ! echo $$ > "${PIDFILE}"; then
		pid_pretty_error
		exit 1
	fi
elif ! echo $$ > "${PIDFILE}"; then
	pid_pretty_error
	exit 1
fi

# Check dependencies & Set explicit paths
# =====================================================================
dynamic_vars () {
	suffix="m"
	eval "${suffix}"_"${1}"="$(command -v "${1}" 2>/dev/null)"
}

# Check mailserver > as smtp port 587 is open and listening
# Still using port 25? I don't care..
if timeout 1 bash -c "cat < /dev/null > /dev/tcp/"${my_ip}"/587" >/dev/null 2>&1; then
	if command -v lsof >/dev/null 2>&1; then
		if lsof -i -P -n | grep -q 587; then
			check_mail_server=0
		else
			check_mail_server=1
		fi
	elif command -v netstat >/dev/null 2>&1; then
		if netstat -tulpn | grep -q 587; then
			check_mail_server=0
		else
			check_mail_server=1
		fi
	elif command -v ss >/dev/null 2>&1; then
		if ss -tulpn | grep -q 587; then
			check_mail_server=0
		else
			check_mail_server=1
		fi
	fi
else
	check_mail_server=1
fi

# Check dependencies
declare -a dependencies=("curl" "iconv" "openssl" "jq" "php" "perl" "awk" "sed" "pstree" "stat" "$send_mail_command" "whiptail" "logrotate" "paste" "column" "zgrep" "mapfile" "readarray" "locale" "systemctl" "chattr")
for i in "${dependencies[@]}"
do
	if ! command -v "$i" > /dev/null 2>&1; then
		echo -e "\n${red}*${reset} ${red}$i not found.${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		# Not break script but warn user about mail operations
		if [ "$i" == "$send_mail_command" ]; then
			echo "${yellow}${m_tab}You need running mail server with $i command.${reset}"
			if [ $check_mail_server -eq 1 ]; then
				# Disable send mail
				send_mail_err="0"
				echo "${yellow}${m_tab}Mail server not configured as SMTP port 587 is closed or not listening.${reset}"
				echo "$(timestamp): Mail server not configured as SMTP port 587 is closed or not listening, $i command not found." >> "${wooaras_log}"
			fi
			echo "${yellow}${m_tab}'mail' command is part of mailutils package.${reset}"
			echo -e "${yellow}${m_tab}You can continue the setup but you cannot get important mail alerts${reset}\n"
			if [ $check_mail_server -eq 0 ]; then
				echo "$(timestamp): $i not found." >> "${wooaras_log}"
			fi
		else
			# Exit for all other conditions
			echo "${yellow}${m_tab}Please install necessary package from your linux repository and re-start setup.${reset}"
			echo -e "${yellow}${m_tab}If package installed but binary not in your PATH: add PATH to ~/.bash_profile, ~/.bashrc or profile.${reset}\n"
			echo "$(timestamp): $i not found." >> "${wooaras_log}"
			exit 1
		fi
	elif [ "$i" == "php" ]; then
		dynamic_vars "$i"
		# Check php-soap module
		if ! $m_php -m | grep -q "soap"; then
			echo -e "\n${red}*${reset} ${red}php-soap module not found.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${yellow}${m_tab}Need for creating SOAP client to get data from ARAS${reset}\n"
			echo "$(timestamp): php-soap module not found, need for creating SOAP client to get data from ARAS" >> "${wooaras_log}"
			exit 1
		fi
	elif [ "$i" == "perl" ]; then
		dynamic_vars "$i"
		# Check perl Text::Fuzzy module
		if ! $m_perl -e 'use Text::Fuzzy;' >/dev/null 2>&1; then
			echo -e "\n${red}*${reset} ${red}Text::Fuzzy PERL module not found.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${yellow}${m_tab}Use distro repo or CPAN (https://metacpan.org/pod/Text::Fuzzy) to install${reset}\n"
			echo "$(timestamp): Text::Fuzzy PERL module not found." >> "${wooaras_log}"
			exit 1
                fi
	else
		# Explicit paths for specific binaries used by script.
		# Best practise to avoid cron errors is declare full path of binaries.
		# I expect bash-builtin commands will not cause any cron errors.
		# If you use specific linux distro and face cron errors please open issue.
		dynamic_vars "$i"
	fi
done

# Prevent iconv text translation errors
# Set locale category for character handling functions (otherwise this script not work correctly)
m_ctype=$(locale | grep LC_CTYPE | cut -d= -f2 | cut -d_ -f1 | tr -d '"')
if [ "$m_ctype" != "en" ]; then
	if locale -a | grep -iq "en_US.utf8"; then
		export LC_ALL=en_US.UTF-8
		export LC_CTYPE=en_US.UTF-8
		lang_setted=1
	else
		echo -e "\n${red}*${reset} ${red}English locale not found${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${red}${m_tab}Please add support on English locale for your shell environment.${reset}"
		echo -e "${yellow}${m_tab}e.g. for ubuntu -> apt-get -y install language-pack-en${reset}\n"
		echo "$(timestamp): English locale not found, please add support on English locale for your shell environment." >> "${wooaras_log}"
		send_mail "English locale not found, please add support on English locale for your shell environment."
		exit 1
	fi
fi
# =====================================================================

# Create temporary files
my_tmp=$(mktemp)
my_tmp_del=$(mktemp)

# Listen exit signals to destroy temporary files
trap clean_up 0 1 2 3 6 15
clean_up () {
	rm -f "${this_script_path:?}"/aras_request.php >/dev/null 2>&1
	rm -rf "${this_script_path:?}"/*.en >/dev/null 2>&1
	rm -rf "${this_script_path:?}"/{*proc*,.*proc} >/dev/null 2>&1
	rm -rf "${this_script_path:?}"/{*json*,.*json} >/dev/null 2>&1
	rm -rf "${this_script_path:?}"/.lvn* >/dev/null 2>&1
	rm -rf ${my_tmp:?} ${my_tmp_del:?} ${PIDFILE:?}

	# Unset locale if setted before
	if [[ "${lang_setted}" ]]; then
		unset LC_ALL
		unset LC_CTYPE
	fi
}

# Global variables
cron_dir="/etc/cron.d"
shopt -s extglob; cron_dir="${cron_dir%%+(/)}"
cron_filename="woocommerce_aras"
cron_filename_update="woocommerce_aras_update"
cron_user="${user}"
systemd_user="${user}"
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
my_tmp_folder="${this_script_path}/tmp"
my_string="woocommerce-aras-cargo-integration"
tmpfiles_d="/etc/tmpfiles.d"
tmpfiles_f="woo-aras.conf"

# Not allow -x that expose sensetive informations
# Disable to write history
hide_me () {
	if [[ "${1}" == "--enable" ]]; then
		if [[ $- =~ x ]]; then my_debug=1; set +x; fi
		set +o history
	elif [[ "${1}" == "--disable" ]]; then
		[[ "${my_debug}" -eq 1 ]] && set -x
		set -o history
	fi
}

# Display automation status
my_status () {
	echo -e "\n${m_tab}${cyan}# WOOCOMMERCE - ARAS CARGO INTEGRATION STATUS${reset}"
	echo -e "${m_tab}${cyan}# ---------------------------------------------------------------------${reset}"

	{ # Start redirection to file

	# Setup status
	if [[ -e "${this_script_path}/.woo.aras.set" ]]; then
		local s_status="Completed"
		echo -e "${green}Default-Setup: $s_status${reset}"

		hide_me --enable
		if [[ ! "${api_key}" || ! "${api_secret}" || ! "${api_endpoint}" ]]; then
			api_key=$(< "$this_script_path/.key.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
			api_secret=$(< "$this_script_path/.secret.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
			api_endpoint=$(< "$this_script_path/.end.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
		fi
		hide_me --disable

		local w_delivered=$($m_curl -s -X GET -u "$api_key":"$api_secret" -H "Content-Type: application/json" "https://$api_endpoint/wp-json/wc/v3/orders?status=delivered")
		if ! grep -q "rest_invalid_param" <<< "${w_delivered}"; then
			local ts_status="Completed"
			echo -e "${green}Two-way_Workflow-Setup: $ts_status${reset}"
		else
			local ts_status="Not_Completed"
			echo -e "${green}Two-way_Workflow-Setup: ${yellow}$ts_status${reset}"
		fi

	else
		local ts_status="Null"
		local s_status="Not_Completed"
		echo -e "${green}Default-Setup: ${red}$s_status${reset}"
		echo -e "${green}Two-way_Workflow-Setup: ${yellow}$ts_status${reset}"
	fi

	# Automation status
	if [[ -e "${this_script_path}/.woo.aras.enb" ]]; then
		local a_status="Enabled"
		echo -e "${green}Automation-Status: $a_status${reset}"
	else
		local a_status="Disabled"
		echo -e "${green}Automation-Status: ${red}$a_status${reset}"
	fi

	# Two-way status
	if [[ -e "${this_script_path}/.two.way.enb" ]]; then
		local t_status="Enabled"
		echo -e "${green}Two-Way-Status: $t_status${reset}"
	else
		local t_status="Disabled"
		echo -e "${green}Two-Way-Status: ${red}$t_status${reset}"
	fi

	# Installation status
	if [[ -s "${cron_dir}/${cron_filename}" ]]; then
		local i_status="Cron"
		echo -e "${green}Installation: $i_status${reset}"
	elif [[ -s "${systemd_dir}/${service_filename}" && -s "${systemd_dir}/${timer_filename}" ]]; then
		if systemctl -t timer | grep "${timer_filename}" | grep -q "active"; then
			local i_status="Systemd"
			echo -e "${green}Installation: $i_status${reset}"
		else
			local i_status="Broken"
			echo -e "${green}Installation: ${red}$i_status${reset}"
		fi
	else
		local i_status="Failed"
		echo -e "${green}Installation: ${red}$i_status${reset}"
	fi

	# Auto-update status
	if [[ -s "${cron_dir}/${cron_filename_update}" ]]; then
		local u_status="Enabled"
		echo -e "${green}Auto-Update: $u_status${reset}"
	else
		local u_status="Disabled"
		echo -e "${green}Auto-Update: ${yellow}$u_status${reset}"
	fi

	# Get total processed order status (include rotated logs)
	local total_processed=$(find "${wooaras_log%/*}/" -name \*.log* -print0 2>/dev/null |
				xargs -0 zgrep -ci "SHIPPED" |
				$m_awk 'BEGIN {cnt=0;FS=":"}; {cnt+=$2;}; END {print cnt;}')
	echo "${green}Total_Processed_Orders: $total_processed${reset}"

	} > "${this_script_path}/.status.proc" # End redirection to file

	column -t -s ' ' <<< "$(< "${this_script_path}/.status.proc")" | $m_sed 's/^/  /'
	echo -e "${m_tab}${cyan}# ---------------------------------------------------------------------${reset}"
	echo ""
}

# Twoway pretty error
twoway_pretty_error () {
	echo -e "\n${red}*${reset} ${red}Two way fulfillment workflow installation aborted:${reset}"
	echo "${cyan}${m_tab}#####################################################${reset}"
	echo "${m_tab}${red}Cannot copy ${i##*/} to${reset}"
	echo -e "${m_tab}${red}${i%/*}${reset}\n"
	echo "$(timestamp): Cannot copy ${i##*/} to ${i%/*}" >> "${wooaras_log}"
	exit 1
}

validate_twoway () {
	# Collect missing files if exist
	missing_files=()
	for i in "${my_files[@]}"
	do
		if ! grep -qw "${my_string}" "${i}"; then
			missing_files+=("${i}")
		fi
	done

	if ! grep -qw "${my_string}" "${absolute_child_path}/functions.php"; then
		missing_files+=("${absolute_child_path}/functions.php")
	fi

	[[ "${missing_files}" ]] && return 1
}

check_delivered () {
	local w_delivered=$($m_curl -s -X GET -u "$api_key":"$api_secret" -H "Content-Type: application/json" "https://$api_endpoint/wp-json/wc/v3/orders?status=delivered")
	if ! grep -q "rest_invalid_param" <<< "${w_delivered}"; then
		echo -e "\n${yellow}*${reset} ${yellow}WARNING: Two way fulfillment workflow installation:${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${yellow}You already have 'delivered' custom order status${reset}"
		echo "${m_tab}${yellow}If you are doing the initial setup for the first time, ${red}!!!DON'T CONTINUE!!!${reset}"
		echo -e "${m_tab}${yellow}If you have integrated 'delivered' custom order status via this script before, ${green}IT'S OK TO CONTINUE${reset}\n"

		while true; do
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -r -n 1 -p "${m_tab}${BC}Do you want to continue setup? --> (Y)es | (N)o${EC} " yn < /dev/tty
			echo ""
				case "${yn}" in
					[Yy]* ) break;;
					[Nn]* ) exit 1;;
					* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}";;
				esac
		done
	fi
}

# Check dependency version
pre_check () {
	# Find distro
	echo -e "\n${green}*${reset} ${green}Checking system requirements.${reset}"
	local running_os="$(grep '^ID=' /etc/os-release | cut -d'=' -f2 | $m_sed -e 's/"//g')"
	case "${running_os}" in
		"centos"|"fedora"|"CentOS") o_s=CentOS;;
		"debian"|"ubuntu") o_s=Debian;;
		"opensuse-leap"|"opensuse-tumbleweed") o_s=OpenSUSE;;
		"arch")  o_s=Arch;;
		"alpine") o_s=Alpine;;
		*) o_s="${running_os}";;
	esac
	echo -ne "${cyan}${m_tab}########                                             [20%]\r${reset}"

	# AST Plugin version
	$m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/system_status" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.active_plugins[].plugin]' | tr -d '[],"' | $m_awk -F/ '{print $2}' | $m_awk -F. '{print $1}' | $m_sed '/^[[:space:]]*$/d' > "${this_script_path}"/.plg.proc
	$m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/system_status" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.active_plugins[].version]' | tr -d '[],"' | $m_sed '/^[[:space:]]*$/d' | $m_awk '{$1=$1};1' > "${this_script_path}"/.plg.ver.proc

	paste "${this_script_path}/.plg.proc" "${this_script_path}/.plg.ver.proc" > "${this_script_path}/.plg.act.proc"
	echo -ne "${cyan}${m_tab}##################                                   [40%]\r${reset}"

	if grep -q "woocommerce-advanced-shipment-tracking" "${this_script_path}/.plg.act.proc"; then
		# AST Plugin version
		local ast_ver=$(< "${this_script_path}/.plg.act.proc" grep "woocommerce-advanced-shipment-tracking" | $m_awk '{print $2}')
	else
		local ast_ver=false
	fi

	# WooCommerce version
	local woo_ver=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/system_status" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.environment.version]|join(" ")')
	echo -ne "${cyan}${m_tab}##########################################           [85%]\r${reset}"

	# Bash Version
	local bash_ver="${BASH_VERSINFO:-0}"

	# Wordpress Version
	local w_ver=$(grep "generator" < <($m_curl -s -X GET -H "Content-Type:text/xml;charset=UTF-8" "https://$api_endpoint/feed/") | $m_perl -pe '($_)=/([0-9]+([.][0-9]+)+)/')

	# awk Version
	if grep -q "GNU Awk" <<< "$($m_awk -Wv 2>&1)"; then
		local gnu_awk=$($m_awk -Wv | grep -w "GNU Awk")
		local gnu_awk_v=$(echo "${gnu_awk}" | $m_awk '{print $3}' | tr -d ,)
	fi

	# sed Version
	local gnu_sed=$($m_sed --version | grep -w "(GNU sed)")
	local gnu_sed_v=$(echo "${gnu_sed}" | $m_awk '{print $4}')

	# jq version
	local jq_ver=$($m_jq --help | grep "version" | tr -d [] | $m_awk '{print $7}')

	echo -ne "${cyan}${m_tab}#####################################################[100%]\r${reset}"
	echo -ne '\n'
	echo -e "${m_tab}${green}Done${reset}"

	echo -e "\n${green}*${reset} ${magenta}System Status:${reset}"
	echo "${cyan}${m_tab}#####################################################${reset}"

	{ # Start redirection to file

	if [[ "${woo_ver}" ]]; then
		if [ "${woo_ver%%.*}" -ge 5 ]; then
			echo "${green}WooCommerce_Version: $woo_ver ✓${reset}"
		elif [ "${woo_ver%%.*}" -ge 4 ]; then
			echo "${yellow}WooCommerce_Version: $woo_ver x${reset}"
		else
			echo "${red}WooCommerce_Version: $woo_ver x${reset}"
			woo_old=1
		fi
	fi

	if [[ "${jq_ver}" ]]; then
		if [ "${jq_ver//./}" -ge 16 ]; then
			echo "${green}jq_Version: $jq_ver ✓${reset}"
		else
			echo "${red}jq_Version: $jq_ver x${reset}"
			local jq_old=1
		fi
	fi

	if [[ "${w_ver}" ]]; then
		if [ "${w_ver%%.*}" -ge 5 ]; then
			echo "${green}Wordpress_Version: $w_ver ✓${reset}"
		else
			echo "${red}Wordpress_Version: $w_ver x${reset}"
			local word_old=1
		fi
	fi

	if [ "${ast_ver}" != "false" ]; then
		echo "${green}AST_Plugin: ACTIVE ✓${reset}"
		echo "${green}AST_Plugin_Version: $ast_ver ✓${reset}"
	else
		echo "${red}AST_Plugin: NOT_FOUND x${reset}"
		echo "${red}AST_Plugin_Version: NOT_FOUND x${reset}"
	fi

	if [ "${bash_ver}" -ge 5 ]; then
		echo "${green}Bash_Version: $bash_ver ✓${reset}"
	else
		echo "${red}Bash_Version: $bash_ver x${reset}"
		local bash_old=1
	fi

	if [[ "${gnu_awk}" ]]; then
		if [ "${gnu_awk_v%%.*}" -ge 5 ]; then
			echo "${green}GNU_Awk_Version: $gnu_awk_v ✓${reset}"
		else
			echo "${red}GNU_Awk_Version: $gnu_awk_v x${reset}"
			local awk_old=1
		fi
	else
		echo "${red}GNU_Awk: NOT_GNU x${reset}"
		local awk_not_gnu=1
	fi

	if [[ "${gnu_sed}" ]]; then
		if [ "${gnu_sed_v%%.*}" -ge 4 ]; then
			echo "${green}GNU_Sed_Version: $gnu_sed_v ✓${reset}"
		else
			echo "${red}GNU_Sed_Version: $gnu_sed_v x${reset}"
			local sed_old=1
		fi
	else
		echo "${red}GNU_Sed: NOT_GNU x${reset}"
		local sed_not_gnu=1
	fi

	echo "${green}Operating_System: $o_s ✓${reset}"
	echo "${green}Dependencies: Ok ✓${reset}"

	} > "${this_script_path}/.msg.proc" # End redirection to file

	column -t -s ' ' <<< "$(< "${this_script_path}/.msg.proc")" | $m_sed 's/^/  /'

	# Quit
	if [[ "${awk_not_gnu}" || "${sed_not_gnu}" || "${awk_old}" || "${sed_old}" || "${woo_old}" || "${bash_old}" || "${word_old}" || "${ast_ver}" == "false" ]]; then
		exit 1
	fi
}

continue_setup () {
	while true; do
		echo -e "\n${yellow}*${reset}${yellow} Two-way fulfillment workflow installation skipped.${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${yellow}You can manually implement two-way fulfillment workflow,${reset}"
		echo "${m_tab}${yellow}after default setup completed. Please check github${reset}"
		echo -e "${m_tab}${yellow}for manual implementation instructions.${reset}\n"
		read -r -n 1 -p "${m_tab}${BC}Do you want to continue default setup (recommended)? --> (Y)es | (N)o${EC} " yn < /dev/tty
		echo ""
		case "${yn}" in
			[Yy]* ) break;;
			[Nn]* ) exit 1;;
			* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}";;
		esac
	done
}

find_child_path () {
	local bridge="$1"
	hide_me --enable
	if [[ ! "${api_key}" || ! "${api_secret}" || ! "${api_endpoint}" ]]; then
		api_key=$(< "$this_script_path/.key.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
		api_secret=$(< "$this_script_path/.secret.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
		api_endpoint=$(< "$this_script_path/.end.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	fi
	hide_me --disable

	# Get active child theme info
	local theme_child=$($m_curl -s -X GET -u "$api_key":"$api_secret" -H "Content-Type: application/json" "https://$api_endpoint/wp-json/wc/v3/system_status" | $m_jq -r '[.theme.is_child_theme]|join(" ")')

	# Find absolute path of child theme if exist
	if [[ "${theme_child}" == "true" ]]; then
		theme_path=$($m_curl -s -X GET -u "$api_key":"$api_secret" -H "Content-Type: application/json" "https://$api_endpoint/wp-json/wc/v3/system_status" | $m_jq -r '[.environment.log_directory]|join(" ")' | $m_awk -F 'wp-content' '{print $1"wp-content"}')
		theme_name=$($m_curl -s -X GET -u "$api_key":"$api_secret" -H "Content-Type: application/json" "https://$api_endpoint/wp-json/wc/v3/system_status" | $m_jq -r '[.theme.name]|join(" ")')
		theme_name="${theme_name//[^[:alnum:]]/}"
		theme_name="${theme_name,,}"
		for i in "${theme_path}"/themes/*
		do
			if [[ -d "${i}" ]]; then
				j="${i}"
				i="${i##*/}"
				i="${i//[^[:alnum:]]/}"
				i="${i,,}"
				if grep -q "${theme_name}" <<< "${i}"; then
					absolute_child_path="${j}"
					break
				fi
			fi
		done

		# Check child theme path found or not
		if [[ ! "${absolute_child_path}" ]]; then
			echo -e "\n${red}*${reset} ${red}Could not find child theme path${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}You must execute script on application server where woocommerce runs${reset}"
			echo "${m_tab}${red}If the problem still persists complete setup without twoway-workflow,${reset}"
			echo "${m_tab}${red}And follow manual implementation instructions on github${reset}"
			echo -e "${m_tab}${red}Expected in ${theme_path}/themes/${reset}\n"
			echo "$(timestamp): Could not found child theme path, expected in $theme_path/themes/" >> "${wooaras_log}"
			exit 1
		else
			echo -e "\n${green}*${reset} ${green}ATTENTION: Please validate child theme path.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${yellow}If you are unsure, without checking  ${red}!!!DON'T CONTINUE!!!${reset}"
			echo "${m_tab}${magenta}$absolute_child_path${reset}"
			while true; do
				echo -e "\n${cyan}${m_tab}#####################################################${reset}"
				read -r -n 1 -p "${m_tab}${BC}Is child theme absolute path correct? --> (Y)es | (N)o${EC} " yn < /dev/tty
				echo ""
				case "${yn}" in
					[Yy]* ) break;;
					[Nn]* ) [[ "$bridge" == "--install" ]] && { twoway=false; continue_setup; break; } || exit 1;;
					* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}";;
				esac
			done

			# After user approval assign files and paths to array
			my_paths=("$absolute_child_path/woocommerce"
				  "$absolute_child_path/woocommerce/emails"
				  "$absolute_child_path/woocommerce/templates"
				  "$absolute_child_path/woocommerce/templates/emails"
				  "$absolute_child_path/woocommerce/templates/emails/plain")
			my_files=("$absolute_child_path/woocommerce/emails/class-wc-delivered-status-order.php"
				  "$absolute_child_path/woocommerce/templates/emails/wc-customer-delivered-status-order.php"
				  "$absolute_child_path/woocommerce/templates/emails/plain/wc-customer-delivered-status-order.php"
				  "$absolute_child_path/woocommerce/aras-woo-delivered.php")
		fi
	else
		echo -e "\n${red}*${reset} ${red}You have no activated child theme${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Without active child theme cannot implement two way fulfillment workflow.${reset}\n"
		echo "$(timestamp): You have no activated child theme, without child theme cannot implement two way fulfillment workflow" >> "${wooaras_log}"
		exit 1
	fi
}

simple_uninstall_twoway () {
	# Take back modifications from functions.php
	if [[ -w "${absolute_child_path}/functions.php" ]]; then
		if grep -qw "${my_string}" "${absolute_child_path}/functions.php"; then
			$m_sed -i "/${my_string}/,/${my_string}/d" "${absolute_child_path}/functions.php"
		else
			echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Expected string not found in function.php. Did you manually modified file after installation?${reset}\n"
			echo "$(timestamp): Expected string not found in function.php. Did you manually modified functions.php after installation? ${absolute_child_path}/functions.php" >> "${wooaras_log}"
			exit 1
		fi
	else
		echo -e "\n${red}*${reset} ${red}Twoway fulfillment uninstallation aborted, as file not writeable: ${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}${absolute_child_path}/functions.php${reset}"
		echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
		echo "$(timestamp): Twoway fulfillment uninstallation aborted, as file not writeable: ${absolute_child_path}/functions.php" >> "${wooaras_log}"
		exit 1
	fi

	# Remove installed files from child theme
	declare -a installed_files=() # This acts as local variable! You can use 'local' also.
	for i in "${my_files[@]}"
	do
		if [[ -w "${i}" ]]; then
			if grep -qw "${my_string}" "${i}"; then
				installed_files+=( "${i}" )
			else
				echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo -e "${m_tab}${red}Expected string not found in ${i}, did you manually modified file after installation?${reset}\n"
				echo "$(timestamp): Expected string not found in $i. Did you manually modified $i after installation?" >> "${wooaras_log}"
				exit 1
			fi
		else
			echo -e "\n${red}*${reset} ${red}Twoway fulfillment uninstallation aborted, as file not writeable: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}$i${reset}"
			echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Twoway fulfillment uninstallation aborted, as file not writeable: $i" >> "${wooaras_log}"
			exit 1
		fi
	done

	for i in "${installed_files[@]}"
	do
		if grep -qw "wp-content/themes" <<< "${i}"; then
			rm -f "${i}"
		else
			echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Incorrect path, $i is not the expected path to remove files${reset}\n"
			echo "$(timestamp): Incorrect path, $i is not the expected path to remove files$" >> "${wooaras_log}"
			exit 1
		fi
	done

	rm -f "${this_script_path:?}/.two.way.enb" >/dev/null 2>&1

	echo -e "\n${yellow}*${reset} ${yellow}Two way fulfillment unistallation: ${reset}"
	echo "${cyan}${m_tab}#####################################################${reset}"
	echo "${m_tab}${yellow}Uninstallation completed.${reset}"
	echo "${m_tab}${yellow}Please check your website for functionality${reset}"
	echo "$(timestamp): Two way fulfillment unistallation: Uninstallation completed." >> "${wooaras_log}"
}

uninstall_twoway () {
	if [[ -e "${this_script_path}/.woo.aras.set" ]]; then # Check default installation is completed
		find_child_path
		if [[ -e "${this_script_path}/.two.way.enb" ]]; then # Check twoway installation
			local get_delivered=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders?status=delivered" -u "$api_key":"$api_secret" -H "Content-Type: application/json") # Get data
			if [[ "${get_delivered}" ]]; then # Any data
				if [[ "${get_delivered}" != "[]" ]]; then # Check for null data
					if grep -q "${my_string}" "${absolute_child_path}/functions.php"; then # Lastly, check the file is not modified
						# Unhook woocommerce order status completed notification temporarly
						$m_sed -i -e '/\'"$my_string"'/{ r '"${this_script_path}/custom-order-status-package/action-unhook-email.php"'' -e 'b R' -e '}' -e 'b' -e ':R {n ; b R' -e '}' "${absolute_child_path}/woocommerce/aras-woo-delivered.php" >/dev/null 2>&1 &&
						# Call page to take effects function.php modifications
						$m_curl -s -X GET "https://$api_endpoint/" >/dev/null 2>&1 ||
						{
						echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}";
						echo "${cyan}${m_tab}#####################################################${reset}";
						echo -e "${m_tab}${red}Could not unhook woocommerce order status completed notification${reset}\n";
						echo "$(timestamp): Could not unhook woocommerce order status completed notification" >> "${wooaras_log}";
						exit 1;
						}

						# Get ids to array --> need bash_ver => 4
						readarray -t delivered_ids < <($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders?status=delivered" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '.[]|[.id]|join(" ")')

						# Update orders status to completed
						for id in "${delivered_ids[@]}"
						do
							if ! $m_curl -s -o /dev/null -X PUT "https://$api_endpoint/wp-json/wc/v3/orders/${id}" --fail \
								-u "$api_key":"$api_secret" \
								-H "Content-Type: application/json" \
								-d '{
								"status": "completed"
								}'; then

								echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}"
								echo "${m_tab}${cyan}#####################################################${reset}"
								echo "${red}*${reset} ${red}Cannot update order:${id} status 'delivered --> completed'${reset}"
								echo -e "${red}*${reset} ${red}Wrong Order ID or wocommerce endpoint error${reset}\n"
								echo "$(timestamp): Cannot update order:${id} status 'delivered --> completed' --> Wrong Order ID or WooCommerce endpoint error" >> "${wooaras_log}"
								exit 1
							fi
						done

						# Lastly remove files and function.php modifications
						simple_uninstall_twoway
					else
						echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}"
						echo "${cyan}${m_tab}#####################################################${reset}"
						echo -e "${m_tab}${red}Expected string not found in function.php. Did you manually modified file after installation?${reset}\n"
						echo "$(timestamp): Expected string not found in function.php. Did you manually modified functions.php after installation? $absolute_child_path/functions.php" >> "${wooaras_log}"
						exit 1
					fi

				else
                                	# There is no any order which flagged as delivered so remove files and mods directly
                                	simple_uninstall_twoway
				fi
			fi
		else
			echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Couldn't find twoway fulfillment installation${reset}\n"
			echo "$(timestamp): Two way fulfillment unistallation aborted, couldn't find twoway fulfillment installation" >> "${wooaras_log}"
			exit 1
		fi
	else
		echo -e "\n${red}*${reset} ${red}Two way fulfillment unistallation aborted: ${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Default installation not completed${reset}\n"
		echo "$(timestamp): Two way fulfillment unistallation aborted: default installation not completed" >> "${wooaras_log}"
		exit 1
	fi
}

# (processing --> shipped --> delivered) twoway fulfillment workflow setup
install_twoway () {
	check_delivered
	find_child_path --install
	if [[ "${twoway}" == "true" ]]; then
		# Get ownership operations
		if [[ -f "${absolute_child_path}/functions.php" ]]; then
			if [[ -r "${absolute_child_path}/functions.php" ]]; then
				local GROUP_OWNER="$(stat --format "%G" "${absolute_child_path}/functions.php" 2> /dev/null)"
				local USER_OWNER="$(stat --format "%U" "${absolute_child_path}/functions.php" 2> /dev/null)"
			else
				echo -e "\n${red}*${reset} ${red}Installation aborted, as file not readable: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${red}$absolute_child_path/functions.php${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Installation aborted, as file not readable: $absolute_child_path/functions.php" >> "${wooaras_log}"
				exit 1
			fi
		elif [[ -r "${theme_path}/index.php" ]]; then
			local GROUP_OWNER="$(stat --format "%G" "${theme_path}/index.php" 2> /dev/null)"
			local USER_OWNER="$(stat --format "%U" "${theme_path}/index.php" 2> /dev/null)"
		else
			echo -e "\n${red}*${reset} ${red}Installation aborted, as file not readable: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}$theme_path/index.php${reset}"
			echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Installation aborted, as file not readable: $theme_path/index.php" >> "${wooaras_log}"
			exit 1
		fi

		# Copy, create apply operations
		if [[ $GROUP_OWNER && $USER_OWNER ]]; then
			# Function.php operations
			if [[ ! -f "${absolute_child_path}/functions.php" ]]; then
				if ! grep -q 'Permission denied' <<< "$(touch "${absolute_child_path}/functions.php" 2>&1)"; then
					cat "${this_script_path}/custom-order-status-package/functions.php" > "${absolute_child_path}/functions.php" &&
					chown "$USER_OWNER":"$GROUP_OWNER" "${absolute_child_path}/functions.php" ||
					{
					echo -e "\n${red}*${reset} ${red}Installation aborted, as file cannot modified: ${reset}"
					echo "${cyan}${m_tab}#####################################################${reset}"
					echo -e "${m_tab}${red}$absolute_child_path/functions.php${reset}\n"
					echo "$(timestamp): Installation aborted, as file cannot modified: $absolute_child_path/functions.php" >> "${wooaras_log}"
					exit 1
					}
				else
					echo -e "\n${red}*${reset} ${red}Installation aborted, as file not writeable: ${reset}"
					echo "${cyan}${m_tab}#####################################################${reset}"
					echo "${m_tab}${red}$absolute_child_path/functions.php${reset}"
					echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
					echo "$(timestamp): Installation aborted, as file not writeable: $absolute_child_path/functions.php" >> "${wooaras_log}"
					exit 1
				fi
			elif [[ -w "${absolute_child_path}/functions.php" ]]; then
				if [[ -s "${absolute_child_path}/functions.php" ]]; then
					# Take backup of user functions.php first
					cp "${absolute_child_path}/functions.php" "${absolute_child_path}/functions.php.wo-aras-backup-$$-$(date +%d-%m-%Y)" &&
					chown "${USER_OWNER}":"${GROUP_OWNER}" "${absolute_child_path}/functions.php.wo-aras-backup-$$-$(date +%d-%m-%Y)" ||
					{
					echo -e "\n${red}*${reset} ${red}Two way fulfillment workflow installation aborted: ${reset}"
					echo "${cyan}${m_tab}#####################################################${reset}"
					echo -e "${m_tab}${red}Cannot take backup of ${absolute_child_path}/functions.php${reset}\n"
					echo "$(timestamp): Two way fulfillment workflow installation aborted: Cannot take backup of ${absolute_child_path}/functions.php" >> "${wooaras_log}"
					exit 1
					}

					if ! grep -q "${my_string}" "${absolute_child_path}/functions.php"; then
						if [ $(< "${absolute_child_path}/functions.php" $m_sed '1q') == "<?php" ]; then
							< "${this_script_path}/custom-order-status-package/functions.php" $m_sed "1 s/.*/ /" >> "${absolute_child_path}/functions.php"
						else
							echo -e "\n${red}*${reset} ${red}Two way fulfillment workflow installation aborted: ${reset}"
							echo "${cyan}${m_tab}#####################################################${reset}"
							echo "${m_tab}${red}Cannot recognise your child theme function.php, expected php shebang at line 1${reset}"
							echo -e "${magenta}$absolute_child_path/functions.php${reset}\n"
							echo "$(timestamp): Cannot recognise your child theme function.php, expected php shebang at line 1 $absolute_child_path/functions.php" >> "${wooaras_log}"
							exit 1
						fi
					fi
				fi
			else
				echo -e "\n${red}*${reset} ${red}Installation aborted, as file not writeable: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${red}${absolute_child_path}/functions.php${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Installation aborted, as file not writeable: ${absolute_child_path}/functions.php" >> "${wooaras_log}"
				exit 1
			fi

			# File, folder operations
			if [[ -w "${absolute_child_path}/functions.php" ]]; then
				for i in "${my_paths[@]}"
				do
					if [[ ! -d "${i}" ]]; then
						mkdir "${i}" &&
						chown "${USER_OWNER}":"${GROUP_OWNER}" "${i}" ||
						{
						echo -e "\n${red}*${reset} ${red}Two way fulfillment workflow Installation aborted: ${reset}"
						echo "${cyan}${m_tab}#####################################################${reset}"
						echo -e "${m_tab}${red}Cannot create folder: ${i}${reset}\n"
						echo "$(timestamp): Installation aborted, cannot create folder ${i}" >> "${wooaras_log}"
						exit 1
						}
					fi
				done

				for i in "${my_files[@]}"
				do
					if [[ ! -f "${i}" ]]; then
						if grep -qw "woocommerce/emails" <<< "${i}"; then
							cp "${this_script_path}/custom-order-status-package/class-wc-delivered-status-order.php" "${i%/*}/" &&
							chown -R "${USER_OWNER}":"${GROUP_OWNER}" "${i%/*}/" || twoway_pretty_error
						elif grep -qw "emails/plain" <<< "${i}"; then
							cp "${this_script_path}/custom-order-status-package/wc-customer-delivered-status-order.php" "${i%/*}/" &&
							chown -R "${USER_OWNER}":"${GROUP_OWNER}" "${i%/*}/" || twoway_pretty_error
						elif grep -qw "aras-woo-delivered.php" <<< "${i}"; then
							cp "${this_script_path}/custom-order-status-package/aras-woo-delivered.php" "${i%/*}/" &&
							chown -R "${USER_OWNER}":"${GROUP_OWNER}" "${i%/*}/" || twoway_pretty_error
						else
							cp "${this_script_path}/custom-order-status-package/wc-customer-delivered-status-order.php" "${i%/*}/" &&
							chown -R "${USER_OWNER}":"${GROUP_OWNER}" "${i%/*}/" || twoway_pretty_error
						fi
					fi
				done
			else
				echo -e "\n${red}*${reset} ${red}Installation aborted, as file not writeable: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${red}$absolute_child_path/functions.php${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Installation aborted, as file not writeable: $absolute_child_path/functions.php" >> "${wooaras_log}"
				exit 1
			fi
		else
			echo -e "\n${red}*${reset} ${red}Installation aborted, could not read file permissions: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Installation aborted, could not read file permissions" >> "${wooaras_log}"
			exit 1
		fi

		# Validate installation
		if ! validate_twoway; then
			echo -e "\n${red}*${reset} ${red}Two way fulfillment workflow installation aborted: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Missing file(s) ${missing_files[@]}${reset}\n"
			echo "$(timestamp): Installation aborted, missing file(s) ${missing_files[@]}" >> "${wooaras_log}"
			exit 1
		else
			# Time to enable functions.php modifications
			$m_sed -i '/aras_woo_include/c include( get_stylesheet_directory() .'"'/woocommerce/aras-woo-delivered.php'"'); //aras_woo_enabled' "${absolute_child_path}/functions.php" ||
			{ echo "Installation failed, as sed failed"; exit 1; }

			echo -e "\n${green}*${reset} ${green}Two way fulfillment workflow is now enabled.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${yellow}Please check your website working correctly and able to login admin panel.${reset}"
			echo "${m_tab}${yellow}Check 'delivered' order status registered and 'delivered' email template exist under woo commerce emails tab${reset}"
			echo "${m_tab}${yellow}If your website or admin panel is broken:${reset}"
			echo "${m_tab}${yellow}First try to restart your web server apache,nginx or php-fpm in an other session${reset}"
			echo "${m_tab}${yellow}If still not working please select r for starting recovery process${reset}"
			echo "${m_tab}${yellow}If everything on the way CONGRATS select c for continue the setup${reset}"

			# Anything broken? Let check website healt and if encountered any errors revert modifications
			while true
			do
				echo "${m_tab}${cyan}#####################################################${reset}"
				read -r -n 1 -p "${m_tab}${BC}r for recovery and quit setup, c for continue${EC} " cs < /dev/tty
				echo ""
				case "${cs}" in
					[Rr]* ) $m_sed -i '/aras_woo_enabled/c \/\/aras_woo_include( get_stylesheet_directory() .'"'/woocommerce/aras-woo-delivered.php'"');' "${absolute_child_path}/functions.php";
						echo -e "\n${yellow}Two way fulfillment workflow installation aborted, recovery process completed.${reset}";
						echo "$(timestamp): Two way fulfillment workflow installation aborted, recovery process completed." >> "${wooaras_log}";
						exit 1;;
					[Cc]* ) depriv "${this_script_path}/.two.way.enb";  break;;
					* ) echo -e "\n${m_tab}${magenta}Please answer r or c${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
				esac
			done

			echo -e "\n${green}*${reset} ${green}Two way fulfillment workflow installation: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${green}Completed${reset}"
			echo "$(timestamp): Two way fulfillment workflow installation completed" >> "${wooaras_log}"
		fi
	fi
}

# Dialog box for twoway fulfillment workflow setup
my_whip_tail () {
	if (whiptail --title "Two-Way Fulfillment Setup" --yesno "Do you want to auto implement two-way (processing->shipped->delivered) fulfillment workflow? If you choose 'NO' script will configure itself for default oneway (processing->completed) setup. Please keep in mind that If you decided to implement twoway workflow be sure you execute this script on webserver where woocommerce runs and don't have any woocommerce custom order statuses installed before. Script will add custom 'delivered' order status to woocommerce fulfillment workflow." 10 110); then
		twoway=true
	else
		twoway=false
	fi
}

# Uninstall bundles like cron jobs, systemd services, logrotate, logs
# This function not removes twoway two way fulfillment workflow.
hard_reset () {
	if [[ -s "${cron_dir}/${cron_filename}" ]]; then
		if [[ -w "${cron_dir}/${cron_filename}" ]]; then
			rm -f  "${cron_dir:?}/${cron_filename:?}" >/dev/null 2>&1
			echo -e "\n${yellow}*${reset} ${yellow}Main cron job uninstalled:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${cron_dir}/${cron_filename}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Cron uninstall aborted, as file not writable: ${cron_dir}/${cron_filename}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
			echo "$(timestamp): Uninstallation error: $cron_dir/$cron_filename not writeable" >> "${wooaras_log}"
		fi
	fi

	if [[ -s "${cron_dir}/${cron_filename_update}" ]]; then
		if [[ -w "${cron_dir}/${cron_filename_update}" ]]; then
			rm -f  "${cron_dir:?}/${cron_filename_update:?}" >/dev/null 2>&1
			echo -e "\n${yellow}*${reset} ${yellow}Updater cron job uninstalled:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${cron_dir}/${cron_filename_update}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Updater cron job uninstallation aborted, as file not writable: ${cron_dir}/${cron_filename_update}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
			echo "$(timestamp): Uninstallation error: ${cron_dir}/${cron_filename_update} is not writeable" >> "${wooaras_log}"
		fi
	fi


	if [[ -s "${systemd_dir}/${service_filename}" || -s "${systemd_dir}/${timer_filename}" ]]; then
		if [[ -w "${systemd_dir}/${service_filename}" ]]; then
			systemctl disable "${timer_filename}" >/dev/null 2>&1
			systemctl stop "${timer_filename}" >/dev/null 2>&1
			systemctl daemon-reload >/dev/null 2>&1
			rm -rf  "${systemd_dir:?}/${service_filename:?}" "${systemd_dir:?}/${timer_filename:?}"  >/dev/null 2>&1
			echo -e "\n${yellow}*${reset} ${yellow}Systemd unit uninstalled: services stopped:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${systemd_dir}/${service_filename}${reset}"
			echo "${yellow}${m_tab}${systemd_dir}/${timer_filename}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Systemd uninstall aborted, as directory not writable: $systemd_dir${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
			echo "$(timestamp): Uninstallation error: ${systemd_dir}/${service_filename} not writeable" >> "${wooaras_log}"
		fi
	fi

	if [[ -s "${logrotate_dir}/${logrotate_filename}" ]]; then
		if [[ -w "${logrotate_dir}/${logrotate_filename}" ]]; then
			rm -f "${logrotate_dir:?}/${logrotate_filename:?}" >/dev/null 2>&1
			echo -e "\n${yellow}*${reset} ${yellow}Logrotate removed:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${logrotate_dir}/${logrotate_filename}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Logrotate uninstall aborted, as file not writable: ${logrotate_dir}/${logrotate_filename}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
			echo "$(timestamp): Uninstallation error: ${logrotate_dir}/${logrotate_filename} not writeable" >> "${wooaras_log}"
		fi
	fi

	if [[ -s "${tmpfiles_d}/${tmpfiles_f}" ]]; then
		if [[ -w "${tmpfiles_d}/${tmpfiles_f}" ]]; then
			rm -f "${tmpfiles_d:?}/${tmpfiles_f:?}" >/dev/null 2>&1
			echo -e "\n${yellow}*${reset} ${yellow}systemd_tmpfiles conf removed:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${tmpfiles_d}/${tmpfiles_f}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Uninstallation aborted, as file not writable: ${tmpfiles_d}/${tmpfiles_f}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
			echo "$(timestamp): Uninstallation aborted, as file not writable: ${tmpfiles_d}/${tmpfiles_f}" >> "${wooaras_log}"
		fi
	fi

	if grep -q "ARAS Cargo" "${logrotate_conf}"; then
		if [[ -w "${logrotate_conf}" ]]; then
			$m_sed -n -e '/^# Via WooCommerce/,/^# END-WOOARAS/!p' -i "${logrotate_conf}" || { echo "Logrotate cannot removed, as sed failed"; exit 1; }
			echo -e "\n${yellow}*${reset} ${yellow}Logrotate rules removed from:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}${logrotate_conf}${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Uninstallation aborted, as file not writable: ${logrotate_conf}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
			echo "$(timestamp): Uninstallation aborted, as file not writable: ${logrotate_conf}" >> "${wooaras_log}"
		fi
	fi

	if grep -q "woo-aras" "/etc/rc.local"; then
		if [[ -w "/etc/rc.local" ]]; then
			$m_sed -i '/woo-aras/d' "/etc/rc.local" || { echo "rc.local rule cannot removed, as sed failed"; exit 1; }
			echo -e "\n${yellow}*${reset} ${yellow}rc.local rule removed from:${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${yellow}${m_tab}/etc/rc.local${reset}"
		else
			echo -e "\n${red}*${reset} ${red}Uninstallation aborted, as file not writable: /etc/rc.local${reset}"
                        echo "${cyan}${m_tab}#####################################################${reset}"
                        echo "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}"
                        echo "$(timestamp): Uninstallation aborted, as file not writable: /etc/rc.local" >> "${wooaras_log}"
		fi
	fi
}

# Instead of uninstall just disable/inactivate script (for urgent cases & debugging purpose)
disable () {
	if [[ -e "${this_script_path}/.woo.aras.set" ]]; then
		if [[ -e "${this_script_path}/.woo.aras.enb" ]]; then
			if [[ -w "${this_script_path}" ]]; then
				rm -f "${this_script_path:?}/.woo.aras.enb" >/dev/null 2>&1 &&
				echo -e "\n${green}*${reset} ${green}Aras-WooCommerce integration disabled.${reset}"
				echo -e "${cyan}${m_tab}#####################################################${reset}\n"
			else
				echo -e "\n${red}*${reset} ${red}Cannot disable Aras-WooCommerce integration: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${red}As folder not writeable ${this_script_path}${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Cannot disable Aras-WooCommerce integration: as folder not writeable ${this_script_path}" >> "${wooaras_log}"
				exit 1
			fi
		else
			echo -e "\n${red}*${reset} ${red}Cannot disable Aras-WooCommerce integration: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Integration already disabled.${reset}\n"
			echo "$(timestamp): Cannot disable Aras-WooCommerce integration: already disabled" >> "${wooaras_log}"
			exit 1
		fi
	else
		echo -e "\n${red}*${reset} ${red}Cannot disable Aras-WooCommerce integration: ${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Default installation not completed${reset}\n"
		echo "$(timestamp): Cannot disable Aras-WooCommerce integration: default installation not completed" >> "${wooaras_log}"
		exit 1
	fi
}

# Enable/activate script if previously disabled
enable () {
	if [[ -e "${this_script_path}/.woo.aras.set" ]]; then
		if [[ ! -e "${this_script_path}/.woo.aras.enb" ]]; then
			if [[ -w "${this_script_path}" ]]; then
				depriv "${this_script_path}/.woo.aras.enb" >/dev/null 2>&1
				echo -e "\n${green}*${reset} ${green}Aras-WooCommerce integration enabled.${reset}"
				echo -e "${cyan}${m_tab}#####################################################${reset}\n"
			else
				echo -e "\n${red}*${reset} ${red}Cannot enable Aras-WooCommerce integration: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${red}As folder not writeable ${this_script_path}${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Cannot enable Aras-WooCommerce integration: as folder not writeable ${this_script_path}" >> "${wooaras_log}"
				exit 1
			fi
		else
			echo -e "\n${red}*${reset} ${red}Cannot enable Aras-WooCommerce integration: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Integration already enabled.${reset}\n"
			echo "$(timestamp): Cannot disable Aras-WooCommerce integration: already enabled " >> "${wooaras_log}"
			exit 1
		fi
	else
		echo -e "\n${red}*${reset} ${red}Cannot enable Aras-WooCommerce integration: ${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Default installation not completed${reset}\n"
		echo "$(timestamp): Cannot enable Aras-WooCommerce integration: default installation not completed" >> "${wooaras_log}"
		exit 1
	fi
}

un_install () {
	# Remove twoway fulfillment workflow
	if [[ -e "${this_script_path}/.two.way.enb" ]]; then
		uninstall_twoway
	fi

	# Removes install bundles aka cron jobs, systemd services, logrotate, systemd_tmpfiles
	if [[ -e "${cron_dir}/${cron_filename}" ||
		-e "${systemd_dir}/${service_filename}" ||
		-e "${logrotate_dir}/${logrotate_filename}" ||
		-e "${systemd_dir}/${timer_filename}" ||
		-e "${tmpfiles_d}/${tmpfiles_f}" ||
		-e "${cron_dir}/${cron_filename_update}" ]]; then
		hard_reset
	fi

	# Remove logs
	if [[ -e "${wooaras_log}" ]]; then
		rm -f "${wooaras_log:?}" >/dev/null 2>&1
		echo -e "\n${yellow}*${reset} ${yellow}Logs removed:${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${yellow}${m_tab}${wooaras_log}${reset}\n"
	fi

	# Remove immutable bit & lock files
	for i in "${this_script_path}"/.*lck
	do
		chattr -i "$i" >/dev/null 2>&1
	done
	rm -rf "${this_script_path:?}"/.*lck >/dev/null 2>&1

	rm -f "${this_script_path:?}/.woo.aras.set" >/dev/null 2>&1
	rm -f "${this_script_path:?}/.woo.aras.enb" >/dev/null 2>&1
	rm -rf "${this_script_path:?}/tmp" >/dev/null 2>&1

	echo "${green}*${reset} ${green}Uninstallation completed${reset}"
	echo -e "${cyan}${m_tab}#####################################################${reset}\n"
}

# Disable setup after successful installation
on_fly_disable () {
	depriv "${this_script_path}/.woo.aras.set" || { echo "Installation failed, as cannot create ${this_script_path}/.woo.aras.set"; exit 1; }
	depriv "${this_script_path}/.woo.aras.enb" || { echo "Installation failed, as cannot create ${this_script_path}/.woo.aras.enb"; exit 1; }
}

# Pre-setup operations
on_fly_enable () {
		# Remove lock files (hard-reset) to re-start fresh setup
		# Remove IMMUTABLE bit
		for i in "${this_script_path}"/.*lck
		do
			chattr -i "${i}" >/dev/null 2>&1
		done
		rm -rf "${this_script_path:?}"/.*lck >/dev/null 2>&1

		rm -f "${this_script_path:?}/.woo.aras.set" >/dev/null 2>&1
		rm -f "${this_script_path:?}/.woo.aras.enb" >/dev/null 2>&1

		# Check absolute files from previous setup
		if [[ -e "${cron_dir}/${cron_filename}" ||
			-e "${systemd_dir}/${service_filename}" ||
			-e "${logrotate_dir}/${logrotate_filename}" ||
			-e "${systemd_dir}/${timer_filename}" ||
			-e "${tmpfiles_d}/${tmpfiles_f}" ||
			-e "${cron_dir}/${cron_filename_update}" ]]; then

			while true
			do
				echo -e "\n${green}*${reset}${green} Installation found${reset}"
				echo "${m_tab}${cyan}##################################################################${reset}"
				read -r -n 1 -p "${m_tab}${BC}Do you want to continue with hard reset? --> (Y)es | (N)o${EC} " yn < /dev/tty
				echo ""
				case "${yn}" in
					[Yy]* ) echo -e "\n${green}*${reset} ${green}Hard resetting for fresh installation: ${reset}";
						echo -ne "${cyan}${m_tab}########                                             [20%]\r${reset}";
						sleep 1;
						echo -ne "${cyan}${m_tab}##################                                   [40%]\r${reset}";
						echo -ne "${cyan}${m_tab}#################################                    [60%]\r${reset}";
						sleep 2;
						echo -ne "${cyan}${m_tab}#####################################                [75%]\r${reset}";
						echo -ne "${cyan}${m_tab}##########################################           [85%]\r${reset}";
						sleep 1;
						echo -ne "${cyan}${m_tab}#####################################################[100%]\r${reset}";
						echo -ne '\n';
						hard_reset;
						break;;
					[Nn]* ) break;;
					*     ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
				esac
			done
		fi

		# WELCOME ASCII
		echo -e  "\n${cyan}${m_tab}######################################################${reset}"
		echo  "${m_tab_3}${green} __          ________ _      _____ ____  __  __ ______ "
		echo  "${m_tab_3} \ \        / |  ____| |    / ____/ __ \|  \/  |  ____|"
		echo  "${m_tab_3}  \ \  /\  / /| |__  | |   | |   | |  | | \  / | |__   "
		echo  "${m_tab_3}   \ \/  \/ / |  __| | |   | |   | |  | | |\/| |  __|  "
		echo  "${m_tab_3}    \  /\  /  | |____| |___| |___| |__| | |  | | |____ "
		echo  "${m_tab_3}     \/  \/   |______|______\_____\____/|_|  |_|______|${reset}"
		echo ""
		echo -e "${cyan}${m_tab}######################################################${reset}\n"

		# STEP 1
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}1${reset}${m_tab_3}${red}**${reset}${yellow} Clear wordpress cache before starting the setup${reset} ${red}**${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		# STEP 2
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

		# STEP 3
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}3${reset}${m_tab_3}${red}**${reset}${yellow}     Be sure you have WooCommerce AST Plugin${reset}     ${red}**${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		# STEP 4
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}4${reset}${m_tab_3}${red}**${reset}${yellow} Create some test orders, If you haven't any yet${reset} ${red}**${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		# STEP 5
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${green}5${reset}${m_tab_3}${red}**${reset}${yellow} Note your wordpress child theme absolute path${reset} ${red}**${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"

		read -n 1 -s -r -p "${green}> When ready press any key to continue setup, q for quit${reset}" reply < /dev/tty; echo
		if [ "$reply" == "q" ]; then
			echo
			exit 0
		elif [ ! -f "${this_script_path}/.two.way.enb" ]; then
			my_whip_tail
		else
			echo -e "\n${yellow}*${reset} ${yellow}Two way fulfillment workflow already installed: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
		fi
}

# If user manually implemented two-way workflow also need to call this function to activate it
# sudo ./woocommerce-aras-cargo.sh  --twoway-enable
twoway_enable () {
	# Get absolte path of child theme
	if [[ -e "${this_script_path}/.woo.aras.set" ]]; then
		find_child_path
	else
		echo -e "\n${red}*${reset} ${red}Two way fulfillment cannot enable: ${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Default installation not completed${reset}\n"
		echo "$(timestamp): Two way fulfillment cannot enabled: default installation not completed" >> "${wooaras_log}"
		exit 1
	fi

	# Check function.php modifications completed
	if grep -q "${my_string}" "${absolute_child_path}/functions.php"; then
		if grep -qw "include( get_stylesheet_directory() .'/woocommerce/aras-woo-delivered.php'); //aras_woo_enabled" "${absolute_child_path}/functions.php"; then
			local functions_mod="applied"
		else
			local functions_mod="not_applied"
		fi
	else
		local functions_mod="not_applied"
	fi

	# Check necessary files installed
	declare missing_t=()
	for i in "${my_files[@]}"
	do
		if [[ ! -f "${i}" ]]; then
			missing_t+=( "${i}" )
		fi
	done

	if [[ ! "${missing_t}" ]]; then
		if [[ ! -e "${this_script_path}/.two.way.enb" ]]; then
			if [[ "${functions_mod}" == "applied" ]]; then
				depriv "${this_script_path}/.two.way.enb"
				echo -e "\n${green}*${reset} ${green}Two way fulfillment workflow enabled successfully: ${reset}"
				echo -e "${cyan}${m_tab}#####################################################${reset}\n"
				echo "$(timestamp): Two way fulfillment workflow manually enabled successfully" >> "${wooaras_log}"
			else
				echo -e "\n${red}*${reset} ${red}Cannot enable two way fulfillment workflow: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${red}Couldn't find necessary modifications in:${reset}"
				echo "${m_tab}${magenta}$absolute_child_path/functions.php${reset}"
				echo -e "${m_tab}${red}Follow the guideline 'Two-way workflow installation' on github${reset}\n"
				echo "$(timestamp): Cannot enable two way fulfillment workflow: Couldn't find necessary modifications in $absolute_child_path/functions.php" >> "${wooaras_log}"
				exit 1
			fi
		else
			echo -e "\n${green}*${reset} ${green}Two way fulfillment workflow has been already enabled: ${reset}"
			echo -e "${cyan}${m_tab}#####################################################${reset}\n"
			echo "$(timestamp): Two way fulfillment workflow has been already enabled:" >> "${wooaras_log}"
			exit 0
		fi
	else
		echo -e "\n${red}*${reset} ${red}Cannot enable two way fulfillment workflow: ${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Couldn't find necessary files, please check your setup${reset}"
		echo "${m_tab}${magenta}${missing_t}${reset}"
		echo -e "${m_tab}${red}Follow the guideline 'Two Way Fulfillment Manual Setup' on github${reset}\n"
		echo "$(timestamp): Cannot enable two way fulfillment workflow: couldn't find necessary files $missing_t, please check your setup" >> "${wooaras_log}"
		exit 1
	fi
}

twoway_disable () {
	if [[ -e "${this_script_path}/.woo.aras.set" ]]; then
		if [[ -e "${this_script_path}/.two.way.enb" ]]; then
			if [[ -w "${this_script_path}" ]]; then
				rm -f "${this_script_path:?}/.two.way.enb" >/dev/null 2>&1
				echo -e "\n${green}*${reset} ${green}Two-way fulfillment workflow disabled.${reset}"
				echo -e "${cyan}${m_tab}#####################################################${reset}\n"
			else
				echo -e "\n${red}*${reset} ${red}Cannot disable two-way workflow: ${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${red}As folder not writeable ${this_script_path}${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Cannot disable two-way workflow: as folder not writeable ${this_script_path}" >> "${wooaras_log}"
				exit 1
			fi
		else
			echo -e "\n${red}*${reset} ${red}Cannot disable two-way workflow: ${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Two-way workflow already disabled.${reset}\n"
			echo "$(timestamp): Cannot disable two-way workflow: already disabled" >> "${wooaras_log}"
			exit 1
		fi
	else
		echo -e "\n${red}*${reset} ${red}Cannot disable two-way workflow: ${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Default installation not completed${reset}\n"
		echo "$(timestamp): Cannot disable two-way workflow: default installation not completed" >> "${wooaras_log}"
		exit 1
	fi
}

download () {
	$m_curl -f -s -k -R -L --compressed -z "$sh_output" -o "$sh_output" "$sh_github" >/dev/null 2>&1
	result=$?

	if [[ "${result}" -ne 0 ]]; then
		echo -e "\n${red}*${reset} ${red}Upgrade failed:${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Could not download: $sh_github${reset}"
		echo "$(timestamp): Upgrade failed, could not download: $sh_github" >> "${wooaras_log}"
		send_mail "Upgrade failed:  could not download: $sh_github"
		exit 1
	fi

	# Test the downloaded content
	if [[ "$(tail -n 1 "${sh_output}" | head -n 1 | cut -c 1-7)" != "exit \$?" ]]; then
		echo -e "\n${red}*${reset} ${red}Upgrade failed:${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Downloaded $sh_output is incomplete, please re-run${reset}"
		echo "$(timestamp): Upgrade failed, cannot verify downloaded script, please re-run." >> "${wooaras_log}"
		send_mail "Upgrade failed: Upgrade failed, cannot verify downloaded script, please re-run."
		exit 1
	fi

	# Keep user defined settings before upgrading
	declare -A keeped
	declare -a getold=("mail_to" "mail_from" "mail_subject_suc" "mail_subject_err"
			   "t_date" "s_date" "e_date" "wooaras_log" "send_mail_err"
			   "company_name" "company_domain" "cron_minute" "cron_minute_update"
			   "on_calendar" "delivery_time" "max_distance" "send_mail_command"
			   "maxsize" "l_maxsize")

	for i in "${getold[@]}"
	do
		read "keeped[$i]" <<< "$(grep "^$i=" "${cron_script_full_path}" | $m_awk -F= '{print $2}')"
	done

	# Apply old user defined settings before upgrading
	# TODO: get sed exit code for failed 'find and replace' operations and exit
	for i in "${!keeped[@]}"
	do
		$m_sed -i -e "s|^$i=.*|$i=${keeped[$i]}|" "${sh_output}"
	done

	$m_sed -n '/^# If you use sendmail/,/^# END/p' 2>/dev/null "${cron_script_full_path}" | $m_sed '1,1d' | $m_sed '$d' > "${this_script_path}/upgr.proc"
	$m_sed -i '
		/^# If you use sendmail/,/^# END/{
			/^# If you use sendmail/{
				n
				r '"${this_script_path}"'/upgr.proc
			}
			/^# END/!d
		}
	' "${sh_output}"

	# Copy over permissions from old version
	local OCTAL_MODE="$(stat -c "%a" "${cron_script_full_path}" 2> /dev/null)"
	if [[ ! "${OCTAL_MODE}" ]]; then
		local OCTAL_MODE="$(stat -f '%p' "${cron_script_full_path}")"
	fi

	# Copy over ownership from old version
	local U_GROUP_OWNER="$(stat --format "%G" "${cron_script_full_path}" 2> /dev/null)"
	local U_USER_OWNER="$(stat --format "%U" "${cron_script_full_path}" 2> /dev/null)"

	# Generate the update script
	cat > "${this_script_path}/${update_script}" <<- EOF
	#!/usr/bin/env bash

	# Overwrite old file with new
	if ! mv -f "${sh_output}" "${cron_script_full_path}"; then
		echo -e "\\n\$(tput setaf 1)*\$(tput sgr0) \$(tput setaf 1)Upgrade failed:\$(tput sgr0)"
		echo "\$(tput setaf 6)${m_tab}#####################################################\$(tput sgr0)"
		echo -e "${m_tab}\$(tput setaf 1)Failed moving ${sh_output} to ${cron_script_full_path}\$(tput sgr0)\\n"
		echo "$(timestamp): Upgrade failed: failed moving ${sh_output} to ${cron_script_full_path}" >> "${wooaras_log}"

		if [ $send_mail_err -eq 1 ]; then
			echo "Upgrade failed: failed moving ${sh_output} to ${cron_script_full_path}" | mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
		fi

		#remove the tmp script before exit
		rm -f \$0
		exit 1
	fi

	# Replace permission
	if ! chmod "${OCTAL_MODE}" "${cron_script_full_path}"; then
		echo -e "\\n\$(tput setaf 1)*\$(tput sgr0) \$(tput setaf 1)Upgrade failed:\$(tput sgr0)"
		echo "\$(tput setaf 6)${m_tab}#####################################################\$(tput sgr0)"
		echo -e "${m_tab}\$(tput setaf 1)Unable to set permissions on ${cron_script_full_path}\$(tput sgr0)\\n"
		echo "$(timestamp): Upgrade failed: Unable to set permissions on ${cron_script_full_path}" >> "${wooaras_log}"

		if [ $send_mail_err -eq 1 ]; then
			 echo "Upgrade failed: Unable to set permissions on ${cron_script_full_path}" | mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
		fi

		#remove the tmp script before exit
		rm -f \$0
		exit 1
	fi

	# Replace ownership
	if ! chown "$U_USER_OWNER":"$U_GROUP_OWNER" "${cron_script_full_path}"; then
		echo -e "\\n\$(tput setaf 1)*\$(tput sgr0) \$(tput setaf 1)Upgrade failed:\$(tput sgr0)"
		echo "\$(tput setaf 6)${m_tab}#####################################################\$(tput sgr0)"
		echo -e "${m_tab}\$(tput setaf 1)Unable to set ownership on ${cron_script_full_path}\$(tput sgr0)\\n"
		echo "$(timestamp): Upgrade failed: Unable to set ownership on ${cron_script_full_path}" >> "${wooaras_log}"

		if [ $send_mail_err -eq 1 ]; then
			echo "Upgrade failed: Unable to set ownership on ${cron_script_full_path}" | mail -s "$mail_subject_err" -a "$mail_from" "$mail_to"
		fi

		#remove the tmp script before exit
		rm -f \$0
		exit 1
	fi

	if [[ "${f_update}" ]]; then
		echo -e "\\n\$(tput setaf 2)*\$(tput sgr0) \$(tput setaf 2)Force upgrade completed.\$(tput sgr0)"
		echo "Force upgrade completed. WooCommerce-aras integration script updated to version ${latest_version}" | mail -s "$mail_subject_suc" -a "$mail_from" "$mail_to" >/dev/null 2>&1
	else
		echo -e "\\n\$(tput setaf 2)*\$(tput sgr0) \$(tput setaf 2)Upgrade completed.\$(tput sgr0)"
		echo -e "Upgrade completed. WooCommerce-aras integration script updated to version ${latest_version}\n${changelog_p}" | mail -s "$mail_subject_suc" -a "$mail_from" "$mail_to" >/dev/null 2>&1
	fi

	echo "\$(tput setaf 6)${m_tab}#####################################################\$(tput sgr0)"
	echo -e "${m_tab}\$(tput setaf 2)Script updated to version ${latest_version}\$(tput sgr0)\\n"
	echo "$(timestamp): Upgrade completed. Script updated to version ${latest_version}" >> "${wooaras_log}"

	# Clean-up
        rm -rf ${this_script_path}/upgr.proc ${PIDFILE} || { echo "Temproray files cannot removed"; }

	#remove the tmp script before exit
	rm -f \$0
	EOF

	# Replaced with $0, so code will update
	exec "$my_bash" "${this_script_path}/${update_script}"
}

upgrade () {
	latest_version=$($m_curl -s --compressed -k "$sh_github" 2>&1 | grep "^script_version=" | head -n1 | cut -d '"' -f 2)
	local current_version=$(grep "^script_version=" "${cron_script_full_path}" | head -n1 | cut -d '"' -f 2)
	changelog_p=$($m_curl -s --compressed -k "$changelog_github" 2>&1 | $m_sed -n "/$latest_version/,/$current_version/p" 2>/dev/null | head -n -2)

	if [[ "${latest_version}" && "${current_version}" ]]; then
		if [[ "${latest_version//./}" -gt "${current_version//./}" ]]; then
			if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
				echo -e "\n${green}*${reset} ${green}NEW UPDATE FOUND!${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo -e "${magenta}$changelog_p${reset}\n" | $m_sed 's/^/  /'
				while true; do
					read -r -n 1 -p "${m_tab}${BC}Do you want to update version $latest_version? --> (Y)es | (N)o${EC} " yn < /dev/tty
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
		else
			echo -e "\n${yellow}*${reset} ${yellow}There is no update!${reset}"
			echo -e "${cyan}${m_tab}#####################################################${reset}\n"
			echo "$(timestamp): Update process started: there is no new update." >> "${wooaras_log}"
		fi

		if [ "${latest_version//./}" -eq "${current_version//./}" ]; then
			if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
				while true; do
					read -r -n 1 -p "${m_tab}${BC}Do you want to force update version $latest_version? --> (Y)es | (N)o${EC} " yn < /dev/tty
					echo ""
					case "${yn}" in
						[Yy]* ) f_update=1; download; break;;
						[Nn]* ) exit 1;;
						* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
					esac
				done
			fi
		fi
	else
		echo -e "\n${red}*${reset} ${red}Upgrade failed! Could not find upgrade content${reset}"
		echo -e "${cyan}${m_tab}#####################################################${reset}\n"
		echo "$(timestamp): Upgrade failed. Could not find upgrade content" >> "${wooaras_log}"
		send_mail "Upgrade failed. Could not find upgrade content"
	fi
}

while :; do
	case "${1}" in
	-s|--setup	      ) on_fly_enable
				break
				;;
	-S|--status	      ) my_status
				exit
				;;
	-t|--twoway-enable    ) twoway_enable
				exit
				;;
	-y|--twoway-disable   ) twoway_disable
				exit
				;;
	-i|--disable          ) disable
				exit
				;;
	-a|--enable	      ) enable
				exit
				;;
	-u|--upgrade          ) upgrade
				exit
				;;
	-d|--uninstall        ) un_install
				exit
				;;
	*                     ) break;;
	esac
	shift
done

# Installation
#=====================================================================
add_cron () {
	if [[ ! -e "${cron_dir}/${cron_filename}" ]]; then
		if [[ ! -d "${cron_dir}" ]]; then
			mkdir "${cron_dir}" >/dev/null 2>&1 &&
			touch "${cron_dir}/${cron_filename}" >/dev/null 2>&1 ||
			{
			echo -e "\n${red}*${reset} Cron install aborted, cannot create directory ${cron_dir}"
			echo -e "${cyan}${m_tab}#####################################################${reset}\n"
			echo "$(timestamp): Installation aborted, as cannot create directory ${cron_dir}" >> "${wooaras_log}"
			exit 1
			}
		else
			touch "${cron_dir}/${cron_filename}" >/dev/null 2>&1 ||
			{
                        echo -e "\n${red}*${reset} Cron install aborted, cannot create ${cron_dir}/${cron_filename}"
			echo -e "${cyan}${m_tab}#####################################################${reset}\n"
                        echo "$(timestamp): SETUP: could not create cron ${cron_filename}" >> "${wooaras_log}"
                        exit 1
                        }
		fi
	fi

	if [[ ! -w "${cron_dir}/${cron_filename}" ]]; then
		echo -e "\n${red}*${reset} Cron install aborted, as file not writable: ${cron_dir}/${cron_filename}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
		echo "$(timestamp): SETUP: Cron install aborted, as file not writable: ${cron_dir}/${cron_filename}." >> "${wooaras_log}"
		exit 1
	else
		if [[ "${auto_update}" -eq 1 ]]; then
			cat <<- EOF > "${cron_dir}/${cron_filename_update}"
			# At 09:19 on Sunday.
			# Via WooCommerce - ARAS Cargo Integration Script
			# Copyright 2021 Hasan ÇALIŞIR
			# MAILTO=$mail_to
			SHELL=/bin/bash
			$cron_minute_update ${cron_user} [ -x ${cron_script_full_path} ] && ${my_bash} ${cron_script_full_path} -u
			EOF
                fi

		cat <<- EOF > "${cron_dir}/${cron_filename}"
		# At every 24th minute past every hour from 9 through 19 on every day-of-week from Monday through Saturday.
		# Via WooCommerce - ARAS Cargo Integration Script
		# Copyright 2021 Hasan ÇALIŞIR
		# MAILTO=$mail_to
		SHELL=/bin/bash
		$cron_minute ${cron_user} [ -x ${cron_script_full_path} ] && ${my_bash} ${cron_script_full_path}
		EOF

		result=$?
		if [[ "${result}" -eq 0 ]]; then
			# Install systemd_tmpfiles
			systemd_tmpfiles

			# Add logrotate
			add_logrotate

			# Drop ownership of script & script path & log file to sudo user
			[[ $SUDO_USER ]] && { chown "${user}":"${user}" "${cron_script_full_path}"; chown "${user}":"${user}" "${this_script_path}"; chown "${user}":"${user}" "${wooaras_log}"; }

			# Set status
			on_fly_disable

			echo -e "\n${green}*${reset} ${green}Installation completed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			if [[ "${auto_update}" -eq 1 ]]; then
				echo "${m_tab}${green}Main cron installed to ${cyan}${cron_dir}/${cron_filename}${reset}${reset}"
				echo "${m_tab}${green}Updater cron installed to ${cyan}${cron_dir}/${cron_filename_update}${reset}${reset}"
			else
				echo "${m_tab}${green}Main cron installed to ${cyan}${cron_dir}/${cron_filename}${reset}${reset}"
			fi
			if [[ "${logrotate_installed}" ]]; then
				if [[ "${logrotate_installed}" == "asfile" ]]; then
					echo "${m_tab}${green}Logrotate installed to ${cyan}${logrotate_dir}/${logrotate_filename}${reset}"
				elif [[ "${logrotate_installed}" == "conf" ]]; then
					echo "${m_tab}${green}Logrotate rules inserted to ${cyan}${logrotate_conf}${reset}"
				fi
			fi
			if [[ "${tmpfiles_installed}" ]]; then
				if [[ "{$tmpfiles_installed}" == "systemd" ]]; then
					echo -e "${m_tab}${green}Runtime path deployed via ${cyan}${tmpfiles_d}/${tmpfiles_f}${reset}\n"
				elif [[ "${tmpfiles_installed}" == "rclocal" ]]; then
					echo -e "${m_tab}${green}Runtime path deployed via ${cyan}/etc/rc.local${reset}\n"
				fi
			fi
			echo "$(timestamp): Installation completed." >> "${wooaras_log}"
		else
			echo -e "\n${red}*${reset} ${red}Installation failed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Could not create cron {cron_dir}/${cron_filename}.${reset}\n"
			echo "$(timestamp): Installation failed, could not create cron {cron_dir}/${cron_filename}" >> "${wooaras_log}"
			exit 1
		fi
	fi
	exit 0
}

add_systemd () {
	[[ -d "/etc/systemd/system" ]] &&
	{
	touch "${systemd_dir}/${service_filename}" 2>/dev/null
	touch "${systemd_dir}/${timer_filename}" 2>/dev/null
	}

	if [[ ! -w "${systemd_dir}/${service_filename}" ]]; then
		echo -e "\n${red}*${reset} ${red}Systemd install aborted, as file not writable:${reset} ${green}${systemd_dir}/${service_filename}${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
		echo "$(timestamp): Systemd install aborted, as file not writable: ${systemd_dir}/${service_filename}" >> "${wooaras_log}"
		exit 1
	else
		cat <<- EOF > "${systemd_dir}/${service_filename}"
		[Unit]
		Description=woocommerce aras cargo integration script.
		RequiresMountsFor=/var/log

		[Service]
		Type=oneshot
		User=${systemd_user}
		Group=${systemd_user}
		RuntimeDirectory=woo-aras
		LogsDirectory=woo-aras
		LogsDirectoryMode=0775
		RuntimeDirectoryMode=0775
		RuntimeDirectoryPreserve=yes
		Environment=RUNNING_FROM_SYSTEMD=1
		ExecStart=${my_bash} ${systemd_script_full_path}

		[Install]
		WantedBy=multi-user.target
		EOF

		cat <<- EOF > "${systemd_dir}/${timer_filename}"
		[Unit]
		Description=woocommerce-aras timer - At every 30th minute past every hour from 9AM through 20PM expect Sunday
		Requires=network-online.target

		[Timer]
		OnCalendar=${on_calendar}
		Persistent=true
		Unit=${service_filename}

		[Install]
		WantedBy=timers.target
		EOF

		systemctl daemon-reload >/dev/null 2>&1 &&
		systemctl enable "${timer_filename}" >/dev/null 2>&1 &&
		systemctl start "${timer_filename}" >/dev/null 2>&1
		result=$?

		if [[ "${result}" -eq 0 ]]; then
			if [[ ! -e "${cron_dir}/${cron_filename_update}" ]]; then
				mkdir -p "$cron_dir" /dev/null 2>&1
				touch "${cron_dir}/${cron_filename_update}" /dev/null 2>&1 ||
				{ echo "could not create cron ${cron_filename_update}";  echo "$(timestamp): SETUP: could not create cron ${cron_filename_update}" >> "${wooaras_log}";  exit 1; }
			fi

			if [[ ! -w "${cron_dir}/${cron_filename_update}" ]]; then
				echo -e "\n${red}*${reset} ${red}Updater cron install aborted, as file not writable: ${cron_dir}/${cron_filename_update}${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Installation aborted, as file not writable: ${cron_dir}/${cron_filename_update}." >> "${wooaras_log}"
				exit 1
			else
				if [[ "${auto_update}" -eq 1 ]]; then
					cat <<- EOF > "${cron_dir}/${cron_filename_update}"
					# At 09:19 on Sunday.
					# Via WooCommerce - ARAS Cargo Integration Script
					# Copyright 2021 Hasan ÇALIŞIR
					# MAILTO=$mail_to
					SHELL=/bin/bash
					$cron_minute_update ${cron_user} [ -x ${cron_script_full_path} ] && ${my_bash} ${cron_script_full_path} -u
					EOF

					result=$?
					if [[ "${result}" -eq 0 ]]; then
						# Add logrotate
						add_logrotate

						# Take ownership of script & path
						[[ $SUDO_USER ]] && { chown "${user}":"${user}" "${cron_script_full_path}"; chown "${user}":"${user}" "${this_script_path}"; chown "${user}":"${user}" "${wooaras_log}"; }

						# Set status
						on_fly_disable
					else
						echo -e "\n${red}*${reset} ${green}Installation failed.${reset}"
						echo "${cyan}${m_tab}#####################################################${reset}"
						echo "${m_tab}${red}Could not create updater cron {cron_dir}/${cron_filename_update}.${reset}"
						echo "$(timestamp): Installation failed, could not create cron {cron_dir}/${cron_filename_update}" >> "${wooaras_log}"
						exit 1
					fi
				fi
			fi

			echo -e "\n${green}*${reset} ${green}Installation completed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${green}Systemd service installed to ${cyan}${systemd_dir}/${service_filename}${reset}"
			echo "${m_tab}${green}Systemd service timer installed to ${cyan}${systemd_dir}/${timer_filename}${reset}"
			if [[ "${auto_update}" -eq 1 ]]; then
				echo "${m_tab}${green}Timer service enabled and started.${reset}"
				echo "${m_tab}${green}Updater cron installed to ${cyan}${cron_dir}/${cron_filename_update}${reset}${reset}"
			else
				echo "${m_tab}${green}Timer service enabled and started.${reset}"
			fi
			if [[ "${logrotate_installed}" ]]; then
				if [[ "${logrotate_installed}" == "asfile" ]]; then
					echo -e "${m_tab}${green}Logrotate installed to ${cyan}${logrotate_dir}/${logrotate_filename}${reset}\n"
				elif [[ "${logrotate_installed}" == "conf" ]]; then
					echo -e "${m_tab}${green}Logrotate rules inserted to ${cyan}${logrotate_conf}${reset}\n"
				fi
			fi
			echo "$(timestamp): Installation completed." >> "${wooaras_log}"
		else
			echo -e "\n${red}*${reset} ${red}Installation failed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Cannot enable/start ${timer_filename} systemd service.${reset}\n"
			echo "$(timestamp): Installation failed, cannot start ${timer_filename} service." >> "${wooaras_log}"
			exit 1
		fi
	fi
	exit 0
}

# Keeping log size small is important for performance
add_logrotate () {
	if grep -qFx "include ${logrotate_dir}" "${logrotate_conf}"; then
		if [[ ! -e "${logrotate_dir}/${logrotate_filename}" ]]; then
			if [[ ! -w "${logrotate_dir}" ]]; then
				echo -e "\n${red}*${reset} ${red}Installation aborted, as folder not writeable: $logrotate_dir${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo -e "${m_tab}${yellow}You can run script as root or execute with sudo.${reset}\n"
				echo "$(timestamp): Installation aborted, as folder not writeable: ${logrotate_dir}" >> "${wooaras_log}"
				exit 1
			else
				logrotate_installed="asfile"
				cat <<- EOF > "${logrotate_dir}/${logrotate_filename}"
				${wooaras_log} {
				prerotate
				${cron_script_full_path} --rotate >/dev/null 2>&1
				exit \$?
				endscript
				daily
				rotate 10000000000
				size ${l_maxsize}
				compress
				create 0660 ${user} ${user}
				postrotate
				/bin/kill -HUP \`cat ${PIDFILE}\` 2>/dev/null || true
				echo "\$(date +"%Y-%m-%d %T"): Logrotation completed" >> ${wooaras_log}
				endscript
				}
				EOF
			fi
		fi
	elif ! grep -q "ARAS Cargo" "${logrotate_conf}"; then
		if [[ ! -w "${logrotate_conf}" ]]; then
			echo -e "\n${red}*${reset} ${red}Installation aborted, as file not writeable: ${logrotate_conf}${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}You can run script as root or execute with sudo.${reset}\n"
			echo "$(timestamp): Installation aborted, as file not writeable: ${logrotate_conf}" >> "${wooaras_log}"
			exit 1
		else
			logrotate_installed="conf"
			cat <<- EOF >> "${logrotate_conf}"

			# Via WooCommerce - ARAS Cargo Integration Script
			# Copyright 2021 Hasan ÇALIŞIR
			${wooaras_log} {
			prerotate
			${cron_script_full_path} --rotate >/dev/null 2>&1
			exit \$?
			endscript
			daily
			rotate 10000000000
			size ${l_maxsize}
			compress
			create 0660 ${user} ${user}
			postrotate
			/bin/kill -HUP \`cat ${PIDFILE}\` 2>/dev/null || true
			echo "\$(date +"%Y-%m-%d %T"): Logrotation completed" >> ${wooaras_log}
			endscript
			# END-WOOARAS
			}
			EOF
		fi
	fi
}

systemd_tmpfiles () {
	if systemctl is-active --quiet "systemd-tmpfiles-setup.service"; then
		if [[ ! -e "${tmpfiles_d}/${tmpfiles_f}" ]]; then
			if [[ ! -w "${tmpfiles_d}" ]]; then
				echo -e "\n${red}*${reset} ${red}Installation aborted, as folder not writable: ${tmpfiles_d}${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
				echo "$(timestamp): Installation aborted, as folder not writable: ${tmpfiles_d}" >> "${wooaras_log}"
				exit 1
			else
				cat <<- EOF > "${tmpfiles_d}/${tmpfiles_f}"
				d ${runtime_path%/*} 0755 $user $user
				d ${wooaras_log%/*} 0755 $user $user
				EOF

				result=$?
				if [[ "${result}" -eq 0 ]]; then
					tmpfiles_installed="systemd"
				else
					echo -e "\n${red}*${reset} ${red}Installation aborted, as file not writable: ${tmpfiles_d}/${tmpfiles_f}${reset}"
					echo "${cyan}${m_tab}#####################################################${reset}"
					echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
					echo "$(timestamp): Installation aborted, as file not writable: ${tmpfiles_d}/${tmpfiles_f}" >> "${wooaras_log}"
					exit 1
				fi
			fi
		fi
	elif systemctl is-active --quiet "rc-local.service"; then
		if [[ ! -w "/etc/rc.local" ]]; then
			echo -e "\n${red}*${reset} ${red}Installation aborted, as file not writable: /etc/rc.local${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo -e "${m_tab}${red}Try to run script as root or execute script with sudo.${reset}\n"
			echo "$(timestamp): Installation aborted, as file not writable: /etc/rc.local" >> "${wooaras_log}"
			exit 1
		elif ! grep -q "woo-aras" "/etc/rc.local"; then
			sed -i \
				-e '$i \mkdir -p '"${runtime_path%/*}"' && chown '"${user}:${user}"' '"${runtime_path%/*}"'' \
				-e '$i \mkdir -p '"${wooaras_log%/*}"' && chown '"${user}:${user}"' '"${wooaras_log%/*}"'' \
				"/etc/rc.local" && tmpfiles_installed="rclocal" || { echo "Installation failed, as sed failed"; exit 1; }
		fi
	fi
}
#=====================================================================

# WooCommerce REST & ARAS SOAP encryption/decryption operations
#=====================================================================

# Check -s argument
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

# Check uncompleted setup
if [[ "$1" != "-s" && "$1" != "--setup" ]]; then
	if [[ "$(ls -1q ${this_script_path}/.*lck 2>/dev/null | wc -l)" -eq 8 ]]; then
		if [[ ! -e "${this_script_path}/.woo.aras.set" ]]; then
			echo -e "\n${yellow}*${reset} ${yellow}The previous installation was not completed.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${yellow}We will continue the installation.${reset}"
			echo "${m_tab}${yellow}If you encounter any problem please use${reset}"
			echo "${m_tab}${yellow}-s argument for hard reset/restart the installation.${reset}"
			help

			read -n 1 -s -r -p "${green}>  Press any key to continue, q for quit${reset}" reply < /dev/tty; echo
			if [[ "${reply}" == "q" ]]; then
				echo
				exit 0
			fi
		fi
	fi
fi

encrypt_ops_exit () {
	send_mail "Woocommerce-Aras Cargo integration error, missing file ${1}, please re-start setup"
	echo "$(timestamp): Woocommerce-Aras Cargo integration error, missing file ${1}, please re-start setup" >> "${wooaras_log}"
	exit 1
}

encrypt_wc_auth () {
	hide_me --enable
	if [[ ! -s "${this_script_path}/.key.wc.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your woocommerce api_key, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -r -p "${m_tab}${BC}Enter WooCommerce API key:${EC} " my_wc_api_key < /dev/tty
			if [[ "${my_wc_api_key}" == "q" || "${my_wc_api_key}" == "quit" ]]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${my_wc_api_key}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.key.wc.lck"
		else
			encrypt_ops_exit "${this_script_path}/.key.wc.lck"
		fi
	fi
	if [[ ! -s "${this_script_path}/.secret.wc.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your woocommerce api_secret, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -r -p "${m_tab}${BC}Enter WooCommerce API secret:${EC} " my_wc_api_secret < /dev/tty
			if [[ "${my_wc_api_secret}" == "q" || "${my_wc_api_secret}" == "quit" ]]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${my_wc_api_secret}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.secret.wc.lck"
		else
			encrypt_ops_exit "${this_script_path}/.secret.wc.lck"
		fi
	fi
	hide_me --disable
}

encrypt_wc_end () {
	hide_me --enable
	if [[ ! -s "${this_script_path}/.end.wc.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your Wordpress installation url, type q for quit${reset}"
			echo -e "${m_tab}${magenta}format --> www.example.com | www.example.com/wordpress.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -r -p "${m_tab}${BC}Enter Wordpress Domain URL:${EC} " my_wc_api_endpoint < /dev/tty
			if [[ "${my_wc_api_endpoint}" == "q" || "${my_wc_api_endpoint}" == "quit" ]]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${my_wc_api_endpoint}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.end.wc.lck"
		else
			encrypt_ops_exit "${this_script_path}/.end.wc.lck"
		fi
	fi
	hide_me --disable
}

encrypt_aras_auth () {
	hide_me --enable
	if [[ ! -s "${this_script_path}/.key.aras.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP api_key, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -r -p "${m_tab}${BC}Enter ARAS SOAP API Password:${EC} " my_aras_api_pass < /dev/tty
			if [[ "${my_aras_api_pass}" == "q" || "${my_aras_api_pass}" == "quit" ]]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${my_aras_api_pass}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.key.aras.lck"
		else
			encrypt_ops_exit "${this_script_path}/.end.wc.lck"
		fi
	fi
	if [[ ! -s "${this_script_path}/.usr.aras.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP api_username, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -r -p "${m_tab}${BC}Enter ARAS SOAP API Username:${EC} " my_aras_api_usr < /dev/tty
			if [[ "${my_aras_api_usr}" == "q" || "${my_aras_api_usr}" == "quit" ]]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${my_aras_api_usr}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.usr.aras.lck"
		else
			encrypt_ops_exit "${this_script_path}/.usr.aras.lck"
		fi
	fi
	if [[ ! -s "${this_script_path}/.mrc.aras.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			while true; do
				echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP merchant_code, type q for quit${reset}"
				echo "${cyan}${m_tab}#####################################################${reset}"
				read -r -p "${m_tab}${BC}Enter ARAS SOAP Merchant Code:${EC} " my_aras_api_mrc < /dev/tty
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo ""
				case "${my_aras_api_mrc}" in
					q) exit 1;;
					''|*[!0-9]*) echo "${yellow}*${reset} ${yellow}Only numbers are allowed.${reset}";;
					*) break;;
				esac
			done
			echo "${my_aras_api_mrc}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.mrc.aras.lck"
		else
			encrypt_ops_exit "${this_script_path}/.mrc.aras.lck"
		fi
	fi
	hide_me --disable
}

encrypt_aras_end () {
	hide_me --enable
	if [[ ! -s "${this_script_path}/.end.aras.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP endpoint_url, type q for quit${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			read -r -p "${m_tab}${BC}Enter ARAS SOAP endpoint URL (wsdl):${EC} " my_aras_api_end < /dev/tty
			if [[ "${my_aras_api_end}" == "q" || "${my_aras_api_end}" == "quit" ]]; then exit 1; fi
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${my_aras_api_end}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.end.aras.lck"
		else
			encrypt_ops_exit "${this_script_path}/.end.aras.lck"
		fi
	fi
	hide_me --disable
}

encrypt_aras_qry () {
	hide_me --enable
	if [[ ! -s "${this_script_path}/.qry.aras.lck" ]]; then
		if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
			echo -e "\n${green}*${reset} ${magenta}Setting your ARAS SOAP query_type.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			while true; do
				read -r -p "${m_tab}${BC}Enter ARAS SOAP query type:${EC} " my_aras_api_qry < /dev/tty
				case "${my_aras_api_qry}" in
					12) break;;
					13) break;;
				 	q) exit 1; break;;
					*) echo "${m_tab}${red}Only query type 12,13 supported. Type 'q' for exit ${reset}" ;;
				esac
			done
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${my_aras_api_qry}" | openssl enc -base64 -e -aes-256-cbc -nosalt  -pass pass:garbageKey  2>/dev/null > "${this_script_path}/.qry.aras.lck"
		else
			encrypt_ops_exit "${this_script_path}/.qry.aras.lck"
		fi
	fi
	hide_me --disable
}

encrypt_wc_auth && encrypt_wc_end && encrypt_aras_auth && encrypt_aras_end && encrypt_aras_qry ||
{
echo -e "\n${red}*${reset} ${red}Encrypt Error: ${reset}";
echo -e "${cyan}${m_tab}#####################################################${reset}\n";
echo "$(timestamp): Encrypt error." >> "${wooaras_log}";
exit 1;
}

# decrypt ARAS SOAP API credentials
decrypt_aras_auth () {
	hide_me --enable
	api_key_aras=$(< "${this_script_path}/.key.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	api_usr_aras=$(< "${this_script_path}/.usr.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	api_mrc_aras=$(< "${this_script_path}/.mrc.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	hide_me --disable
}
decrypt_aras_end () {
	hide_me --enable
	api_end_aras=$(< "${this_script_path}/.end.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	hide_me --disable
}
api_qry_aras=$(< "${this_script_path}/.qry.aras.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)

# decrypt WooCommerce API credentials
decrypt_wc_auth () {
	hide_me --enable
	api_key=$(< "${this_script_path}/.key.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	api_secret=$(< "${this_script_path}/.secret.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	hide_me --disable
}
decrypt_wc_end () {
	hide_me --enable
	api_endpoint=$(< "${this_script_path}/.end.wc.lck" openssl enc -base64 -d -aes-256-cbc -nosalt -pass pass:garbageKey 2>/dev/null)
	hide_me --disable
}

decrypt_aras_auth && decrypt_aras_end && decrypt_wc_auth && decrypt_wc_end ||
{
echo -e "\n${red}*${reset} ${red}Decrypt Error: ${reset}";
echo -e "${cyan}${m_tab}#####################################################${reset}\n";
echo "$(timestamp): Decrypt error." >> "${wooaras_log}";
exit 1;
}

# Write out the current history(memory) to the history file
history -w

# Double check any sensetive data written to history
if [[ "${HISTFILE}" ]]; then
	declare -a lock_files=(".key.wc.lck" ".secret.wc.lck" ".end.wc.lck" ".key.aras.lck" ".usr.aras.lck" ".mrc.aras.lck" ".end.aras.lck" ".qry.aras.lck")
	for i in "${lock_files[@]}"
	do
		$m_sed -i "/$i/d" "${HISTFILE}" >/dev/null 2>&1
	done
fi
#=====================================================================

# Controls
#=====================================================================
# Pre-defined curl functions for various tests
w_curl_s () {
	$m_curl -X GET -H "Content-Type: application/json" "https://$api_endpoint/wp-json/wc/v3/settings" > "${this_script_path}/curl.proc" 2>&1
}

w_curl_a () {
	$m_curl -X GET \
		-u "$api_key":"$api_secret" \
		-H "Content-Type: application/json" \
		"https://$api_endpoint/wp-json/wc/v3/settings" > "${this_script_path}/curl.proc" 2>&1
}

control_ops_exit () {
	send_mail "${1}"
        echo "$(timestamp): ${1}" >> "${wooaras_log}"
        exit 1

}

control_ops_try_exit () {
	echo -e "\n${red}>${m_tab}${1}${reset}\n"
	echo "$(timestamp): ${1}" >> "${wooaras_log}"
	exit 1
}

# Test host connection
w_curl_a
if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
	try=0
	while grep -q "Could not resolve host" "${this_script_path}/curl.proc"
	do
		try=$((try+1))
		[[ $try -eq 3 ]] && control_ops_try_exit "Too many bad try, could not resolve host $api_endpoint"
		echo ""
		echo -e "\n${red}*${reset} ${red}Connection error, could not resolve host${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo  "${m_tab}${red}Check your Wordpress domain ${magenta}$api_endpoint${reset}"
		echo "$(timestamp): Connection error, could not resolve host $api_endpoint" >> "${wooaras_log}"
		while true
		do
			echo -e "\n${m_tab}${cyan}##################################################################${reset}"
			read -r -n 1 -p "${m_tab}${BC}Do you want to reset your Wordpress domain now? --> (Y)es | (N)o${EC} " yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -rf "${this_script_path:?}/.end.wc.lck";
					encrypt_wc_end;
					decrypt_wc_end;
					w_curl_a; break;;
				[Nn]* ) exit 1;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
			esac
		done
	done
elif grep -q "Could not resolve host" "${this_script_path}/curl.proc"; then
	control_ops_exit "Connection error, could not resolve host $api_endpoint!"
fi

# Test WooCommerce REST API
if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
	if grep -q  "404\|400" "${this_script_path}/curl.proc"; then
		echo -e "\n${red}*${reset}${red} WooCommerce REST API connection error${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Check WooCommerce REST API enabled${reset}\n"
		echo "$(timestamp): WooCommerce REST API connection error, check WooCommerce REST API enabled." >> "${wooaras_log}"
		exit 1
	fi
elif grep -q  "404\|400" "${this_script_path}/curl.proc"; then
	control_ops_exit "WooCommerce REST API connection error, check WooCommerce REST API enabled."
fi

# Test WooCommerce REST API Authorization
if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
	if grep -q "403" "${this_script_path}/curl.proc"; then
		echo -e "\n${red}*${reset}${red} WooCommerce REST API Authorization error${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Could not connect destination from $my_ip.${reset}"
		echo "${m_tab}${red}Check your firewall settings and webserver restrictions.${reset}"
		echo -e "${m_tab}${red}Give allow to $my_ip on your end and restart setup.${reset}\n"
		echo "$(timestamp): WooCommerce REST API Authorization error, could not connect destination from $my_ip." >> "${wooaras_log}"
		exit 1
	fi
elif grep -q "403" "${this_script_path}/curl.proc"; then
	control_ops_exit "WooCommerce REST API Authorization error, could not connect destination from $my_ip"
fi

# Test WooCommerce REST API Authentication
if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
	try=0
	while grep -q "woocommerce_rest_authentication_error\|woocommerce_rest_cannot_view\|401" "${this_script_path}/curl.proc"
	do
		try=$((try+1))
		[[ $try -eq 3 ]] && control_ops_try_exit "Too many bad try, could not connect WooCommerce REST API"
		echo -e "\n${red}*${reset} ${red}WooCommerce REST API Authentication error${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Check your WooCommerce REST API credentials${reset}\n"
		echo "$(timestamp): WooCommerce REST API Authentication error, check your WooCommerce REST API credentials." >> "${wooaras_log}"
		while true
		do
			echo "${m_tab}${cyan}###########################################################################${reset}"
			read -r -n 1 -p "${m_tab}${BC}Do you want to reset your WooCommerce REST API credentials now? --> (Y)es | (N)o${EC} " yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -rf "${this_script_path:?}/.key.wc.lck" "${this_script_path:?}/.secret.wc.lck";
					encrypt_wc_auth;
					decrypt_wc_auth;
					w_curl_a; break;;
				[Nn]* ) exit 1;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
			esac
		done
	done
elif grep -q "woocommerce_rest_authentication_error\|woocommerce_rest_cannot_view\|401" "${this_script_path}/curl.proc"; then
	control_ops_exit "WooCommerce REST API Authentication error, check your WooCommerce REST API credentials."
fi

# After successful curl respond with credentials we send a new curl request without credentials
# CRITICAL: Throwing in error? Caching json requests!
# If you have server side caching setup like fastcgi cache skip caching json requests
w_curl_s
if ! grep -q "401" "${this_script_path}/curl.proc"; then
        echo -e "\n${red}*${reset}${red} You are caching wp-json request !${reset}"
        echo "${cyan}${m_tab}#####################################################${reset}"
        echo "${m_tab}${red}Deadly security vulnerability detected.${reset}"
        echo "${m_tab}${red}Check your wordpress caching plugin configuration and be sure wp-json exluded.${reset}"
        echo "${m_tab}${red}If you have server side caching setup,${reset}"
	echo -e "${m_tab}${red}like fastcgi cache skip caching json requests.${reset}\n"
	echo "$(timestamp): CRITICAL: You are caching wp-json requests, check your wordpress caching plugin configuration and be sure wp-json exluded" >> "${wooaras_log}"
	exit 1
fi

hide_me --enable
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
hide_me --disable

# Make SOAP request to ARAS web service to get shipment DATA in JSON format
# We will request last 10 day data as setted before
aras_request () {
	$m_php "${this_script_path}/aras_request.php" > "${this_script_path}/aras.json"
}

# Test Aras SOAP Endpoint
aras_request
if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
	try=0
	while grep -q "error_4625264224" "${this_script_path}/aras.json"
	do
		try=$((try+1))
		[[ $try -eq 3 ]] && control_ops_try_exit "Too many bad try, could not connect ARAS SOAP API."
		echo ""
		echo -e "\n${red}*${reset} ${red}ARAS SOAP API connection error${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo "${m_tab}${red}Check your ARAS SOAP API endpoint URL${reset}"
		echo -e "${m_tab}${magenta}$api_end_aras${reset}\n"
		echo "$(timestamp): ARAS SOAP API connection error, check your ARAS SOAP API endpoint URL." >> "${wooaras_log}"
		while true
		do
			echo "${m_tab}${cyan}###########################################################################${reset}"
			read -r -n 1 -p "${m_tab}${BC}Do you want to reset your ARAS SOAP endpoint URL now? --> (Y)es | (N)o${EC}" yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -f "${this_script_path}/.end.aras.lck";
					encrypt_aras_end;
					decrypt_aras_end;
					$m_sed -i -z 's!([^(]*,!("'"$api_end_aras"'",!' "${this_script_path}/aras_request.php";
					aras_request; break;;
				[Nn]* ) exit 1;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${m_tab}${cyan}###########################################################################${reset}";;
			esac
		done
	done
elif grep -q "error_4625264224" "${this_script_path}/aras.json"; then
	control_ops_exit "ARAS SOAP API connection error, check your ARAS SOAP API endpoint URL."
fi

# Test Aras SOAP Authentication
if [[ "${RUNNING_FROM_CRON}" -eq 0 && "${RUNNING_FROM_SYSTEMD}" -eq 0 ]]; then
	try=0
	while grep -q "error_75546475052" "${this_script_path}/aras.json"
	do
		try=$((try+1))
		[[ "${try}" -eq 3 ]] && control_ops_try_exit "Too many bad try, could not connect ARAS SOAP API."
		echo ""
                echo -e "\n${red}*${reset} ${red}ARAS SOAP API Authentication error${reset}"
                echo "${cyan}${m_tab}#####################################################${reset}"
                echo -e "${m_tab}${red}Check your ARAS SOAP API credentials${reset}\n"
		echo "$(timestamp): ARAS SOAP API Authentication error, check your ARAS SOAP API credentials" >> "${wooaras_log}"
		while true
		do
			echo "${m_tab}${cyan}###########################################################################${reset}"
			read -r -n 1 -p "${m_tab}${BC}Do you want to reset your ARAS SOAP API credentials now? --> (Y)es | (N)o${EC}" yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) rm -rf "${this_script_path:?}/.key.aras.lck" "${this_script_path:?}/.usr.aras.lck" "${this_script_path:?}/.mrc.aras.lck";
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
elif grep -q "error_75546475052" "${this_script_path}/aras.json"; then
		control_ops_exit "ARAS SOAP API Authentication error, check your ARAS SOAP API credentials"
fi

# disabled trap clean_up may expose credentials so delete file immediately
rm -f "${this_script_path:?}/aras_request.php"
# END CONTROLS
#=====================================================================

# Passed all controls, time to call INSTALLATION functions
# Also validate the data that parsed by script.
# If ARAS data is empty first check 'merchant code' which not return any error from ARAS SOAP end
if [[ $RUNNING_FROM_CRON -eq 0 ]] && [[ $RUNNING_FROM_SYSTEMD -eq 0 ]]; then
	if [[ ! -e "${this_script_path}/.woo.aras.set" ]]; then
		pre_check
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
		if [[ "${data_test}" == "[]" ]]; then
			echo -e "\n${red}*${reset} ${red}Couldn't find any woocommerce order data to validate.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}You can simply create a test order if throw in error here.${reset}"
			echo -e "${m_tab}${red}Without data validation by user we cannot go for production.${reset}\n"
			echo "$(timestamp): Couldn't find any woocommerce order data to validate. You can simply create a test order." >> "${wooaras_log}"
			exit 1
		else
			echo -e "${m_tab}${green}Done${reset}"
			echo -e "\n${green}${m_tab}Please validate Order_ID & Customer_Info.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			column -t -s' ' <<< $(echo "$data_test" | $m_jq -r '.[]|[.id,.shipping.first_name,.shipping.last_name]|join(" ")' |
				iconv -f utf8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' |
				$m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= |
				$m_sed '1i Order_ID Customer_Name' | $m_sed '2i --------------- -------------') | $m_sed 's/^/  /'
			while true
 			do
				echo "${m_tab}${cyan}#####################################################${reset}"
				read -r -n 1 -p "${m_tab}${BC}Is data correct? --> (Y)es | (N)o${EC} " yn < /dev/tty
				echo ""
				case "${yn}" in
					[Yy]* ) break;;
					[Nn]* ) exit 1;;
					* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}";;
				esac
			done
		fi

		if [ -s "${this_script_path}/aras.json" ]; then
			< "${this_script_path}/aras.json" $m_sed 's/^[^[]*://g' | $m_awk 'BEGIN{OFS=FS="]"};{$NF="";print $0}' > "${this_script_path}/aras.json.mod" || { echo 'cannot modify aras.json'; exit 1; }
		fi

		if grep "null" "${this_script_path}/aras.json.mod"; then
			echo -e "\n${red}*${reset} ${red}Couldn't find any ARAS cargo data to validate${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			echo "${m_tab}${red}You can try to set 'start_date' 'end_date' for long time span.${reset}"
			echo -e "${m_tab}${red}Unable to continue without verifying the data.${reset}\n"
			echo "$(timestamp): Couldn't find any ARAS cargo data to validate" >> "${wooaras_log}"
			exit 1
		else
			echo -e "\n${green}${m_tab}Please validate Tracking_Number & Customer_Info.${reset}"
			echo "${cyan}${m_tab}#####################################################${reset}"
			column -t -s' ' <<< $(< "${this_script_path}/aras.json.mod" $m_jq -r '.[]|[.DURUM_KODU,.KARGO_TAKIP_NO,.ALICI]|join(" ")' |
				cut -f2- -d ' ' | iconv -f utf8 -t ascii//TRANSLIT | tr '[:upper:]' '[:lower:]' |
				$m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= |
				$m_sed '1i Tracking_Number Customer_Name' | $m_sed '2i --------------- -------------' |
				$m_sed '8,$d') | $m_sed 's/^/  /'
			while true
			do
				echo "${m_tab}${cyan}#####################################################${reset}"
				read -r -n 1 -p "${m_tab}${BC}Is data correct? --> (Y)es | (N)o${EC} " yn < /dev/tty
				echo ""
				case "${yn}" in
					[Yy]* ) break;;
					[Nn]* ) exit 1;;
					* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}";;
				esac
			done
		fi

		echo -e "\n${green}*${reset} ${green}Please set auto update preference${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"

		# Auto upgrade cronjob
		while true
		do
			read -r -n 1 -p "${m_tab}${BC}Script automatically update itself? --> (Y)es | (N)o${EC} " yn < /dev/tty
			echo ""
			case "${yn}" in
				[Yy]* ) auto_update=1; break;;
				[Nn]* ) auto_update=0; break;;
				* ) echo -e "\n${m_tab}${magenta}Please answer yes or no.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
			esac
		done

		# Add IMMUTABLE to critical files
		for i in "${this_script_path}"/.*lck
		do
			chattr +i "$i" >/dev/null 2>&1
		done

		echo -e "\n${green}*${reset} ${green}Default setup completed.${reset}"
		# Forward to twoway installation
		if [[ "${twoway}" ]]; then
			if [[ "${twoway}" == "true" ]]; then
				echo "${cyan}${m_tab}#####################################################${reset}"
				echo "${m_tab}${green}Installing two way fulfillment workflow...${reset}"
				install_twoway
				echo -e "\n${m_tab}${green}Please select your job schedule method.${reset}"
			else
				echo -e "${cyan}${m_tab}#####################################################${reset}\n"
				echo "${m_tab}${green}Please select your job schedule method.${reset}"
			fi
		else
			echo -e "${cyan}${m_tab}#####################################################${reset}\n"
			echo "${m_tab}${green}Please select your job schedule method.${reset}"
		fi

		# Forward to installation
		while true
		do
			echo "${m_tab}${cyan}#####################################################${reset}"
			read -r -n 1 -p "${m_tab}${BC}c for crontab, s for systemd(recommended), q for quit${EC} " cs < /dev/tty
			echo ""
			case "${cs}" in
				[Cc]* ) add_cron; break;;
				[Ss]* ) add_systemd; break;;
				[qQ]* ) exit 1;;
			* ) echo -e "\n${m_tab}${magenta}Please answer c or s, q.${reset}"; echo "${cyan}${m_tab}#####################################################${reset}";;
			esac
		done
	fi
fi

# MAIN STRING MATCHING LOGIC
# =============================================================================================

# Exit --> always appended file not removed by trap on previous run
catch_trap_fail () {
	echo -e "\n${red}*${reset} ${red}Removing temporary file failed on previous run${reset}"
	echo "${cyan}${m_tab}#####################################################${reset}"
	echo "${m_tab}${red}File(s) ${1} ${2} still exist.${reset}"
	echo -e "${m_tab}${red}Could not catch signal to remove file(s)${reset}\n"
	echo "$(timestamp): Could not catch signal to remove files ${1} ${2} on previous run" >> "${wooaras_log}"
	send_mail "Could not catch signal to remove file(s) ${1} ${2} on previous run"
	exit 1
}

# Get WC order's ID (processing status) & WC customer info
# As of 2021 max 100 orders fetchable with one query
if $m_curl -s -o /dev/null -X GET --fail "https://$api_endpoint/wp-json/wc/v3/orders?status=processing&per_page=100" -u "$api_key":"$api_secret" -H "Content-Type: application/json"; then
	$m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders?status=processing&per_page=100" -u "$api_key":"$api_secret" -H "Content-Type: application/json" |
	$m_jq -r '.[]|[.id,.shipping.first_name,.shipping.last_name]|join(" ")' > "$this_script_path/wc.proc"
else
	echo -e "\n${red}*${reset}${red} WooCommerce REST API Connection Error${reset}"
	echo "${cyan}${m_tab}#####################################################${reset}"
	echo -e "${m_tab}${red}This can be temporary connection error${reset}\n"
	echo "$(timestamp): WooCommerce REST API connection error, this can be temporary connection error" >> "${wooaras_log}"
	send_mail "WooCommerce REST API connection error, this can be temporary connection error"
	exit 1
fi

# Two-way workflow, extract tracking number from data we previosly marked as shipped
if [[ -e "${this_script_path}/.two.way.enb" ]]; then
	declare -A check_status_del
	declare -A check_status_del_new

	# Parse access log to get shipped order data
	if [[ -e "${wooaras_log}" ]]; then
		grep "SHIPPED" "${wooaras_log}" | $m_awk '{print $1,$6,$8}' | tr = ' ' | $m_awk '{print $1,$3,$5}' | $m_sed "s|^|$(date +"%T,%d-%b-%Y") |" | $m_awk '{print $3,$4,$1,$2}' |
		$m_awk '
		BEGIN{
  			num=split("jan,feb,mar,apr,may,jun,jul,aug,sep,oct,nov,dec",month,",")
			for(i=1;i<=12;i++){
			a[month[i]]=i
			}
		}
		{
		split($(NF-1),array,"[:,-]")
		split($(NF),array1,"[:,-]")
		val=mktime(array[6]" "a[tolower(array[5])]" "array[4]" "array[1]" "array[2]" "array[3])
		val1=mktime(array1[6]" "a[tolower(array1[5])]" "array1[4]" "array1[1]" "array1[2]" "array1[3])
		delta=val>=val1?val-val1:val1-val
		hrs = int(delta/3600)
		min = int((delta - hrs*3600)/60)
		sec = delta - (hrs*3600 + min*60)
		printf "%s\t%02d:%02d:%02d\n", $0, hrs, min, sec
		hrs=min=sec=delta=""
		}
		' |
		$m_awk '{print $1,$2,$5}' | tr : ' ' | $m_awk '{print $1,$2,$3/24}' | tr . ' ' | $m_awk '{print $3,$2,$1}' | $m_awk '(NR>0) && ($1 <= '"$delivery_time"')' | cut -f2- -d ' ' > "${this_script_path}/wc.proc.del"
	else
		echo -e "\n${red}*${reset} ${red}Could not find ${wooaras_log}${reset}"
		echo "${cyan}${m_tab}#####################################################${reset}"
		echo -e "${m_tab}${red}Check script logging correctly${reset}\n"
		echo "$(timestamp): Could not find ${wooaras_log}, check script logging correctly." >> "${wooaras_log}"
		send_mail "Could not find ${wooaras_log}, check script logging correctly."
		exit 1
	fi

	# Verify columns of file
	if [[ -s "${this_script_path}/wc.proc.del" ]]; then
		good_del=true
		while read -ra fields
		do
			if [[ ! (${fields[0]} =~ ^[+-]?[[:digit:]]+$ && ${fields[1]} =~ ^[+-]?[[:digit:]]+$ ) ]]; then
				good_del=false
				break
			fi
		done < "${this_script_path}/wc.proc.del"
		if $good_del; then
			while read -r track id; do
				check_status_del[$track]=$id
			done < "${this_script_path}/wc.proc.del"
		fi
	fi

	# Validate that orders are only in shipped/completed status
	if [[ "${#check_status_del[@]}" -gt 0 ]]; then
		if ! [[ -e "${this_script_path}/wc.proc.del.tmp1" && -e "${this_script_path}/wc.proc.del.tmp" ]]; then # These are always appended file and trap(cleanup) can fail
			for i in "${!check_status_del[@]}"
			do
				check_status_del_new[$i]=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders/${check_status_del[$i]}" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.status]|join(" ")')
				echo "${i}" "${check_status_del_new[$i]}" >> "${this_script_path}/wc.proc.del.tmp1"
				echo "${i}" "${check_status_del[$i]}" >> "${this_script_path}/wc.proc.del.tmp"
			done
			$m_awk 'FNR==NR{a[$1]=$2;next}{print $0,a[$1]?a[$1]:"NA"}' "${this_script_path}/wc.proc.del.tmp1" "${this_script_path}/wc.proc.del.tmp" | $m_sed '/completed/!d' > "${this_script_path}/wc.proc.del"
		else
			catch_trap_fail "${this_script_path}/wc.proc.del.tmp1" "${this_script_path}/wc.proc.del.tmp"
		fi
	fi
fi


# Modify ARAS SOAP json response to make easily parsable with jq
if [[ -s "${this_script_path}/aras.json" ]]; then
	< "${this_script_path}/aras.json" $m_sed 's/^[^[]*://g' | $m_awk 'BEGIN{OFS=FS="]"};{$NF="";print $0}' > "${this_script_path}/aras.json.mod" || { echo 'cannot modify aras.json'; exit 1; }
fi

# Parse ARAS JSON data with jq to get necessary data --> status, recipient{name,surname}, tracking number(undelivered yet)
if [[ -s "${this_script_path}/aras.json.mod" ]]; then
	< "${this_script_path}/aras.json.mod" $m_jq -r '.[]|[.DURUM_KODU,.KARGO_TAKIP_NO,.ALICI]|join(" ")' | $m_sed '/^6/d' | cut -f2- -d ' ' > "${this_script_path}/aras.proc"
fi

# Two-way workflow, Parse ARAS JSON data with jq to get necessary data --> status, recipient{name,surname}, tracking number(delivered)
if [[ -e "${this_script_path}/.two.way.enb" ]]; then
	if [ -s "${this_script_path}/aras.json.mod" ]; then
		< "${this_script_path}/aras.json.mod" $m_jq -r '.[]|[.DURUM_KODU,.KARGO_TAKIP_NO,.ALICI]|join(" ")' | $m_sed '/^6/!d' | cut -f2- -d ' ' | $m_awk '{print $1}' > "${this_script_path}/aras.proc.del"
	fi
fi

# For perfect matching with order id and tracking number we are normalizing the data.
# Translate customer info to 'en' & transform text to lowercase & remove whitespaces
if [[ -s "${this_script_path}/aras.proc" && -s "${this_script_path}/wc.proc" ]]; then
	iconv -f utf8 -t ascii//TRANSLIT < "${this_script_path}/aras.proc" | tr '[:upper:]' '[:lower:]' | $m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= | $m_awk '{gsub("[.=_:,-?]*","",$2)}1' > "${this_script_path}/aras.proc.en"
	iconv -f utf8 -t ascii//TRANSLIT < "${this_script_path}/wc.proc" | tr '[:upper:]' '[:lower:]' | $m_awk '{s=$1;gsub($1 FS,x);$1=$1;print s FS $0}' OFS= | $m_awk '{gsub("[.=_:,-?]*","",$2)}1' > "${this_script_path}/wc.proc.en"
fi

# Two-way workflow
if [[ -e "${this_script_path}/.two.way.enb" ]]; then
	if [[ -s "${this_script_path}/aras.proc.del" && -s "${this_script_path}/wc.proc.del" ]]; then
		good_aras_del=true
		while read -ra fields
		do
			if [[ ! ${fields[0]} =~ ^[+-]?[[:digit:]]+$ ]]; then
				good_aras_del=false
				break
			fi
		done < "${this_script_path}/aras.proc.del"

		if $good_aras_del; then
			if [ "$($m_awk '{print NF}' "${this_script_path}"/aras.proc.del | sort -nu | tail -n 1)" -eq 1 ]; then
				mapfile -t two_way_arr < "${this_script_path}"/aras.proc.del
				for i in "${two_way_arr[@]}"
				do
					if grep -qw "$i" "${this_script_path}"/wc.proc.del; then
						echo -e "$(grep "$i" "${this_script_path}"/wc.proc.del | $m_awk '{print $2}')\n" >> "${my_tmp_del}"
					fi
				done

				if [[ -s "${my_tmp_del}" ]]; then
					echo "$(< "${my_tmp_del}" $m_sed '/^[[:blank:]]*$/ d' | $m_awk '!seen[$0]++')" > "${my_tmp_del}"
				fi
			fi
		fi
	fi
fi

# Verify data integrity (check fields only contains digits, letters && existence of data (eliminate null,whitespace)
# If only data valid then read file into associative array (so array length will not effected by null data)
declare -A aras_array
declare -A wc_array

for en in "${this_script_path}"/*.en
do
	if [[ -s "${en}" ]]; then
		good=true
		while read -ra fields
		do
			if [[ ! (${fields[0]} =~ ^[+-]?[[:digit:]]+$ && ${fields[1]} =~ ^[a-z]+$ ) ]]; then
				good=false
				break
			fi
		done < "${en}"
		if $good; then
			if grep -q "wc.proc" <<< "${en}"; then
				while read -r id w_customer
				do
					wc_array[$id]="${w_customer}"
				done < "${en}"
			elif grep -q "aras.proc" <<< "${en}"; then
				while read -r track a_customer
				do
					aras_array[$track]="${a_customer}"
				done < "${en}"
			fi
		fi
	fi
done

# Prepeare necessary data for matching operation
if [[ "${#aras_array[@]}" -gt 0 && "${#wc_array[@]}" -gt 0 ]]; then # Check length of arrays to continue
	if [[ ! -e "${this_script_path}/.lvn.all.cus" ]]; then # This is always appended file and trap(cleanup) can fail
		for i in "${!wc_array[@]}"; do
			for j in "${!aras_array[@]}"; do
				echo "${i}" "${wc_array[$i]}" "${j}" "${aras_array[$j]}" >> "${this_script_path}/.lvn.all.cus"
			done
		done
	else
		catch_trap_fail "${this_script_path}/.lvn.all.cus"
	fi
fi

# Use perl for string matching via levenshtein distance function
if [[ -s "${this_script_path}/.lvn.all.cus" ]]; then
	if [[ ! -e "${this_script_path}/.lvn.stn" ]]; then # This is always appended file and trap can fail, linux is mystery
		while read -r wc aras
		do
			$m_perl -MText::Fuzzy -e 'my $tf = Text::Fuzzy->new ("$ARGV[0]");' -e 'print $tf->distance ("$ARGV[1]"), "\n";' "$wc" "$aras" >> "${this_script_path}/.lvn.stn"
		done < <( < "${this_script_path}/.lvn.all.cus" $m_awk '{print $2,$4}' )
		$m_paste "${this_script_path}/.lvn.all.cus" "${this_script_path}/.lvn.stn" | $m_awk '($5 <= '"$max_distance"')' | $m_awk '{print $1,$3}' > "${my_tmp}"
	else
		catch_trap_fail "${this_script_path}/.lvn.stn"
	fi

	# Better handle multiple orders(processing) for same customer
	# Better handle multiple tracking numbers for same customer
	if [[ -s "${my_tmp}" ]]; then
		declare -A magic
		while read -r id track; do
			magic[${id}]="${magic[$id]}${magic[$id]:+ }${track}"
		done < "${my_tmp}"

		if [[ ! -e "${this_script_path}/.lvn.mytmp2" ]]; then
			for id in "${!magic[@]}"; do
				echo "$id ${magic[$id]}" >> "${this_script_path}/.lvn.mytmp2" # This is always appended file and trap can fail, linux is mystery
			done
		else
			catch_trap_fail "${this_script_path}/.lvn.mytmp2"
		fi
	fi

	if [[ -s "${this_script_path}/.lvn.mytmp2" ]]; then
		if [[ "$($m_awk '{print NF}' "${this_script_path}"/.lvn.mytmp2 | sort -nu | tail -n 1)" -gt 2 ]]; then
			$m_awk 'NF==3' "${this_script_path}/.lvn.mytmp2" > "${this_script_path}/.lvn.mytmp3"
			if [[ "$($m_awk 'x[$2]++ == 1 { print $2 }' "${this_script_path}"/.lvn.mytmp3)" ]]; then
				for i in $($m_awk 'x[$2]++ == 1 { print $2 }' "${this_script_path}/.lvn.mytmp3"); do
					$m_sed -i "0,/$i/{s/$i//}" "${this_script_path}/.lvn.mytmp3"
				done
				cat <(cat "${this_script_path}/.lvn.mytmp3" | $m_awk '{$1=$1}1' | $m_awk '{print $1,$2}') <(cat "${this_script_path}/.lvn.mytmp2" | $m_awk 'NF<=2') > "${my_tmp}"
			else
				cat <(cat "${this_script_path}/.lvn.mytmp3" | $m_awk '{print $1,$2}') <(cat "${this_script_path}/.lvn.mytmp2" | $m_awk 'NF<=2') > "${my_tmp}"
			fi
		fi
	fi
fi
# END MAIN STRING MATCHING LOGIC
# ============================================================================================

# Lets start updating woocommerce order status as completed with AST plugin.
# ARAS Tracking number will be sent to customer.
exit_curl_fail () {
	echo -e "\n${red}*${reset} ${red}Could not update order [${id}] status${reset}"
	echo "${m_tab}${cyan}#####################################################${reset}"
	echo "${m_tab}${red}Wrong Order ID or REST endpoint error${reset}"
	echo -e "${m_tab}${red}Check ${1} to validate data${reset}\n"
	echo "$(timestamp): Could not update order ${id} status, wrong Order ID(corrupt data) or REST endpoint error, check ${1} to validate data" >> "${wooaras_log}"
	send_mail "Could not update order [${id}] status, wrong Order ID(couupt data) or WooCommerce REST API endpoint error, check ${1} to validate data"
	exit 1
}

if [[ -e "${this_script_path}/.woo.aras.enb" ]]; then
	if [[ -s "${my_tmp}" ]]; then
		# For debugging purpose save the parsed data first
		if [[ ! -d "${this_script_path}/tmp" ]]; then
			mkdir "${this_script_path}/tmp" || { echo "Updating order failed, could not create folder ${this_script_path}/tmp"; exit 1; }
		fi
		cat <(cat "${my_tmp}") > "${my_tmp_folder}/$(date +%d-%m-%Y)-main.$$"
		cat <(cat "${this_script_path}/wc.proc.en") > "${my_tmp_folder}/$(date +%d-%m-%Y)-wc.proc.en.$$"
		cat <(cat "${this_script_path}/aras.proc.en") > "${my_tmp_folder}/$(date +%d-%m-%Y)-aras.proc.en.$$"

		while read -r id track
		do
			# Update order with AST Plugin REST API
			if $m_curl -s -o /dev/null -X POST --fail \
				-u "$api_key":"$api_secret" \
				-H "Content-Type: application/json" \
				-d '{"tracking_provider": "Aras Kargo","tracking_number": "'"${track}"'","date_shipped": "'"${t_date}"'","status_shipped": 1}' \
				"https://$api_endpoint/wp-json/wc-ast/v3/orders/$id/shipment-trackings"; then
				sleep 5
				c_name=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders/$id" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.shipping.first_name,.shipping.last_name]|join(" ")')
				# If you use 'sequential order number' plugins
				order_number=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders/$id" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.meta_data]' | $m_awk '/_order_number/{getline; print}' | $m_awk -F: '{print $2}' | tr -d '"' | $m_sed -r 's/\s+//g' | tr " " "*" | tr "\t" "&")
				# Notify shop manager -- HTML mail
				send_mail_suc <<- EOF >/dev/null 2>&1
				<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd"><html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"/></head><body><table id="v1template_container" style="background-color: #ffffff; border: 1px solid #dedede; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1); border-radius: 3px;" border="0" width="600" cellspacing="0" cellpadding="0"><tbody><tr><td align="center" valign="top"><table id="v1template_header" style="background-color: #567d46; color: #ffffff; border-bottom: 0; font-weight: bold; line-height: 100%; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; border-radius: 3px 3px 0 0;" border="0" width="100%" cellspacing="0" cellpadding="0"><tbody><tr><td id="v1header_wrapper" style="padding: 36px 48px; display: block;"><h2 style="font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 30px; font-weight: 300; line-height: 150%; margin: 0px; text-shadow: #78976b 0px 1px 0px; color: #ffffff; background-color: inherit; text-align: center;">Aras Kargo Otomatik Güncelleme: $id - $order_number</h2></td></tr></tbody></table></td></tr><tr><td align="center" valign="top"><table id="v1template_body" border="0" width="600" cellspacing="0" cellpadding="0"><tbody><tr><td id="v1body_content" style="background-color: #ffffff;" valign="top"><table border="0" width="100%" cellspacing="0" cellpadding="20"><tbody><tr><td style="padding: 48px 48px 32px;" valign="top"><div id="v1body_content_inner" style="color: #636363; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 14px; line-height: 150%; text-align: left;"><p style="margin: 0 0 16px;">Merhaba $company_name, $c_name siparişi kargoya verildi ve sipariş durumu tamamlandı olarak güncellendi: Müşteriye kargo takip kodunu da içeren bir bilgilendirme maili gönderildi.</p><h2 style="color: #567d46; display: block; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 18px; font-weight: bold; line-height: 130%; margin: 0 0 18px; text-align: left;"><a class="v1link" style="font-weight: normal; text-decoration: underline; color: #567d46;" href="#" target="_blank" rel="noreferrer">[Sipariş #$id]</a> ($t_date)</h2><div style="margin-bottom: 40px;"><table class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; width: 100%; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif;" border="1" cellspacing="0" cellpadding="6"><thead><tr><th class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; padding: 12px; text-align: left;">KARGO</th><th class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; padding: 12px; text-align: left;">İSİM</th><th class="v1td" style="color: #636363; border: 1px solid #e5e5e5; vertical-align: middle; padding: 12px; text-align: left;">TAKİP KODU</th></tr></thead><tbody><tr class="v1order_item"><td class="v1td" style="color: #636363; border: 1px solid #e5e5e5; padding: 12px; text-align: left; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; word-wrap: break-word;">ARAS KARGO</td><td class="v1td" style="color: #636363; border: 1px solid #e5e5e5; padding: 12px; text-align: left; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif;">$c_name</td><td class="v1td" style="color: #636363; border: 1px solid #e5e5e5; padding: 12px; text-align: left; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif;">$track</td></tr></tbody></table></div></div></td></tr></tbody></table></td></tr></tbody></table></td></tr></tbody></table></body></html>
				EOF
				echo "$(date +"%T,%d-%b-%Y"): ORDER MARKED AS SHIPPED: Order_Id=$id Order_Number=$order_number Aras_Tracking_Number=$track Customer_Info=$c_name" >> "${wooaras_log}"
				echo "${green}*${reset} ${green}ORDER UPDATED AS COMPLETED: Order_Id=$id Order_Number=$order_number Aras_Tracking_Number=$track Customer_Info=$c_name${reset}"
				sleep 10
			else
				exit_curl_fail "${my_tmp_folder}/$(date +%d-%m-%Y)-main.$$"
			fi
		done < "${my_tmp}"
	else
		echo "${yellow}*${reset} ${yellow}Couldn't find any updateable order now.${reset}"
		echo "$(timestamp): Couldn't find any updateable order now." >> "${wooaras_log}"
	fi

	if [[ -e "${this_script_path}/.two.way.enb" ]]; then
		if [[ -s "${my_tmp_del}" ]]; then
			# For debugging purpose save the parsed data first
			if [[ ! -d "${this_script_path}/tmp" ]]; then
				mkdir "${this_script_path}/tmp" || { echo "Updating order failed, could not create folder ${this_script_path}/tmp"; exit 1; }
			fi
			cat <(cat "${my_tmp_del}") > "${my_tmp_folder}/$(date +%d-%m-%Y)-main.del.$$"
			cat <(cat "${this_script_path}/wc.proc.del") > "${my_tmp_folder}/$(date +%d-%m-%Y)-wc.proc.del.$$"
			cat <(cat "${this_script_path}/aras.proc.del") > "${my_tmp_folder}/$(date +%d-%m-%Y)-aras.proc.del.$$"

			while read -r id
			do
				# Update order as delivered via WooCommerce REST API
				if $m_curl -s -o /dev/null -X PUT --fail \
					-u "$api_key":"$api_secret" \
					-H "Content-Type: application/json" \
					-d '{"status": "delivered"}' \
					"https://$api_endpoint/wp-json/wc/v3/orders/$id"; then
					sleep 5
					c_name=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders/$id" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.shipping.first_name,.shipping.last_name]|join(" ")')
					# Get order number if you use 'sequential order number' plugin
					order_number=$($m_curl -s -X GET "https://$api_endpoint/wp-json/wc/v3/orders/$id" -u "$api_key":"$api_secret" -H "Content-Type: application/json" | $m_jq -r '[.meta_data]' | $m_awk '/_order_number/{getline; print}' | $m_awk -F: '{print $2}' | tr -d '"' | $m_sed -r 's/\s+//g' | tr " " "*" | tr "\t" "&")
					# Notify shop manager -- HTML mail
					send_mail_suc <<- EOF >/dev/null 2>&1
					<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd"><html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"/></head><body><table id="v1template_container" style="background-color: #ffffff; border: 1px solid #dedede; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1); border-radius: 3px;" border="0" width="600" cellspacing="0" cellpadding="0"><tbody><tr><td align="center" valign="top"><table id="v1template_header" style="background-color: #567d46; color: #ffffff; border-bottom: 0; font-weight: bold; line-height: 100%; vertical-align: middle; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; border-radius: 3px 3px 0 0;" border="0" width="100%" cellspacing="0" cellpadding="0"><tbody><tr><td id="v1header_wrapper" style="padding: 36px 48px; display: block;"><h2 style="font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 30px; font-weight: 300; line-height: 150%; margin: 0px; text-shadow: #78976b 0px 1px 0px; color: #ffffff; background-color: inherit; text-align: center;">Aras Kargo Otomatik Güncelleme: $id - $order_number</h2></td></tr></tbody></table></td></tr><tr><td align="center" valign="top"><table id="v1template_body" border="0" width="600" cellspacing="0" cellpadding="0"><tbody><tr><td id="v1body_content" style="background-color: #ffffff;" valign="top"><table border="0" width="100%" cellspacing="0" cellpadding="20"><tbody><tr><td style="padding: 48px 48px 32px;" valign="top"><div id="v1body_content_inner" style="color: #636363; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 14px; line-height: 150%; text-align: left;"><p style="margin: 0 0 16px;">Merhaba <strong>$company_name</strong>, <strong>$c_name</strong> siparişi müşteriye ulaştı ve sipariş durumu <strong>Teslim Edildi</strong> olarak güncellendi. Müşteriye sipariş durumunu içeren bir bilgilendirme e-mail'i gönderildi.</p><h2 style="color: #567d46; display: block; font-family: 'Helvetica Neue', Helvetica, Roboto, Arial, sans-serif; font-size: 18px; font-weight: bold; line-height: 130%; margin: 0 0 18px; text-align: left;"><a class="v1link" style="font-weight: normal; text-decoration: underline; color: #567d46;" href="#" target="_blank" rel="noopener noreferrer">[Sipariş #$id]</a> ($t_date)</h2><div style="margin-bottom: 40px;">&nbsp;</div></div></td></tr></tbody></table></td></tr></tbody></table></td></tr></tbody></table></body></html>
					EOF
					echo "$(date +"%T,%d-%b-%Y"): ORDER MARKED AS DELIVERED: Order_Id=$id Order_Number=$order_number Customer_Info=$c_name" >> "${wooaras_log}"
					echo "${green}*${reset} ${green}ORDER UPDATED AS DELIVERED: Order_Id=$id Order_Number=$order_number Customer_Info=$c_name${reset}"
					sleep 10
				else
					exit_curl_fail "${my_tmp_folder}/$(date +%d-%m-%Y)-main.del.$$"
				fi
			done < "${my_tmp_del}"
		else
			echo "${yellow}*${reset} ${yellow}[Two-way] Couldn't find any updateable order now.${reset}"
			echo "$(timestamp): [Two-way] Couldn't find any updateable order now." >> "${wooaras_log}"
		fi
	fi
fi

# And lastly we exit
exit $?
