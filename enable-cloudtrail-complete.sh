#!/bin/bash

# CloudTrail KMS Encryption and Logging Enablement Script
# This script properly enables KMS encryption and logging for all CloudTrail trails

PROFILE="ancla"
REGION="us-east-1"
KMS_ALIAS="alias/cloudtrail-key"

echo "=== Habilitando CloudTrail Logging y KMS Encryption ==="
echo "Proveedor: AWS"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo

# Obtener Account ID y KMS Key
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"

# Obtener KMS Key ARN
KMS_KEY_ARN=$(aws kms describe-key \
    --key-id "$KMS_ALIAS" \
    --profile "$PROFILE" --region "$REGION" \
    --query KeyMetadata.Arn --output text 2>/dev/null)

if [ -n "$KMS_KEY_ARN" ] && [ "$KMS_KEY_ARN" != "None" ]; then
    echo "✔ KMS Key ARN: $KMS_KEY_ARN"
else
    echo "❌ KMS Key no encontrada en alias: $KMS_ALIAS"
    exit 1
fi

# Obtener todos los trails
echo
echo "🛤️ Procesando todos los CloudTrails..."
TRAILS=$(aws cloudtrail describe-trails \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[*].Name' --output text 2>/dev/null)

if [ -z "$TRAILS" ]; then
    echo "⚠️ No se encontraron trails"
    exit 0
fi

echo "📋 Trails encontrados: $TRAILS"

# Procesar cada trail
for TRAIL in $TRAILS; do
    echo
    echo "🔒 Configurando trail: $TRAIL"
    
    # Obtener información del trail
    TRAIL_INFO=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].[S3BucketName,KMSKeyId,IsLogging]' \
        --output text 2>/dev/null)
    
    S3_BUCKET=$(echo "$TRAIL_INFO" | cut -f1)
    CURRENT_KMS=$(echo "$TRAIL_INFO" | cut -f2)
    IS_LOGGING=$(echo "$TRAIL_INFO" | cut -f3)
    
    echo "  📦 S3 Bucket: $S3_BUCKET"
    echo "  🔐 KMS Actual: $CURRENT_KMS"
    echo "  📝 Logging: $IS_LOGGING"
    
    if [ -z "$S3_BUCKET" ] || [ "$S3_BUCKET" = "None" ]; then
        echo "  ❌ Trail no tiene bucket S3, omitiendo..."
        continue
    fi
    
    # Paso 1: Habilitar KMS encryption
    echo "  🔐 Aplicando KMS encryption..."
    
    UPDATE_RESULT=$(aws cloudtrail update-trail \
        --name "$TRAIL" \
        --kms-key-id "$KMS_KEY_ARN" \
        --profile "$PROFILE" \
        --region "$REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "    ✔ KMS encryption configurado"
    else
        echo "    ⚠️ Error configurando KMS: $UPDATE_RESULT"
        
        # Intentar con solo el Key ID
        KMS_KEY_ID=$(echo "$KMS_KEY_ARN" | cut -d'/' -f2)
        echo "    🔄 Intentando con Key ID: $KMS_KEY_ID"
        
        UPDATE_RESULT2=$(aws cloudtrail update-trail \
            --name "$TRAIL" \
            --kms-key-id "$KMS_KEY_ID" \
            --profile "$PROFILE" \
            --region "$REGION" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "    ✔ KMS encryption configurado con Key ID"
        else
            echo "    ❌ No se pudo configurar KMS: $UPDATE_RESULT2"
        fi
    fi
    
    # Paso 2: Verificar y habilitar logging
    echo "  📝 Verificando estado de logging..."
    
    LOGGING_STATUS=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    
    if [ "$LOGGING_STATUS" != "true" ]; then
        echo "    🚀 Habilitando logging..."
        
        START_RESULT=$(aws cloudtrail start-logging \
            --name "$TRAIL" \
            --profile "$PROFILE" \
            --region "$REGION" 2>&1)
        
        if [ $? -eq 0 ]; then
            echo "    ✔ Logging habilitado exitosamente"
        else
            echo "    ❌ Error habilitando logging: $START_RESULT"
        fi
    else
        echo "    ✔ Logging ya está habilitado"
    fi
    
    # Paso 3: Configurar event selectors completos
    echo "  📋 Configurando event selectors..."
    
    EVENT_RESULT=$(aws cloudtrail put-event-selectors \
        --trail-name "$TRAIL" \
        --event-selectors '[
            {
                "ReadWriteType": "All",
                "IncludeManagementEvents": true,
                "DataResourceType": "S3Object",
                "DataResourceValues": ["arn:aws:s3:::*/*"]
            },
            {
                "ReadWriteType": "All", 
                "IncludeManagementEvents": true,
                "DataResourceType": "AWS::Lambda::Function",
                "DataResourceValues": ["*"]
            }
        ]' \
        --profile "$PROFILE" --region "$REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "    ✔ Event selectors configurados"
    else
        echo "    ⚠️ Event selectors: usando configuración básica"
        
        # Configuración básica si falla la avanzada
        aws cloudtrail put-event-selectors \
            --trail-name "$TRAIL" \
            --event-selectors ReadWriteType=All,IncludeManagementEvents=true \
            --profile "$PROFILE" --region "$REGION" 2>/dev/null
    fi
done

# Verificación final
echo
echo "🔍 Verificación final..."
echo "═══════════════════════"

for TRAIL in $TRAILS; do
    echo
    echo "📊 Estado final de $TRAIL:"
    
    # Verificar configuración final
    FINAL_INFO=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].[KMSKeyId,S3BucketName]' \
        --output text 2>/dev/null)
    
    FINAL_KMS=$(echo "$FINAL_INFO" | cut -f1)
    FINAL_BUCKET=$(echo "$FINAL_INFO" | cut -f2)
    
    FINAL_LOGGING=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    
    echo "  🔐 KMS Key: $FINAL_KMS"
    echo "  📦 S3 Bucket: $FINAL_BUCKET"
    echo "  📝 Logging Activo: $FINAL_LOGGING"
    
    # Evaluación del estado
    if [ "$FINAL_LOGGING" = "true" ] && [ -n "$FINAL_KMS" ] && [ "$FINAL_KMS" != "None" ]; then
        echo "  ✅ Estado: COMPLETAMENTE CONFIGURADO"
    elif [ "$FINAL_LOGGING" = "true" ]; then
        echo "  ⚠️ Estado: LOGGING ACTIVO, KMS PENDIENTE"
    elif [ -n "$FINAL_KMS" ] && [ "$FINAL_KMS" != "None" ]; then
        echo "  ⚠️ Estado: KMS CONFIGURADO, LOGGING INACTIVO"
    else
        echo "  ❌ Estado: CONFIGURACIÓN INCOMPLETA"
    fi
done

echo
echo "📈 RESUMEN EJECUTIVO"
echo "═══════════════════════"
echo "🔑 KMS Key: $KMS_KEY_ARN"
echo "👤 Perfil: $PROFILE"  
echo "🌎 Región: $REGION"

# Contar trails configurados correctamente
TOTAL_TRAILS=0
CONFIGURED_TRAILS=0

for TRAIL in $TRAILS; do
    TOTAL_TRAILS=$((TOTAL_TRAILS + 1))
    
    TRAIL_KMS=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].KMSKeyId' \
        --output text 2>/dev/null)
    
    TRAIL_LOGGING=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    
    if [ "$TRAIL_LOGGING" = "true" ] && [ -n "$TRAIL_KMS" ] && [ "$TRAIL_KMS" != "None" ]; then
        CONFIGURED_TRAILS=$((CONFIGURED_TRAILS + 1))
    fi
done

echo "🛤️ Total trails: $TOTAL_TRAILS"
echo "✅ Trails completamente configurados: $CONFIGURED_TRAILS"

if [ "$CONFIGURED_TRAILS" -eq "$TOTAL_TRAILS" ]; then
    echo
    echo "🎉 ¡ÉXITO COMPLETO!"
    echo "🔒 Todos los trails tienen KMS encryption y logging activo"
    echo "🛡️ Audit trail completamente protegido y funcional"
else
    echo
    echo "⚠️ Configuración parcial completada"
    echo "💡 Algunos trails pueden necesitar configuración manual adicional"
fi

echo
echo "✅ Proceso completado"