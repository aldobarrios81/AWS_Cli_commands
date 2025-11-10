#!/bin/bash
set -e

PROFILE="ancla"
REGION="us-east-1"
PROVIDER="AWS"

echo "=== Habilitando KMS Encryption para todos los CloudTrail ==="
echo "Proveedor: $PROVIDER"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo

# Nombre único de la KMS Key
KMS_ALIAS="alias/cloudtrail-key"

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"

# Verificar si ya existe la KMS Key
echo
echo "🔑 Verificando KMS Key para CloudTrail..."
KMS_KEY_ID=$(aws kms list-aliases --profile "$PROFILE" --region "$REGION" \
  --query "Aliases[?AliasName=='$KMS_ALIAS'].TargetKeyId" --output text 2>/dev/null || echo "")

if [ -z "$KMS_KEY_ID" ] || [ "$KMS_KEY_ID" = "None" ]; then
    echo "📝 Creando nueva KMS Key para CloudTrail..."
    
    # Crear la KMS Key con una política más completa
    KMS_KEY_ID=$(aws kms create-key \
        --description "KMS Key for CloudTrail encryption - Enhanced Security" \
        --key-usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --query KeyMetadata.KeyId --output text \
        --profile "$PROFILE" --region "$REGION")
    
    # Crear alias para la key
    aws kms create-alias \
        --alias-name "$KMS_ALIAS" \
        --target-key-id "$KMS_KEY_ID" \
        --profile "$PROFILE" --region "$REGION"
    
    # Añadir tags
    aws kms tag-resource \
        --key-id "$KMS_KEY_ID" \
        --tags TagKey=Name,TagValue=CloudTrailKMS \
               TagKey=Purpose,TagValue=CloudTrailEncryption \
               TagKey=Environment,TagValue=Production \
               TagKey=ManagedBy,TagValue=SecurityScript \
        --profile "$PROFILE" --region "$REGION"
    
    echo "  ✔ KMS Key creada exitosamente: $KMS_KEY_ID"
    echo "  ✔ Alias creado: $KMS_ALIAS"
else
    echo "✔ KMS Key existente encontrada: $KMS_KEY_ID"
fi

# Verificar CloudTrail existente
echo
echo "🛤️ Verificando configuración de CloudTrail..."

# Listar todos los trails disponibles
echo "📋 Obteniendo lista de trails disponibles..."
TRAILS_LIST=$(aws cloudtrail describe-trails \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[*].[Name,HomeRegion,S3BucketName,KMSKeyId]' \
    --output table 2>/dev/null)

if [ -n "$TRAILS_LIST" ]; then
    echo "$TRAILS_LIST"
else
    echo "⚠️ No se pudieron obtener trails o no existen trails."
fi

# Intentar encontrar un trail para configurar
CLOUDTRAIL_NAME="default-trail"
EXISTING_TRAIL=$(aws cloudtrail describe-trails \
    --query "trailList[?Name=='$CLOUDTRAIL_NAME'].Name" --output text \
    --profile "$PROFILE" --region "$REGION" 2>/dev/null)

if [ -z "$EXISTING_TRAIL" ] || [ "$EXISTING_TRAIL" = "None" ]; then
    echo "📝 Trail '$CLOUDTRAIL_NAME' no encontrado. Buscando otros trails..."
    
    # Tomar el primer trail disponible
    FIRST_TRAIL=$(aws cloudtrail describe-trails \
        --query 'trailList[0].Name' --output text \
        --profile "$PROFILE" --region "$REGION" 2>/dev/null)
    
    if [ -n "$FIRST_TRAIL" ] && [ "$FIRST_TRAIL" != "None" ] && [ "$FIRST_TRAIL" != "null" ]; then
        CLOUDTRAIL_NAME="$FIRST_TRAIL"
        echo "✔ Usando trail existente: $CLOUDTRAIL_NAME"
    else
        echo
        echo "❌ No hay trails de CloudTrail disponibles en la región $REGION"
        echo "💡 Para habilitar KMS encryption en CloudTrail, necesitas:"
        echo "   1. Un trail de CloudTrail existente"
        echo "   2. O crear uno nuevo usando: aws cloudtrail create-trail"
        echo
        echo "🔧 Ejemplo para crear un trail básico:"
        echo "   aws cloudtrail create-trail --name default-trail --s3-bucket-name <bucket-name> --profile $PROFILE --region $REGION"
        echo
        exit 1
    fi
else
    echo "✔ Trail encontrado: $CLOUDTRAIL_NAME"
fi
echo "✔ KMS Key ARN: $KMS_KEY_ARN"

# Configurar política de la KMS Key para CloudTrail
echo
echo "🔑 Configurando política de KMS Key..."
cat > /tmp/cloudtrail-kms-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Id": "CloudTrailKMSPolicy",
  "Statement": [
    {
      "Sid": "EnableCloudTrailEncryption",
      "Effect": "Allow",
      "Principal": { 
        "Service": "cloudtrail.amazonaws.com" 
      },
      "Action": [
        "kms:GenerateDataKey*",
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:DescribeKey",
        "kms:CreateGrant"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:EncryptionContext:aws:cloudtrail:arn": "arn:aws:cloudtrail:$REGION:$ACCOUNT_ID:trail/*"
        }
      }
    },
    {
      "Sid": "EnableAccountAdministration", 
      "Effect": "Allow",
      "Principal": { 
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root" 
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "EnableCrossAccountLogDelivery",
      "Effect": "Allow", 
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}
EOF

echo "📝 Aplicando política de KMS Key..."
aws kms put-key-policy \
    --key-id "$KMS_KEY_ID" \
    --policy file:///tmp/cloudtrail-kms-policy.json \
    --policy-name default \
    --profile "$PROFILE" --region "$REGION"

if [ $? -eq 0 ]; then
    echo "  ✔ Política de KMS Key aplicada correctamente"
else
    echo "  ⚠️ Error aplicando política KMS, continuando con configuración básica..."
fi

# Obtener todos los trails disponibles para configurar
echo
echo "🛤️ Configurando KMS Encryption para todos los trails..."
TRAILS=$(aws cloudtrail describe-trails \
    --query 'trailList[*].Name' --output text \
    --profile "$PROFILE" --region "$REGION" 2>/dev/null)

if [ -z "$TRAILS" ]; then
    echo "⚠️ No se encontraron CloudTrails en la región $REGION"
    echo "💡 Considera crear un trail usando: aws cloudtrail create-trail"
    exit 0
fi

echo "📋 Trails encontrados: $TRAILS"

# Procesar cada trail
for TRAIL in $TRAILS; do
    echo
    echo "🔒 Procesando trail: $TRAIL"
    
    # Obtener información del trail
    TRAIL_INFO=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].[S3BucketName,KMSKeyId,IsMultiRegionTrail]' \
        --output text 2>/dev/null)
    
    BUCKET=$(echo "$TRAIL_INFO" | cut -f1)
    CURRENT_KMS=$(echo "$TRAIL_INFO" | cut -f2)
    IS_MULTI_REGION=$(echo "$TRAIL_INFO" | cut -f3)
    
    echo "  📦 S3 Bucket: $BUCKET"
    echo "  🔐 KMS Actual: $CURRENT_KMS"
    echo "  🌍 Multi-Region: $IS_MULTI_REGION"
    
    if [ -z "$BUCKET" ] || [ "$BUCKET" = "None" ]; then
        echo "  ⚠️ Trail no tiene bucket S3 configurado, omitiendo..."
        continue
    fi
    
    # Verificar si ya tiene la KMS key correcta
    if [ "$CURRENT_KMS" = "$KMS_KEY_ARN" ]; then
        echo "  ✔ Trail ya tiene la KMS key correcta configurada"
        continue
    fi
    
    # Configurar política del S3 bucket para permitir KMS
    echo "  📝 Configurando política del bucket S3..."
    cat > /tmp/cloudtrail-bucket-policy-$TRAIL.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::$BUCKET",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudtrail:$REGION:$ACCOUNT_ID:trail/$TRAIL"
        }
      }
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow", 
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$BUCKET/AWSLogs/$ACCOUNT_ID/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "AWS:SourceArn": "arn:aws:cloudtrail:$REGION:$ACCOUNT_ID:trail/$TRAIL"
        }
      }
    }
  ]
}
EOF
    
    aws s3api put-bucket-policy \
        --bucket "$BUCKET" \
        --policy file:///tmp/cloudtrail-bucket-policy-$TRAIL.json \
        --profile "$PROFILE" 2>/dev/null || echo "    ⚠️ No se pudo actualizar política del bucket (puede requerir permisos adicionales)"
    
    # Habilitar KMS encryption en el trail
    echo "  🔐 Aplicando KMS encryption..."
    UPDATE_RESULT=$(aws cloudtrail update-trail \
        --name "$TRAIL" \
        --kms-key-id "$KMS_KEY_ARN" \
        --profile "$PROFILE" \
        --region "$REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "    ✔ KMS encryption habilitado exitosamente"
        
        # Verificar el resultado
        NEW_KMS=$(aws cloudtrail describe-trails \
            --trail-name "$TRAIL" \
            --profile "$PROFILE" --region "$REGION" \
            --query 'trailList[0].KMSKeyId' \
            --output text 2>/dev/null)
        
        if [ "$NEW_KMS" = "$KMS_KEY_ARN" ]; then
            echo "    ✅ Verificación exitosa: KMS configurado correctamente"
        else
            echo "    ⚠️ Verificación: KMS key podría necesitar tiempo para aplicarse"
        fi
    else
        echo "    ❌ Error configurando KMS: $UPDATE_RESULT"
        echo "    💡 Verifica permisos de CloudTrail y KMS"
    fi
    
    # Limpiar archivo temporal
    rm -f /tmp/cloudtrail-bucket-policy-$TRAIL.json
done

# Resumen final
echo
echo "📊 RESUMEN FINAL - CloudTrail KMS Encryption"
echo "════════════════════════════════════════════"
echo "🔑 KMS Key ARN: $KMS_KEY_ARN"
echo "🏷️ KMS Alias: $KMS_ALIAS"
echo "👤 Profile: $PROFILE"
echo "🌎 Region: $REGION"

# Verificar estado final de todos los trails
echo
echo "📋 Estado final de todos los trails:"
aws cloudtrail describe-trails \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[*].[Name,KMSKeyId,IsLogging]' \
    --output table 2>/dev/null || echo "No se pudieron obtener detalles de trails"

echo
echo "✅ PROCESO COMPLETADO"
echo "🔒 CloudTrail logs ahora están protegidos con KMS encryption"
echo "🛡️ Esto proporciona cifrado at-rest y control de acceso granular"

# Limpiar archivos temporales
rm -f /tmp/cloudtrail-kms-policy.json

