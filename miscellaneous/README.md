# WooCommerce - Aras Cargo Integration
> We need column command from util-linux package not bsdmainutils

This is a known issue with Debian based distributions.
They use column command from bsdmainutils.
https://bugs.launchpad.net/ubuntu/+source/util-linux/+bug/1705437

'column' compiled from 'util-linux-2.37.2'
https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.37/util-linux-2.37.2.tar.gz

If you don't trust this source, you can compile the source code yourself.
