#!/bin/bash
# enable-ec2-ebs-dlm-backup.sh
# Configura DLM para snapshots automáticos de EC2 y EBS en us-east-1

REGION="us-east-1"
PROFILE="xxxxxxxx"

# Parámetros del policy
DESCRIPTION="DLM policy for automatic snapshots of EC2 EBS volumes"
EXECUTION_ROLE_ARN="arn:aws:iam::xxxxxxxxxxxxx:role/AWSDataLifecycleManagerDefaultRole"
TARGET_TAG_KEY="Backup"
TARGET_TAG_VALUE="True"
SCHEDULE_NAME="DailyBackup"
RETENTION_COUNT=7   # cantidad de snapshots a retener

echo "=== Configurando DLM para respaldos automáticos de EC2 y EBS en $REGION ==="

aws dlm create-lifecycle-policy \
    --region $REGION \
    --profile $PROFILE \
    --description "$DESCRIPTION" \
    --state ENABLED \
    --execution-role-arn $EXECUTION_ROLE_ARN \
    --policy-details "{
        \"ResourceTypes\": [\"VOLUME\"],
        \"TargetTags\": [{\"Key\": \"$TARGET_TAG_KEY\", \"Value\": \"$TARGET_TAG_VALUE\"}],
        \"Schedules\": [{
            \"Name\": \"$SCHEDULE_NAME\",
            \"CreateRule\": {\"Interval\": 24, \"IntervalUnit\": \"HOURS\"},
            \"RetainRule\": {\"Count\": $RETENTION_COUNT}
        }]
    }"

echo "✅ DLM configurado para respaldos automáticos de EC2 y volúmenes EBS"

