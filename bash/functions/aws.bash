stack_names() {
    aws opsworks describe-stacks | jq --compact-output --raw-output --monochrome-output '.Stacks[] | .Name'
}

stack_name() {
    local sid="$1"
    aws opsworks describe-stacks --stack-id "$sid" | jq -r '.Stacks[] | .Name'
}

stack_id() {
    local name="$1"
    aws opsworks describe-stacks \
        | jq --monochrome-output --raw-output '.Stacks[] | select(.Name == "'"$name"'") | .StackId'
}

stack_ids() {
    aws opsworks describe-stacks | jq --monochrome-output --raw-output '.Stacks[] | .StackId'
}

stack_json() {
    aws opsworks describe-stacks \
        | jq '.Stacks[] | select(.CustomJson) | {StackId, Name, CustomJson: (.CustomJson | fromjson)}'
}

stack_layers() {
    local stack_name="$1"
    local stack_id="$(stack_id "$stack_name")"

    aws opsworks describe-layers --stack-id "$stack_id"
}

layer_id() {
    local stack_id="$1"
    local layer_name="$2"
    stack_layers "$stack_id" \
        | jq -r '.Layers[] | select(.Name == "'"$layer_name"'") | .LayerId'
}

layer_instances() {
    local stack_name="$1"
    local stack_id="$(stack_id "$stack_name")"
    local layer_name="$2"

    aws opsworks describe-instances --layer-id "$(layer_id "$stack_id" "$layer_name")"
}

ssh_layer_instances() {
    local stack_name="$1"
    local layer_name="$2"

    layer_instances "$stack_name" "$layer_name" | \
        jq --compact-output --raw-output --monochrome-output \
           '.Instances[] | select(.PrivateIp) | @sh "ssh \(.PrivateIp) # \(.Hostname)"'
}

layer_instances_ips() {
    local stack_name="$1"
    local layer_name="$2"

    layer_instances "$stack_name" "$layer_name" | \
        jq --compact-output --raw-output --monochrome-output \
           '.Instances[] | select(.PrivateIp) | .PrivateIp'
}

create_and_start_instance() {
    local stack_name="$1"
    local stack_id="$(stack_id "$stack_name")"
    local layer_name="$2"
    local instance_type="$3"

    new_instance_id="$(aws opsworks \
      create-instance \
      --stack-id "$stack_id" \
      --layer-ids $(layer_id "$stack_id" "$layer_name") \
      --instance-type "$instance_type" \
    | jq -r '.InstanceId')"

    aws opsworks start-instance --instance-id "$new_instance_id"
}

# left as an example for now
new_data_warehouse_service_instance() {
    create_and_start_instance primary data_warehouse_service m3.medium
}

layer_json() {
    for stack_id in $(stack_ids)
    do
        stack_layers "$stack_id" \
            | jq '.Layers[] | select(.CustomJson) | {StackId, Name, CustomJson: (.CustomJson | fromjson)}'
    done
}

layer_custom_recipes() {
    local stack_id="$1"
    stack_layers "$stack_id" \
        | jq '.Layers[]
          | {StackId,
             Name,
             CustomRecipes: (.CustomRecipes
                             | [.Undeploy,
                                .Setup,
                                .Configure,
                                .Shutdown,
                                .Deploy]
                             | flatten)}'
}


stack_instance_id() {
    local stack_id="$1"
    aws opsworks describe-instances --stack-id "$stack_id"
}

ssh_stack_instances() {
    local stack_name="$1"
    aws opsworks describe-instances --stack-id "$(stack_id "$stack_name")" \
        | jq --compact-output --raw-output --monochrome-output \
             '.Instances[] | select(.PrivateIp) | @sh "ssh \(.PrivateIp) # \(.Hostname)"'
}

ssh_matching_instances() {
    local stack_name="$1"
    local pattern="$2"

    ssh_stack_instances "$stack_name" | grep -F "$pattern"
}

instance_id() {
    local stack_id="$1"
    local instance_hostname="$2"

    aws opsworks describe-instances --stack-id "$stack_id" \
        | jq -r '.Instances[] | select(.Hostname == "'"$instance_hostname"'") | .InstanceId'
}

stop_instance() {
    local stack_id="$(stack_id "$1")"
    local hostname="$2"
    local instance_id="$(instance_id "$stack_id" "$2")"

    aws opsworks stop-instance --instance-id "$instance_id"
}

instance_ips() {
    for stack_id in $(stack_ids)
    do
        aws opsworks describe-instances --stack-id="$stack_id" \
            | jq --compact-output '.Instances[] | select(.PrivateIp) | {Hostname, PrivateIp, StackId, Ec2InstanceId}'
    done \
        | sort
}
