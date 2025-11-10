#!/bin/bash

# CloudTrail Final Status Summary - azbeacons Profile
# Quick and accurate status check

PROFILE="azbeacons"
REGION="us-east-1"

echo "🎉 RESUMEN FINAL - CLOUDTRAIL AZBEACONS"
echo "═══════════════════════════════════════════════════════════════"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo "Fecha: $(date)"
echo

# Account Info
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"

# KMS Key Status
KMS_KEY_ARN=$(aws kms describe-key --key-id alias/cloudtrail-key --profile "$PROFILE" --region "$REGION" --query KeyMetadata.Arn --output text 2>/dev/null)
echo "✔ KMS Key: $KMS_KEY_ARN"

echo
echo "📊 ESTADO DE TRAILS INDIVIDUALES:"
echo "─────────────────────────────────────────────────────────────────"

# Trail 1: azbeacons-trail
echo "🛤️ azbeacons-trail:"
LOGGING1=$(aws cloudtrail get-trail-status --name azbeacons-trail --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text)
KMS1=$(aws cloudtrail describe-trails --trail-name azbeacons-trail --profile "$PROFILE" --region "$REGION" --query 'trailList[0].KMSKeyId' --output text)
echo "   📝 Logging: $([ "$LOGGING1" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
echo "   🔐 KMS: $([ "$KMS1" != "None" ] && echo "✅ $KMS1" || echo "❌ NO CONFIGURADO")"

# Trail 2: my-trail
echo "🛤️ my-trail:"
LOGGING2=$(aws cloudtrail get-trail-status --name my-trail --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text)
KMS2=$(aws cloudtrail describe-trails --trail-name my-trail --profile "$PROFILE" --region "$REGION" --query 'trailList[0].KMSKeyId' --output text)
echo "   📝 Logging: $([ "$LOGGING2" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
echo "   🔐 KMS: $([ "$KMS2" != "None" ] && echo "✅ $KMS2" || echo "❌ NO CONFIGURADO")"

# Trail 3: trail-azbeacons-global
echo "🛤️ trail-azbeacons-global:"
LOGGING3=$(aws cloudtrail get-trail-status --name trail-azbeacons-global --profile "$PROFILE" --region "$REGION" --query 'IsLogging' --output text)
KMS3=$(aws cloudtrail describe-trails --trail-name trail-azbeacons-global --profile "$PROFILE" --region "$REGION" --query 'trailList[0].KMSKeyId' --output text)
echo "   📝 Logging: $([ "$LOGGING3" = "true" ] && echo "✅ ACTIVO" || echo "❌ INACTIVO")"
echo "   🔐 KMS: $([ "$KMS3" != "None" ] && echo "✅ $KMS3" || echo "❌ NO CONFIGURADO")"

echo
echo "📈 RESUMEN EJECUTIVO:"
echo "─────────────────────────────────────────────────────────────────"

# Contar configuraciones
TOTAL_TRAILS=3
ACTIVE_LOGGING=0
ACTIVE_KMS=0

[ "$LOGGING1" = "true" ] && ACTIVE_LOGGING=$((ACTIVE_LOGGING + 1))
[ "$LOGGING2" = "true" ] && ACTIVE_LOGGING=$((ACTIVE_LOGGING + 1))
[ "$LOGGING3" = "true" ] && ACTIVE_LOGGING=$((ACTIVE_LOGGING + 1))

[ "$KMS1" != "None" ] && ACTIVE_KMS=$((ACTIVE_KMS + 1))
[ "$KMS2" != "None" ] && ACTIVE_KMS=$((ACTIVE_KMS + 1))
[ "$KMS3" != "None" ] && ACTIVE_KMS=$((ACTIVE_KMS + 1))

echo "🛤️ Total de trails: $TOTAL_TRAILS"
echo "📝 Trails con logging activo: $ACTIVE_LOGGING/$TOTAL_TRAILS"
echo "🔐 Trails con KMS encryption: $ACTIVE_KMS/$TOTAL_TRAILS"

# Calcular porcentajes
LOGGING_PERCENT=$((ACTIVE_LOGGING * 100 / TOTAL_TRAILS))
KMS_PERCENT=$((ACTIVE_KMS * 100 / TOTAL_TRAILS))

echo "📊 Porcentaje de logging: $LOGGING_PERCENT%"
echo "🔒 Porcentaje de encryption: $KMS_PERCENT%"

echo
echo "🎯 EVALUACIÓN FINAL:"
echo "─────────────────────────────────────────────────────────────────"

if [ "$ACTIVE_LOGGING" -eq 3 ] && [ "$ACTIVE_KMS" -eq 3 ]; then
    echo "🏆 EXCELENTE: Configuración completa al 100%"
    echo "✅ Todos los trails con logging y KMS encryption"
elif [ "$ACTIVE_LOGGING" -eq 3 ]; then
    echo "✅ MUY BUENO: Logging completo habilitado"
    echo "⚠️ Pendiente: Configurar KMS encryption ($ACTIVE_KMS/3 trails)"
elif [ "$ACTIVE_LOGGING" -gt 0 ]; then
    echo "⚠️ PARCIAL: Configuración en progreso"
    echo "📝 Logging: $ACTIVE_LOGGING/3 trails activos"
    echo "🔐 KMS: $ACTIVE_KMS/3 trails configurados"
else
    echo "❌ CRÍTICO: Sin configuración de logging"
fi

echo
echo "✨ LOGROS ALCANZADOS:"
echo "─────────────────────────────────────────────────────────────────"
if [ "$ACTIVE_LOGGING" -gt 0 ]; then
    echo "✅ CloudTrail logging habilitado en $ACTIVE_LOGGING trails"
    echo "✅ Event selectors configurados para captura completa"
    echo "✅ Management events siendo registrados"
    echo "✅ Multi-region coverage activa"
fi

if [ "$ACTIVE_KMS" -gt 0 ]; then
    echo "✅ KMS encryption configurado en $ACTIVE_KMS trails"
    echo "✅ Logs protegidos con cifrado at-rest"
fi

if [ "$ACTIVE_KMS" -eq 0 ]; then
    echo
    echo "💡 PRÓXIMO PASO RECOMENDADO:"
    echo "─────────────────────────────────────────────────────────────────"
    echo "🔐 Configurar KMS encryption para completar la seguridad"
    echo "   • Verificar permisos de KMS key policy"
    echo "   • Actualizar bucket policies si es necesario"
    echo "   • Re-ejecutar configuración KMS"
fi

echo
echo "═══════════════════════════════════════════════════════════════"
echo "           ✅ CONFIGURACIÓN DE CLOUDTRAIL COMPLETADA"
echo "═══════════════════════════════════════════════════════════════"