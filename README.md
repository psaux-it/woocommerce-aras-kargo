[![Build Status](https://travis-ci.com/hsntgm/woocommerce-aras-kargo.svg?token=pex9yoGqJVyVQgXxYi7X&branch=main)](https://travis-ci.com/github/hsntgm/woocommerce-aras-kargo)

# WooCommerce - Aras Cargo Integration
## Pluginless pure linux server side bash script solution #root
[![N|Solid](https://www.cyberciti.biz/media/new/category/old/terminal.png)](https://www.psauxit.com) 

The aim of this bash script solution is effortlessly integrate WooCommerce and ARAS cargo with help of AST plugin. Note that this is not a deep integrate solution. Instead of syncing your order with Aras end just listens ARAS for newly created cargo tracking numbers and match them with application (WooCommerce) side customer info. 

## What is the actual solution here exactly?
![woocommerce](https://user-images.githubusercontent.com/25556606/125707166-aa92a5a3-5655-450c-bc23-c67d8fc5ab10.png)

> This automation updates woocomerce order status 'processing' to 
> 'completed/shipped' (via REST), when the matching cargo tracking code is 
> generated on the ARAS Cargo end (via SOAP). Attachs cargo information 
> (tracking number, track link etc.) to order completed/shipped e-mail with the
> help of AST plugin (REST) and notify customer. If you implemented
> two way fulfillment workflow, script goes one layer up and updates order status 'shipped'
> to 'delivered' and notify customer via second mail. Simply you don't need to add cargo 
> tracking number manually and update order status via WooCommerce orders dashboard.
> The aim of script is automating the process fully.

## What are the supported workflows?
![mermaid-diagram-20210714032040](https://user-images.githubusercontent.com/25556606/125541661-f8a05b42-c174-4bfb-81c9-84e01036a1f6.png)

In default workflow if the cargo on the way (tracking number generated on ARAS end) we update order status processing to completed. If you use default workflow there is no need to create any custom order status.

![mermaid-diagram-20210714032102](https://user-images.githubusercontent.com/25556606/125541613-e1232826-72ad-4555-98cc-5e1b79c8e352.png)

If you are implementing two way workflow 'processing -> shipped -> delivered' we need to do some extra stuff that explained below.

## Two way workflow installation (Optional)
![twoway_fulfillment](https://user-images.githubusercontent.com/25556606/126962984-d0c6a0e5-e22c-45f4-ba04-500c0f30e405.png)
Script will ask you for auto implementation during the setup. You can choose auto installation or you can go with manual implementation. Manual implementation explained below. In both cases there are 3 prerequisites:

### Prerequisites
- 1-You need a child theme activated (all modifications will apply to child theme - we will never touch core files)
- 2-Execute script on application server (webserver where your wordpress/woocommerce currently runs on)
- 3-Be sure you work with default woocommerce fulfillment workflow (e.g don't have any 'delivered' custom order status which has been already implemented before)

If you go with auto implementation script will find your absolute child theme path and will ask your approval for modifications. If child theme path is wrong please DON'T CONTINUE and go with manual implementation.

### Manual Implementation
You can find necessary files in ```custom-order-status-package```
I assume you child theme absolute path is ```/var/www/html/wp-content/themes/my-child```


## Will mess up anything?
No! At least if you don't modify source code blindly. If you have a pre-prod env. test it before production.
Also interactive setup will ask you to validate some parsed data. If you don't validate the data -installation part will be skipped.
While auto implementing two way fulfillment workflow we just use child theme so we never ever touch any core files of wordpress or woocommerce directly.

![setup5](https://user-images.githubusercontent.com/25556606/124501159-baf95700-ddc9-11eb-81ce-84c5b9117639.png)

## Any drawbacks?
Partially Yes! If you have multiple order from same customer just ship them all at once. If you partially ship them (multiple tracking number) matching algorithm can fail but not mess up anything. Keep in mind that If you have a large volume e-commerce platform eg. marketplace you need deep integration solutions.

## Where is the Turkish translation?
Critical part such as success mails, fronted&admin side custom order status label supports Turkish. You are welcome to add support/contribute on Turkish translation of setup&logging&readme part.

## Features
- Interactive easy setup
- Two way fulfillment workflow with custom order status package
- Encryped sensetive data (REST,SOAP credentials) also never seen on bash history
- Powerful error handling for various checks like SOAP and REST API connections
- Auto installation methods via cron, systemd
- Logrotate support
- Pluginless pure server side bash solution, set and forget
- HTML notify mails for updated orders, errors
- Easily auto upgrade to latest version
- Strong string matching logic via levenshtein distance function

![setup](https://user-images.githubusercontent.com/25556606/124499928-7e2c6080-ddc7-11eb-9df2-672a0f5ab2d1.png)

## Hard Dependencies (not included in default linux installations)
- perl-Text::Fuzzy>=0.29 --> for string matching via levenshtein distance function
- jq>=1.6 --> simplify JSON parsing operations
- php>=7.0 --> for creating SOAP client to get data from ARAS
- whiptail (as also known (newt,libnewt))

## Recommended Tools
- mail --> for shop manager mail alerts (comes with mailutils linux package)

## Tested Applications Versions
- wordpress>=5.7.2
- wocommerce>=5.5.1 
- woocommerce AST plugin>=3.2.5 (https://wordpress.org/plugins/woo-advanced-shipment-tracking/)

## Tested Linux Distros
- Gentoo
- Ubuntu
- Debian

## Requirements During Interactive Setup
- WooCommerce REST API Key (v3)
- WooCommerce REST API Secret (v3)
- Wordpress Site URL (format in www.my-ecommerce.com)
- ARAS SOAP API Password
- ARAS SOAP API Username
- ARAS SOAP Endpoint URL (wsdl) (get from ARAS commercial user control panel)
- ARAS SOAP Merchant Code
- ARAS SOAP Query Type (restricted to 12/13)

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

## Usage
- If you go with two way fulfillment workflow (with custom order status package) be sure your setup is working
- Get necessary credentials from ARAS commercial user control panel (https://esasweb.araskargo.com.tr/) (choose JSON fromat)
![araskargo-11](https://user-images.githubusercontent.com/25556606/125905483-99941283-cd59-4ac5-b9ea-afc54132dc7b.png)
- Enable and setup WooCommerce REST API, get credentials (only support REST API v3)
- Adjust user defined settings as mentioned before
- Clear wordpress cache for some security checks
- Be sure you have some data both on woocommerce and ARAS for validations (if not create test orders)
- Clone repo ```git clone https://github.com/hsntgm/woocommerce-aras-kargo.git``` (Never manually copy/paste script)
- Copy woocommerce-aras-cargo.sh anywhere you want and execute script as 'root' or with sudo 
- ```sudo ./woocommerce-aras-cargo.sh --setup```

![help](https://user-images.githubusercontent.com/25556606/124503366-175e7580-ddce-11eb-8e3c-fcd01bde6028.png)
