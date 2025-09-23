#!/bin/bash
# enable-ecr-kms-encryption.sh
# Habilita cifrado KMS en todos los ECR Repositories

REGION="us-east-1"
PROFILE="xxxxxxxx"

# Key KMS que se usará para cifrado. Puede ser "alias/aws/ecr" o tu key propia
KMS_KEY="alias/aws/ecr"

echo "=== Habilitando KMS Encryption para ECR Repositories en $REGION ==="

# Listar todos los repositorios ECR
REPOS=$(aws ecr describe-repositories --region $REGION --profile $PROFILE --query 'repositories[].repositoryName' --output text)

for REPO in $REPOS; do
    echo "-> Verificando repositorio: $REPO"

    # Obtener info del repositorio
    INFO=$(aws ecr describe-repositories --repository-names $REPO --region $REGION --profile $PROFILE)
    
    # Revisar si ya tiene KMS habilitado
    ENCRYPTED=$(echo "$INFO" | jq -r '.repositories[0].encryptionConfiguration.kmsKey')
    if [ "$ENCRYPTED" != "null" ]; then
        echo "   ✔ Repositorio ya tiene KMS: $ENCRYPTED"
        continue
    fi

    # Actualizar repositorio para habilitar KMS encryption
    aws ecr put-image-scanning-configuration \
        --repository-name $REPO \
        --region $REGION \
        --profile $PROFILE \
        --image-scanning-configuration scanOnPush=true

    aws ecr put-encryption-configuration \
        --repository-name $REPO \
        --region $REGION \
        --profile $PROFILE \
        --encryption-configuration encryptionType=KMS,kmsKey=$KMS_KEY

    echo "   ✔ KMS habilitado para $REPO con KMS Key $KMS_KEY"
done

echo "✅ Proceso completado"

