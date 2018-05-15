boxcutter_optimization_queue() {
    if [[ -z $1 ]]
    then
        # shellcheck disable=SC2016
        curl --silent \
             http://172.16.10.202:8080/job/Boxcutter%20--%20Rebuild/lastSuccessfulBuild/artifact/artifacts/chef-run-report.json \
            | jq '.all_resources
                  | group_by(.json_class)
                  | [ .[]
                      | reduce .[] as $i (
                        {json_class: "", elapsed_time: 0};
                        {json_class: $i.json_class, elapsed_time: (
                          .elapsed_time + $i.instance_vars.elapsed_time)})]
                  | sort_by(.elapsed_time) | reverse | .[:10]'
    else
        # shellcheck disable=SC2016
        jq '.all_resources
            | group_by(.json_class)
            | [ .[]
                | reduce .[] as $i (
                  {json_class: "", elapsed_time: 0};
                  {json_class: $i.json_class,
                   elapsed_time: (
                     .elapsed_time + $i.instance_vars.elapsed_time)})]
            | sort_by(.elapsed_time) | reverse | .[:10]' < "$1"
    fi
}
