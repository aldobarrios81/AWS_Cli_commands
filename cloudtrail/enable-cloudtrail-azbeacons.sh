#!/bin/bash

# CloudTrail Complete Configuration for azbeacons Profile
# Enables logging and KMS encryption for all CloudTrail trails

PROFILE="azbeacons"
REGION="us-east-1"
KMS_ALIAS="alias/cloudtrail-key"

echo "=== Habilitando CloudTrail Logging y KMS Encryption ==="
echo "Proveedor: AWS"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"

# Verificar KMS Key existente
echo
echo "🔑 Verificando KMS Key para CloudTrail..."
KMS_KEY_ARN=$(aws kms describe-key \
    --key-id "$KMS_ALIAS" \
    --profile "$PROFILE" --region "$REGION" \
    --query KeyMetadata.Arn --output text 2>/dev/null)

if [ -n "$KMS_KEY_ARN" ] && [ "$KMS_KEY_ARN" != "None" ]; then
    echo "✔ KMS Key encontrada: $KMS_KEY_ARN"
else
    echo "❌ KMS Key no encontrada"
    exit 1
fi

# Obtener todos los trails
echo
echo "🛤️ Procesando todos los CloudTrails..."
TRAILS=$(aws cloudtrail describe-trails \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[*].Name' --output text 2>/dev/null)

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
    
    BUCKET=$(echo "$TRAIL_INFO" | cut -f1)
    CURRENT_KMS=$(echo "$TRAIL_INFO" | cut -f2)
    IS_LOGGING=$(echo "$TRAIL_INFO" | cut -f3)
    
    echo "  📦 S3 Bucket: $BUCKET"
    echo "  🔐 KMS Actual: $CURRENT_KMS"
    echo "  📝 Logging: $IS_LOGGING"
    
    # Configurar KMS encryption
    echo "  🔐 Aplicando KMS encryption..."
    
    # Intentar con ARN completo
    UPDATE_RESULT=$(aws cloudtrail update-trail \
        --name "$TRAIL" \
        --kms-key-id "$KMS_KEY_ARN" \
        --profile "$PROFILE" \
        --region "$REGION" 2>&1)
    
    if [ $? -eq 0 ]; then
        echo "    ✔ KMS encryption configurado exitosamente"
    else
        echo "    ⚠️ Error configurando KMS: $UPDATE_RESULT"
        
        # Intentar con Key ID solo
        KMS_KEY_ID=$(echo "$KMS_KEY_ARN" | cut -d'/' -f2)
        echo "  🔄 Intentando con Key ID: $KMS_KEY_ID"
        
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
    
    # Verificar y habilitar logging
    LOGGING_STATUS=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    
    echo "  📝 Verificando estado de logging..."
    if [ "$LOGGING_STATUS" != "true" ]; then
        echo "    🚀 Habilitando logging..."
        aws cloudtrail start-logging \
            --name "$TRAIL" \
            --profile "$PROFILE" --region "$REGION"
        
        if [ $? -eq 0 ]; then
            echo "    ✔ Logging habilitado exitosamente"
        else
            echo "    ❌ Error habilitando logging"
        fi
    else
        echo "    ✔ Logging ya está activo"
    fi
    
    # Configurar event selectors para capturar todos los eventos
    echo "  📋 Configurando event selectors..."
    aws cloudtrail put-event-selectors \
        --trail-name "$TRAIL" \
        --event-selectors ReadWriteType=All,IncludeManagementEvents=true \
        --profile "$PROFILE" --region "$REGION" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "    ✔ Event selectors configurados"
        aws cloudtrail get-event-selectors \
            --trail-name "$TRAIL" \
            --profile "$PROFILE" --region "$REGION" \
            --output json | head -20
    else
        echo "    ⚠️ Event selectors: usando configuración básica"
        aws cloudtrail get-event-selectors \
            --trail-name "$TRAIL" \
            --profile "$PROFILE" --region "$REGION" \
            --output json 2>/dev/null | head -20
    fi
done

# Verificación final
echo
echo "🔍 Verificación final..."
echo "═══════════════════════"

for TRAIL in $TRAILS; do
    echo
    FINAL_INFO=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].[KMSKeyId,S3BucketName]' \
        --output text 2>/dev/null)
    
    FINAL_LOGGING=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    
    FINAL_KMS=$(echo "$FINAL_INFO" | cut -f1)
    FINAL_BUCKET=$(echo "$FINAL_INFO" | cut -f2)
    
    echo "📊 Estado final de $TRAIL:"
    echo "  🔐 KMS Key: $FINAL_KMS"
    echo "  📦 S3 Bucket: $FINAL_BUCKET"
    echo "  📝 Logging Activo: $FINAL_LOGGING"
    
    # Evaluar configuración
    if [ "$FINAL_LOGGING" = "true" ] && [ -n "$FINAL_KMS" ] && [ "$FINAL_KMS" != "None" ]; then
        echo "  ✅ Estado: COMPLETAMENTE CONFIGURADO"
    elif [ "$FINAL_LOGGING" = "true" ]; then
        echo "  ⚠️ Estado: LOGGING ACTIVO, KMS PENDIENTE"
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
echo "🛤️ Total trails: $(echo $TRAILS | wc -w)"

# Contar trails completamente configurados
CONFIGURED_COUNT=0
for TRAIL in $TRAILS; do
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
        CONFIGURED_COUNT=$((CONFIGURED_COUNT + 1))
    fi
done

echo "✅ Trails completamente configurados: $CONFIGURED_COUNT"

if [ "$CONFIGURED_COUNT" -eq "$(echo $TRAILS | wc -w)" ]; then
    echo
    echo "🎉 ¡ÉXITO COMPLETO!"
    echo "✅ Todos los trails configurados con logging y KMS encryption"
    echo "🔒 CloudTrail logs protegidos con cifrado at-rest"
    echo "📊 Monitoreo y auditoría completos habilitados"
else
    echo
    echo "⚠️ Configuración parcial completada"
    echo "💡 Algunos trails pueden necesitar configuración manual adicional"
fi

echo
echo "✅ Proceso completado"