#!/bin/bash

# Verificación de Alertas en Tiempo Real de GuardDuty
# Valida la configuración de SNS, EventBridge y suscripciones

set -e

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    echo ""
    echo "Ejemplos:"
    echo "  $0 metrokia"
    echo "  $0 AZLOGICA"
    exit 1
fi

PROFILE="$1"
REGION="us-east-1"
SNS_TOPIC_NAME="guardduty-realtime-alerts"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔔 VERIFICACIÓN ALERTAS GUARDDUTY EN TIEMPO REAL${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo ""

# Verificar credenciales
echo -e "${PURPLE}🔍 Verificando credenciales...${NC}"
CALLER_IDENTITY=$(aws sts get-caller-identity --profile "$PROFILE" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    echo -e "${YELLOW}💡 Verificar: aws configure list --profile $PROFILE${NC}"
    exit 1
fi

ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | jq -r '.Account' 2>/dev/null)
CURRENT_USER=$(echo "$CALLER_IDENTITY" | jq -r '.Arn' 2>/dev/null)

echo -e "✅ Credenciales válidas"
echo -e "   📋 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "   👤 Usuario/Rol: ${BLUE}$CURRENT_USER${NC}"
echo ""

# Verificar que GuardDuty esté habilitado
echo -e "${PURPLE}🛡️ Verificando GuardDuty...${NC}"
DETECTOR_ID=$(aws guardduty list-detectors \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "DetectorIds[0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$DETECTOR_ID" == "None" || -z "$DETECTOR_ID" || "$DETECTOR_ID" == "null" ]]; then
    echo -e "${RED}❌ GuardDuty NO está habilitado${NC}"
    echo -e "${YELLOW}💡 Primero ejecutar: ./enable-guardduty-all-regions.sh $PROFILE${NC}"
    exit 1
fi

echo -e "✅ GuardDuty habilitado (Detector ID: ${GREEN}$DETECTOR_ID${NC})"
echo ""

# Verificar SNS Topic
echo -e "${PURPLE}📧 Verificando SNS Topic...${NC}"
TOPICS=$(aws sns list-topics \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" \
    --output text 2>/dev/null)

if [ -z "$TOPICS" ] || [ "$TOPICS" = "None" ]; then
    echo -e "${RED}❌ SNS Topic no encontrado${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-guardduty-realtime-alerts.sh $PROFILE${NC}"
    
    # Generar reporte de no configurado
    VERIFICATION_REPORT="guardduty-alerts-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"
    cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "guardduty_detector_id": "$DETECTOR_ID",
  "sns_topic_configured": false,
  "eventbridge_rules_configured": false,
  "subscriptions_count": 0,
  "compliance": "NON_COMPLIANT",
  "recommendations": [
    "Configurar SNS Topic para alertas de GuardDuty",
    "Crear reglas de EventBridge para diferentes severidades",
    "Configurar suscripciones email/SMS",
    "Probar las alertas con findings de prueba"
  ],
  "remediation_command": "./enable-guardduty-realtime-alerts.sh $PROFILE your-email@domain.com"
}
EOF
    echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"
    exit 1
fi

TOPIC_ARN=$(echo "$TOPICS" | head -1)
echo -e "✅ SNS Topic encontrado: ${GREEN}$TOPIC_ARN${NC}"

# Obtener atributos del Topic
TOPIC_ATTRIBUTES=$(aws sns get-topic-attributes \
    --topic-arn "$TOPIC_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null)

if [ $? -eq 0 ]; then
    DISPLAY_NAME=$(echo "$TOPIC_ATTRIBUTES" | jq -r '.Attributes.DisplayName // "N/A"' 2>/dev/null)
    SUBSCRIPTIONS_CONFIRMED=$(echo "$TOPIC_ATTRIBUTES" | jq -r '.Attributes.SubscriptionsConfirmed // "0"' 2>/dev/null)
    SUBSCRIPTIONS_PENDING=$(echo "$TOPIC_ATTRIBUTES" | jq -r '.Attributes.SubscriptionsPending // "0"' 2>/dev/null)
    
    echo -e "   📋 Display Name: ${BLUE}$DISPLAY_NAME${NC}"
    echo -e "   ✅ Suscripciones confirmadas: ${GREEN}$SUBSCRIPTIONS_CONFIRMED${NC}"
    echo -e "   ⏳ Suscripciones pendientes: ${YELLOW}$SUBSCRIPTIONS_PENDING${NC}"
fi

# Verificar suscripciones al Topic
echo ""
echo -e "${PURPLE}👥 Verificando suscripciones...${NC}"
SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
    --topic-arn "$TOPIC_ARN" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Subscriptions" \
    --output json 2>/dev/null)

if [ $? -eq 0 ] && [ "$SUBSCRIPTIONS" != "[]" ] && [ "$SUBSCRIPTIONS" != "null" ]; then
    SUB_COUNT=$(echo "$SUBSCRIPTIONS" | jq '. | length' 2>/dev/null)
    echo -e "📊 Total suscripciones: ${GREEN}$SUB_COUNT${NC}"
    echo -e "📋 Detalles de suscripciones:"
    
    echo "$SUBSCRIPTIONS" | jq -r '.[] | "   • Protocol: \(.Protocol) | Endpoint: \(.Endpoint) | Status: \(.SubscriptionArn)"' 2>/dev/null | while read -r line; do
        if [[ "$line" == *"PendingConfirmation"* ]]; then
            echo -e "${YELLOW}$line${NC}"
        elif [[ "$line" == *"arn:aws:sns"* ]]; then
            echo -e "${GREEN}$line${NC}"
        else
            echo -e "${BLUE}$line${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠️ No hay suscripciones configuradas${NC}"
    echo -e "💡 Agregar suscripción: aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@domain.com --profile $PROFILE"
fi

# Verificar reglas de EventBridge
echo ""
echo -e "${PURPLE}🔔 Verificando reglas de EventBridge...${NC}"

GUARDDUTY_RULES=$(aws events list-rules \
    --name-prefix "GuardDuty" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Rules" \
    --output json 2>/dev/null)

if [ $? -eq 0 ] && [ "$GUARDDUTY_RULES" != "[]" ] && [ "$GUARDDUTY_RULES" != "null" ]; then
    RULE_COUNT=$(echo "$GUARDDUTY_RULES" | jq '. | length' 2>/dev/null)
    echo -e "📊 Reglas de GuardDuty encontradas: ${GREEN}$RULE_COUNT${NC}"
    
    # Analizar cada regla
    RULES_ENABLED=0
    RULES_DISABLED=0
    
    echo -e "📋 Detalles de reglas:"
    echo "$GUARDDUTY_RULES" | jq -r '.[] | "\(.Name)|\(.State)|\(.Description // "N/A")"' 2>/dev/null | while IFS='|' read -r name state description; do
        if [ "$state" = "ENABLED" ]; then
            echo -e "   ✅ ${GREEN}$name${NC}: $state"
            RULES_ENABLED=$((RULES_ENABLED + 1))
        else
            echo -e "   ❌ ${RED}$name${NC}: $state"
            RULES_DISABLED=$((RULES_DISABLED + 1))
        fi
        echo -e "      📝 $description"
        
        # Verificar targets de la regla
        TARGETS=$(aws events list-targets-by-rule \
            --rule "$name" \
            --region "$REGION" \
            --profile "$PROFILE" \
            --query "Targets[].Arn" \
            --output text 2>/dev/null)
        
        if [ -n "$TARGETS" ] && [ "$TARGETS" != "None" ]; then
            TARGET_COUNT=$(echo "$TARGETS" | wc -w)
            echo -e "      🎯 Targets: ${BLUE}$TARGET_COUNT configurados${NC}"
            
            # Verificar si el SNS Topic está como target
            if echo "$TARGETS" | grep -q "$TOPIC_ARN"; then
                echo -e "      📧 ✅ SNS Topic configurado como target"
            else
                echo -e "      📧 ⚠️ SNS Topic NO configurado como target"
            fi
        else
            echo -e "      🎯 ${YELLOW}Sin targets configurados${NC}"
        fi
        echo ""
    done
else
    echo -e "${RED}❌ No se encontraron reglas de EventBridge para GuardDuty${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-guardduty-realtime-alerts.sh $PROFILE${NC}"
fi

# Verificar patrones de eventos en las reglas
echo -e "${PURPLE}🎯 Analizando patrones de eventos...${NC}"
PATTERN_ANALYSIS=""

# Verificar regla de alta severidad
HIGH_SEVERITY_RULE=$(echo "$GUARDDUTY_RULES" | jq -r '.[] | select(.Name | contains("HighSeverity")) | .Name' 2>/dev/null)
if [ -n "$HIGH_SEVERITY_RULE" ] && [ "$HIGH_SEVERITY_RULE" != "null" ]; then
    echo -e "✅ Regla de alta severidad configurada: ${GREEN}$HIGH_SEVERITY_RULE${NC}"
    PATTERN_ANALYSIS="$PATTERN_ANALYSIS\n   ✅ Alta severidad (≥7.0)"
else
    echo -e "⚠️ ${YELLOW}Regla de alta severidad no encontrada${NC}"
fi

# Verificar regla de severidad media
MEDIUM_SEVERITY_RULE=$(echo "$GUARDDUTY_RULES" | jq -r '.[] | select(.Name | contains("MediumSeverity")) | .Name' 2>/dev/null)
if [ -n "$MEDIUM_SEVERITY_RULE" ] && [ "$MEDIUM_SEVERITY_RULE" != "null" ]; then
    echo -e "✅ Regla de severidad media configurada: ${GREEN}$MEDIUM_SEVERITY_RULE${NC}"
    PATTERN_ANALYSIS="$PATTERN_ANALYSIS\n   ✅ Severidad media (4.0-6.9)"
else
    echo -e "⚠️ ${YELLOW}Regla de severidad media no encontrada${NC}"
fi

# Verificar regla de cryptomining
CRYPTO_RULE=$(echo "$GUARDDUTY_RULES" | jq -r '.[] | select(.Name | contains("Cryptocurrency")) | .Name' 2>/dev/null)
if [ -n "$CRYPTO_RULE" ] && [ "$CRYPTO_RULE" != "null" ]; then
    echo -e "✅ Regla de cryptomining configurada: ${GREEN}$CRYPTO_RULE${NC}"
    PATTERN_ANALYSIS="$PATTERN_ANALYSIS\n   ✅ Detección de cryptomining/malware"
else
    echo -e "⚠️ ${YELLOW}Regla de cryptomining no encontrada${NC}"
fi

# Probar conectividad con SNS (opcional)
echo ""
echo -e "${PURPLE}🧪 Prueba de conectividad (opcional)...${NC}"
read -p "¿Deseas enviar un mensaje de prueba al SNS Topic? (y/N): " test_sns
if [[ $test_sns == [yY] || $test_sns == [yY][eE][sS] ]]; then
    TEST_MESSAGE="🧪 PRUEBA DE ALERTAS GUARDDUTY\n\nEste es un mensaje de prueba para verificar que las alertas de GuardDuty están funcionando correctamente.\n\nFecha: $(date)\nAccount: $ACCOUNT_ID\nRegión: $REGION\nPerfil: $PROFILE\n\nSi recibes este mensaje, la configuración de alertas está funcionando! ✅"
    
    aws sns publish \
        --topic-arn "$TOPIC_ARN" \
        --message "$TEST_MESSAGE" \
        --subject "🧪 Prueba de Alertas GuardDuty - $PROFILE" \
        --region "$REGION" \
        --profile "$PROFILE" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "✅ ${GREEN}Mensaje de prueba enviado exitosamente${NC}"
        echo -e "📧 Verificar bandeja de entrada en los próximos minutos"
    else
        echo -e "❌ ${RED}Error enviando mensaje de prueba${NC}"
    fi
fi

# Calcular puntuación de alertas
ALERT_SCORE=0

# Puntuación base por SNS Topic
if [ -n "$TOPIC_ARN" ]; then
    ALERT_SCORE=$((ALERT_SCORE + 2))
fi

# Puntuación por suscripciones
CONFIRMED_SUBS=$(echo "$SUBSCRIPTIONS_CONFIRMED" | bc 2>/dev/null || echo "0")
if [ "$CONFIRMED_SUBS" -gt 0 ]; then
    ALERT_SCORE=$((ALERT_SCORE + 2))
fi

# Puntuación por reglas de EventBridge
RULE_COUNT_NUM=$(echo "$GUARDDUTY_RULES" | jq '. | length' 2>/dev/null || echo "0")
if [ "$RULE_COUNT_NUM" -ge 3 ]; then
    ALERT_SCORE=$((ALERT_SCORE + 3))
elif [ "$RULE_COUNT_NUM" -ge 1 ]; then
    ALERT_SCORE=$((ALERT_SCORE + 1))
fi

# Puntuación por patrones específicos
if [ -n "$HIGH_SEVERITY_RULE" ] && [ "$HIGH_SEVERITY_RULE" != "null" ]; then
    ALERT_SCORE=$((ALERT_SCORE + 2))
fi

if [ -n "$CRYPTO_RULE" ] && [ "$CRYPTO_RULE" != "null" ]; then
    ALERT_SCORE=$((ALERT_SCORE + 1))
fi

# Mostrar puntuación de alertas
echo ""
if [ $ALERT_SCORE -ge 8 ]; then
    echo -e "🔔 Puntuación de alertas: ${GREEN}EXCELENTE ($ALERT_SCORE/10)${NC}"
elif [ $ALERT_SCORE -ge 6 ]; then
    echo -e "🔔 Puntuación de alertas: ${BLUE}BUENA ($ALERT_SCORE/10)${NC}"
elif [ $ALERT_SCORE -ge 4 ]; then
    echo -e "🔔 Puntuación de alertas: ${YELLOW}REGULAR ($ALERT_SCORE/10)${NC}"
else
    echo -e "🔔 Puntuación de alertas: ${RED}REQUIERE MEJORAS ($ALERT_SCORE/10)${NC}"
fi

# Generar reporte de verificación
VERIFICATION_REPORT="guardduty-alerts-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "guardduty_detector_id": "$DETECTOR_ID",
  "sns_topic": {
    "configured": $([ -n "$TOPIC_ARN" ] && echo "true" || echo "false"),
    "topic_arn": "$TOPIC_ARN",
    "display_name": "$DISPLAY_NAME",
    "subscriptions_confirmed": $(echo "$SUBSCRIPTIONS_CONFIRMED" | bc 2>/dev/null || echo "0"),
    "subscriptions_pending": $(echo "$SUBSCRIPTIONS_PENDING" | bc 2>/dev/null || echo "0")
  },
  "eventbridge_rules": {
    "total_rules": $(echo "$RULE_COUNT_NUM" | bc 2>/dev/null || echo "0"),
    "high_severity_rule": "$([ -n "$HIGH_SEVERITY_RULE" ] && echo "$HIGH_SEVERITY_RULE" || echo "not_configured")",
    "medium_severity_rule": "$([ -n "$MEDIUM_SEVERITY_RULE" ] && echo "$MEDIUM_SEVERITY_RULE" || echo "not_configured")",
    "crypto_rule": "$([ -n "$CRYPTO_RULE" ] && echo "$CRYPTO_RULE" || echo "not_configured")"
  },
  "alert_score": $ALERT_SCORE,
  "compliance": "$(if [ $ALERT_SCORE -ge 6 ]; then echo "COMPLIANT"; else echo "NEEDS_IMPROVEMENT"; fi)",
  "recommendations": [
    $(if [ "$CONFIRMED_SUBS" -eq 0 ]; then echo "\"Configurar y confirmar suscripciones email/SMS\","; fi)
    $(if [ "$RULE_COUNT_NUM" -lt 3 ]; then echo "\"Configurar reglas de EventBridge para todas las severidades\","; fi)
    $(if [ -z "$HIGH_SEVERITY_RULE" ] || [ "$HIGH_SEVERITY_RULE" = "null" ]; then echo "\"Crear regla específica para alta severidad\","; fi)
    "Probar las alertas regularmente",
    "Configurar escalamiento para alertas críticas",
    "Documentar procedimientos de respuesta"
  ]
}
EOF

echo ""
echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de mejora
if [ $ALERT_SCORE -lt 8 ]; then
    echo ""
    echo -e "${PURPLE}=== Comandos de Mejora ===${NC}"
    
    if [ -z "$TOPIC_ARN" ] || [ "$RULE_COUNT_NUM" -lt 3 ]; then
        echo -e "${CYAN}🔧 Para configurar alertas completas:${NC}"
        echo -e "${BLUE}./enable-guardduty-realtime-alerts.sh $PROFILE your-email@domain.com${NC}"
    fi
    
    if [ "$CONFIRMED_SUBS" -eq 0 ]; then
        echo -e "${CYAN}📧 Para agregar suscripción email:${NC}"
        echo -e "${BLUE}aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint your-email@domain.com --profile $PROFILE${NC}"
    fi
    
    if [ "$SUBSCRIPTIONS_PENDING" -gt 0 ]; then
        echo -e "${CYAN}⏳ Hay suscripciones pendientes de confirmación${NC}"
        echo -e "${YELLOW}Revisar email y confirmar suscripciones${NC}"
    fi
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN ALERTAS GUARDDUTY ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🛡️ Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"

if [ -n "$TOPIC_ARN" ]; then
    echo -e "📧 SNS Topic: ${GREEN}Configurado${NC}"
    echo -e "👥 Suscripciones: ${GREEN}$SUBSCRIPTIONS_CONFIRMED confirmadas${NC} / ${YELLOW}$SUBSCRIPTIONS_PENDING pendientes${NC}"
else
    echo -e "📧 SNS Topic: ${RED}No configurado${NC}"
fi

if [ "$RULE_COUNT_NUM" -gt 0 ]; then
    echo -e "🔔 Reglas EventBridge: ${GREEN}$RULE_COUNT_NUM configuradas${NC}"
else
    echo -e "🔔 Reglas EventBridge: ${RED}No configuradas${NC}"
fi

echo ""

# Estado final
if [ $ALERT_SCORE -ge 8 ]; then
    echo -e "${GREEN}🎉 ESTADO: ALERTAS PERFECTAMENTE CONFIGURADAS${NC}"
    echo -e "${BLUE}💡 Sistema de alertas en tiempo real óptimo${NC}"
elif [ $ALERT_SCORE -ge 6 ]; then
    echo -e "${BLUE}✅ ESTADO: ALERTAS BIEN CONFIGURADAS${NC}"
    echo -e "${YELLOW}💡 Algunas mejoras menores recomendadas${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: ALERTAS REQUIEREN CONFIGURACIÓN${NC}"
    echo -e "${RED}💡 Implementar configuración completa de alertas${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$VERIFICATION_REPORT${NC}"
if [ -n "$TOPIC_ARN" ]; then
    echo -e "🌐 Consola SNS: ${BLUE}https://$REGION.console.aws.amazon.com/sns/v3/home?region=$REGION#/topic/$TOPIC_ARN${NC}"
fi
echo ""