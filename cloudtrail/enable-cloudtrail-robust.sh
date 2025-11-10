#!/bin/bash

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    exit 1
fi

PROFILE="$1"
REGION="us-east-1"

# Verificar credenciales
if ! aws sts get-caller-identity --profile "$PROFILE" > /dev/null 2>&1; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")

echo "=== Habilitando CloudTrail Completo - ${PROFILE} ==="
echo "Account ID: $ACCOUNT_ID | Región: $REGION"
echo ""

# Nombres únicos
TRAIL_NAME="console-auth-trail-${PROFILE}"
BUCKET_NAME="aws-cloudtrail-logs-${ACCOUNT_ID}-${PROFILE}"

echo "🪣 Paso 1: Configurando S3 bucket para CloudTrail..."

# Verificar si el bucket ya existe
if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
    echo "✅ Bucket ya existe: $BUCKET_NAME"
else
    echo "📦 Creando bucket: $BUCKET_NAME"
    
    # Crear bucket
    aws s3api create-bucket \
        --bucket "$BUCKET_NAME" \
        --profile "$PROFILE" \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "✅ Bucket creado exitosamente"
    else
        echo "❌ Error creando bucket"
        exit 1
    fi
    
    # Configurar public access block
    echo "🔒 Configurando seguridad del bucket..."
    aws s3api put-public-access-block \
        --bucket "$BUCKET_NAME" \
        --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --profile "$PROFILE"
fi

echo ""
echo "🔐 Paso 2: Configurando política del bucket S3..."

# Crear política del bucket para CloudTrail
cat > /tmp/cloudtrail-s3-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailAclCheck",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketAcl",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudtrail:${REGION}:${ACCOUNT_ID}:trail/${TRAIL_NAME}"
                }
            }
        },
        {
            "Sid": "AWSCloudTrailWrite",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}/AWSLogs/${ACCOUNT_ID}/*",
            "Condition": {
                "StringEquals": {
                    "s3:x-amz-acl": "bucket-owner-full-control",
                    "AWS:SourceArn": "arn:aws:cloudtrail:${REGION}:${ACCOUNT_ID}:trail/${TRAIL_NAME}"
                }
            }
        },
        {
            "Sid": "AWSCloudTrailGetBucketLocation",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "s3:GetBucketLocation",
            "Resource": "arn:aws:s3:::${BUCKET_NAME}",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudtrail:${REGION}:${ACCOUNT_ID}:trail/${TRAIL_NAME}"
                }
            }
        }
    ]
}
EOF

# Aplicar política
aws s3api put-bucket-policy \
    --bucket "$BUCKET_NAME" \
    --policy file:///tmp/cloudtrail-s3-policy.json \
    --profile "$PROFILE"

if [ $? -eq 0 ]; then
    echo "✅ Política S3 configurada correctamente"
else
    echo "❌ Error configurando política S3"
    exit 1
fi

echo ""
echo "🛤️ Paso 3: Creando CloudTrail..."

# Verificar si el trail ya existe
EXISTING_TRAIL=$(aws cloudtrail describe-trails \
    --trail-name "$TRAIL_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'trailList[0].Name' \
    --output text 2>/dev/null)

if [ "$EXISTING_TRAIL" = "$TRAIL_NAME" ]; then
    echo "✅ Trail ya existe: $TRAIL_NAME"
else
    echo "🔧 Creando nuevo trail: $TRAIL_NAME"
    
    # Crear el trail
    TRAIL_RESULT=$(aws cloudtrail create-trail \
        --name "$TRAIL_NAME" \
        --s3-bucket-name "$BUCKET_NAME" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        --profile "$PROFILE" \
        --region "$REGION" 2>&1)
    
    if echo "$TRAIL_RESULT" | grep -q "TrailARN"; then
        echo "✅ Trail creado exitosamente"
    else
        echo "❌ Error creando trail: $TRAIL_RESULT"
        exit 1
    fi
fi

echo ""
echo "🚀 Paso 4: Iniciando logging..."

# Iniciar logging
START_RESULT=$(aws cloudtrail start-logging \
    --name "$TRAIL_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" 2>&1)

if [ $? -eq 0 ]; then
    echo "✅ Logging iniciado exitosamente"
else
    echo "⚠️ Error iniciando logging: $START_RESULT"
fi

echo ""
echo "🔍 Paso 5: Verificación final..."

# Verificar estado del trail
TRAIL_STATUS=$(aws cloudtrail get-trail-status \
    --name "$TRAIL_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" 2>/dev/null)

if [ $? -eq 0 ]; then
    IS_LOGGING=$(echo "$TRAIL_STATUS" | jq -r '.IsLogging // false')
    LATEST_DELIVERY=$(echo "$TRAIL_STATUS" | jq -r '.LatestDeliveryTime // "N/A"')
    
    echo "📊 Estado del Trail:"
    echo "   Trail: $TRAIL_NAME"
    echo "   Bucket: $BUCKET_NAME" 
    echo "   Logging activo: $IS_LOGGING"
    echo "   Última entrega: $LATEST_DELIVERY"
    
    if [ "$IS_LOGGING" = "true" ]; then
        echo ""
        echo "🎉 ¡CloudTrail configurado exitosamente!"
        echo "✅ Los eventos de ConsoleLogin se registrarán en S3"
        echo ""
        echo "📝 IMPORTANTE: Para console authentication failures monitoring"
        echo "   necesitas también habilitar CloudWatch Logs integration"
        echo ""
        echo "🔧 Próximos pasos opcionales:"
        echo "1. Configurar CloudWatch Logs (para log metric filters)"
        echo "2. Ejecutar console auth failures monitoring:"
        echo "   ./general/setup-console-auth-failures-monitoring.sh $PROFILE"
        echo ""
        echo "✅ CloudTrail básico está funcionando y registrando eventos"
    else
        echo ""
        echo "⚠️ CloudTrail creado pero logging no está activo"
        echo "Revisa los permisos y configuración"
    fi
else
    echo "❌ Error verificando estado del trail"
fi

echo ""
echo "=== Configuración CloudTrail completada ==="

# Limpiar archivos temporales
rm -f /tmp/cloudtrail-s3-policy.json