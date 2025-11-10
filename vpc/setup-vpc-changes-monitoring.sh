#!/bin/bash
# setup-vpc-changes-monitoring.sh
# Configurar monitoring para cambios en VPC
# Regla de seguridad CIS AWS: Configure log metric filter and alarm for VPC changes
# Uso: ./setup-vpc-changes-monitoring.sh [perfil]

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
EMAIL="felipe.castillo@azlogica.com"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔒 IMPLEMENTANDO MONITORING PARA VPC CHANGES${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Regla: Configure log metric filter and alarm for VPC changes"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI no está instalado${NC}"
    exit 1
fi

AWS_VERSION=$(aws --version 2>&1)
echo -e "✅ AWS CLI encontrado: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
echo -e "${PURPLE}🔐 Verificando credenciales para perfil '$PROFILE'...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo verificar las credenciales para el perfil '$PROFILE'${NC}"
    echo -e "${YELLOW}💡 Verifica que el perfil esté configurado correctamente${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Patrón de filtro para cambios en VPC
# Monitorea eventos críticos de VPC
FILTER_PATTERN='{ ($.eventName = CreateVpc) || ($.eventName = DeleteVpc) || ($.eventName = ModifyVpcAttribute) || ($.eventName = AcceptVpcPeeringConnection) || ($.eventName = CreateVpcPeeringConnection) || ($.eventName = DeleteVpcPeeringConnection) || ($.eventName = RejectVpcPeeringConnection) || ($.eventName = AttachVpnGateway) || ($.eventName = DetachVpnGateway) || ($.eventName = CreateVpnConnection) || ($.eventName = DeleteVpnConnection) || ($.eventName = CreateVpnGateway) || ($.eventName = DeleteVpnGateway) || ($.eventName = AssociateDhcpOptions) || ($.eventName = CreateDhcpOptions) || ($.eventName = DeleteDhcpOptions) || ($.eventName = AssociateVpcCidrBlock) || ($.eventName = DisassociateVpcCidrBlock) }'

echo -e "${BLUE}📋 Patrón de filtro configurado:${NC}"
echo -e "${YELLOW}Eventos monitoreados:${NC}"
echo "   • CreateVpc - Creación de VPC"
echo "   • DeleteVpc - Eliminación de VPC"
echo "   • ModifyVpcAttribute - Modificación de atributos VPC"
echo "   • VPC Peering (Create/Delete/Accept/Reject)"
echo "   • VPN Gateway operations (Attach/Detach/Create/Delete)"
echo "   • VPN Connection operations (Create/Delete)"
echo "   • DHCP Options (Associate/Create/Delete)"
echo "   • VPC CIDR Block (Associate/Disassociate)"
echo ""

# Paso 1: Configurar SNS Topic
echo -e "${PURPLE}=== Paso 1: Configurando SNS Topic ===${NC}"

# Verificar si el SNS topic existe
SNS_TOPIC_ARN=$(aws sns list-topics --profile "$PROFILE" --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text 2>/dev/null)

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo -e "${YELLOW}📝 Creando SNS Topic: $SNS_TOPIC_NAME${NC}"
    SNS_TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --profile "$PROFILE" --region "$REGION" --query TopicArn --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$SNS_TOPIC_ARN" ]; then
        echo -e "${RED}❌ Error creando SNS Topic${NC}"
        exit 1
    fi
    
    echo -e "✅ SNS Topic creado: ${GREEN}$SNS_TOPIC_ARN${NC}"
else
    echo -e "✅ SNS Topic existente: ${GREEN}$SNS_TOPIC_ARN${NC}"
fi

# Configurar suscripción de email
echo -e "${BLUE}📬 Configurando suscripción de email...${NC}"

# Verificar si ya existe la suscripción
EXISTING_SUBSCRIPTION=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" --query "Subscriptions[?Endpoint=='$EMAIL' && Protocol=='email'].SubscriptionArn" --output text 2>/dev/null)

if [ -z "$EXISTING_SUBSCRIPTION" ] || [ "$EXISTING_SUBSCRIPTION" == "None" ]; then
    echo -e "   📧 Creando suscripción para: ${BLUE}$EMAIL${NC}"
    aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Suscripción creada exitosamente"
        echo -e "   ${YELLOW}⚠️ Revisa tu email para confirmar la suscripción${NC}"
    else
        echo -e "   ${RED}❌ Error creando suscripción${NC}"
    fi
else
    echo -e "   ✅ Suscripción de email ya existe para: ${BLUE}$EMAIL${NC}"
    
    # Verificar estado de la suscripción
    SUBSCRIPTION_STATUS=$(aws sns get-subscription-attributes --subscription-arn "$EXISTING_SUBSCRIPTION" --profile "$PROFILE" --region "$REGION" --query 'Attributes.PendingConfirmation' --output text 2>/dev/null)
    
    if [ "$SUBSCRIPTION_STATUS" == "true" ]; then
        echo -e "   ${YELLOW}⚠️ Suscripción pendiente de confirmación${NC}"
    else
        echo -e "   ✅ Suscripción confirmada y activa"
    fi
fi

echo ""

# Paso 2: Verificar VPCs existentes
echo -e "${PURPLE}=== Paso 2: Verificando VPCs existentes ===${NC}"

# Contar VPCs
VPC_COUNT=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --query 'length(Vpcs)' --output text 2>/dev/null)

if [ -z "$VPC_COUNT" ] || [ "$VPC_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ No se encontraron VPCs en la cuenta${NC}"
else
    echo -e "✅ VPCs encontradas en la cuenta: ${GREEN}$VPC_COUNT VPCs${NC}"
    echo -e "${BLUE}📋 Estas VPCs serán monitoreadas por cambios${NC}"
    
    # Mostrar información básica de VPCs
    echo -e "${BLUE}📄 Resumen de VPCs (primeros 5):${NC}"
    aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --query 'Vpcs[0:4].[VpcId,State,CidrBlock,Tags[?Key==`Name`].Value | [0]]' --output table 2>/dev/null
    
    # Estadísticas adicionales
    echo -e "${BLUE}🌐 Análisis de VPCs:${NC}"
    
    # VPCs por estado
    AVAILABLE_VPCS=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --filters "Name=state,Values=available" --query 'length(Vpcs)' --output text 2>/dev/null)
    echo -e "   📊 VPCs disponibles: ${GREEN}$AVAILABLE_VPCS${NC}"
    
    # VPC por defecto
    DEFAULT_VPC=$(aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --filters "Name=is-default,Values=true" --query 'length(Vpcs)' --output text 2>/dev/null)
    echo -e "   📊 VPC por defecto: ${GREEN}$DEFAULT_VPC${NC}"
    
    # Análisis de CIDR blocks
    echo -e "   📊 Rangos CIDR configurados:"
    aws ec2 describe-vpcs --profile "$PROFILE" --region "$REGION" --query 'Vpcs[].CidrBlock' --output text 2>/dev/null | sort | uniq -c | while read count cidr; do
        echo -e "      📌 $cidr: ${BLUE}$count VPC(s)${NC}"
    done
    
    # Verificar VPC Peering
    PEERING_COUNT=$(aws ec2 describe-vpc-peering-connections --profile "$PROFILE" --region "$REGION" --query 'length(VpcPeeringConnections)' --output text 2>/dev/null)
    echo -e "   📊 VPC Peering Connections: ${GREEN}$PEERING_COUNT${NC}"
    
    # Verificar VPN Gateways
    VGW_COUNT=$(aws ec2 describe-vpn-gateways --profile "$PROFILE" --region "$REGION" --query 'length(VpnGateways)' --output text 2>/dev/null)
    echo -e "   📊 VPN Gateways: ${GREEN}$VGW_COUNT${NC}"
    
    # Verificar DHCP Options
    DHCP_COUNT=$(aws ec2 describe-dhcp-options --profile "$PROFILE" --region "$REGION" --query 'length(DhcpOptions)' --output text 2>/dev/null)
    echo -e "   📊 DHCP Options Sets: ${GREEN}$DHCP_COUNT${NC}"
fi

echo ""

# Paso 3: Configurar CloudTrail Log Groups
echo -e "${PURPLE}=== Paso 3: Configurando Metric Filters ===${NC}"

# Buscar CloudTrail log groups
LOG_GROUPS=$(aws logs describe-log-groups --profile "$PROFILE" --region "$REGION" --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`)].logGroupName' --output text 2>/dev/null)

if [ -z "$LOG_GROUPS" ]; then
    echo -e "${RED}❌ No se encontraron CloudTrail Log Groups${NC}"
    echo -e "${YELLOW}💡 Asegúrate de tener CloudTrail configurado con CloudWatch Logs${NC}"
    exit 1
fi

echo -e "✅ CloudTrail Log Groups encontrados:"
for log_group in $LOG_GROUPS; do
    echo -e "   📄 $log_group"
done
echo ""

# Configurar metric filters para cada log group
FILTERS_CREATED=0

for LOG_GROUP in $LOG_GROUPS; do
    echo -e "${BLUE}🔧 Configurando metric filter para: $LOG_GROUP${NC}"
    
    # Crear nombre único para el filtro basado en el log group
    CLEAN_LOG_GROUP=$(echo "$LOG_GROUP" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    UNIQUE_FILTER_NAME="$FILTER_NAME-$CLEAN_LOG_GROUP"
    
    # Verificar si el metric filter ya existe
    EXISTING_FILTER=$(aws logs describe-metric-filters --log-group-name "$LOG_GROUP" --filter-name-prefix "$FILTER_NAME" --profile "$PROFILE" --region "$REGION" --query 'metricFilters[0].filterName' --output text 2>/dev/null)
    
    if [ "$EXISTING_FILTER" != "None" ] && [ -n "$EXISTING_FILTER" ]; then
        echo -e "   ✅ Metric filter ya existe: ${GREEN}$EXISTING_FILTER${NC}"
    else
        echo -e "   📝 Creando metric filter: $UNIQUE_FILTER_NAME"
        
        # Crear metric filter
        aws logs put-metric-filter \
            --log-group-name "$LOG_GROUP" \
            --filter-name "$UNIQUE_FILTER_NAME" \
            --filter-pattern "$FILTER_PATTERN" \
            --metric-transformations \
                metricName="$METRIC_NAME",metricNamespace="$METRIC_NAMESPACE",metricValue="1",defaultValue=0 \
            --profile "$PROFILE" \
            --region "$REGION" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ Metric filter creado exitosamente"
            FILTERS_CREATED=$((FILTERS_CREATED + 1))
        else
            echo -e "   ${RED}❌ Error creando metric filter${NC}"
            continue
        fi
    fi
done

echo ""

# Paso 4: Configurar CloudWatch Alarms
echo -e "${PURPLE}=== Paso 4: Configurando CloudWatch Alarms ===${NC}"

ALARMS_CREATED=0

for LOG_GROUP in $LOG_GROUPS; do
    echo -e "${BLUE}⏰ Configurando alarma para: $LOG_GROUP${NC}"
    
    # Crear nombre único para la alarma
    CLEAN_LOG_GROUP=$(echo "$LOG_GROUP" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    UNIQUE_ALARM_NAME="$ALARM_PREFIX-$CLEAN_LOG_GROUP"
    
    # Verificar si la alarma ya existe
    EXISTING_ALARM=$(aws cloudwatch describe-alarms --alarm-names "$UNIQUE_ALARM_NAME" --profile "$PROFILE" --region "$REGION" --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null)
    
    if [ "$EXISTING_ALARM" != "None" ] && [ -n "$EXISTING_ALARM" ]; then
        echo -e "   ✅ CloudWatch Alarm ya existe: ${GREEN}$EXISTING_ALARM${NC}"
    else
        echo -e "   📝 Creando CloudWatch Alarm: $UNIQUE_ALARM_NAME"
        
        # Crear alarma
        aws cloudwatch put-metric-alarm \
            --alarm-name "$UNIQUE_ALARM_NAME" \
            --alarm-description "CIS - VPC Changes Detected in $LOG_GROUP" \
            --actions-enabled \
            --alarm-actions "$SNS_TOPIC_ARN" \
            --metric-name "$METRIC_NAME" \
            --namespace "$METRIC_NAMESPACE" \
            --statistic Sum \
            --period 300 \
            --threshold 1 \
            --comparison-operator GreaterThanOrEqualToThreshold \
            --datapoints-to-alarm 1 \
            --evaluation-periods 1 \
            --treat-missing-data notBreaching \
            --profile "$PROFILE" \
            --region "$REGION" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ CloudWatch Alarm creada exitosamente"
            ALARMS_CREATED=$((ALARMS_CREATED + 1))
        else
            echo -e "   ${RED}❌ Error creando CloudWatch Alarm${NC}"
        fi
    fi
done

echo ""

# Resumen final
echo -e "${PURPLE}=== RESUMEN DE CONFIGURACIÓN ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📧 SNS Topic: ${GREEN}$SNS_TOPIC_ARN${NC}"
echo -e "📊 VPCs monitoreadas: ${GREEN}$VPC_COUNT${NC}"
echo -e "📋 CloudTrail Log Groups: ${GREEN}$(echo $LOG_GROUPS | wc -w)${NC}"
echo -e "🔧 Metric Filters creados: ${GREEN}$FILTERS_CREATED${NC}"
echo -e "⏰ CloudWatch Alarms creadas: ${GREEN}$ALARMS_CREATED${NC}"

echo ""
echo -e "${GREEN}🎉 CONFIGURACIÓN COMPLETADA${NC}"
echo -e "${BLUE}💡 VPC Changes Monitoring está ahora activo${NC}"
echo ""

echo -e "${YELLOW}📋 EVENTOS QUE ACTIVARÁN ALERTAS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🏗️  VPC Lifecycle:"
echo "   • CreateVpc - Creación de nueva VPC"
echo "   • DeleteVpc - Eliminación de VPC"
echo "   • ModifyVpcAttribute - Cambios en atributos (DNS, DHCP, etc.)"
echo ""
echo "🔗 VPC Peering:"
echo "   • CreateVpcPeeringConnection - Nueva conexión peering"
echo "   • AcceptVpcPeeringConnection - Aceptación de peering"
echo "   • RejectVpcPeeringConnection - Rechazo de peering"
echo "   • DeleteVpcPeeringConnection - Eliminación de peering"
echo ""
echo "🌐 VPN Connectivity:"
echo "   • CreateVpnConnection/DeleteVpnConnection - Conexiones VPN"
echo "   • CreateVpnGateway/DeleteVpnGateway - Gateways VPN"
echo "   • AttachVpnGateway/DetachVpnGateway - Asociaciones VPN"
echo ""
echo "⚙️  Network Configuration:"
echo "   • AssociateDhcpOptions - Cambios en opciones DHCP"
echo "   • CreateDhcpOptions/DeleteDhcpOptions - Gestión DHCP"
echo "   • AssociateVpcCidrBlock/DisassociateVpcCidrBlock - CIDR blocks"
echo ""

echo -e "${BLUE}📋 PRÓXIMOS PASOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Confirmar suscripción de email si está pendiente"
echo "2. Probar las notificaciones con un evento de prueba"
echo "3. Establecer procedimientos de respuesta a cambios de VPC"
echo "4. Revisar configuraciones críticas de VPC regularmente"
echo "5. Documentar la configuración para el equipo de seguridad"
echo "6. Considerar alertas adicionales para recursos VPC específicos"