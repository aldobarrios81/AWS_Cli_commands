#!/bin/bash
set -euo pipefail

PROFILE="azcenit"
CENTRAL_REGION="us-east-1"

# ID de cuenta para un nombre único
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")
LOG_BUCKET="central-s3-logs-${ACCOUNT_ID}"

echo "=== Habilitando S3 Access Logging en todos los buckets ==="
echo "Perfil: $PROFILE  |  Región central: $CENTRAL_REGION"
echo "Bucket central: $LOG_BUCKET"
echo

# 1. Crear bucket de logs central si no existe
if ! aws s3api head-bucket --bucket "$LOG_BUCKET" --profile "$PROFILE" 2>/dev/null; then
  echo "-> Creando bucket de logs: $LOG_BUCKET en $CENTRAL_REGION"

  if [ "$CENTRAL_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
      --bucket "$LOG_BUCKET" \
      --region "$CENTRAL_REGION" \
      --profile "$PROFILE"
  else
    aws s3api create-bucket \
      --bucket "$LOG_BUCKET" \
      --region "$CENTRAL_REGION" \
      --create-bucket-configuration LocationConstraint=$CENTRAL_REGION \
      --profile "$PROFILE"
  fi

  # Bloqueo de acceso público y versioning
  aws s3api put-public-access-block \
    --bucket "$LOG_BUCKET" \
    --public-access-block-configuration '{
      "BlockPublicAcls": true,
      "IgnorePublicAcls": true,
      "BlockPublicPolicy": true,
      "RestrictPublicBuckets": true
    }' \
    --profile "$PROFILE"

  aws s3api put-bucket-versioning \
    --bucket "$LOG_BUCKET" \
    --versioning-configuration Status=Enabled \
    --profile "$PROFILE"
fi

# 2. Permitir logs de S3
aws s3api put-bucket-policy \
  --bucket "$LOG_BUCKET" \
  --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Principal\": {\"Service\": \"logging.s3.amazonaws.com\"},
        \"Action\": \"s3:PutObject\",
        \"Resource\": \"arn:aws:s3:::${LOG_BUCKET}/*\",
        \"Condition\": {\"StringEquals\": {\"aws:SourceAccount\": \"$ACCOUNT_ID\"}}
      }
    ]
  }" \
  --profile "$PROFILE"

# 3. Listar y habilitar logging en todos los buckets
BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text --profile "$PROFILE")

for b in $BUCKETS; do
  if [ "$b" != "$LOG_BUCKET" ]; then
    echo ">>> Habilitando logs en: $b"
    aws s3api put-bucket-logging \
      --bucket "$b" \
      --bucket-logging-status "{
        \"LoggingEnabled\": {
          \"TargetBucket\": \"$LOG_BUCKET\",
          \"TargetPrefix\": \"$b/\"
        }
      }" \
      --profile "$PROFILE"
  else
    echo ">>> Saltando bucket central: $b"
  fi
done

echo
echo "=== Proceso completado. Todos los buckets envían logs a s3://$LOG_BUCKET/ ==="

