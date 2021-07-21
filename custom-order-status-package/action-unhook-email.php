<?php
add_action( 'woocommerce_email', 'unhook_those_pesky_emails' );
function unhook_those_pesky_emails( $email_class ) {
        remove_action( 'woocommerce_order_status_completed_notification', array( $email_class->emails['WC_Email_Customer_Completed_Order'], 'trigger' ) );
}
