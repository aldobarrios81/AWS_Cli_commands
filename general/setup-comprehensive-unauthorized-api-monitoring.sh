
# Comprehensive Unauthorized API Calls Monitoring Setup
# Configura filtros de métricas y alarmas para detectar actividad sospechosa

PROFILE="azcenit"
REGION="us-east-1"
LOG_GROUP_NAME=""
METRIC_NAMESPACE="Security/UnauthorizedAccess"
SNS_TOPIC_NAME="unauthorized-api-alerts"

# Colores para output
RED='\\033[0;31m'
GREEN='\\033[0;32m'
YELLOW='\\033[1;33m'
BLUE='\\033[0;34m'
NC='\\033[0m' # No Color

echo "================================================================="
echo "� CONFIGURANDO MONITOREO COMPLETO DE API CALLS NO AUTORIZADAS"
echo "================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query 'Account' --output text 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "❌ Error: No se puede obtener el Account ID. Verificar credenciales AWS."
    exit 1
fi

echo "Account ID: $ACCOUNT_ID"
echo ""

# Paso 1: Buscar CloudTrail Log Groups
echo "=== Paso 1: Identificando CloudTrail Log Groups ==="

# Buscar todos los posibles log groups de CloudTrail
POSSIBLE_LOG_GROUPS=$(aws logs describe-log-groups \
    --profile "$PROFILE" --region "$REGION" \
    --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' \
    --output text 2>/dev/null)

if [ -z "$POSSIBLE_LOG_GROUPS" ]; then
    echo "⚠️ No se encontraron log groups de CloudTrail específicos."
    echo "� Buscando log groups generales..."
    
    ALL_LOG_GROUPS=$(aws logs describe-log-groups \
        --profile "$PROFILE" --region "$REGION" \
        --query 'logGroups[].logGroupName' \
        --output text 2>/dev/null)
    
    echo "� Log Groups disponibles:"
    for lg in $ALL_LOG_GROUPS; do
        echo "   - $lg"
    done
    
    # Buscar el log group más probable para CloudTrail
    for lg in $ALL_LOG_GROUPS; do
        if [[ $lg == *"trail"* ]] || [[ $lg == *"cloudtrail"* ]] || [[ $lg == *"CloudTrail"* ]]; then
            LOG_GROUP_NAME=$lg
            break
        fi
    done
    
    if [ -z "$LOG_GROUP_NAME" ]; then
        echo "� No se encontró log group específico de CloudTrail."
        echo "� Configurando para el primer log group disponible como demo..."
        LOG_GROUP_NAME=$(echo $ALL_LOG_GROUPS | awk '{print $1}')
        echo "� Usando: $LOG_GROUP_NAME"
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

# Función para crear filtro de métrica
create_metric_filter() {
    local filter_name="$1"
    local filter_pattern="$2"
    local metric_name="$3"
    local description="$4"
    
    echo "� Configurando filtro: $filter_name"
    
    # Verificar si el filtro ya existe
    EXISTING_FILTER=$(aws logs describe-metric-filters \
        --log-group-name "$LOG_GROUP_NAME" \
        --filter-name-prefix "$filter_name" \
        --profile "$PROFILE" --region "$REGION" \
        --query 'metricFilters[0].filterName' --output text 2>/dev/null)
    
    if [ "$EXISTING_FILTER" = "$filter_name" ]; then
        echo "   ✅ Filtro ya existe: $filter_name"
        return 0
    fi
    
    # Crear el filtro
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

# 1. Llamadas API no autorizadas (errores 403)
create_metric_filter \
    "UnauthorizedApiCalls-AccessDenied" \
    '{ ($.errorCode = "*UnauthorizedOperation") || ($.errorCode = "AccessDenied*") }' \
    "UnauthorizedApiCalls" \
    "Detecta llamadas API no autorizadas"

# 2. Intentos de escalación de privilegios
create_metric_filter \
    "PrivilegeEscalationAttempts" \
    '{ ($.eventName = "AttachUserPolicy") || ($.eventName = "AttachRolePolicy") || ($.eventName = "PutUserPolicy") || ($.eventName = "PutRolePolicy") || ($.eventName = "CreateRole") }' \
    "PrivilegeEscalationAttempts" \
    "Detecta intentos de escalación de privilegios"

# 3. Cambios en políticas de seguridad
create_metric_filter \
    "SecurityPolicyChanges" \
    '{ ($.eventName = "DeleteGroupPolicy") || ($.eventName = "DeleteUserPolicy") || ($.eventName = "DeleteRolePolicy") || ($.eventName = "PutGroupPolicy") }' \
    "SecurityPolicyChanges" \
    "Detecta cambios en políticas de seguridad"

# 4. Fallos de autenticación
create_metric_filter \
    "AuthenticationFailures" \
    '{ ($.errorCode = "SigninFailure") || ($.errorCode = "InvalidUserID.NotFound") || ($.errorCode = "TokenRefreshRequired") }' \
    "AuthenticationFailures" \
    "Detecta fallos de autenticación"

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

# Crear alarmas
create_alarm "Security-UnauthorizedApiCalls-HIGH" "UnauthorizedApiCalls" "CRITICAL: API calls no autorizadas detectadas" "1"
create_alarm "Security-PrivilegeEscalation-CRITICAL" "PrivilegeEscalationAttempts" "CRITICAL: Intentos de escalación de privilegios" "1"
create_alarm "Security-PolicyChanges-MEDIUM" "SecurityPolicyChanges" "MEDIUM: Cambios en políticas de seguridad" "1"
create_alarm "Security-AuthFailures-HIGH" "AuthenticationFailures" "HIGH: Múltiples fallos de autenticación" "3"

echo ""

# Paso 5: Resumen
echo "================================================================="
echo "✅ CONFIGURACIÓN COMPLETADA - MONITOREO API NO AUTORIZADAS"
echo "================================================================="
echo ""
echo "� RESUMEN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "� Account ID: $ACCOUNT_ID"
echo "� Región: $REGION"
echo "� Log Group: $LOG_GROUP_NAME"
echo "� SNS Topic: $SNS_TOPIC_ARN"
echo ""
echo "� FILTROS DE MÉTRICAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• UnauthorizedApiCalls - Llamadas API denegadas"
echo "• PrivilegeEscalationAttempts - Escalación de privilegios"
echo "• SecurityPolicyChanges - Cambios en políticas"
echo "• AuthenticationFailures - Fallos de autenticación"
echo ""
echo "� ALARMAS CONFIGURADAS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "• Security-UnauthorizedApiCalls-HIGH"
echo "• Security-PrivilegeEscalation-CRITICAL"
echo "• Security-PolicyChanges-MEDIUM"
echo "• Security-AuthFailures-HIGH"
echo ""
echo "� COMANDOS DE VERIFICACIÓN:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "# Ver filtros configurados:"
echo "aws logs describe-metric-filters --log-group-name \"$LOG_GROUP_NAME\" --profile $PROFILE --region $REGION"
echo ""
echo "# Ver alarmas de seguridad:"
echo "aws cloudwatch describe-alarms --alarm-name-prefix \"Security-\" --profile $PROFILE --region $REGION"
echo ""
echo "� CONFIGURAR SUSCRIPCIÓN EMAIL:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "aws sns subscribe \\"
echo "    --topic-arn $SNS_TOPIC_ARN \\"
echo "    --protocol email \\"
echo "    --notification-endpoint security@empresa.com \\"
echo "    --profile $PROFILE --region $REGION"
echo ""
echo "================================================================="
echo "� MONITOREO DE SEGURIDAD CONFIGURADO EXITOSAMENTE"
echo "================================================================="
