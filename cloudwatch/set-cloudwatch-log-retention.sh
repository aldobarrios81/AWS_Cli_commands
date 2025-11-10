#!/bin/bash
# set-cloudwatch-log-retention.sh
# Configura retención de logs para todos los CloudWatch Log Groups

PROFILE="xxxxxxx"
REGION="us-east-1"
RETENTION_DAYS=90  # Cambia el número de días según tu política

echo "=== Configurando retención de logs ($RETENTION_DAYS días) para todos los Log Groups en $REGION ==="

LOG_GROUPS=$(aws logs describe-log-groups \
    --query 'logGroups[*].logGroupName' \
    --output text \
    --profile $PROFILE \
    --region $REGION)

if [ -z "$LOG_GROUPS" ]; then
    echo "⚠ No se encontraron log groups en $REGION"
    exit 0
fi

for LOG_GROUP in $LOG_GROUPS; do
    echo "-> Configurando retención para Log Group: $LOG_GROUP"
    aws logs put-retention-policy \
        --log-group-name "$LOG_GROUP" \
        --retention-in-days $RETENTION_DAYS \
        --profile $PROFILE \
        --region $REGION
    echo "   ✔ Retención establecida para $LOG_GROUP"
done

echo "=== Retención de logs configurada en todos los Log Groups ✅ ==="

