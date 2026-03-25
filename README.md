### STATUS
[![woo-aras-setup.sh CI](https://github.com/psaux-it/woocommerce-aras-kargo/actions/workflows/test.yml/badge.svg)](https://github.com/psaux-it/woocommerce-aras-kargo/actions/workflows/test.yml)
# WooCommerce - Aras Cargo Integration

##### QUICK START - ONE LINER's
```sudo bash < <(curl -Ss https://psaux-it.github.io/woo-aras-setup.sh)```  
```sudo bash < <(wget -q -O - https://psaux-it.github.io/woo-aras-setup.sh)```

## What is the actual solution here exactly?

The aim of this pluginless bash scripting solution is effortlessly integrate WooCommerce and ARAS cargo with help of [free AST plugin](https://wordpress.org/plugins/woo-advanced-shipment-tracking/). Note that this is not a deep integrate solution. Instead of syncing your order with Aras end just listens ARAS for newly created cargo tracking numbers and match them with application (WooCommerce) side customer info.
This solution best suits to small-mid size e-commerce business. Keep in mind that If you have a large volume e-commerce business you need deep integration solutions.

<img width="3616" height="2176" alt="Image" src="https://github.com/user-attachments/assets/89f161f9-2435-486c-8bc7-5294e854bea1" />

> This automation updates woocomerce order status 'processing' to 
> 'completed/shipped', when the matching cargo tracking code is 
> generated on the ARAS Kargo end. Attachs cargo information 
> (tracking number, track link etc.) to order completed/shipped e-mail with the
> help of AST plugin and notify customer. If you implemented
> two-way fulfillment workflow, script goes one layer up and updates order status 'shipped'
> to 'delivered' and notify customer via second mail. Simply you don't need to add cargo 
> tracking number manually and update order status via WooCommerce orders dashboard.
> The aim of script is automating the process fully.

---

## What are the supported workflows?

In default if the cargo on the way (tracking number generated on ARAS end) automation will update order status processing to completed. If you use default workflow there is no need to create any custom order status.

If you are implementing two-way workflow 'processing -> shipped -> delivered' we need to do some extra stuff that explained below.

<img width="3981" height="1821" alt="Image" src="https://github.com/user-attachments/assets/86bcaba6-d949-4d4f-9bf2-f7f8373a0d7f" />

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
cp custom-order-status-package/fallback-order-status-sql.php /var/www/html/wp-content/themes/my-child/woocommerce/
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
//woo_aras_include_once( get_stylesheet_directory() .'/woocommerce/fallback-order-status-sql.php');
// woocommerce-aras-cargo-integration
```

Configure AST plugin and ENABLE --> Rename the "Completed" Order status label to "Shipped". If everything seems ok lastly enable workflow via;

```
sudo ./woocommerce-aras-cargo.sh --twoway-enable
```

## Requirements During Interactive Setup
- WooCommerce REST API Key (v3)
- WooCommerce REST API Secret (v3)
- Wordpress Site URL (format in www.my-ecommerce.com)
- ARAS SOAP API Password
- ARAS SOAP API Username
- ARAS SOAP Endpoint URL (wsdl) (get from ARAS commercial user control panel)
- ARAS SOAP Merchant Code
- ARAS SOAP Query Type (restricted to 12/13)

