#!/bin/bash
# enable-cloudwatch-kms-fixed.sh
# Habilita KMS SSE para todos los CloudWatch Log Groups en us-east-1

set -e

PROFILE="azcenit"
REGION="us-east-1"
KMS_ALIAS="cloudwatch-logs-key"

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
    
    # Crear política para CloudWatch Logs
    echo "-> Configurando política de KMS para CloudWatch Logs..."
    KMS_POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "Enable IAM User Permissions",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::'$ACCOUNT_ID':root"
                },
                "Action": "kms:*",
                "Resource": "*"
            },
            {
                "Sid": "Allow CloudWatch Logs",
                "Effect": "Allow",
                "Principal": {
                    "Service": "logs.'$REGION'.amazonaws.com"
                },
                "Action": [
                    "kms:Encrypt",
                    "kms:Decrypt",
                    "kms:ReEncrypt*",
                    "kms:GenerateDataKey*",
                    "kms:DescribeKey"
                ],
                "Resource": "*",
                "Condition": {
                    "ArnEquals": {
                        "kms:EncryptionContext:aws:logs:arn": "arn:aws:logs:'$REGION':'$ACCOUNT_ID':log-group:*"
                    }
                }
            }
        ]
    }'
    
    aws kms put-key-policy --profile $PROFILE --region $REGION \
        --key-id "$KMS_KEY" --policy-name default --policy "$KMS_POLICY"
    
    echo "   ✔ Política de KMS configurada"
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

