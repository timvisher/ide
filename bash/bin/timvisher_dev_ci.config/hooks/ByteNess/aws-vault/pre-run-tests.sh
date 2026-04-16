#!/usr/bin/env bash
# Clean stale aws-vault keychain entries before running tests.
#
# The post-integrate.sh hook also clears the keychain, but only
# fires on success.  This pre-hook ensures cleanup happens every
# run, even when tests fail.

set -euo pipefail

echo "--- aws-vault keychain cleanup ---"

# Remove aws-vault session and oidc-token entries from the login keychain.
count=0
while security delete-generic-password -s aws-vault login.keychain-db >/dev/null 2>&1
do
  (( count += 1 ))
done

if (( 0 < count ))
then
  echo "Removed $count aws-vault keychain item(s) from login"
else
  echo "No aws-vault keychain items found in login"
fi

# Remove the aws-vault-test keychain if it exists in the search
# list (created by go test and never cleaned up).
aws_vault_test_kc=$(
  security list-keychains |
    sed 's/^ *"//; s/"$//' |
    grep 'aws-vault-test\.keychain' || true
)

if [[ -n $aws_vault_test_kc ]]
then
  echo "Removing stale aws-vault-test keychain: $aws_vault_test_kc"
  security delete-keychain "$aws_vault_test_kc" 2>/dev/null || true
fi
