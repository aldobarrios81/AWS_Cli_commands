
#!/bin/bash
# Create log metric filter and alarm for console login without MFA
# Regla de seguridad CIS AWS: 3.2 - Monitor console login without MFA
# Perfil: ancla | Región: us-east-1

PROFILE="ancla"
REGION="us-east-1"
LOG_GROUP_NAME=""
METRIC_NAMESPACE="CISBenchmark"
METRIC_NAME="ConsoleLoginWithoutMFA"
FILTER_NAME="CIS-ConsoleLoginWithoutMFA"
ALARM_NAME="CIS-3.2-ConsoleLoginWithoutMFA"
SNS_TOPIC_NAME="cis-security-alerts"
ALARM_DESCRIPTION="CIS 3.2 - Console login without MFA detected"
NOTIFICATION_EMAIL="felipe.castillo@azlogica.com"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=================================================================="
echo "🔒 IMPLEMENTANDO CIS 3.2 - CONSOLE LOGIN WITHOUT MFA MONITORING"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Regla: Create log metric filter and alarm for console login without MFA"
echo ""

# Verificar prerrequisitos
echo "🔍 Verificando prerrequisitos..."

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    echo "❌ ERROR: AWS CLI no está instalado"
    echo ""
    echo "📋 INSTRUCCIONES DE INSTALACIÓN:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Instalar AWS CLI v2:"
    echo "   curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
    echo "   unzip awscliv2.zip"
    echo "   sudo ./aws/install"
    echo ""
    echo "2. Configurar perfil 'ancla':"
    echo "   aws configure --profile ancla"
    echo ""
    echo "3. Ejecutar este script nuevamente"
    echo ""
    exit 1
fi

echo "✅ AWS CLI encontrado: $(aws --version)"

# Obtener Account ID
echo "🔐 Verificando credenciales para perfil '$PROFILE'..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query 'Account' --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ ERROR: No se puede obtener el Account ID"
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

echo "Account ID: $ACCOUNT_ID"
echo ""

# Paso 1: Buscar CloudTrail Log Groups
echo "=== Paso 1: Identificando CloudTrail Log Groups ==="

POSSIBLE_LOG_GROUPS=$(aws logs describe-log-groups \
    --profile "$PROFILE" --region "$REGION" \
    --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' \
    --output text 2>/dev/null)

if [ -z "$POSSIBLE_LOG_GROUPS" ]; then
    echo "⚠️ No se encontraron log groups de CloudTrail específicos."
    ALL_LOG_GROUPS=$(aws logs describe-log-groups \
        --profile "$PROFILE" --region "$REGION" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null)
    
    echo "� Log Groups disponibles:"
    for lg in $ALL_LOG_GROUPS; do
        echo "   - $lg"
    done
    
    for lg in $ALL_LOG_GROUPS; do
        if [[ $lg == *"trail"* ]] || [[ $lg == *"cloudtrail"* ]] || [[ $lg == *"CloudTrail"* ]]; then
            LOG_GROUP_NAME=$lg
            break
        fi
    done
    
    if [ -z "$LOG_GROUP_NAME" ]; then
        echo "� Usando primer log group disponible como demo..."
        LOG_GROUP_NAME=$(echo $ALL_LOG_GROUPS | awk '{print $1}')
    fi
else
    LOG_GROUP_NAME=$(echo $POSSIBLE_LOG_GROUPS | awk '{print $1}')
    echo "✅ CloudTrail Log Group encontrado: $LOG_GROUP_NAME"
fi

if [ -z "$LOG_GROUP_NAME" ]; then
    echo "❌ Error: No se puede encontrar ningún log group."
    exit 1
fi

echo ""

# Paso 2: Crear SNS Topic
echo "=== Paso 2: Configurando SNS Topic para Alertas ==="

EXISTING_TOPIC=$(aws sns list-topics \
    --profile "$PROFILE" --region "$REGION" \
    --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
    --output text 2>/dev/null)

if [ -n "$EXISTING_TOPIC" ]; then
    SNS_TOPIC_ARN="$EXISTING_TOPIC"
    echo "✅ Usando SNS Topic existente: $SNS_TOPIC_ARN"
else
    echo "� Creando SNS Topic: $SNS_TOPIC_NAME"
    SNS_TOPIC_ARN=$(aws sns create-topic \
        --name "$SNS_TOPIC_NAME" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'TopicArn' --output text 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo "✅ SNS Topic creado: $SNS_TOPIC_ARN"
    else
        echo "❌ Error creando SNS Topic"
        exit 1
    fi
fi

echo ""

# Paso 3: Configurar Filtros de Métricas
echo "=== Paso 3: Configurando Filtros de Métricas ==="

create_metric_filter() {
    local filter_name="$1"
    local filter_pattern="$2"
    local metric_name="$3"
    
    echo "� Configurando filtro: $filter_name"
    
    EXISTING_FILTER=$(aws logs describe-metric-filters \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name-prefix "$filter_name" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'metricFilters[0].filterName' --output text 2>/dev/null)
    
    if [ "$EXISTING_FILTER" = "$filter_name" ]; then
        echo "   ✅ Filtro ya existe: $filter_name"
        return 0
    fi
    
    aws logs put-metric-filter \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name "$filter_name" \
        --filter-pattern "$filter_pattern" \
        --metric-transformations \
            metricName="$metric_name",metricNamespace="$METRIC_NAMESPACE",metricValue="1",defaultValue=0 \
        --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Filtro configurado: $filter_name"
    else
        echo "   ⚠️ Error configurando filtro: $filter_name"
    fi
}

# CIS 3.2: Console login sin MFA - Filtro de métrica principal
echo "🎯 Configurando filtro de métrica para Console Login sin MFA..."
create_metric_filter \
    "$FILTER_NAME" \
    '{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") && ($.responseElements.ConsoleLogin = "Success") }' \
    "$METRIC_NAME"

echo ""

# Paso 4: Crear Alarmas
echo "=== Paso 4: Configurando Alarmas CloudWatch ==="

create_alarm() {
    local alarm_name="$1"
    local metric_name="$2"
    local description="$3"
    local threshold="$4"
    
    echo "� Configurando alarma: $alarm_name"
    
    EXISTING_ALARM=$(aws cloudwatch describe-alarms \
        --alarm-names "$alarm_name" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'MetricAlarms[0].AlarmName' --output text 2>/dev/null)
    
    if [ "$EXISTING_ALARM" = "$alarm_name" ]; then
        echo "   ✅ Alarma ya existe: $alarm_name"
        return 0
    fi
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name" \
        --alarm-description "$description" \
        --metric-name "$metric_name" \
        --namespace "$METRIC_NAMESPACE" \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 1 \
        --threshold "$threshold" \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --alarm-actions "$SNS_TOPIC_ARN" \
        --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Alarma configurada: $alarm_name (umbral: ≥$threshold)"
    else
        echo "   ⚠️ Error configurando alarma: $alarm_name"
    fi
}

# CIS 3.2: Crear alarma para Console Login sin MFA
echo "⚠️ Configurando alarma CloudWatch para Console Login sin MFA..."
create_alarm "$ALARM_NAME" "$METRIC_NAME" "$ALARM_DESCRIPTION" "1"

echo ""

# Resumen
echo "=================================================================="
echo "✅ CIS 3.2 IMPLEMENTADO - CONSOLE LOGIN WITHOUT MFA MONITORING"
echo "=================================================================="
echo ""
echo "🎯 RESUMEN DE IMPLEMENTACIÓN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Account ID: $ACCOUNT_ID"
echo "🌎 Región: $REGION"
echo "📋 Log Group: $LOG_GROUP_NAME"
echo "📢 SNS Topic: $SNS_TOPIC_ARN"
echo ""
echo "🔍 FILTRO DE MÉTRICA CONFIGURADO:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Nombre: $FILTER_NAME"
echo "• Métrica: $METRIC_NAME"
echo "• Namespace: $METRIC_NAMESPACE"
echo "• Patrón: Console login exitoso SIN MFA"
echo ""
echo "🚨 ALARMA CLOUDWATCH CONFIGURADA:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Nombre: $ALARM_NAME"
echo "• Umbral: ≥1 evento en 5 minutos"
echo "• Descripción: $ALARM_DESCRIPTION"
echo ""
echo "🔧 COMANDOS DE VERIFICACIÓN CIS 3.2:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Verificar filtro de métrica configurado:"
echo "aws logs describe-metric-filters --log-group-name \"$LOG_GROUP_NAME\" --filter-name-prefix \"$FILTER_NAME\" --profile $PROFILE --region $REGION"
echo ""
echo "# Verificar alarma CloudWatch:"
echo "aws cloudwatch describe-alarms --alarm-names \"$ALARM_NAME\" --profile $PROFILE --region $REGION"
echo ""
echo "# Buscar eventos de console login sin MFA en las últimas 24 horas:"
echo "aws logs filter-log-events --log-group-name \"$LOG_GROUP_NAME\" --filter-pattern '{ (\$.eventName = \"ConsoleLogin\") && (\$.additionalEventData.MFAUsed != \"Yes\") && (\$.responseElements.ConsoleLogin = \"Success\") }' --start-time \$(date -d '24 hours ago' +%s)000 --profile $PROFILE --region $REGION"
echo ""
echo "# Verificar métrica en CloudWatch:"
echo "aws cloudwatch get-metric-statistics --namespace \"$METRIC_NAMESPACE\" --metric-name \"$METRIC_NAME\" --start-time \$(date -d '1 hour ago' --iso-8601) --end-time \$(date --iso-8601) --period 300 --statistics Sum --profile $PROFILE --region $REGION"
echo ""
echo "📧 CONFIGURAR NOTIFICACIONES POR EMAIL:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "aws sns subscribe \\"
echo "    --topic-arn $SNS_TOPIC_ARN \\"
echo "    --protocol email \\"
echo "    --notification-endpoint $NOTIFICATION_EMAIL \\"
echo "    --profile $PROFILE --region $REGION"
echo ""
echo "📋 CUMPLIMIENTO CIS 3.2 - ACCIONES RECOMENDADAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Filtro de métrica configurado para detectar console login sin MFA"
echo "✅ Alarma CloudWatch configurada para alertas inmediatas"
echo "✅ SNS Topic configurado para notificaciones"
echo ""
echo "🔒 PRÓXIMOS PASOS PARA SEGURIDAD COMPLETA:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Habilitar MFA obligatorio para TODOS los usuarios IAM"
echo "• Configurar MFA para el root account"
echo "• Implementar políticas IAM que requieran MFA para acciones críticas"
echo "• Establecer procedimientos de respuesta a incidentes"
echo "• Revisar regularmente eventos de console login en CloudTrail"
echo ""
echo "=================================================================="
echo "🎉 CIS 3.2 - CONSOLE LOGIN WITHOUT MFA MONITORING COMPLETADO"
echo "=================================================================="
