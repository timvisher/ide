#!/usr/bin/env bash

webhookz_dead_letters_count() {
    dead_letters=$(aws s3api list-objects --bucket com-stitchdata-prod-webhookz-dead-letters)
    if [[ -n $dead_letters ]]
    then
        jq '.Contents | length' <<<"$dead_letters"
    else
        echo 0
    fi
}

webhookz_sample_dead_letters() {
    while read -r key
    do
        aws s3 cp s3://com-stitchdata-prod-webhookz-dead-letters/"$(jq -r '.Key' <<<"$key")" - | jq '. | del(.body) | . + {LastModified: "'"$(jq -r '.LastModified' <<<"$key")"'", Key: "'"$(jq -r '.Key' <<<"$key")"'"}'
    done < <(aws s3api list-objects --bucket com-stitchdata-prod-webhookz-dead-letters | jq -rc '.Contents[range(0;(.Contents | length);(.Contents | length / 24 | floor))] | {Key, LastModified}')
}

webhookz_dead_letters_report() {
    # 25 dead letters
    while read -r dead_letter
    do
        dead_letter=$(jq '. | select(."response-body" != "circuit-breaker :fallback-s3 tripped") | del(.body) | . + {"response-body": (."response-body" | fromjson | . + {"stack-trace": (."stack-trace" | split("\n"))})}')
        if [[ -n $dead_letter ]]
        then
            jq '. | {Key, LastModified, message: (."response-body" | .message), "stack-trace": [(."response-body"."stack-trace"[range(9)])]}' <<<"$dead_letter"
        fi
    done < <(webhookz_sample_dead_letters | jq --slurp -rc '.[]')
}

webhookz_dead_letters_replay() {
    webhookz_instance_exec --force 'source /etc/default/webhookz && java -Xmx1g -cp /opt/deploy/webhookz/webhookz-standalone.jar com.stitchdata.webhookz.tools.dead_letters -b com-stitchdata-prod-webhookz-dead-letters'
}
