#!/bin/bash

# Verificación de Amazon GuardDuty
# Valida el estado de GuardDuty y sus configuraciones de seguridad

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

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🛡️ VERIFICACIÓN AMAZON GUARDDUTY${NC}"
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

# Verificar si GuardDuty está habilitado
echo -e "${PURPLE}🛡️ Verificando estado de GuardDuty...${NC}"
DETECTOR_IDS=$(aws guardduty list-detectors \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "DetectorIds" \
    --output text 2>/dev/null || echo "None")

if [ "$DETECTOR_IDS" = "None" ] || [ -z "$DETECTOR_IDS" ] || [ "$DETECTOR_IDS" = "null" ]; then
    echo -e "${RED}❌ GuardDuty NO está habilitado${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-guardduty-all-regions.sh $PROFILE${NC}"
    echo ""
    
    # Generar reporte de no habilitado
    VERIFICATION_REPORT="guardduty-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"
    cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "guardduty_status": "DISABLED",
  "compliance": "NON_COMPLIANT",
  "recommendations": [
    "Habilitar GuardDuty para detección de amenazas",
    "Configurar notificaciones para hallazgos críticos",
    "Revisar hallazgos regularmente",
    "Considerar habilitar características avanzadas"
  ],
  "remediation_command": "./enable-guardduty-all-regions.sh $PROFILE"
}
EOF
    echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"
    exit 1
fi

# Obtener el primer detector (normalmente solo hay uno por región)
DETECTOR_ID=$(echo "$DETECTOR_IDS" | awk '{print $1}')
echo -e "✅ GuardDuty está habilitado"
echo -e "   📋 Detector ID: ${GREEN}$DETECTOR_ID${NC}"

# Obtener información detallada del detector
echo -e "${PURPLE}📊 Obteniendo información detallada...${NC}"
DETECTOR_INFO=$(aws guardduty get-detector \
    --detector-id "$DETECTOR_ID" \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error obteniendo información del detector${NC}"
    exit 1
fi

# Extraer información clave
STATUS=$(echo "$DETECTOR_INFO" | jq -r '.Status' 2>/dev/null)
SERVICE_ROLE=$(echo "$DETECTOR_INFO" | jq -r '.ServiceRole' 2>/dev/null)
FINDING_FREQUENCY=$(echo "$DETECTOR_INFO" | jq -r '.FindingPublishingFrequency' 2>/dev/null)
CREATED_AT=$(echo "$DETECTOR_INFO" | jq -r '.CreatedAt' 2>/dev/null)
UPDATED_AT=$(echo "$DETECTOR_INFO" | jq -r '.UpdatedAt' 2>/dev/null)

echo -e "📊 Información del Detector:"
echo -e "   🔍 Estado: ${GREEN}$STATUS${NC}"
echo -e "   🎯 Frecuencia de hallazgos: ${BLUE}$FINDING_FREQUENCY${NC}"
echo -e "   🔐 Service Role: ${BLUE}$SERVICE_ROLE${NC}"
echo -e "   📅 Creado: ${BLUE}$(date -d "$CREATED_AT" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$CREATED_AT")${NC}"
echo -e "   🔄 Actualizado: ${BLUE}$(date -d "$UPDATED_AT" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$UPDATED_AT")${NC}"

# Verificar características avanzadas
echo ""
echo -e "${PURPLE}🚀 Verificando características avanzadas...${NC}"
FEATURES=$(echo "$DETECTOR_INFO" | jq -r '.Features[]?' 2>/dev/null)

FEATURE_COUNT=0
ENABLED_FEATURES=0
DISABLED_FEATURES=0

if [ -n "$FEATURES" ]; then
    echo -e "📋 Características disponibles:"
    while IFS= read -r feature_line; do
        if [ -n "$feature_line" ]; then
            FEATURE_COUNT=$((FEATURE_COUNT + 1))
            FEATURE_NAME=$(echo "$feature_line" | jq -r '.Name' 2>/dev/null)
            FEATURE_STATUS=$(echo "$feature_line" | jq -r '.Status' 2>/dev/null)
            
            if [ "$FEATURE_STATUS" = "ENABLED" ]; then
                echo -e "   ✅ ${GREEN}$FEATURE_NAME${NC}: $FEATURE_STATUS"
                ENABLED_FEATURES=$((ENABLED_FEATURES + 1))
            else
                echo -e "   ❌ ${YELLOW}$FEATURE_NAME${NC}: $FEATURE_STATUS"
                DISABLED_FEATURES=$((DISABLED_FEATURES + 1))
            fi
        fi
    done <<< "$(echo "$DETECTOR_INFO" | jq -c '.Features[]?' 2>/dev/null)"
else
    echo -e "   ⚠️ ${YELLOW}Solo características básicas habilitadas${NC}"
fi

# Obtener estadísticas de hallazgos (últimos 7 días)
echo ""
echo -e "${PURPLE}📈 Verificando hallazgos recientes...${NC}"
SEVEN_DAYS_AGO=$(date -d '7 days ago' -Iseconds)
FINDINGS=$(aws guardduty list-findings \
    --detector-id "$DETECTOR_ID" \
    --finding-criteria "{\"UpdatedAt\":{\"GreaterThan\":\"$SEVEN_DAYS_AGO\"}}" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "FindingIds" \
    --output text 2>/dev/null || echo "")

if [ -n "$FINDINGS" ] && [ "$FINDINGS" != "None" ]; then
    FINDING_COUNT=$(echo "$FINDINGS" | wc -w)
    echo -e "📊 Hallazgos en los últimos 7 días: ${YELLOW}$FINDING_COUNT${NC}"
    
    if [ $FINDING_COUNT -gt 0 ]; then
        echo -e "${YELLOW}⚠️ Se encontraron hallazgos recientes. Revisar en la consola de GuardDuty${NC}"
        
        # Obtener algunos detalles de los primeros hallazgos
        FIRST_FINDINGS=$(echo "$FINDINGS" | head -3)
        if [ -n "$FIRST_FINDINGS" ]; then
            echo -e "   🔍 Primeros hallazgos (máximo 3):"
            for finding_id in $FIRST_FINDINGS; do
                FINDING_DETAIL=$(aws guardduty get-findings \
                    --detector-id "$DETECTOR_ID" \
                    --finding-ids "$finding_id" \
                    --region "$REGION" \
                    --profile "$PROFILE" \
                    --query "Findings[0].[Type,Severity,Title]" \
                    --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$FINDING_DETAIL" ]; then
                    FINDING_TYPE=$(echo "$FINDING_DETAIL" | cut -f1)
                    FINDING_SEVERITY=$(echo "$FINDING_DETAIL" | cut -f2)
                    FINDING_TITLE=$(echo "$FINDING_DETAIL" | cut -f3)
                    
                    case "$FINDING_SEVERITY" in
                        "HIGH"|"8"|"9"|"10") SEVERITY_COLOR="$RED" ;;
                        "MEDIUM"|"4"|"5"|"6"|"7") SEVERITY_COLOR="$YELLOW" ;;
                        *) SEVERITY_COLOR="$GREEN" ;;
                    esac
                    
                    echo -e "      • ${SEVERITY_COLOR}[$FINDING_SEVERITY]${NC} $FINDING_TYPE"
                    echo -e "        $FINDING_TITLE"
                fi
            done
        fi
    fi
else
    echo -e "✅ ${GREEN}No hay hallazgos en los últimos 7 días${NC}"
fi

# Verificar configuración de notificaciones (CloudWatch Events/EventBridge)
echo ""
echo -e "${PURPLE}🔔 Verificando configuración de notificaciones...${NC}"
EVENTBRIDGE_RULES=$(aws events list-rules \
    --name-prefix "GuardDuty" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Rules[].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$EVENTBRIDGE_RULES" ] && [ "$EVENTBRIDGE_RULES" != "None" ]; then
    RULE_COUNT=$(echo "$EVENTBRIDGE_RULES" | wc -w)
    echo -e "✅ ${GREEN}Reglas de EventBridge configuradas: $RULE_COUNT${NC}"
    for rule in $EVENTBRIDGE_RULES; do
        echo -e "   📋 $rule"
    done
else
    echo -e "⚠️ ${YELLOW}No se encontraron reglas de EventBridge para GuardDuty${NC}"
    echo -e "💡 Considerar configurar notificaciones para hallazgos críticos"
fi

# Calcular puntuación de seguridad
SECURITY_SCORE=0

# Puntuación base por estar habilitado
if [ "$STATUS" = "ENABLED" ]; then
    SECURITY_SCORE=$((SECURITY_SCORE + 3))
fi

# Puntuación por frecuencia de hallazgos
case "$FINDING_FREQUENCY" in
    "FIFTEEN_MINUTES") SECURITY_SCORE=$((SECURITY_SCORE + 2)) ;;
    "ONE_HOUR") SECURITY_SCORE=$((SECURITY_SCORE + 1)) ;;
    *) SECURITY_SCORE=$((SECURITY_SCORE + 0)) ;;
esac

# Puntuación por características avanzadas
if [ $ENABLED_FEATURES -gt 0 ]; then
    SECURITY_SCORE=$((SECURITY_SCORE + ENABLED_FEATURES))
fi

# Puntuación por notificaciones
if [ -n "$EVENTBRIDGE_RULES" ] && [ "$EVENTBRIDGE_RULES" != "None" ]; then
    SECURITY_SCORE=$((SECURITY_SCORE + 1))
fi

# Mostrar puntuación de seguridad
echo ""
if [ $SECURITY_SCORE -ge 8 ]; then
    echo -e "🔐 Puntuación de seguridad: ${GREEN}EXCELENTE ($SECURITY_SCORE/10)${NC}"
elif [ $SECURITY_SCORE -ge 6 ]; then
    echo -e "🔐 Puntuación de seguridad: ${BLUE}BUENA ($SECURITY_SCORE/10)${NC}"
elif [ $SECURITY_SCORE -ge 4 ]; then
    echo -e "🔐 Puntuación de seguridad: ${YELLOW}REGULAR ($SECURITY_SCORE/10)${NC}"
else
    echo -e "🔐 Puntuación de seguridad: ${RED}REQUIERE MEJORAS ($SECURITY_SCORE/10)${NC}"
fi

# Generar reporte de verificación
VERIFICATION_REPORT="guardduty-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "guardduty_status": "$STATUS",
  "detector_id": "$DETECTOR_ID",
  "finding_frequency": "$FINDING_FREQUENCY",
  "service_role": "$SERVICE_ROLE",
  "created_at": "$CREATED_AT",
  "updated_at": "$UPDATED_AT",
  "features": {
    "total_available": $FEATURE_COUNT,
    "enabled": $ENABLED_FEATURES,
    "disabled": $DISABLED_FEATURES
  },
  "recent_findings": {
    "count_last_7_days": $(echo "$FINDINGS" | wc -w || echo 0)
  },
  "notification_rules": $(echo "$EVENTBRIDGE_RULES" | wc -w || echo 0),
  "security_score": $SECURITY_SCORE,
  "compliance": "$(if [ $SECURITY_SCORE -ge 6 ]; then echo "COMPLIANT"; else echo "NEEDS_IMPROVEMENT"; fi)",
  "recommendations": [
    $(if [ "$FINDING_FREQUENCY" != "FIFTEEN_MINUTES" ]; then echo "\"Configurar frecuencia de hallazgos a 15 minutos\","; fi)
    $(if [ $DISABLED_FEATURES -gt 0 ]; then echo "\"Habilitar características avanzadas disponibles\","; fi)
    $(if [ -z "$EVENTBRIDGE_RULES" ] || [ "$EVENTBRIDGE_RULES" = "None" ]; then echo "\"Configurar notificaciones de EventBridge\","; fi)
    "Revisar hallazgos regularmente",
    "Configurar automated response para hallazgos críticos",
    "Implementar dashboard de monitoreo"
  ]
}
EOF

echo ""
echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de mejora
if [ $SECURITY_SCORE -lt 8 ]; then
    echo ""
    echo -e "${PURPLE}=== Comandos de Mejora ===${NC}"
    
    if [ "$FINDING_FREQUENCY" != "FIFTEEN_MINUTES" ] || [ $DISABLED_FEATURES -gt 0 ]; then
        echo -e "${CYAN}🔧 Para mejorar configuración:${NC}"
        echo -e "${BLUE}./enable-guardduty-all-regions.sh $PROFILE${NC}"
    fi
    
    if [ -z "$EVENTBRIDGE_RULES" ] || [ "$EVENTBRIDGE_RULES" = "None" ]; then
        echo -e "${CYAN}🔔 Para configurar notificaciones:${NC}"
        echo -e "${BLUE}aws events put-rule --name GuardDutyFindings --event-pattern '{\"source\":[\"aws.guardduty\"]}' --profile $PROFILE${NC}"
    fi
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN GUARDDUTY ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🛡️ Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "📋 Detector ID: ${GREEN}$DETECTOR_ID${NC}"
echo -e "📊 Estado: ${GREEN}$STATUS${NC}"
echo -e "🎯 Frecuencia: ${BLUE}$FINDING_FREQUENCY${NC}"

if [ $FEATURE_COUNT -gt 0 ]; then
    echo -e "🚀 Características: ${GREEN}$ENABLED_FEATURES habilitadas${NC} / ${YELLOW}$DISABLED_FEATURES deshabilitadas${NC}"
fi

if [ -n "$FINDINGS" ] && [ "$FINDINGS" != "None" ]; then
    FINDING_COUNT=$(echo "$FINDINGS" | wc -w)
    if [ $FINDING_COUNT -gt 0 ]; then
        echo -e "⚠️ Hallazgos recientes: ${YELLOW}$FINDING_COUNT en últimos 7 días${NC}"
    else
        echo -e "✅ Hallazgos recientes: ${GREEN}Ninguno en últimos 7 días${NC}"
    fi
fi

echo ""

# Estado final
if [ $SECURITY_SCORE -ge 8 ]; then
    echo -e "${GREEN}🎉 ESTADO: CONFIGURACIÓN EXCELENTE${NC}"
    echo -e "${BLUE}💡 GuardDuty está optimamente configurado${NC}"
elif [ $SECURITY_SCORE -ge 6 ]; then
    echo -e "${BLUE}✅ ESTADO: CONFIGURACIÓN BUENA${NC}"
    echo -e "${YELLOW}💡 Algunas mejoras menores recomendadas${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: REQUIERE MEJORAS${NC}"
    echo -e "${RED}💡 Implementar recomendaciones de seguridad${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$VERIFICATION_REPORT${NC}"
echo -e "🌐 Consola GuardDuty: ${BLUE}https://$REGION.console.aws.amazon.com/guardduty/home?region=$REGION${NC}"
echo ""