#!/bin/sh
# One-shot init for go-sync: waits for DynamoDB Local, creates the table from
# dynamodb-table.json (copy of upstream schema/dynamodb/table.json) if it does
# not exist yet, and enables TTL on ExpirationTime. Idempotent. Runs in the
# official amazon/aws-cli image; credentials are DynamoDB Local dummies.
set -eu
EP="${AWS_ENDPOINT:-http://dynamodb:8000}"
TABLE="${TABLE_NAME:-client-entity}"

i=0
until aws dynamodb list-tables --endpoint-url "$EP" >/dev/null 2>&1; do
    i=$((i + 1))
    if [ "$i" -ge 60 ]; then
        echo "go-sync init: DynamoDB Local not reachable at $EP" >&2
        exit 1
    fi
    sleep 2
done

if aws dynamodb describe-table --table-name "$TABLE" --endpoint-url "$EP" >/dev/null 2>&1; then
    echo "go-sync init: table $TABLE already exists"
    exit 0
fi

sed "s/\"client-entity-dev\"/\"${TABLE}\"/" /init/dynamodb-table.json > /tmp/table.json
aws dynamodb create-table --cli-input-json file:///tmp/table.json --endpoint-url "$EP" >/dev/null
aws dynamodb update-time-to-live --table-name "$TABLE" \
    --time-to-live-specification "Enabled=true, AttributeName=ExpirationTime" \
    --endpoint-url "$EP" >/dev/null
echo "go-sync init: table $TABLE created"
