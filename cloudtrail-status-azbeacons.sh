#!/bin/bash

# CloudTrail Status Summary for azbeacons Profile
# Complete status check and summary

PROFILE="azbeacons"
REGION="us-east-1"
KMS_ALIAS="alias/cloudtrail-key"

echo "════════════════════════════════════════════════════════════════"
echo "         CLOUDTRAIL STATUS REPORT - PERFIL AZBEACONS"
echo "════════════════════════════════════════════════════════════════"
echo "Fecha: $(date)"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo

# Verificar Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"

# Verificar KMS Key
echo
echo "🔑 CONFIGURACIÓN DE KMS KEY"
echo "────────────────────────────────────────────"
KMS_KEY_ARN=$(aws kms describe-key \
    --key-id "$KMS_ALIAS" \
    --profile "$PROFILE" --region "$REGION" \
    --query KeyMetadata.Arn --output text 2>/dev/null)

if [ -n "$KMS_KEY_ARN" ] && [ "$KMS_KEY_ARN" != "None" ]; then
    echo "✅ KMS Key: DISPONIBLE"
    echo "   ARN: $KMS_KEY_ARN"
    
    # Verificar Key Policy
    echo "   Verificando permisos de KMS key..."
    KEY_POLICY=$(aws kms get-key-policy \
        --key-id "$KMS_ALIAS" \
        --policy-name default \
        --profile "$PROFILE" --region "$REGION" \
        --output text 2>/dev/null | grep -c cloudtrail || echo "0")
    
    if [ "$KEY_POLICY" -gt 0 ]; then
        echo "   ✅ Policy contiene permisos para CloudTrail"
    else
        echo "   ⚠️ Policy podría necesitar permisos para CloudTrail"
    fi
else
    echo "❌ KMS Key: NO ENCONTRADA"
fi

# Verificar CloudTrails
echo
echo "🛤️ ESTADO DE CLOUDTRAILS"
echo "────────────────────────────────────────────"

TRAILS=$(aws cloudtrail describe-trails \
    --profile "$PROFILE" --region "$REGION" \
    --query 'trailList[*].Name' --output text 2>/dev/null)

TOTAL_TRAILS=$(echo "$TRAILS" | wc -w)
LOGGING_TRAILS=0
ENCRYPTED_TRAILS=0

echo "📊 Total de trails encontrados: $TOTAL_TRAILS"
echo

for TRAIL in $TRAILS; do
    echo "📋 Trail: $TRAIL"
    
    # Estado de logging
    LOGGING_STATUS=$(aws cloudtrail get-trail-status \
        --name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'IsLogging' --output text 2>/dev/null)
    
    # Configuración del trail
    TRAIL_CONFIG=$(aws cloudtrail describe-trails \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'trailList[0].[S3BucketName,KMSKeyId,IsMultiRegionTrail,IncludeGlobalServiceEvents]' \
        --output text 2>/dev/null)
    
    S3_BUCKET=$(echo "$TRAIL_CONFIG" | cut -f1)
    KMS_KEY=$(echo "$TRAIL_CONFIG" | cut -f2)
    MULTI_REGION=$(echo "$TRAIL_CONFIG" | cut -f3)
    GLOBAL_EVENTS=$(echo "$TRAIL_CONFIG" | cut -f4)
    
    echo "   📦 S3 Bucket: $S3_BUCKET"
    echo "   🔐 KMS Key: $([ "$KMS_KEY" != "None" ] && echo "$KMS_KEY" || echo "❌ NO CONFIGURADO")"
    echo "   📝 Logging: $([ "$LOGGING_STATUS" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
    echo "   🌍 Multi-Region: $MULTI_REGION"
    echo "   🌐 Eventos Globales: $GLOBAL_EVENTS"
    
    # Contar trails activos
    [ "$LOGGING_STATUS" = "true" ] && LOGGING_TRAILS=$((LOGGING_TRAILS + 1))
    [ "$KMS_KEY" != "None" ] && [ -n "$KMS_KEY" ] && ENCRYPTED_TRAILS=$((ENCRYPTED_TRAILS + 1))
    
    # Event Selectors
    EVENT_SELECTORS=$(aws cloudtrail get-event-selectors \
        --trail-name "$TRAIL" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'EventSelectors[0].[ReadWriteType,IncludeManagementEvents]' \
        --output text 2>/dev/null)
    
    READ_WRITE=$(echo "$EVENT_SELECTORS" | cut -f1)
    MGMT_EVENTS=$(echo "$EVENT_SELECTORS" | cut -f2)
    
    echo "   📋 Event Selectors: $READ_WRITE / Management: $MGMT_EVENTS"
    
    # Estado general
    if [ "$LOGGING_STATUS" = "true" ] && [ "$KMS_KEY" != "None" ]; then
        echo "   🎯 Estado: ✅ COMPLETAMENTE CONFIGURADO"
    elif [ "$LOGGING_STATUS" = "true" ]; then
        echo "   🎯 Estado: ⚠️ LOGGING ACTIVO - KMS PENDIENTE"
    else
        echo "   🎯 Estado: ❌ CONFIGURACIÓN INCOMPLETA"
    fi
    echo
done

# Resumen de métricas
echo "📈 MÉTRICAS DE CONFIGURACIÓN"
echo "────────────────────────────────────────────"
echo "🛤️ Total de trails: $TOTAL_TRAILS"
echo "📝 Trails con logging activo: $LOGGING_TRAILS"
echo "🔐 Trails con KMS encryption: $ENCRYPTED_TRAILS"

LOGGING_PERCENTAGE=$((LOGGING_TRAILS * 100 / TOTAL_TRAILS))
ENCRYPTION_PERCENTAGE=$((ENCRYPTED_TRAILS * 100 / TOTAL_TRAILS))

echo "📊 Porcentaje de logging: $LOGGING_PERCENTAGE%"
echo "🔒 Porcentaje de encryption: $ENCRYPTION_PERCENTAGE%"

# Evaluación general
echo
echo "🎯 EVALUACIÓN GENERAL"
echo "────────────────────────────────────────────"

if [ "$LOGGING_TRAILS" -eq "$TOTAL_TRAILS" ] && [ "$ENCRYPTED_TRAILS" -eq "$TOTAL_TRAILS" ]; then
    echo "🏆 EXCELENTE: Configuración completa"
    echo "✅ Todos los trails tienen logging y encryption activos"
elif [ "$LOGGING_TRAILS" -eq "$TOTAL_TRAILS" ]; then
    echo "✅ BUENO: Logging completo configurado"
    echo "⚠️ Pendiente: Configurar KMS encryption"
elif [ "$LOGGING_TRAILS" -gt 0 ]; then
    echo "⚠️ PARCIAL: Configuración en progreso"
    echo "💡 Necesario: Completar logging y encryption"
else
    echo "❌ CRÍTICO: Sin configuración de logging"
    echo "🚨 Urgente: Habilitar logging de CloudTrail"
fi

# Recomendaciones específicas
echo
echo "💡 RECOMENDACIONES ESPECÍFICAS"
echo "────────────────────────────────────────────"

if [ "$ENCRYPTED_TRAILS" -lt "$TOTAL_TRAILS" ]; then
    echo "🔐 KMS Encryption:"
    echo "   • Verificar permisos de KMS key policy"
    echo "   • Confirmar permisos de CloudTrail service"
    echo "   • Validar bucket policies de S3"
    echo "   • Re-ejecutar configuración KMS si es necesario"
fi

if [ "$LOGGING_TRAILS" -lt "$TOTAL_TRAILS" ]; then
    echo "📝 Logging:"
    echo "   • Habilitar logging en trails inactivos"
    echo "   • Verificar permisos de IAM"
    echo "   • Confirmar configuración de S3 buckets"
fi

echo
echo "🔧 COMANDOS ÚTILES PARA DEBUGGING:"
echo "────────────────────────────────────────────"
echo "• Verificar trail: aws cloudtrail get-trail-status --name <trail> --profile $PROFILE"
echo "• Ver configuración: aws cloudtrail describe-trails --profile $PROFILE"
echo "• Habilitar logging: aws cloudtrail start-logging --name <trail> --profile $PROFILE"
echo "• Configurar KMS: aws cloudtrail update-trail --name <trail> --kms-key-id $KMS_KEY_ARN --profile $PROFILE"
echo "• Verificar KMS policy: aws kms get-key-policy --key-id $KMS_ALIAS --policy-name default --profile $PROFILE"

echo
echo "════════════════════════════════════════════════════════════════"
echo "                    REPORTE COMPLETADO"
echo "════════════════════════════════════════════════════════════════"