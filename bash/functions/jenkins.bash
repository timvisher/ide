aws_jenkins_ip() { _ide_deprecated ide_jenkins_instance_ip "$@"; }
ide_jenkins_instance_ip() {
    ide_aws_opsworks_layer_instances_ips deployment jenkins_master
}

ssh_jenkins_instance() { _ide_deprecated ide_jenkins_ssh_instance "$@"; }
ide_jenkins_ssh_instance() {
    eval "$(ide_aws_opsworks_layer_ssh deployment jenkins_master "$@")"
}
ide_ssh_jenkins_instance() { ide_jenkins_ssh_instance "$@"; }

aws_layer_status_jenkins_master() {
    _ide_deprecated ide_jenkins_layer_status "$@";
}
ide_jenkins_layer_status() {
    ide_aws_opsworks_layer_status deployment jenkins_master
}

aws_elb_instance_health_jenkins_stitchdata_com() {
    _ide_deprecated ide_jenkins_elb_instance_health "$@";
}
ide_jenkins_elb_instance_health() {
    ide_aws_elb_instance_health jenkins-stitchdata-com
}
