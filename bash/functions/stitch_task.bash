ide_stitch_task_clone_connection() {
    local client_id connection_id

    client_id="$1"
    connection_id="$2"

    api_host=${API_HOST:-10.10.10.4}

    eval "$(ide_connection_service_ssh_instance \
              stitch_task clone_connection \
              --target-host="${api_host}" \
              "$client_id" "$connection_id") -s" \
        | jq -r '@sh "./run-it check \(.id)"'
}

ide_stitch_task_connection_info() {
  local client_id connection_id

  client_id="$1"
  connection_id="$2"

  ide_connection_service_ssh_instance \
    stitch_task connection_info \
    --connection_id "$connection_id" \
    "$client_id"
}

ide_stitch_task_clone_state() {
  local source_client_id source_connection_id target_client_id target_connection_id prod_state local_state_version

  source_client_id="$1"
  source_connection_id="$2"
  target_client_id="$3"
  target_connection_id="$4"

  api_host=${API_HOST:-10.10.10.4}
  token=${STITCH_DEV_TOKEN:-$dev_token}

  prod_state=$(
    ide_menagerie_ssh_instance stitch_task clone_state \
                               --target-host="http://${api_host}:5033" \
                               "$source_client_id" \
                               "$source_connection_id" \
        | jq '.state')

  local_state_version=$(
    stitch_task clone_state \
                --target-host="http://${api_host}:5033" \
                "$target_client_id" \
                "$target_connection_id" \
        | jq '.version')

  curl -X PUT \
       -s "http://${api_host}:5033/menagerie/public/v1/clients/$target_client_id/connections/$target_connection_id/state" \
       -d '{"state": '"$prod_state"' , "version": '"$local_state_version"'}' \
       -H 'Authorization: Bearer '"$token"'' \
       -H 'Content-Type: application/json' \
       -H 'User-Agent: stitch-task-clone-state' \
       -H 'Accept-Encoding: gzip, deflate' > /dev/null
}

ide_stitch_task_clone_field_selection() {
  local dry_run source_client_id source_connection_id target_client_id target_connection_id import_token ui_token

  dry_run=true
  if [[ "$#" -eq 5 ]] && [ "$1" = '-N' ]
  then
      unset dry_run
      shift
  fi

  source_client_id="$1"
  source_connection_id="$2"
  target_client_id="$3"
  target_connection_id="$4"

  api_host=${API_HOST:-10.10.10.4}
  token=${STITCH_DEV_TOKEN:-$dev_token}

  import_token=$(curl -H 'Authorization: Bearer '"$token"'' \
                      -s "http://${api_host}:5003/clients/$target_client_id/connections/$target_connection_id" \
                     | jq -r '.import_token')
  raw_ui_token=$(curl -H 'Content-Type: application/json' \
                      -d '{"email":"spoolz-mcdata@talend.com","password":"abc123"}' \
                      -v "http://${api_host}:8443/session" 2>&1 \
                     | grep -o 'DASHSESS2=\w*;' \
                     | sed 's/DASHSESS2=//')
  ui_token="${raw_ui_token%;}"

  ide_connection_service_ssh_instance \
      stitch_task clone_field_selection \
      --target-host="http://${api_host}:5033"  \
      --import-token="$import_token" \
      --ui-token="$ui_token" \
      --target-client-id="$target_client_id" \
      --target-connection-id="$target_connection_id" \
      "$source_client_id" "$source_connection_id" \
      > ./the-cloned-selection

  if [[ -n $dry_run ]]
  then
      echo 'DRY RUN: Created ./the-cloned-selection'
  else
    bash ./the-cloned-selection > /dev/null && rm ./the-cloned-selection
    echo 'Done'
  fi
}

ide_stitch_task_mirror_prod() {
  local client_id connection_id dev_client dev_conn

  client_id="$1"
  connection_id="$2"

  dev_client=3
  dev_conn=$(ide_stitch_task_clone_connection "$client_id" "$connection_id" | grep -Eo '[[:digit:]]+')
  ide_stitch_task_clone_field_selection -N "$client_id" "$connection_id" "$dev_client" "$dev_conn"
  ide_stitch_task_clone_state "$client_id" "$connection_id" "$dev_client" "$dev_conn"
}
