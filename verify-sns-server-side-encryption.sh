#!/bin/bash
# verify-sns-server-side-encryption.sh
# Verificar configuración de cifrado server-side para tópicos SNS
# Auditar y validar implementación de cifrado KMS

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
REGION="us-east-1"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICACIÓN CIFRADO SERVER-SIDE SNS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC}"
echo "Auditando configuración de cifrado KMS en tópicos SNS"
echo ""

# Verificar credenciales
echo -e "${PURPLE}🔐 Verificando acceso...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"

# Variables para estadísticas
TOTAL_TOPICS=0
ENCRYPTED_TOPICS=0
UNENCRYPTED_TOPICS=0
KMS_CUSTOMER_MANAGED=0
KMS_AWS_MANAGED=0
TOPICS_WITH_SUBSCRIPTIONS=0
SECURITY_VIOLATIONS=0

# Verificar regiones
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Escaneando regiones...${NC}"

for region in "${REGIONS[@]}"; do
    SNS_COUNT=$(aws sns list-topics \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Topics)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$SNS_COUNT" ] && [ "$SNS_COUNT" -gt 0 ]; then
        echo -e "✅ ${GREEN}$region${NC}: $SNS_COUNT tópicos encontrados"
        ACTIVE_REGIONS+=("$region")
    else
        echo -e "ℹ️ ${BLUE}$region${NC}: Sin tópicos SNS"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron tópicos SNS en ninguna región${NC}"
    exit 0
fi

echo ""

# Función para evaluar seguridad de tópico
evaluate_topic_security() {
    local topic_arn="$1"
    local region="$2"
    local security_score=0
    local issues=()
    
    # Verificar cifrado
    local encryption_key=$(aws sns get-topic-attributes \
        --topic-arn "$topic_arn" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'Attributes.KmsMasterKeyId' \
        --output text 2>/dev/null)
    
    if [ -n "$encryption_key" ] && [ "$encryption_key" != "None" ]; then
        security_score=$((security_score + 25))
        
        # Verificar tipo de clave
        if [[ "$encryption_key" =~ "alias/aws/sns" ]]; then
            KMS_AWS_MANAGED=$((KMS_AWS_MANAGED + 1))
        else
            security_score=$((security_score + 15))
            KMS_CUSTOMER_MANAGED=$((KMS_CUSTOMER_MANAGED + 1))
        fi
    else
        issues+=("Sin cifrado KMS configurado")
    fi
    
    # Verificar política de acceso
    local topic_policy=$(aws sns get-topic-attributes \
        --topic-arn "$topic_arn" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'Attributes.Policy' \
        --output text 2>/dev/null)
    
    if [ -n "$topic_policy" ] && [ "$topic_policy" != "None" ]; then
        security_score=$((security_score + 10))
        
        # Verificar condiciones restrictivas
        if [[ "$topic_policy" =~ "Condition" ]]; then
            security_score=$((security_score + 15))
        else
            issues+=("Política sin condiciones restrictivas")
        fi
        
        # Verificar acceso público
        if [[ "$topic_policy" =~ '"Principal":"*"' ]]; then
            issues+=("Posible acceso público en política")
            SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
        fi
    else
        issues+=("Sin política de acceso personalizada")
    fi
    
    # Verificar suscripciones
    local subscriptions=$(aws sns list-subscriptions-by-topic \
        --topic-arn "$topic_arn" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Subscriptions)' \
        --output text 2>/dev/null)
    
    if [ -n "$subscriptions" ] && [ "$subscriptions" -gt 0 ]; then
        security_score=$((security_score + 10))
        TOPICS_WITH_SUBSCRIPTIONS=$((TOPICS_WITH_SUBSCRIPTIONS + 1))
    fi
    
    # Verificar atributos de entrega
    local delivery_policy=$(aws sns get-topic-attributes \
        --topic-arn "$topic_arn" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'Attributes.DeliveryPolicy' \
        --output text 2>/dev/null)
    
    if [ -n "$delivery_policy" ] && [ "$delivery_policy" != "None" ]; then
        security_score=$((security_score + 10))
    fi
    
    # Verificar configuración de display name
    local display_name=$(aws sns get-topic-attributes \
        --topic-arn "$topic_arn" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'Attributes.DisplayName' \
        --output text 2>/dev/null)
    
    if [ -n "$display_name" ] && [ "$display_name" != "None" ]; then
        security_score=$((security_score + 5))
    fi
    
    # Verificar tags
    local tags=$(aws sns list-tags-for-resource \
        --resource-arn "$topic_arn" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Tags)' \
        --output text 2>/dev/null)
    
    if [ -n "$tags" ] && [ "$tags" -gt 0 ]; then
        security_score=$((security_score + 10))
    else
        issues+=("Sin tags de identificación")
    fi
    
    # Determinar clasificación de seguridad
    local security_level
    local security_color
    
    if [ $security_score -ge 80 ]; then
        security_level="EXCELENTE"
        security_color="$GREEN"
    elif [ $security_score -ge 60 ]; then
        security_level="BUENA"
        security_color="$GREEN"
    elif [ $security_score -ge 40 ]; then
        security_level="MEDIA"
        security_color="$YELLOW"
    elif [ $security_score -ge 20 ]; then
        security_level="BAJA"
        security_color="$YELLOW"
    else
        security_level="CRÍTICA"
        security_color="$RED"
    fi
    
    echo "$security_score|$security_level|$security_color|${issues[*]}|$encryption_key"
}

# Procesar cada región
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Analizando región: $CURRENT_REGION ===${NC}"
    
    # Obtener tópicos SNS
    SNS_TOPICS=$(aws sns list-topics \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'Topics[].TopicArn' \
        --output text 2>/dev/null)
    
    if [ -z "$SNS_TOPICS" ]; then
        echo -e "${BLUE}ℹ️ Sin tópicos en región $CURRENT_REGION${NC}"
        continue
    fi
    
    for topic_arn in $SNS_TOPICS; do
        if [ -n "$topic_arn" ]; then
            TOTAL_TOPICS=$((TOTAL_TOPICS + 1))
            
            # Extraer nombre del tópico
            TOPIC_NAME=$(basename "$topic_arn")
            
            echo -e "${CYAN}📢 Tópico: $TOPIC_NAME${NC}"
            echo -e "   🌐 ARN: ${BLUE}$topic_arn${NC}"
            
            # Evaluar seguridad del tópico
            SECURITY_RESULT=$(evaluate_topic_security "$topic_arn" "$CURRENT_REGION")
            
            # Parsear resultado
            IFS='|' read -r score level color issues encryption_key <<< "$SECURITY_RESULT"
            
            # Mostrar estado de cifrado
            if [ -n "$encryption_key" ] && [ "$encryption_key" != "None" ]; then
                echo -e "   ✅ Cifrado: ${GREEN}HABILITADO${NC}"
                echo -e "   🔑 Clave KMS: ${BLUE}$encryption_key${NC}"
                ENCRYPTED_TOPICS=$((ENCRYPTED_TOPICS + 1))
                
                # Verificar detalles de la clave KMS si es customer managed
                if [[ ! "$encryption_key" =~ "alias/aws/sns" ]]; then
                    KEY_INFO=$(aws kms describe-key \
                        --key-id "$encryption_key" \
                        --profile "$PROFILE" \
                        --region "$CURRENT_REGION" \
                        --query '[KeyMetadata.Description,KeyMetadata.KeyUsage,KeyMetadata.KeyState]' \
                        --output text 2>/dev/null)
                    
                    if [ $? -eq 0 ]; then
                        echo -e "   🔍 Descripción: ${BLUE}$(echo "$KEY_INFO" | cut -f1)${NC}"
                        echo -e "   🎯 Estado: ${GREEN}$(echo "$KEY_INFO" | cut -f3)${NC}"
                    fi
                fi
                
            else
                echo -e "   ❌ Cifrado: ${RED}NO CONFIGURADO${NC}"
                UNENCRYPTED_TOPICS=$((UNENCRYPTED_TOPICS + 1))
            fi
            
            # Verificar información adicional del tópico
            TOPIC_ATTRIBUTES=$(aws sns get-topic-attributes \
                --topic-arn "$topic_arn" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Attributes.[DisplayName,SubscriptionsConfirmed,SubscriptionsPending,Owner]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                DISPLAY_NAME=$(echo "$TOPIC_ATTRIBUTES" | cut -f1)
                SUBS_CONFIRMED=$(echo "$TOPIC_ATTRIBUTES" | cut -f2)
                SUBS_PENDING=$(echo "$TOPIC_ATTRIBUTES" | cut -f3)
                OWNER=$(echo "$TOPIC_ATTRIBUTES" | cut -f4)
                
                if [ -n "$DISPLAY_NAME" ] && [ "$DISPLAY_NAME" != "None" ]; then
                    echo -e "   📝 Nombre Display: ${BLUE}$DISPLAY_NAME${NC}"
                fi
                
                echo -e "   👥 Propietario: ${BLUE}$OWNER${NC}"
                echo -e "   📊 Suscripciones: ${GREEN}$SUBS_CONFIRMED confirmadas${NC}"
                
                if [ "$SUBS_PENDING" -gt 0 ]; then
                    echo -e "   ⏳ Pendientes: ${YELLOW}$SUBS_PENDING${NC}"
                fi
            fi
            
            # Verificar suscripciones detalladas
            SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
                --topic-arn "$topic_arn" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Subscriptions[].[Protocol,Endpoint,SubscriptionArn]' \
                --output text 2>/dev/null)
            
            if [ -n "$SUBSCRIPTIONS" ]; then
                echo -e "   🔗 Tipos de suscripciones:"
                echo "$SUBSCRIPTIONS" | while read protocol endpoint sub_arn; do
                    if [ -n "$protocol" ] && [ "$protocol" != "None" ]; then
                        # Truncar endpoint si es muy largo
                        if [ ${#endpoint} -gt 50 ]; then
                            endpoint="${endpoint:0:47}..."
                        fi
                        echo -e "      📌 ${BLUE}$protocol${NC}: $endpoint"
                    fi
                done
            fi
            
            # Verificar tags
            TAGS=$(aws sns list-tags-for-resource \
                --resource-arn "$topic_arn" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Tags[].[Key,Value]' \
                --output text 2>/dev/null)
            
            if [ -n "$TAGS" ]; then
                TAG_COUNT=$(echo "$TAGS" | wc -l)
                echo -e "   🏷️ Tags: ${GREEN}$TAG_COUNT configurados${NC}"
                
                # Mostrar algunos tags importantes
                while read key value; do
                    if [ -n "$key" ] && [[ "$key" =~ ^(Environment|Purpose|Owner|Project)$ ]]; then
                        echo -e "      🏷️ ${BLUE}$key${NC}: $value"
                    fi
                done <<< "$TAGS"
            else
                echo -e "   🏷️ Tags: ${YELLOW}Sin configurar${NC}"
            fi
            
            # Mostrar puntuación de seguridad
            echo -e "   🔐 Seguridad: ${color}$level ($score/100)${NC}"
            
            # Mostrar problemas si existen
            if [ -n "$issues" ] && [ "$issues" != " " ]; then
                echo -e "   ⚠️ Problemas detectados:"
                IFS=' ' read -ra ISSUE_ARRAY <<< "$issues"
                for issue in "${ISSUE_ARRAY[@]}"; do
                    if [ -n "$issue" ]; then
                        echo -e "      🚨 $issue"
                    fi
                done
            fi
            
            echo ""
        fi
    done
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION completada${NC}"
    echo ""
done

# Verificar métricas CloudWatch relacionadas
echo -e "${PURPLE}=== Verificando Monitoreo CloudWatch ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "📊 Verificando alarmas SNS en: ${CYAN}$CURRENT_REGION${NC}"
    
    # Buscar alarmas relacionadas con SNS
    SNS_ALARMS=$(aws cloudwatch describe-alarms \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'MetricAlarms[?Namespace==`AWS/SNS`].[AlarmName,StateValue,MetricName]' \
        --output text 2>/dev/null)
    
    if [ -n "$SNS_ALARMS" ]; then
        ALARM_COUNT=$(echo "$SNS_ALARMS" | wc -l)
        echo -e "   ✅ Alarmas encontradas: ${GREEN}$ALARM_COUNT${NC}"
        
        while read alarm_name state metric; do
            if [ -n "$alarm_name" ]; then
                STATE_COLOR="$GREEN"
                if [ "$state" == "ALARM" ]; then
                    STATE_COLOR="$RED"
                elif [ "$state" == "INSUFFICIENT_DATA" ]; then
                    STATE_COLOR="$YELLOW"
                fi
                echo -e "   📊 ${BLUE}$alarm_name${NC}: ${STATE_COLOR}$state${NC} ($metric)"
            fi
        done <<< "$SNS_ALARMS"
    else
        echo -e "   ⚠️ Sin alarmas CloudWatch configuradas para SNS"
    fi
done

# Generar reporte de verificación
REPORT_FILE="sns-encryption-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$REPORT_FILE" << EOF
{
    "verification_report": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "profile": "$PROFILE",
        "account_id": "$ACCOUNT_ID",
        "regions_analyzed": [$(printf '"%s",' "${ACTIVE_REGIONS[@]}" | sed 's/,$//')]
    },
    "encryption_summary": {
        "total_topics": $TOTAL_TOPICS,
        "encrypted_topics": $ENCRYPTED_TOPICS,
        "unencrypted_topics": $UNENCRYPTED_TOPICS,
        "encryption_percentage": $((TOTAL_TOPICS > 0 ? ENCRYPTED_TOPICS * 100 / TOTAL_TOPICS : 0))
    },
    "kms_analysis": {
        "customer_managed_keys": $KMS_CUSTOMER_MANAGED,
        "aws_managed_keys": $KMS_AWS_MANAGED
    },
    "security_metrics": {
        "topics_with_subscriptions": $TOPICS_WITH_SUBSCRIPTIONS,
        "security_violations": $SECURITY_VIOLATIONS
    },
    "compliance_status": {
        "fully_encrypted": $((UNENCRYPTED_TOPICS == 0)),
        "recommendation": "$([ $UNENCRYPTED_TOPICS -eq 0 ] && echo "Compliant" || echo "Requires encryption implementation")"
    }
}
EOF

echo -e "✅ Reporte JSON generado: ${GREEN}$REPORT_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN SNS ENCRYPTION ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔍 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones analizadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC}"
echo -e "📢 Total tópicos: ${GREEN}$TOTAL_TOPICS${NC}"

if [ $TOTAL_TOPICS -gt 0 ]; then
    ENCRYPTION_PERCENT=$((ENCRYPTED_TOPICS * 100 / TOTAL_TOPICS))
    echo ""
    echo -e "🔐 Tópicos cifrados: ${GREEN}$ENCRYPTED_TOPICS${NC} (${GREEN}$ENCRYPTION_PERCENT%${NC})"
    echo -e "❌ Sin cifrar: ${RED}$UNENCRYPTED_TOPICS${NC}"
    echo -e "🔑 Claves customer-managed: ${GREEN}$KMS_CUSTOMER_MANAGED${NC}"
    echo -e "🔑 Claves AWS-managed: ${BLUE}$KMS_AWS_MANAGED${NC}"
    echo -e "📡 Tópicos con suscripciones: ${GREEN}$TOPICS_WITH_SUBSCRIPTIONS${NC}"
    
    if [ $SECURITY_VIOLATIONS -gt 0 ]; then
        echo -e "⚠️ Violaciones de seguridad: ${YELLOW}$SECURITY_VIOLATIONS${NC}"
    fi
    
    echo ""
    
    # Estado de cumplimiento
    if [ $UNENCRYPTED_TOPICS -eq 0 ]; then
        echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE CIFRADO${NC}"
        echo -e "${BLUE}💡 Todos los tópicos SNS implementan cifrado${NC}"
    else
        COMPLIANCE_PERCENT=$((ENCRYPTED_TOPICS * 100 / TOTAL_TOPICS))
        echo -e "${YELLOW}⚠️ ESTADO: CIFRADO PARCIAL ($COMPLIANCE_PERCENT%)${NC}"
        echo -e "${YELLOW}💡 $UNENCRYPTED_TOPICS tópicos requieren cifrado${NC}"
    fi
else
    echo -e "${BLUE}ℹ️ ESTADO: SIN TÓPICOS SNS${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$REPORT_FILE${NC}"
echo ""

# Comandos sugeridos para remediar problemas
if [ $UNENCRYPTED_TOPICS -gt 0 ]; then
    echo -e "${YELLOW}🔧 COMANDOS DE REMEDIACIÓN:${NC}"
    echo -e "Para habilitar cifrado en tópicos sin protección:"
    echo -e "${CYAN}./enable-sns-server-side-encryption.sh $PROFILE${NC}"
    echo ""
fi