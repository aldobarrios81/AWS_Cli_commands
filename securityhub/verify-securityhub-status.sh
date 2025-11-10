#!/bin/bash

# Verificación de AWS Security Hub
# Valida el estado de Security Hub, estándares, controles y configuraciones

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
echo -e "${BLUE}🛡️ VERIFICACIÓN AWS SECURITY HUB${NC}"
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

# Verificar si Security Hub está habilitado
echo -e "${PURPLE}🛡️ Verificando estado de Security Hub...${NC}"
HUB_INFO=$(aws securityhub describe-hub \
    --profile "$PROFILE" \
    --region "$REGION" 2>/dev/null || echo "NOT_ENABLED")

if [[ "$HUB_INFO" == "NOT_ENABLED" ]]; then
    echo -e "${RED}❌ Security Hub NO está habilitado${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-securityhub-auto-enable.sh $PROFILE${NC}"
    echo ""
    
    # Generar reporte de no habilitado
    VERIFICATION_REPORT="securityhub-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"
    cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "security_hub_status": "DISABLED",
  "standards_enabled": 0,
  "controls_total": 0,
  "controls_enabled": 0,
  "compliance": "NON_COMPLIANT",
  "recommendations": [
    "Habilitar Security Hub para gestión centralizada de seguridad",
    "Configurar estándares de seguridad (AWS Foundational, CIS)",
    "Habilitar integraciones con GuardDuty y otros servicios",
    "Configurar alertas para hallazgos críticos"
  ],
  "remediation_command": "./enable-securityhub-auto-enable.sh $PROFILE"
}
EOF
    echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"
    exit 1
fi

# Extraer información del hub
HUB_ARN=$(echo "$HUB_INFO" | jq -r '.HubArn' 2>/dev/null)
SUBSCRIBED_AT=$(echo "$HUB_INFO" | jq -r '.SubscribedAt' 2>/dev/null)
AUTO_ENABLE=$(echo "$HUB_INFO" | jq -r '.AutoEnableControls // "false"' 2>/dev/null)

echo -e "✅ Security Hub está habilitado"
echo -e "   📋 Hub ARN: ${GREEN}$HUB_ARN${NC}"
echo -e "   📅 Habilitado: ${BLUE}$(date -d "$SUBSCRIBED_AT" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$SUBSCRIBED_AT")${NC}"
echo -e "   🔄 Auto-enable controles: ${BLUE}$AUTO_ENABLE${NC}"
echo ""

# Verificar estándares habilitados
echo -e "${PURPLE}📊 Verificando estándares de seguridad...${NC}"
STANDARDS=$(aws securityhub get-enabled-standards \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "StandardsSubscriptions" \
    --output json 2>/dev/null || echo "[]")

if [ -n "$STANDARDS" ] && [ "$STANDARDS" != "[]" ]; then
    STANDARDS_COUNT=$(echo "$STANDARDS" | jq '. | length' 2>/dev/null)
    echo -e "📊 Estándares habilitados: ${GREEN}$STANDARDS_COUNT${NC}"
    
    echo -e "📋 Detalles de estándares:"
    echo "$STANDARDS" | jq -r '.[] | "\(.StandardsArn)|\(.StandardsStatus)|\(.StandardsStatusReason // "N/A")"' 2>/dev/null | while IFS='|' read -r arn status reason; do
        STD_NAME=$(basename "$arn" | cut -d'/' -f1 | sed 's/-/ /g' | sed 's/\b\w/\U&/g')
        
        if [ "$status" = "READY" ]; then
            echo -e "   ✅ ${GREEN}$STD_NAME${NC}: $status"
        elif [ "$status" = "PENDING" ]; then
            echo -e "   ⏳ ${YELLOW}$STD_NAME${NC}: $status"
        else
            echo -e "   ❌ ${RED}$STD_NAME${NC}: $status"
        fi
        
        if [ "$reason" != "N/A" ]; then
            echo -e "      📝 $reason"
        fi
    done
else
    echo -e "${YELLOW}⚠️ No hay estándares habilitados${NC}"
    echo -e "💡 Se recomienda habilitar al menos AWS Foundational Security Best Practices"
fi

echo ""

# Análisis de controles por estándar
echo -e "${PURPLE}🔧 Analizando controles de seguridad...${NC}"

TOTAL_CONTROLS=0
ENABLED_CONTROLS=0
DISABLED_CONTROLS=0
STANDARDS_ANALYZED=0

if [ -n "$STANDARDS" ] && [ "$STANDARDS" != "[]" ]; then
    echo "$STANDARDS" | jq -r '.[].StandardsSubscriptionArn' | while read -r sub_arn; do
        if [ -n "$sub_arn" ] && [ "$sub_arn" != "null" ]; then
            STANDARDS_ANALYZED=$((STANDARDS_ANALYZED + 1))
            STD_NAME=$(echo "$sub_arn" | grep -o '[^/]*\-[^/]*$' | head -1 | sed 's/-/ /g')
            
            echo -e "   🔍 ${CYAN}$STD_NAME${NC}:"
            
            CONTROLS=$(aws securityhub describe-standards-controls \
                --standards-subscription-arn "$sub_arn" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query "Controls[].{Status:ControlStatus,Id:ControlId,Title:Title,SeverityRating:SeverityRating}" \
                --output json 2>/dev/null)
            
            if [ -n "$CONTROLS" ] && [ "$CONTROLS" != "[]" ]; then
                STD_TOTAL=$(echo "$CONTROLS" | jq '. | length')
                STD_ENABLED=$(echo "$CONTROLS" | jq '[.[] | select(.Status == "ENABLED")] | length')
                STD_DISABLED=$(echo "$CONTROLS" | jq '[.[] | select(.Status == "DISABLED")] | length')
                
                echo -e "      📊 Total: ${BLUE}$STD_TOTAL${NC} | ✅ Habilitados: ${GREEN}$STD_ENABLED${NC} | ❌ Deshabilitados: ${RED}$STD_DISABLED${NC}"
                
                # Mostrar controles por severidad
                CRITICAL_CONTROLS=$(echo "$CONTROLS" | jq '[.[] | select(.SeverityRating == "CRITICAL")] | length')
                HIGH_CONTROLS=$(echo "$CONTROLS" | jq '[.[] | select(.SeverityRating == "HIGH")] | length')
                MEDIUM_CONTROLS=$(echo "$CONTROLS" | jq '[.[] | select(.SeverityRating == "MEDIUM")] | length')
                LOW_CONTROLS=$(echo "$CONTROLS" | jq '[.[] | select(.SeverityRating == "LOW")] | length')
                
                echo -e "      🚨 Críticos: ${RED}$CRITICAL_CONTROLS${NC} | 🔴 Altos: ${YELLOW}$HIGH_CONTROLS${NC} | 🟡 Medios: ${BLUE}$MEDIUM_CONTROLS${NC} | 🟢 Bajos: ${GREEN}$LOW_CONTROLS${NC}"
                
                # Mostrar algunos controles deshabilitados críticos
                DISABLED_CRITICAL=$(echo "$CONTROLS" | jq -r '.[] | select(.Status == "DISABLED" and .SeverityRating == "CRITICAL") | .Id' | head -3)
                if [ -n "$DISABLED_CRITICAL" ]; then
                    echo -e "      ⚠️ ${RED}Controles críticos deshabilitados:${NC}"
                    while IFS= read -r control_id; do
                        if [ -n "$control_id" ]; then
                            echo -e "         - $control_id"
                        fi
                    done <<< "$DISABLED_CRITICAL"
                fi
                
                TOTAL_CONTROLS=$((TOTAL_CONTROLS + STD_TOTAL))
                ENABLED_CONTROLS=$((ENABLED_CONTROLS + STD_ENABLED))
                DISABLED_CONTROLS=$((DISABLED_CONTROLS + STD_DISABLED))
            else
                echo -e "      ⚠️ ${YELLOW}No se pudieron obtener controles${NC}"
            fi
            echo ""
        fi
    done
fi

# Verificar hallazgos recientes
echo -e "${PURPLE}🔍 Verificando hallazgos recientes...${NC}"
SEVEN_DAYS_AGO=$(date -d '7 days ago' -Iseconds)

FINDINGS=$(aws securityhub get-findings \
    --filters "{\"UpdatedAt\":[{\"Start\":\"$SEVEN_DAYS_AGO\"}]}" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "Findings[].{Severity:Severity.Label,Type:Types[0],Title:Title,ComplianceStatus:Compliance.Status}" \
    --output json 2>/dev/null || echo "[]")

if [ -n "$FINDINGS" ] && [ "$FINDINGS" != "[]" ]; then
    FINDINGS_COUNT=$(echo "$FINDINGS" | jq '. | length')
    echo -e "📊 Hallazgos en los últimos 7 días: ${YELLOW}$FINDINGS_COUNT${NC}"
    
    # Contar por severidad
    CRITICAL_FINDINGS=$(echo "$FINDINGS" | jq '[.[] | select(.Severity == "CRITICAL")] | length')
    HIGH_FINDINGS=$(echo "$FINDINGS" | jq '[.[] | select(.Severity == "HIGH")] | length')
    MEDIUM_FINDINGS=$(echo "$FINDINGS" | jq '[.[] | select(.Severity == "MEDIUM")] | length')
    LOW_FINDINGS=$(echo "$FINDINGS" | jq '[.[] | select(.Severity == "LOW")] | length')
    
    echo -e "   🚨 Críticos: ${RED}$CRITICAL_FINDINGS${NC} | 🔴 Altos: ${YELLOW}$HIGH_FINDINGS${NC} | 🟡 Medios: ${BLUE}$MEDIUM_FINDINGS${NC} | 🟢 Bajos: ${GREEN}$LOW_FINDINGS${NC}"
    
    # Contar por estado de cumplimiento
    FAILED_FINDINGS=$(echo "$FINDINGS" | jq '[.[] | select(.ComplianceStatus == "FAILED")] | length')
    PASSED_FINDINGS=$(echo "$FINDINGS" | jq '[.[] | select(.ComplianceStatus == "PASSED")] | length')
    WARNING_FINDINGS=$(echo "$FINDINGS" | jq '[.[] | select(.ComplianceStatus == "WARNING")] | length')
    
    echo -e "   ❌ Fallados: ${RED}$FAILED_FINDINGS${NC} | ✅ Pasados: ${GREEN}$PASSED_FINDINGS${NC} | ⚠️ Advertencias: ${YELLOW}$WARNING_FINDINGS${NC}"
    
    if [ $CRITICAL_FINDINGS -gt 0 ] || [ $HIGH_FINDINGS -gt 0 ]; then
        echo -e "${YELLOW}⚠️ Se encontraron hallazgos críticos/altos. Revisar en la consola de Security Hub${NC}"
    fi
else
    echo -e "✅ ${GREEN}No hay hallazgos en los últimos 7 días${NC}"
fi

echo ""

# Verificar integraciones
echo -e "${PURPLE}🔗 Verificando integraciones...${NC}"
INTEGRATIONS=$(aws securityhub list-enabled-products-for-import \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "ProductArns" \
    --output json 2>/dev/null || echo "[]")

if [ -n "$INTEGRATIONS" ] && [ "$INTEGRATIONS" != "[]" ]; then
    INTEGRATION_COUNT=$(echo "$INTEGRATIONS" | jq '. | length')
    echo -e "✅ Integraciones habilitadas: ${GREEN}$INTEGRATION_COUNT${NC}"
    
    echo -e "📋 Productos integrados:"
    echo "$INTEGRATIONS" | jq -r '.[]' | while read -r integration; do
        PRODUCT_NAME=$(basename "$integration" | sed 's/-/ /g' | sed 's/\b\w/\U&/g')
        echo -e "   - $PRODUCT_NAME"
    done
else
    echo -e "ℹ️ ${BLUE}No hay integraciones de terceros configuradas${NC}"
fi

# Verificar servicios de AWS integrados automáticamente
echo -e "🔍 Verificando servicios AWS integrados:"

# GuardDuty
GUARDDUTY_STATUS=$(aws guardduty list-detectors \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "DetectorIds[0]" \
    --output text 2>/dev/null || echo "None")

if [[ "$GUARDDUTY_STATUS" != "None" && -n "$GUARDDUTY_STATUS" ]]; then
    echo -e "   ✅ ${GREEN}GuardDuty integrado${NC}"
else
    echo -e "   ❌ ${YELLOW}GuardDuty no habilitado${NC}"
fi

# Config
CONFIG_STATUS=$(aws configservice describe-configuration-recorders \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query "ConfigurationRecorders[0].name" \
    --output text 2>/dev/null || echo "None")

if [[ "$CONFIG_STATUS" != "None" && -n "$CONFIG_STATUS" ]]; then
    echo -e "   ✅ ${GREEN}AWS Config integrado${NC}"
else
    echo -e "   ❌ ${YELLOW}AWS Config no habilitado${NC}"
fi

# Verificar configuración de notificaciones
echo ""
echo -e "${PURPLE}🔔 Verificando configuración de alertas...${NC}"
SH_RULES=$(aws events list-rules \
    --name-prefix "SecurityHub" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "Rules[].Name" \
    --output text 2>/dev/null || echo "")

if [ -n "$SH_RULES" ] && [ "$SH_RULES" != "None" ]; then
    RULE_COUNT=$(echo "$SH_RULES" | wc -w)
    echo -e "✅ ${GREEN}Reglas de EventBridge configuradas: $RULE_COUNT${NC}"
    for rule in $SH_RULES; do
        echo -e "   📋 $rule"
    done
else
    echo -e "⚠️ ${YELLOW}No se encontraron reglas de EventBridge para Security Hub${NC}"
    echo -e "💡 Considerar ejecutar: ./enable-securityhub-realtime-alerts.sh $PROFILE"
fi

# Calcular puntuación de seguridad
SECURITY_SCORE=0

# Puntuación base por estar habilitado
SECURITY_SCORE=$((SECURITY_SCORE + 2))

# Puntuación por estándares habilitados
if [ -n "$STANDARDS" ] && [ "$STANDARDS" != "[]" ]; then
    STANDARDS_COUNT=$(echo "$STANDARDS" | jq '. | length' 2>/dev/null)
    if [ "$STANDARDS_COUNT" -ge 2 ]; then
        SECURITY_SCORE=$((SECURITY_SCORE + 3))
    elif [ "$STANDARDS_COUNT" -ge 1 ]; then
        SECURITY_SCORE=$((SECURITY_SCORE + 2))
    fi
fi

# Puntuación por controles habilitados
if [ $TOTAL_CONTROLS -gt 0 ]; then
    ENABLED_PERCENT=$((ENABLED_CONTROLS * 100 / TOTAL_CONTROLS))
    if [ $ENABLED_PERCENT -ge 90 ]; then
        SECURITY_SCORE=$((SECURITY_SCORE + 3))
    elif [ $ENABLED_PERCENT -ge 70 ]; then
        SECURITY_SCORE=$((SECURITY_SCORE + 2))
    elif [ $ENABLED_PERCENT -ge 50 ]; then
        SECURITY_SCORE=$((SECURITY_SCORE + 1))
    fi
fi

# Puntuación por integraciones
if [ -n "$INTEGRATIONS" ] && [ "$INTEGRATIONS" != "[]" ]; then
    SECURITY_SCORE=$((SECURITY_SCORE + 1))
fi

# Penalización por hallazgos críticos
if [ -n "$CRITICAL_FINDINGS" ] && [ "$CRITICAL_FINDINGS" -gt 0 ]; then
    SECURITY_SCORE=$((SECURITY_SCORE - 1))
fi

# Puntuación por alertas configuradas
if [ -n "$SH_RULES" ] && [ "$SH_RULES" != "None" ]; then
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
VERIFICATION_REPORT="securityhub-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "security_hub_status": "ENABLED",
  "hub_arn": "$HUB_ARN",
  "subscribed_at": "$SUBSCRIBED_AT",
  "auto_enable_controls": $AUTO_ENABLE,
  "standards": {
    "total_enabled": $(echo "$STANDARDS" | jq '. | length' 2>/dev/null || echo "0"),
    "details": $(echo "$STANDARDS" | jq '[.[] | {arn: .StandardsArn, status: .StandardsStatus}]' 2>/dev/null || echo "[]")
  },
  "controls": {
    "total": $TOTAL_CONTROLS,
    "enabled": $ENABLED_CONTROLS,
    "disabled": $DISABLED_CONTROLS,
    "compliance_percentage": $(if [ $TOTAL_CONTROLS -gt 0 ]; then echo "$((ENABLED_CONTROLS * 100 / TOTAL_CONTROLS))"; else echo "0"; fi)
  },
  "findings_last_7_days": {
    "total": $(echo "$FINDINGS" | jq '. | length' 2>/dev/null || echo "0"),
    "critical": $(echo "$CRITICAL_FINDINGS" | bc 2>/dev/null || echo "0"),
    "high": $(echo "$HIGH_FINDINGS" | bc 2>/dev/null || echo "0"),
    "medium": $(echo "$MEDIUM_FINDINGS" | bc 2>/dev/null || echo "0"),
    "low": $(echo "$LOW_FINDINGS" | bc 2>/dev/null || echo "0")
  },
  "integrations": {
    "third_party_count": $(echo "$INTEGRATIONS" | jq '. | length' 2>/dev/null || echo "0"),
    "guardduty_integrated": $(if [[ "$GUARDDUTY_STATUS" != "None" && -n "$GUARDDUTY_STATUS" ]]; then echo "true"; else echo "false"; fi),
    "config_integrated": $(if [[ "$CONFIG_STATUS" != "None" && -n "$CONFIG_STATUS" ]]; then echo "true"; else echo "false"; fi)
  },
  "alerting": {
    "eventbridge_rules": $(echo "$SH_RULES" | wc -w 2>/dev/null || echo "0")
  },
  "security_score": $SECURITY_SCORE,
  "compliance": "$(if [ $SECURITY_SCORE -ge 6 ]; then echo "COMPLIANT"; else echo "NEEDS_IMPROVEMENT"; fi)",
  "recommendations": [
    $(if [ -z "$STANDARDS" ] || [ "$STANDARDS" = "[]" ]; then echo "\"Habilitar estándares de seguridad (AWS Foundational, CIS)\","; fi)
    $(if [ $DISABLED_CONTROLS -gt 0 ]; then echo "\"Habilitar controles de seguridad deshabilitados\","; fi)
    $(if [ "$CRITICAL_FINDINGS" -gt 0 ]; then echo "\"Remediar hallazgos críticos inmediatamente\","; fi)
    $(if [[ "$GUARDDUTY_STATUS" == "None" || -z "$GUARDDUTY_STATUS" ]]; then echo "\"Habilitar GuardDuty para detección de amenazas\","; fi)
    $(if [ -z "$SH_RULES" ] || [ "$SH_RULES" = "None" ]; then echo "\"Configurar alertas de EventBridge\","; fi)
    "Revisar y remediar hallazgos regularmente",
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
    
    if [ -z "$STANDARDS" ] || [ "$STANDARDS" = "[]" ]; then
        echo -e "${CYAN}🔧 Para habilitar estándares de seguridad:${NC}"
        echo -e "${BLUE}./enable-securityhub-auto-enable.sh $PROFILE${NC}"
    fi
    
    if [[ "$GUARDDUTY_STATUS" == "None" || -z "$GUARDDUTY_STATUS" ]]; then
        echo -e "${CYAN}🛡️ Para habilitar GuardDuty:${NC}"
        echo -e "${BLUE}./enable-guardduty-all-regions.sh $PROFILE${NC}"
    fi
    
    if [ -z "$SH_RULES" ] || [ "$SH_RULES" = "None" ]; then
        echo -e "${CYAN}🔔 Para configurar alertas:${NC}"
        echo -e "${BLUE}./enable-securityhub-realtime-alerts.sh $PROFILE${NC}"
    fi
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN SECURITY HUB ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🛡️ Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "📊 Estado: ${GREEN}HABILITADO${NC}"

if [ -n "$STANDARDS" ] && [ "$STANDARDS" != "[]" ]; then
    STANDARDS_COUNT=$(echo "$STANDARDS" | jq '. | length' 2>/dev/null)
    echo -e "📋 Estándares: ${GREEN}$STANDARDS_COUNT habilitados${NC}"
fi

if [ $TOTAL_CONTROLS -gt 0 ]; then
    ENABLED_PERCENT=$((ENABLED_CONTROLS * 100 / TOTAL_CONTROLS))
    echo -e "🔧 Controles: ${GREEN}$ENABLED_CONTROLS/$TOTAL_CONTROLS habilitados${NC} (${BLUE}$ENABLED_PERCENT%${NC})"
fi

if [ -n "$FINDINGS" ] && [ "$FINDINGS" != "[]" ]; then
    FINDINGS_COUNT=$(echo "$FINDINGS" | jq '. | length')
    if [ "$CRITICAL_FINDINGS" -gt 0 ] || [ "$HIGH_FINDINGS" -gt 0 ]; then
        echo -e "⚠️ Hallazgos críticos/altos: ${RED}$((CRITICAL_FINDINGS + HIGH_FINDINGS))${NC}"
    else
        echo -e "✅ Sin hallazgos críticos/altos recientes"
    fi
else
    echo -e "✅ Sin hallazgos recientes"
fi

echo ""

# Estado final
if [ $SECURITY_SCORE -ge 8 ]; then
    echo -e "${GREEN}🎉 ESTADO: SECURITY HUB PERFECTAMENTE CONFIGURADO${NC}"
    echo -e "${BLUE}💡 Configuración de seguridad óptima${NC}"
elif [ $SECURITY_SCORE -ge 6 ]; then
    echo -e "${BLUE}✅ ESTADO: SECURITY HUB BIEN CONFIGURADO${NC}"
    echo -e "${YELLOW}💡 Algunas mejoras menores recomendadas${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: SECURITY HUB REQUIERE MEJORAS${NC}"
    echo -e "${RED}💡 Implementar recomendaciones de seguridad${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$VERIFICATION_REPORT${NC}"
echo -e "🌐 Consola Security Hub: ${BLUE}https://$REGION.console.aws.amazon.com/securityhub/home?region=$REGION${NC}"
echo ""