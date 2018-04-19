ide_sourcerer_service_ssh_instance() {
    ssh_layer_instance webservices sourcerer_service "$@"
}

ide_sourcerer_service_connect_db() {
    ide_sourcerer_service_ssh_instance -t connect-db
}

# ide_sourcerer_workers_connect_db() {
#     # FIXME
#     false
# }
