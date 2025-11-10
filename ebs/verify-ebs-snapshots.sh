#!/bin/bash
# verify-ebs-snapshots.sh
# Verificar y auditar snapshots EBS
# Genera reportes detallados de compliance y backup

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
echo -e "${BLUE}🔍 VERIFICACIÓN SNAPSHOTS EBS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región Principal: ${GREEN}$REGION${NC}"
echo "Auditando configuración de snapshots y políticas de backup"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔧 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
AWS_VERSION=$(aws --version 2>/dev/null | head -1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: AWS CLI no encontrado${NC}"
    exit 1
fi
echo -e "✅ AWS CLI: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"

# Variables de auditoría
TOTAL_VOLUMES=0
TOTAL_SNAPSHOTS=0
VOLUMES_WITH_SNAPSHOTS=0
VOLUMES_WITHOUT_SNAPSHOTS=0
RECENT_SNAPSHOTS=0
OLD_SNAPSHOTS=0
ENCRYPTED_SNAPSHOTS=0
UNENCRYPTED_SNAPSHOTS=0
AUTOMATED_SNAPSHOTS=0
MANUAL_SNAPSHOTS=0
BACKUP_COMPLIANCE_SCORE=0
REGIONS_SCANNED=0
TOTAL_SNAPSHOT_SIZE_GB=0

# Verificar regiones con recursos
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Escaneando regiones...${NC}"
for region in "${REGIONS[@]}"; do
    VOLUME_COUNT=$(aws ec2 describe-volumes \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Volumes[?State!=`deleted`])' \
        --output text 2>/dev/null)
    
    SNAPSHOT_COUNT=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Snapshots)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && ([ -n "$VOLUME_COUNT" ] && [ "$VOLUME_COUNT" -gt 0 ] || [ -n "$SNAPSHOT_COUNT" ] && [ "$SNAPSHOT_COUNT" -gt 0 ]); then
        echo -e "✅ Región ${GREEN}$region${NC}: ${VOLUME_COUNT:-0} volúmenes, ${SNAPSHOT_COUNT:-0} snapshots"
        ACTIVE_REGIONS+=("$region")
        REGIONS_SCANNED=$((REGIONS_SCANNED + 1))
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin recursos EBS"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron recursos EBS en ninguna región${NC}"
    echo -e "${BLUE}💡 Compliance: 100% (Sin recursos que auditar)${NC}"
    exit 0
fi

echo ""

# Crear archivo de reporte JSON
REPORT_FILE="ebs-snapshots-audit-$PROFILE-$(date +%Y%m%d-%H%M%S).json"
SUMMARY_FILE="ebs-snapshots-summary-$PROFILE-$(date +%Y%m%d-%H%M%S).md"

# Inicializar reporte JSON
cat > "$REPORT_FILE" << EOF
{
  "audit": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "profile": "$PROFILE",
    "account_id": "$ACCOUNT_ID",
    "audit_type": "EBS_SNAPSHOTS_AUDIT",
    "regions_scanned": $REGIONS_SCANNED,
    "active_regions": [$(printf '"%s",' "${ACTIVE_REGIONS[@]}" | sed 's/,$//')],
    "summary": {
      "total_volumes": 0,
      "total_snapshots": 0,
      "volumes_with_snapshots": 0,
      "volumes_without_snapshots": 0,
      "recent_snapshots": 0,
      "backup_compliance_score": 0
    },
    "volumes": [],
    "snapshots": [],
    "recommendations": []
  }
}
EOF

# Función para evaluar compliance de backup por volumen
evaluate_backup_compliance() {
    local volume_id="$1"
    local region="$2"
    
    local compliance_score=0
    local issues=()
    local recommendations=()
    
    # Verificar snapshots recientes (últimas 24 horas)
    local recent_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=volume-id,Values=$volume_id" \
                  "Name=start-time,Values=$(date -d '1 day ago' +%Y-%m-%d)*" \
        --query 'length(Snapshots)' \
        --output text 2>/dev/null)
    
    if [ "${recent_snapshots:-0}" -gt 0 ]; then
        compliance_score=$((compliance_score + 30))
    else
        issues+=("Sin snapshots recientes (24h)")
        recommendations+=("Crear snapshot inmediato")
    fi
    
    # Verificar snapshots en última semana
    local weekly_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=volume-id,Values=$volume_id" \
                  "Name=start-time,Values=$(date -d '7 days ago' +%Y-%m-%d)*" \
        --query 'length(Snapshots)' \
        --output text 2>/dev/null)
    
    if [ "${weekly_snapshots:-0}" -gt 0 ]; then
        compliance_score=$((compliance_score + 20))
    else
        issues+=("Sin snapshots semanales")
        recommendations+=("Establecer política de backup semanal")
    fi
    
    # Verificar total de snapshots históricos
    local total_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=volume-id,Values=$volume_id" \
        --query 'length(Snapshots)' \
        --output text 2>/dev/null)
    
    if [ "${total_snapshots:-0}" -ge 5 ]; then
        compliance_score=$((compliance_score + 20))
    elif [ "${total_snapshots:-0}" -gt 0 ]; then
        compliance_score=$((compliance_score + 10))
        recommendations+=("Aumentar frecuencia de snapshots")
    else
        issues+=("Sin snapshots históricos")
        recommendations+=("Implementar estrategia de backup")
    fi
    
    # Verificar automatización (tags de automatización)
    local automated_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=volume-id,Values=$volume_id" \
                  "Name=tag:AutomatedBackup,Values=true" \
        --query 'length(Snapshots)' \
        --output text 2>/dev/null)
    
    if [ "${automated_snapshots:-0}" -gt 0 ]; then
        compliance_score=$((compliance_score + 15))
    else
        issues+=("Sin automatización de backup")
        recommendations+=("Configurar DLM o scripts automáticos")
    fi
    
    # Verificar cifrado de snapshots
    local encrypted_snapshots=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=volume-id,Values=$volume_id" \
                  "Name=encrypted,Values=true" \
        --query 'length(Snapshots)' \
        --output text 2>/dev/null)
    
    if [ "${encrypted_snapshots:-0}" -eq "${total_snapshots:-0}" ] && [ "${total_snapshots:-0}" -gt 0 ]; then
        compliance_score=$((compliance_score + 15))
    elif [ "${encrypted_snapshots:-0}" -gt 0 ]; then
        compliance_score=$((compliance_score + 5))
        issues+=("Algunos snapshots sin cifrar")
        recommendations+=("Cifrar todos los snapshots futuros")
    else
        issues+=("Snapshots sin cifrar")
        recommendations+=("Implementar cifrado de snapshots")
    fi
    
    # Determinar nivel de compliance
    if [ $compliance_score -ge 85 ]; then
        echo "EXCELLENT|$compliance_score|${issues[*]}|${recommendations[*]}|$recent_snapshots|$weekly_snapshots|$total_snapshots"
    elif [ $compliance_score -ge 70 ]; then
        echo "GOOD|$compliance_score|${issues[*]}|${recommendations[*]}|$recent_snapshots|$weekly_snapshots|$total_snapshots"
    elif [ $compliance_score -ge 50 ]; then
        echo "AVERAGE|$compliance_score|${issues[*]}|${recommendations[*]}|$recent_snapshots|$weekly_snapshots|$total_snapshots"
    elif [ $compliance_score -ge 30 ]; then
        echo "POOR|$compliance_score|${issues[*]}|${recommendations[*]}|$recent_snapshots|$weekly_snapshots|$total_snapshots"
    else
        echo "CRITICAL|$compliance_score|${issues[*]}|${recommendations[*]}|$recent_snapshots|$weekly_snapshots|$total_snapshots"
    fi
}

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Auditando región: $CURRENT_REGION ===${NC}"
    
    # Obtener volúmenes EBS
    VOLUMES_DATA=$(aws ec2 describe-volumes \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --filters "Name=state,Values=in-use,available" \
        --query 'Volumes[].[VolumeId,VolumeType,Size,Encrypted,State,Tags[?Key==`Name`].Value|[0],CreateTime,Attachments[0].InstanceId]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener volúmenes en región $CURRENT_REGION${NC}"
        continue
    fi
    
    if [ -z "$VOLUMES_DATA" ]; then
        echo -e "${BLUE}ℹ️ Sin volúmenes EBS activos en región $CURRENT_REGION${NC}"
    else
        echo -e "${GREEN}📊 Analizando volúmenes EBS en $CURRENT_REGION...${NC}"
        
        while IFS=$'\t' read -r volume_id volume_type size encrypted state volume_name create_time instance_id; do
            if [ -n "$volume_id" ]; then
                TOTAL_VOLUMES=$((TOTAL_VOLUMES + 1))
                
                # Normalizar nombre
                if [ -z "$volume_name" ] || [ "$volume_name" = "None" ]; then
                    volume_name="$volume_id"
                fi
                
                # Normalizar valores
                [ "$instance_id" = "None" ] && instance_id=""
                
                echo -e "${CYAN}💾 Analizando volumen: $volume_name${NC}"
                echo -e "   🆔 ID: ${BLUE}$volume_id${NC}"
                echo -e "   📦 Tipo: ${BLUE}$volume_type${NC}"
                echo -e "   📏 Tamaño: ${BLUE}${size}GB${NC}"
                echo -e "   🔐 Cifrado: $([ "$encrypted" = "True" ] && echo -e "${GREEN}SÍ${NC}" || echo -e "${YELLOW}NO${NC}")"
                echo -e "   🔄 Estado: ${BLUE}$state${NC}"
                
                if [ -n "$instance_id" ]; then
                    echo -e "   🖥️ Instancia: ${BLUE}$instance_id${NC}"
                else
                    echo -e "   🖥️ Instancia: ${YELLOW}No adjunto${NC}"
                fi
                
                if [ -n "$create_time" ] && [ "$create_time" != "None" ]; then
                    local create_date=$(date -d "$create_time" +%Y-%m-%d 2>/dev/null)
                    if [ -n "$create_date" ]; then
                        echo -e "   📅 Creado: ${BLUE}$create_date${NC}"
                    fi
                fi
                
                # Evaluar compliance de backup
                COMPLIANCE_RESULT=$(evaluate_backup_compliance "$volume_id" "$CURRENT_REGION")
                IFS='|' read -r compliance_level compliance_score issues recommendations recent_count weekly_count total_count <<< "$COMPLIANCE_RESULT"
                
                # Actualizar contadores globales
                if [ "${total_count:-0}" -gt 0 ]; then
                    VOLUMES_WITH_SNAPSHOTS=$((VOLUMES_WITH_SNAPSHOTS + 1))
                else
                    VOLUMES_WITHOUT_SNAPSHOTS=$((VOLUMES_WITHOUT_SNAPSHOTS + 1))
                fi
                
                RECENT_SNAPSHOTS=$((RECENT_SNAPSHOTS + ${recent_count:-0}))
                
                # Mostrar compliance
                case "$compliance_level" in
                    EXCELLENT)
                        echo -e "   🏆 Backup Compliance: ${GREEN}EXCELENTE ($compliance_score/100)${NC}"
                        ;;
                    GOOD)
                        echo -e "   ✅ Backup Compliance: ${GREEN}BUENO ($compliance_score/100)${NC}"
                        ;;
                    AVERAGE)
                        echo -e "   ⚠️ Backup Compliance: ${YELLOW}PROMEDIO ($compliance_score/100)${NC}"
                        ;;
                    POOR)
                        echo -e "   ❌ Backup Compliance: ${RED}DEFICIENTE ($compliance_score/100)${NC}"
                        ;;
                    CRITICAL)
                        echo -e "   🚨 Backup Compliance: ${RED}CRÍTICO ($compliance_score/100)${NC}"
                        ;;
                esac
                
                echo -e "   📷 Snapshots: Recientes: ${GREEN}${recent_count:-0}${NC} | Semanales: ${BLUE}${weekly_count:-0}${NC} | Total: ${BLUE}${total_count:-0}${NC}"
                
                if [ -n "$issues" ] && [ "$issues" != " " ]; then
                    echo -e "   ⚠️ Issues: ${YELLOW}$issues${NC}"
                fi
                
                if [ -n "$recommendations" ] && [ "$recommendations" != " " ]; then
                    echo -e "   💡 Recomendaciones: ${CYAN}$recommendations${NC}"
                fi
                
                # Agregar al reporte JSON
                local volume_json=$(cat << EOF
{
  "volume_id": "$volume_id",
  "volume_name": "$volume_name",
  "volume_type": "$volume_type",
  "size_gb": $size,
  "encrypted": $([ "$encrypted" = "True" ] && echo "true" || echo "false"),
  "state": "$state",
  "region": "$CURRENT_REGION",
  "instance_id": "$instance_id",
  "create_time": "$create_time",
  "backup_compliance": {
    "level": "$compliance_level",
    "score": $compliance_score,
    "recent_snapshots": ${recent_count:-0},
    "weekly_snapshots": ${weekly_count:-0},
    "total_snapshots": ${total_count:-0},
    "issues": "$issues",
    "recommendations": "$recommendations"
  }
}
EOF
)
                
                # Añadir volumen al reporte
                local temp_file=$(mktemp)
                jq --argjson volume "$volume_json" '.audit.volumes += [$volume]' "$REPORT_FILE" > "$temp_file"
                mv "$temp_file" "$REPORT_FILE"
                
                echo ""
            fi
        done <<< "$VOLUMES_DATA"
    fi
    
    # Obtener información de snapshots en la región
    echo -e "${GREEN}📷 Analizando snapshots en $CURRENT_REGION...${NC}"
    
    SNAPSHOTS_DATA=$(aws ec2 describe-snapshots \
        --owner-ids "$ACCOUNT_ID" \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'Snapshots[].[SnapshotId,VolumeId,VolumeSize,Encrypted,State,Progress,StartTime,Description,Tags[?Key==`AutomatedBackup`].Value|[0]]' \
        --output text 2>/dev/null)
    
    if [ -n "$SNAPSHOTS_DATA" ]; then
        local region_snapshots=0
        local region_size=0
        
        while IFS=$'\t' read -r snapshot_id volume_id volume_size encrypted state progress start_time description automated; do
            if [ -n "$snapshot_id" ]; then
                region_snapshots=$((region_snapshots + 1))
                region_size=$((region_size + volume_size))
                
                # Contadores globales
                TOTAL_SNAPSHOTS=$((TOTAL_SNAPSHOTS + 1))
                TOTAL_SNAPSHOT_SIZE_GB=$((TOTAL_SNAPSHOT_SIZE_GB + volume_size))
                
                if [ "$encrypted" = "True" ]; then
                    ENCRYPTED_SNAPSHOTS=$((ENCRYPTED_SNAPSHOTS + 1))
                else
                    UNENCRYPTED_SNAPSHOTS=$((UNENCRYPTED_SNAPSHOTS + 1))
                fi
                
                if [ "$automated" = "true" ]; then
                    AUTOMATED_SNAPSHOTS=$((AUTOMATED_SNAPSHOTS + 1))
                else
                    MANUAL_SNAPSHOTS=$((MANUAL_SNAPSHOTS + 1))
                fi
                
                # Verificar si es snapshot reciente (últimas 48 horas)
                if [ -n "$start_time" ]; then
                    local snapshot_date=$(date -d "$start_time" +%s 2>/dev/null)
                    local cutoff_date=$(date -d "2 days ago" +%s 2>/dev/null)
                    
                    if [ -n "$snapshot_date" ] && [ -n "$cutoff_date" ] && [ "$snapshot_date" -gt "$cutoff_date" ]; then
                        # Es snapshot reciente, ya contabilizado arriba
                        :
                    else
                        OLD_SNAPSHOTS=$((OLD_SNAPSHOTS + 1))
                    fi
                fi
                
                # Agregar snapshot al reporte JSON
                local snapshot_json=$(cat << EOF
{
  "snapshot_id": "$snapshot_id",
  "volume_id": "$volume_id",
  "volume_size_gb": $volume_size,
  "encrypted": $([ "$encrypted" = "True" ] && echo "true" || echo "false"),
  "state": "$state",
  "progress": "$progress",
  "start_time": "$start_time",
  "description": "$description",
  "automated": $([ "$automated" = "true" ] && echo "true" || echo "false"),
  "region": "$CURRENT_REGION"
}
EOF
)
                
                # Añadir snapshot al reporte
                local temp_file=$(mktemp)
                jq --argjson snapshot "$snapshot_json" '.audit.snapshots += [$snapshot]' "$REPORT_FILE" > "$temp_file"
                mv "$temp_file" "$REPORT_FILE"
            fi
        done <<< "$SNAPSHOTS_DATA"
        
        echo -e "   📊 Snapshots en región: ${BLUE}$region_snapshots${NC}"
        echo -e "   💾 Tamaño total: ${BLUE}${region_size}GB${NC}"
    else
        echo -e "   ℹ️ Sin snapshots en región $CURRENT_REGION"
    fi
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION auditada${NC}"
    echo ""
done

# Calcular puntuación de compliance global
if [ $TOTAL_VOLUMES -gt 0 ]; then
    # Porcentaje de volúmenes con snapshots
    VOLUMES_WITH_BACKUP_PERCENT=$((VOLUMES_WITH_SNAPSHOTS * 100 / TOTAL_VOLUMES))
    
    # Base de puntuación
    BACKUP_COMPLIANCE_SCORE=$VOLUMES_WITH_BACKUP_PERCENT
    
    # Bonificaciones por snapshots recientes
    if [ $RECENT_SNAPSHOTS -gt 0 ]; then
        RECENT_BONUS=$((RECENT_SNAPSHOTS * 2))
        if [ $RECENT_BONUS -gt 20 ]; then
            RECENT_BONUS=20
        fi
        BACKUP_COMPLIANCE_SCORE=$((BACKUP_COMPLIANCE_SCORE + RECENT_BONUS))
    fi
    
    # Bonificaciones por automatización
    if [ $AUTOMATED_SNAPSHOTS -gt 0 ] && [ $TOTAL_SNAPSHOTS -gt 0 ]; then
        AUTOMATION_PERCENT=$((AUTOMATED_SNAPSHOTS * 100 / TOTAL_SNAPSHOTS))
        AUTOMATION_BONUS=$((AUTOMATION_PERCENT / 10))
        BACKUP_COMPLIANCE_SCORE=$((BACKUP_COMPLIANCE_SCORE + AUTOMATION_BONUS))
    fi
    
    # Penalizaciones por volúmenes sin backup
    if [ $VOLUMES_WITHOUT_SNAPSHOTS -gt 0 ]; then
        NO_BACKUP_PENALTY=$((VOLUMES_WITHOUT_SNAPSHOTS * 10))
        BACKUP_COMPLIANCE_SCORE=$((BACKUP_COMPLIANCE_SCORE - NO_BACKUP_PENALTY))
    fi
    
    # Mantener en rango 0-100
    if [ $BACKUP_COMPLIANCE_SCORE -gt 100 ]; then
        BACKUP_COMPLIANCE_SCORE=100
    elif [ $BACKUP_COMPLIANCE_SCORE -lt 0 ]; then
        BACKUP_COMPLIANCE_SCORE=0
    fi
else
    BACKUP_COMPLIANCE_SCORE=100  # Sin volúmenes = compliance perfecto
fi

# Actualizar resumen en reporte JSON
jq --argjson total_vol "$TOTAL_VOLUMES" \
   --argjson total_snap "$TOTAL_SNAPSHOTS" \
   --argjson vol_with_snap "$VOLUMES_WITH_SNAPSHOTS" \
   --argjson vol_without_snap "$VOLUMES_WITHOUT_SNAPSHOTS" \
   --argjson recent_snap "$RECENT_SNAPSHOTS" \
   --argjson compliance "$BACKUP_COMPLIANCE_SCORE" \
   '.audit.summary.total_volumes = $total_vol |
    .audit.summary.total_snapshots = $total_snap |
    .audit.summary.volumes_with_snapshots = $vol_with_snap |
    .audit.summary.volumes_without_snapshots = $vol_without_snap |
    .audit.summary.recent_snapshots = $recent_snap |
    .audit.summary.backup_compliance_score = $compliance' "$REPORT_FILE" > "${REPORT_FILE}.tmp"
mv "${REPORT_FILE}.tmp" "$REPORT_FILE"

# Generar recomendaciones generales
RECOMMENDATIONS=()

if [ $VOLUMES_WITHOUT_SNAPSHOTS -gt 0 ]; then
    RECOMMENDATIONS+=("Implementar backup para $VOLUMES_WITHOUT_SNAPSHOTS volumen(es) sin snapshots")
fi

if [ $RECENT_SNAPSHOTS -eq 0 ] && [ $TOTAL_VOLUMES -gt 0 ]; then
    RECOMMENDATIONS+=("No hay snapshots recientes - ejecutar backup inmediato")
fi

if [ $AUTOMATED_SNAPSHOTS -eq 0 ] && [ $TOTAL_SNAPSHOTS -gt 0 ]; then
    RECOMMENDATIONS+=("Implementar automatización con DLM o scripts")
fi

if [ $UNENCRYPTED_SNAPSHOTS -gt 0 ]; then
    RECOMMENDATIONS+=("Configurar cifrado para futuros snapshots")
fi

if [ ${#RECOMMENDATIONS[@]} -eq 0 ]; then
    RECOMMENDATIONS+=("Excelente: Estrategia de backup bien configurada")
fi

# Agregar recomendaciones al JSON
for rec in "${RECOMMENDATIONS[@]}"; do
    jq --arg rec "$rec" '.audit.recommendations += [$rec]' "$REPORT_FILE" > "${REPORT_FILE}.tmp"
    mv "${REPORT_FILE}.tmp" "$REPORT_FILE"
done

# Generar resumen ejecutivo
cat > "$SUMMARY_FILE" << EOF
# Auditoría EBS Snapshots - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones**: ${ACTIVE_REGIONS[*]}

## 📊 Resumen Ejecutivo

### Puntuación de Backup Compliance: **${BACKUP_COMPLIANCE_SCORE}/100**

### Métricas Principales
- **Total volúmenes EBS**: $TOTAL_VOLUMES
- **Total snapshots**: $TOTAL_SNAPSHOTS
- **Volúmenes con backup**: $VOLUMES_WITH_SNAPSHOTS ($((TOTAL_VOLUMES > 0 ? VOLUMES_WITH_SNAPSHOTS * 100 / TOTAL_VOLUMES : 0))%)
- **Volúmenes sin backup**: $VOLUMES_WITHOUT_SNAPSHOTS

### Distribución de Snapshots
- **Snapshots recientes (48h)**: $RECENT_SNAPSHOTS
- **Snapshots antiguos**: $OLD_SNAPSHOTS
- **Snapshots cifrados**: $ENCRYPTED_SNAPSHOTS
- **Snapshots sin cifrar**: $UNENCRYPTED_SNAPSHOTS
- **Snapshots automatizados**: $AUTOMATED_SNAPSHOTS
- **Snapshots manuales**: $MANUAL_SNAPSHOTS

## 🎯 Estado de Compliance

EOF

if [ $BACKUP_COMPLIANCE_SCORE -ge 90 ]; then
    echo "**🏆 EXCELENTE** - Estrategia de backup óptima" >> "$SUMMARY_FILE"
elif [ $BACKUP_COMPLIANCE_SCORE -ge 80 ]; then
    echo "**✅ BUENO** - Backup adecuado con mejoras menores" >> "$SUMMARY_FILE"
elif [ $BACKUP_COMPLIANCE_SCORE -ge 70 ]; then
    echo "**⚠️ PROMEDIO** - Requiere atención en backup crítico" >> "$SUMMARY_FILE"
elif [ $BACKUP_COMPLIANCE_SCORE -ge 50 ]; then
    echo "**❌ DEFICIENTE** - Riesgos significativos de pérdida de datos" >> "$SUMMARY_FILE"
else
    echo "**🚨 CRÍTICO** - Exposición grave a pérdida de datos" >> "$SUMMARY_FILE"
fi

cat >> "$SUMMARY_FILE" << EOF

## 🔍 Recomendaciones Prioritarias

EOF

for i in "${!RECOMMENDATIONS[@]}"; do
    echo "$((i+1)). ${RECOMMENDATIONS[i]}" >> "$SUMMARY_FILE"
done

cat >> "$SUMMARY_FILE" << EOF

## 💰 Análisis de Costos

- **Tamaño total snapshots**: ${TOTAL_SNAPSHOT_SIZE_GB}GB
- **Costo estimado mensual**: \$$(echo "scale=2; $TOTAL_SNAPSHOT_SIZE_GB * 0.05" | bc -l 2>/dev/null || echo "N/A")
- **Snapshots por volumen promedio**: $([ $TOTAL_VOLUMES -gt 0 ] && echo "scale=1; $TOTAL_SNAPSHOTS / $TOTAL_VOLUMES" | bc -l || echo "0")

## 📋 Comandos de Corrección

\`\`\`bash
# Crear snapshots para volúmenes sin backup
./create-ebs-snapshots.sh $PROFILE

# Verificar snapshots específicos
aws ec2 describe-snapshots --owner-ids $ACCOUNT_ID \\
    --filters "Name=volume-id,Values=VOLUME_ID" \\
    --profile $PROFILE --region REGION

# Configurar DLM para automatización
aws dlm create-lifecycle-policy \\
    --execution-role-arn arn:aws:iam::$ACCOUNT_ID:role/AWSDataLifecycleManagerDefaultRole \\
    --description "Automated EBS snapshots" \\
    --state ENABLED --profile $PROFILE --region REGION
\`\`\`

---
*Reporte generado automáticamente - $(date)*
EOF

echo -e "${PURPLE}=== REPORTE DE AUDITORÍA EBS SNAPSHOTS ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones auditadas: ${GREEN}$REGIONS_SCANNED${NC} (${ACTIVE_REGIONS[*]})"
echo -e "💾 Total volúmenes EBS: ${GREEN}$TOTAL_VOLUMES${NC}"
echo -e "📷 Total snapshots: ${GREEN}$TOTAL_SNAPSHOTS${NC}"
echo -e "✅ Volúmenes con backup: ${GREEN}$VOLUMES_WITH_SNAPSHOTS${NC} ($((TOTAL_VOLUMES > 0 ? VOLUMES_WITH_SNAPSHOTS * 100 / TOTAL_VOLUMES : 0))%)"
echo -e "⚠️ Sin backup: ${YELLOW}$VOLUMES_WITHOUT_SNAPSHOTS${NC}"
echo -e "📅 Snapshots recientes: ${GREEN}$RECENT_SNAPSHOTS${NC}"
echo -e "🔐 Snapshots cifrados: ${GREEN}$ENCRYPTED_SNAPSHOTS${NC}"
echo -e "🤖 Snapshots automatizados: ${GREEN}$AUTOMATED_SNAPSHOTS${NC}"

# Mostrar puntuación con colores
if [ $BACKUP_COMPLIANCE_SCORE -ge 90 ]; then
    echo -e "🏆 Compliance Backup: ${GREEN}$BACKUP_COMPLIANCE_SCORE/100 (EXCELENTE)${NC}"
elif [ $BACKUP_COMPLIANCE_SCORE -ge 80 ]; then
    echo -e "✅ Compliance Backup: ${GREEN}$BACKUP_COMPLIANCE_SCORE/100 (BUENO)${NC}"
elif [ $BACKUP_COMPLIANCE_SCORE -ge 70 ]; then
    echo -e "⚠️ Compliance Backup: ${YELLOW}$BACKUP_COMPLIANCE_SCORE/100 (PROMEDIO)${NC}"
elif [ $BACKUP_COMPLIANCE_SCORE -ge 50 ]; then
    echo -e "❌ Compliance Backup: ${RED}$BACKUP_COMPLIANCE_SCORE/100 (DEFICIENTE)${NC}"
else
    echo -e "🚨 Compliance Backup: ${RED}$BACKUP_COMPLIANCE_SCORE/100 (CRÍTICO)${NC}"
fi

echo ""
echo -e "📁 Reporte JSON: ${GREEN}$REPORT_FILE${NC}"
echo -e "📄 Resumen ejecutivo: ${GREEN}$SUMMARY_FILE${NC}"

# Estado final
echo ""
if [ $TOTAL_VOLUMES -eq 0 ]; then
    echo -e "${GREEN}✅ SIN VOLÚMENES EBS - COMPLIANCE: 100%${NC}"
elif [ $VOLUMES_WITHOUT_SNAPSHOTS -eq 0 ] && [ $RECENT_SNAPSHOTS -gt 0 ]; then
    echo -e "${GREEN}🎉 TODOS LOS VOLÚMENES TIENEN BACKUP RECIENTE${NC}"
elif [ $BACKUP_COMPLIANCE_SCORE -ge 80 ]; then
    echo -e "${GREEN}✅ COMPLIANCE DE BACKUP SATISFACTORIO${NC}"
    echo -e "${BLUE}💡 Considerar mejoras en automatización${NC}"
else
    echo -e "${YELLOW}⚠️ REQUIERE ATENCIÓN INMEDIATA EN BACKUP${NC}"
    echo -e "${RED}🚨 Volúmenes críticos sin protección de datos${NC}"
fi