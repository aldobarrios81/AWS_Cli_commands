#!/usr/bin/env bash
#
# Habilita AWS Config en TODAS las regiones
# 1. Crea bucket S3 central con nombre único
# 2. Aplica política de escritura
# 3. Activa Config en cada región

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    exit 1
fi

PROFILE="$1"
CENTRAL_REGION="us-east-1"

# Verificar credenciales
if ! aws sts get-caller-identity --profile "$PROFILE" > /dev/null 2>&1; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --profile $PROFILE)

BUCKET_NAME="central-awsconfig-logs-$ACCOUNT_ID-$(date +%s)"
echo "=== Habilitando AWS Config en todas las regiones ==="
echo "Perfil: $PROFILE | Bucket: $BUCKET_NAME | Región bucket: $CENTRAL_REGION"

echo "-> Creando bucket S3 central..."
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region $CENTRAL_REGION \
  --profile $PROFILE
echo "   ✔ Bucket creado"

echo "-> Aplicando política al bucket..."
cat > /tmp/config-bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSConfigBucketPermissionsCheck",
      "Effect": "Allow",
      "Principal": { "Service": "config.amazonaws.com" },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::$BUCKET_NAME"
    },
    {
      "Sid": "AWSConfigBucketDelivery",
      "Effect": "Allow",
      "Principal": { "Service": "config.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/AWSLogs/$ACCOUNT_ID/*",
      "Condition": { "StringEquals": { "s3:x-amz-acl": "bucket-owner-full-control" } }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --bucket "$BUCKET_NAME" \
  --policy file:///tmp/config-bucket-policy.json \
  --profile $PROFILE
echo "   ✔ Política aplicada"

echo "-> Activando AWS Config en todas las regiones..."
# ✅ Región fija solo para listar regiones
REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text --region $CENTRAL_REGION --profile $PROFILE)

for REGION in $REGIONS; do
  echo "   Región: $REGION"

  aws configservice put-delivery-channel \
    --delivery-channel-name default \
    --s3-bucket-name $BUCKET_NAME \
    --config-snapshot-delivery-properties deliveryFrequency=TwentyFour_Hours \
    --profile $PROFILE \
    --region $REGION

  aws configservice put-configuration-recorder \
    --configuration-recorder name=default,roleARN="arn:aws:iam::$ACCOUNT_ID:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig" \
    --recording-group allSupported=true,includeGlobalResourceTypes=true \
    --profile $PROFILE \
    --region $REGION

  aws configservice start-configuration-recorder \
    --configuration-recorder-name default \
    --profile $PROFILE \
    --region $REGION

  echo "      ✔ AWS Config habilitado en $REGION"
done

echo "=== Proceso finalizado. Bucket central: $BUCKET_NAME ==="

