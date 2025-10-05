#!/bin/bash
# api-gatewayv2-access-logging-verification.sh
# Verificación de Access Logging en API Gateway V2

PROFILE="azbeacons"
REGION="us-east-1"

echo "🎯 REPORTE DE VERIFICACIÓN: API GATEWAY V2 ACCESS LOGGING"
echo "═══════════════════════════════════════════════════════════════"
echo "📅 Fecha: $(date)"
echo "👤 Perfil: $PROFILE"
echo "🌎 Región: $REGION"
echo

echo "📊 ANÁLISIS DE APIs Y STAGES"
echo "────────────────────────────────────────────────────────────────"

# Obtener todas las APIs
API_IDS=$(aws apigatewayv2 get-apis --query 'Items[*].ApiId' --output text --profile $PROFILE --region $REGION 2>/dev/null)

if [ -z "$API_IDS" ]; then
    echo "⚠️ No se encontraron APIs de API Gateway V2"
    exit 0
fi

TOTAL_APIS=$(echo $API_IDS | wc -w)
TOTAL_STAGES=0
CONFIGURED_STAGES=0

echo "🔍 APIs encontradas: $TOTAL_APIS"
echo

for API_ID in $API_IDS; do
    echo "🔍 API ID: $API_ID"
    
    # Obtener información de la API
    API_INFO=$(aws apigatewayv2 get-api --api-id $API_ID --profile $PROFILE --region $REGION 2>/dev/null)
    API_NAME=$(echo "$API_INFO" | jq -r '.Name // "N/A"')
    API_PROTOCOL=$(echo "$API_INFO" | jq -r '.ProtocolType // "N/A"')
    API_ENDPOINT=$(echo "$API_INFO" | jq -r '.ApiEndpoint // "N/A"')
    
    echo "   📝 Nombre: $API_NAME"
    echo "   🔗 Protocolo: $API_PROTOCOL"
    echo "   🌐 Endpoint: $API_ENDPOINT"
    echo
    
    # Obtener stages y su configuración de logging
    STAGES_INFO=$(aws apigatewayv2 get-stages --api-id $API_ID --profile $PROFILE --region $REGION 2>/dev/null)
    STAGE_COUNT=$(echo "$STAGES_INFO" | jq '.Items | length' 2>/dev/null)
    
    echo "   📋 Stages encontrados: $STAGE_COUNT"
    
    if [ "$STAGE_COUNT" -gt 0 ]; then
        TOTAL_STAGES=$((TOTAL_STAGES + STAGE_COUNT))
        
        # Analizar cada stage
        for i in $(seq 0 $((STAGE_COUNT - 1))); do
            STAGE_NAME=$(echo "$STAGES_INFO" | jq -r ".Items[$i].StageName")
            LOG_DEST=$(echo "$STAGES_INFO" | jq -r ".Items[$i].AccessLogSettings.DestinationArn // \"None\"")
            LOG_FORMAT=$(echo "$STAGES_INFO" | jq -r ".Items[$i].AccessLogSettings.Format // \"None\"")
            AUTO_DEPLOY=$(echo "$STAGES_INFO" | jq -r ".Items[$i].AutoDeploy // false")
            DEPLOYMENT_ID=$(echo "$STAGES_INFO" | jq -r ".Items[$i].DeploymentId // \"N/A\"")
            
            echo "   🛤️ Stage: $STAGE_NAME"
            
            if [ "$LOG_DEST" != "None" ] && [ "$LOG_DEST" != "null" ]; then
                CONFIGURED_STAGES=$((CONFIGURED_STAGES + 1))
                LOG_GROUP=$(echo "$LOG_DEST" | sed 's|.*log-group:\([^:]*\).*|\1|')
                echo "      ✅ Access Logging: CONFIGURADO"
                echo "      📦 Log Group: $LOG_GROUP"
                echo "      📝 Formato: $(echo "$LOG_FORMAT" | cut -c1-50)..."
            else
                echo "      ❌ Access Logging: NO CONFIGURADO"
            fi
            
            echo "      🚀 Auto Deploy: $([ "$AUTO_DEPLOY" = "true" ] && echo "✅ Habilitado" || echo "❌ Deshabilitado")"
            echo "      🔄 Deployment ID: $DEPLOYMENT_ID"
            echo
        done
    fi
    
    echo "────────────────────────────────────────────────────────────────"
done

echo
echo "📊 RESUMEN GENERAL"
echo "────────────────────────────────────────────────────────────────"
echo "🔍 Total APIs evaluadas: $TOTAL_APIS"
echo "🛤️ Total Stages encontrados: $TOTAL_STAGES"
echo "✅ Stages con Access Logging: $CONFIGURED_STAGES"

if [ "$TOTAL_STAGES" -gt 0 ]; then
    COVERAGE_PERCENT=$((CONFIGURED_STAGES * 100 / TOTAL_STAGES))
    echo "📈 Cobertura de logging: $COVERAGE_PERCENT%"
fi

echo
echo "🎖️ EVALUACIÓN DE CONFIGURACIÓN"
echo "────────────────────────────────────────────────────────────────"

if [ "$CONFIGURED_STAGES" -eq "$TOTAL_STAGES" ] && [ "$TOTAL_STAGES" -gt 0 ]; then
    echo "🏆 ESTADO: EXCELENTE"
    echo "✅ Todos los stages tienen Access Logging configurado"
    echo "✅ Auditoría completa de requests API"
    echo "✅ Compliance de seguridad cumplido"
    SCORE=100
elif [ "$CONFIGURED_STAGES" -gt 0 ]; then
    echo "⚠️ ESTADO: PARCIAL"
    echo "✅ Algunos stages configurados ($CONFIGURED_STAGES/$TOTAL_STAGES)"
    echo "⚠️ Revisar stages sin logging"
    SCORE=$((CONFIGURED_STAGES * 100 / TOTAL_STAGES))
else
    echo "❌ ESTADO: CRÍTICO"
    echo "❌ Ningún stage tiene Access Logging"
    echo "❌ Sin auditoría de requests API"
    SCORE=0
fi

echo "📊 Puntuación: $SCORE/100"

echo
echo "🔒 BENEFICIOS DEL ACCESS LOGGING"
echo "────────────────────────────────────────────────────────────────"
echo "🛡️ Auditoría completa de requests HTTP"
echo "🔍 Monitoreo de patrones de acceso"
echo "📊 Análisis de performance de API"
echo "⚠️ Detección de intentos maliciosos"
echo "📝 Compliance con estándares de seguridad"
echo "🔬 Debugging y troubleshooting"

echo
echo "💡 INFORMACIÓN TÉCNICA"
echo "────────────────────────────────────────────────────────────────"
echo "📋 Datos capturados por log:"
echo "   • Request ID único"
echo "   • IP del cliente"
echo "   • Método HTTP (GET, POST, etc.)"
echo "   • Recurso accedido"
echo "   • Código de estado HTTP"
echo "   • Timestamp de la request"

echo
echo "📈 MÉTRICAS DISPONIBLES"
echo "────────────────────────────────────────────────────────────────"
echo "⏱️ Latencia de respuesta"
echo "📊 Frecuencia de requests"
echo "❌ Rate de errores"
echo "🔍 Patrones de uso"
echo "🌍 Distribución geográfica"

echo
echo "═══════════════════════════════════════════════════════════════"
echo "        🎯 VERIFICACIÓN API GATEWAY V2 ACCESS LOGGING COMPLETADA"
echo "═══════════════════════════════════════════════════════════════"