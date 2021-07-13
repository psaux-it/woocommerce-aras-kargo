<?php
if ( ! defined( 'ABSPATH' ) ) {
        exit; // Exit if accessed directly
}

if ( ! class_exists( 'WC_Email' ) ) {
        return;
}

/**
 * Class WC_Custom_Completed_Order
 */
class WC_Delivered_status_Order extends WC_Email {

        /**
         * Create an instance of the class.
         *
         * @access public
         * @return void
         */
        function __construct() {
                // Email slug we can use to filter other data.
                // Replace 'my-custom-status' with your custom order status slug
                // Replace 'My Custom Status' with your custom order status name
                $this->id          = 'wc_customer_delivered_status_order';
                $this->title       = __( 'Delivered Order to Customer', 'text-domain' );
                $this->description = __( 'An email sent to the customer when an order status change to Delivered.', 'text-domain' );
                // For admin area to let the user know we are sending this email to customers.
                $this->customer_email = true;
                $this->heading     = __( 'Delivered Status', 'text-domain' );
                // translators: placeholder is {blogname}, a variable that will be substituted when email is sent out
                $this->subject     = sprintf( _x( '[%s] Delivered Status', 'default email subject for delivered status emails sent to the customer', 'text-domain' ), '{blogname}' );

    // Template paths.
                $this->template_html  = 'emails/wc-customer-delivered-status-order.php';
                $this->template_plain = 'emails/plain/wc-customer-delivered-status-order.php';
                $this->template_base  = DELIVERED_WC_EMAIL_PATH . 'templates/';

    // Action to which we hook onto to send the email.
                add_action( 'woocommerce_order_status_delivered', array( $this, 'trigger' ) );

                parent::__construct();
        }

         /**
         * Trigger Function that will send this email to the customer.
         *
         * @access public
         * @return void
         */
        function trigger( $order_id ) {
                $this->object = wc_get_order( $order_id );

                if ( version_compare( '3.0.0', WC()->version, '>' ) ) {
                        $order_email = $this->object->billing_email;
                } else {
                        $order_email = $this->object->get_billing_email();
                }

                $this->recipient = $order_email;


                if ( ! $this->is_enabled() || ! $this->get_recipient() ) {
                        return;
                }

                $this->send( $this->get_recipient(), $this->get_subject(), $this->get_content(), $this->get_headers(), $this->get_attachments() );
        }

        /**
         * Get content html.
         *
         * @access public
         * @return string
         */
        public function get_content_html() {
                return wc_get_template_html( $this->template_html, array(
                        'order'         => $this->object,
                        'email_heading' => $this->get_heading(),
                        'sent_to_admin' => false,
                        'plain_text'    => false,
                        'email'                 => $this
                ), '', $this->template_base );
        }

        /**
         * Get content plain.
         *
         * @return string
         */
        public function get_content_plain() {
                return wc_get_template_html( $this->template_plain, array(
                        'order'         => $this->object,
                        'email_heading' => $this->get_heading(),
                        'sent_to_admin' => false,
                        'plain_text'    => true,
                        'email'                 => $this
                ), '', $this->template_base );
        }
}
