#!/bin/bash
# enable-cloudwatch-kms-fixed.sh
# Habilita KMS SSE para todos los CloudWatch Log Groups en us-east-1

set -e

PROFILE=${1:-xxxxxxx}
REGION=${2:-us-east-1}
KMS_ALIAS=${3:-cloudwatch-logs-key}

echo "=== Habilitando KMS SSE para CloudWatch Log Groups en $REGION ==="
echo "Perfil: $PROFILE | Alias de KMS: $KMS_ALIAS"

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query Account --output text)

# Verificar si la KMS Key ya existe
KMS_KEY=$(aws kms list-aliases --profile $PROFILE --region $REGION \
    --query "Aliases[?AliasName=='alias/$KMS_ALIAS'].TargetKeyId" --output text)

if [ -z "$KMS_KEY" ]; then
    echo "-> Creando KMS Key con alias $KMS_ALIAS..."
    KMS_KEY=$(aws kms create-key --profile $PROFILE --region $REGION \
        --description "KMS Key para CloudWatch Log Groups" \
        --query KeyMetadata.KeyId --output text)
    aws kms create-alias --profile $PROFILE --region $REGION \
        --alias-name "alias/$KMS_ALIAS" --target-key-id "$KMS_KEY"
    echo "   ✔ KMS Key creada: $KMS_KEY"
else
    echo "✔ KMS Key ya existe: $KMS_KEY"
fi

# Construir ARN completo de la KMS Key
KMS_ARN="arn:aws:kms:$REGION:$ACCOUNT_ID:key/$KMS_KEY"

# Listar todos los log groups
LOG_GROUPS=$(aws logs describe-log-groups --profile $PROFILE --region $REGION \
    --query 'logGroups[*].logGroupName' --output text)

# Asociar KMS Key a cada Log Group
for LOG_GROUP in $LOG_GROUPS; do
    echo "-> Habilitando SSE-KMS para Log Group: $LOG_GROUP"
    set +e
    aws logs associate-kms-key --profile $PROFILE --region $REGION \
        --log-group-name "$LOG_GROUP" \
        --kms-key-id "$KMS_ARN"
    if [ $? -eq 0 ]; then
        echo "   ✔ SSE habilitado para $LOG_GROUP"
    else
        echo "   ⚠ Error habilitando SSE para $LOG_GROUP"
    fi
    set -e
done

echo "=== Proceso completado ✅ ==="

