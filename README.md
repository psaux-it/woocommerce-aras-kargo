[![Build Status](https://travis-ci.com/hsntgm/woocommerce-aras-kargo.svg?token=pex9yoGqJVyVQgXxYi7X&branch=main)](https://travis-ci.com/github/hsntgm/woocommerce-aras-kargo)

# WooCommerce - Aras Cargo Integration
## Pluginless pure server side bash script  solution #root
[![N|Solid](https://www.cyberciti.biz/media/new/category/old/terminal.png)](https://www.psauxit.com) 

The aim of this bash script solution is effortlessly integrate WooCommerce and ARAS cargo with help of AST plugin. With some drawbacks still very useful for low volume e-commerce platforms. Hope the further version will not have any drawback. Note that this is not a deep integrate solution. Instead of syncing your order with Aras end just listens ARAS for newly created cargo tracking numbers and match them with application (WooCommerce) side customer info. 

## What is the actual solution here exactly?
> This automation updates woocomerce order status from processing to completed (REST),
> when the matching cargo tracking code is generated on the ARAS Cargo end (SOAP).
> Attachs cargo information (tracking number, track link etc.) to
> order completed e-mail with the help of AST plugin (REST) and notify customer.
> Simply you don't need to manually add cargo tracking number and update order status
> via WooCommerce orders dashboard. The aim of script is automating the process fully.

## Is this approach works %100? What is the drawback?
Not yet! As mentioned this is not a deep integration solution. And deep integration costs you money! For now useful for low volume e-commerce platforms. The actual drawback is we haven't any linked uniq string on both sides other than name,surname,telephone number. If we have multiple orders which on processing status from same customer we cannot match order with exact tracking number and you have to take manual actions.

## How to get rid of drawback?
Is Aras cargo able to insert/link your woocommerce order id while receiving to cargo? We need to link order on both side with uniq string. Also ARAS end must return this uniq string to match. If this is possible please contribute or simply keep in touch with me for implementation.

## What is the current workflow?
In default if cargo on the way (tracking number generated on ARAS end) we update order status processing to completed. So we assume order is completed. Currently script doesn't support custom shipment status like 'shipped'. If you use this kind of workflow wait for further versions. I will implement three-way (processing-shipped-completed) workflow in next releases.   

## Will mess up anything?
No! Interactive setup will ask you to validate some parsed data. If you don't validate the data installation part will be skipped. This solution never ever touch any core files of wordpress or woocommerce. You can uninstall any time you want.

![setup5](https://user-images.githubusercontent.com/25556606/124501159-baf95700-ddc9-11eb-81ce-84c5b9117639.png)

## Features
- Interactive easy setup
- Encrypt all sensetive data (REST,SOAP credentials) also never seen on bash history. Doesn't keep any sensetive data on files.
- Powerful error handling for various checks like SOAP and REST API connections
- Auto installation methods via cron, systemd
- Adds logrotate if you have
- Pluginless pure server side bash solution, no need any deep integration effort that cost you money
- HTML notify mails for updated orders, errors
- Easily auto upgrade to latest version

![setup](https://user-images.githubusercontent.com/25556606/124499928-7e2c6080-ddc7-11eb-9df2-672a0f5ab2d1.png) ![setup4](https://user-images.githubusercontent.com/25556606/124500396-61445d00-ddc8-11eb-92eb-de3af3ff3d63.png)

## Hard Dependencies
- bash
- curl
- openssl
- jq
- php
- iconv
- pstree
- gnu sed
- gnu awk
- stat
- woocommerce AST plugin

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
![help](https://user-images.githubusercontent.com/25556606/124503366-175e7580-ddce-11eb-8e3c-fcd01bde6028.png)
