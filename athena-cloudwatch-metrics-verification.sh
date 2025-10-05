#!/bin/bash
# athena-cloudwatch-metrics-verification.sh
# Verificación de CloudWatch Metrics para Athena WorkGroups

PROFILE="azcenit"
REGION="us-east-1"

echo "🎯 REPORTE DE VERIFICACIÓN: ATHENA CLOUDWATCH METRICS"
echo "═══════════════════════════════════════════════════════════════"
echo "📅 Fecha: $(date)"
echo "👤 Perfil: $PROFILE"
echo "🌎 Región: $REGION"
echo

echo "📊 ANÁLISIS DE WORKGROUPS DE ATHENA"
echo "────────────────────────────────────────────────────────────────"

# Obtener todos los workgroups
WORKGROUPS=$(aws athena list-work-groups --region "$REGION" --profile "$PROFILE" --query "WorkGroups[].Name" --output text 2>/dev/null)

if [ -z "$WORKGROUPS" ]; then
    echo "⚠️ No se encontraron WorkGroups de Athena"
    exit 0
fi

WG_COUNT=$(echo $WORKGROUPS | wc -w)
ENABLED_COUNT=0

echo "🔍 WorkGroups encontrados: $WG_COUNT"
echo

for WG in $WORKGROUPS; do
    echo "📋 WorkGroup: $WG"
    
    # Obtener configuración del workgroup
    WG_CONFIG=$(aws athena get-work-group --work-group "$WG" --region "$REGION" --profile "$PROFILE" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        # Verificar si CloudWatch Metrics está habilitado
        METRICS_ENABLED=$(echo "$WG_CONFIG" | jq -r '.WorkGroup.Configuration.PublishCloudWatchMetricsEnabled // false')
        STATE=$(echo "$WG_CONFIG" | jq -r '.WorkGroup.State // "UNKNOWN"')
        DESCRIPTION=$(echo "$WG_CONFIG" | jq -r '.WorkGroup.Description // "No description"')
        CREATION_TIME=$(echo "$WG_CONFIG" | jq -r '.WorkGroup.CreationTime // "N/A"')
        
        # Obtener configuración de resultados
        RESULT_BUCKET=$(echo "$WG_CONFIG" | jq -r '.WorkGroup.Configuration.ResultConfiguration.OutputLocation // "N/A"')
        ENCRYPTION_OPTION=$(echo "$WG_CONFIG" | jq -r '.WorkGroup.Configuration.ResultConfiguration.EncryptionConfiguration.EncryptionOption // "N/A"')
        
        echo "   📝 Descripción: $DESCRIPTION"
        echo "   🔄 Estado: $STATE"
        echo "   📅 Creado: $CREATION_TIME"
        echo "   📦 Bucket de resultados: $(echo $RESULT_BUCKET | sed 's|s3://||')"
        echo "   🔐 Encriptación: $ENCRYPTION_OPTION"
        
        if [ "$METRICS_ENABLED" = "true" ]; then
            ENABLED_COUNT=$((ENABLED_COUNT + 1))
            echo "   ✅ CloudWatch Metrics: HABILITADO"
        else
            echo "   ❌ CloudWatch Metrics: DESHABILITADO"
        fi
        
        # Verificar si hay configuraciones adicionales
        ENFORCE_WG_CONFIG=$(echo "$WG_CONFIG" | jq -r '.WorkGroup.Configuration.EnforceWorkGroupConfiguration // false')
        echo "   ⚙️ Enforce WG Config: $([ "$ENFORCE_WG_CONFIG" = "true" ] && echo "✅ SÍ" || echo "❌ NO")"
        
    else
        echo "   ❌ Error obteniendo configuración"
    fi
    
    echo
done

echo "📊 RESUMEN GENERAL"
echo "────────────────────────────────────────────────────────────────"
echo "🔍 Total WorkGroups: $WG_COUNT"
echo "✅ Con CloudWatch Metrics: $ENABLED_COUNT"

if [ "$WG_COUNT" -gt 0 ]; then
    COVERAGE_PERCENT=$((ENABLED_COUNT * 100 / WG_COUNT))
    echo "📈 Cobertura de metrics: $COVERAGE_PERCENT%"
fi

echo
echo "🎖️ EVALUACIÓN DE CONFIGURACIÓN"
echo "────────────────────────────────────────────────────────────────"

if [ "$ENABLED_COUNT" -eq "$WG_COUNT" ] && [ "$WG_COUNT" -gt 0 ]; then
    echo "🏆 ESTADO: EXCELENTE"
    echo "✅ Todos los WorkGroups tienen CloudWatch Metrics habilitado"
    echo "✅ Monitoreo completo de queries Athena"
    echo "✅ Métricas de performance disponibles"
    SCORE=100
elif [ "$ENABLED_COUNT" -gt 0 ]; then
    echo "⚠️ ESTADO: PARCIAL"
    echo "✅ Algunos WorkGroups configurados ($ENABLED_COUNT/$WG_COUNT)"
    echo "⚠️ Revisar WorkGroups sin metrics"
    SCORE=$((ENABLED_COUNT * 100 / WG_COUNT))
else
    echo "❌ ESTADO: CRÍTICO"
    echo "❌ Ningún WorkGroup tiene CloudWatch Metrics"
    echo "❌ Sin monitoreo de queries Athena"
    SCORE=0
fi

echo "📊 Puntuación: $SCORE/100"

echo
echo "🔒 BENEFICIOS DE CLOUDWATCH METRICS"
echo "────────────────────────────────────────────────────────────────"
echo "📊 Monitoreo de performance de queries"
echo "⏱️ Métricas de tiempo de ejecución"
echo "💾 Uso de recursos y datos procesados"
echo "❌ Detección de queries fallidas"
echo "📈 Análisis de patrones de uso"
echo "🔍 Troubleshooting y optimización"

echo
echo "💡 MÉTRICAS DISPONIBLES"
echo "────────────────────────────────────────────────────────────────"
echo "🔍 Métricas principales capturadas:"
echo "   • QueryExecutionTime - Tiempo total de ejecución"
echo "   • DataProcessedInBytes - Datos procesados por query"
echo "   • QueryQueueTime - Tiempo en cola de ejecución"
echo "   • EngineExecutionTime - Tiempo de procesamiento del motor"
echo "   • QueryPlanningTime - Tiempo de planificación de query"
echo "   • ServiceProcessingTime - Tiempo de procesamiento del servicio"

echo
echo "📈 CASOS DE USO"
echo "────────────────────────────────────────────────────────────────"
echo "🎯 Optimización de queries costosas"
echo "⚡ Identificación de cuellos de botella"
echo "💰 Control de costos de procesamiento"
echo "📊 Reportes de uso y performance"
echo "🚨 Alertas por queries lentas o fallidas"

echo
echo "⚙️ CONFIGURACIÓN TÉCNICA"
echo "────────────────────────────────────────────────────────────────"
echo "📍 Namespace: AWS/Athena"
echo "🔄 Frecuencia: Tiempo real"
echo "📊 Dimensiones: WorkGroup, QueryType, QueryState"
echo "💾 Retención: Según configuración CloudWatch"

echo
echo "═══════════════════════════════════════════════════════════════"
echo "        🎯 VERIFICACIÓN ATHENA CLOUDWATCH METRICS COMPLETADA"
echo "═══════════════════════════════════════════════════════════════"