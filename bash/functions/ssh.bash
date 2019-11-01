delete_known_host_line () {
    sed -i".bak$(date -u '+%FT%TZ')" "$1"'d' ~/.ssh/known_hosts
}

##########################################################################
### ssh config ordering
###
### **NOTE:** Ordering is super finicky _everywhere_ in this file. Be
### extremely cautious about changing anything related to config ordering
##########################################################################

_ideEXP_ssh_config_bastion() {
  cat <<'EOF'
# If your local username doesn't match your username in production, you
# can either change your local username or add a section like the
# following to ~/.ssh/config
#
# Match host stitch-*,*.stitchdata.com,10.2.*
#   User <your production username> # like `User tvisher`

# stitch-prod AWS Primary VPC
Match host 10.*,stitch-*,*.stitchdata.com
  # forward your agent up to interact with git and ssh past the bastion.
  ForwardAgent yes
  # Don't wait around for awhile
  ConnectTimeout 5
  # These boxes change all the time and we don't care
  StrictHostKeyChecking no
  CheckHostIP no
  UpdateHostKeys no
  UserKnownHostsFile /dev/null
  # I never want to hear about your problems, ssh, until I do.
  LogLevel QUIET

Host app.sandbox.stitchdata.com
  # This goes through an ELB so we need to keep it alive
  ServerAliveInterval 30
  # Any time we establish a connection to this host (bastion), so long as
  # that connection is live, reuse it instead of establishing a new
  # one.
  ControlMaster auto
  ControlPath /tmp/ssh_mux_%h_%p_%r
  # By default, ControlMaster will terminate the shared connection as
  # soon as there are no more active connections to the server. This
  # gives us a 10 minute window after the last connection is closed
  # where we can continue to piggyback on it.
  ControlPersist 10m

Host stitch-bastion
  HostName bastion.stitchdata.com
  # Any time we establish a connection to this host (bastion), so long as
  # that connection is live, reuse it instead of establishing a new
  # one.
  ControlMaster auto
  ControlPath /tmp/ssh_mux_%h_%p_%r
  # By default, ControlMaster will terminate the shared connection as
  # soon as there are no more active connections to the server. This
  # gives us a 10 minute window after the last connection is closed
  # where we can continue to piggyback on it.
  ControlPersist 10m

Match host 10.2.*
  ProxyJump stitch-bastion

Match host 10.3.*
  ProxyJump app.sandbox.stitchdata.com

EOF
}

_ideEXP_ssh_aws_opsworks_describe_instances() {
  local stacks_json
  stacks_json=$(aws opsworks describe-stacks | jq '.Stacks[]')

  local layer_names_by_id
  layer_names_by_id=$(
    <<<"$stacks_json" jq -r '.StackId' |
      parallel -j 0 'aws opsworks describe-layers --stack-id={}' |
      jq '.Layers[]' |
      jq -s 'map({(.LayerId): .Name})
             | add'
                   )

  <<<"$stacks_json" jq -r '.StackId' |
    parallel -j 0 'aws opsworks describe-instances --stack-id={}' |
    jq '.Instances[]
        | select(.PrivateIp and .Hostname)
        | . + {
                ide_hostname: "stitch-\(.Hostname|gsub("_"; "-"))",
                ide_layer_name: ("stitch-\('"$layer_names_by_id"'[.LayerIds[0]]|gsub("_"; "-"))")
              }
        | select(.ide_layer_name != "stitch-bastion")'
}

_ideEXP_ssh_aws_opsworks_describe_layer_instances() {
  _ideEXP_ssh_aws_opsworks_describe_instances |
    jq -rs 'group_by(.ide_layer_name)[][0]'
}

_ideEXP_ssh_config_opsworks_instances() {
  _ideEXP_ssh_aws_opsworks_describe_instances |
    jq -r '"Host \(.ide_hostname)\n  HostName \(.PrivateIp)\n"'
}

_ideEXP_hosts_file_opsworks_instances() {
  _ideEXP_ssh_aws_opsworks_describe_instances |
    jq -r '"\(.PrivateIp) \(.ide_hostname)"'
}

_ideEXP_ssh_config_opsworks_layers() {
  _ideEXP_ssh_aws_opsworks_describe_layer_instances |
    jq -r '"Host \(.ide_layer_name)\n  HostName \(.PrivateIp)\n"'
}

_ideEXP_hosts_file_opsworks_layers() {
  _ideEXP_ssh_aws_opsworks_describe_layer_instances |
    jq -r '"\(.PrivateIp) \(.ide_layer_name)"'
}

_ideEXP_ssh_k8s_nodes_describe_instances() {
  local node_groups=(
    'nodes.kube.stitchdata.com'
    'nodes.staging-kube.stitchdata.com'
    'production_eks'
    'staging_eks'
  )

  aws_as_describe_groups_instances "${node_groups[@]}" |
    jq -r 'select(.PrivateIpAddress and (.State.Name == "running"))
           | . + {
                   Name:
                   ("stitch-k8s-\(.Tags|from_entries|.Name)-\(.PrivateIpAddress)"|gsub("[\\._]"; "-")),

                   GroupName:
                   ("stitch-k8s-\(.Tags|from_entries|."aws:autoscaling:groupName")"|gsub("[\\._]"; "-"))
                 }'
}

_ideEXP_ssh_k8s_nodes_describe_group_instances() {
  _ideEXP_ssh_k8s_nodes_describe_instances |
    jq -rs 'group_by(.GroupName)[][0]'
}

_ideEXP_ssh_config_k8s_nodes() {
  cat <<EOF
Match host stitch-k8s-nodes*,stitch-*-eks*
  ForwardAgent yes
  ConnectTimeout 5
  StrictHostKeyChecking no
  LogLevel QUIET
  UpdateHostKeys no
  UserKnownHostsFile /dev/null

Host stitch-staging-kube-bastion
  HostName bastion.staging-kube.stitchdata.com
  StrictHostKeyChecking no
  LogLevel QUIET
  UpdateHostKeys no
  UserKnownHostsFile /dev/null
  ServerAliveInterval 50
  User admin

Match host stitch-k8s-*-eks*
  User ec2-user

Match host stitch-k8s-nodes*
  User admin

Match host stitch-k8s-nodes-staging*
  ProxyJump stitch-staging-kube-bastion

EOF

  _ideEXP_ssh_k8s_nodes_describe_instances |
    jq -r '"Host \(.Name)\n  HostName \(.PrivateIpAddress)\n"'

  _ideEXP_ssh_k8s_nodes_describe_group_instances |
    jq -r '"Host \(.GroupName)\n  HostName \(.PrivateIpAddress)\n"'
}

_ideEXP_hosts_file_k8s_nodes() {
  _ideEXP_ssh_k8s_nodes_describe_instances |
    jq -r '"\(.PrivateIpAddress) \(.Name)"'

  _ideEXP_ssh_k8s_nodes_describe_group_instances |
    jq -r '"\(.PrivateIpAddress) \(.GroupName)"'
}

_ideEXP_ssh_config_all() {
  _ideEXP_ssh_config_k8s_nodes
  _ideEXP_ssh_config_opsworks_instances
  _ideEXP_ssh_config_opsworks_layers
  _ideEXP_ssh_config_bastion
}

_ideEXP_hosts_file_all() {
  _ideEXP_hosts_file_k8s_nodes
  _ideEXP_hosts_file_opsworks_instances
  _ideEXP_hosts_file_opsworks_layers
}

_ideEXP_ssh_config_all_disk() {
  _ideEXP_ssh_config_all | tee ~/.ssh/config.d/stitch.conf
}

_ideEXP_hosts_file_all_disk() {
   sudo sed -i.bak $'
/# BEGIN Stitch Hosts inserted by ide/,/# END Stitch Hosts inserted by ide/c\\\n# BEGIN Stitch Hosts inserted by ide\\\n'"$(
  _ideEXP_hosts_file_all | sed 's/$/\\/'
)"$'\n# END Stitch Hosts inserted by ide' /etc/hosts &&
     grep -F -- stitch- /etc/hosts
}
