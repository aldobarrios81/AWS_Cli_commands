#!/bin/bash
# verify-cloudtrail-config-changes-monitoring.sh
# Verificar configuración de monitoring para cambios en CloudTrail
# Regla de seguridad CIS AWS: 3.5 - Monitor CloudTrail configuration changes

# Configuración para perfil azcenit
PROFILE="azcenit"
REGION="us-east-1"
METRIC_NAMESPACE="CISBenchmark"
METRIC_NAME="CloudTrailConfigChanges"
FILTER_NAME="CIS-CloudTrailConfigChanges"
ALARM_PREFIX="CIS-3.5-CloudTrailConfigChanges"
SNS_TOPIC_NAME="cis-security-alerts"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICANDO CIS 3.5 - CLOUDTRAIL CONFIG CHANGES MONITORING${NC}"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Verificando configuración de monitoreo para cambios en CloudTrail"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query 'Account' --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ ERROR: No se puede obtener el Account ID${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# Verificar SNS Topic
echo "=== Verificando SNS Topic ==="
SNS_TOPIC_ARN=$(aws sns list-topics \
    --profile "$PROFILE" --region "$REGION" \
    --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
    --output text 2>/dev/null)

if [ -z "$SNS_TOPIC_ARN" ] || [ "$SNS_TOPIC_ARN" = "None" ]; then
    echo -e "${RED}❌ SNS Topic '$SNS_TOPIC_NAME' no encontrado${NC}"
    SNS_STATUS="❌ No configurado"
else
    echo -e "${GREEN}✅ SNS Topic encontrado: $(basename $SNS_TOPIC_ARN)${NC}"
    echo "   ARN: $SNS_TOPIC_ARN"
    
    # Verificar suscripciones
    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$SNS_TOPIC_ARN" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,Status:SubscriptionArn}' \
        --output table 2>/dev/null)
    
    if [ ! -z "$SUBSCRIPTIONS" ]; then
        echo -e "${BLUE}📧 Suscripciones configuradas:${NC}"
        echo "$SUBSCRIPTIONS"
        SNS_STATUS="✅ Configurado con suscripciones"
    else
        echo -e "${YELLOW}⚠️ SNS Topic existe pero sin suscripciones${NC}"
        SNS_STATUS="⚠️ Sin suscripciones"
    fi
fi
echo ""

# Buscar CloudTrail Log Groups
echo "=== Verificando CloudTrail Log Groups y Metric Filters ==="

CLOUDTRAIL_LOG_GROUPS=$(aws logs describe-log-groups \
    --profile "$PROFILE" --region "$REGION" \
    --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' \
    --output text 2>/dev/null)

if [ -z "$CLOUDTRAIL_LOG_GROUPS" ] || [ "$CLOUDTRAIL_LOG_GROUPS" = "None" ]; then
    echo -e "${RED}❌ No se encontraron log groups de CloudTrail${NC}"
    FILTERS_STATUS="❌ No hay log groups"
else
    echo -e "${GREEN}✅ CloudTrail Log Groups encontrados:${NC}"
    
    TOTAL_FILTERS=0
    CONFIGURED_FILTERS=0
    
    for LOG_GROUP in $CLOUDTRAIL_LOG_GROUPS; do
        echo "   📄 $LOG_GROUP"
        TOTAL_FILTERS=$((TOTAL_FILTERS + 1))
        
        # Verificar metric filter
        FILTER_INFO=$(aws logs describe-metric-filters \
            --log-group-name "$LOG_GROUP" \
            --filter-name-prefix "$FILTER_NAME" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query 'metricFilters[0].{Name:filterName,Pattern:filterPattern}' \
            --output json 2>/dev/null)
        
        if [ "$FILTER_INFO" != "null" ] && [ ! -z "$FILTER_INFO" ]; then
            echo -e "${GREEN}     ✅ Metric Filter configurado: $FILTER_NAME${NC}"
            CONFIGURED_FILTERS=$((CONFIGURED_FILTERS + 1))
            
            # Mostrar patrón del filtro
            PATTERN=$(echo $FILTER_INFO | jq -r '.Pattern' 2>/dev/null)
            echo "     📋 Patrón: $PATTERN"
        else
            echo -e "${RED}     ❌ Metric Filter NO configurado${NC}"
        fi
    done
    
    if [ $CONFIGURED_FILTERS -eq $TOTAL_FILTERS ]; then
        FILTERS_STATUS="✅ Todos configurados ($CONFIGURED_FILTERS/$TOTAL_FILTERS)"
    elif [ $CONFIGURED_FILTERS -gt 0 ]; then
        FILTERS_STATUS="⚠️ Parcialmente configurados ($CONFIGURED_FILTERS/$TOTAL_FILTERS)"
    else
        FILTERS_STATUS="❌ Ninguno configurado (0/$TOTAL_FILTERS)"
    fi
fi
echo ""

# Verificar CloudWatch Alarms
echo "=== Verificando CloudWatch Alarms ==="

ALARMS=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "$ALARM_PREFIX" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason,Actions:AlarmActions}' \
    --output json 2>/dev/null)

if [ "$ALARMS" = "[]" ] || [ -z "$ALARMS" ]; then
    echo -e "${RED}❌ No se encontraron alarmas configuradas${NC}"
    ALARMS_STATUS="❌ No configuradas"
else
    echo -e "${GREEN}✅ CloudWatch Alarms encontradas:${NC}"
    
    # Parsear y mostrar información de las alarmas
    ALARM_COUNT=$(echo $ALARMS | jq '. | length' 2>/dev/null)
    ACTIVE_ALARMS=0
    
    for i in $(seq 0 $((ALARM_COUNT - 1))); do
        ALARM_INFO=$(echo $ALARMS | jq -r ".[$i]" 2>/dev/null)
        ALARM_NAME=$(echo $ALARM_INFO | jq -r '.Name' 2>/dev/null)
        ALARM_STATE=$(echo $ALARM_INFO | jq -r '.State' 2>/dev/null)
        ALARM_REASON=$(echo $ALARM_INFO | jq -r '.Reason' 2>/dev/null)
        
        case $ALARM_STATE in
            "OK")
                echo -e "   ✅ $ALARM_NAME: ${GREEN}$ALARM_STATE${NC}"
                ACTIVE_ALARMS=$((ACTIVE_ALARMS + 1))
                ;;
            "ALARM")
                echo -e "   🚨 $ALARM_NAME: ${RED}$ALARM_STATE${NC}"
                echo "      Razón: $ALARM_REASON"
                ACTIVE_ALARMS=$((ACTIVE_ALARMS + 1))
                ;;
            "INSUFFICIENT_DATA")
                echo -e "   ⚠️ $ALARM_NAME: ${YELLOW}$ALARM_STATE${NC}"
                ACTIVE_ALARMS=$((ACTIVE_ALARMS + 1))
                ;;
            *)
                echo -e "   ❓ $ALARM_NAME: ${PURPLE}$ALARM_STATE${NC}"
                ;;
        esac
    done
    
    ALARMS_STATUS="✅ Configuradas ($ALARM_COUNT alarmas)"
fi
echo ""

# Verificar métricas CloudWatch
echo "=== Verificando Métricas en CloudWatch ==="

METRIC_EXISTS=$(aws cloudwatch list-metrics \
    --namespace "$METRIC_NAMESPACE" \
    --metric-name "$METRIC_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'Metrics[0].MetricName' \
    --output text 2>/dev/null)

if [ "$METRIC_EXISTS" = "$METRIC_NAME" ]; then
    echo -e "${GREEN}✅ Métrica '$METRIC_NAME' existe en namespace '$METRIC_NAMESPACE'${NC}"
    
    # Obtener estadísticas recientes
    END_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")
    START_TIME=$(date -u -d '1 hour ago' +"%Y-%m-%dT%H:%M:%S")
    
    METRIC_STATS=$(aws cloudwatch get-metric-statistics \
        --namespace "$METRIC_NAMESPACE" \
        --metric-name "$METRIC_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period 300 \
        --statistics Sum \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'Datapoints[].Sum' \
        --output text 2>/dev/null)
    
    if [ ! -z "$METRIC_STATS" ] && [ "$METRIC_STATS" != "None" ]; then
        TOTAL_EVENTS=$(echo $METRIC_STATS | tr ' ' '+' | bc 2>/dev/null || echo "0")
        echo "   📊 Eventos detectados en la última hora: $TOTAL_EVENTS"
        METRICS_STATUS="✅ Activas con datos"
    else
        echo "   📊 No hay eventos en la última hora (esto es normal)"
        METRICS_STATUS="✅ Activas sin eventos recientes"
    fi
else
    echo -e "${RED}❌ Métrica '$METRIC_NAME' no encontrada${NC}"
    METRICS_STATUS="❌ No configuradas"
fi
echo ""

# Resumen de estado
echo "=================================================================="
echo -e "${BLUE}📊 RESUMEN DEL ESTADO CIS 3.5${NC}"
echo "=================================================================="
echo "Perfil: $PROFILE (Account: $ACCOUNT_ID)"
echo "Regla: CIS 3.5 - CloudTrail Configuration Changes Monitoring"
echo ""
echo "📋 COMPONENTES VERIFICADOS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "SNS Topic:           $SNS_STATUS"
echo -e "Metric Filters:      $FILTERS_STATUS"
echo -e "CloudWatch Alarms:   $ALARMS_STATUS"
echo -e "Métricas:           $METRICS_STATUS"
echo ""

# Determinar estado general
if [[ $SNS_STATUS == *"✅"* ]] && [[ $FILTERS_STATUS == *"✅"* ]] && [[ $ALARMS_STATUS == *"✅"* ]] && [[ $METRICS_STATUS == *"✅"* ]]; then
    echo -e "${GREEN}🎉 ESTADO GENERAL: ✅ COMPLETAMENTE CONFIGURADO${NC}"
    echo ""
    echo -e "${BLUE}🛡️ PROTECCIÓN ACTIVA:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Monitoreo activo de cambios en configuración CloudTrail"
    echo "• Detección automática de actividades de administración"
    echo "• Alertas inmediatas por modificaciones no autorizadas"
    echo "• Cumplimiento con CIS AWS Benchmark 3.5"
elif [[ $SNS_STATUS == *"❌"* ]] || [[ $FILTERS_STATUS == *"❌"* ]] || [[ $ALARMS_STATUS == *"❌"* ]]; then
    echo -e "${RED}⚠️ ESTADO GENERAL: ❌ CONFIGURACIÓN INCOMPLETA${NC}"
    echo ""
    echo -e "${YELLOW}🔧 ACCIONES REQUERIDAS:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ $SNS_STATUS == *"❌"* ]]; then
        echo "• Configurar SNS Topic para notificaciones"
    fi
    if [[ $FILTERS_STATUS == *"❌"* ]]; then
        echo "• Configurar Metric Filters en CloudTrail log groups"
    fi
    if [[ $ALARMS_STATUS == *"❌"* ]]; then
        echo "• Configurar CloudWatch Alarms"
    fi
    echo ""
    echo "💡 Ejecutar: ./setup-cloudtrail-config-changes-monitoring.sh"
else
    echo -e "${YELLOW}⚠️ ESTADO GENERAL: 🔄 CONFIGURACIÓN PARCIAL${NC}"
    echo ""
    echo -e "${BLUE}📋 REVISIÓN RECOMENDADA:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• Algunos componentes están configurados correctamente"
    echo "• Revisar elementos marcados con ⚠️"
    echo "• Completar configuración faltante si es necesario"
fi

echo ""
echo -e "${BLUE}🔍 EVENTOS MONITOREADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• CreateTrail - Creación de nuevos trails"
echo "• UpdateTrail - Modificación de trails existentes"
echo "• DeleteTrail - Eliminación de trails"
echo "• StartLogging - Activación de logging"
echo "• StopLogging - Desactivación de logging"
echo ""
echo -e "${YELLOW}💡 PRÓXIMOS PASOS SUGERIDOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Confirmar suscripción de email en SNS si está pendiente"
echo "2. Probar notificaciones con una modificación controlada"
echo "3. Documentar procedimientos de respuesta a alertas"
echo "4. Implementar esta configuración en otros perfiles/regiones"
echo "5. Revisar periódicamente el estado del monitoreo"
echo ""