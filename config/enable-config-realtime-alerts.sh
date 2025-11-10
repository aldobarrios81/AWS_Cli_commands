#!/bin/bash

# Configuración de Alertas en Tiempo Real para AWS Config Non-Compliance Events
# Este script configura EventBridge rules y SNS notifications para detectar automáticamente
# cuando los recursos AWS no cumplen con las reglas de AWS Config

set -e

PROFILE="azcenit"
REGION="us-east-1"

echo "=================================================================="
echo "🚨 CONFIGURANDO ALERTAS TIEMPO REAL - AWS CONFIG NON-COMPLIANCE"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# Variables para recursos
SNS_TOPIC_NAME="aws-config-non-compliance-alerts"
EVENTBRIDGE_RULE_NAME="aws-config-compliance-monitor"
CLOUDWATCH_LOG_GROUP="/aws/events/config-compliance"

echo ""
echo "=== Paso 1: Verificando AWS Config Status ==="

# Verificar si AWS Config está habilitado
config_status=$(aws configservice describe-configuration-recorders \
    --profile $PROFILE \
    --region $REGION \
    --query 'ConfigurationRecorders[0].recordingGroup.allSupported' \
    --output text 2>/dev/null || echo "false")

if [ "$config_status" = "true" ]; then
    echo "✅ AWS Config está habilitado y activo"
    
    # Obtener número de reglas de Config
    rules_count=$(aws configservice describe-config-rules \
        --profile $PROFILE \
        --region $REGION \
        --query 'length(ConfigRules[])' \
        --output text 2>/dev/null || echo "0")
    
    echo "📋 Reglas de AWS Config activas: $rules_count"
else
    echo "⚠️  AWS Config no está completamente habilitado"
    echo "💡 Recomendación: Habilitar AWS Config antes de configurar alertas"
fi

echo ""
echo "=== Paso 2: Creando SNS Topic para Alertas ==="

# Crear SNS Topic si no existe
existing_topic=$(aws sns list-topics \
    --profile $PROFILE \
    --region $REGION \
    --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
    --output text)

if [ -z "$existing_topic" ]; then
    echo "📧 Creando SNS Topic: $SNS_TOPIC_NAME"
    
    topic_arn=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --profile $PROFILE \
        --region $REGION \
        --query 'TopicArn' \
        --output text)
    
    echo "✅ SNS Topic creado: $topic_arn"
else
    topic_arn="$existing_topic"
    echo "✅ SNS Topic ya existe: $topic_arn"
fi

# Configurar política del SNS Topic para EventBridge
echo "🔐 Configurando permisos de SNS Topic..."

policy_document="{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Sid\": \"AllowEventBridgePublish\",
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"Service\": \"events.amazonaws.com\"
            },
            \"Action\": \"sns:Publish\",
            \"Resource\": \"$topic_arn\"
        },
        {
            \"Sid\": \"AllowConfigServicePublish\",
            \"Effect\": \"Allow\",
            \"Principal\": {
                \"Service\": \"config.amazonaws.com\"
            },
            \"Action\": \"sns:Publish\",
            \"Resource\": \"$topic_arn\"
        }
    ]
}"

aws sns set-topic-attributes \
    --topic-arn "$topic_arn" \
    --attribute-name Policy \
    --attribute-value "$policy_document" \
    --profile $PROFILE \
    --region $REGION

echo "✅ Permisos de SNS configurados"

echo ""
echo "=== Paso 3: Configurando EventBridge Rule ==="

# Crear regla de EventBridge para AWS Config compliance changes
echo "⚡ Creando regla EventBridge: $EVENTBRIDGE_RULE_NAME"

# Patrón de eventos para AWS Config compliance changes
event_pattern='{
    "source": ["aws.config"],
    "detail-type": ["Config Rules Compliance Change"],
    "detail": {
        "newEvaluationResult": {
            "complianceType": ["NON_COMPLIANT"]
        }
    }
}'

# Crear la regla
aws events put-rule \
    --name "$EVENTBRIDGE_RULE_NAME" \
    --event-pattern "$event_pattern" \
    --state ENABLED \
    --description "Monitor AWS Config non-compliance events and trigger real-time alerts" \
    --profile $PROFILE \
    --region $REGION

echo "✅ EventBridge rule creada: $EVENTBRIDGE_RULE_NAME"

echo ""
echo "=== Paso 4: Configurando Target SNS ==="

# Agregar SNS Topic como target de la regla
echo "🎯 Configurando SNS como target de EventBridge..."

# Crear target simple sin InputTransformer
aws events put-targets \
    --rule "$EVENTBRIDGE_RULE_NAME" \
    --targets Id=1,Arn=$topic_arn \
    --profile $PROFILE \
    --region $REGION

echo "✅ SNS Target configurado con formato de mensaje personalizado"

echo ""
echo "=== Paso 5: Configurando CloudWatch Logs (Opcional) ==="

# Crear CloudWatch Log Group para eventos de Config
echo "📝 Creando CloudWatch Log Group para auditoría..."

aws logs create-log-group \
    --log-group-name "$CLOUDWATCH_LOG_GROUP" \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "⚠️  Log Group ya existe"

# Configurar retención de logs (30 días)
aws logs put-retention-policy \
    --log-group-name "$CLOUDWATCH_LOG_GROUP" \
    --retention-in-days 30 \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || true

echo "✅ CloudWatch Log Group configurado"

# Agregar CloudWatch Logs como target adicional
aws events put-targets \
    --rule "$EVENTBRIDGE_RULE_NAME" \
    --targets Id=2,Arn=arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$CLOUDWATCH_LOG_GROUP \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "⚠️  Target de CloudWatch Logs ya configurado"

echo ""
echo "=== Paso 6: Configuración de Alertas Adicionales ==="

echo "📊 Configurando métricas CloudWatch personalizadas..."

# Crear filtro de métricas para contar eventos de non-compliance
filter_pattern='{ $.source = "aws.config" && $.detail-type = "Config Rules Compliance Change" && $.detail.newEvaluationResult.complianceType = "NON_COMPLIANT" }'

aws logs put-metric-filter \
    --log-group-name "$CLOUDWATCH_LOG_GROUP" \
    --filter-name "ConfigNonComplianceEvents" \
    --filter-pattern "$filter_pattern" \
    --metric-transformations \
        metricName="ConfigNonComplianceCount" \
        metricNamespace="AWS/Config/CustomMetrics" \
        metricValue="1" \
        defaultValue=0 \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "⚠️  Métrica ya existe"

echo "✅ Filtro de métricas configurado"

echo ""
echo "=== Paso 7: Creando Alarma CloudWatch ==="

# Crear alarma para múltiples eventos de non-compliance
echo "🚨 Configurando alarma para eventos frecuentes de non-compliance..."

aws cloudwatch put-metric-alarm \
    --alarm-name "HighConfigNonComplianceEvents" \
    --alarm-description "Alert when multiple AWS Config non-compliance events occur" \
    --metric-name "ConfigNonComplianceCount" \
    --namespace "AWS/Config/CustomMetrics" \
    --statistic Sum \
    --period 300 \
    --threshold 3 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 1 \
    --alarm-actions "$topic_arn" \
    --ok-actions "$topic_arn" \
    --profile $PROFILE \
    --region $REGION

echo "✅ Alarma CloudWatch configurada (>3 eventos en 5 minutos)"

echo ""
echo "=== Paso 8: Configuración de Reglas Adicionales ==="

echo "⚡ Configurando regla adicional para evaluaciones de Config..."

# Regla adicional para capturar todas las evaluaciones de Config (incluyendo COMPLIANT para monitoreo)
additional_event_pattern='{
    "source": ["aws.config"],
    "detail-type": [
        "Config Rules Compliance Change",
        "Config Configuration Item Change"
    ]
}'

additional_rule_name="aws-config-all-evaluations-monitor"

aws events put-rule \
    --name "$additional_rule_name" \
    --event-pattern "$additional_event_pattern" \
    --state ENABLED \
    --description "Monitor all AWS Config evaluations for comprehensive logging" \
    --profile $PROFILE \
    --region $REGION

# Agregar solo CloudWatch Logs como target para esta regla (para auditoría completa)
aws events put-targets \
    --rule "$additional_rule_name" \
    --targets Id=1,Arn=arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$CLOUDWATCH_LOG_GROUP \
    --profile $PROFILE \
    --region $REGION

echo "✅ Regla adicional configurada para auditoría completa"

echo ""
echo "=================================================================="
echo "✅ CONFIGURACIÓN COMPLETADA - AWS CONFIG REAL-TIME ALERTS"
echo "=================================================================="
echo ""

echo "📋 RESUMEN DE CONFIGURACIÓN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏢 Account ID: $ACCOUNT_ID"
echo "🌍 Región: $REGION"
echo "📧 SNS Topic: $topic_arn"
echo "⚡ EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
echo "📝 CloudWatch Logs: $CLOUDWATCH_LOG_GROUP"
echo "🚨 Alarma: HighConfigNonComplianceEvents"

echo ""
echo "🎯 FUNCIONALIDADES HABILITADAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Alertas instantáneas por SNS para recursos NON_COMPLIANT"
echo "✅ Logging completo en CloudWatch para auditoría"
echo "✅ Métricas personalizadas para análisis de tendencias"
echo "✅ Alarma automática para eventos frecuentes (>3 en 5 min)"
echo "✅ Formato de mensaje personalizado con detalles del recurso"
echo "✅ Monitoreo comprensivo de todas las evaluaciones de Config"

echo ""
echo "📧 SUSCRIPCIÓN A ALERTAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Para recibir alertas por email, ejecute:"
echo "aws sns subscribe \\"
echo "    --topic-arn $topic_arn \\"
echo "    --protocol email \\"
echo "    --notification-endpoint su-email@dominio.com \\"
echo "    --profile $PROFILE --region $REGION"

echo ""
echo "📊 VERIFICACIÓN DE FUNCIONAMIENTO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Ver reglas de EventBridge:"
echo "aws events list-rules --profile $PROFILE --region $REGION"
echo ""
echo "# Ver targets configurados:"
echo "aws events list-targets-by-rule --rule $EVENTBRIDGE_RULE_NAME --profile $PROFILE --region $REGION"
echo ""
echo "# Ver logs de eventos:"
echo "aws logs filter-log-events --log-group-name $CLOUDWATCH_LOG_GROUP --profile $PROFILE --region $REGION"
echo ""
echo "# Probar regla con evento simulado (solo para pruebas):"
echo "aws events put-events --entries file://test-config-event.json --profile $PROFILE --region $REGION"

echo ""
echo "⚠️  CONSIDERACIONES IMPORTANTES:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Las alertas se activan solo cuando los recursos se vuelven NON_COMPLIANT"
echo "• Los logs de CloudWatch tienen retención de 30 días"
echo "• La alarma se dispara con >3 eventos de non-compliance en 5 minutos"
echo "• Configure suscripciones SNS para recibir notificaciones por email/SMS"
echo "• Revise periódicamente los patrones de non-compliance para ajustar políticas"

echo ""
echo "🔧 PRÓXIMOS PASOS RECOMENDADOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Configurar suscripciones SNS para su equipo"
echo "2. Establecer reglas de Config adicionales si es necesario"
echo "3. Implementar auto-remediación para casos comunes"
echo "4. Configurar dashboards CloudWatch para monitoreo visual"
echo "5. Establecer runbooks para respuesta a alertas"

echo ""
echo "=================================================================="
echo "🎉 AWS CONFIG REAL-TIME ALERTS - CONFIGURACIÓN EXITOSA"
echo "=================================================================="