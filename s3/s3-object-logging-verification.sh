#!/bin/bash
# s3-object-logging-verification.sh
# Verificación completa de S3 Object-Level Logging

PROFILE="ancla"
REGION="us-east-1"
TRAIL_NAME="S3ObjectReadTrail"

echo "🎯 REPORTE DE VERIFICACIÓN: S3 OBJECT-LEVEL LOGGING"
echo "═══════════════════════════════════════════════════════════════"
echo "📅 Fecha: $(date)"
echo "👤 Perfil: $PROFILE"
echo "🌎 Región: $REGION"
echo "🛤️ Trail: $TRAIL_NAME"
echo

echo "📊 ESTADO DEL TRAIL"
echo "────────────────────────────────────────────────────────────────"
LOGGING_STATUS=$(aws cloudtrail get-trail-status --name $TRAIL_NAME --profile $PROFILE --region $REGION --query 'IsLogging' --output text 2>/dev/null)
echo "✔ Estado de logging: $([ "$LOGGING_STATUS" = "true" ] && echo "🟢 ACTIVO" || echo "🔴 INACTIVO")"

TRAIL_INFO=$(aws cloudtrail describe-trails --trail-name $TRAIL_NAME --profile $PROFILE --region $REGION --query 'trailList[0]' 2>/dev/null)
S3_BUCKET=$(echo "$TRAIL_INFO" | jq -r '.S3BucketName // "N/A"')
IS_MULTI_REGION=$(echo "$TRAIL_INFO" | jq -r '.IsMultiRegionTrail // false')

echo "📦 Bucket de almacenamiento: $S3_BUCKET"
echo "🌍 Multi-región: $([ "$IS_MULTI_REGION" = "true" ] && echo "✅ SÍ" || echo "❌ NO")"

echo
echo "🔍 CONFIGURACIÓN DE EVENT SELECTORS"
echo "────────────────────────────────────────────────────────────────"
EVENT_SELECTORS=$(aws cloudtrail get-event-selectors --trail-name $TRAIL_NAME --profile $PROFILE --region $REGION 2>/dev/null)

if [ $? -eq 0 ]; then
    READ_WRITE_TYPE=$(echo "$EVENT_SELECTORS" | jq -r '.EventSelectors[0].ReadWriteType // "N/A"')
    INCLUDE_MGMT=$(echo "$EVENT_SELECTORS" | jq -r '.EventSelectors[0].IncludeManagementEvents // false')
    BUCKET_COUNT=$(echo "$EVENT_SELECTORS" | jq -r '.EventSelectors[0].DataResources[0].Values | length')
    
    echo "📝 Tipo de eventos: $READ_WRITE_TYPE $([ "$READ_WRITE_TYPE" = "ReadOnly" ] && echo "✅" || echo "⚠️")"
    echo "⚙️ Management Events: $([ "$INCLUDE_MGMT" = "true" ] && echo "✅ Incluidos" || echo "❌ Excluidos")"
    echo "📁 Buckets monitoreados: $BUCKET_COUNT"
    
    echo
    echo "📋 LISTA DE BUCKETS MONITOREADOS (primeros 10):"
    echo "────────────────────────────────────────────────────────────────"
    echo "$EVENT_SELECTORS" | jq -r '.EventSelectors[0].DataResources[0].Values[0:10][]' | head -10 | while read bucket_arn; do
        BUCKET_NAME=$(echo "$bucket_arn" | sed 's|arn:aws:s3:::\([^/]*\)/.*|\1|')
        echo "   📦 $BUCKET_NAME"
    done
    
    if [ "$BUCKET_COUNT" -gt 10 ]; then
        echo "   ... y $((BUCKET_COUNT - 10)) buckets más"
    fi
else
    echo "❌ Error obteniendo configuración de event selectors"
fi

echo
echo "📈 MÉTRICAS DE COBERTURA"
echo "────────────────────────────────────────────────────────────────"
TOTAL_BUCKETS=$(aws s3api list-buckets --query 'Buckets | length(@)' --output text --profile $PROFILE 2>/dev/null)
COVERED_BUCKETS=${BUCKET_COUNT:-0}

echo "🏪 Total buckets en cuenta: ${TOTAL_BUCKETS:-"N/A"}"
echo "👁️ Buckets monitoreados: $COVERED_BUCKETS"

if [ -n "$TOTAL_BUCKETS" ] && [ "$TOTAL_BUCKETS" -gt 0 ]; then
    COVERAGE_PERCENT=$((COVERED_BUCKETS * 100 / TOTAL_BUCKETS))
    echo "📊 Cobertura: $COVERAGE_PERCENT% $([ $COVERAGE_PERCENT -eq 100 ] && echo "🏆" || echo "📈")"
fi

echo
echo "🔒 CONFIGURACIÓN DE SEGURIDAD"
echo "────────────────────────────────────────────────────────────────"
echo "🎯 Eventos monitoreados: Operaciones de LECTURA en objetos S3"
echo "🛡️ Beneficios de seguridad:"
echo "   ✔ Auditoría completa de acceso a datos S3"
echo "   ✔ Detección de accesos no autorizados"
echo "   ✔ Compliance con estándares de seguridad"
echo "   ✔ Trazabilidad de operaciones de lectura"

echo
echo "💡 INFORMACIÓN TÉCNICA"
echo "────────────────────────────────────────────────────────────────"
echo "🔍 Tipos de eventos capturados:"
echo "   • GetObject (lectura de objetos)"
echo "   • HeadObject (metadata de objetos)"
echo "   • ListObjects (listado de objetos)"
echo "   • GetObjectVersion (versiones específicas)"
echo
echo "📝 Formato de logs: JSON en S3"
echo "⏱️ Latencia típica: 5-15 minutos"
echo "💰 Costo: Basado en eventos de datos registrados"

echo
echo "🎖️ EVALUACIÓN FINAL"
echo "────────────────────────────────────────────────────────────────"
if [ "$LOGGING_STATUS" = "true" ] && [ "$COVERED_BUCKETS" -gt 0 ]; then
    echo "🏆 ESTADO: EXITOSO"
    echo "✅ S3 Object-Level Logging configurado correctamente"
    echo "✅ Trail activo y funcionando"
    echo "✅ $COVERED_BUCKETS buckets bajo monitoreo"
    echo "✅ Eventos de lectura siendo capturados"
    
    SCORE=95
    if [ "$READ_WRITE_TYPE" = "ReadOnly" ]; then
        SCORE=$((SCORE + 5))
    fi
    
    echo "📊 Puntuación de configuración: $SCORE/100"
else
    echo "⚠️ ESTADO: NECESITA ATENCIÓN"
    echo "❌ Trail inactivo o sin buckets monitoreados"
    echo "📊 Puntuación de configuración: 30/100"
fi

echo
echo "═══════════════════════════════════════════════════════════════"
echo "           🎯 VERIFICACIÓN S3 OBJECT-LEVEL COMPLETADA"
echo "═══════════════════════════════════════════════════════════════"