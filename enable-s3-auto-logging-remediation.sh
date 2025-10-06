#!/bin/bash

# Auto-remediación para S3 Bucket Logging
# Detecta buckets sin logging y habilita automáticamente el access logging

set -e

PROFILE="azcenit"
REGION="us-east-1"
LOG_BUCKET_SUFFIX="-access-logs"

echo "=== Implementando Auto-Remediación para S3 Bucket Logging ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Crear bucket principal para logs si no existe
MAIN_LOG_BUCKET="s3-access-logs-${ACCOUNT_ID}-${REGION}"
echo ""
echo "-> Verificando bucket de logs principal: $MAIN_LOG_BUCKET"

if aws s3api head-bucket --bucket "$MAIN_LOG_BUCKET" --profile $PROFILE --region $REGION 2>/dev/null; then
    echo "   ✔ Bucket de logs ya existe: $MAIN_LOG_BUCKET"
else
    echo "   -> Creando bucket de logs: $MAIN_LOG_BUCKET"
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "$MAIN_LOG_BUCKET" \
            --profile $PROFILE \
            --region $REGION 2>/dev/null || true
    else
        aws s3api create-bucket \
            --bucket "$MAIN_LOG_BUCKET" \
            --profile $PROFILE \
            --region $REGION \
            --create-bucket-configuration LocationConstraint=$REGION 2>/dev/null || true
    fi
    
    # Configurar política del bucket de logs
    cat > /tmp/log-bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3ServerAccessLogsPolicy",
            "Effect": "Allow",
            "Principal": {
                "Service": "logging.s3.amazonaws.com"
            },
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${MAIN_LOG_BUCKET}/*",
            "Condition": {
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:s3:::*"
                },
                "StringEquals": {
                    "aws:SourceAccount": "$ACCOUNT_ID"
                }
            }
        },
        {
            "Sid": "S3ServerAccessLogsPolicyGetBucketAcl",
            "Effect": "Allow",
            "Principal": {
                "Service": "logging.s3.amazonaws.com"
            },
            "Action": [
                "s3:GetBucketAcl"
            ],
            "Resource": "arn:aws:s3:::${MAIN_LOG_BUCKET}",
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "$ACCOUNT_ID"
                }
            }
        }
    ]
}
EOF

    aws s3api put-bucket-policy \
        --bucket "$MAIN_LOG_BUCKET" \
        --policy file:///tmp/log-bucket-policy.json \
        --profile $PROFILE \
        --region $REGION

    # Habilitar versionado en bucket de logs
    aws s3api put-bucket-versioning \
        --bucket "$MAIN_LOG_BUCKET" \
        --versioning-configuration Status=Enabled \
        --profile $PROFILE \
        --region $REGION

    # Configurar lifecycle para logs antiguos
    cat > /tmp/log-lifecycle.json << EOF
{
    "Rules": [
        {
            "ID": "S3AccessLogsLifecycle",
            "Status": "Enabled",
            "Filter": {},
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ],
            "Expiration": {
                "Days": 2555
            }
        }
    ]
}
EOF

    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$MAIN_LOG_BUCKET" \
        --lifecycle-configuration file:///tmp/log-lifecycle.json \
        --profile $PROFILE \
        --region $REGION

    echo "   ✔ Bucket de logs creado y configurado: $MAIN_LOG_BUCKET"
fi

echo ""
echo "=== Escaneando buckets sin logging habilitado ==="

# Obtener lista de todos los buckets
buckets=$(aws s3api list-buckets --profile $PROFILE --query 'Buckets[].Name' --output text)
total_buckets=0
buckets_without_logging=0
buckets_remediated=0

for bucket in $buckets; do
    total_buckets=$((total_buckets + 1))
    
    # Verificar si el bucket es de logs (saltar auto-remediación)
    if [[ "$bucket" == *"access-logs"* ]] || [[ "$bucket" == "$MAIN_LOG_BUCKET" ]]; then
        echo "-> Saltando bucket de logs: $bucket"
        continue
    fi
    
    # Obtener la región del bucket
    bucket_region=$(aws s3api get-bucket-location --bucket "$bucket" --profile $PROFILE --query 'LocationConstraint' --output text 2>/dev/null || echo "us-east-1")
    if [ "$bucket_region" = "None" ] || [ "$bucket_region" = "null" ]; then
        bucket_region="us-east-1"
    fi
    
    # Solo procesar buckets en la región especificada
    if [ "$bucket_region" != "$REGION" ]; then
        echo "-> Saltando bucket en región diferente: $bucket ($bucket_region)"
        continue
    fi
    
    echo "-> Verificando logging en bucket: $bucket"
    
    # Verificar si tiene logging habilitado
    logging_status=$(aws s3api get-bucket-logging --bucket "$bucket" --profile $PROFILE --region $REGION 2>/dev/null || echo "DISABLED")
    
    if echo "$logging_status" | grep -q "TargetBucket"; then
        echo "   ✔ Logging ya habilitado"
    else
        echo "   ⚠ Logging deshabilitado - Aplicando auto-remediación"
        buckets_without_logging=$((buckets_without_logging + 1))
        
        # Configurar logging
        cat > /tmp/logging-config.json << EOF
{
    "LoggingEnabled": {
        "TargetBucket": "$MAIN_LOG_BUCKET",
        "TargetPrefix": "${bucket}/access-logs/"
    }
}
EOF
        
        if aws s3api put-bucket-logging \
            --bucket "$bucket" \
            --bucket-logging-status file:///tmp/logging-config.json \
            --profile $PROFILE \
            --region $REGION 2>/dev/null; then
            echo "   ✔ Auto-remediación aplicada: logging habilitado"
            buckets_remediated=$((buckets_remediated + 1))
        else
            echo "   ❌ Error aplicando auto-remediación"
        fi
    fi
done

# Limpiar archivos temporales
rm -f /tmp/log-bucket-policy.json /tmp/log-lifecycle.json /tmp/logging-config.json

echo ""
echo "=== Resumen de Auto-Remediación ==="
echo "📊 Total buckets procesados: $total_buckets"
echo "⚠️  Buckets sin logging detectados: $buckets_without_logging"
echo "✅ Buckets remediados: $buckets_remediated"
echo "🗂️  Bucket de logs centralizado: $MAIN_LOG_BUCKET"

echo ""
echo "=== Configuración de Monitoreo Continuo ==="
echo "Para habilitar monitoreo continuo, configure:"
echo "1. CloudWatch Event Rule para detectar nuevos buckets"
echo "2. Lambda function para auto-remediación automática"
echo "3. SNS notifications para alertas de remediación"

echo ""
echo "=== Auto-Remediación Completada ✅ ==="