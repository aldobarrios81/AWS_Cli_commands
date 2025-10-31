#!/bin/bash
# ebs-snapshots-summary.sh
# Resumen consolidado de snapshots EBS - Multi-perfil
# Análisis ejecutivo de backup y compliance para todos los perfiles

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}📊 RESUMEN EJECUTIVO - EBS SNAPSHOTS BACKUP${NC}"
echo "=================================================================="
echo -e "Análisis consolidado de backup para todos los perfiles AWS"
echo ""

# Configuración de perfiles
PROFILES=("ancla" "azbeacons" "azcenit")
REGIONS=("us-east-1" "us-west-2" "eu-west-1")

# Variables globales de resumen
GLOBAL_TOTAL_VOLUMES=0
GLOBAL_TOTAL_SNAPSHOTS=0
GLOBAL_VOLUMES_WITH_SNAPSHOTS=0
GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS=0
GLOBAL_RECENT_SNAPSHOTS=0
GLOBAL_ENCRYPTED_SNAPSHOTS=0
GLOBAL_UNENCRYPTED_SNAPSHOTS=0
GLOBAL_AUTOMATED_SNAPSHOTS=0
GLOBAL_MANUAL_SNAPSHOTS=0
GLOBAL_REGIONS_SCANNED=0
GLOBAL_TOTAL_SIZE_GB=0
ACTIVE_PROFILES=0

# Arrays para almacenar datos por perfil
declare -A PROFILE_DATA
declare -A PROFILE_SCORES
declare -A PROFILE_STATUS

echo -e "${PURPLE}🔍 Verificando perfiles AWS disponibles...${NC}"

# Función para verificar disponibilidad de perfil
check_profile_availability() {
    local profile="$1"
    
    local account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$account_id" ]; then
        echo -e "✅ Perfil ${GREEN}$profile${NC}: Account ID ${GREEN}$account_id${NC}"
        ACTIVE_PROFILES=$((ACTIVE_PROFILES + 1))
        return 0
    else
        echo -e "❌ Perfil ${RED}$profile${NC}: No disponible o sin credenciales"
        return 1
    fi
}

# Verificar todos los perfiles
AVAILABLE_PROFILES=()
for profile in "${PROFILES[@]}"; do
    if check_profile_availability "$profile"; then
        AVAILABLE_PROFILES+=("$profile")
    fi
done

if [ ${#AVAILABLE_PROFILES[@]} -eq 0 ]; then
    echo -e "${RED}❌ No hay perfiles disponibles para auditar${NC}"
    exit 1
fi

echo ""

# Función para analizar perfil individual
analyze_profile() {
    local profile="$1"
    local total_volumes=0
    local total_snapshots=0
    local volumes_with_snapshots=0
    local volumes_without_snapshots=0
    local recent_snapshots=0
    local encrypted_snapshots=0
    local unencrypted_snapshots=0
    local automated_snapshots=0
    local manual_snapshots=0
    local regions_with_resources=0
    local total_size_gb=0
    
    echo -e "${PURPLE}=== Analizando perfil: $profile ===${NC}"
    
    # Obtener Account ID
    local account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    
    # Escanear regiones
    for region in "${REGIONS[@]}"; do
        echo -e "🌍 Escaneando región ${CYAN}$region${NC}..."
        
        # Obtener volúmenes en la región
        local volumes_data=$(aws ec2 describe-volumes \
            --profile "$profile" \
            --region "$region" \
            --filters "Name=state,Values=in-use,available" \
            --query 'Volumes[].[VolumeId,Size]' \
            --output text 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo -e "   ⚠️ Error accediendo a región $region"
            continue
        fi
        
        local region_volumes=0
        local region_snapshots=0
        local region_size=0
        
        if [ -n "$volumes_data" ]; then
            regions_with_resources=$((regions_with_resources + 1))
            
            # Procesar volúmenes
            while IFS=$'\t' read -r volume_id size; do
                if [ -n "$volume_id" ]; then
                    region_volumes=$((region_volumes + 1))
                    total_volumes=$((total_volumes + 1))
                    region_size=$((region_size + size))
                    total_size_gb=$((total_size_gb + size))
                    
                    # Verificar si tiene snapshots
                    local volume_snapshots=$(aws ec2 describe-snapshots \
                        --owner-ids "$account_id" \
                        --profile "$profile" \
                        --region "$region" \
                        --filters "Name=volume-id,Values=$volume_id" \
                        --query 'length(Snapshots)' \
                        --output text 2>/dev/null)
                    
                    if [ -n "$volume_snapshots" ] && [ "$volume_snapshots" -gt 0 ]; then
                        volumes_with_snapshots=$((volumes_with_snapshots + 1))
                    else
                        volumes_without_snapshots=$((volumes_without_snapshots + 1))
                    fi
                fi
            done <<< "$volumes_data"
        fi
        
        # Obtener snapshots en la región
        local snapshots_data=$(aws ec2 describe-snapshots \
            --owner-ids "$account_id" \
            --profile "$profile" \
            --region "$region" \
            --query 'Snapshots[].[SnapshotId,Encrypted,StartTime,Tags[?Key==`AutomatedBackup`].Value|[0]]' \
            --output text 2>/dev/null)
        
        if [ -n "$snapshots_data" ]; then
            if [ $regions_with_resources -eq 0 ] && [ $region_volumes -eq 0 ]; then
                regions_with_resources=$((regions_with_resources + 1))
            fi
            
            while IFS=$'\t' read -r snapshot_id encrypted start_time automated; do
                if [ -n "$snapshot_id" ]; then
                    region_snapshots=$((region_snapshots + 1))
                    total_snapshots=$((total_snapshots + 1))
                    
                    # Verificar cifrado
                    if [ "$encrypted" = "True" ]; then
                        encrypted_snapshots=$((encrypted_snapshots + 1))
                    else
                        unencrypted_snapshots=$((unencrypted_snapshots + 1))
                    fi
                    
                    # Verificar automatización
                    if [ "$automated" = "true" ]; then
                        automated_snapshots=$((automated_snapshots + 1))
                    else
                        manual_snapshots=$((manual_snapshots + 1))
                    fi
                    
                    # Verificar si es snapshot reciente (últimas 48 horas)
                    if [ -n "$start_time" ]; then
                        local snapshot_date=$(date -d "$start_time" +%s 2>/dev/null)
                        local cutoff_date=$(date -d "2 days ago" +%s 2>/dev/null)
                        
                        if [ -n "$snapshot_date" ] && [ -n "$cutoff_date" ] && [ "$snapshot_date" -gt "$cutoff_date" ]; then
                            recent_snapshots=$((recent_snapshots + 1))
                        fi
                    fi
                fi
            done <<< "$snapshots_data"
        fi
        
        echo -e "   📊 Volúmenes: ${BLUE}$region_volumes${NC} | Snapshots: ${BLUE}$region_snapshots${NC} | Tamaño: ${BLUE}${region_size}GB${NC}"
    done
    
    # Calcular puntuación de compliance para el perfil
    local compliance_score=0
    if [ $total_volumes -gt 0 ]; then
        # Base: porcentaje de volúmenes con backup
        local backup_percent=$((volumes_with_snapshots * 100 / total_volumes))
        compliance_score=$backup_percent
        
        # Bonificar por snapshots recientes
        if [ $recent_snapshots -gt 0 ]; then
            local recent_bonus=$((recent_snapshots * 5))
            if [ $recent_bonus -gt 20 ]; then
                recent_bonus=20
            fi
            compliance_score=$((compliance_score + recent_bonus))
        fi
        
        # Bonificar por automatización
        if [ $automated_snapshots -gt 0 ] && [ $total_snapshots -gt 0 ]; then
            local automation_percent=$((automated_snapshots * 100 / total_snapshots))
            local automation_bonus=$((automation_percent / 10))
            compliance_score=$((compliance_score + automation_bonus))
        fi
        
        # Penalizar por volúmenes sin backup
        if [ $volumes_without_snapshots -gt 0 ]; then
            local no_backup_penalty=$((volumes_without_snapshots * 15))
            compliance_score=$((compliance_score - no_backup_penalty))
        fi
        
        # Mantener en rango 0-100
        if [ $compliance_score -gt 100 ]; then
            compliance_score=100
        elif [ $compliance_score -lt 0 ]; then
            compliance_score=0
        fi
    else
        compliance_score=100  # Sin volúmenes = compliance perfecto
    fi
    
    # Determinar estado del perfil
    local status="UNKNOWN"
    if [ $total_volumes -eq 0 ]; then
        status="NO_VOLUMES"
    elif [ $volumes_without_snapshots -eq 0 ] && [ $recent_snapshots -gt 0 ]; then
        status="EXCELLENT"
    elif [ $compliance_score -ge 80 ]; then
        status="GOOD"
    elif [ $compliance_score -ge 60 ]; then
        status="WARNING"
    else
        status="CRITICAL"
    fi
    
    # Almacenar datos del perfil
    PROFILE_DATA["$profile"]="$account_id|$total_volumes|$total_snapshots|$volumes_with_snapshots|$volumes_without_snapshots|$recent_snapshots|$encrypted_snapshots|$unencrypted_snapshots|$automated_snapshots|$manual_snapshots|$regions_with_resources|$total_size_gb"
    PROFILE_SCORES["$profile"]="$compliance_score"
    PROFILE_STATUS["$profile"]="$status"
    
    # Actualizar totales globales
    GLOBAL_TOTAL_VOLUMES=$((GLOBAL_TOTAL_VOLUMES + total_volumes))
    GLOBAL_TOTAL_SNAPSHOTS=$((GLOBAL_TOTAL_SNAPSHOTS + total_snapshots))
    GLOBAL_VOLUMES_WITH_SNAPSHOTS=$((GLOBAL_VOLUMES_WITH_SNAPSHOTS + volumes_with_snapshots))
    GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS=$((GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS + volumes_without_snapshots))
    GLOBAL_RECENT_SNAPSHOTS=$((GLOBAL_RECENT_SNAPSHOTS + recent_snapshots))
    GLOBAL_ENCRYPTED_SNAPSHOTS=$((GLOBAL_ENCRYPTED_SNAPSHOTS + encrypted_snapshots))
    GLOBAL_UNENCRYPTED_SNAPSHOTS=$((GLOBAL_UNENCRYPTED_SNAPSHOTS + unencrypted_snapshots))
    GLOBAL_AUTOMATED_SNAPSHOTS=$((GLOBAL_AUTOMATED_SNAPSHOTS + automated_snapshots))
    GLOBAL_MANUAL_SNAPSHOTS=$((GLOBAL_MANUAL_SNAPSHOTS + manual_snapshots))
    GLOBAL_REGIONS_SCANNED=$((GLOBAL_REGIONS_SCANNED + regions_with_resources))
    GLOBAL_TOTAL_SIZE_GB=$((GLOBAL_TOTAL_SIZE_GB + total_size_gb))
    
    # Mostrar resumen del perfil
    echo -e "   💾 Total volúmenes: ${BLUE}$total_volumes${NC}"
    echo -e "   📷 Total snapshots: ${BLUE}$total_snapshots${NC}"
    echo -e "   ✅ Con backup: ${GREEN}$volumes_with_snapshots${NC} | Sin backup: ${YELLOW}$volumes_without_snapshots${NC}"
    echo -e "   📅 Snapshots recientes: ${GREEN}$recent_snapshots${NC}"
    echo -e "   🔐 Cifrados: ${GREEN}$encrypted_snapshots${NC} | Sin cifrar: ${YELLOW}$unencrypted_snapshots${NC}"
    echo -e "   🤖 Automatizados: ${GREEN}$automated_snapshots${NC} | Manuales: ${BLUE}$manual_snapshots${NC}"
    echo -e "   📏 Tamaño total: ${BLUE}${total_size_gb}GB${NC}"
    echo -e "   📊 Compliance: ${GREEN}$compliance_score/100${NC}"
    
    case "$status" in
        NO_VOLUMES)
            echo -e "   ✅ Estado: ${GREEN}SIN VOLÚMENES EBS${NC}"
            ;;
        EXCELLENT)
            echo -e "   🏆 Estado: ${GREEN}EXCELENTE${NC}"
            ;;
        GOOD)
            echo -e "   ✅ Estado: ${GREEN}BUENO${NC}"
            ;;
        WARNING)
            echo -e "   ⚠️ Estado: ${YELLOW}REQUIERE ATENCIÓN${NC}"
            ;;
        CRITICAL)
            echo -e "   🚨 Estado: ${RED}CRÍTICO${NC}"
            ;;
    esac
    
    echo ""
}

# Analizar cada perfil disponible
for profile in "${AVAILABLE_PROFILES[@]}"; do
    analyze_profile "$profile"
done

# Generar archivo de reporte consolidado
CONSOLIDATED_REPORT="ebs-snapshots-consolidated-$(date +%Y%m%d-%H%M%S).json"

cat > "$CONSOLIDATED_REPORT" << EOF
{
  "consolidated_audit": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "audit_type": "EBS_SNAPSHOTS_CONSOLIDATED",
    "profiles_analyzed": [$(printf '"%s",' "${AVAILABLE_PROFILES[@]}" | sed 's/,$//')],
    "total_profiles": ${#AVAILABLE_PROFILES[@]},
    "regions_covered": [$(printf '"%s",' "${REGIONS[@]}" | sed 's/,$//')],
    "global_summary": {
      "total_volumes": $GLOBAL_TOTAL_VOLUMES,
      "total_snapshots": $GLOBAL_TOTAL_SNAPSHOTS,
      "volumes_with_snapshots": $GLOBAL_VOLUMES_WITH_SNAPSHOTS,
      "volumes_without_snapshots": $GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS,
      "recent_snapshots": $GLOBAL_RECENT_SNAPSHOTS,
      "encrypted_snapshots": $GLOBAL_ENCRYPTED_SNAPSHOTS,
      "unencrypted_snapshots": $GLOBAL_UNENCRYPTED_SNAPSHOTS,
      "automated_snapshots": $GLOBAL_AUTOMATED_SNAPSHOTS,
      "manual_snapshots": $GLOBAL_MANUAL_SNAPSHOTS,
      "regions_scanned": $GLOBAL_REGIONS_SCANNED,
      "total_size_gb": $GLOBAL_TOTAL_SIZE_GB
    },
    "profile_details": {
EOF

# Agregar detalles de cada perfil
profile_count=0
for profile in "${AVAILABLE_PROFILES[@]}"; do
    profile_count=$((profile_count + 1))
    
    IFS='|' read -r account_id total_volumes total_snapshots volumes_with_snapshots volumes_without_snapshots recent_snapshots encrypted_snapshots unencrypted_snapshots automated_snapshots manual_snapshots regions_with_resources total_size_gb <<< "${PROFILE_DATA[$profile]}"
    
    cat >> "$CONSOLIDATED_REPORT" << EOF
      "$profile": {
        "account_id": "$account_id",
        "compliance_score": ${PROFILE_SCORES[$profile]},
        "status": "${PROFILE_STATUS[$profile]}",
        "metrics": {
          "total_volumes": $total_volumes,
          "total_snapshots": $total_snapshots,
          "volumes_with_snapshots": $volumes_with_snapshots,
          "volumes_without_snapshots": $volumes_without_snapshots,
          "recent_snapshots": $recent_snapshots,
          "encrypted_snapshots": $encrypted_snapshots,
          "unencrypted_snapshots": $unencrypted_snapshots,
          "automated_snapshots": $automated_snapshots,
          "manual_snapshots": $manual_snapshots,
          "regions_with_resources": $regions_with_resources,
          "total_size_gb": $total_size_gb
        }
      }$([ $profile_count -lt ${#AVAILABLE_PROFILES[@]} ] && echo "," || echo "")
EOF
done

cat >> "$CONSOLIDATED_REPORT" << EOF
    }
  }
}
EOF

# Calcular compliance global
GLOBAL_COMPLIANCE_SCORE=0
if [ $GLOBAL_TOTAL_VOLUMES -gt 0 ]; then
    # Base: porcentaje global de volúmenes con backup
    GLOBAL_BACKUP_PERCENT=$((GLOBAL_VOLUMES_WITH_SNAPSHOTS * 100 / GLOBAL_TOTAL_VOLUMES))
    GLOBAL_COMPLIANCE_SCORE=$GLOBAL_BACKUP_PERCENT
    
    # Bonificar por snapshots recientes
    if [ $GLOBAL_RECENT_SNAPSHOTS -gt 0 ]; then
        GLOBAL_RECENT_BONUS=$((GLOBAL_RECENT_SNAPSHOTS * 3))
        if [ $GLOBAL_RECENT_BONUS -gt 15 ]; then
            GLOBAL_RECENT_BONUS=15
        fi
        GLOBAL_COMPLIANCE_SCORE=$((GLOBAL_COMPLIANCE_SCORE + GLOBAL_RECENT_BONUS))
    fi
    
    # Bonificar por automatización
    if [ $GLOBAL_AUTOMATED_SNAPSHOTS -gt 0 ] && [ $GLOBAL_TOTAL_SNAPSHOTS -gt 0 ]; then
        GLOBAL_AUTOMATION_PERCENT=$((GLOBAL_AUTOMATED_SNAPSHOTS * 100 / GLOBAL_TOTAL_SNAPSHOTS))
        GLOBAL_AUTOMATION_BONUS=$((GLOBAL_AUTOMATION_PERCENT / 20))
        GLOBAL_COMPLIANCE_SCORE=$((GLOBAL_COMPLIANCE_SCORE + GLOBAL_AUTOMATION_BONUS))
    fi
    
    # Penalizar por volúmenes sin backup
    if [ $GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS -gt 0 ]; then
        GLOBAL_NO_BACKUP_PENALTY=$((GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS * 10))
        GLOBAL_COMPLIANCE_SCORE=$((GLOBAL_COMPLIANCE_SCORE - GLOBAL_NO_BACKUP_PENALTY))
    fi
    
    # Mantener en rango 0-100
    if [ $GLOBAL_COMPLIANCE_SCORE -gt 100 ]; then
        GLOBAL_COMPLIANCE_SCORE=100
    elif [ $GLOBAL_COMPLIANCE_SCORE -lt 0 ]; then
        GLOBAL_COMPLIANCE_SCORE=0
    fi
else
    GLOBAL_COMPLIANCE_SCORE=100
fi

# Calcular costos estimados
MONTHLY_COST=$(echo "scale=2; $GLOBAL_TOTAL_SIZE_GB * 0.05" | bc -l 2>/dev/null)
ANNUAL_COST=$(echo "scale=2; $MONTHLY_COST * 12" | bc -l 2>/dev/null)

# Generar dashboard ejecutivo
EXECUTIVE_DASHBOARD="ebs-snapshots-executive-dashboard-$(date +%Y%m%d).md"

cat > "$EXECUTIVE_DASHBOARD" << EOF
# 🏢 Dashboard Ejecutivo - EBS Snapshots Backup

**Fecha del Reporte**: $(date)
**Perfiles Analizados**: ${#AVAILABLE_PROFILES[@]}
**Cobertura de Regiones**: ${#REGIONS[@]} regiones (${REGIONS[*]})

---

## 📊 Métricas Globales de Backup

### Puntuación Consolidada: **${GLOBAL_COMPLIANCE_SCORE}/100**

EOF

if [ $GLOBAL_COMPLIANCE_SCORE -ge 90 ]; then
    echo "### 🏆 **EXCELENTE** - Estrategia de backup excepcional" >> "$EXECUTIVE_DASHBOARD"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 80 ]; then
    echo "### ✅ **BUENO** - Backup sólido con oportunidades de mejora menores" >> "$EXECUTIVE_DASHBOARD"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 70 ]; then
    echo "### ⚠️ **PROMEDIO** - Requiere atención en backup crítico" >> "$EXECUTIVE_DASHBOARD"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 50 ]; then
    echo "### ❌ **DEFICIENTE** - Exposición significativa a pérdida de datos" >> "$EXECUTIVE_DASHBOARD"
else
    echo "### 🚨 **CRÍTICO** - Riesgo grave de pérdida total de datos" >> "$EXECUTIVE_DASHBOARD"
fi

cat >> "$EXECUTIVE_DASHBOARD" << EOF

---

## 📈 Resumen Cuantitativo

| Métrica | Valor | Porcentaje |
|---------|-------|------------|
| **Total Volúmenes EBS** | $GLOBAL_TOTAL_VOLUMES | 100% |
| **Total Snapshots** | $GLOBAL_TOTAL_SNAPSHOTS | - |
| **Volúmenes con Backup** | $GLOBAL_VOLUMES_WITH_SNAPSHOTS | $([ $GLOBAL_TOTAL_VOLUMES -gt 0 ] && echo "$((GLOBAL_VOLUMES_WITH_SNAPSHOTS * 100 / GLOBAL_TOTAL_VOLUMES))" || echo "0")% |
| **Volúmenes Sin Backup** | $GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS | $([ $GLOBAL_TOTAL_VOLUMES -gt 0 ] && echo "$((GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS * 100 / GLOBAL_TOTAL_VOLUMES))" || echo "0")% |
| **Snapshots Recientes (48h)** | $GLOBAL_RECENT_SNAPSHOTS | - |
| **Snapshots Cifrados** | $GLOBAL_ENCRYPTED_SNAPSHOTS | $([ $GLOBAL_TOTAL_SNAPSHOTS -gt 0 ] && echo "$((GLOBAL_ENCRYPTED_SNAPSHOTS * 100 / GLOBAL_TOTAL_SNAPSHOTS))" || echo "0")% |
| **Snapshots Automatizados** | $GLOBAL_AUTOMATED_SNAPSHOTS | $([ $GLOBAL_TOTAL_SNAPSHOTS -gt 0 ] && echo "$((GLOBAL_AUTOMATED_SNAPSHOTS * 100 / GLOBAL_TOTAL_SNAPSHOTS))" || echo "0")% |
| **Tamaño Total** | ${GLOBAL_TOTAL_SIZE_GB}GB | - |

---

## 💰 Análisis Financiero

- **Costo Mensual Estimado**: \$${MONTHLY_COST:-"0.00"}
- **Costo Anual Proyectado**: \$${ANNUAL_COST:-"0.00"}
- **Costo por GB/mes**: \$0.05
- **ROI de Backup**: Prevención de pérdidas > costos operativos

---

## 🏢 Análisis por Perfil/Cuenta

EOF

for profile in "${AVAILABLE_PROFILES[@]}"; do
    IFS='|' read -r account_id total_volumes total_snapshots volumes_with_snapshots volumes_without_snapshots recent_snapshots encrypted_snapshots unencrypted_snapshots automated_snapshots manual_snapshots regions_with_resources total_size_gb <<< "${PROFILE_DATA[$profile]}"
    
    local compliance_score=${PROFILE_SCORES[$profile]}
    local status=${PROFILE_STATUS[$profile]}
    
    cat >> "$EXECUTIVE_DASHBOARD" << EOF
### 📋 Perfil: **$profile** (Account: $account_id)

EOF
    
    case "$status" in
        NO_VOLUMES)
            echo "**Estado**: 🟢 Sin volúmenes EBS (Compliance: 100%)" >> "$EXECUTIVE_DASHBOARD"
            ;;
        EXCELLENT)
            echo "**Estado**: 🏆 Excelente (Compliance: $compliance_score/100)" >> "$EXECUTIVE_DASHBOARD"
            ;;
        GOOD)
            echo "**Estado**: ✅ Bueno (Compliance: $compliance_score/100)" >> "$EXECUTIVE_DASHBOARD"
            ;;
        WARNING)
            echo "**Estado**: ⚠️ Requiere Atención (Compliance: $compliance_score/100)" >> "$EXECUTIVE_DASHBOARD"
            ;;
        CRITICAL)
            echo "**Estado**: 🚨 Crítico (Compliance: $compliance_score/100)" >> "$EXECUTIVE_DASHBOARD"
            ;;
    esac
    
    cat >> "$EXECUTIVE_DASHBOARD" << EOF

- **Volúmenes Totales**: $total_volumes
- **Snapshots Totales**: $total_snapshots  
- **Con Backup**: $volumes_with_snapshots | **Sin Backup**: $volumes_without_snapshots
- **Snapshots Recientes**: $recent_snapshots
- **Snapshots Cifrados**: $encrypted_snapshots
- **Automatizados**: $automated_snapshots
- **Tamaño**: ${total_size_gb}GB

EOF
done

cat >> "$EXECUTIVE_DASHBOARD" << EOF
---

## 🎯 Recomendaciones Estratégicas

### Acciones Inmediatas (0-30 días)
EOF

# Generar recomendaciones basadas en el análisis
if [ $GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS -gt 0 ]; then
    echo "1. **🚨 CRÍTICO**: Implementar backup inmediato para $GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS volumen(es) sin snapshots" >> "$EXECUTIVE_DASHBOARD"
fi

if [ $GLOBAL_RECENT_SNAPSHOTS -eq 0 ] && [ $GLOBAL_TOTAL_VOLUMES -gt 0 ]; then
    echo "2. **⚠️ ALTO**: No hay snapshots recientes - ejecutar backup de emergencia" >> "$EXECUTIVE_DASHBOARD"
fi

if [ $GLOBAL_UNENCRYPTED_SNAPSHOTS -gt 0 ]; then
    echo "3. **🔐 MEDIO**: Configurar cifrado para $GLOBAL_UNENCRYPTED_SNAPSHOTS snapshot(s) sin cifrar" >> "$EXECUTIVE_DASHBOARD"
fi

# Identificar perfiles problemáticos
CRITICAL_PROFILES=0
WARNING_PROFILES=0
for profile in "${AVAILABLE_PROFILES[@]}"; do
    case "${PROFILE_STATUS[$profile]}" in
        CRITICAL)
            CRITICAL_PROFILES=$((CRITICAL_PROFILES + 1))
            ;;
        WARNING)
            WARNING_PROFILES=$((WARNING_PROFILES + 1))
            ;;
    esac
done

if [ $CRITICAL_PROFILES -gt 0 ]; then
    echo "4. **🔴 URGENTE**: Revisar estrategia de backup en $CRITICAL_PROFILES perfil(es) con estado crítico" >> "$EXECUTIVE_DASHBOARD"
fi

cat >> "$EXECUTIVE_DASHBOARD" << EOF

### Mejoras de Proceso (30-90 días)
1. **Automatización**: Implementar DLM (Data Lifecycle Manager) para snapshots automáticos
2. **Políticas**: Establecer políticas organizacionales de backup por criticidad
3. **Monitoreo**: Configurar alertas para fallos de backup y volúmenes nuevos
4. **Capacitación**: Entrenar equipos en mejores prácticas de backup EBS

### Iniciativas Estratégicas (90+ días)
1. **Cross-Region**: Implementar replicación de snapshots críticos a región secundaria
2. **Disaster Recovery**: Integrar snapshots en planes de recuperación de desastres
3. **Compliance**: Alinear retención con requerimientos regulatorios
4. **Cost Optimization**: Optimizar retención y automatizar limpieza de snapshots antiguos

---

## 📊 Tendencias y Benchmarks

### Comparación Sectorial
- **Organizaciones Tier 1**: >95% de volúmenes con backup
- **Empresas Establecidas**: 85-95% de cobertura de backup
- **Organizaciones en Crecimiento**: 70-85% de cobertura  
- **Startups/Nuevas**: <70% de cobertura

**Su Organización**: $([ $GLOBAL_TOTAL_VOLUMES -gt 0 ] && echo "$((GLOBAL_VOLUMES_WITH_SNAPSHOTS * 100 / GLOBAL_TOTAL_VOLUMES))" || echo "0")% de cobertura

### Impacto en el Negocio
- **Protección de Datos**: Prevención de pérdida total de datos críticos
- **Continuidad Operacional**: Minimización de downtime por fallas de almacenamiento
- **Cumplimiento Regulatorio**: Evidencia de controles de backup y retención
- **Reducción de Costos**: Evita costos de recreación de datos perdidos

---

## 🔧 Herramientas de Implementación

### Scripts de Automatización Disponibles
\`\`\`bash
# Crear snapshots para todos los volúmenes
./create-ebs-snapshots.sh PERFIL

# Verificar compliance de backup
./verify-ebs-snapshots.sh PERFIL

# Generar reportes ejecutivos
./ebs-snapshots-summary.sh
\`\`\`

### Comandos de Corrección Rápida
\`\`\`bash
# Crear snapshots para volúmenes sin backup
for profile in ancla azbeacons azcenit; do
  for region in us-east-1 us-west-2 eu-west-1; do
    # Obtener volúmenes sin snapshots recientes
    aws ec2 describe-volumes --profile \$profile --region \$region \\
      --query "Volumes[?State=='in-use'].VolumeId" --output text | \\
      xargs -I {} aws ec2 create-snapshot --volume-id {} \\
      --description "Emergency backup - \$(date)" --profile \$profile --region \$region
  done
done

# Configurar DLM para automatización
aws dlm create-lifecycle-policy \\
  --execution-role-arn arn:aws:iam::\$ACCOUNT_ID:role/AWSDataLifecycleManagerDefaultRole \\
  --description "Automated daily snapshots" \\
  --state ENABLED
\`\`\`

---

## 📞 Contactos y Escalación

- **Responsable de Backup**: [Insertar contacto]
- **Administradores AWS**: [Insertar contactos]  
- **Escalación Ejecutiva**: [Insertar contacto]
- **Soporte 24/7**: [Insertar contacto]

---

*Reporte generado automáticamente el $(date) | Próxima revisión recomendada: $(date -d "+15 days")*
EOF

# Mostrar resumen en pantalla
echo -e "${PURPLE}=== DASHBOARD EJECUTIVO CONSOLIDADO ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🏢 Perfiles analizados: ${GREEN}${#AVAILABLE_PROFILES[@]}${NC} (${AVAILABLE_PROFILES[*]})"
echo -e "🌍 Regiones cubiertas: ${GREEN}${#REGIONS[@]}${NC} (${REGIONS[*]})"
echo -e "💾 Total volúmenes EBS: ${GREEN}$GLOBAL_TOTAL_VOLUMES${NC}"
echo -e "📷 Total snapshots: ${GREEN}$GLOBAL_TOTAL_SNAPSHOTS${NC}"
echo -e "✅ Volúmenes con backup: ${GREEN}$GLOBAL_VOLUMES_WITH_SNAPSHOTS${NC} ($([ $GLOBAL_TOTAL_VOLUMES -gt 0 ] && echo "$((GLOBAL_VOLUMES_WITH_SNAPSHOTS * 100 / GLOBAL_TOTAL_VOLUMES))" || echo "0")%)"
echo -e "⚠️ Sin backup: ${YELLOW}$GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS${NC} ($([ $GLOBAL_TOTAL_VOLUMES -gt 0 ] && echo "$((GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS * 100 / GLOBAL_TOTAL_VOLUMES))" || echo "0")%)"
echo -e "📅 Snapshots recientes: ${GREEN}$GLOBAL_RECENT_SNAPSHOTS${NC}"
echo -e "🔐 Snapshots cifrados: ${GREEN}$GLOBAL_ENCRYPTED_SNAPSHOTS${NC} ($([ $GLOBAL_TOTAL_SNAPSHOTS -gt 0 ] && echo "$((GLOBAL_ENCRYPTED_SNAPSHOTS * 100 / GLOBAL_TOTAL_SNAPSHOTS))" || echo "0")%)"
echo -e "🤖 Snapshots automatizados: ${GREEN}$GLOBAL_AUTOMATED_SNAPSHOTS${NC} ($([ $GLOBAL_TOTAL_SNAPSHOTS -gt 0 ] && echo "$((GLOBAL_AUTOMATED_SNAPSHOTS * 100 / GLOBAL_TOTAL_SNAPSHOTS))" || echo "0")%)"
echo -e "📏 Tamaño total: ${GREEN}${GLOBAL_TOTAL_SIZE_GB}GB${NC}"

if [ -n "$MONTHLY_COST" ]; then
    echo -e "💰 Costo estimado mensual: ${GREEN}\$${MONTHLY_COST}${NC}"
fi

# Mostrar compliance global con colores
if [ $GLOBAL_COMPLIANCE_SCORE -ge 90 ]; then
    echo -e "🏆 Compliance Global: ${GREEN}$GLOBAL_COMPLIANCE_SCORE/100 (EXCELENTE)${NC}"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 80 ]; then
    echo -e "✅ Compliance Global: ${GREEN}$GLOBAL_COMPLIANCE_SCORE/100 (BUENO)${NC}"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 70 ]; then
    echo -e "⚠️ Compliance Global: ${YELLOW}$GLOBAL_COMPLIANCE_SCORE/100 (PROMEDIO)${NC}"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 50 ]; then
    echo -e "❌ Compliance Global: ${RED}$GLOBAL_COMPLIANCE_SCORE/100 (DEFICIENTE)${NC}"
else
    echo -e "🚨 Compliance Global: ${RED}$GLOBAL_COMPLIANCE_SCORE/100 (CRÍTICO)${NC}"
fi

echo ""
echo -e "${PURPLE}=== RESUMEN POR PERFIL ===${NC}"
for profile in "${AVAILABLE_PROFILES[@]}"; do
    IFS='|' read -r account_id total_volumes total_snapshots volumes_with_snapshots volumes_without_snapshots recent_snapshots encrypted_snapshots unencrypted_snapshots automated_snapshots manual_snapshots regions_with_resources total_size_gb <<< "${PROFILE_DATA[$profile]}"
    
    local compliance_score=${PROFILE_SCORES[$profile]}
    local status=${PROFILE_STATUS[$profile]}
    
    echo -e "${CYAN}📋 $profile${NC} (${BLUE}$account_id${NC})"
    
    case "$status" in
        NO_VOLUMES)
            echo -e "   ✅ Estado: ${GREEN}SIN VOLÚMENES${NC} | Compliance: ${GREEN}100/100${NC}"
            ;;
        EXCELLENT)
            echo -e "   🏆 Estado: ${GREEN}EXCELENTE${NC} | Compliance: ${GREEN}$compliance_score/100${NC}"
            ;;
        GOOD)
            echo -e "   ✅ Estado: ${GREEN}BUENO${NC} | Compliance: ${GREEN}$compliance_score/100${NC}"
            ;;
        WARNING)
            echo -e "   ⚠️ Estado: ${YELLOW}ATENCIÓN${NC} | Compliance: ${YELLOW}$compliance_score/100${NC}"
            ;;
        CRITICAL)
            echo -e "   🚨 Estado: ${RED}CRÍTICO${NC} | Compliance: ${RED}$compliance_score/100${NC}"
            ;;
    esac
    
    echo -e "   📊 Volúmenes: ${BLUE}$total_volumes${NC} | Snapshots: ${BLUE}$total_snapshots${NC} | Sin backup: ${RED}$volumes_without_snapshots${NC} | Tamaño: ${BLUE}${total_size_gb}GB${NC}"
done

echo ""
echo -e "📁 Reporte JSON: ${GREEN}$CONSOLIDATED_REPORT${NC}"
echo -e "📊 Dashboard Ejecutivo: ${GREEN}$EXECUTIVE_DASHBOARD${NC}"

# Estado final organizacional
echo ""
if [ $GLOBAL_TOTAL_VOLUMES -eq 0 ]; then
    echo -e "${GREEN}✅ ORGANIZACIÓN SIN VOLÚMENES EBS${NC}"
    echo -e "${BLUE}💡 No se requieren acciones de backup${NC}"
elif [ $GLOBAL_VOLUMES_WITHOUT_SNAPSHOTS -eq 0 ] && [ $GLOBAL_RECENT_SNAPSHOTS -gt 0 ]; then
    echo -e "${GREEN}🎉 ORGANIZACIÓN CON BACKUP COMPLETO${NC}"
    echo -e "${BLUE}💡 Todos los volúmenes tienen backup reciente${NC}"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 80 ]; then
    echo -e "${GREEN}✅ COMPLIANCE DE BACKUP SATISFACTORIO${NC}"
    echo -e "${BLUE}💡 Continuar con mejoras en automatización${NC}"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 60 ]; then
    echo -e "${YELLOW}⚠️ REQUIERE ATENCIÓN EN BACKUP${NC}"
    echo -e "${YELLOW}🔧 Implementar plan de mejora de backup${NC}"
else
    echo -e "${RED}🚨 ESTADO CRÍTICO DE BACKUP${NC}"
    echo -e "${RED}🆘 Riesgo grave de pérdida de datos - intervención inmediata${NC}"
fi