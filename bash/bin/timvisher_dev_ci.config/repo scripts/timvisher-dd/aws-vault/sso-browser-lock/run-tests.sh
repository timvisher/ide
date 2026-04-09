#!/usr/bin/env bash

source ~/.functions/logging.bash ||
  {
    echo "Unable to source logging functions" >&2
    exit 1
  }

cd "$(git rev-parse --show-toplevel)" || exit 1

echo "--- vet ---"
make vet || exit 1

echo "--- test ---"
make test || exit 1

timvisher_EXP_wait_for_connectivity binaries.ddbuild.io 443 ||
  die "Couldn't connect to in time"

ls -lA aws-vault

info 'Building aws-vault'

go build -o aws-vault . ||
  die "Couldn't build aws-vault"

ls -lA aws-vault

./aws-vault --version

while security delete-generic-password -s aws-vault login
do
  ((count+=1))
done
if (( 0 < count ))
then
  echo "Removed $count aws-vault keychain item(s) from login"
else
  echo "No aws-vault keychain items found in login"
fi
