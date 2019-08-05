delete_known_host_line () {
    sed -i".bak$(date -u '+%FT%TZ')" "$1"'d' ~/.ssh/known_hosts
}

ide_ssh_regenerate_stitch_opsworks_config() {
  mkdir -p ~/.ssh/config.d
  ide_aws_opsworks_instance_ips \
    | jq -r '"Host \(.Hostname)\n  HostName \(.PrivateIp)\n"' \
    | tee ~/.ssh/config.d/stitch_opsworks
}
