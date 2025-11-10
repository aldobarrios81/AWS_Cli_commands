#!/bin/bash
# verify-route-table-changes-monitoring.sh
# Verificar configuración de monitoring para cambios en Route Tables
# Regla de seguridad CIS AWS: 3.13 - Monitor route table changes
# Uso: ./verify-route-table-changes-monitoring.sh [perfil]

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
METRIC_NAME="RouteTableChanges"
FILTER_NAME="CIS-RouteTableChanges"
ALARM_PREFIX="CIS-3.13-RouteTableChanges"
SNS_TOPIC_NAME="cis-security-alerts"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICANDO CIS 3.13 - ROUTE TABLE CHANGES MONITORING${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Verificando configuración de monitoreo para cambios en Route Tables"
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

# Verificar Route Tables en la cuenta
echo -e "${PURPLE}=== Verificando Route Tables en la cuenta ===${NC}"

# Contar y analizar Route Tables
RT_COUNT=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --query 'length(RouteTables)' --output text 2>/dev/null)

if [ -z "$RT_COUNT" ] || [ "$RT_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ No se encontraron Route Tables${NC}"
else
    echo -e "${GREEN}✅ Route Tables encontradas: $RT_COUNT tablas${NC}"
    
    # Mostrar estadísticas de Route Tables
    echo -e "${BLUE}📊 Estadísticas de Route Tables:${NC}"
    
    # Route Tables por VPC
    echo -e "${BLUE}📄 Route Tables por VPC:${NC}"
    VPC_LIST=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --query 'RouteTables[].VpcId' --output text 2>/dev/null | tr '\t' '\n' | sort | uniq)
    
    MAIN_TABLES_TOTAL=0
    CUSTOM_TABLES_TOTAL=0
    
    for vpc in $VPC_LIST; do
        VPC_NAME=$(aws ec2 describe-vpcs --vpc-ids "$vpc" --profile "$PROFILE" --region "$REGION" --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null)
        RT_COUNT_VPC=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --filters "Name=vpc-id,Values=$vpc" --query 'length(RouteTables)' --output text 2>/dev/null)
        
        if [ -z "$VPC_NAME" ] || [ "$VPC_NAME" == "None" ]; then
            VPC_NAME="Sin nombre"
        fi
        
        # Contar main vs custom route tables
        MAIN_RT=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --filters "Name=vpc-id,Values=$vpc" --query 'length(RouteTables[?Associations[?Main==`true`]])' --output text 2>/dev/null)
        CUSTOM_RT=$((RT_COUNT_VPC - MAIN_RT))
        
        MAIN_TABLES_TOTAL=$((MAIN_TABLES_TOTAL + MAIN_RT))
        CUSTOM_TABLES_TOTAL=$((CUSTOM_TABLES_TOTAL + CUSTOM_RT))
        
        echo -e "   📄 VPC $vpc ($VPC_NAME): ${GREEN}$RT_COUNT_VPC tablas${NC}"
        echo -e "      📌 Main: ${BLUE}$MAIN_RT${NC} | Custom: ${BLUE}$CUSTOM_RT${NC}"
        
        # Mostrar información de subnets asociadas
        SUBNET_COUNT=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --filters "Name=vpc-id,Values=$vpc" --query 'sum(RouteTables[].length(Associations))' --output text 2>/dev/null)
        echo -e "      🔗 Asociaciones subnet: ${BLUE}$SUBNET_COUNT${NC}"
    done
    
    echo ""
    echo -e "📊 Resumen Global:"
    echo -e "   📌 Total Main Route Tables: ${GREEN}$MAIN_TABLES_TOTAL${NC}"
    echo -e "   📌 Total Custom Route Tables: ${GREEN}$CUSTOM_TABLES_TOTAL${NC}"
    
    echo ""
    
    # Análisis de rutas críticas
    echo -e "${BLUE}🛣️ Análisis de Rutas Críticas:${NC}"
    
    # Contar rutas por defecto (0.0.0.0/0)
    DEFAULT_ROUTES_COUNT=0
    IGW_ROUTES_COUNT=0
    NAT_ROUTES_COUNT=0
    VGW_ROUTES_COUNT=0
    
    # Obtener todas las route tables y analizar sus rutas
    ROUTE_TABLES=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --query 'RouteTables[].RouteTableId' --output text 2>/dev/null)
    
    for rt_id in $ROUTE_TABLES; do
        # Contar rutas por defecto
        DEFAULT_COUNT=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --profile "$PROFILE" --region "$REGION" --query 'length(RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`])' --output text 2>/dev/null)
        
        if [ -n "$DEFAULT_COUNT" ] && [ "$DEFAULT_COUNT" -gt 0 ]; then
            DEFAULT_ROUTES_COUNT=$((DEFAULT_ROUTES_COUNT + DEFAULT_COUNT))
            
            # Analizar el tipo de gateway de las rutas por defecto
            IGW_COUNT=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --profile "$PROFILE" --region "$REGION" --query 'length(RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0` && starts_with(GatewayId, `igw-`)])' --output text 2>/dev/null)
            NAT_COUNT=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --profile "$PROFILE" --region "$REGION" --query 'length(RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0` && starts_with(NatGatewayId, `nat-`)])' --output text 2>/dev/null)
            VGW_COUNT=$(aws ec2 describe-route-tables --route-table-ids "$rt_id" --profile "$PROFILE" --region "$REGION" --query 'length(RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0` && starts_with(GatewayId, `vgw-`)])' --output text 2>/dev/null)
            
            IGW_ROUTES_COUNT=$((IGW_ROUTES_COUNT + IGW_COUNT))
            NAT_ROUTES_COUNT=$((NAT_ROUTES_COUNT + NAT_COUNT))
            VGW_ROUTES_COUNT=$((VGW_ROUTES_COUNT + VGW_COUNT))
        fi
    done
    
    echo -e "   🌐 Rutas por defecto (0.0.0.0/0): ${YELLOW}$DEFAULT_ROUTES_COUNT${NC}"
    echo -e "      📌 A Internet Gateway: ${GREEN}$IGW_ROUTES_COUNT${NC}"
    echo -e "      📌 A NAT Gateway: ${GREEN}$NAT_ROUTES_COUNT${NC}"
    echo -e "      📌 A VPN Gateway: ${GREEN}$VGW_ROUTES_COUNT${NC}"
    
    # Contar total de rutas
    TOTAL_ROUTES=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --query 'sum(RouteTables[].length(Routes))' --output text 2>/dev/null)
    echo -e "   📊 Total de rutas en todas las tablas: ${GREEN}$TOTAL_ROUTES${NC}"
    
    # Alertas de seguridad
    if [ "$IGW_ROUTES_COUNT" -gt 0 ]; then
        echo -e "   ${YELLOW}⚠️ Rutas directas a Internet encontradas - Revisar exposición${NC}"
    fi
    
    if [ "$DEFAULT_ROUTES_COUNT" -eq 0 ]; then
        echo -e "   ${GREEN}✅ No hay rutas por defecto configuradas${NC}"
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
    echo -e "${RED}❌ No se encontraron CloudWatch Alarms para CIS 3.13${NC}"
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

if [ "$RT_COUNT" -gt 0 ]; then
    echo -e "✅ Route Tables: ${GREEN}$RT_COUNT TABLAS MONITOREADAS${NC}"
    echo -e "   📌 Main: ${GREEN}$MAIN_TABLES_TOTAL${NC} | Custom: ${GREEN}$CUSTOM_TABLES_TOTAL${NC}"
    echo -e "   📊 Total rutas: ${GREEN}$TOTAL_ROUTES${NC} | Rutas por defecto: ${YELLOW}$DEFAULT_ROUTES_COUNT${NC}"
else
    echo -e "⚠️ Route Tables: ${YELLOW}NO ENCONTRADAS${NC}"
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
    echo -e "${GREEN}🎉 CIS 3.13 - CONFIGURACIÓN COMPLETA Y FUNCIONAL${NC}"
    echo -e "${BLUE}💡 Route Table changes monitoring está activo${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN INCOMPLETA${NC}"
    echo -e "${BLUE}💡 Ejecuta el script de configuración para completar CIS 3.13${NC}"
fi

echo ""
echo -e "${BLUE}📋 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Confirmar suscripción de email si está pendiente"
echo "2. Probar las notificaciones con un evento de prueba"
echo "3. Establecer procedimientos de respuesta a cambios de Route Table"
echo "4. Revisar rutas por defecto hacia Internet (IGW)"
echo "5. Documentar la configuración para el equipo de seguridad"
echo "6. Programar auditorías regulares de Route Tables"