#!/bin/bash
# setup-nacl-changes-monitoring.sh
# Create log metric filter and alarm for NACL (Network Access Control List) changes
# Regla de seguridad CIS AWS: 3.11 - Monitor NACL changes
# Uso: ./setup-nacl-changes-monitoring.sh [perfil]

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
ALARM_NAME="CIS-3.11-NACLChanges"
SNS_TOPIC_NAME="cis-security-alerts"
ALARM_DESCRIPTION="CIS 3.11 - Network Access Control List (NACL) changes detected"
NOTIFICATION_EMAIL="felipe.castillo@azlogica.com"

# Patrón del filtro para detectar cambios en NACLs
FILTER_PATTERN='{ ($.eventName = "CreateNetworkAcl") || ($.eventName = "CreateNetworkAclEntry") || ($.eventName = "DeleteNetworkAcl") || ($.eventName = "DeleteNetworkAclEntry") || ($.eventName = "ReplaceNetworkAclEntry") || ($.eventName = "ReplaceNetworkAclAssociation") }'

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔒 IMPLEMENTANDO CIS 3.11 - NACL CHANGES MONITORING${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Regla: Create log metric filter and alarm for NACL changes"
echo ""

# Verificar prerrequisitos
echo -e "${BLUE}🔍 Verificando prerrequisitos...${NC}"

# Verificar si AWS CLI está instalado
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI no está instalado${NC}"
    exit 1
fi

AWS_VERSION=$(aws --version 2>&1)
echo -e "✅ AWS CLI encontrado: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales del perfil
echo -e "${BLUE}🔐 Verificando credenciales para perfil '$PROFILE'...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo verificar las credenciales para el perfil '$PROFILE'${NC}"
    echo -e "${YELLOW}💡 Verifica que el perfil esté configurado correctamente${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Paso 1: Configurar SNS Topic
echo -e "${PURPLE}=== Paso 1: Configurando SNS Topic ===${NC}"

# Verificar si el topic ya existe
SNS_TOPIC_ARN=$(aws sns list-topics --profile "$PROFILE" --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text 2>/dev/null)

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo -e "${YELLOW}⚠️ SNS Topic no existe, creando...${NC}"
    SNS_TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --profile "$PROFILE" --region "$REGION" --query TopicArn --output text)
    echo -e "✅ SNS Topic creado: ${GREEN}$SNS_TOPIC_ARN${NC}"
else
    echo -e "✅ SNS Topic existente: ${GREEN}$SNS_TOPIC_ARN${NC}"
fi

# Configurar suscripción de email
echo -e "${BLUE}📬 Configurando suscripción de email...${NC}"
EXISTING_SUBSCRIPTION=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" --query "Subscriptions[?Endpoint=='$NOTIFICATION_EMAIL'].SubscriptionArn" --output text 2>/dev/null)

if [ -z "$EXISTING_SUBSCRIPTION" ] || [ "$EXISTING_SUBSCRIPTION" == "None" ]; then
    aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol email --notification-endpoint "$NOTIFICATION_EMAIL" --profile "$PROFILE" --region "$REGION" > /dev/null 2>&1
    echo -e "   📧 Suscripción de email creada para: ${GREEN}$NOTIFICATION_EMAIL${NC}"
    echo -e "   ${YELLOW}⚠️ Revisa tu email y confirma la suscripción${NC}"
else
    echo -e "   ✅ Suscripción de email ya existe para: ${GREEN}$NOTIFICATION_EMAIL${NC}"
    
    # Verificar el estado de la suscripción
    SUB_STATUS=$(aws sns get-subscription-attributes --subscription-arn "$EXISTING_SUBSCRIPTION" --profile "$PROFILE" --region "$REGION" --query 'Attributes.PendingConfirmation' --output text 2>/dev/null)
    if [ "$SUB_STATUS" == "false" ]; then
        echo -e "   ✅ Suscripción confirmada y activa"
    else
        echo -e "   ${YELLOW}⚠️ Suscripción pendiente de confirmación${NC}"
    fi
fi

echo ""

# Paso 2: Verificar NACLs existentes
echo -e "${PURPLE}=== Paso 2: Verificando Network ACLs existentes ===${NC}"

# Contar NACLs
NACL_COUNT=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --query 'length(NetworkAcls)' --output text 2>/dev/null)

if [ -z "$NACL_COUNT" ] || [ "$NACL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠️ No se encontraron Network ACLs en la cuenta${NC}"
else
    echo -e "✅ Network ACLs encontradas en la cuenta: ${GREEN}$NACL_COUNT ACLs${NC}"
    echo -e "📋 Estas ACLs de red serán monitoreadas por cambios"
    
    # Mostrar ejemplos de NACLs (primeros 3)
    echo -e "${BLUE}📄 Ejemplos de Network ACLs (primeros 3):${NC}"
    aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --query 'NetworkAcls[:3].[NetworkAclId,VpcId,IsDefault]' --output table 2>/dev/null | head -10
    
    # Verificar VPCs asociadas
    echo -e "${BLUE}🌐 VPCs con Network ACLs:${NC}"
    VPC_LIST=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --query 'NetworkAcls[].VpcId' --output text 2>/dev/null | tr '\t' '\n' | sort | uniq)
    
    for vpc in $VPC_LIST; do
        VPC_NAME=$(aws ec2 describe-vpcs --vpc-ids "$vpc" --profile "$PROFILE" --region "$REGION" --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null)
        NACL_COUNT_VPC=$(aws ec2 describe-network-acls --profile "$PROFILE" --region "$REGION" --filters "Name=vpc-id,Values=$vpc" --query 'length(NetworkAcls)' --output text 2>/dev/null)
        
        if [ -z "$VPC_NAME" ] || [ "$VPC_NAME" == "None" ]; then
            VPC_NAME="Sin nombre"
        fi
        
        echo -e "   📄 VPC $vpc ($VPC_NAME): ${GREEN}$NACL_COUNT_VPC ACLs${NC}"
    done
fi

echo ""

# Paso 3: Identificar CloudTrail Log Groups
echo -e "${PURPLE}=== Paso 3: Identificando CloudTrail Log Groups ===${NC}"

# Buscar log groups de CloudTrail
LOG_GROUPS=$(aws logs describe-log-groups --profile "$PROFILE" --region "$REGION" --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`)].logGroupName' --output text 2>/dev/null)

if [ -z "$LOG_GROUPS" ]; then
    echo -e "${RED}❌ No se encontraron CloudTrail Log Groups${NC}"
    echo -e "${YELLOW}💡 CloudTrail debe estar configurado para enviar logs a CloudWatch${NC}"
    exit 1
fi

echo -e "${GREEN}✅ CloudTrail Log Groups encontrados:${NC}"
for log_group in $LOG_GROUPS; do
    echo -e "   - $log_group"
done
echo ""

# Paso 4: Configurar Metric Filters y CloudWatch Alarms
echo -e "${PURPLE}=== Paso 4: Configurando Metric Filters y CloudWatch Alarms ===${NC}"

FILTERS_CREATED=0
ALARMS_CREATED=0

for LOG_GROUP in $LOG_GROUPS; do
    echo -e "${BLUE}📄 Procesando Log Group: $LOG_GROUP${NC}"
    
    # Limpiar el nombre del log group para usarlo en nombres de recursos
    CLEAN_LOG_GROUP=$(echo "$LOG_GROUP" | sed 's/[^a-zA-Z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g')
    
    METRIC_FILTER_NAME="$FILTER_NAME-$CLEAN_LOG_GROUP"
    ALARM_NAME_FULL="$ALARM_NAME-$CLEAN_LOG_GROUP"
    
    # Verificar si el metric filter ya existe
    EXISTING_FILTER=$(aws logs describe-metric-filters --log-group-name "$LOG_GROUP" --filter-name-prefix "$METRIC_FILTER_NAME" --profile "$PROFILE" --region "$REGION" --query 'metricFilters[0].filterName' --output text 2>/dev/null)
    
    if [ "$EXISTING_FILTER" != "None" ] && [ -n "$EXISTING_FILTER" ]; then
        echo -e "   ${YELLOW}⚠️ Metric Filter ya existe, actualizando...${NC}"
    else
        echo -e "   🔧 Creando nuevo Metric Filter...${NC}"
    fi
    
    # Crear/actualizar metric filter
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP" \
        --filter-name "$METRIC_FILTER_NAME" \
        --filter-pattern "$FILTER_PATTERN" \
        --metric-transformations \
            metricName="$METRIC_NAME",metricNamespace="$METRIC_NAMESPACE",metricValue="1" \
        --profile "$PROFILE" \
        --region "$REGION" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Metric Filter configurado"
        FILTERS_CREATED=$((FILTERS_CREATED + 1))
    else
        echo -e "   ${RED}❌ Error configurando Metric Filter${NC}"
        continue
    fi
    
    # Configurar CloudWatch Alarm
    echo -e "   ⏰ Configurando CloudWatch Alarm: ${BLUE}$ALARM_NAME_FULL${NC}"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME_FULL" \
        --alarm-description "$ALARM_DESCRIPTION" \
        --metric-name "$METRIC_NAME" \
        --namespace "$METRIC_NAMESPACE" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --profile "$PROFILE" \
        --region "$REGION" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ CloudWatch Alarm configurado"
        ALARMS_CREATED=$((ALARMS_CREATED + 1))
    else
        echo -e "   ${RED}❌ Error configurando CloudWatch Alarm${NC}"
    fi
    
    echo ""
done

# Resumen final
echo "=================================================================="
echo -e "${GREEN}🎉 IMPLEMENTACIÓN CIS 3.11 COMPLETADA${NC}"
echo "=================================================================="
echo -e "Perfil procesado: ${GREEN}$PROFILE${NC} (Account: ${GREEN}$ACCOUNT_ID${NC})"
echo -e "Metric Filters creados: ${GREEN}$FILTERS_CREATED${NC}"
echo -e "CloudWatch Alarms creadas: ${GREEN}$ALARMS_CREATED${NC}"
echo -e "SNS Topic: ${GREEN}$SNS_TOPIC_ARN${NC}"
echo ""

echo -e "${BLUE}📋 ¿QUÉ SE HA CONFIGURADO?${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Metric Filters para detectar cambios en Network ACLs"
echo "✅ CloudWatch Alarms para alertas de modificaciones de ACL de red"
echo "✅ SNS Topic para notificaciones inmediatas de seguridad"
echo "✅ Cumplimiento con CIS AWS Benchmark 3.11"
echo ""

echo -e "${BLUE}🔍 EVENTOS NACL MONITOREADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• CreateNetworkAcl - Creación de nuevas ACLs de red"
echo "• CreateNetworkAclEntry - Creación de reglas en ACLs"
echo "• DeleteNetworkAcl - Eliminación de ACLs de red"
echo "• DeleteNetworkAclEntry - Eliminación de reglas de ACLs"
echo "• ReplaceNetworkAclEntry - Modificación de reglas existentes"
echo "• ReplaceNetworkAclAssociation - Cambios de asociación ACL-subnet"
echo ""

echo -e "${RED}⚠️ IMPORTANCIA DE ESTA REGLA:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Network ACLs proporcionan control de tráfico a nivel de subred"
echo "• Son la segunda línea de defensa después de Security Groups"
echo "• Cambios no autorizados pueden bloquear o permitir tráfico no deseado"
echo "• Reglas maliciosas pueden interrumpir servicios críticos"
echo "• Modificaciones accidentales pueden afectar conectividad de subredes completas"
echo "• Detección temprana previene interrupciones de red y brechas de seguridad"
echo ""

echo -e "${YELLOW}🔔 PRÓXIMOS PASOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. ✅ Suscripción de email configurada automáticamente"
echo -e "   📧 Revisa tu email (${GREEN}$NOTIFICATION_EMAIL${NC}) y confirma la suscripción"
echo ""
echo "2. Verificar el estado de las alarmas:"
echo -e "   ${BLUE}./verify-nacl-changes-monitoring.sh${NC}"
echo ""
echo "3. Probar las notificaciones (opcional):"
echo -e "   ${BLUE}aws sns publish --topic-arn $SNS_TOPIC_ARN --message 'Prueba de notificación CIS 3.11' --profile $PROFILE${NC}"
echo ""
echo "4. Establecer procedimientos de respuesta para cambios de NACL:"
echo "   - Investigar inmediatamente cambios no autorizados en ACLs de red"
echo "   - Revisar nuevas reglas que puedan bloquear tráfico crítico"
echo "   - Validar eliminación de ACLs con el equipo de infraestructura"
echo "   - Auditar cambios de asociaciones ACL-subnet"
echo "   - Verificar reglas DENY que puedan interrumpir servicios"
echo ""
echo "5. Monitorear regularmente las alertas y patrones de cambios"
echo ""
echo "6. Documentar esta configuración en la política de seguridad de red"