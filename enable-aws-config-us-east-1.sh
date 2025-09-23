#!/bin/bash
set -euo pipefail

ACCOUNT_ID="${1:?Falta ID de cuenta}"
PROFILE="${2:?Falta perfil AWS CLI}"
REGION="us-east-1"

BUCKET="awsconfig-logs-${ACCOUNT_ID}-${RANDOM}"
ROLE="AWSConfigRole"

echo "=== Habilitando AWS Config en $REGION ==="
echo "Cuenta: $ACCOUNT_ID | Perfil: $PROFILE | Bucket: $BUCKET"

# 1. Crear bucket S3
aws s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --profile "$PROFILE"
echo "   ✔ Bucket creado"

# 2. Aplicar bucket policy para AWS Config
echo "-> Aplicando bucket policy..."
cat > /tmp/awsconfig-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${BUCKET}/*",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "${ACCOUNT_ID}"
        }
      }
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "config.amazonaws.com"
      },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::${BUCKET}"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket "$BUCKET" \
  --policy file:///tmp/awsconfig-bucket-policy.json \
  --profile "$PROFILE"
echo "   ✔ Bucket policy aplicada"

# 3. Crear rol si no existe
if ! aws iam get-role --role-name "$ROLE" --profile "$PROFILE" >/dev/null 2>&1; then
  echo "-> Creando rol IAM $ROLE..."
  aws iam create-role \
    --role-name "$ROLE" \
    --assume-role-policy-document '{
      "Version":"2012-10-17",
      "Statement":[{
        "Effect":"Allow",
        "Principal":{"Service":"config.amazonaws.com"},
        "Action":"sts:AssumeRole"
      }]
    }' \
    --profile "$PROFILE"

  aws iam attach-role-policy \
    --role-name "$ROLE" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSConfigRole \
    --profile "$PROFILE"
  echo "   ✔ Rol IAM creado y políticas adjuntas"
else
  echo "   ✔ Rol IAM $ROLE ya existe"
fi

# 4. Configuration Recorder
echo "-> Creando configuration recorder..."
aws configservice put-configuration-recorder \
  --configuration-recorder '{
    "name": "default",
    "roleARN": "arn:aws:iam::'"$ACCOUNT_ID"':role/'"$ROLE"'",
    "recordingGroup": {
      "allSupported": true,
      "includeGlobalResourceTypes": true
    }
  }' \
  --region "$REGION" \
  --profile "$PROFILE"

# 5. Delivery Channel
echo "-> Creando delivery channel..."
aws configservice put-delivery-channel \
  --delivery-channel '{
    "name": "default",
    "s3BucketName": "'"$BUCKET"'"
  }' \
  --region "$REGION" \
  --profile "$PROFILE"

# 6. Start Recorder
aws configservice start-configuration-recorder \
  --configuration-recorder-name default \
  --region "$REGION" \
  --profile "$PROFILE"

echo "=== AWS Config habilitado en $REGION con bucket $BUCKET ==="

