#!/bin/bash

# Verificación de Configuración de Alertas AWS Config Real-Time
# Valida que todas las alertas estén correctamente configuradas en los 3 perfiles

set -e

echo "=================================================================="
echo "🔍 VERIFICACIÓN AWS CONFIG REAL-TIME ALERTS"
echo "=================================================================="
echo ""

# Array de perfiles
PROFILES=("ancla" "azbeacons" "azcenit")
REGION="us-east-1"

# Contadores globales
total_profiles=0
configured_profiles=0
total_sns_topics=0
total_eventbridge_rules=0
total_cloudwatch_alarms=0

echo "┌─────────────────┬──────────────────┬─────────────────┬─────────────────┬─────────────────┐"
echo "│ Perfil          │ Account ID       │ SNS Topic       │ EventBridge     │ CloudWatch      │"
echo "├─────────────────┼──────────────────┼─────────────────┼─────────────────┼─────────────────┤"

for PROFILE in "${PROFILES[@]}"; do
    total_profiles=$((total_profiles + 1))
    
    # Obtener Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text 2>/dev/null || echo "ERROR")
    
    if [ "$ACCOUNT_ID" = "ERROR" ]; then
        printf "│ %-15s │ %-16s │ %-15s │ %-15s │ %-15s │\n" "$PROFILE" "ERROR" "❌" "❌" "❌"
        continue
    fi
    
    # Formatear Account ID
    formatted_account_id="${ACCOUNT_ID:0:3}...${ACCOUNT_ID: -3}"
    
    # Verificar SNS Topic
    sns_exists=$(aws sns list-topics \
        --profile $PROFILE \
        --region $REGION \
        --query "Topics[?contains(TopicArn, 'aws-config-non-compliance-alerts')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    sns_status="❌"
    if [ ! -z "$sns_exists" ]; then
        sns_status="✅"
        total_sns_topics=$((total_sns_topics + 1))
    fi
    
    # Verificar EventBridge Rules
    eventbridge_rule=$(aws events list-rules \
        --profile $PROFILE \
        --region $REGION \
        --query "Rules[?Name=='aws-config-compliance-monitor'].Name" \
        --output text 2>/dev/null || echo "")
    
    eventbridge_status="❌"
    if [ ! -z "$eventbridge_rule" ]; then
        eventbridge_status="✅"
        total_eventbridge_rules=$((total_eventbridge_rules + 1))
    fi
    
    # Verificar CloudWatch Alarm
    alarm_exists=$(aws cloudwatch describe-alarms \
        --profile $PROFILE \
        --region $REGION \
        --alarm-names "HighConfigNonComplianceEvents" \
        --query "MetricAlarms[0].AlarmName" \
        --output text 2>/dev/null || echo "None")
    
    cloudwatch_status="❌"
    if [ "$alarm_exists" != "None" ] && [ ! -z "$alarm_exists" ]; then
        cloudwatch_status="✅"
        total_cloudwatch_alarms=$((total_cloudwatch_alarms + 1))
    fi
    
    # Contar perfil como configurado si tiene al menos SNS y EventBridge
    if [ "$sns_status" = "✅" ] && [ "$eventbridge_status" = "✅" ]; then
        configured_profiles=$((configured_profiles + 1))
    fi
    
    printf "│ %-15s │ %-16s │ %-15s │ %-15s │ %-15s │\n" "$PROFILE" "$formatted_account_id" "$sns_status" "$eventbridge_status" "$cloudwatch_status"
done

echo "└─────────────────┴──────────────────┴─────────────────┴─────────────────┴─────────────────┘"
echo ""

# Estadísticas detalladas
echo "📊 ESTADÍSTICAS DE CONFIGURACIÓN:"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "🏢 Total de perfiles auditados: $total_profiles"
echo "✅ Perfiles completamente configurados: $configured_profiles"
echo "📧 SNS Topics configurados: $total_sns_topics"
echo "⚡ EventBridge Rules configuradas: $total_eventbridge_rules"
echo "🚨 CloudWatch Alarms configuradas: $total_cloudwatch_alarms"

echo ""

# Análisis detallado por perfil
echo "🔍 ANÁLISIS DETALLADO POR PERFIL:"
echo "═══════════════════════════════════════════════════════════════════════════"

for PROFILE in "${PROFILES[@]}"; do
    echo ""
    echo "📋 Perfil: $PROFILE"
    echo "───────────────────────────────────────────────────────────────────"
    
    # Obtener Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text 2>/dev/null || echo "ERROR")
    
    if [ "$ACCOUNT_ID" = "ERROR" ]; then
        echo "❌ Error de conectividad - Verificar credenciales"
        continue
    fi
    
    echo "🏢 Account ID: $ACCOUNT_ID"
    
    # Detalles SNS
    sns_topic_arn=$(aws sns list-topics \
        --profile $PROFILE \
        --region $REGION \
        --query "Topics[?contains(TopicArn, 'aws-config-non-compliance-alerts')].TopicArn" \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$sns_topic_arn" ]; then
        echo "✅ SNS Topic: $sns_topic_arn"
        
        # Verificar suscripciones
        subscriptions=$(aws sns list-subscriptions-by-topic \
            --topic-arn "$sns_topic_arn" \
            --profile $PROFILE \
            --region $REGION \
            --query 'length(Subscriptions[])' \
            --output text 2>/dev/null || echo "0")
        
        echo "   📧 Suscripciones activas: $subscriptions"
    else
        echo "❌ SNS Topic: No configurado"
    fi
    
    # Detalles EventBridge
    eventbridge_rules=$(aws events list-rules \
        --profile $PROFILE \
        --region $REGION \
        --query "Rules[?contains(Name, 'config')].{Name:Name,State:State}" \
        --output table 2>/dev/null || echo "No hay reglas")
    
    if [[ "$eventbridge_rules" != "No hay reglas" ]] && [[ "$eventbridge_rules" != *"None"* ]]; then
        echo "✅ EventBridge Rules:"
        echo "$eventbridge_rules" | sed 's/^/   /'
    else
        echo "❌ EventBridge Rules: No configuradas"
    fi
    
    # Detalles CloudWatch
    alarm_state=$(aws cloudwatch describe-alarms \
        --profile $PROFILE \
        --region $REGION \
        --alarm-names "HighConfigNonComplianceEvents" \
        --query "MetricAlarms[0].StateValue" \
        --output text 2>/dev/null || echo "None")
    
    if [ "$alarm_state" != "None" ] && [ ! -z "$alarm_state" ]; then
        echo "✅ CloudWatch Alarm: HighConfigNonComplianceEvents (Estado: $alarm_state)"
    else
        echo "❌ CloudWatch Alarm: No configurada"
    fi
    
    # Estado AWS Config
    config_status=$(aws configservice describe-configuration-recorders \
        --profile $PROFILE \
        --region $REGION \
        --query 'ConfigurationRecorders[0].recordingGroup.allSupported' \
        --output text 2>/dev/null || echo "false")
    
    if [ "$config_status" = "true" ]; then
        echo "✅ AWS Config: Habilitado"
    else
        echo "⚠️  AWS Config: No completamente habilitado"
    fi
done

echo ""
echo "🎯 ESTADO GENERAL DE CONFIGURACIÓN:"
echo "═══════════════════════════════════════════════════════════════════════════"

if [ "$configured_profiles" -eq "$total_profiles" ] && [ "$total_cloudwatch_alarms" -eq "$total_profiles" ]; then
    echo "✅ CONFIGURACIÓN COMPLETA"
    echo "   ➤ Todos los perfiles tienen alertas configuradas"
    echo "   ➤ SNS Topics, EventBridge Rules y CloudWatch Alarms activos"
    echo "   ➤ Sistema de alertas en tiempo real operativo"
elif [ "$configured_profiles" -eq "$total_profiles" ]; then
    echo "🟡 CONFIGURACIÓN PARCIAL"
    echo "   ➤ Todos los perfiles tienen alertas básicas"
    echo "   ➤ Falta configuración de CloudWatch Alarms en algunos perfiles"
    echo "   ➤ Funcionalidad core operativa"
else
    missing_profiles=$((total_profiles - configured_profiles))
    echo "⚠️  CONFIGURACIÓN INCOMPLETA"
    echo "   ➤ $missing_profiles perfil(es) sin configurar completamente"
    echo "   ➤ Algunas alertas pueden no funcionar"
    echo "   ➤ Requiere atención inmediata"
fi

echo ""
echo "📧 COMANDOS DE SUSCRIPCIÓN SNS:"
echo "═══════════════════════════════════════════════════════════════════════════"

for PROFILE in "${PROFILES[@]}"; do
    # Obtener Account ID para el ARN
    ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text 2>/dev/null || echo "ERROR")
    
    if [ "$ACCOUNT_ID" != "ERROR" ]; then
        # Verificar si existe el topic
        sns_exists=$(aws sns list-topics \
            --profile $PROFILE \
            --region $REGION \
            --query "Topics[?contains(TopicArn, 'aws-config-non-compliance-alerts')].TopicArn" \
            --output text 2>/dev/null || echo "")
        
        if [ ! -z "$sns_exists" ]; then
            echo "# Para $PROFILE ($ACCOUNT_ID):"
            echo "aws sns subscribe \\"
            echo "    --topic-arn arn:aws:sns:$REGION:$ACCOUNT_ID:aws-config-non-compliance-alerts \\"
            echo "    --protocol email \\"
            echo "    --notification-endpoint su-email@dominio.com \\"
            echo "    --profile $PROFILE --region $REGION"
            echo ""
        fi
    fi
done

echo "🔧 PRÓXIMAS ACCIONES RECOMENDADAS:"
echo "═══════════════════════════════════════════════════════════════════════════"

if [ "$configured_profiles" -eq "$total_profiles" ]; then
    echo "1. ✅ Configurar suscripciones SNS para recibir alertas por email"
    echo "2. ✅ Habilitar AWS Config en los perfiles donde no esté activo"
    echo "3. ✅ Probar las alertas con eventos simulados"
    echo "4. ✅ Configurar auto-remediación para casos comunes"
    echo "5. ✅ Crear dashboards CloudWatch para monitoreo visual"
else
    echo "1. ⚠️  Completar configuración en perfiles faltantes"
    echo "2. ⚠️  Verificar credenciales y permisos AWS"
    echo "3. ⚠️  Re-ejecutar scripts de configuración si es necesario"
    echo "4. ⚠️  Validar conectividad de red"
fi

echo ""
echo "📊 MONITOREO Y VERIFICACIÓN:"
echo "═══════════════════════════════════════════════════════════════════════════"
echo "# Verificar logs de eventos (ejecutar para cada perfil):"
echo "aws logs filter-log-events --log-group-name /aws/events/config-compliance --profile [PROFILE] --region $REGION"
echo ""
echo "# Ver targets configurados:"
echo "aws events list-targets-by-rule --rule aws-config-compliance-monitor --profile [PROFILE] --region $REGION"
echo ""
echo "# Estado de alarmas CloudWatch:"
echo "aws cloudwatch describe-alarms --alarm-names HighConfigNonComplianceEvents --profile [PROFILE] --region $REGION"

echo ""
echo "=================================================================="
echo "📋 Timestamp: $(date '+%Y-%m-%d %H:%M:%S UTC')"
echo "🔍 Región auditada: $REGION"
echo "🛠️  Verificación completada exitosamente"
echo "=================================================================="