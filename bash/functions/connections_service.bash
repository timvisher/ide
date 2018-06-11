ssh_connection_service_instance() {
    _ide_deprecated ide_connections_service_ssh_instance "$@"
}
ide_connections_service_ssh_instance() {
    ide_aws_opsworks_ssh_layer_instance webservices connection_service "$@"
}

ssh_connection_service_instances() {
    _ide_deprecated ide_connections_service_ssh_instances "$@"
}
ide_connections_service_ssh_instances() {
    ide_aws_opsworks_layer_ssh webservices connection_service "$@"
}

multi_exec_connection_service() {
    _ide_deprecated ide_connections_service_multi_exec "$@"
}
ide_connections_service_multi_exec() {
    multi_exec_layer webservices connection_service "$@"
}

ide_connections_service_connect_db() {
    ide_connections_service_ssh_instance -t connect-db
}

aws_layer_status_connection_service() {
    _ide_deprecated ide_connections_service_layer_status "$@"
}
ide_connections_service_layer_status() {
    aws_layer_status webservices connection_service
}

aws_elb_instance_health_connection_service() {
    _ide_deprecated ide_connections_service_instance_health "$@"
}
ide_connections_service_instance_health() {
    aws_elb_instance_health connection-service "$@"
}
