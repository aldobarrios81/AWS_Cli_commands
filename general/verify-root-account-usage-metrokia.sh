#!/bin/bash
# verify-root-account-usage-metrokia.sh
# Verificar el estado de la implementación de CIS 3.3 - Root Account Usage Monitoring
# Para el perfil metrokia

# Configuración
PROFILE="metrokia"
REGION="us-east-1"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "=================================================================="
echo -e "${CYAN}🔍 VERIFICACIÓN CIS 3.3 - ROOT ACCOUNT USAGE MONITORING${NC}"
echo -e "${PURPLE}PERFIL: $PROFILE${NC}"
echo "=================================================================="
echo "Región: $REGION"
echo ""

# Obtener Account ID
echo -e "${BLUE}🔐 Verificando credenciales para $PROFILE...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query 'Account' --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ ERROR: No se puede acceder al perfil '$PROFILE'${NC}"
    echo -e "${YELLOW}   Verifica que el perfil esté configurado correctamente${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# Verificar SNS Topic
echo -e "${BLUE}📧 SNS Topic para alertas:${NC}"
SNS_TOPIC=$(aws sns list-topics --profile "$PROFILE" --region "$REGION" --query "Topics[?contains(TopicArn, 'cis-security-alerts')].TopicArn" --output text 2>/dev/null)

if [ ! -z "$SNS_TOPIC" ] && [ "$SNS_TOPIC" != "None" ]; then
    echo -e "${GREEN}   ✅ $SNS_TOPIC${NC}"
    
    # Verificar suscripciones
    echo -e "${BLUE}   📬 Suscripciones configuradas:${NC}"
    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC" --profile "$PROFILE" --region "$REGION" --query 'Subscriptions[].{Protocol:Protocol,Endpoint:Endpoint,Status:SubscriptionArn}' --output text 2>/dev/null)
    
    if [ ! -z "$SUBSCRIPTIONS" ]; then
        echo "$SUBSCRIPTIONS" | while read protocol endpoint status; do
            if [ "$status" != "PendingConfirmation" ] && [ "$status" != "None" ]; then
                echo -e "${GREEN}      ✅ $protocol: $endpoint${NC}"
            else
                echo -e "${YELLOW}      ⚠️ $protocol: $endpoint (Pendiente confirmación)${NC}"
            fi
        done
    else
        echo -e "${YELLOW}      ⚠️ No hay suscripciones configuradas${NC}"
    fi
else
    echo -e "${RED}   ❌ No configurado${NC}"
fi
echo ""

# Verificar Log Groups de CloudTrail
echo -e "${BLUE}📋 CloudTrail Log Groups:${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --profile "$PROFILE" --region "$REGION" --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' --output text 2>/dev/null)

if [ ! -z "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
    for group in $LOG_GROUPS; do
        echo -e "${GREEN}   ✅ $group${NC}"
    done
else
    echo -e "${YELLOW}   ⚠️ No se encontraron CloudTrail Log Groups${NC}"
fi
echo ""

# Verificar Metric Filters
echo -e "${BLUE}🔧 Metric Filters (CIS-RootAccountUsage):${NC}"
if [ ! -z "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
    FILTERS_FOUND=0
    for group in $LOG_GROUPS; do
        METRIC_FILTER=$(aws logs describe-metric-filters --profile "$PROFILE" --region "$REGION" --log-group-name "$group" --filter-name-prefix "CIS-RootAccountUsage" --query 'metricFilters[0].{FilterName:filterName,Pattern:filterPattern}' --output text 2>/dev/null)
        
        if [ ! -z "$METRIC_FILTER" ] && [ "$METRIC_FILTER" != "None" ]; then
            FILTER_NAME=$(echo "$METRIC_FILTER" | cut -f1)
            FILTER_PATTERN=$(echo "$METRIC_FILTER" | cut -f2)
            echo -e "${GREEN}   ✅ $FILTER_NAME en $group${NC}"
            echo -e "${BLUE}      Patrón: $FILTER_PATTERN${NC}"
            FILTERS_FOUND=$((FILTERS_FOUND + 1))
        fi
    done
    
    if [ $FILTERS_FOUND -eq 0 ]; then
        echo -e "${RED}   ❌ No se encontraron Metric Filters configurados${NC}"
    fi
else
    echo -e "${RED}   ❌ No se pueden verificar (no hay CloudTrail Log Groups)${NC}"
fi
echo ""

# Verificar CloudWatch Alarms
echo -e "${BLUE}⏰ CloudWatch Alarms:${NC}"
ALARMS=$(aws cloudwatch describe-alarms --profile "$PROFILE" --region "$REGION" --query 'MetricAlarms[?contains(AlarmName, `CIS-3.3-RootAccountUsage`)].{Name:AlarmName,State:StateValue,Reason:StateReason}' --output text 2>/dev/null)

if [ ! -z "$ALARMS" ] && [ "$ALARMS" != "None" ]; then
    echo "$ALARMS" | while read alarm_name state reason; do
        if [ ! -z "$alarm_name" ]; then
            case "$state" in
                "OK")
                    echo -e "${GREEN}   ✅ $alarm_name [$state]${NC}"
                    ;;
                "INSUFFICIENT_DATA")
                    echo -e "${YELLOW}   ⚠️ $alarm_name [$state]${NC}"
                    echo -e "${BLUE}      Razón: $reason${NC}"
                    ;;
                "ALARM")
                    echo -e "${RED}   🚨 $alarm_name [$state] - ¡USO DE ROOT DETECTADO!${NC}"
                    echo -e "${RED}      Razón: $reason${NC}"
                    ;;
                *)
                    echo -e "${BLUE}   ℹ️ $alarm_name [$state]${NC}"
                    ;;
            esac
        fi
    done
else
    echo -e "${RED}   ❌ No se encontraron CloudWatch Alarms configuradas${NC}"
fi
echo ""

# Verificar eventos recientes de root usage (últimas 24 horas)
echo -e "${BLUE}🔍 Verificando eventos recientes de cuenta root (últimas 24 horas):${NC}"

# Calcular timestamp de hace 24 horas
if command -v date >/dev/null 2>&1; then
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        START_TIME=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')
    else
        # BSD date (macOS)
        START_TIME=$(date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ')
    fi
    END_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    echo -e "${BLUE}   Buscando eventos desde: $START_TIME${NC}"
    
    # Buscar eventos de root en todos los log groups
    if [ ! -z "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
        ROOT_EVENTS_FOUND=0
        for group in $LOG_GROUPS; do
            ROOT_EVENTS=$(aws logs filter-log-events \
                --profile "$PROFILE" --region "$REGION" \
                --log-group-name "$group" \
                --start-time $(date -d "$START_TIME" +%s)000 \
                --end-time $(date -d "$END_TIME" +%s)000 \
                --filter-pattern '{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }' \
                --query 'events[].{Time:eventTime,Event:eventName,SourceIP:sourceIPAddress}' \
                --output text 2>/dev/null | head -5)
            
            if [ ! -z "$ROOT_EVENTS" ]; then
                ROOT_EVENTS_FOUND=1
                echo -e "${YELLOW}   ⚠️ Eventos de cuenta root encontrados en $group:${NC}"
                echo "$ROOT_EVENTS" | while read event_time event_name source_ip; do
                    if [ ! -z "$event_time" ]; then
                        READABLE_TIME=$(date -d @$((event_time/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Tiempo no disponible")
                        echo -e "${YELLOW}      • $READABLE_TIME - $event_name desde $source_ip${NC}"
                    fi
                done
            fi
        done
        
        if [ $ROOT_EVENTS_FOUND -eq 0 ]; then
            echo -e "${GREEN}   ✅ No se detectaron eventos de cuenta root en las últimas 24 horas${NC}"
        else
            echo -e "${RED}   🚨 REVISAR: Se detectó uso de la cuenta root${NC}"
        fi
    else
        echo -e "${YELLOW}   ⚠️ No se pueden verificar eventos (no hay CloudTrail Log Groups)${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️ No se puede verificar eventos recientes (comando 'date' no disponible)${NC}"
fi
echo ""

echo "=================================================================="
echo -e "${GREEN}🎯 VERIFICACIÓN COMPLETADA PARA METROKIA${NC}"
echo "=================================================================="
echo ""
echo -e "${YELLOW}📋 EXPLICACIÓN DE ESTADOS DE ALARMAS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ OK${NC} - Alarma en estado normal (no se detectó uso de root)"
echo -e "${YELLOW}⚠️ INSUFFICIENT_DATA${NC} - Alarma recién creada o sin datos suficientes"
echo -e "${RED}🚨 ALARM${NC} - ¡ALERTA! Se detectó uso de la cuenta root"
echo ""
echo -e "${YELLOW}⚠️ RECORDATORIOS IMPORTANTES:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• La cuenta root debe usarse solo para tareas específicas que lo requieren"
echo "• Siempre investigue cualquier uso no autorizado de la cuenta root"
echo "• Mantenga habilitado MFA en la cuenta root"
echo "• Use usuarios IAM para actividades operativas diarias"
echo ""
echo -e "${BLUE}🔔 ACCIONES RECOMENDADAS PARA METROKIA:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Si no hay suscripciones de email, configurarlas:"
echo "   aws sns subscribe --topic-arn [SNS_ARN] --protocol email --notification-endpoint [EMAIL] --profile metrokia"
echo ""
echo "2. Monitorear regularmente el estado de las alarmas"
echo ""
echo "3. Investigar inmediatamente cualquier alerta de uso de root"
echo ""
echo "4. Revisar y actualizar la documentación de políticas de seguridad"
echo ""