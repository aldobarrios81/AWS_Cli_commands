#!/bin/bash
# setup-s3-bucket-policy-changes-monitoring.sh
# Create log metric filter and alarm for S3 bucket policy changes
# Regla de seguridad CIS AWS: 3.8 - Monitor S3 bucket policy changes
# Uso: ./setup-s3-bucket-policy-changes-monitoring.sh [perfil]

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
METRIC_NAME="S3BucketPolicyChanges"
FILTER_NAME="CIS-S3BucketPolicyChanges"
ALARM_NAME="CIS-3.8-S3BucketPolicyChanges"
SNS_TOPIC_NAME="cis-security-alerts"
ALARM_DESCRIPTION="CIS 3.8 - S3 bucket policy changes detected"
NOTIFICATION_EMAIL="felipe.castillo@azlogica.com"

# Patrón del filtro para detectar cambios en políticas de buckets S3
FILTER_PATTERN='{ ($.eventSource = "s3.amazonaws.com") && (($.eventName = "PutBucketPolicy") || ($.eventName = "DeleteBucketPolicy") || ($.eventName = "PutBucketAcl") || ($.eventName = "PutBucketPublicAccessBlock")) }'

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔒 IMPLEMENTANDO CIS 3.8 - S3 BUCKET POLICY CHANGES MONITORING${NC}"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Regla: Create log metric filter and alarm for S3 bucket policy changes"
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
    echo "2. Configurar perfil '$PROFILE':"
    echo "   aws configure --profile $PROFILE"
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
    echo "   - s3:ListAllMyBuckets (para verificar buckets)"
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

# Configurar suscripción de email automáticamente
echo -e "${BLUE}📬 Configurando suscripción de email...${NC}"

# Verificar si ya existe una suscripción para este email
EXISTING_SUBSCRIPTION=$(aws sns list-subscriptions-by-topic \
    --topic-arn "$SNS_TOPIC_ARN" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "Subscriptions[?Endpoint=='$NOTIFICATION_EMAIL' && Protocol=='email'].SubscriptionArn" \
    --output text 2>/dev/null)

if [ -z "$EXISTING_SUBSCRIPTION" ] || [ "$EXISTING_SUBSCRIPTION" = "None" ]; then
    echo -e "${BLUE}   📧 Creando suscripción de email para: $NOTIFICATION_EMAIL${NC}"
    
    SUBSCRIPTION_ARN=$(aws sns subscribe \
        --topic-arn "$SNS_TOPIC_ARN" \
        --protocol email \
        --notification-endpoint "$NOTIFICATION_EMAIL" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'SubscriptionArn' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$SUBSCRIPTION_ARN" ]; then
        echo -e "${GREEN}   ✅ Suscripción creada: $SUBSCRIPTION_ARN${NC}"
        echo -e "${YELLOW}   ⚠️ IMPORTANTE: Revisa tu email y confirma la suscripción${NC}"
        echo -e "${BLUE}   📧 Email enviado a: $NOTIFICATION_EMAIL${NC}"
    else
        echo -e "${RED}   ❌ Error creando suscripción de email${NC}"
    fi
else
    echo -e "${GREEN}   ✅ Suscripción de email ya existe para: $NOTIFICATION_EMAIL${NC}"
    
    # Verificar estado de la suscripción
    SUBSCRIPTION_STATUS=$(aws sns get-subscription-attributes \
        --subscription-arn "$EXISTING_SUBSCRIPTION" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --query 'Attributes.PendingConfirmation' \
        --output text 2>/dev/null)
    
    if [ "$SUBSCRIPTION_STATUS" = "true" ]; then
        echo -e "${YELLOW}   ⚠️ Suscripción pendiente de confirmación${NC}"
        echo -e "${BLUE}   📧 Revisa tu email y confirma la suscripción${NC}"
    else
        echo -e "${GREEN}   ✅ Suscripción confirmada y activa${NC}"
    fi
fi

echo ""

# Paso 2: Verificar S3 Buckets (opcional pero informativo)
echo "=== Paso 2: Verificando S3 Buckets existentes ==="

S3_BUCKETS=$(aws s3api list-buckets \
    --profile "$PROFILE" \
    --query 'Buckets[].Name' \
    --output text 2>/dev/null | wc -w)

if [ $? -eq 0 ] && [ "$S3_BUCKETS" -gt 0 ]; then
    echo -e "${GREEN}✅ S3 Buckets encontrados en la cuenta: $S3_BUCKETS buckets${NC}"
    echo -e "${BLUE}📋 Estos buckets serán monitoreados por cambios de políticas${NC}"
    
    # Mostrar algunos buckets de ejemplo (primeros 3)
    SAMPLE_BUCKETS=$(aws s3api list-buckets \
        --profile "$PROFILE" \
        --query 'Buckets[0:3].Name' \
        --output text 2>/dev/null)
    
    echo -e "${BLUE}📄 Ejemplos de buckets (primeros 3):${NC}"
    for bucket in $SAMPLE_BUCKETS; do
        echo "   - $bucket"
    done
else
    echo -e "${YELLOW}⚠️ No se encontraron S3 Buckets o sin permisos para listarlos${NC}"
    echo -e "${BLUE}💡 El monitoreo funcionará cuando se modifiquen políticas de S3${NC}"
fi
echo ""

# Paso 3: Buscar CloudTrail Log Groups
echo "=== Paso 3: Identificando CloudTrail Log Groups ==="

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

# Paso 4: Configurar Metric Filters y Alarmas
echo "=== Paso 4: Configurando Metric Filters y CloudWatch Alarms ==="

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
echo -e "${GREEN}🎉 IMPLEMENTACIÓN CIS 3.8 COMPLETADA${NC}"
echo "=================================================================="
echo "Perfil procesado: $PROFILE (Account: $ACCOUNT_ID)"
echo "Metric Filters creados: $FILTERS_CREATED"
echo "CloudWatch Alarms creadas: $ALARMS_CREATED"
echo "SNS Topic: $(basename $SNS_TOPIC_ARN)"
echo ""

echo -e "${BLUE}📋 ¿QUÉ SE HA CONFIGURADO?${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Metric Filters para detectar cambios en políticas de S3 buckets"
echo "✅ CloudWatch Alarms para alertas de modificaciones de acceso"
echo "✅ SNS Topic para notificaciones inmediatas de seguridad"
echo "✅ Cumplimiento con CIS AWS Benchmark 3.8"
echo ""
echo -e "${BLUE}🔍 EVENTOS S3 MONITOREADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• PutBucketPolicy - Modificación de políticas de bucket"
echo "• DeleteBucketPolicy - Eliminación de políticas de bucket"
echo "• PutBucketAcl - Cambios en ACL de bucket"
echo "• PutBucketPublicAccessBlock - Modificación de acceso público"
echo ""
echo -e "${YELLOW}⚠️ IMPORTANCIA DE ESTA REGLA:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• S3 buckets contienen datos críticos y sensibles"
echo "• Cambios de políticas pueden exponer datos públicamente"
echo "• Eliminación de políticas puede remover protecciones de seguridad"
echo "• Modificaciones no autorizadas comprometen la integridad de datos"
echo "• Detección temprana previene exposición accidental de información"
echo ""
echo -e "${YELLOW}🔔 PRÓXIMOS PASOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. ✅ Suscripción de email configurada automáticamente"
echo "   📧 Revisa tu email ($NOTIFICATION_EMAIL) y confirma la suscripción"
echo ""
echo "2. Verificar el estado de las alarmas:"
echo "   ./verify-s3-bucket-policy-changes-monitoring.sh"
echo ""
echo "3. Probar las notificaciones (opcional):"
echo "   aws sns publish --topic-arn $SNS_TOPIC_ARN --message 'Prueba de notificación CIS 3.8' --profile $PROFILE"
echo ""
echo "4. Establecer procedimientos de respuesta para eventos S3:"
echo "   - Investigar inmediatamente cambios no autorizados en buckets críticos"
echo "   - Revisar permisos públicos accidentales"
echo "   - Validar eliminación de políticas con el equipo de datos"
echo ""
echo "5. Monitorear regularmente las alertas y patrones de acceso"
echo ""
echo "6. Documentar esta configuración en la política de protección de datos"
echo ""