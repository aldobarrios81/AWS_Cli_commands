#!/bin/bash
# verify-console-login-mfa-monitoring.sh
# Verificar el estado de la implementación de CIS 3.2 - Console Login Without MFA Monitoring

PROFILES=("ancla" "azbeacons" "azcenit")
REGION="us-east-1"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICACIÓN CIS 3.2 - CONSOLE LOGIN WITHOUT MFA MONITORING${NC}"
echo "=================================================================="
echo "Verificando implementación en perfiles: ${PROFILES[*]}"
echo "Región: $REGION"
echo ""

for profile in "${PROFILES[@]}"; do
    echo "=================================================================="
    echo -e "${PURPLE}📊 PERFIL: $profile${NC}"
    echo "=================================================================="
    
    # Obtener Account ID
    account_id=$(aws sts get-caller-identity --profile "$profile" --region "$REGION" --query 'Account' --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$account_id" ]; then
        echo -e "${RED}❌ ERROR: No se puede acceder al perfil '$profile'${NC}"
        echo ""
        continue
    fi
    
    echo -e "${GREEN}✅ Account ID: $account_id${NC}"
    echo ""
    
    # Verificar SNS Topic
    echo -e "${BLUE}📧 SNS Topic:${NC}"
    sns_topic=$(aws sns list-topics --profile "$profile" --region "$REGION" --query "Topics[?contains(TopicArn, 'cis-security-alerts')].TopicArn" --output text 2>/dev/null)
    
    if [ ! -z "$sns_topic" ]; then
        echo -e "${GREEN}   ✅ $sns_topic${NC}"
    else
        echo -e "${RED}   ❌ No configurado${NC}"
    fi
    echo ""
    
    # Verificar Log Groups de CloudTrail
    echo -e "${BLUE}📋 CloudTrail Log Groups:${NC}"
    log_groups=$(aws logs describe-log-groups --profile "$profile" --region "$REGION" --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' --output text 2>/dev/null)
    
    if [ ! -z "$log_groups" ]; then
        for group in $log_groups; do
            echo -e "${GREEN}   ✅ $group${NC}"
        done
    else
        echo -e "${YELLOW}   ⚠️ No se encontraron CloudTrail Log Groups${NC}"
    fi
    echo ""
    
    # Verificar Metric Filters
    echo -e "${BLUE}🔧 Metric Filters (CIS-ConsoleLoginWithoutMFA):${NC}"
    metric_filters=$(aws logs describe-metric-filters --profile "$profile" --region "$REGION" --filter-name-prefix "CIS-ConsoleLoginWithoutMFA" --query 'metricFilters[].{LogGroup:logGroupName,FilterName:filterName}' --output text 2>/dev/null)
    
    if [ ! -z "$metric_filters" ]; then
        echo "$metric_filters" | while read filter_name log_group; do
            if [ ! -z "$filter_name" ] && [ ! -z "$log_group" ]; then
                echo -e "${GREEN}   ✅ $filter_name en $log_group${NC}"
            fi
        done
    else
        echo -e "${RED}   ❌ No configurados${NC}"
    fi
    echo ""
    
    # Verificar CloudWatch Alarms
    echo -e "${BLUE}⏰ CloudWatch Alarms:${NC}"
    alarms=$(aws cloudwatch describe-alarms --profile "$profile" --region "$REGION" --query 'MetricAlarms[?contains(AlarmName, `CIS-3.2-ConsoleLoginWithoutMFA`)].{Name:AlarmName,State:StateValue}' --output text 2>/dev/null)
    
    if [ ! -z "$alarms" ]; then
        echo "$alarms" | while read alarm_name state; do
            if [ ! -z "$alarm_name" ] && [ ! -z "$state" ]; then
                case "$state" in
                    "OK")
                        echo -e "${GREEN}   ✅ $alarm_name [$state]${NC}"
                        ;;
                    "INSUFFICIENT_DATA")
                        echo -e "${YELLOW}   ⚠️ $alarm_name [$state]${NC}"
                        ;;
                    "ALARM")
                        echo -e "${RED}   🚨 $alarm_name [$state]${NC}"
                        ;;
                    *)
                        echo -e "${BLUE}   ℹ️ $alarm_name [$state]${NC}"
                        ;;
                esac
            fi
        done
    else
        echo -e "${RED}   ❌ No configuradas${NC}"
    fi
    
    echo ""
done

echo "=================================================================="
echo -e "${GREEN}🎯 RESUMEN DE VERIFICACIÓN COMPLETADO${NC}"
echo "=================================================================="
echo ""
echo -e "${YELLOW}📋 EXPLICACIÓN DE ESTADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ OK${NC} - Alarma en estado normal (no hay logins sin MFA)"
echo -e "${YELLOW}⚠️ INSUFFICIENT_DATA${NC} - Alarma recién creada o sin datos suficientes"
echo -e "${RED}🚨 ALARM${NC} - ¡ALERTA! Se detectaron logins sin MFA"
echo ""
echo -e "${BLUE}🔔 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Configurar suscripciones de email en los SNS Topics"
echo "2. Probar las alarmas (opcional) con un evento de prueba"
echo "3. Monitorear regularmente el estado de las alarmas"
echo "4. Revisar y actualizar la documentación de seguridad"
echo ""