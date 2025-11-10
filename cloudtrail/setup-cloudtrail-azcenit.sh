#!/bin/bash

# CloudTrail Complete Setup for azcenit Profile
# Creates KMS key, S3 bucket, CloudTrail, and enables logging and encryption

PROFILE="azcenit"
REGION="us-east-1"
KMS_ALIAS="alias/cloudtrail-key"
S3_BUCKET_NAME="cloudtrail-logs-azcenit-$(date +%s)"
TRAIL_NAME="azcenit-management-events"

echo "═══════════════════════════════════════════════════════════════════"
echo "        🚀 CONFIGURACIÓN COMPLETA DE CLOUDTRAIL - AZCENIT"
echo "═══════════════════════════════════════════════════════════════════"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo "Fecha: $(date)"
echo

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"
echo "✔ S3 Bucket propuesto: $S3_BUCKET_NAME"
echo "✔ Trail propuesto: $TRAIL_NAME"

echo
echo "🔧 PASO 1: CREACIÓN DE KMS KEY"
echo "────────────────────────────────────────────────────────────────────"

# Verificar si ya existe la KMS Key
KMS_KEY_ID=$(aws kms list-aliases --profile "$PROFILE" --region "$REGION" \
  --query "Aliases[?AliasName=='$KMS_ALIAS'].TargetKeyId" --output text 2>/dev/null || echo "")

if [ -z "$KMS_KEY_ID" ] || [ "$KMS_KEY_ID" = "None" ]; then
    echo "📝 Creando nueva KMS Key para CloudTrail..."
    
    # Crear la KMS Key
    KMS_KEY_ID=$(aws kms create-key \
        --description "KMS Key for CloudTrail encryption - azcenit Profile" \
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
               TagKey=Profile,TagValue=azcenit \
        --profile "$PROFILE" --region "$REGION"
    
    echo "  ✔ KMS Key creada exitosamente: $KMS_KEY_ID"
    echo "  ✔ Alias creado: $KMS_ALIAS"
else
    echo "✔ KMS Key existente encontrada: $KMS_KEY_ID"
fi

# Obtener el ARN de la KMS Key
KMS_KEY_ARN=$(aws kms describe-key \
    --key-id "$KMS_KEY_ID" \
    --profile "$PROFILE" --region "$REGION" \
    --query KeyMetadata.Arn --output text)
echo "✔ KMS Key ARN: $KMS_KEY_ARN"

echo
echo "🔑 PASO 2: CONFIGURACIÓN DE KMS KEY POLICY"
echo "────────────────────────────────────────────────────────────────────"

# Configurar política de la KMS Key para CloudTrail
echo "📝 Aplicando política de KMS Key para CloudTrail..."
cat > /tmp/cloudtrail-kms-policy-azcenit.json <<EOF
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

aws kms put-key-policy \
    --key-id "$KMS_KEY_ID" \
    --policy file:///tmp/cloudtrail-kms-policy-azcenit.json \
    --policy-name default \
    --profile "$PROFILE" --region "$REGION"

if [ $? -eq 0 ]; then
    echo "  ✔ Política de KMS Key aplicada correctamente"
else
    echo "  ⚠️ Error aplicando política KMS, continuando..."
fi

echo
echo "📦 PASO 3: CREACIÓN DE S3 BUCKET"
echo "────────────────────────────────────────────────────────────────────"

# Verificar si el bucket ya existe
if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" --profile "$PROFILE" 2>/dev/null; then
    echo "✔ S3 Bucket ya existe: $S3_BUCKET_NAME"
else
    echo "📝 Creando S3 bucket para CloudTrail logs..."
    
    # Crear el bucket
    aws s3api create-bucket \
        --bucket "$S3_BUCKET_NAME" \
        --profile "$PROFILE" \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "  ✔ S3 Bucket creado: $S3_BUCKET_NAME"
    else
        echo "  ❌ Error creando S3 bucket"
        exit 1
    fi
    
    # Habilitar versionado
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET_NAME" \
        --versioning-configuration Status=Enabled \
        --profile "$PROFILE"
    
    # Bloquear acceso público
    aws s3api put-public-access-block \
        --bucket "$S3_BUCKET_NAME" \
        --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
        --profile "$PROFILE"
    
    echo "  ✔ Configuraciones de seguridad aplicadas al bucket"
fi

echo
echo "📝 PASO 4: CONFIGURACIÓN DE BUCKET POLICY"
echo "────────────────────────────────────────────────────────────────────"

# Crear bucket policy para CloudTrail
cat > /tmp/cloudtrail-bucket-policy-azcenit.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::$S3_BUCKET_NAME",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudtrail:$REGION:$ACCOUNT_ID:trail/$TRAIL_NAME"
        }
      }
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow", 
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/AWSLogs/$ACCOUNT_ID/*",
      "Condition": {
        "StringEquals": {
          "s3:x-amz-acl": "bucket-owner-full-control",
          "AWS:SourceArn": "arn:aws:cloudtrail:$REGION:$ACCOUNT_ID:trail/$TRAIL_NAME"
        }
      }
    },
    {
      "Sid": "AWSCloudTrailGetBucketLocation",
      "Effect": "Allow",
      "Principal": { "Service": "cloudtrail.amazonaws.com" },
      "Action": "s3:GetBucketLocation",
      "Resource": "arn:aws:s3:::$S3_BUCKET_NAME",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudtrail:$REGION:$ACCOUNT_ID:trail/$TRAIL_NAME"
        }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
    --bucket "$S3_BUCKET_NAME" \
    --policy file:///tmp/cloudtrail-bucket-policy-azcenit.json \
    --profile "$PROFILE"

if [ $? -eq 0 ]; then
    echo "  ✔ Bucket policy aplicada correctamente"
else
    echo "  ⚠️ Error aplicando bucket policy, continuando..."
fi

echo
echo "🛤️ PASO 5: CREACIÓN DE CLOUDTRAIL"
echo "────────────────────────────────────────────────────────────────────"

# Crear CloudTrail
echo "📝 Creando CloudTrail trail..."
TRAIL_ARN=$(aws cloudtrail create-trail \
    --name "$TRAIL_NAME" \
    --s3-bucket-name "$S3_BUCKET_NAME" \
    --include-global-service-events \
    --is-multi-region-trail \
    --enable-log-file-validation \
    --kms-key-id "$KMS_KEY_ARN" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'TrailARN' \
    --output text)

if [ $? -eq 0 ]; then
    echo "  ✔ CloudTrail creado exitosamente"
    echo "  ✔ Trail ARN: $TRAIL_ARN"
else
    echo "  ❌ Error creando CloudTrail"
    # Intentar sin KMS por ahora
    echo "  🔄 Intentando crear trail sin KMS primero..."
    TRAIL_ARN=$(aws cloudtrail create-trail \
        --name "$TRAIL_NAME" \
        --s3-bucket-name "$S3_BUCKET_NAME" \
        --include-global-service-events \
        --is-multi-region-trail \
        --enable-log-file-validation \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'TrailARN' \
        --output text)
    
    if [ $? -eq 0 ]; then
        echo "  ✔ CloudTrail creado sin KMS"
        echo "  ✔ Trail ARN: $TRAIL_ARN"
    else
        echo "  ❌ No se pudo crear CloudTrail"
        exit 1
    fi
fi

echo
echo "📋 PASO 6: CONFIGURACIÓN DE EVENT SELECTORS"
echo "────────────────────────────────────────────────────────────────────"

# Configurar event selectors para capturar todos los eventos
echo "📝 Configurando event selectors..."
aws cloudtrail put-event-selectors \
    --trail-name "$TRAIL_NAME" \
    --event-selectors ReadWriteType=All,IncludeManagementEvents=true \
    --profile "$PROFILE" --region "$REGION"

if [ $? -eq 0 ]; then
    echo "  ✔ Event selectors configurados"
    # Mostrar configuración
    aws cloudtrail get-event-selectors \
        --trail-name "$TRAIL_NAME" \
        --profile "$PROFILE" --region "$REGION" \
        --output json | head -15
else
    echo "  ⚠️ Error configurando event selectors"
fi

echo
echo "🚀 PASO 7: HABILITACIÓN DE LOGGING"
echo "────────────────────────────────────────────────────────────────────"

# Habilitar logging
echo "📝 Habilitando logging en CloudTrail..."
aws cloudtrail start-logging \
    --name "$TRAIL_NAME" \
    --profile "$PROFILE" --region "$REGION"

if [ $? -eq 0 ]; then
    echo "  ✔ Logging habilitado exitosamente"
else
    echo "  ❌ Error habilitando logging"
fi

echo
echo "🔐 PASO 8: CONFIGURACIÓN DE KMS ENCRYPTION"
echo "────────────────────────────────────────────────────────────────────"

# Intentar aplicar KMS encryption al trail
echo "📝 Aplicando KMS encryption al trail..."
aws cloudtrail update-trail \
    --name "$TRAIL_NAME" \
    --kms-key-id "$KMS_KEY_ARN" \
    --profile "$PROFILE" \
    --region "$REGION"

if [ $? -eq 0 ]; then
    echo "  ✔ KMS encryption aplicado exitosamente"
else
    echo "  ⚠️ KMS encryption no aplicado - puede requerir ajuste de permisos"
fi

echo
echo "🔍 PASO 9: VERIFICACIÓN FINAL"
echo "────────────────────────────────────────────────────────────────────"

# Verificar configuración final
FINAL_LOGGING=$(aws cloudtrail get-trail-status \
    --name "$TRAIL_NAME" \
    --profile "$PROFILE" --region "$REGION" \
    --query 'IsLogging' --output text 2>/dev/null)

FINAL_CONFIG=$(aws cloudtrail describe-trails \
    --trail-name "$TRAIL_NAME" \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[0].[KMSKeyId,S3BucketName,IsMultiRegionTrail]' \
    --output text 2>/dev/null)

FINAL_KMS=$(echo "$FINAL_CONFIG" | cut -f1)
FINAL_BUCKET=$(echo "$FINAL_CONFIG" | cut -f2)
FINAL_MULTI_REGION=$(echo "$FINAL_CONFIG" | cut -f3)

echo "📊 Estado final de configuración:"
echo "  🛤️ Trail: $TRAIL_NAME"
echo "  📦 S3 Bucket: $FINAL_BUCKET"
echo "  🔐 KMS Key: $([ "$FINAL_KMS" != "None" ] && echo "$FINAL_KMS" || echo "❌ NO CONFIGURADO")"
echo "  📝 Logging: $([ "$FINAL_LOGGING" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
echo "  🌍 Multi-Region: $FINAL_MULTI_REGION"

# Evaluación final
echo
echo "🎯 EVALUACIÓN FINAL:"
echo "────────────────────────────────────────────────────────────────────"

if [ "$FINAL_LOGGING" = "true" ] && [ "$FINAL_KMS" != "None" ]; then
    echo "🏆 EXCELENTE: Configuración completa exitosa"
    echo "✅ CloudTrail completamente configurado con logging y KMS encryption"
elif [ "$FINAL_LOGGING" = "true" ]; then
    echo "✅ MUY BUENO: CloudTrail funcional"
    echo "📝 Logging activo y funcionando"
    echo "⚠️ Pendiente: Configurar KMS encryption"
else
    echo "⚠️ PARCIAL: Configuración creada pero requiere ajustes"
fi

# Limpiar archivos temporales
rm -f /tmp/cloudtrail-kms-policy-azcenit.json
rm -f /tmp/cloudtrail-bucket-policy-azcenit.json

echo
echo "✅ CONFIGURACIÓN DE CLOUDTRAIL COMPLETADA"
echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 Para monitorear: aws cloudtrail get-trail-status --name $TRAIL_NAME --profile $PROFILE"
echo "📋 Para ver eventos: aws logs describe-log-groups --profile $PROFILE"
echo "🔐 KMS Key ARN: $KMS_KEY_ARN"
echo "📦 S3 Bucket: $S3_BUCKET_NAME"
echo "═══════════════════════════════════════════════════════════════════"