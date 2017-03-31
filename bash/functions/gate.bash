#!/usr/bin/env bash

gate_dead_letters_count() {
    dead_letters=$(aws s3api list-objects --bucket com-stitchdata-prod-gate-dead-letters)
    if [[ -n $dead_letters ]]
    then
        jq '.Contents | length' <<<"$dead_letters"
    else
        echo 0
    fi
}

gate_sample_dead_letters() {
    while read -r key
    do
        aws s3 cp s3://com-stitchdata-prod-gate-dead-letters/"$(jq -r '.Key' <<<"$key")" - | jq '. | del(.body) | . + {LastModified: "'"$(jq -r '.LastModified' <<<"$key")"'", Key: "'"$(jq -r '.Key' <<<"$key")"'"}'
    done < <(aws s3api list-objects --bucket com-stitchdata-prod-gate-dead-letters | jq -rc '.Contents[range(0;(.Contents | length);(.Contents | length / 24 | floor))] | {Key, LastModified}')
}

gate_dead_letters_report() {
    # 25 dead letters
    while read -r dead_letter
    do
        dead_letter=$(jq '. | select(."response-body" != "circuit-breaker :fallback-s3 tripped") | del(.body) | . + {"response-body": (."response-body" | fromjson | . + {"stack-trace": (."stack-trace" | split("\n"))})}')
        if [[ -n $dead_letter ]]
        then
            jq '. | {Key, LastModified, message: (."response-body" | .message), "stack-trace": [(."response-body"."stack-trace"[range(9)])]}' <<<"$dead_letter"
        fi
    done < <(gate_sample_dead_letters | jq --slurp -rc '.[]')
}

gate_replay_dead_letters() {
    gate_instance_exec --force 'source /etc/default/pipeline-gate && java -Xmx1g -cp /opt/deploy/pipeline-gate/pipeline-gate-service-standalone.jar com.rjmetrics.pipeline.gate.tools.replay -b com-stitchdata-prod-gate-dead-letters'
}
