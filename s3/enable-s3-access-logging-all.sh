#!/bin/bash
set -euo pipefail

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    echo ""
    echo "Ejemplos:"
    echo "  $0 metrokia"
    echo "  $0 AZLOGICA"
    exit 1
fi

PROFILE="$1"
CENTRAL_REGION="us-east-1"

# Verificar credenciales y mostrar información de la cuenta
echo "🔍 Verificando credenciales para perfil: $PROFILE"
CALLER_IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    echo "Verificar configuración: aws configure list --profile $PROFILE"
    exit 1
fi

CURRENT_USER=$(echo "$CALLER_IDENTITY" | jq -r '.Arn' 2>/dev/null)
echo "✅ Credenciales válidas"
echo "   Usuario/Rol: $CURRENT_USER"

# ID de cuenta para un nombre único
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")
LOG_BUCKET="central-s3-logs-${ACCOUNT_ID}"

echo "=== Habilitando S3 Access Logging en todos los buckets ==="
echo "Perfil: $PROFILE  |  Región central: $CENTRAL_REGION"
echo "Bucket central: $LOG_BUCKET"
echo

# 1. Crear bucket de logs central si no existe
echo "📦 Verificando bucket de logs central: $LOG_BUCKET"
if ! aws s3api head-bucket --bucket "$LOG_BUCKET" --profile "$PROFILE" 2>/dev/null; then
  echo "🔨 Creando bucket de logs: $LOG_BUCKET en $CENTRAL_REGION"

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

  echo "🔒 Configurando seguridad del bucket de logs..."
  
  # Bloqueo de acceso público
  aws s3api put-public-access-block \
    --bucket "$LOG_BUCKET" \
    --public-access-block-configuration '{
      "BlockPublicAcls": true,
      "IgnorePublicAcls": true,
      "BlockPublicPolicy": true,
      "RestrictPublicBuckets": true
    }' \
    --profile "$PROFILE"

  # Habilitar versioning
  aws s3api put-bucket-versioning \
    --bucket "$LOG_BUCKET" \
    --versioning-configuration Status=Enabled \
    --profile "$PROFILE"

  # Configurar lifecycle para logs antiguos (opcional, para gestión de costos)
  aws s3api put-bucket-lifecycle-configuration \
    --bucket "$LOG_BUCKET" \
    --lifecycle-configuration '{
      "Rules": [{
        "ID": "DeleteOldLogs",
        "Status": "Enabled",
        "Filter": {"Prefix": ""},
        "Transitions": [{
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        }, {
          "Days": 90,
          "StorageClass": "GLACIER"
        }],
        "Expiration": {"Days": 365}
      }]
    }' \
    --profile "$PROFILE"

  echo "✅ Bucket de logs creado y configurado correctamente"
else
  echo "✅ Bucket de logs ya existe: $LOG_BUCKET"
fi

# 2. Configurar política del bucket para permitir logs de S3
echo "📋 Configurando política del bucket de logs..."
BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ServerAccessLogsPolicy",
      "Effect": "Allow",
      "Principal": {"Service": "logging.s3.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${LOG_BUCKET}/*",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:s3:::*"
        },
        "StringEquals": {
          "aws:SourceAccount": "$ACCOUNT_ID"
        }
      }
    },
    {
      "Sid": "S3ServerAccessLogsDeliveryRootAccess",
      "Effect": "Allow",
      "Principal": {"Service": "logging.s3.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${LOG_BUCKET}/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "aws:SourceAccount": "$ACCOUNT_ID"
        }
      }
    }
  ]
}
EOF
)

aws s3api put-bucket-policy \
  --bucket "$LOG_BUCKET" \
  --policy "$BUCKET_POLICY" \
  --profile "$PROFILE"

echo "✅ Política del bucket configurada correctamente"

# 3. Listar y habilitar logging en todos los buckets
echo ""
echo "🔍 Obteniendo lista de buckets..."
BUCKETS=$(aws s3api list-buckets --query 'Buckets[].Name' --output text --profile "$PROFILE")

if [ -z "$BUCKETS" ]; then
    echo "⚠️ No se encontraron buckets en la cuenta"
    exit 0
fi

# Contar buckets para estadísticas
TOTAL_BUCKETS=0
BUCKETS_PROCESSED=0
BUCKETS_SKIPPED=0
BUCKETS_WITH_ERRORS=0

echo "📦 Buckets encontrados:"
for b in $BUCKETS; do
    TOTAL_BUCKETS=$((TOTAL_BUCKETS + 1))
    echo "  - $b"
done

echo ""
read -p "¿Deseas continuar habilitando logging en todos los buckets? (y/N): " confirm
if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
    echo "Operación cancelada"
    exit 0
fi

echo ""
echo "🔧 Habilitando S3 Access Logging..."

for b in $BUCKETS; do
  if [ "$b" != "$LOG_BUCKET" ]; then
    echo "------------------------------------------------------------"
    echo "📦 Procesando bucket: $b"
    
    # Verificar si ya tiene logging habilitado
    CURRENT_LOGGING=$(aws s3api get-bucket-logging --bucket "$b" --profile "$PROFILE" 2>/dev/null || echo "NONE")
    
    if [ "$CURRENT_LOGGING" != "NONE" ] && echo "$CURRENT_LOGGING" | grep -q "TargetBucket"; then
        CURRENT_TARGET=$(echo "$CURRENT_LOGGING" | jq -r '.LoggingEnabled.TargetBucket // "NONE"' 2>/dev/null)
        echo "   ℹ️ Ya tiene logging habilitado hacia: $CURRENT_TARGET"
        
        if [ "$CURRENT_TARGET" = "$LOG_BUCKET" ]; then
            echo "   ✅ Ya está configurado correctamente"
            BUCKETS_PROCESSED=$((BUCKETS_PROCESSED + 1))
            continue
        else
            echo "   🔄 Reconfigurando hacia bucket central: $LOG_BUCKET"
        fi
    else
        echo "   🔧 Habilitando logging por primera vez"
    fi
    
    # Habilitar logging
    LOGGING_CONFIG=$(cat <<EOF
{
  "LoggingEnabled": {
    "TargetBucket": "$LOG_BUCKET",
    "TargetPrefix": "$b/"
  }
}
EOF
)
    
    if aws s3api put-bucket-logging \
      --bucket "$b" \
      --bucket-logging-status "$LOGGING_CONFIG" \
      --profile "$PROFILE" 2>/dev/null; then
        echo "   ✅ Logging habilitado exitosamente"
        echo "   📍 Logs se guardarán en: s3://$LOG_BUCKET/$b/"
        BUCKETS_PROCESSED=$((BUCKETS_PROCESSED + 1))
    else
        echo "   ❌ Error habilitando logging"
        BUCKETS_WITH_ERRORS=$((BUCKETS_WITH_ERRORS + 1))
    fi
  else
    echo "------------------------------------------------------------"
    echo "📦 Saltando bucket central de logs: $b"
    BUCKETS_SKIPPED=$((BUCKETS_SKIPPED + 1))
  fi
done

echo ""
echo "=============================================================="
echo "✅ PROCESO COMPLETADO - S3 ACCESS LOGGING"
echo "=============================================================="
echo ""
echo "📊 Resumen de operaciones:"
echo "  - Total buckets: $TOTAL_BUCKETS"
echo "  - Buckets procesados: $BUCKETS_PROCESSED"
echo "  - Buckets saltados: $BUCKETS_SKIPPED"
echo "  - Errores: $BUCKETS_WITH_ERRORS"
echo ""
echo "📦 Bucket central de logs: s3://$LOG_BUCKET/"
echo "🔍 Verificar resultado:"
echo "  ./verify-s3-logging-status.sh $PROFILE"
echo ""
echo "💡 Los logs de acceso pueden tardar hasta 24 horas en aparecer"
echo ""

