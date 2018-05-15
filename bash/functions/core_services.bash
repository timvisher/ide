ide_core_services_web_ssh_instance() {
    ide_aws_opsworks_ssh_layer_instance webservices core_service "$@"
}

ide_core_services_web_connect_db() {
    ide_core_services_web_ssh_instance -t connect-db
}
ide_masterdb_connect() { ide_core_services_web_connect_db; }
ide_rjmadmin_connect() { ide_core_services_web_connect_db; }
