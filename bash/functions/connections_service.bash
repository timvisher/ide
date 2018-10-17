ssh_connection_service_instance() { _ide_deprecated ide_connections_service_ssh_instance "$@"; }
ide_connections_service_ssh_instance() { _ide_deprecated ide_connection_service_ssh_instance "$@"; }
ssh_connection_service_instances() { _ide_deprecated ide_connections_service_ssh_instances "$@"; }
ide_connections_service_ssh_instances() { _ide_deprecated ide_connection_service_ssh_instances "$@"; }
multi_exec_connection_service() { _ide_deprecated ide_connection_service_multi_exec "$@"; }
ide_connections_service_multi_exec() { _ide_deprecated ide_connection_service_multi_exec "$@"; }
ide_connections_service_connect_db() { _ide_deprecated ide_connection_service_db "$@"; }
_ide_ssh_define_common_service_functions webservices connection_service

aws_layer_status_connection_service() { _ide_deprecated ide_connections_service_layer_status "$@"; }
ide_connections_service_layer_status() {
    aws_layer_status webservices connection_service
}

aws_elb_instance_health_connection_service() { _ide_deprecated ide_connections_service_instance_health "$@";}
ide_connections_service_instance_health() { _ide_deprecated ide_connection_service_instance_health "$@"; }
ide_connection_service_instance_health() {
    aws_elb_instance_health connection-service "$@"
}

