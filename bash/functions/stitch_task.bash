ide_stitch_task_clone_connection() {
    local client_id connection_id

    client_id="$1"
    connection_id="$2"

    eval "$(ide_connection_service_ssh_instance \
              stitch_task clone_connection \
              --target-host=10.10.10.4 \
              "$client_id" "$connection_id") -s" \
        | jq -r '@sh "./run-it check \(.id)"'
}
