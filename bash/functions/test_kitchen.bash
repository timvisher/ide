ide_test_kitchen_list_instances() {
    aws ec2 describe-instances \
        --filters 'Name=tag:created-by,Values=test-kitchen' \
        'Name=instance-state-name,Values=running' \
        | jq '.Reservations[].Instances[] | {InstanceId,LaunchTime}'
}
