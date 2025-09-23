#!/bin/bash
# enable-dynamodb-pitr.sh
# Habilita Point-In-Time Recovery (PITR) para todas las tablas DynamoDB en us-east-1

REGION="us-east-1"
PROFILE="xxxxxxxx"

echo "=== Habilitando Point-In-Time Recovery para todas las tablas DynamoDB en $REGION ==="

# Listar todas las tablas
TABLES=$(aws dynamodb list-tables --region $REGION --profile $PROFILE --query 'TableNames[]' --output text)

for TABLE in $TABLES; do
    echo "-> Habilitando PITR para tabla: $TABLE"
    aws dynamodb update-continuous-backups \
        --region $REGION \
        --profile $PROFILE \
        --table-name "$TABLE" \
        --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
    echo "   ✔ PITR habilitado en $TABLE"
done

echo "✅ Point-In-Time Recovery habilitado para todas las tablas DynamoDB"

