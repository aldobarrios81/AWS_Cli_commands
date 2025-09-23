#!/bin/bash
# Habilita AWS Config en us-east-1 e incluye recursos globales
# Uso: ./enable-aws-config-us-east-1-global.sh <ACCOUNT_ID> <AWS_PROFILE>

set -euo pipefail

ACCOUNT_ID="$1"
PROFILE="$2"
REGION="us-east-1"
ROLE_NAME="AWSConfigRole"
BUCKET_NAME="awsconfig-logs-${ACCOUNT_ID}-$(date +%s)"

echo "=== Habilitando AWS Config en ${REGION} con recursos globales ==="
echo "Cuenta: ${ACCOUNT_ID} | Perfil: ${PROFILE} | Bucket: ${BUCKET_NAME}"

# 1. Crear bucket (sin LocationConstraint en us-east-1)
aws s3api create-bucket \
  --bucket "${BUCKET_NAME}" \
  --region "${REGION}" \
  --profile "${PROFILE}" >/dev/null
echo "   ✔ Bucket creado"

# 2. Bucket policy
cat > /tmp/awsconfig-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "config.amazonaws.com"},
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ],
      "Condition": {
        "StringEquals": {
          "AWS:SourceAccount": "${ACCOUNT_ID}"
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket "${BUCKET_NAME}" \
  --policy file:///tmp/awsconfig-bucket-policy.json \
  --profile "${PROFILE}"
echo "   ✔ Bucket policy aplicada"

# 3. Rol IAM
if ! aws iam get-role --role-name "${ROLE_NAME}" --profile "${PROFILE}" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "${ROLE_NAME}" \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {"Service": "config.amazonaws.com"},
          "Action": "sts:AssumeRole"
        }
      ]
    }' \
    --profile "${PROFILE}"
  aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSConfigRole \
    --profile "${PROFILE}"
  echo "   ✔ Rol IAM creado y policy adjunta"
else
  echo "   ✔ Rol IAM ${ROLE_NAME} ya existe"
fi

# 4. Configuration Recorder con JSON (booleans reales)
cat > /tmp/config-recorder.json <<EOF
{
  "name": "default",
  "roleARN": "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}",
  "recordingGroup": {
    "allSupported": true,
    "includeGlobalResourceTypes": true
  }
}
EOF

aws configservice put-configuration-recorder \
  --configuration-recorder file:///tmp/config-recorder.json \
  --region "${REGION}" \
  --profile "${PROFILE}"
echo "   ✔ Configuration recorder configurado (incluye globales)"

# 5. Delivery Channel
cat > /tmp/config-delivery.json <<EOF
{
  "name": "default",
  "s3BucketName": "${BUCKET_NAME}"
}
EOF

aws configservice put-delivery-channel \
  --delivery-channel file:///tmp/config-delivery.json \
  --region "${REGION}" \
  --profile "${PROFILE}"
echo "   ✔ Delivery channel creado"

# 6. Iniciar grabación
aws configservice start-configuration-recorder \
  --configuration-recorder-name default \
  --region "${REGION}" \
  --profile "${PROFILE}"
echo "   ✔ Grabación iniciada"

echo "=== AWS Config habilitado en ${REGION} (recursos globales incluidos) con bucket ${BUCKET_NAME} ==="

