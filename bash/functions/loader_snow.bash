ide_loader_snow_ssh_instance() {
    ide_aws_opsworks_ssh_layer_instance pipeline loader_snow "$@"
}

ide_loader_snow_ssh_instances() {
    ide_aws_opsworks_layer_ssh pipeline loader_snow "$@"
}

ide_loader_snow_multi_exec() {
    multi_exec_layer pipeline loader_snow "$@"
}

ide_loader_snow_connect_db() {
    ide_loader_snow_ssh_instance -t connect-db
}

ide_loader_snow_layer_status() {
    aws_layer_status pipeline loader_snow
}
