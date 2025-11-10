#!/bin/bash

# CloudTrail KMS Encryption Verification Script
# This script verifies the KMS encryption status of all CloudTrail trails

PROFILE="azcenit"
REGION="us-east-1"

echo "=== Verificación de KMS Encryption en CloudTrail ==="
echo "Proveedor: AWS"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo

# Verificar KMS Key creada
echo "🔑 Verificando KMS Key para CloudTrail..."
KMS_KEY_ARN=$(aws kms describe-key \
    --key-id alias/cloudtrail-key \
    --profile "$PROFILE" --region "$REGION" \
    --query KeyMetadata.Arn --output text 2>/dev/null)

if [ -n "$KMS_KEY_ARN" ] && [ "$KMS_KEY_ARN" != "None" ]; then
    echo "✔ KMS Key encontrada: $KMS_KEY_ARN"
else
    echo "❌ KMS Key no encontrada"
    exit 1
fi

# Verificar todos los trails
echo
echo "📋 Estado actual de todos los CloudTrails:"
echo "═══════════════════════════════════════════"

TRAILS=$(aws cloudtrail describe-trails \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[*].Name' --output text 2>/dev/null)

if [ -z "$TRAILS" ]; then
    echo "⚠️ No se encontraron trails"
    exit 0
fi

for TRAIL in $TRAILS; do
    echo
    echo "🛤️ Trail: $TRAIL"
    
    # Obtener información detallada del trail
    TRAIL_INFO=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].[Name,S3BucketName,KMSKeyId,IsLogging,IsMultiRegionTrail,IncludeGlobalServiceEvents]' \
        --output text 2>/dev/null)
    
    TRAIL_NAME=$(echo "$TRAIL_INFO" | cut -f1)
    S3_BUCKET=$(echo "$TRAIL_INFO" | cut -f2)
    KMS_KEY=$(echo "$TRAIL_INFO" | cut -f3)
    IS_LOGGING=$(echo "$TRAIL_INFO" | cut -f4)
    MULTI_REGION=$(echo "$TRAIL_INFO" | cut -f5)
    GLOBAL_EVENTS=$(echo "$TRAIL_INFO" | cut -f6)
    
    echo "  📦 S3 Bucket: $S3_BUCKET"
    echo "  🔐 KMS Key: $KMS_KEY"
    echo "  📝 Logging Activo: $IS_LOGGING"
    echo "  🌍 Multi-Region: $MULTI_REGION"
    echo "  🌐 Eventos Globales: $GLOBAL_EVENTS"
    
    # Verificar status de logging
    LOGGING_STATUS=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    
    if [ "$LOGGING_STATUS" = "true" ]; then
        echo "  ✔ Estado: Trail activo y registrando eventos"
    else
        echo "  ⚠️ Estado: Trail no está registrando eventos"
    fi
    
    # Verificar KMS encryption
    if [ -n "$KMS_KEY" ] && [ "$KMS_KEY" != "None" ]; then
        if [ "$KMS_KEY" = "$KMS_KEY_ARN" ]; then
            echo "  🔒 KMS Encryption: ✅ CONFIGURADO CORRECTAMENTE"
        else
            echo "  🔒 KMS Encryption: ⚠️ Configurado con key diferente"
            echo "    Key actual: $KMS_KEY"
        fi
    else
        echo "  🔒 KMS Encryption: ❌ NO CONFIGURADO"
    fi
done

echo
echo "🔍 Verificación de Event Selectors:"
echo "═══════════════════════════════════"

for TRAIL in $TRAILS; do
    echo
    echo "📋 Event selectors para $TRAIL:"
    
    EVENT_SELECTORS=$(aws cloudtrail get-event-selectors \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'EventSelectors[*].[ReadWriteType,IncludeManagementEvents,DataResourceType]' \
        --output table 2>/dev/null)
    
    if [ -n "$EVENT_SELECTORS" ]; then
        echo "$EVENT_SELECTORS"
    else
        echo "  ⚠️ No se pudieron obtener event selectors"
    fi
done

# Resumen final de seguridad
echo
echo "📊 RESUMEN DE SEGURIDAD CLOUDTRAIL"
echo "═══════════════════════════════════════"

ENCRYPTED_TRAILS=0
TOTAL_TRAILS=0

for TRAIL in $TRAILS; do
    TOTAL_TRAILS=$((TOTAL_TRAILS + 1))
    
    TRAIL_KMS=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].KMSKeyId' \
        --output text 2>/dev/null)
    
    if [ -n "$TRAIL_KMS" ] && [ "$TRAIL_KMS" != "None" ]; then
        ENCRYPTED_TRAILS=$((ENCRYPTED_TRAILS + 1))
    fi
done

echo "🛤️ Total de trails: $TOTAL_TRAILS"
echo "🔒 Trails con KMS encryption: $ENCRYPTED_TRAILS"
echo "🔑 KMS Key ARN: $KMS_KEY_ARN"

if [ "$ENCRYPTED_TRAILS" -eq "$TOTAL_TRAILS" ]; then
    echo
    echo "✅ ÉXITO: Todos los trails tienen KMS encryption habilitado"
    echo "🛡️ Los logs de CloudTrail están protegidos con cifrado at-rest"
    echo "🔐 Control granular de acceso a través de KMS policies"
else
    echo
    echo "⚠️ ATENCIÓN: $((TOTAL_TRAILS - ENCRYPTED_TRAILS)) trails sin KMS encryption"
    echo "💡 Considera habilitar encryption en todos los trails"
fi

echo
echo "🔧 Para habilitar logging en trails inactivos:"
echo "aws cloudtrail start-logging --name <trail-name> --profile $PROFILE --region $REGION"
echo
echo "✅ Verificación completada"