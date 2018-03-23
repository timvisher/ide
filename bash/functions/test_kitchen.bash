ide_test_kitchen_list_instances() {
    aws_ec2_describe_instances \
        | jq 'select("test-kitchen" == (
                  select(.Tags) |
                  .Tags[] |
                  select("created-by" == .Key) |
                  .Value
              )) |
              select(.State.Name != "terminated") |
              {InstanceId, LaunchTime}'
}
