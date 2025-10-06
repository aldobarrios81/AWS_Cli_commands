#!/bin/bash
# verify-config-changes-monitoring.sh
# Verificar configuración de monitoring para cambios en AWS Config
# Regla de seguridad CIS AWS: 3.9 - Monitor AWS Config configuration changes
# Uso: ./verify-config-changes-monitoring.sh [perfil]

# Verificar parámetros
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
REGION="us-east-1"
METRIC_NAMESPACE="CISBenchmark"
METRIC_NAME="ConfigChanges"
FILTER_NAME="CIS-ConfigChanges"
ALARM_PREFIX="CIS-3.9-ConfigChanges"
SNS_TOPIC_NAME="cis-security-alerts"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICANDO CIS 3.9 - AWS CONFIG CHANGES MONITORING${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Verificando configuración de monitoreo para cambios en AWS Config"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo verificar las credenciales para el perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# Verificar SNS Topic
echo -e "${PURPLE}=== Verificando SNS Topic ===${NC}"
SNS_TOPIC_ARN=$(aws sns list-topics --profile "$PROFILE" --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text 2>/dev/null)

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo -e "${RED}❌ SNS Topic '$SNS_TOPIC_NAME' no encontrado${NC}"
    echo -e "${YELLOW}💡 Ejecuta primero el script de configuración${NC}"
    exit 1
else
    echo -e "${GREEN}✅ SNS Topic encontrado: $SNS_TOPIC_ARN${NC}"
    echo -e "   ARN: ${BLUE}$SNS_TOPIC_ARN${NC}"
    
    # Verificar suscripciones
    echo -e "${BLUE}📧 Suscripciones configuradas:${NC}"
    aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" --output table --query 'Subscriptions[*].[Endpoint,Protocol,SubscriptionArn]' 2>/dev/null
fi
echo ""

# Verificar AWS Config
echo -e "${PURPLE}=== Verificando AWS Config ===${NC}"

# Verificar Configuration Recorders
CONFIG_RECORDERS=$(aws configservice describe-configuration-recorders --profile "$PROFILE" --region "$REGION" --query 'ConfigurationRecorders[].name' --output text 2>/dev/null)

if [ -z "$CONFIG_RECORDERS" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron Configuration Recorders${NC}"
    echo -e "${BLUE}💡 Recomendación: Habilitar AWS Config para monitoreo completo${NC}"
else
    echo -e "${GREEN}✅ Configuration Recorders encontrados: $CONFIG_RECORDERS${NC}"
    
    # Estado detallado de cada recorder
    for recorder in $CONFIG_RECORDERS; do
        echo -e "${BLUE}📊 Analizando recorder: $recorder${NC}"
        
        # Estado de grabación
        RECORDER_STATUS=$(aws configservice describe-configuration-recorder-status --configuration-recorder-names "$recorder" --profile "$PROFILE" --region "$REGION" --query 'ConfigurationRecordersStatus[0].recording' --output text 2>/dev/null)
        
        if [ "$RECORDER_STATUS" == "true" ]; then
            echo -e "   Estado: ${GREEN}ACTIVO (Grabando)${NC}"
        else
            echo -e "   Estado: ${YELLOW}INACTIVO${NC}"
        fi
        
        # Última vez que se inició
        LAST_START=$(aws configservice describe-configuration-recorder-status --configuration-recorder-names "$recorder" --profile "$PROFILE" --region "$REGION" --query 'ConfigurationRecordersStatus[0].lastStartTime' --output text 2>/dev/null)
        
        if [ "$LAST_START" != "None" ] && [ -n "$LAST_START" ]; then
            echo -e "   Último inicio: ${BLUE}$LAST_START${NC}"
        fi
        
        # Recursos monitoreados
        RECORD_ALL=$(aws configservice describe-configuration-recorders --configuration-recorder-names "$recorder" --profile "$PROFILE" --region "$REGION" --query 'ConfigurationRecorders[0].recordingGroup.allSupported' --output text 2>/dev/null)
        
        if [ "$RECORD_ALL" == "true" ]; then
            echo -e "   Recursos: ${GREEN}Todos los recursos soportados${NC}"
        else
            echo -e "   Recursos: ${YELLOW}Recursos específicos seleccionados${NC}"
        fi
        echo ""
    done
fi

# Verificar Delivery Channels
DELIVERY_CHANNELS=$(aws configservice describe-delivery-channels --profile "$PROFILE" --region "$REGION" --query 'DeliveryChannels[].name' --output text 2>/dev/null)

if [ -z "$DELIVERY_CHANNELS" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron Delivery Channels${NC}"
else
    echo -e "${GREEN}✅ Delivery Channels encontrados: $DELIVERY_CHANNELS${NC}"
    
    for channel in $DELIVERY_CHANNELS; do
        echo -e "${BLUE}📤 Analizando delivery channel: $channel${NC}"
        
        # Bucket S3 de destino
        S3_BUCKET=$(aws configservice describe-delivery-channels --delivery-channel-names "$channel" --profile "$PROFILE" --region "$REGION" --query 'DeliveryChannels[0].s3BucketName' --output text 2>/dev/null)
        
        if [ "$S3_BUCKET" != "None" ] && [ -n "$S3_BUCKET" ]; then
            echo -e "   Bucket S3: ${GREEN}$S3_BUCKET${NC}"
        fi
        
        # Frecuencia de entrega
        FREQUENCY=$(aws configservice describe-delivery-channels --delivery-channel-names "$channel" --profile "$PROFILE" --region "$REGION" --query 'DeliveryChannels[0].configSnapshotDeliveryProperties.deliveryFrequency' --output text 2>/dev/null)
        
        if [ "$FREQUENCY" != "None" ] && [ -n "$FREQUENCY" ]; then
            echo -e "   Frecuencia: ${BLUE}$FREQUENCY${NC}"
        fi
        echo ""
    done
fi

# Verificar CloudTrail Log Groups
echo -e "${PURPLE}=== Verificando CloudTrail Log Groups ===${NC}"
LOG_GROUPS=$(aws logs describe-log-groups --profile "$PROFILE" --region "$REGION" --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`)].logGroupName' --output text 2>/dev/null)

if [ -z "$LOG_GROUPS" ]; then
    echo -e "${RED}❌ No se encontraron CloudTrail Log Groups${NC}"
    exit 1
else
    echo -e "${GREEN}✅ CloudTrail Log Groups encontrados:${NC}"
    for log_group in $LOG_GROUPS; do
        echo -e "   📄 $log_group"
        
        # Verificar retención de logs
        RETENTION=$(aws logs describe-log-groups --log-group-name-prefix "$log_group" --profile "$PROFILE" --region "$REGION" --query 'logGroups[0].retentionInDays' --output text 2>/dev/null)
        
        if [ "$RETENTION" != "None" ] && [ -n "$RETENTION" ]; then
            echo -e "      Retención: ${BLUE}$RETENTION días${NC}"
        else
            echo -e "      Retención: ${YELLOW}Sin límite${NC}"
        fi
    done
fi
echo ""

# Verificar Metric Filters
echo -e "${PURPLE}=== Verificando Metric Filters ===${NC}"
FILTERS_FOUND=0

for LOG_GROUP in $LOG_GROUPS; do
    echo -e "${BLUE}🔍 Verificando filtros para: $LOG_GROUP${NC}"
    
    CLEAN_LOG_GROUP=$(echo "$LOG_GROUP" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    EXPECTED_FILTER_NAME="$FILTER_NAME-$CLEAN_LOG_GROUP"
    
    # Buscar metric filter
    FILTER_INFO=$(aws logs describe-metric-filters --log-group-name "$LOG_GROUP" --filter-name-prefix "$FILTER_NAME" --profile "$PROFILE" --region "$REGION" --query 'metricFilters[0]' --output json 2>/dev/null)
    
    if [ "$FILTER_INFO" != "null" ] && [ -n "$FILTER_INFO" ]; then
        FILTER_NAME_FOUND=$(echo "$FILTER_INFO" | jq -r '.filterName // empty' 2>/dev/null)
        FILTER_PATTERN_FOUND=$(echo "$FILTER_INFO" | jq -r '.filterPattern // empty' 2>/dev/null)
        
        if [ -n "$FILTER_NAME_FOUND" ]; then
            echo -e "   ✅ Metric Filter encontrado: ${GREEN}$FILTER_NAME_FOUND${NC}"
            echo -e "   📋 Patrón: ${BLUE}$FILTER_PATTERN_FOUND${NC}"
            FILTERS_FOUND=$((FILTERS_FOUND + 1))
        else
            echo -e "   ${RED}❌ Metric Filter no encontrado${NC}"
        fi
    else
        echo -e "   ${RED}❌ Metric Filter no encontrado${NC}"
    fi
    echo ""
done

# Verificar CloudWatch Alarms
echo -e "${PURPLE}=== Verificando CloudWatch Alarms ===${NC}"
ALARMS_FOUND=0

# Buscar todas las alarmas que coincidan con nuestro prefijo
ALARMS=$(aws cloudwatch describe-alarms --alarm-name-prefix "$ALARM_PREFIX" --profile "$PROFILE" --region "$REGION" --query 'MetricAlarms[*].AlarmName' --output text 2>/dev/null)

if [ -z "$ALARMS" ]; then
    echo -e "${RED}❌ No se encontraron CloudWatch Alarms para CIS 3.9${NC}"
else
    echo -e "${GREEN}✅ CloudWatch Alarms encontradas:${NC}"
    
    for alarm in $ALARMS; do
        echo -e "${BLUE}⏰ Analizando alarm: $alarm${NC}"
        
        # Obtener detalles de la alarma
        ALARM_DETAILS=$(aws cloudwatch describe-alarms --alarm-names "$alarm" --profile "$PROFILE" --region "$REGION" --query 'MetricAlarms[0]' --output json 2>/dev/null)
        
        if [ "$ALARM_DETAILS" != "null" ] && [ -n "$ALARM_DETAILS" ]; then
            ALARM_STATE=$(echo "$ALARM_DETAILS" | jq -r '.StateValue // empty' 2>/dev/null)
            ALARM_REASON=$(echo "$ALARM_DETAILS" | jq -r '.StateReason // empty' 2>/dev/null)
            THRESHOLD=$(echo "$ALARM_DETAILS" | jq -r '.Threshold // empty' 2>/dev/null)
            
            # Color del estado
            case $ALARM_STATE in
                "OK")
                    STATE_COLOR="${GREEN}"
                    ;;
                "ALARM")
                    STATE_COLOR="${RED}"
                    ;;
                "INSUFFICIENT_DATA")
                    STATE_COLOR="${YELLOW}"
                    ;;
                *)
                    STATE_COLOR="${BLUE}"
                    ;;
            esac
            
            echo -e "   Estado: ${STATE_COLOR}$ALARM_STATE${NC}"
            echo -e "   Razón: ${BLUE}$ALARM_REASON${NC}"
            echo -e "   Umbral: ${BLUE}≥ $THRESHOLD${NC}"
            
            # Verificar acciones de la alarma
            ACTIONS=$(echo "$ALARM_DETAILS" | jq -r '.AlarmActions[]? // empty' 2>/dev/null)
            if [ -n "$ACTIONS" ]; then
                echo -e "   Acciones SNS: ${GREEN}Configuradas${NC}"
                echo "$ACTIONS" | while read action; do
                    echo -e "     📧 $action"
                done
            else
                echo -e "   Acciones SNS: ${RED}No configuradas${NC}"
            fi
            
            ALARMS_FOUND=$((ALARMS_FOUND + 1))
        fi
        echo ""
    done
fi

# Resumen final
echo -e "${PURPLE}=== RESUMEN DE VERIFICACIÓN ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$SNS_TOPIC_ARN" ]; then
    echo -e "✅ SNS Topic: ${GREEN}CONFIGURADO${NC}"
else
    echo -e "❌ SNS Topic: ${RED}NO CONFIGURADO${NC}"
fi

if [ -n "$CONFIG_RECORDERS" ]; then
    echo -e "✅ AWS Config: ${GREEN}CONFIGURADO${NC}"
else
    echo -e "⚠️ AWS Config: ${YELLOW}NO CONFIGURADO${NC}"
fi

if [ -n "$LOG_GROUPS" ]; then
    echo -e "✅ CloudTrail Logs: ${GREEN}CONFIGURADO${NC}"
else
    echo -e "❌ CloudTrail Logs: ${RED}NO CONFIGURADO${NC}"
fi

echo -e "📊 Metric Filters encontrados: ${GREEN}$FILTERS_FOUND${NC}"
echo -e "⏰ CloudWatch Alarms encontradas: ${GREEN}$ALARMS_FOUND${NC}"

echo ""
if [ $FILTERS_FOUND -gt 0 ] && [ $ALARMS_FOUND -gt 0 ] && [ -n "$SNS_TOPIC_ARN" ]; then
    echo -e "${GREEN}🎉 CIS 3.9 - CONFIGURACIÓN COMPLETA Y FUNCIONAL${NC}"
    echo -e "${BLUE}💡 AWS Config changes monitoring está activo${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN INCOMPLETA${NC}"
    echo -e "${BLUE}💡 Ejecuta el script de configuración para completar CIS 3.9${NC}"
fi

echo ""
echo -e "${BLUE}📋 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Confirmar suscripción de email si está pendiente"
echo "2. Probar las notificaciones con un evento de prueba"
echo "3. Establecer procedimientos de respuesta a alertas"
echo "4. Documentar la configuración para el equipo"
echo "5. Programar revisiones regulares del estado de AWS Config"