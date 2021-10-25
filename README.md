# WooCommerce - Aras Cargo Integration
## Pluginless linux server side bash scripting solution
<img align="left" width="100" height="100" src="https://www.cyberciti.biz/media/new/category/old/terminal.png">

##### QUICK START - ONE LINER
```sudo bash < <(curl -Ssk https://raw.githubusercontent.com/hsntgm/woocommerce-aras-kargo/main/woo-aras-setup.sh)```

The aim of this pluginless bash scripting solution is effortlessly integrate WooCommerce and ARAS cargo with help of [free AST plugin](https://wordpress.org/plugins/woo-advanced-shipment-tracking/). Note that this is not a deep integrate solution. Instead of syncing your order with Aras end just listens ARAS for newly created cargo tracking numbers and match them with application (WooCommerce) side customer info.
This solution best suits to small-mid size e-commerce business. Keep in mind that If you have a large volume e-commerce business you need deep integration solutions.

## What is the actual solution here exactly?
![woocommerce_aras](https://user-images.githubusercontent.com/25556606/128205563-e9e5d617-1dd9-4eed-a284-3389180e09f9.png)

> This automation updates woocomerce order status 'processing' to 
> 'completed/shipped' (via REST), when the matching cargo tracking code is 
> generated on the ARAS Cargo end (via SOAP). Attachs cargo information 
> (tracking number, track link etc.) to order completed/shipped e-mail with the
> help of AST plugin (REST) and notify customer. If you implemented
> two-way fulfillment workflow, script goes one layer up and updates order status 'shipped'
> to 'delivered' and notify customer via second mail. Simply you don't need to add cargo 
> tracking number manually and update order status via WooCommerce orders dashboard.
> The aim of script is automating the process fully.

## What is the point of the project?
Because deep integration solutions are complex and costly, this automation was written to simplify this integration for small and medium-sized e-commerce owners.
Aras Cargo is the most used and most affordable cargo company in Turkey. ARAS provides SOAP XML/JSON membership to corporate customers. WooCommerce is also the most preferred e-commerce platform. Simply perfect match for small and medium-sized e-commerce owners.
If you need further technical assistance (for an other cargo company) or want to support my open source work:

<a href="https://commerce.coinbase.com/checkout/68aa76a7-a8e5-4de0-9e7c-29f9457e6802" target="_blank"><img src="https://user-images.githubusercontent.com/25556606/127000632-0bd49ce4-9eda-4b58-b3ac-9a9de9a809b2.png" alt="Buy MeA Coffee"></a>

---

## What are the supported workflows?
![mermaid-diagram-20210714032040](https://user-images.githubusercontent.com/25556606/125541661-f8a05b42-c174-4bfb-81c9-84e01036a1f6.png)

In default if the cargo on the way (tracking number generated on ARAS end) automation will update order status processing to completed. If you use default workflow there is no need to create any custom order status.

![mermaid-diagram-20210714032102](https://user-images.githubusercontent.com/25556606/125541613-e1232826-72ad-4555-98cc-5e1b79c8e352.png)

If you are implementing two-way workflow 'processing -> shipped -> delivered' we need to do some extra stuff that explained below.

![order-status](https://user-images.githubusercontent.com/25556606/127660311-26896fb9-6ed2-480a-8fef-104cb45ff825.png)

## Two-way workflow installation (Optional)
![twoway_fulfillment](https://user-images.githubusercontent.com/25556606/126962984-d0c6a0e5-e22c-45f4-ba04-500c0f30e405.png)
Automation script will ask you for auto implementation during the setup. You can choose auto installation or you can go with manual implementation. If auto implementation can't find your child theme path correctly follow manual implementation instructions below.
In both cases there are 4 prerequisites:

### Two-way workflow prerequisites
- 1-You need a active child theme (all modifications will apply to child theme - we never touch woocommerce/wordpress core files)
- 2-Execute script on application server (webserver where your wordpress/woocommerce currently runs on)
- 3-Be sure you work with default woocommerce fulfillment workflow (e.g don't have any custom order status which has been already implemented before)
- 4-Complete default setup first

If you go with auto implementation, automation script will find your absolute child theme path and will ask your approval for modifications. If child theme path is wrong please DON'T CONTINUE and go with manual implementation.

![child_theme](https://user-images.githubusercontent.com/25556606/126969002-c6346955-feaa-4ad1-adff-3cde1217fe13.png)

### Two-way workflow manual implementation guide
You can find necessary files in ```custom-order-status-package``` I assume you child theme absolute path is ```/var/www/html/wp-content/themes/my-child```

```
mkdir /var/www/html/wp-content/themes/my-child/woocommerce
mkdir /var/www/html/wp-content/themes/my-child/woocommerce/emails
mkdir /var/www/html/wp-content/themes/my-child/woocommerce/templates
mkdir /var/www/html/wp-content/themes/my-child/woocommerce/templates/emails
mkdir /var/www/html/wp-content/themes/my-child/woocommerce/templates/emails/plain
```

```
cp custom-order-status-package/aras-woo-delivered.php /var/www/html/wp-content/themes/my-child/woocommerce/
cp custom-order-status-package/class-wc-delivered-status-order.php /var/www/html/wp-content/themes/my-child/woocommerce/emails/
cp custom-order-status-package/wc-customer-delivered-status-order.php /var/www/html/wp-content/themes/my-child/woocommerce/templates/emails/
cp custom-order-status-package/wc-customer-delivered-status-order.php /var/www/html/wp-content/themes/my-child/woocommerce/templates/emails/plain/
```

```
chown -R your_webserver_user:your_webserver_group /var/www/html/wp-content/themes/my-child/woocommerce
```

Add below code to your child theme's functions.php ```/var/www/html/wp-content/themes/my-child/functions.php```

```
<?php
// woocommerce-aras-cargo-integration
include( get_stylesheet_directory() .'/woocommerce/aras-woo-delivered.php');
// woocommerce-aras-cargo-integration
```

Check your website working correctly and able to login admin panel. Check 'delivered' order status registered(via orders dashboard) and 'delivered' email template exist under woocommerce setup emails tab. Adjust 'delivered' mail template such as subject, body as you wish.

---

Configure AST plugin as shown in the picture and ENABLE --> Rename the "Completed" Order status label to "Shipped"
![ast](https://user-images.githubusercontent.com/25556606/126977656-7ab827aa-4551-470f-a833-9b0975cfddef.png)

If everything seems ok lastly enable workflow via;

```
sudo ./woocommerce-aras-cargo.sh --twoway-enable
```

## Will mess up anything?
No! At least if you don't modify source code blindly. If you have a pre-prod env. test it before production.
Also interactive setup will ask you to validate some parsed data. If you don't validate the data -installation part will be skipped.
While auto implementing two-way fulfillment workflow we just use child theme so we never ever touch any core files of wordpress&woocommerce directly.

![setup5](https://user-images.githubusercontent.com/25556606/127653348-b78cfc4b-d38e-4e4f-9c93-65014ab1d041.png)

## Any drawbacks?
Partially Yes! If you have multiple order from same customer just ship them all at once as much as possible. If you partially ship them (multiple tracking number) matching algorithm can fail but not mess up anything.
Secondly, be sure the customer info (first and last name) in the cargo information is correct and match with order info. Levenshtein matching algorithm will help you up to 3 characters. Keep in mind that If you have a large volume e-commerce platform you need deep integration solutions.

## Where is the Turkish translation?
Critical part such as success mails, fronted&admin side custom order status label supports Turkish. You are welcome to add support/contribute on Turkish translation of setup&logging&readme part.

## Features
- Interactive easy setup & automatically prepare environment & install needed packages for supported Linux distributions
- Adjustable user options like delivery_time, max_distance, job schedule timer, check --options
- User has full control over the automation with useful arguments, check --help
- Pluginless server side bash scripting solution, nothing is complex and costly, set and forget
- Auto two-way fulfillment workflow implementation with custom order status package
- Encryped sensetive data (REST,SOAP credentials) hardened as much as possible (credentials always headache in bash scripting)
- Powerful error handling for various checks like SOAP and REST API connections
- Easy debugging with useful search parameters
- Statistics via automation
- Support installation methods via cron, systemd
- Logrotate support
- HTML notify mails for shop manager
- Easily auto upgrade to latest version (also via cron job)
- Strong string matching logic (perl) via levenshtein distance function

![setup](https://user-images.githubusercontent.com/25556606/124499928-7e2c6080-ddc7-11eb-9df2-672a0f5ab2d1.png)

## Top-Level Directory & File Layout
    .
    ├── custom-order-status-package                        # Holds build-time dependencies (twoway)
    │   ├── aras-woo-delivered.php                           # Two-way installation
    │   ├── class-wc-delivered-status-order.php              # Two-way installation
    │   ├── fallback-order-status-sql.php                    # Two-way uninstallation
    │   ├── functions.php                                    # Two-way installation
    │   └── wc-customer-delivered-status-order.php           # Two-way installation
    ├── emails                                             # Holds runtime dependencies
    │   ├── delivered.min.html                               # Delivered html mail template
    │   └── shipped.min.html                                 # Shipped html mail template
    ├── lck                                                # Holds encrypted runtime dependencies
    ├── tmp                                                # Holds data for debugging
    ├── CHANGELOG                                          # Documentation file
    ├── README.md                                          # Documentation file
    ├── woo-aras-setup.sh                                  # Setup executable
    └── woocommerce-aras-cargo.sh                          # Main executable
 
## Hard Dependencies (may not included in default linux installations)
- curl
- perl-Text::Fuzzy>=0.29 --> perl module for string matching via levenshtein distance function
- jq>=1.6 --> simplify JSON parsing operations (careful to versioning)
- php, php-soap --> for creating SOAP client to get data from ARAS
- GNU awk>=5 (gawk in Ubuntu)
- GNU sed>=4.8
- whiptail (as also known (newt,libnewt))

## Recommended Tools
- mail --> for shop manager & system admin, need for important mail alerts (comes with mailutils linux package). If you use mutt, ssmtp, sendmail etc. please edit mail function as you wish.

## Tested Applications Versions
- wordpress>=5.7.2
- wocommerce>=5.5.1 
- woocommerce AST plugin>=3.2.5 (https://wordpress.org/plugins/woo-advanced-shipment-tracking/)

## Supported Linux Distributions
- Debian
- Ubuntu
- CentOS
- Fedora
- RHEL
- Arch
- Manjaro
- Gentoo
- SUSE
- openSUSE Leap
- openSUSE Tumbleweed

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
Please check and modify below settings before starting the setup. You can read the code comments in the script. We always keep these settings.
So it is enough to set one time, no need the re-adjust after upgrade. For mail notifications you need working mail server like postfix with 'mail' command which comes with mailutils linux package.
If you use mutt, ssmtp, sendmail etc. please edit mail function as you wish. You can find detailed info about below settings in script comments.

- delivery_time
- max_distance
- cron_minute
- cron_minute_update
- on_calendar
- wooaras_log
- company_name
- company_domain
- send_mail_command
- send_mail_err
- maxsize
- l_maxsize
- mail_to
- mail_from
- mail_subject_suc
- mail_subject_err

## Basic Usage
- Note your wordpress child theme absolute path for confirmation during setup (twoway)
- Get necessary credentials from ARAS commercial user control panel (https://esasweb.araskargo.com.tr/) (choose JSON fromat)
![araskargo-11](https://user-images.githubusercontent.com/25556606/125905483-99941283-cd59-4ac5-b9ea-afc54132dc7b.png)
- Enable WooCommerce REST API, get credentials (only support REST API v3)
- Adjust user defined settings such as mail_to, company_name as mentioned before
- Be sure you have some data both on woocommerce and ARAS for validations during setup (if not create test orders)
- Start the setup with one liner
- ```sudo bash < <(curl -Ssk https://raw.githubusercontent.com/hsntgm/woocommerce-aras-kargo/main/woo-aras-setup.sh)```
- or
- ```sudo bash < <(wget --no-check-certificate -q -O - https://raw.githubusercontent.com/hsntgm/woocommerce-aras-kargo/main/woo-aras-setup.sh)```

![woocommerce-aras-help](https://user-images.githubusercontent.com/25556606/135243353-2151f4c6-d916-466c-9ab6-5b6e5a5086fd.png)

## Debugging

If you encountered any errors such as long pending order which automation missed or orders updated with the wrong tracking code, you can easily use debugging parameters to display related log files.
Also use --status argument to check statistics and other useful informations about automation.

#### --force-shipped
In some cases, the orders in the status of processing are not marked as shipped on time, but these orders are in the status of delivered on the Aras Cargo side.
This breaks the two-way workflow. In short, these orders are never marked as shipped. If this is the case use the --force-shipped|-f argument to tailor the two-way workflow.

### Debugging Parameters:

```--force-shipped |-f```
```--debug-shipped |-g```
```--debug-delivered |-z```
```--status |-S```

![woocommerce-aras-istatistik](https://user-images.githubusercontent.com/25556606/134528100-8113adcb-c4bd-4414-a6dc-fc9e7574b585.png)

#### Usage
```./woocommerce-aras-cargo.sh --debug-shipped|--debug-delivered|-g|-z 'x[range]-month-year' 'ORDER_ID\|TRACKING_NUMBER' or (ORDER_ID || TRACKING_NUMBER)```

#### Example 1:
> filters 11th-19th of September dated shipped data for both suspicious order_id and tracking number  
```./woocommerce-aras-cargo.sh -g '1[1-9]-09-2021' '13241\|108324345362'```

#### Example 2:
> filters September 15 dated delivered data for suspicious tracking number  
```./woocommerce-aras-cargo.sh -z 15-09-2021 108324345362```

![debug_integration](https://user-images.githubusercontent.com/25556606/134054537-b1f3fc44-fa3f-42ac-bd94-62a08c4025fe.png)
