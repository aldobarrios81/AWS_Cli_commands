#!/bin/bash
# setup-root-account-usage-monitoring-ancla.sh
# Configure log metric filter and alarm for root account usage
# Regla de seguridad CIS AWS: 3.3 - Monitor root account usage
# Perfil: ancla | Región: us-east-1

# Configuración específica para perfil azcenit
PROFILE="azcenit"
REGION="us-east-1"
METRIC_NAMESPACE="CISBenchmark"
METRIC_NAME="RootAccountUsage"
FILTER_NAME="CIS-RootAccountUsage"
ALARM_NAME="CIS-3.3-RootAccountUsage"
SNS_TOPIC_NAME="cis-security-alerts"
ALARM_DESCRIPTION="CIS 3.3 - Root account usage detected"
NOTIFICATION_EMAIL="felipe.castillo@azlogica.com"

# Patrón del filtro para detectar uso de cuenta root
FILTER_PATTERN='{ $.userIdentity.type = "Root" && $.userIdentity.invokedBy NOT EXISTS && $.eventType != "AwsServiceEvent" }'

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔒 IMPLEMENTANDO CIS 3.3 - ROOT ACCOUNT USAGE MONITORING${NC}"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Regla: Configure log metric filter and alarm for root account usage"
echo ""

# Verificar prerrequisitos
echo -e "${YELLOW}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ ERROR: AWS CLI no está instalado${NC}"
    echo ""
    echo "📋 INSTRUCCIONES DE INSTALACIÓN:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Instalar AWS CLI v2:"
    echo "   curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
    echo "   unzip awscliv2.zip"
    echo "   sudo ./aws/install"
    echo ""
    echo "2. Configurar perfil 'azcenit':"
    echo "   aws configure --profile azcenit"
    echo ""
    echo "3. Ejecutar este script nuevamente"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ AWS CLI encontrado: $(aws --version)${NC}"

# Obtener Account ID
echo -e "${BLUE}🔐 Verificando credenciales para perfil '$PROFILE'...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query 'Account' --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ ERROR: No se puede obtener el Account ID${NC}"
    echo ""
    echo "📋 POSIBLES SOLUCIONES:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Verificar que el perfil '$PROFILE' esté configurado:"
    echo "   aws configure list --profile $PROFILE"
    echo ""
    echo "2. Configurar el perfil si no existe:"
    echo "   aws configure --profile $PROFILE"
    echo ""
    echo "3. Verificar credenciales:"
    echo "   aws sts get-caller-identity --profile $PROFILE"
    echo ""
    echo "4. Verificar permisos IAM necesarios:"
    echo "   - logs:DescribeLogGroups"
    echo "   - logs:PutMetricFilter"
    echo "   - logs:DescribeMetricFilters"
    echo "   - cloudwatch:PutMetricAlarm"
    echo "   - cloudwatch:DescribeAlarms"
    echo "   - sns:CreateTopic"
    echo "   - sns:ListTopics"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# Paso 1: Configurar SNS Topic
echo "=== Paso 1: Configurando SNS Topic ==="

# Verificar si el topic ya existe
SNS_TOPIC_ARN=$(aws sns list-topics \
    --profile "$PROFILE" --region "$REGION" \
    --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
    --output text 2>/dev/null)

if [ -z "$SNS_TOPIC_ARN" ] || [ "$SNS_TOPIC_ARN" = "None" ]; then
    echo -e "${BLUE}📧 Creando SNS Topic: $SNS_TOPIC_NAME${NC}"
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'TopicArn' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$SNS_TOPIC_ARN" ]; then
        echo -e "${GREEN}✅ SNS Topic creado: $SNS_TOPIC_ARN${NC}"
    else
        echo -e "${RED}❌ Error creando SNS Topic${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ SNS Topic existente: $SNS_TOPIC_ARN${NC}"
fi
echo ""

# Paso 2: Buscar CloudTrail Log Groups
echo "=== Paso 2: Identificando CloudTrail Log Groups ==="

CLOUDTRAIL_LOG_GROUPS=$(aws logs describe-log-groups \
    --profile "$PROFILE" --region "$REGION" \
    --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' \
    --output text 2>/dev/null)

if [ -z "$CLOUDTRAIL_LOG_GROUPS" ] || [ "$CLOUDTRAIL_LOG_GROUPS" = "None" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron log groups de CloudTrail específicos.${NC}"
    ALL_LOG_GROUPS=$(aws logs describe-log-groups \
        --profile "$PROFILE" --region "$REGION" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null)
    
    echo -e "${BLUE}📋 Log Groups disponibles:${NC}"
    for lg in $ALL_LOG_GROUPS; do
        echo "   - $lg"
    done
    
    CLOUDTRAIL_LOG_GROUPS=""
    for lg in $ALL_LOG_GROUPS; do
        if [[ $lg == *"trail"* ]] || [[ $lg == *"cloudtrail"* ]] || [[ $lg == *"CloudTrail"* ]]; then
            if [ -z "$CLOUDTRAIL_LOG_GROUPS" ]; then
                CLOUDTRAIL_LOG_GROUPS="$lg"
            else
                CLOUDTRAIL_LOG_GROUPS="$CLOUDTRAIL_LOG_GROUPS $lg"
            fi
        fi
    done
    
    if [ -z "$CLOUDTRAIL_LOG_GROUPS" ]; then
        echo -e "${RED}❌ No se encontraron log groups de CloudTrail${NC}"
        echo ""
        echo "📋 SOLUCIONES RECOMENDADAS:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "1. Configurar CloudTrail primero:"
        echo "   ./enable-cloudtrail-complete.sh"
        echo ""
        echo "2. Verificar que CloudTrail esté enviando logs a CloudWatch"
        echo ""
        echo "3. Ejecutar este script nuevamente"
        echo ""
        exit 1
    fi
fi

echo -e "${GREEN}✅ CloudTrail Log Groups encontrados:${NC}"
for group in $CLOUDTRAIL_LOG_GROUPS; do
    echo "   - $group"
done
echo ""

# Paso 3: Configurar Metric Filters y Alarmas
echo "=== Paso 3: Configurando Metric Filters y CloudWatch Alarms ==="

FILTERS_CREATED=0
ALARMS_CREATED=0

for LOG_GROUP in $CLOUDTRAIL_LOG_GROUPS; do
    echo -e "${BLUE}📄 Procesando Log Group: $LOG_GROUP${NC}"
    
    # Verificar si el filtro ya existe
    EXISTING_FILTER=$(aws logs describe-metric-filters \
        --log-group-name "$LOG_GROUP" \
        --filter-name-prefix "$FILTER_NAME" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'metricFilters[0].filterName' \
        --output text 2>/dev/null)
    
    if [ "$EXISTING_FILTER" != "None" ] && [ ! -z "$EXISTING_FILTER" ]; then
        echo -e "${YELLOW}   ⚠️ Metric Filter ya existe, actualizando...${NC}"
    else
        echo -e "${BLUE}   🔧 Creando nuevo Metric Filter...${NC}"
    fi
    
    # Crear/actualizar el metric filter
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP" \
        --filter-name "$FILTER_NAME" \
        --filter-pattern "$FILTER_PATTERN" \
        --metric-transformations \
            metricName="$METRIC_NAME",metricNamespace="$METRIC_NAMESPACE",metricValue=1 \
        --profile "$PROFILE" \
        --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}   ✅ Metric Filter configurado${NC}"
        FILTERS_CREATED=$((FILTERS_CREATED + 1))
    else
        echo -e "${RED}   ❌ Error configurando Metric Filter${NC}"
        continue
    fi
    
    # Crear CloudWatch alarm
    ALARM_NAME_FULL="${ALARM_NAME}-$(echo $LOG_GROUP | sed 's/\//-/g')"
    
    echo -e "${BLUE}   ⏰ Configurando CloudWatch Alarm: $ALARM_NAME_FULL${NC}"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME_FULL" \
        --alarm-description "$ALARM_DESCRIPTION" \
        --metric-name "$METRIC_NAME" \
        --namespace "$METRIC_NAMESPACE" \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 1 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --ok-actions "$SNS_TOPIC_ARN" \
        --treat-missing-data notBreaching \
        --profile "$PROFILE" \
        --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}   ✅ CloudWatch Alarm configurado${NC}"
        ALARMS_CREATED=$((ALARMS_CREATED + 1))
    else
        echo -e "${RED}   ❌ Error configurando CloudWatch Alarm${NC}"
    fi
    
    echo ""
done

# Resumen final
echo "=================================================================="
echo -e "${GREEN}🎉 IMPLEMENTACIÓN CIS 3.3 COMPLETADA${NC}"
echo "=================================================================="
echo "Perfil procesado: $PROFILE (Account: $ACCOUNT_ID)"
echo "Metric Filters creados: $FILTERS_CREATED"
echo "CloudWatch Alarms creadas: $ALARMS_CREATED"
echo "SNS Topic: $(basename $SNS_TOPIC_ARN)"
echo ""

echo -e "${BLUE}📋 ¿QUÉ SE HA CONFIGURADO?${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Metric Filters para detectar uso de cuenta root en CloudTrail"
echo "✅ CloudWatch Alarms que se activan cuando se detecta uso de root"
echo "✅ SNS Topic para notificaciones de seguridad"
echo "✅ Cumplimiento con CIS AWS Benchmark 3.3"
echo ""
echo -e "${BLUE}🔍 PATRÓN DE FILTRO CONFIGURADO:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "{ \$.userIdentity.type = \"Root\" && \$.userIdentity.invokedBy NOT EXISTS && \$.eventType != \"AwsServiceEvent\" }"
echo ""
echo -e "${YELLOW}⚠️ IMPORTANTE SOBRE LA CUENTA ROOT:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• La cuenta root debería usarse SOLO para tareas que lo requieren específicamente"
echo "• Ejemplos de uso legítimo: cambiar plan de soporte, cerrar cuenta, etc."
echo "• Para uso diario, utilizar usuarios IAM con los permisos mínimos necesarios"
echo "• Siempre habilitar MFA en la cuenta root"
echo ""
echo -e "${YELLOW}🔔 PRÓXIMOS PASOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Configurar suscripción de email en el SNS Topic:"
echo "   aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint $NOTIFICATION_EMAIL --profile $PROFILE"
echo ""
echo "2. Verificar el estado de las alarmas:"
echo "   ./verify-root-account-usage-monitoring.sh"
echo ""
echo "3. Revisar regularmente las alertas y investigar cualquier uso no autorizado"
echo ""
echo "4. Documentar esta configuración en su política de seguridad"
echo ""