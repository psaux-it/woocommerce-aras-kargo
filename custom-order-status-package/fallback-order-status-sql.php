<?php

/** * woocommerce-aras-cargo-integration */
add_action('init', 'process_query');
	function process_query(){
		global $wpdb;
		$table_name = $wpdb->prefix . 'posts';
		$wpdb->query(
			$wpdb->prepare( "UPDATE $table_name SET post_status = 'wc-completed' WHERE post_type = 'shop_order' AND post_status = 'wc-delivered'" )
		);
	}
