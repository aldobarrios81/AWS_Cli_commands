#!/bin/bash
set -euo pipefail

# Variables
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
PROFILE="azcenit"
BUCKET_NAME="aws-config-logs-${ACCOUNT_ID}-${REGION}"
ROLE_NAME="AWSConfigRole"

echo "=== Verificando bucket S3 para AWS Config ==="
if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile $PROFILE 2>/dev/null; then
    echo "Bucket $BUCKET_NAME ya existe."
else
    echo "Creando bucket: $BUCKET_NAME ..."
    aws s3 mb "s3://$BUCKET_NAME" --region $REGION --profile $PROFILE
fi

echo "=== Verificando rol de servicio para AWS Config ==="
if aws iam get-role --role-name $ROLE_NAME --profile $PROFILE >/dev/null 2>&1; then
    echo "Rol $ROLE_NAME ya existe."
else
    echo "Creando rol $ROLE_NAME ..."
    aws iam create-role \
        --role-name $ROLE_NAME \
        --assume-role-policy-document '{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Service": "config.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
            }
          ]
        }' \
        --profile $PROFILE

    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSConfigRole \
        --profile $PROFILE || true

    aws iam attach-role-policy \
        --role-name $ROLE_NAME \
        --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess \
        --profile $PROFILE
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo "=== Creando configuration recorder con global resources ==="
aws configservice put-configuration-recorder \
  --configuration-recorder "{
    \"name\": \"default\",
    \"roleARN\": \"${ROLE_ARN}\",
    \"recordingGroup\": {
        \"allSupported\": true,
        \"includeGlobalResourceTypes\": true
    }
  }" \
  --region $REGION --profile $PROFILE

echo "=== Creando delivery channel ==="
aws configservice put-delivery-channel \
  --delivery-channel "{
    \"name\": \"default\",
    \"s3BucketName\": \"${BUCKET_NAME}\"
  }" \
  --region $REGION --profile $PROFILE

echo "=== Iniciando configuration recorder ==="
aws configservice start-configuration-recorder \
  --configuration-recorder-name default \
  --region $REGION --profile $PROFILE

echo "✅ AWS Config habilitado correctamente en $REGION"

