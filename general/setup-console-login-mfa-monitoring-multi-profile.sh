#!/bin/bash
# setup-console-login-mfa-monitoring-multi-profile.sh
# Create log metric filter and alarm for console login without MFA
# Regla de seguridad CIS AWS: 3.2 - Monitor console login without MFA
# Perfiles: ancla | azbeacons | azcenit | Región: us-east-1

# Configuración
PROFILES=("ancla" "azbeacons" "azcenit")
REGION="us-east-1"
METRIC_NAMESPACE="CISBenchmark"
METRIC_NAME="ConsoleLoginWithoutMFA"
FILTER_NAME="CIS-ConsoleLoginWithoutMFA"
ALARM_NAME="CIS-3.2-ConsoleLoginWithoutMFA"
SNS_TOPIC_NAME="cis-security-alerts"
ALARM_DESCRIPTION="CIS 3.2 - Console login without MFA detected"

# Patrón del filtro para detectar logins sin MFA
FILTER_PATTERN='{ ($.eventName = "ConsoleLogin") && ($.additionalEventData.MFAUsed != "Yes") }'

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Función para mostrar banner
show_banner() {
    echo "=================================================================="
    echo -e "${BLUE}🔒 IMPLEMENTANDO CIS 3.2 - CONSOLE LOGIN WITHOUT MFA MONITORING${NC}"
    echo "=================================================================="
    echo "Perfiles: ${PROFILES[*]} | Región: $REGION"
    echo "Regla: Create log metric filter and alarm for console login without MFA"
    echo ""
}

# Función para verificar prerrequisitos
check_prerequisites() {
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
        echo "2. Configurar perfiles:"
        echo "   aws configure --profile ancla"
        echo "   aws configure --profile azbeacons"
        echo "   aws configure --profile azcenit"
        echo ""
        exit 1
    fi
    
    echo -e "${GREEN}✅ AWS CLI encontrado: $(aws --version)${NC}"
    echo ""
}

# Función para verificar y crear SNS topic
setup_sns_topic() {
    local profile=$1
    local account_id=$2
    
    echo -e "${BLUE}   📧 Configurando SNS Topic...${NC}"
    
    # Verificar si el topic ya existe
    local topic_arn=$(aws sns list-topics \
        --profile "$profile" \
        --region "$REGION" \
        --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
        --output text 2>/dev/null)
    
    if [ -z "$topic_arn" ] || [ "$topic_arn" = "None" ]; then
        echo "   🔹 Creando SNS Topic: $SNS_TOPIC_NAME"
        topic_arn=$(aws sns create-topic \
            --name "$SNS_TOPIC_NAME" \
            --profile "$profile" \
            --region "$REGION" \
            --query 'TopicArn' \
            --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ ! -z "$topic_arn" ]; then
            echo -e "${GREEN}   ✅ SNS Topic creado: $topic_arn${NC}"
        else
            echo -e "${RED}   ❌ Error creando SNS Topic${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}   ✅ SNS Topic existente: $topic_arn${NC}"
    fi
    
    # Guardar ARN en archivo temporal
    echo "$topic_arn" > "/tmp/sns_arn_${profile}.txt"
}

# Función para buscar CloudTrail log groups
find_cloudtrail_log_groups() {
    local profile=$1
    
    echo -e "${BLUE}   📋 Buscando CloudTrail Log Groups...${NC}"
    
    # Buscar log groups relacionados con CloudTrail
    local log_groups=$(aws logs describe-log-groups \
        --profile "$profile" \
        --region "$REGION" \
        --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' \
        --output text 2>/dev/null)
    
    if [ -z "$log_groups" ] || [ "$log_groups" = "None" ]; then
        # Si no encuentra específicos, buscar todos y filtrar
        echo "   🔍 Buscando en todos los log groups..."
        local all_groups=$(aws logs describe-log-groups \
            --profile "$profile" \
            --region "$REGION" \
            --query 'logGroups[].logGroupName' \
            --output text 2>/dev/null)
        
        log_groups=""
        for group in $all_groups; do
            if [[ $group == *"trail"* ]] || [[ $group == *"cloudtrail"* ]] || [[ $group == *"CloudTrail"* ]]; then
                if [ -z "$log_groups" ]; then
                    log_groups="$group"
                else
                    log_groups="$log_groups $group"
                fi
            fi
        done
    fi
    
    if [ -z "$log_groups" ] || [ "$log_groups" = "None" ]; then
        echo -e "${YELLOW}   ⚠️ No se encontraron log groups de CloudTrail${NC}"
        return 1
    fi
    
    echo -e "${GREEN}   ✅ Log groups encontrados:${NC}"
    for group in $log_groups; do
        echo "      - $group"
    done
    
    # Guardar en archivo temporal para evitar problemas con echo
    echo "$log_groups" > "/tmp/log_groups_${profile}.txt"
}

# Función para crear metric filter
create_metric_filter() {
    local profile=$1
    local log_group=$2
    
    echo -e "${BLUE}   🔧 Configurando Metric Filter para: $log_group${NC}"
    
    # Verificar si el filtro ya existe
    local existing_filter=$(aws logs describe-metric-filters \
        --log-group-name "$log_group" \
        --filter-name-prefix "$FILTER_NAME" \
        --profile "$profile" \
        --region "$REGION" \
        --query 'metricFilters[0].filterName' \
        --output text 2>/dev/null)
    
    if [ "$existing_filter" != "None" ] && [ ! -z "$existing_filter" ]; then
        echo -e "${YELLOW}   ⚠️ Metric Filter ya existe, actualizando...${NC}"
    fi
    
    # Crear/actualizar el metric filter
    aws logs put-metric-filter \
        --log-group-name "$log_group" \
        --filter-name "$FILTER_NAME" \
        --filter-pattern "$FILTER_PATTERN" \
        --metric-transformations \
            metricName="$METRIC_NAME",metricNamespace="$METRIC_NAMESPACE",metricValue=1 \
        --profile "$profile" \
        --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}   ✅ Metric Filter configurado${NC}"
        return 0
    else
        echo -e "${RED}   ❌ Error configurando Metric Filter${NC}"
        return 1
    fi
}

# Función para crear CloudWatch alarm
create_cloudwatch_alarm() {
    local profile=$1
    local sns_topic_arn=$2
    local log_group=$3
    
    local alarm_name_full="${ALARM_NAME}-$(echo $log_group | sed 's/\//-/g')"
    
    echo -e "${BLUE}   ⏰ Configurando CloudWatch Alarm: $alarm_name_full${NC}"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$alarm_name_full" \
        --alarm-description "$ALARM_DESCRIPTION" \
        --metric-name "$METRIC_NAME" \
        --namespace "$METRIC_NAMESPACE" \
        --statistic Sum \
        --period 300 \
        --evaluation-periods 1 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --alarm-actions "$sns_topic_arn" \
        --ok-actions "$sns_topic_arn" \
        --treat-missing-data notBreaching \
        --profile "$profile" \
        --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}   ✅ CloudWatch Alarm configurado${NC}"
        return 0
    else
        echo -e "${RED}   ❌ Error configurando CloudWatch Alarm${NC}"
        return 1
    fi
}

# Función principal para procesar un perfil
process_profile() {
    local profile=$1
    local profile_success=true
    
    echo "=================================================================="
    echo -e "${PURPLE}🔄 PROCESANDO PERFIL: $profile${NC}"
    echo "=================================================================="
    
    # Verificar credenciales
    echo -e "${BLUE}🔐 Verificando credenciales para perfil '$profile'...${NC}"
    local account_id=$(aws sts get-caller-identity \
        --profile "$profile" \
        --region "$REGION" \
        --query 'Account' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$account_id" ]; then
        echo -e "${RED}❌ ERROR: No se puede obtener el Account ID para perfil '$profile'${NC}"
        echo ""
        echo "📋 POSIBLES SOLUCIONES:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "1. Configurar el perfil: aws configure --profile $profile"
        echo "2. Verificar credenciales: aws sts get-caller-identity --profile $profile"
        echo ""
        return 1
    fi
    
    echo -e "${GREEN}✅ Account ID: $account_id${NC}"
    echo ""
    
    # Configurar SNS Topic
    setup_sns_topic "$profile" "$account_id"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error configurando SNS Topic para $profile${NC}"
        return 1
    fi
    
    # Leer SNS ARN del archivo temporal
    local sns_topic_arn=$(cat "/tmp/sns_arn_${profile}.txt")
    
    # Buscar CloudTrail log groups
    find_cloudtrail_log_groups "$profile"
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}⚠️ Saltando perfil $profile - No hay CloudTrail log groups${NC}"
        return 1
    fi
    
    # Leer log groups del archivo temporal
    local log_groups=$(cat "/tmp/log_groups_${profile}.txt")
    
    # Procesar cada log group
    local filters_created=0
    local alarms_created=0
    
    for log_group in $log_groups; do
        echo ""
        echo -e "${BLUE}📄 Procesando Log Group: $log_group${NC}"
        
        # Crear metric filter
        if create_metric_filter "$profile" "$log_group"; then
            filters_created=$((filters_created + 1))
        fi
        
        # Crear CloudWatch alarm
        if create_cloudwatch_alarm "$profile" "$sns_topic_arn" "$log_group"; then
            alarms_created=$((alarms_created + 1))
        fi
    done
    
    echo ""
    echo -e "${GREEN}✅ PERFIL $profile COMPLETADO:${NC}"
    echo "   - Metric Filters creados: $filters_created"
    echo "   - CloudWatch Alarms creadas: $alarms_created"
    echo "   - SNS Topic: $(basename $sns_topic_arn)"
    echo ""
    
    # Limpiar archivos temporales
    rm -f "/tmp/log_groups_${profile}.txt" "/tmp/sns_arn_${profile}.txt"
}

# Función principal
main() {
    show_banner
    check_prerequisites
    
    local total_profiles=${#PROFILES[@]}
    local successful_profiles=0
    
    echo -e "${YELLOW}📊 RESUMEN DE EJECUCIÓN${NC}"
    echo "Perfiles a procesar: $total_profiles"
    echo "Región: $REGION"
    echo ""
    
    # Procesar cada perfil
    for profile in "${PROFILES[@]}"; do
        if process_profile "$profile"; then
            successful_profiles=$((successful_profiles + 1))
        fi
    done
    
    # Resumen final
    echo "=================================================================="
    echo -e "${GREEN}🎉 IMPLEMENTACIÓN COMPLETADA${NC}"
    echo "=================================================================="
    echo "Perfiles procesados exitosamente: $successful_profiles/$total_profiles"
    echo ""
    echo -e "${BLUE}📋 ¿QUÉ SE HA CONFIGURADO?${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ Metric Filters para detectar logins sin MFA en CloudTrail"
    echo "✅ CloudWatch Alarms que se activan cuando se detecta el evento"
    echo "✅ SNS Topics para notificaciones de seguridad"
    echo "✅ Cumplimiento con CIS AWS Benchmark 3.2"
    echo ""
    echo -e "${YELLOW}🔔 PRÓXIMOS PASOS:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Configurar suscripciones de email en los SNS Topics"
    echo "2. Probar las alarmas generando un evento de prueba"
    echo "3. Revisar y ajustar los umbrales según sea necesario"
    echo "4. Documentar la implementación en su política de seguridad"
    echo ""
}

# Ejecutar script
main "$@"