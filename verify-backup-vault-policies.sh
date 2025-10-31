#!/bin/bash
# verify-backup-vault-policies.sh
# Verificar y auditar políticas de acceso en backup vaults
# Evaluar configuraciones de seguridad y cumplimiento

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
echo -e "${BLUE}🔍 VERIFICACIÓN POLÍTICAS BACKUP VAULTS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC}"
echo "Auditando configuraciones de seguridad en backup vaults"
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
TOTAL_VAULTS=0
VAULTS_WITH_POLICIES=0
VAULTS_WITHOUT_POLICIES=0
VAULTS_WITH_ENCRYPTION=0
VAULTS_WITH_NOTIFICATIONS=0
SECURITY_VIOLATIONS=0
HIGH_SECURITY_VAULTS=0

# Verificar regiones
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Escaneando regiones...${NC}"

for region in "${REGIONS[@]}"; do
    VAULT_COUNT=$(aws backup describe-backup-vaults \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(BackupVaultList)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$VAULT_COUNT" ] && [ "$VAULT_COUNT" -gt 0 ]; then
        echo -e "✅ ${GREEN}$region${NC}: $VAULT_COUNT backup vaults encontrados"
        ACTIVE_REGIONS+=("$region")
    else
        echo -e "ℹ️ ${BLUE}$region${NC}: Sin backup vaults"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron backup vaults en ninguna región${NC}"
    exit 0
fi

echo ""

# Función para evaluar seguridad de un backup vault
evaluate_vault_security() {
    local vault_name="$1"
    local region="$2"
    local security_score=0
    local issues=()
    local features=()
    
    # Verificar información básica del vault
    local vault_info=$(aws backup describe-backup-vault \
        --backup-vault-name "$vault_name" \
        --profile "$PROFILE" \
        --region "$region" \
        --query '[BackupVaultArn,EncryptionKeyArn,NumberOfRecoveryPoints,CreationDate]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo "ERROR|0|Cannot access vault"
        return 1
    fi
    
    local vault_arn=$(echo "$vault_info" | cut -f1)
    local encryption_key=$(echo "$vault_info" | cut -f2)
    local recovery_points=$(echo "$vault_info" | cut -f3)
    local creation_date=$(echo "$vault_info" | cut -f4)
    
    # Verificar cifrado (20 puntos)
    if [ -n "$encryption_key" ] && [ "$encryption_key" != "None" ]; then
        security_score=$((security_score + 20))
        features+=("Cifrado KMS habilitado")
        VAULTS_WITH_ENCRYPTION=$((VAULTS_WITH_ENCRYPTION + 1))
    else
        issues+=("Sin cifrado KMS configurado")
    fi
    
    # Verificar política de acceso (30 puntos)
    local vault_policy=$(aws backup get-backup-vault-access-policy \
        --backup-vault-name "$vault_name" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'Policy' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$vault_policy" ] && [ "$vault_policy" != "None" ]; then
        security_score=$((security_score + 15))
        features+=("Política de acceso configurada")
        VAULTS_WITH_POLICIES=$((VAULTS_WITH_POLICIES + 1))
        
        # Verificar si la política es restrictiva
        if [[ "$vault_policy" =~ "Deny" ]]; then
            security_score=$((security_score + 15))
            features+=("Política restrictiva con denegaciones")
            
            # Verificar controles específicos
            if [[ "$vault_policy" =~ "MultiFactorAuth" ]]; then
                security_score=$((security_score + 5))
                features+=("Requerimiento MFA")
            fi
            
            if [[ "$vault_policy" =~ "SourceIp" ]]; then
                security_score=$((security_score + 5))
                features+=("Restricción por IP")
            fi
            
            if [[ "$vault_policy" =~ "DateGreaterThan\|DateLessThan" ]]; then
                security_score=$((security_score + 5))
                features+=("Restricción temporal")
            fi
        else
            issues+=("Política sin controles restrictivos")
        fi
    else
        issues+=("Sin política de acceso configurada")
        VAULTS_WITHOUT_POLICIES=$((VAULTS_WITHOUT_POLICIES + 1))
    fi
    
    # Verificar notificaciones (15 puntos)
    local notifications=$(aws backup get-backup-vault-notifications \
        --backup-vault-name "$vault_name" \
        --profile "$PROFILE" \
        --region "$region" \
        --query '[SNSTopicArn,BackupVaultEvents]' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$notifications" ] && [ "$notifications" != "None" ]; then
        security_score=$((security_score + 15))
        features+=("Notificaciones configuradas")
        VAULTS_WITH_NOTIFICATIONS=$((VAULTS_WITH_NOTIFICATIONS + 1))
    else
        issues+=("Sin notificaciones configuradas")
    fi
    
    # Verificar tags (10 puntos)
    local tags=$(aws backup list-tags \
        --resource-arn "$vault_arn" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Tags)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$tags" ] && [ "$tags" -gt 0 ]; then
        security_score=$((security_score + 10))
        features+=("$tags tags configurados")
    else
        issues+=("Sin tags de gestión")
    fi
    
    # Verificar recovery points (10 puntos)
    if [ -n "$recovery_points" ] && [ "$recovery_points" -gt 0 ]; then
        security_score=$((security_score + 10))
        features+=("$recovery_points recovery points")
    else
        issues+=("Sin recovery points disponibles")
    fi
    
    # Verificar antigüedad del vault (5 puntos bonus)
    if [ -n "$creation_date" ]; then
        local vault_age_days=$(( ($(date +%s) - $(date -d "$creation_date" +%s)) / 86400 ))
        if [ "$vault_age_days" -gt 30 ]; then
            security_score=$((security_score + 5))
            features+=("Vault maduro ($vault_age_days días)")
        fi
    fi
    
    # Determinar nivel de seguridad
    local security_level
    local security_color
    
    if [ $security_score -ge 80 ]; then
        security_level="EXCELENTE"
        security_color="$GREEN"
        HIGH_SECURITY_VAULTS=$((HIGH_SECURITY_VAULTS + 1))
    elif [ $security_score -ge 65 ]; then
        security_level="BUENA"
        security_color="$GREEN"
    elif [ $security_score -ge 50 ]; then
        security_level="MEDIA"
        security_color="$YELLOW"
    elif [ $security_score -ge 30 ]; then
        security_level="BAJA"
        security_color="$YELLOW"
    else
        security_level="CRÍTICA"
        security_color="$RED"
        SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
    fi
    
    # Verificar violaciones específicas de seguridad
    if [[ "$vault_policy" =~ '"Principal":"*"' ]] && [[ ! "$vault_policy" =~ "Deny" ]]; then
        issues+=("Posible acceso público sin restricciones")
        SECURITY_VIOLATIONS=$((SECURITY_VIOLATIONS + 1))
    fi
    
    echo "$security_score|$security_level|$security_color|${issues[*]}|${features[*]}|$vault_arn|$encryption_key|$recovery_points"
}

# Función para verificar compliance específico
check_compliance_requirements() {
    local vault_name="$1"
    local region="$2"
    local compliance_score=0
    local compliance_issues=()
    
    # Verificar política de acceso para compliance
    local vault_policy=$(aws backup get-backup-vault-access-policy \
        --backup-vault-name "$vault_name" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'Policy' \
        --output text 2>/dev/null)
    
    if [ -n "$vault_policy" ] && [ "$vault_policy" != "None" ]; then
        # Verificar controles requeridos para compliance
        
        # 1. Control de eliminación
        if [[ "$vault_policy" =~ "DeleteBackupVault\|DeleteRecoveryPoint" ]] && [[ "$vault_policy" =~ "Deny" ]]; then
            compliance_score=$((compliance_score + 25))
        else
            compliance_issues+=("Falta protección contra eliminación")
        fi
        
        # 2. Requerimiento de MFA
        if [[ "$vault_policy" =~ "MultiFactorAuth" ]]; then
            compliance_score=$((compliance_score + 25))
        else
            compliance_issues+=("Sin requerimiento MFA")
        fi
        
        # 3. Restricción temporal
        if [[ "$vault_policy" =~ "DateGreaterThan\|DateLessThan" ]]; then
            compliance_score=$((compliance_score + 20))
        else
            compliance_issues+=("Sin restricción temporal")
        fi
        
        # 4. Restricción de IP
        if [[ "$vault_policy" =~ "SourceIp" ]]; then
            compliance_score=$((compliance_score + 15))
        else
            compliance_issues+=("Sin restricción por IP")
        fi
        
        # 5. Control de cifrado
        if [[ "$vault_policy" =~ "EncryptionEnabled" ]]; then
            compliance_score=$((compliance_score + 15))
        else
            compliance_issues+=("Sin control de cifrado obligatorio")
        fi
    else
        compliance_issues+=("Sin política de acceso")
    fi
    
    echo "$compliance_score|${compliance_issues[*]}"
}

# Procesar cada región
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Analizando región: $CURRENT_REGION ===${NC}"
    
    # Obtener backup vaults
    BACKUP_VAULTS=$(aws backup describe-backup-vaults \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'BackupVaultList[].BackupVaultName' \
        --output text 2>/dev/null)
    
    if [ -z "$BACKUP_VAULTS" ]; then
        echo -e "${BLUE}ℹ️ Sin backup vaults en región $CURRENT_REGION${NC}"
        continue
    fi
    
    for vault_name in $BACKUP_VAULTS; do
        if [ -n "$vault_name" ]; then
            TOTAL_VAULTS=$((TOTAL_VAULTS + 1))
            
            echo -e "${CYAN}🗄️ Vault: $vault_name${NC}"
            
            # Evaluar seguridad del vault
            SECURITY_RESULT=$(evaluate_vault_security "$vault_name" "$CURRENT_REGION")
            
            # Parsear resultado
            IFS='|' read -r score level color issues features vault_arn encryption_key recovery_points <<< "$SECURITY_RESULT"
            
            # Mostrar información básica
            echo -e "   🌐 ARN: ${BLUE}$vault_arn${NC}"
            
            if [ -n "$encryption_key" ] && [ "$encryption_key" != "None" ]; then
                echo -e "   🔐 Cifrado: ${GREEN}HABILITADO${NC}"
                echo -e "   🔑 KMS Key: ${BLUE}$encryption_key${NC}"
            else
                echo -e "   ❌ Cifrado: ${RED}NO CONFIGURADO${NC}"
            fi
            
            echo -e "   📊 Recovery Points: ${BLUE}$recovery_points${NC}"
            
            # Mostrar puntuación de seguridad
            echo -e "   🔐 Seguridad: ${color}$level ($score/100)${NC}"
            
            # Mostrar características de seguridad
            if [ -n "$features" ] && [ "$features" != " " ]; then
                echo -e "   ✅ Características:"
                IFS=' ' read -ra FEATURE_ARRAY <<< "$features"
                for feature in "${FEATURE_ARRAY[@]}"; do
                    if [ -n "$feature" ]; then
                        echo -e "      🛡️ $feature"
                    fi
                done
            fi
            
            # Mostrar problemas detectados
            if [ -n "$issues" ] && [ "$issues" != " " ]; then
                echo -e "   ⚠️ Problemas detectados:"
                IFS=' ' read -ra ISSUE_ARRAY <<< "$issues"
                for issue in "${ISSUE_ARRAY[@]}"; do
                    if [ -n "$issue" ]; then
                        echo -e "      🚨 $issue"
                    fi
                done
            fi
            
            # Verificar compliance específico
            COMPLIANCE_RESULT=$(check_compliance_requirements "$vault_name" "$CURRENT_REGION")
            IFS='|' read -r compliance_score compliance_issues <<< "$COMPLIANCE_RESULT"
            
            echo -e "   📋 Compliance: ${BLUE}$compliance_score/100${NC}"
            
            if [ -n "$compliance_issues" ] && [ "$compliance_issues" != " " ]; then
                echo -e "   📌 Gaps de compliance:"
                IFS=' ' read -ra COMPLIANCE_ARRAY <<< "$compliance_issues"
                for gap in "${COMPLIANCE_ARRAY[@]}"; do
                    if [ -n "$gap" ]; then
                        echo -e "      📋 $gap"
                    fi
                done
            fi
            
            # Verificar jobs de backup recientes
            RECENT_JOBS=$(aws backup list-backup-jobs \
                --by-backup-vault-name "$vault_name" \
                --max-results 5 \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'BackupJobs[?CreationDate>=`'$(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ)'`].[State,CreationDate,ResourceType]' \
                --output text 2>/dev/null)
            
            if [ -n "$RECENT_JOBS" ]; then
                JOB_COUNT=$(echo "$RECENT_JOBS" | wc -l)
                echo -e "   📅 Jobs recientes (7 días): ${GREEN}$JOB_COUNT${NC}"
                
                # Mostrar estados de jobs
                echo "$RECENT_JOBS" | head -3 | while read state date resource_type; do
                    if [ -n "$state" ]; then
                        case $state in
                            COMPLETED)
                                echo -e "      ✅ ${GREEN}$state${NC} - $resource_type ($date)"
                                ;;
                            FAILED|ABORTED)
                                echo -e "      ❌ ${RED}$state${NC} - $resource_type ($date)"
                                ;;
                            *)
                                echo -e "      🔄 ${YELLOW}$state${NC} - $resource_type ($date)"
                                ;;
                        esac
                    fi
                done
            else
                echo -e "   📅 Jobs recientes: ${YELLOW}Ninguno (últimos 7 días)${NC}"
            fi
            
            echo ""
        fi
    done
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION completada${NC}"
    echo ""
done

# Verificar configuración de AWS Backup a nivel de cuenta
echo -e "${PURPLE}=== Verificando Configuración Global AWS Backup ===${NC}"

# Verificar configuración de backup por defecto
echo -e "${CYAN}🔍 Verificando configuración global...${NC}"

BACKUP_PLAN_COUNT=$(aws backup list-backup-plans \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'length(BackupPlansList)' \
    --output text 2>/dev/null)

if [ -n "$BACKUP_PLAN_COUNT" ] && [ "$BACKUP_PLAN_COUNT" -gt 0 ]; then
    echo -e "   ✅ Backup plans configurados: ${GREEN}$BACKUP_PLAN_COUNT${NC}"
else
    echo -e "   ⚠️ Sin backup plans configurados"
fi

# Verificar roles IAM para backup
IAM_ROLES=$(aws iam list-roles \
    --profile "$PROFILE" \
    --query 'Roles[?contains(RoleName, `Backup`) || contains(RoleName, `backup`)].RoleName' \
    --output text 2>/dev/null)

if [ -n "$IAM_ROLES" ]; then
    ROLE_COUNT=$(echo "$IAM_ROLES" | wc -w)
    echo -e "   ✅ Roles IAM para backup: ${GREEN}$ROLE_COUNT${NC}"
    
    for role in $IAM_ROLES; do
        echo -e "      📋 $role"
    done
else
    echo -e "   ⚠️ Sin roles IAM específicos para backup"
fi

# Generar reporte de verificación
REPORT_FILE="backup-vault-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$REPORT_FILE" << EOF
{
    "verification_report": {
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
        "profile": "$PROFILE",
        "account_id": "$ACCOUNT_ID",
        "regions_analyzed": [$(printf '"%s",' "${ACTIVE_REGIONS[@]}" | sed 's/,$//')]
    },
    "vault_summary": {
        "total_vaults": $TOTAL_VAULTS,
        "vaults_with_policies": $VAULTS_WITH_POLICIES,
        "vaults_without_policies": $VAULTS_WITHOUT_POLICIES,
        "vaults_with_encryption": $VAULTS_WITH_ENCRYPTION,
        "vaults_with_notifications": $VAULTS_WITH_NOTIFICATIONS,
        "high_security_vaults": $HIGH_SECURITY_VAULTS,
        "policy_coverage_percentage": $((TOTAL_VAULTS > 0 ? VAULTS_WITH_POLICIES * 100 / TOTAL_VAULTS : 0))
    },
    "security_metrics": {
        "security_violations": $SECURITY_VIOLATIONS,
        "encryption_coverage": $((TOTAL_VAULTS > 0 ? VAULTS_WITH_ENCRYPTION * 100 / TOTAL_VAULTS : 0)),
        "notification_coverage": $((TOTAL_VAULTS > 0 ? VAULTS_WITH_NOTIFICATIONS * 100 / TOTAL_VAULTS : 0))
    },
    "compliance_status": {
        "fully_secured": $((VAULTS_WITHOUT_POLICIES == 0 && SECURITY_VIOLATIONS == 0)),
        "recommendation": "$([ $VAULTS_WITHOUT_POLICIES -eq 0 ] && [ $SECURITY_VIOLATIONS -eq 0 ] && echo "Compliant" || echo "Requires policy implementation")"
    }
}
EOF

echo -e "✅ Reporte JSON generado: ${GREEN}$REPORT_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN BACKUP VAULT POLICIES ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔍 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones analizadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC}"
echo -e "🗄️ Total backup vaults: ${GREEN}$TOTAL_VAULTS${NC}"

if [ $TOTAL_VAULTS -gt 0 ]; then
    POLICY_PERCENT=$((VAULTS_WITH_POLICIES * 100 / TOTAL_VAULTS))
    ENCRYPTION_PERCENT=$((VAULTS_WITH_ENCRYPTION * 100 / TOTAL_VAULTS))
    NOTIFICATION_PERCENT=$((VAULTS_WITH_NOTIFICATIONS * 100 / TOTAL_VAULTS))
    
    echo ""
    echo -e "🛡️ Vaults con políticas: ${GREEN}$VAULTS_WITH_POLICIES${NC} (${GREEN}$POLICY_PERCENT%${NC})"
    echo -e "❌ Sin políticas: ${RED}$VAULTS_WITHOUT_POLICIES${NC}"
    echo -e "🔐 Con cifrado KMS: ${GREEN}$VAULTS_WITH_ENCRYPTION${NC} (${GREEN}$ENCRYPTION_PERCENT%${NC})"
    echo -e "📢 Con notificaciones: ${GREEN}$VAULTS_WITH_NOTIFICATIONS${NC} (${GREEN}$NOTIFICATION_PERCENT%${NC})"
    echo -e "⭐ Alta seguridad: ${GREEN}$HIGH_SECURITY_VAULTS${NC}"
    
    if [ $SECURITY_VIOLATIONS -gt 0 ]; then
        echo -e "⚠️ Violaciones de seguridad: ${YELLOW}$SECURITY_VIOLATIONS${NC}"
    fi
    
    echo ""
    
    # Estado de cumplimiento
    if [ $VAULTS_WITHOUT_POLICIES -eq 0 ] && [ $SECURITY_VIOLATIONS -eq 0 ]; then
        echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE SEGURO${NC}"
        echo -e "${BLUE}💡 Todos los backup vaults implementan políticas restrictivas${NC}"
    else
        echo -e "${YELLOW}⚠️ ESTADO: SEGURIDAD PARCIAL${NC}"
        if [ $VAULTS_WITHOUT_POLICIES -gt 0 ]; then
            echo -e "${YELLOW}💡 $VAULTS_WITHOUT_POLICIES vaults requieren políticas${NC}"
        fi
        if [ $SECURITY_VIOLATIONS -gt 0 ]; then
            echo -e "${RED}💡 $SECURITY_VIOLATIONS vaults con problemas críticos${NC}"
        fi
    fi
else
    echo -e "${BLUE}ℹ️ ESTADO: SIN BACKUP VAULTS${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$REPORT_FILE${NC}"
echo ""

# Comandos sugeridos para remediar problemas
if [ $VAULTS_WITHOUT_POLICIES -gt 0 ] || [ $SECURITY_VIOLATIONS -gt 0 ]; then
    echo -e "${YELLOW}🔧 COMANDOS DE REMEDIACIÓN:${NC}"
    echo -e "Para configurar políticas en vaults desprotegidos:"
    echo -e "${CYAN}./limit-backup-vault-access.sh $PROFILE${NC}"
    echo ""
fi