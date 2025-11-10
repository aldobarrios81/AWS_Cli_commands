#!/bin/bash
# verify-vpc-changes-monitoring.sh
# Verificar configuración de monitoring para cambios en VPC
# Regla de seguridad CIS AWS: Configure log metric filter and alarm for VPC changes
# Uso: ./verify-vpc-changes-monitoring.sh [perfil]

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
METRIC_NAME="VpcChanges"
FILTER_NAME="CIS-VpcChanges"
ALARM_PREFIX="CIS-VpcChanges"
SNS_TOPIC_NAME="cis-security-alerts"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICANDO VPC CHANGES MONITORING${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Verificando configuración de monitoreo para cambios en VPC"
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

# Verificar VPCs en la cuenta
echo -e "${PURPLE}=== Verificando VPCs en la cuenta ===${NC}"

# Contar y analizar VPCs
VPC_COUNT=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --query 'length(Vpcs)' --output text 2>/dev/null)

if [ -z "$VPC_COUNT" ] || [ "$VPC_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ No se encontraron VPCs${NC}"
else
    echo -e "${GREEN}✅ VPCs encontradas: $VPC_COUNT VPCs${NC}"
    
    # Mostrar estadísticas detalladas de VPCs
    echo -e "${BLUE}📊 Estadísticas de VPCs:${NC}"
    
    # VPCs por estado
    AVAILABLE_VPCS=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --filters "Name=state,Values=available" --query 'length(Vpcs)' --output text 2>/dev/null)
    PENDING_VPCS=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --filters "Name=state,Values=pending" --query 'length(Vpcs)' --output text 2>/dev/null)
    
    echo -e "   📊 Estados de VPCs:"
    echo -e "      ✅ Disponibles: ${GREEN}$AVAILABLE_VPCS${NC}"
    if [ "$PENDING_VPCS" -gt 0 ]; then
        echo -e "      ⏳ Pendientes: ${YELLOW}$PENDING_VPCS${NC}"
    fi
    
    # VPC por defecto
    DEFAULT_VPC_COUNT=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --filters "Name=is-default,Values=true" --query 'length(Vpcs)' --output text 2>/dev/null)
    CUSTOM_VPC_COUNT=$((VPC_COUNT - DEFAULT_VPC_COUNT))
    
    echo -e "   📊 Tipos de VPCs:"
    echo -e "      🏠 VPC por defecto: ${GREEN}$DEFAULT_VPC_COUNT${NC}"
    echo -e "      🏗️ VPCs personalizadas: ${GREEN}$CUSTOM_VPC_COUNT${NC}"
    
    # Análisis detallado de VPCs
    echo -e "${BLUE}📄 Detalle de VPCs:${NC}"
    
    VPC_LIST=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --query 'Vpcs[].VpcId' --output text 2>/dev/null)
    
    for vpc_id in $VPC_LIST; do
        VPC_INFO=$(aws ec2 describe-vpcs --vpc-ids "$vpc_id" --profile "$PROFILE" --region "$REGION" --query 'Vpcs[0]' --output json 2>/dev/null)
        
        VPC_NAME=$(echo "$VPC_INFO" | jq -r '.Tags[]? | select(.Key=="Name") | .Value // "Sin nombre"' 2>/dev/null)
        VPC_CIDR=$(echo "$VPC_INFO" | jq -r '.CidrBlock' 2>/dev/null)
        VPC_STATE=$(echo "$VPC_INFO" | jq -r '.State' 2>/dev/null)
        VPC_DEFAULT=$(echo "$VPC_INFO" | jq -r '.IsDefault' 2>/dev/null)
        
        if [ -z "$VPC_NAME" ] || [ "$VPC_NAME" == "null" ]; then
            VPC_NAME="Sin nombre"
        fi
        
        # Configurar color según si es VPC por defecto
        if [ "$VPC_DEFAULT" == "true" ]; then
            VPC_TYPE_COLOR="${YELLOW}"
            VPC_TYPE="[Default]"
        else
            VPC_TYPE_COLOR="${BLUE}"
            VPC_TYPE="[Custom]"
        fi
        
        echo -e "   📄 VPC: ${GREEN}$vpc_id${NC} ($VPC_NAME)"
        echo -e "      ${VPC_TYPE_COLOR}$VPC_TYPE${NC} Estado: ${GREEN}$VPC_STATE${NC} | CIDR: ${BLUE}$VPC_CIDR${NC}"
        
        # Contar recursos asociados
        SUBNET_COUNT=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --profile "$PROFILE" --region "$REGION" --query 'length(Subnets)' --output text 2>/dev/null)
        IGW_COUNT=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --profile "$PROFILE" --region "$REGION" --query 'length(InternetGateways)' --output text 2>/dev/null)
        RT_COUNT=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --profile "$PROFILE" --region "$REGION" --query 'length(RouteTables)' --output text 2>/dev/null)
        SG_COUNT=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --profile "$PROFILE" --region "$REGION" --query 'length(SecurityGroups)' --output text 2>/dev/null)
        
        echo -e "      📊 Recursos: Subnets:${BLUE}$SUBNET_COUNT${NC} | IGW:${BLUE}$IGW_COUNT${NC} | RT:${BLUE}$RT_COUNT${NC} | SG:${BLUE}$SG_COUNT${NC}"
        
        # Verificar configuraciones críticas
        DNS_HOSTNAMES=$(echo "$VPC_INFO" | jq -r '.DnsHostnames // false' 2>/dev/null)
        DNS_SUPPORT=$(echo "$VPC_INFO" | jq -r '.DnsSupport // false' 2>/dev/null)
        
        echo -e "      ⚙️ DNS Hostnames: ${BLUE}$DNS_HOSTNAMES${NC} | DNS Support: ${BLUE}$DNS_SUPPORT${NC}"
        
        # Verificar DHCP Options
        DHCP_OPTIONS_ID=$(echo "$VPC_INFO" | jq -r '.DhcpOptionsId' 2>/dev/null)
        if [ -n "$DHCP_OPTIONS_ID" ] && [ "$DHCP_OPTIONS_ID" != "null" ]; then
            echo -e "      🔧 DHCP Options: ${BLUE}$DHCP_OPTIONS_ID${NC}"
        fi
        
        echo ""
    done
    
    # Verificar VPC Peering
    echo -e "${BLUE}🔗 VPC Peering Connections:${NC}"
    PEERING_COUNT=$(aws ec2 describe-vpc-peering-connections --profile "$PROFILE" --region "$REGION" --query 'length(VpcPeeringConnections)' --output text 2>/dev/null)
    
    if [ "$PEERING_COUNT" -gt 0 ]; then
        echo -e "   ✅ Conexiones de peering encontradas: ${GREEN}$PEERING_COUNT${NC}"
        
        # Mostrar estado de conexiones
        aws ec2 describe-vpc-peering-connections --profile "$PROFILE" --region "$REGION" --query 'VpcPeeringConnections[].[VpcPeeringConnectionId,Status.Code,RequesterVpcInfo.VpcId,AccepterVpcInfo.VpcId]' --output table 2>/dev/null
    else
        echo -e "   📄 No hay conexiones VPC peering configuradas"
    fi
    
    # Verificar VPN Gateways
    echo -e "${BLUE}🌐 VPN Gateways:${NC}"
    VGW_COUNT=$(aws ec2 describe-vpn-gateways --profile "$PROFILE" --region "$REGION" --query 'length(VpnGateways)' --output text 2>/dev/null)
    
    if [ "$VGW_COUNT" -gt 0 ]; then
        echo -e "   ✅ VPN Gateways encontrados: ${GREEN}$VGW_COUNT${NC}"
        aws ec2 describe-vpn-gateways --profile "$PROFILE" --region "$REGION" --query 'VpnGateways[].[VpnGatewayId,State,Type,VpcAttachments[0].VpcId]' --output table 2>/dev/null
    else
        echo -e "   📄 No hay VPN Gateways configurados"
    fi
    
    # Verificar DHCP Options Sets
    echo -e "${BLUE}⚙️ DHCP Options Sets:${NC}"
    DHCP_COUNT=$(aws ec2 describe-dhcp-options --profile "$PROFILE" --region "$REGION" --query 'length(DhcpOptions)' --output text 2>/dev/null)
    echo -e "   📊 DHCP Options Sets configurados: ${GREEN}$DHCP_COUNT${NC}"
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
    echo -e "${RED}❌ No se encontraron CloudWatch Alarms para VPC Changes${NC}"
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

if [ "$VPC_COUNT" -gt 0 ]; then
    echo -e "✅ VPCs: ${GREEN}$VPC_COUNT VPCS MONITOREADAS${NC}"
    echo -e "   📊 Disponibles: ${GREEN}$AVAILABLE_VPCS${NC} | Por defecto: ${GREEN}$DEFAULT_VPC_COUNT${NC} | Personalizadas: ${GREEN}$CUSTOM_VPC_COUNT${NC}"
    echo -e "   🔗 VPC Peering: ${GREEN}$PEERING_COUNT${NC} | VPN Gateways: ${GREEN}$VGW_COUNT${NC} | DHCP Options: ${GREEN}$DHCP_COUNT${NC}"
else
    echo -e "⚠️ VPCs: ${YELLOW}NO ENCONTRADAS${NC}"
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
    echo -e "${GREEN}🎉 VPC CHANGES MONITORING - CONFIGURACIÓN COMPLETA Y FUNCIONAL${NC}"
    echo -e "${BLUE}💡 VPC changes monitoring está activo${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN INCOMPLETA${NC}"
    echo -e "${BLUE}💡 Ejecuta el script de configuración para completar VPC monitoring${NC}"
fi

echo ""
echo -e "${BLUE}📋 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Confirmar suscripción de email si está pendiente"
echo "2. Probar las notificaciones con un evento de prueba"
echo "3. Establecer procedimientos de respuesta a cambios de VPC"
echo "4. Revisar configuraciones críticas de VPC regularmente"
echo "5. Documentar arquitectura de red y dependencias VPC"
echo "6. Implementar controles adicionales para VPC críticas"