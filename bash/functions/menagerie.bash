ide_menagerie_ssh_instance() {
    ide_aws_opsworks_ssh_layer_instance webservices menagerie "$@"
}

ide_menagerie_connect_db() {
    ide_menagerie_ssh_instance -t connect-db
}
