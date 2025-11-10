#!/bin/bash
# backup-vault-policies-summary.sh
# Resumen consolidado de políticas de backup vaults across all profiles
# Genera análisis comparativo y recomendaciones estratégicas

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=========================================================================="
echo -e "${BLUE}📊 RESUMEN CONSOLIDADO - BACKUP VAULT POLICIES${NC}"
echo "=========================================================================="
echo -e "Análisis multi-perfil de políticas de acceso para backup vaults"
echo -e "Generado: $(date)"
echo ""

# Profiles y regiones a analizar
PROFILES=("ancla" "azbeacons" "azcenit")
REGIONS=("us-east-1" "us-west-2" "eu-west-1")

# Variables globales de resumen
GLOBAL_TOTAL_VAULTS=0
GLOBAL_VAULTS_WITH_POLICIES=0
GLOBAL_VAULTS_WITHOUT_POLICIES=0
GLOBAL_VAULTS_WITH_ENCRYPTION=0
GLOBAL_VAULTS_WITH_NOTIFICATIONS=0
GLOBAL_HIGH_SECURITY_VAULTS=0
GLOBAL_ACTIVE_PROFILES=0
GLOBAL_ACTIVE_REGIONS=0
GLOBAL_SECURITY_VIOLATIONS=0

# Arrays para almacenar datos por perfil
declare -A PROFILE_DATA
declare -A REGION_DATA

# Función para verificar acceso al perfil
check_profile_access() {
    local profile="$1"
    aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null
}

# Función para contar backup vaults por región
count_vaults_in_region() {
    local profile="$1"
    local region="$2"
    
    aws backup describe-backup-vaults \
        --profile "$profile" \
        --region "$region" \
        --query 'length(BackupVaultList)' \
        --output text 2>/dev/null
}

# Función para analizar seguridad de backup vaults
analyze_vaults_security() {
    local profile="$1"
    local region="$2"
    local with_policies=0
    local without_policies=0
    local with_encryption=0
    local with_notifications=0
    local high_security=0
    local security_violations=0
    
    # Obtener lista de vaults
    local vaults=$(aws backup describe-backup-vaults \
        --profile "$profile" \
        --region "$region" \
        --query 'BackupVaultList[].BackupVaultName' \
        --output text 2>/dev/null)
    
    if [ -n "$vaults" ]; then
        for vault_name in $vaults; do
            if [ -n "$vault_name" ]; then
                local security_score=0
                
                # Verificar política de acceso
                local vault_policy=$(aws backup get-backup-vault-access-policy \
                    --backup-vault-name "$vault_name" \
                    --profile "$profile" \
                    --region "$region" \
                    --query 'Policy' \
                    --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$vault_policy" ] && [ "$vault_policy" != "None" ]; then
                    with_policies=$((with_policies + 1))
                    security_score=$((security_score + 30))
                    
                    # Verificar si es restrictiva
                    if [[ "$vault_policy" =~ "Deny" ]]; then
                        security_score=$((security_score + 20))
                    fi
                    
                    # Verificar controles específicos
                    if [[ "$vault_policy" =~ "MultiFactorAuth" ]]; then
                        security_score=$((security_score + 10))
                    fi
                    
                    if [[ "$vault_policy" =~ "SourceIp" ]]; then
                        security_score=$((security_score + 10))
                    fi
                    
                    # Verificar violaciones de seguridad
                    if [[ "$vault_policy" =~ '"Principal":"*"' ]] && [[ ! "$vault_policy" =~ "Deny" ]]; then
                        security_violations=$((security_violations + 1))
                    fi
                else
                    without_policies=$((without_policies + 1))
                fi
                
                # Verificar cifrado
                local vault_info=$(aws backup describe-backup-vault \
                    --backup-vault-name "$vault_name" \
                    --profile "$profile" \
                    --region "$region" \
                    --query 'EncryptionKeyArn' \
                    --output text 2>/dev/null)
                
                if [ -n "$vault_info" ] && [ "$vault_info" != "None" ]; then
                    with_encryption=$((with_encryption + 1))
                    security_score=$((security_score + 20))
                fi
                
                # Verificar notificaciones
                local notifications=$(aws backup get-backup-vault-notifications \
                    --backup-vault-name "$vault_name" \
                    --profile "$profile" \
                    --region "$region" \
                    --query 'SNSTopicArn' \
                    --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$notifications" ] && [ "$notifications" != "None" ]; then
                    with_notifications=$((with_notifications + 1))
                    security_score=$((security_score + 20))
                fi
                
                # Clasificar como alta seguridad si score >= 70
                if [ $security_score -ge 70 ]; then
                    high_security=$((high_security + 1))
                fi
            fi
        done
    fi
    
    echo "$with_policies|$without_policies|$with_encryption|$with_notifications|$high_security|$security_violations"
}

echo -e "${PURPLE}🔍 Analizando perfiles y regiones...${NC}"
echo ""

# Analizar cada perfil
for profile in "${PROFILES[@]}"; do
    echo -e "${CYAN}=== Perfil: $profile ===${NC}"
    
    # Verificar acceso
    account_id=$(check_profile_access "$profile")
    
    if [ -z "$account_id" ]; then
        echo -e "   ${RED}❌ Sin acceso al perfil $profile${NC}"
        PROFILE_DATA["$profile"]="ERROR|0|0|0|0|0|0|0"
        continue
    fi
    
    echo -e "   ✅ Account ID: ${GREEN}$account_id${NC}"
    GLOBAL_ACTIVE_PROFILES=$((GLOBAL_ACTIVE_PROFILES + 1))
    
    # Variables por perfil
    profile_total=0
    profile_with_policies=0
    profile_without_policies=0
    profile_with_encryption=0
    profile_with_notifications=0
    profile_high_security=0
    profile_security_violations=0
    profile_active_regions=0
    
    # Analizar cada región
    for region in "${REGIONS[@]}"; do
        vault_count=$(count_vaults_in_region "$profile" "$region")
        
        if [ -n "$vault_count" ] && [ "$vault_count" -gt 0 ]; then
            echo -e "   📍 ${GREEN}$region${NC}: $vault_count backup vaults"
            profile_active_regions=$((profile_active_regions + 1))
            
            # Analizar seguridad en la región
            security_result=$(analyze_vaults_security "$profile" "$region")
            IFS='|' read -r with_policies without_policies with_encryption with_notifications high_security security_violations <<< "$security_result"
            
            profile_total=$((profile_total + vault_count))
            profile_with_policies=$((profile_with_policies + with_policies))
            profile_without_policies=$((profile_without_policies + without_policies))
            profile_with_encryption=$((profile_with_encryption + with_encryption))
            profile_with_notifications=$((profile_with_notifications + with_notifications))
            profile_high_security=$((profile_high_security + high_security))
            profile_security_violations=$((profile_security_violations + security_violations))
            
            # Estadísticas por región
            region_key="$profile-$region"
            REGION_DATA["$region_key"]="$vault_count|$with_policies|$without_policies|$with_encryption|$with_notifications|$high_security|$security_violations"
            
            if [ "$with_policies" -eq "$vault_count" ]; then
                echo -e "      🛡️ Políticas: ${GREEN}100% ($with_policies/$vault_count)${NC}"
            elif [ "$with_policies" -gt 0 ]; then
                percent=$((with_policies * 100 / vault_count))
                echo -e "      🛡️ Políticas: ${YELLOW}$percent% ($with_policies/$vault_count)${NC}"
            else
                echo -e "      🛡️ Políticas: ${RED}0% (0/$vault_count)${NC}"
            fi
            
            if [ "$security_violations" -gt 0 ]; then
                echo -e "      ⚠️ Violaciones: ${RED}$security_violations${NC}"
            fi
            
        else
            echo -e "   📍 ${BLUE}$region${NC}: Sin backup vaults"
        fi
    done
    
    # Guardar datos del perfil
    PROFILE_DATA["$profile"]="$account_id|$profile_total|$profile_with_policies|$profile_without_policies|$profile_with_encryption|$profile_with_notifications|$profile_high_security|$profile_security_violations"
    
    # Sumar a totales globales
    GLOBAL_TOTAL_VAULTS=$((GLOBAL_TOTAL_VAULTS + profile_total))
    GLOBAL_VAULTS_WITH_POLICIES=$((GLOBAL_VAULTS_WITH_POLICIES + profile_with_policies))
    GLOBAL_VAULTS_WITHOUT_POLICIES=$((GLOBAL_VAULTS_WITHOUT_POLICIES + profile_without_policies))
    GLOBAL_VAULTS_WITH_ENCRYPTION=$((GLOBAL_VAULTS_WITH_ENCRYPTION + profile_with_encryption))
    GLOBAL_VAULTS_WITH_NOTIFICATIONS=$((GLOBAL_VAULTS_WITH_NOTIFICATIONS + profile_with_notifications))
    GLOBAL_HIGH_SECURITY_VAULTS=$((GLOBAL_HIGH_SECURITY_VAULTS + profile_high_security))
    GLOBAL_SECURITY_VIOLATIONS=$((GLOBAL_SECURITY_VIOLATIONS + profile_security_violations))
    
    # Mostrar resumen del perfil
    if [ $profile_total -gt 0 ]; then
        profile_policy_percent=$((profile_with_policies * 100 / profile_total))
        echo -e "   📊 Total: ${GREEN}$profile_total${NC} vaults, Políticas: ${GREEN}$profile_policy_percent%${NC}"
        
        if [ $profile_security_violations -gt 0 ]; then
            echo -e "   ⚠️ Violaciones de seguridad: ${RED}$profile_security_violations${NC}"
        fi
    else
        echo -e "   📊 ${BLUE}Sin backup vaults en este perfil${NC}"
    fi
    
    echo ""
done

# Contar regiones únicas activas
for profile in "${PROFILES[@]}"; do
    for region in "${REGIONS[@]}"; do
        region_key="$profile-$region"
        if [[ -n "${REGION_DATA[$region_key]}" ]]; then
            # Verificar si ya contamos esta región
            found=false
            for counted_region in $COUNTED_REGIONS; do
                if [ "$counted_region" = "$region" ]; then
                    found=true
                    break
                fi
            done
            
            if [ "$found" = false ]; then
                GLOBAL_ACTIVE_REGIONS=$((GLOBAL_ACTIVE_REGIONS + 1))
                COUNTED_REGIONS="$COUNTED_REGIONS $region"
            fi
        fi
    done
done

echo -e "${PURPLE}=== RESUMEN EJECUTIVO ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🏢 Perfiles analizados: ${GREEN}$GLOBAL_ACTIVE_PROFILES${NC}/3"
echo -e "🌍 Regiones con vaults: ${GREEN}$GLOBAL_ACTIVE_REGIONS${NC}"
echo -e "🗄️ Total backup vaults: ${GREEN}$GLOBAL_TOTAL_VAULTS${NC}"

if [ $GLOBAL_TOTAL_VAULTS -gt 0 ]; then
    GLOBAL_POLICY_PERCENT=$((GLOBAL_VAULTS_WITH_POLICIES * 100 / GLOBAL_TOTAL_VAULTS))
    GLOBAL_ENCRYPTION_PERCENT=$((GLOBAL_VAULTS_WITH_ENCRYPTION * 100 / GLOBAL_TOTAL_VAULTS))
    GLOBAL_NOTIFICATION_PERCENT=$((GLOBAL_VAULTS_WITH_NOTIFICATIONS * 100 / GLOBAL_TOTAL_VAULTS))
    
    echo -e "🛡️ Vaults con políticas: ${GREEN}$GLOBAL_VAULTS_WITH_POLICIES${NC} (${GREEN}$GLOBAL_POLICY_PERCENT%${NC})"
    echo -e "❌ Sin políticas: ${RED}$GLOBAL_VAULTS_WITHOUT_POLICIES${NC}"
    echo -e "🔐 Con cifrado KMS: ${GREEN}$GLOBAL_VAULTS_WITH_ENCRYPTION${NC} (${GREEN}$GLOBAL_ENCRYPTION_PERCENT%${NC})"
    echo -e "📢 Con notificaciones: ${GREEN}$GLOBAL_VAULTS_WITH_NOTIFICATIONS${NC} (${GREEN}$GLOBAL_NOTIFICATION_PERCENT%${NC})"
    echo -e "⭐ Alta seguridad: ${GREEN}$GLOBAL_HIGH_SECURITY_VAULTS${NC}"
    
    if [ $GLOBAL_SECURITY_VIOLATIONS -gt 0 ]; then
        echo -e "⚠️ Violaciones de seguridad: ${RED}$GLOBAL_SECURITY_VIOLATIONS${NC}"
    fi
else
    echo -e "${BLUE}ℹ️ No se encontraron backup vaults en ningún perfil${NC}"
fi

echo ""

# Tabla comparativa por perfil
echo -e "${PURPLE}=== COMPARATIVA POR PERFIL ===${NC}"
printf "%-12s %-15s %-8s %-10s %-12s %-8s %-12s %-10s\n" "PERFIL" "ACCOUNT_ID" "VAULTS" "POLÍTICAS" "% POLÍTICAS" "CIFRADO" "NOTIFICACIÓN" "VIOLACIONES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for profile in "${PROFILES[@]}"; do
    data="${PROFILE_DATA[$profile]}"
    
    if [[ "$data" == ERROR* ]]; then
        printf "%-12s %-15s %-8s %-10s %-12s %-8s %-12s %-10s\n" "$profile" "ERROR" "-" "-" "-" "-" "-" "-"
    else
        IFS='|' read -r account_id total with_policies without_policies with_encryption with_notifications high_security violations <<< "$data"
        
        if [ "$total" -gt 0 ]; then
            percent=$((with_policies * 100 / total))
            printf "%-12s %-15s %-8s %-10s %-12s %-8s %-12s %-10s\n" "$profile" "$account_id" "$total" "$with_policies" "${percent}%" "$with_encryption" "$with_notifications" "$violations"
        else
            printf "%-12s %-15s %-8s %-10s %-12s %-8s %-12s %-10s\n" "$profile" "$account_id" "0" "-" "-" "-" "-" "-"
        fi
    fi
done

echo ""

# Análisis de riesgos
echo -e "${PURPLE}=== ANÁLISIS DE RIESGOS ===${NC}"

RISK_LEVEL="BAJO"
RISK_COLOR="$GREEN"
RISK_ISSUES=()

if [ $GLOBAL_SECURITY_VIOLATIONS -gt 0 ]; then
    RISK_LEVEL="CRÍTICO"
    RISK_COLOR="$RED"
    RISK_ISSUES+=("$GLOBAL_SECURITY_VIOLATIONS vaults con violaciones de seguridad")
fi

if [ $GLOBAL_VAULTS_WITHOUT_POLICIES -gt 0 ]; then
    if [ $GLOBAL_VAULTS_WITHOUT_POLICIES -eq $GLOBAL_TOTAL_VAULTS ]; then
        if [ "$RISK_LEVEL" != "CRÍTICO" ]; then
            RISK_LEVEL="CRÍTICO"
            RISK_COLOR="$RED"
        fi
        RISK_ISSUES+=("Ningún backup vault tiene políticas configuradas")
    elif [ $GLOBAL_POLICY_PERCENT -lt 50 ]; then
        if [ "$RISK_LEVEL" != "CRÍTICO" ]; then
            RISK_LEVEL="ALTO"
            RISK_COLOR="$RED"
        fi
        RISK_ISSUES+=("Menos del 50% de vaults tienen políticas ($GLOBAL_POLICY_PERCENT%)")
    elif [ $GLOBAL_POLICY_PERCENT -lt 80 ]; then
        if [ "$RISK_LEVEL" == "BAJO" ]; then
            RISK_LEVEL="MEDIO"
            RISK_COLOR="$YELLOW"
        fi
        RISK_ISSUES+=("Políticas parciales implementadas ($GLOBAL_POLICY_PERCENT%)")
    fi
fi

if [ $GLOBAL_VAULTS_WITH_ENCRYPTION -lt $GLOBAL_TOTAL_VAULTS ]; then
    if [ "$RISK_LEVEL" == "BAJO" ]; then
        RISK_LEVEL="MEDIO"
        RISK_COLOR="$YELLOW"
    fi
    RISK_ISSUES+=("Vaults sin cifrado KMS detectados")
fi

echo -e "🎯 Nivel de riesgo: ${RISK_COLOR}$RISK_LEVEL${NC}"

if [ ${#RISK_ISSUES[@]} -gt 0 ]; then
    echo -e "⚠️ Problemas identificados:"
    for issue in "${RISK_ISSUES[@]}"; do
        echo -e "   🚨 $issue"
    done
else
    echo -e "✅ ${GREEN}No se identificaron riesgos críticos${NC}"
fi

echo ""

# Recomendaciones
echo -e "${PURPLE}=== RECOMENDACIONES ===${NC}"

if [ $GLOBAL_VAULTS_WITHOUT_POLICIES -gt 0 ] || [ $GLOBAL_SECURITY_VIOLATIONS -gt 0 ]; then
    echo -e "${YELLOW}🔧 ACCIÓN REQUERIDA:${NC}"
    echo -e "1. Implementar políticas restrictivas en vaults desprotegidos:"
    
    for profile in "${PROFILES[@]}"; do
        data="${PROFILE_DATA[$profile]}"
        if [[ "$data" != ERROR* ]]; then
            IFS='|' read -r account_id total with_policies without_policies with_encryption with_notifications high_security violations <<< "$data"
            
            if [ "$without_policies" -gt 0 ] || [ "$violations" -gt 0 ]; then
                echo -e "   ${CYAN}./limit-backup-vault-access.sh $profile${NC}"
            fi
        fi
    done
    
    echo ""
fi

echo -e "${GREEN}💡 MEJORES PRÁCTICAS:${NC}"
echo "1. 🛡️ Implementar políticas de acceso restrictivas en todos los vaults"
echo "2. 🔐 Habilitar cifrado KMS customer-managed para mayor control"
echo "3. 📢 Configurar notificaciones SNS para eventos críticos"
echo "4. 🔄 Implementar rotación automática de claves KMS"
echo "5. 🏷️ Aplicar tags consistentes para gestión y auditoría"
echo "6. 👥 Crear roles IAM específicos para administración de backup"
echo "7. 🔍 Auditar configuraciones trimestralmente"
echo "8. 📋 Documentar procedimientos de emergencia y recuperación"

echo ""

# Comandos útiles
echo -e "${PURPLE}=== COMANDOS ÚTILES ===${NC}"
echo -e "${CYAN}# Verificar estado actual de políticas:${NC}"
echo -e "for profile in ancla azbeacons azcenit; do"
echo -e "    echo \"=== \$profile ===\""
echo -e "    ./verify-backup-vault-policies.sh \$profile"
echo -e "done"
echo ""

echo -e "${CYAN}# Implementar políticas en todos los perfiles:${NC}"
echo -e "for profile in ancla azbeacons azcenit; do"
echo -e "    ./limit-backup-vault-access.sh \$profile"
echo -e "done"
echo ""

echo -e "${CYAN}# Verificar backup vaults manualmente:${NC}"
echo -e "aws backup describe-backup-vaults --profile PROFILE --region us-east-1"
echo ""

echo -e "${CYAN}# Verificar política específica:${NC}"
echo -e "aws backup get-backup-vault-access-policy \\"
echo -e "    --backup-vault-name VAULT_NAME \\"
echo -e "    --profile PROFILE --region us-east-1"

# Generar reporte JSON consolidado
CONSOLIDATED_REPORT="backup-vault-policies-consolidated-$(date +%Y%m%d-%H%M).json"

cat > "$CONSOLIDATED_REPORT" << EOF
{
    "consolidated_report": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "analysis_scope": {
            "profiles": [$(printf '"%s",' "${PROFILES[@]}" | sed 's/,$//')]
        }
    },
    "global_summary": {
        "active_profiles": $GLOBAL_ACTIVE_PROFILES,
        "active_regions": $GLOBAL_ACTIVE_REGIONS,
        "total_vaults": $GLOBAL_TOTAL_VAULTS,
        "vaults_with_policies": $GLOBAL_VAULTS_WITH_POLICIES,
        "vaults_without_policies": $GLOBAL_VAULTS_WITHOUT_POLICIES,
        "policy_coverage_percentage": $((GLOBAL_TOTAL_VAULTS > 0 ? GLOBAL_VAULTS_WITH_POLICIES * 100 / GLOBAL_TOTAL_VAULTS : 0))
    },
    "security_metrics": {
        "vaults_with_encryption": $GLOBAL_VAULTS_WITH_ENCRYPTION,
        "vaults_with_notifications": $GLOBAL_VAULTS_WITH_NOTIFICATIONS,
        "high_security_vaults": $GLOBAL_HIGH_SECURITY_VAULTS,
        "security_violations": $GLOBAL_SECURITY_VIOLATIONS
    },
    "risk_assessment": {
        "level": "$RISK_LEVEL",
        "unprotected_vaults_exist": $((GLOBAL_VAULTS_WITHOUT_POLICIES > 0)),
        "security_violations_exist": $((GLOBAL_SECURITY_VIOLATIONS > 0)),
        "compliance_status": "$([ $GLOBAL_VAULTS_WITHOUT_POLICIES -eq 0 ] && [ $GLOBAL_SECURITY_VIOLATIONS -eq 0 ] && echo "COMPLIANT" || echo "NON_COMPLIANT")"
    },
    "profile_breakdown": {
EOF

# Añadir datos por perfil al JSON
first_profile=true
for profile in "${PROFILES[@]}"; do
    data="${PROFILE_DATA[$profile]}"
    
    if [ "$first_profile" = false ]; then
        echo "," >> "$CONSOLIDATED_REPORT"
    fi
    first_profile=false
    
    if [[ "$data" == ERROR* ]]; then
        echo "        \"$profile\": {" >> "$CONSOLIDATED_REPORT"
        echo "            \"status\": \"ERROR\"," >> "$CONSOLIDATED_REPORT"
        echo "            \"accessible\": false" >> "$CONSOLIDATED_REPORT"
        echo -n "        }" >> "$CONSOLIDATED_REPORT"
    else
        IFS='|' read -r account_id total with_policies without_policies with_encryption with_notifications high_security violations <<< "$data"
        
        echo "        \"$profile\": {" >> "$CONSOLIDATED_REPORT"
        echo "            \"account_id\": \"$account_id\"," >> "$CONSOLIDATED_REPORT"
        echo "            \"total_vaults\": $total," >> "$CONSOLIDATED_REPORT"
        echo "            \"vaults_with_policies\": $with_policies," >> "$CONSOLIDATED_REPORT"
        echo "            \"vaults_without_policies\": $without_policies," >> "$CONSOLIDATED_REPORT"
        echo "            \"vaults_with_encryption\": $with_encryption," >> "$CONSOLIDATED_REPORT"
        echo "            \"vaults_with_notifications\": $with_notifications," >> "$CONSOLIDATED_REPORT"
        echo "            \"high_security_vaults\": $high_security," >> "$CONSOLIDATED_REPORT"
        echo "            \"security_violations\": $violations," >> "$CONSOLIDATED_REPORT"
        echo "            \"policy_coverage_percentage\": $((total > 0 ? with_policies * 100 / total : 0))" >> "$CONSOLIDATED_REPORT"
        echo -n "        }" >> "$CONSOLIDATED_REPORT"
    fi
done

cat >> "$CONSOLIDATED_REPORT" << EOF

    },
    "recommendations": [
        {
            "priority": "CRITICAL",
            "action": "Implement access policies for unprotected vaults",
            "applicable": $((GLOBAL_VAULTS_WITHOUT_POLICIES > 0))
        },
        {
            "priority": "HIGH", 
            "action": "Address security violations in vault policies",
            "applicable": $((GLOBAL_SECURITY_VIOLATIONS > 0))
        },
        {
            "priority": "MEDIUM",
            "action": "Enable KMS encryption for all vaults",
            "applicable": $((GLOBAL_VAULTS_WITH_ENCRYPTION < GLOBAL_TOTAL_VAULTS))
        },
        {
            "priority": "LOW",
            "action": "Configure SNS notifications for backup events",
            "applicable": $((GLOBAL_VAULTS_WITH_NOTIFICATIONS < GLOBAL_TOTAL_VAULTS))
        }
    ]
}
EOF

echo -e "✅ Reporte consolidado generado: ${GREEN}$CONSOLIDATED_REPORT${NC}"
echo ""

# Estado final
echo -e "${PURPLE}=== ESTADO FINAL ===${NC}"
if [ $GLOBAL_TOTAL_VAULTS -eq 0 ]; then
    echo -e "${BLUE}ℹ️ SIN BACKUP VAULTS EN NINGÚN PERFIL${NC}"
elif [ $GLOBAL_VAULTS_WITHOUT_POLICIES -eq 0 ] && [ $GLOBAL_SECURITY_VIOLATIONS -eq 0 ]; then
    echo -e "${GREEN}🎉 POLÍTICAS COMPLETAMENTE IMPLEMENTADAS${NC}"
    echo -e "${BLUE}💡 Todos los backup vaults tienen políticas restrictivas${NC}"
else
    echo -e "${YELLOW}⚠️ IMPLEMENTACIÓN PARCIAL ($GLOBAL_POLICY_PERCENT% completado)${NC}"
    if [ $GLOBAL_VAULTS_WITHOUT_POLICIES -gt 0 ]; then
        echo -e "${YELLOW}💡 $GLOBAL_VAULTS_WITHOUT_POLICIES vaults requieren políticas${NC}"
    fi
    if [ $GLOBAL_SECURITY_VIOLATIONS -gt 0 ]; then
        echo -e "${RED}💡 $GLOBAL_SECURITY_VIOLATIONS vaults con problemas críticos${NC}"
    fi
fi