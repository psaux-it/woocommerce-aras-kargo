<?php

/** * woocommerce-aras-cargo-integration */

add_action('init', 'register_order_status');
add_filter('wc_order_statuses', 'add_delivered_to_order_statuses');
add_filter('woocommerce_reports_order_statuses', 'include_custom_order_status_to_reports', 20, 1);
add_filter('woocommerce_order_is_paid_statuses', 'delivered_woocommerce_order_is_paid_statuses');
add_filter('bulk_actions-edit-shop_order', 'add_bulk_actions', 50, 1 );

/*** Register new status : Delivered
**/
function register_order_status()
{
	register_post_status('wc-delivered', array(
		'label' => __('Teslim Edildi', 'text-domain'),
		'public' => true,
		'show_in_admin_status_list' => true,
		'show_in_admin_all_list' => true,
		'exclude_from_search' => false,
		'label_count' => _n_noop('Teslim Edildi <span class="count">(%s)</span>', 'Teslim Edildi <span class="count">(%s)</span>', 'text-domain')
	));
}

/*
* add status after completed
*/
function add_delivered_to_order_statuses($order_statuses)
{
	$new_order_statuses = array();
	foreach ($order_statuses as $key => $status) {
		$new_order_statuses[$key] = $status;
		if ('wc-completed' === $key) {
			$new_order_statuses['wc-delivered'] = __('Teslim Edildi', 'text-domain');
		}
	}
	return $new_order_statuses;
}

/*
* Adding the custom order status to the default woocommerce order statuses
*/
function include_custom_order_status_to_reports($statuses)
{
	if ($statuses)
		$statuses[] = 'delivered';
	return $statuses;
}

/*
* mark status as a paid.
*/
function delivered_woocommerce_order_is_paid_statuses($statuses)
{
	$statuses[] = 'delivered';
	return $statuses;
}

/* add bulk action
* Change order status to delivered
*/
function add_bulk_actions( $bulk_actions )
{
	$lable = wc_get_order_status_name( 'delivered' );
	$bulk_actions['mark_delivered'] = __( 'Olarak işaretle ' . $lable . '', 'text-domain' );
	return $bulk_actions;
}

/**
* Class My_Custom_Status_WC_Email
*/
class Delivered_WC_Email
{
	/**
	* Delivered_WC_Email constructor.
	*/
	public function __construct() {
		// Filtering the emails and adding our own email.
		add_filter( 'woocommerce_email_classes', array( $this, 'register_email' ), 90, 1 );
		// Absolute path to the plugin folder.
		define( 'DELIVERED_WC_EMAIL_PATH', trailingslashit( get_stylesheet_directory() ) );
	}

	/**
	* @param array $emails
	*
	* @return array
	*/
	public function register_email( $emails ) {
		require_once DELIVERED_WC_EMAIL_PATH.'woocommerce/emails/class-wc-delivered-status-order.php';
		$emails['WC_Delivered_status_Order'] = new WC_Delivered_status_Order();
		return $emails;
	}
}
new Delivered_WC_Email();

/** * woocommerce-aras-cargo-integration */
