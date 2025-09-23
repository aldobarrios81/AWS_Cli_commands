#!/bin/bash
set -e

PROFILE=${2:-xxxxxxx}
REGION="us-east-1"

echo "=== Habilitando KMS Encryption para todos los CloudTrail en $REGION ==="
echo "Perfil: $PROFILE"

# Nombre único de la KMS Key
KMS_ALIAS="alias/cloudtrail-key"

# Verificar si ya existe la KMS Key
KMS_KEY_ID=$(aws kms list-aliases --profile "$PROFILE" --region "$REGION" \
  --query "Aliases[?AliasName=='$KMS_ALIAS'].TargetKeyId" --output text)

if [ -z "$KMS_KEY_ID" ]; then
    echo "-> Creando KMS Key para CloudTrail..."
    KMS_KEY_ID=$(aws kms create-key \
        --description "KMS Key for CloudTrail encryption" \
        --tags TagKey=Name,TagValue=CloudTrailKMS \
        --query KeyMetadata.KeyId --output text \
        --profile "$PROFILE" --region "$REGION")
    aws kms create-alias \
        --alias-name "$KMS_ALIAS" \
        --target-key-id "$KMS_KEY_ID" \
        --profile "$PROFILE" --region "$REGION"
    echo "   ✔ KMS Key creada: $KMS_KEY_ID"
else
    echo "✔ KMS Key existente: $KMS_KEY_ID"
fi

# Aplicar política de la KMS Key
cat > /tmp/cloudtrail-kms-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Id": "CloudTrailDefaultPolicy",
  "Statement": [
    {
      "Sid": "AllowCloudTrailUse",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": [
        "kms:GenerateDataKey*",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowAccountAdmin",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text --profile $PROFILE):root" },
      "Action": "kms:*",
      "Resource": "*"
    }
  ]
}
EOF

aws kms put-key-policy \
    --key-id "$KMS_KEY_ID" \
    --policy file:///tmp/cloudtrail-kms-policy.json \
    --profile "$PROFILE" --region "$REGION"

echo "✔ Política de KMS Key aplicada"

# Listar todos los trails en la región
TRAILS=$(aws cloudtrail describe-trails --query 'trailList[*].Name' --output text --profile "$PROFILE" --region "$REGION")

if [ -z "$TRAILS" ]; then
    echo "⚠ No se encontraron CloudTrail en $REGION"
    exit 0
fi

for TRAIL in $TRAILS; do
    echo "-> Habilitando KMS Encryption para el trail: $TRAIL"

    BUCKET=$(aws cloudtrail describe-trails --trail-name "$TRAIL" \
      --query 'trailList[0].S3BucketName' --output text --profile "$PROFILE" --region "$REGION")

    if [ -z "$BUCKET" ]; then
        echo "   ⚠ El trail $TRAIL no tiene bucket configurado, se omite"
        continue
    fi

    # Aplicar política al bucket
    cat > /tmp/cloudtrail-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": ["s3:GetBucketAcl"],
      "Resource": "arn:aws:s3:::$BUCKET"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": ["s3:PutObject"],
      "Resource": "arn:aws:s3:::$BUCKET/AWSLogs/$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)/*",
      "Condition": { "StringEquals": { "s3:x-amz-acl": "bucket-owner-full-control" } }
    }
  ]
}
EOF

    aws s3api put-bucket-policy \
      --bucket "$BUCKET" \
      --policy file:///tmp/cloudtrail-bucket-policy.json \
      --profile "$PROFILE" --region "$REGION"

    # Habilitar KMS en el trail
    aws cloudtrail update-trail \
        --name "$TRAIL" \
        --kms-key-id "$KMS_KEY_ID" \
        --profile "$PROFILE" \
        --region "$REGION"

    echo "   ✔ KMS habilitado para $TRAIL"
done

echo "=== Proceso completado ✅ ==="

