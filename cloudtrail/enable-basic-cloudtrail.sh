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

echo "=== Habilitando CloudTrail Básico para Console Auth Monitoring ==="
echo "Perfil: $PROFILE | Account ID: $ACCOUNT_ID | Región: $REGION"
echo ""

# Nombres únicos
TRAIL_NAME="cloudtrail-${PROFILE}-console-auth"
BUCKET_NAME="cloudtrail-logs-${ACCOUNT_ID}-${PROFILE}"
LOG_GROUP_NAME="/aws/cloudtrail/${TRAIL_NAME}"

echo "🪣 Paso 1: Creando S3 bucket para CloudTrail logs..."

# Crear bucket S3
if aws s3api head-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
    echo "✅ Bucket ya existe: $BUCKET_NAME"
else
    echo "📦 Creando bucket: $BUCKET_NAME"
    
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" --region "$REGION"
    else
        aws s3api create-bucket --bucket "$BUCKET_NAME" --profile "$PROFILE" --region "$REGION" \
            --create-bucket-configuration LocationConstraint="$REGION"
    fi
    
    if [ $? -eq 0 ]; then
        echo "✅ Bucket creado exitosamente"
    else
        echo "❌ Error creando bucket"
        exit 1
    fi
fi

echo ""
echo "🔒 Paso 2: Configurando políticas del bucket..."

# Política para permitir que CloudTrail escriba al bucket
cat > /tmp/cloudtrail-bucket-policy.json <<EOF
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
            "Resource": "arn:aws:s3:::${BUCKET_NAME}"
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
                    "s3:x-amz-acl": "bucket-owner-full-control"
                }
            }
        }
    ]
}
EOF

aws s3api put-bucket-policy --bucket "$BUCKET_NAME" --policy file:///tmp/cloudtrail-bucket-policy.json --profile "$PROFILE"

if [ $? -eq 0 ]; then
    echo "✅ Política del bucket configurada"
else
    echo "❌ Error configurando política del bucket"
    exit 1
fi

echo ""
echo "📝 Paso 3: Creando CloudWatch Log Group..."

# Crear log group para CloudWatch
aws logs create-log-group --log-group-name "$LOG_GROUP_NAME" --profile "$PROFILE" --region "$REGION" 2>/dev/null || echo "Log group ya existe"

# Crear o verificar el rol de servicio para CloudTrail
echo ""
echo "🔐 Paso 4: Configurando rol de servicio para CloudWatch logs..."

ROLE_NAME="CloudTrail_CloudWatchLogs_Role"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# Verificar si el rol existe
if aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" 2>/dev/null; then
    echo "✅ Rol de servicio ya existe: $ROLE_NAME"
else
    echo "🔧 Creando rol de servicio: $ROLE_NAME"
    
    # Crear política de confianza
    cat > /tmp/cloudtrail-trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

    # Crear el rol
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document file:///tmp/cloudtrail-trust-policy.json \
        --profile "$PROFILE"

    # Crear política para escribir a CloudWatch
    cat > /tmp/cloudtrail-logs-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogGroup",
                "logs:CreateLogStream"
            ],
            "Resource": "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}:*"
        }
    ]
}
EOF

    # Crear la política
    aws iam create-policy \
        --policy-name "CloudTrailLogsPolicy" \
        --policy-document file:///tmp/cloudtrail-logs-policy.json \
        --profile "$PROFILE" 2>/dev/null || echo "Política ya existe"

    # Adjuntar la política al rol
    aws iam attach-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/CloudTrailLogsPolicy" \
        --profile "$PROFILE"

    echo "✅ Rol de servicio configurado"
fi

echo ""
echo "🛤️ Paso 5: Creando CloudTrail..."

# Crear el trail
TRAIL_RESULT=$(aws cloudtrail create-trail \
    --name "$TRAIL_NAME" \
    --s3-bucket-name "$BUCKET_NAME" \
    --cloud-watch-logs-log-group-arn "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:${LOG_GROUP_NAME}:*" \
    --cloud-watch-logs-role-arn "$ROLE_ARN" \
    --include-global-service-events \
    --is-multi-region-trail \
    --enable-log-file-validation \
    --profile "$PROFILE" \
    --region "$REGION" 2>&1)

if echo "$TRAIL_RESULT" | grep -q "TrailARN"; then
    echo "✅ CloudTrail creado exitosamente: $TRAIL_NAME"
else
    if echo "$TRAIL_RESULT" | grep -q "already exists"; then
        echo "✅ CloudTrail ya existe: $TRAIL_NAME"
    else
        echo "❌ Error creando CloudTrail: $TRAIL_RESULT"
        exit 1
    fi
fi

echo ""
echo "🚀 Paso 6: Iniciando logging..."

# Iniciar el logging
aws cloudtrail start-logging --name "$TRAIL_NAME" --profile "$PROFILE" --region "$REGION"

if [ $? -eq 0 ]; then
    echo "✅ Logging iniciado exitosamente"
else
    echo "❌ Error iniciando logging"
fi

echo ""
echo "🔍 Paso 7: Verificación final..."

# Verificar estado
TRAIL_STATUS=$(aws cloudtrail get-trail-status --name "$TRAIL_NAME" --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text)

echo "📊 Estado del trail: $TRAIL_STATUS"
echo "🪣 S3 Bucket: $BUCKET_NAME"
echo "📝 CloudWatch Log Group: $LOG_GROUP_NAME"

if [ "$TRAIL_STATUS" = "true" ]; then
    echo ""
    echo "🎉 ¡CloudTrail configurado exitosamente!"
    echo "✅ Console authentication events se registrarán en CloudWatch"
    echo "✅ Ya puedes ejecutar el script de console auth failures monitoring"
    echo ""
    echo "🔧 Próximo paso:"
    echo "./general/setup-console-auth-failures-monitoring.sh $PROFILE"
else
    echo ""
    echo "⚠️ CloudTrail creado pero logging no está activo"
    echo "Verifica la configuración manualmente"
fi

echo ""
echo "=== Configuración CloudTrail completada ==="

# Limpiar archivos temporales
rm -f /tmp/cloudtrail-*.json