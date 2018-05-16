ide_spool_ssh_instance() {
    ide_aws_opsworks_ssh_layer_instance webservices spool_service "$@"
}

ide_spool_connect_db() {
    ide_spool_ssh_instance -t connect-db
}
