[![Build Status](https://travis-ci.com/hsntgm/woocommerce-aras-kargo.svg?token=pex9yoGqJVyVQgXxYi7X&branch=main)](https://travis-ci.com/github/hsntgm/woocommerce-aras-kargo)

# WooCommerce - Aras Cargo Integration
## Pluginless pure linux server side bash script solution #root
[![N|Solid](https://www.cyberciti.biz/media/new/category/old/terminal.png)](https://www.psauxit.com) 

The aim of this bash script solution is effortlessly integrate WooCommerce and ARAS cargo with help of AST plugin. Note that this is not a deep integrate solution. Instead of syncing your order with Aras end just listens ARAS for newly created cargo tracking numbers and match them with application (WooCommerce) side customer info. 

## What is the actual solution here exactly?
> This automation updates woocomerce order status from processing to completed (REST),
> when the matching cargo tracking code is generated on the ARAS Cargo end (SOAP).
> Attachs cargo information (tracking number, track link etc.) to
> order completed e-mail with the help of AST plugin (REST) and notify customer.
> Simply you don't need to manually add cargo tracking number and update order status
> via WooCommerce orders dashboard. The aim of script is automating the process fully.

## What are the supported workflows?
- 1. processing -> completed
- 2. processing -> shipped -> delivered 

In default workflow if the cargo on the way (tracking number generated on ARAS end) we update order status processing to completed. If you use this workflow there is no need to create any custom order status.  
If you use three way workflow 'processing -> shipped -> delivered' we need to do some modifications that explained below.

## Will mess up anything?
No! Interactive setup will ask you to validate some parsed data. If you don't validate the data installation part will be skipped. This solution never ever touch any core files of wordpress or woocommerce. You can uninstall any time you want.

![setup5](https://user-images.githubusercontent.com/25556606/124501159-baf95700-ddc9-11eb-81ce-84c5b9117639.png)

## Where is Turkish translation?
You are welcome to add support/contribute on Turkish translation. Currently script only supports mail notifications in Turkish. The setup and logs not supported yet.

## Features
- Interactive easy setup
- Encrypt all sensetive data (REST,SOAP credentials) also never seen on bash history. Doesn't keep any sensetive data on files.
- Powerful error handling for various checks like SOAP and REST API connections
- Auto installation methods via cron, systemd
- Adds logrotate if you have
- Pluginless pure server side bash solution, set and forget
- HTML notify mails for updated orders, errors
- Easily auto upgrade to latest version
- Prevent mismatchs caused by typo via levenshtein distance function. Approximate string matching up to 3 characters.

![setup](https://user-images.githubusercontent.com/25556606/124499928-7e2c6080-ddc7-11eb-9df2-672a0f5ab2d1.png) ![setup4](https://user-images.githubusercontent.com/25556606/124500396-61445d00-ddc8-11eb-92eb-de3af3ff3d63.png)

## Hard Dependencies
- bash
- perl
- perl Text::Fuzzy
- curl
- openssl
- mail (mailutils)
- jq
- php
- iconv
- pstree
- sed
- awk
- stat
- paste
- woocommerce AST plugin free (https://wordpress.org/plugins/woo-advanced-shipment-tracking/)

## User Defined Settings
Please set below settings manually in the script. While auto update triggers we always keep these settings.
So it is enough to set one time. For mail notification you need working mail server like postfix with 'mail' command which comes with mailutils linux package.

- error_log
- access_log
- company_name
- company_domain
- mail_to
- mail_from
- mail_subject_suc
- mail_subject_err

## Pre-Requisites
- WooCommerce API Key (v3)
- WooCommerce API Secret (v3)
- Wordpress Domain URL
- ARAS SOAP API Password
- ARAS SOAP API Username
- ARAS SOAP Endpoint URL (wsdl)
- ARAS SOAP Merchant Code
- ARAS SOAP Query Type (12 or 13)

## Usage
- Get necessary credentials from ARAS commercial user control panel (https://esasweb.araskargo.com.tr/) (choose JSON fromat)
- Enable and setup WooCommerce REST API (use v3, not legacy)
- Adjust user defined settings as mentioned before
- Clear wordpress cache for some security checks
- Be sure you have some data both on woocommerce and ARAS for validations (if not create test orders)
- Clone repo ```git clone https://github.com/hsntgm/woocommerce-aras-kargo.git``` (Never manually copy/paste script)
- Copy woocommerce-aras-cargo.sh anywhere you want and execute script as 'root' or with sudo 
- ```sudo ./woocommerce-aras-cargo.sh --setup```

![help](https://user-images.githubusercontent.com/25556606/124503366-175e7580-ddce-11eb-8e3c-fcd01bde6028.png)
