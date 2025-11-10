#!/bin/bash
# verify-nacl-changes-monitoring.sh
# Verificar configuración de monitoring para cambios en Network ACLs
# Regla de seguridad CIS AWS: 3.11 - Monitor NACL changes
# Uso: ./verify-nacl-changes-monitoring.sh [perfil]

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
METRIC_NAME="NACLChanges"
FILTER_NAME="CIS-NACLChanges"
ALARM_PREFIX="CIS-3.11-NACLChanges"
SNS_TOPIC_NAME="cis-security-alerts"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICANDO CIS 3.11 - NACL CHANGES MONITORING${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Verificando configuración de monitoreo para cambios en Network ACLs"
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

# Verificar Network ACLs en la cuenta
echo -e "${PURPLE}=== Verificando Network ACLs en la cuenta ===${NC}"

# Contar y listar NACLs
NACL_COUNT=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --query 'length(NetworkAcls)' --output text 2>/dev/null)

if [ -z "$NACL_COUNT" ] || [ "$NACL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ No se encontraron Network ACLs${NC}"
else
    echo -e "${GREEN}✅ Network ACLs encontradas: $NACL_COUNT ACLs${NC}"
    
    # Mostrar estadísticas de NACLs
    echo -e "${BLUE}📊 Estadísticas de Network ACLs:${NC}"
    
    # NACLs por VPC
    echo -e "${BLUE}📄 Network ACLs por VPC:${NC}"
    VPC_LIST=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --query 'NetworkAcls[].VpcId' --output text 2>/dev/null | tr '\t' '\n' | sort | uniq)
    
    for vpc in $VPC_LIST; do
        VPC_NAME=$(aws ec2 describe-vpcs --vpc-ids "$vpc" --profile "$PROFILE" --region "$REGION" --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null)
        NACL_COUNT_VPC=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --filters "Name=vpc-id,Values=$vpc" --query 'length(NetworkAcls)' --output text 2>/dev/null)
        
        if [ -z "$VPC_NAME" ] || [ "$VPC_NAME" == "None" ]; then
            VPC_NAME="Sin nombre"
        fi
        
        echo -e "   📄 VPC $vpc ($VPC_NAME): ${GREEN}$NACL_COUNT_VPC ACLs${NC}"
        
        # Mostrar ACLs default vs custom
        DEFAULT_NACLS=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --filters "Name=vpc-id,Values=$vpc" "Name=default,Values=true" --query 'length(NetworkAcls)' --output text 2>/dev/null)
        CUSTOM_NACLS=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --filters "Name=vpc-id,Values=$vpc" "Name=default,Values=false" --query 'length(NetworkAcls)' --output text 2>/dev/null)
        
        echo -e "      📌 Default ACLs: ${BLUE}$DEFAULT_NACLS${NC} | Custom ACLs: ${BLUE}$CUSTOM_NACLS${NC}"
    done
    
    echo ""
    
    # Ejemplos de Network ACLs detalladas
    echo -e "${BLUE}🔒 Ejemplos de Network ACLs (primeros 3):${NC}"
    aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --query 'NetworkAcls[:3].[NetworkAclId,VpcId,IsDefault]' --output table 2>/dev/null
    
    echo ""
    
    # Verificar reglas críticas en NACLs
    echo -e "${BLUE}⚠️ Verificando reglas críticas en Network ACLs:${NC}"
    
    # Buscar reglas DENY que puedan ser problemáticas
    DENY_RULES_COUNT=0
    ALLOW_ALL_COUNT=0
    
    NACLS=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --query 'NetworkAcls[].NetworkAclId' --output text 2>/dev/null)
    
    for nacl_id in $NACLS; do
        # Contar reglas DENY
        DENY_COUNT=$(aws ec2 describe-network-acls --network-acl-ids "$nacl_id" --profile "$PROFILE" --region "$REGION" --query 'NetworkAcls[0].Entries[?RuleAction==`deny`]' --output json 2>/dev/null | jq '. | length' 2>/dev/null)
        
        if [ -n "$DENY_COUNT" ] && [ "$DENY_COUNT" -gt 0 ]; then
            DENY_RULES_COUNT=$((DENY_RULES_COUNT + DENY_COUNT))
        fi
        
        # Verificar reglas que permiten todo el tráfico (0.0.0.0/0)
        ALLOW_ALL=$(aws ec2 describe-network-acls --network-acl-ids "$nacl_id" --profile "$PROFILE" --region "$REGION" --query 'NetworkAcls[0].Entries[?RuleAction==`allow` && CidrBlock==`0.0.0.0/0`]' --output json 2>/dev/null | jq '. | length' 2>/dev/null)
        
        if [ -n "$ALLOW_ALL" ] && [ "$ALLOW_ALL" -gt 0 ]; then
            ALLOW_ALL_COUNT=$((ALLOW_ALL_COUNT + ALLOW_ALL))
        fi
    done
    
    echo -e "   📊 Total de reglas DENY encontradas: ${YELLOW}$DENY_RULES_COUNT${NC}"
    echo -e "   📊 Total de reglas ALLOW 0.0.0.0/0: ${YELLOW}$ALLOW_ALL_COUNT${NC}"
    
    if [ "$DENY_RULES_COUNT" -gt 0 ]; then
        echo -e "   ${YELLOW}💡 Revisar reglas DENY para evitar bloqueos no deseados${NC}"
    fi
    
    if [ "$ALLOW_ALL_COUNT" -gt 0 ]; then
        echo -e "   ${YELLOW}💡 Revisar reglas permisivas (0.0.0.0/0) por seguridad${NC}"
    fi
fi

echo ""

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
        
        # Verificar tamaño del log group
        SIZE=$(aws logs describe-log-groups --log-group-name-prefix "$log_group" --profile "$PROFILE" --region "$REGION" --query 'logGroups[0].storedBytes' --output text 2>/dev/null)
        
        if [ "$SIZE" != "None" ] && [ -n "$SIZE" ]; then
            SIZE_MB=$((SIZE / 1024 / 1024))
            echo -e "      Tamaño almacenado: ${BLUE}$SIZE_MB MB${NC}"
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
    echo -e "${RED}❌ No se encontraron CloudWatch Alarms para CIS 3.11${NC}"
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

if [ "$NACL_COUNT" -gt 0 ]; then
    echo -e "✅ Network ACLs: ${GREEN}$NACL_COUNT ACLS MONITOREADAS${NC}"
else
    echo -e "⚠️ Network ACLs: ${YELLOW}NO ENCONTRADAS${NC}"
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
    echo -e "${GREEN}🎉 CIS 3.11 - CONFIGURACIÓN COMPLETA Y FUNCIONAL${NC}"
    echo -e "${BLUE}💡 Network ACL changes monitoring está activo${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN INCOMPLETA${NC}"
    echo -e "${BLUE}💡 Ejecuta el script de configuración para completar CIS 3.11${NC}"
fi

echo ""
echo -e "${BLUE}📋 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Confirmar suscripción de email si está pendiente"
echo "2. Probar las notificaciones con un evento de prueba"
echo "3. Establecer procedimientos de respuesta a cambios de NACL"
echo "4. Revisar reglas DENY que puedan causar interrupciones"
echo "5. Documentar la configuración para el equipo de seguridad"
echo "6. Programar auditorías regulares de Network ACLs"