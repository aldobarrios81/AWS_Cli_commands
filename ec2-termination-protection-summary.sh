#!/bin/bash
# ec2-termination-protection-summary.sh
# Resumen consolidado de protección contra terminación EC2 - Multi-perfil
# Análisis ejecutivo de compliance y seguridad para todos los perfiles

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}📊 RESUMEN EJECUTIVO - EC2 TERMINATION PROTECTION${NC}"
echo "=================================================================="
echo -e "Análisis consolidado de compliance para todos los perfiles AWS"
echo ""

# Configuración de perfiles
PROFILES=("ancla" "azbeacons" "azcenit")
REGIONS=("us-east-1" "us-west-2" "eu-west-1")

# Variables globales de resumen
GLOBAL_TOTAL_INSTANCES=0
GLOBAL_PROTECTED_INSTANCES=0
GLOBAL_UNPROTECTED_INSTANCES=0
GLOBAL_CRITICAL_PROTECTED=0
GLOBAL_CRITICAL_UNPROTECTED=0
GLOBAL_VIOLATIONS=0
GLOBAL_REGIONS_SCANNED=0
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
    local total_instances=0
    local protected_instances=0
    local unprotected_instances=0
    local critical_protected=0
    local critical_unprotected=0
    local violations=0
    local regions_with_instances=0
    
    echo -e "${PURPLE}=== Analizando perfil: $profile ===${NC}"
    
    # Obtener Account ID
    local account_id=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    
    # Escanear regiones
    for region in "${REGIONS[@]}"; do
        echo -e "🌍 Escaneando región ${CYAN}$region${NC}..."
        
        # Obtener instancias en la región
        local instances_data=$(aws ec2 describe-instances \
            --profile "$profile" \
            --region "$region" \
            --filters "Name=instance-state-name,Values=running,stopped,stopping,pending,rebooting" \
            --query 'Reservations[].Instances[].[InstanceId,InstanceType,DisableApiTermination,Tags[?Key==`Name`].Value|[0]]' \
            --output text 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo -e "   ⚠️ Error accediendo a región $region"
            continue
        fi
        
        if [ -z "$instances_data" ]; then
            echo -e "   ℹ️ Sin instancias en región $region"
            continue
        fi
        
        regions_with_instances=$((regions_with_instances + 1))
        local region_instances=0
        local region_protected=0
        
        # Procesar instancias
        while IFS=$'\t' read -r instance_id instance_type termination_protection instance_name; do
            if [ -n "$instance_id" ]; then
                region_instances=$((region_instances + 1))
                
                # Determinar criticidad básica
                local is_critical=false
                
                # Evaluar por tipo de instancia
                if [[ "$instance_type" =~ ^(m5|m6|c5|c6|r5|r6) ]]; then
                    is_critical=true
                fi
                
                # Evaluar por nombre
                if [[ "$instance_name" =~ (prod|production|critical|database|db) ]]; then
                    is_critical=true
                fi
                
                # Verificar protección
                if [ "$termination_protection" = "True" ] || [ "$termination_protection" = "true" ]; then
                    protected_instances=$((protected_instances + 1))
                    region_protected=$((region_protected + 1))
                    
                    if [ "$is_critical" = true ]; then
                        critical_protected=$((critical_protected + 1))
                    fi
                else
                    unprotected_instances=$((unprotected_instances + 1))
                    
                    if [ "$is_critical" = true ]; then
                        critical_unprotected=$((critical_unprotected + 1))
                        violations=$((violations + 1))
                    fi
                fi
                
                total_instances=$((total_instances + 1))
            fi
        done <<< "$instances_data"
        
        echo -e "   📊 Instancias: ${BLUE}$region_instances${NC} | Protegidas: ${GREEN}$region_protected${NC}"
    done
    
    # Calcular puntuación de compliance para el perfil
    local compliance_score=0
    if [ $total_instances -gt 0 ]; then
        # Base: porcentaje de protección
        local protection_percent=$((protected_instances * 100 / total_instances))
        compliance_score=$protection_percent
        
        # Penalizar por instancias críticas sin proteger
        if [ $critical_unprotected -gt 0 ]; then
            local penalty=$((critical_unprotected * 15))
            compliance_score=$((compliance_score - penalty))
        fi
        
        # Bonificar por protección de críticas
        if [ $critical_protected -gt 0 ]; then
            local bonus=$((critical_protected * 3))
            compliance_score=$((compliance_score + bonus))
        fi
        
        # Mantener en rango 0-100
        if [ $compliance_score -gt 100 ]; then
            compliance_score=100
        elif [ $compliance_score -lt 0 ]; then
            compliance_score=0
        fi
    else
        compliance_score=100  # Sin instancias = compliance perfecto
    fi
    
    # Determinar estado del perfil
    local status="UNKNOWN"
    if [ $total_instances -eq 0 ]; then
        status="NO_INSTANCES"
    elif [ $critical_unprotected -eq 0 ] && [ $violations -eq 0 ]; then
        status="COMPLIANT"
    elif [ $compliance_score -ge 80 ]; then
        status="GOOD"
    elif [ $compliance_score -ge 60 ]; then
        status="WARNING"
    else
        status="CRITICAL"
    fi
    
    # Almacenar datos del perfil
    PROFILE_DATA["$profile"]="$account_id|$total_instances|$protected_instances|$unprotected_instances|$critical_protected|$critical_unprotected|$violations|$regions_with_instances"
    PROFILE_SCORES["$profile"]="$compliance_score"
    PROFILE_STATUS["$profile"]="$status"
    
    # Actualizar totales globales
    GLOBAL_TOTAL_INSTANCES=$((GLOBAL_TOTAL_INSTANCES + total_instances))
    GLOBAL_PROTECTED_INSTANCES=$((GLOBAL_PROTECTED_INSTANCES + protected_instances))
    GLOBAL_UNPROTECTED_INSTANCES=$((GLOBAL_UNPROTECTED_INSTANCES + unprotected_instances))
    GLOBAL_CRITICAL_PROTECTED=$((GLOBAL_CRITICAL_PROTECTED + critical_protected))
    GLOBAL_CRITICAL_UNPROTECTED=$((GLOBAL_CRITICAL_UNPROTECTED + critical_unprotected))
    GLOBAL_VIOLATIONS=$((GLOBAL_VIOLATIONS + violations))
    GLOBAL_REGIONS_SCANNED=$((GLOBAL_REGIONS_SCANNED + regions_with_instances))
    
    # Mostrar resumen del perfil
    echo -e "   📋 Total instancias: ${BLUE}$total_instances${NC}"
    echo -e "   🔒 Protegidas: ${GREEN}$protected_instances${NC} | Sin proteger: ${YELLOW}$unprotected_instances${NC}"
    echo -e "   🔴 Críticas sin proteger: ${RED}$critical_unprotected${NC}"
    echo -e "   📊 Compliance: ${GREEN}$compliance_score/100${NC}"
    
    case "$status" in
        NO_INSTANCES)
            echo -e "   ✅ Estado: ${GREEN}SIN INSTANCIAS${NC}"
            ;;
        COMPLIANT)
            echo -e "   🏆 Estado: ${GREEN}TOTALMENTE CONFORME${NC}"
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
CONSOLIDATED_REPORT="ec2-termination-protection-consolidated-$(date +%Y%m%d-%H%M%S).json"

cat > "$CONSOLIDATED_REPORT" << EOF
{
  "consolidated_audit": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "audit_type": "EC2_TERMINATION_PROTECTION_CONSOLIDATED",
    "profiles_analyzed": [$(printf '"%s",' "${AVAILABLE_PROFILES[@]}" | sed 's/,$//')],
    "total_profiles": ${#AVAILABLE_PROFILES[@]},
    "regions_covered": [$(printf '"%s",' "${REGIONS[@]}" | sed 's/,$//')],
    "global_summary": {
      "total_instances": $GLOBAL_TOTAL_INSTANCES,
      "protected_instances": $GLOBAL_PROTECTED_INSTANCES,
      "unprotected_instances": $GLOBAL_UNPROTECTED_INSTANCES,
      "critical_protected": $GLOBAL_CRITICAL_PROTECTED,
      "critical_unprotected": $GLOBAL_CRITICAL_UNPROTECTED,
      "security_violations": $GLOBAL_VIOLATIONS,
      "regions_scanned": $GLOBAL_REGIONS_SCANNED
    },
    "profile_details": {
EOF

# Agregar detalles de cada perfil
profile_count=0
for profile in "${AVAILABLE_PROFILES[@]}"; do
    profile_count=$((profile_count + 1))
    
    IFS='|' read -r account_id total_instances protected_instances unprotected_instances critical_protected critical_unprotected violations regions_with_instances <<< "${PROFILE_DATA[$profile]}"
    
    cat >> "$CONSOLIDATED_REPORT" << EOF
      "$profile": {
        "account_id": "$account_id",
        "compliance_score": ${PROFILE_SCORES[$profile]},
        "status": "${PROFILE_STATUS[$profile]}",
        "metrics": {
          "total_instances": $total_instances,
          "protected_instances": $protected_instances,
          "unprotected_instances": $unprotected_instances,
          "critical_protected": $critical_protected,
          "critical_unprotected": $critical_unprotected,
          "violations": $violations,
          "regions_with_instances": $regions_with_instances
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
if [ $GLOBAL_TOTAL_INSTANCES -gt 0 ]; then
    # Base: porcentaje global de protección
    GLOBAL_PROTECTION_PERCENT=$((GLOBAL_PROTECTED_INSTANCES * 100 / GLOBAL_TOTAL_INSTANCES))
    GLOBAL_COMPLIANCE_SCORE=$GLOBAL_PROTECTION_PERCENT
    
    # Penalizar por instancias críticas sin proteger
    if [ $GLOBAL_CRITICAL_UNPROTECTED -gt 0 ]; then
        GLOBAL_PENALTY=$((GLOBAL_CRITICAL_UNPROTECTED * 10))
        GLOBAL_COMPLIANCE_SCORE=$((GLOBAL_COMPLIANCE_SCORE - GLOBAL_PENALTY))
    fi
    
    # Bonificar por protección de críticas
    if [ $GLOBAL_CRITICAL_PROTECTED -gt 0 ]; then
        GLOBAL_BONUS=$((GLOBAL_CRITICAL_PROTECTED * 2))
        GLOBAL_COMPLIANCE_SCORE=$((GLOBAL_COMPLIANCE_SCORE + GLOBAL_BONUS))
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

# Generar dashboard ejecutivo
EXECUTIVE_DASHBOARD="ec2-termination-protection-executive-dashboard-$(date +%Y%m%d).md"

cat > "$EXECUTIVE_DASHBOARD" << EOF
# 🏢 Dashboard Ejecutivo - EC2 Termination Protection

**Fecha del Reporte**: $(date)
**Perfiles Analizados**: ${#AVAILABLE_PROFILES[@]}
**Cobertura de Regiones**: ${#REGIONS[@]} regiones (${REGIONS[*]})

---

## 📊 Métricas Globales de Compliance

### Puntuación Consolidada: **${GLOBAL_COMPLIANCE_SCORE}/100**

EOF

if [ $GLOBAL_COMPLIANCE_SCORE -ge 90 ]; then
    echo "### 🏆 **EXCELENTE** - Organización con estándares de seguridad excepcionales" >> "$EXECUTIVE_DASHBOARD"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 80 ]; then
    echo "### ✅ **BUENO** - Configuración sólida con oportunidades de mejora menores" >> "$EXECUTIVE_DASHBOARD"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 70 ]; then
    echo "### ⚠️ **PROMEDIO** - Requiere atención en controles críticos de seguridad" >> "$EXECUTIVE_DASHBOARD"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 50 ]; then
    echo "### ❌ **DEFICIENTE** - Exposición significativa a riesgos operacionales" >> "$EXECUTIVE_DASHBOARD"
else
    echo "### 🚨 **CRÍTICO** - Riesgo grave de pérdida de datos y continuidad del negocio" >> "$EXECUTIVE_DASHBOARD"
fi

cat >> "$EXECUTIVE_DASHBOARD" << EOF

---

## 📈 Resumen Cuantitativo

| Métrica | Valor | Porcentaje |
|---------|-------|------------|
| **Total de Instancias EC2** | $GLOBAL_TOTAL_INSTANCES | 100% |
| **Instancias Protegidas** | $GLOBAL_PROTECTED_INSTANCES | $([ $GLOBAL_TOTAL_INSTANCES -gt 0 ] && echo "$((GLOBAL_PROTECTED_INSTANCES * 100 / GLOBAL_TOTAL_INSTANCES))" || echo "0")% |
| **Instancias Sin Protección** | $GLOBAL_UNPROTECTED_INSTANCES | $([ $GLOBAL_TOTAL_INSTANCES -gt 0 ] && echo "$((GLOBAL_UNPROTECTED_INSTANCES * 100 / GLOBAL_TOTAL_INSTANCES))" || echo "0")% |
| **Instancias Críticas Protegidas** | $GLOBAL_CRITICAL_PROTECTED | - |
| **Instancias Críticas Expuestas** | $GLOBAL_CRITICAL_UNPROTECTED | - |
| **Violaciones de Seguridad** | $GLOBAL_VIOLATIONS | - |
| **Regiones con Instancias** | $GLOBAL_REGIONS_SCANNED | $(( GLOBAL_REGIONS_SCANNED * 100 / ${#REGIONS[@]} ))% |

---

## 🏢 Análisis por Perfil/Cuenta

EOF

for profile in "${AVAILABLE_PROFILES[@]}"; do
    IFS='|' read -r account_id total_instances protected_instances unprotected_instances critical_protected critical_unprotected violations regions_with_instances <<< "${PROFILE_DATA[$profile]}"
    
    local compliance_score=${PROFILE_SCORES[$profile]}
    local status=${PROFILE_STATUS[$profile]}
    
    cat >> "$EXECUTIVE_DASHBOARD" << EOF
### 📋 Perfil: **$profile** (Account: $account_id)

EOF
    
    case "$status" in
        NO_INSTANCES)
            echo "**Estado**: 🟢 Sin instancias EC2 (Compliance: 100%)" >> "$EXECUTIVE_DASHBOARD"
            ;;
        COMPLIANT)
            echo "**Estado**: 🏆 Totalmente Conforme (Compliance: $compliance_score/100)" >> "$EXECUTIVE_DASHBOARD"
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

- **Instancias Totales**: $total_instances
- **Protegidas**: $protected_instances | **Sin Proteger**: $unprotected_instances
- **Críticas Sin Proteger**: $critical_unprotected
- **Violaciones**: $violations
- **Regiones Activas**: $regions_with_instances

EOF
done

cat >> "$EXECUTIVE_DASHBOARD" << EOF
---

## 🎯 Recomendaciones Estratégicas

### Acciones Inmediatas (0-30 días)
EOF

# Generar recomendaciones basadas en el análisis
if [ $GLOBAL_CRITICAL_UNPROTECTED -gt 0 ]; then
    echo "1. **🚨 CRÍTICO**: Proteger inmediatamente $GLOBAL_CRITICAL_UNPROTECTED instancia(s) crítica(s) identificada(s)" >> "$EXECUTIVE_DASHBOARD"
fi

if [ $GLOBAL_VIOLATIONS -gt 0 ]; then
    echo "2. **⚠️ ALTO**: Remediar $GLOBAL_VIOLATIONS violación(es) de seguridad detectada(s)" >> "$EXECUTIVE_DASHBOARD"
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
    echo "3. **🔴 URGENTE**: Revisar configuración en $CRITICAL_PROFILES perfil(es) con estado crítico" >> "$EXECUTIVE_DASHBOARD"
fi

cat >> "$EXECUTIVE_DASHBOARD" << EOF

### Mejoras de Proceso (30-90 días)
1. **Automatización**: Implementar protección automática en pipelines de despliegue
2. **Políticas**: Establecer políticas organizacionales para protección obligatoria
3. **Monitoreo**: Configurar alertas en tiempo real para cambios de protección
4. **Capacitación**: Entrenar equipos en mejores prácticas de seguridad EC2

### Iniciativas Estratégicas (90+ días)
1. **Governance**: Integrar controles en marcos de governance corporativa
2. **Compliance**: Alinear con estándares de seguridad (SOC2, ISO27001)
3. **Disaster Recovery**: Incluir protección en planes de continuidad
4. **Cost Optimization**: Balancear protección con optimización de costos

---

## 📊 Tendencias y Benchmarks

### Comparación Sectorial
- **Organizaciones Tier 1**: >95% de compliance
- **Empresas Establecidas**: 85-95% de compliance  
- **Organizaciones en Crecimiento**: 70-85% de compliance
- **Startups/Nuevas**: <70% de compliance

**Su Organización**: $GLOBAL_COMPLIANCE_SCORE% de compliance

### Impacto en el Negocio
- **Reducción de Riesgo**: Prevención de pérdidas por terminación accidental
- **Continuidad Operacional**: Protección de sistemas críticos de negocio
- **Cumplimiento Regulatorio**: Evidencia de controles preventivos
- **Reducción de Costos**: Minimización de tiempo de recuperación

---

## 🔧 Herramientas de Implementación

### Scripts de Automatización Disponibles
\`\`\`bash
# Habilitar protección masiva
./enable-ec2-termination-protection.sh PERFIL

# Verificar compliance
./verify-ec2-termination-protection.sh PERFIL

# Generar reportes ejecutivos
./ec2-termination-protection-summary.sh
\`\`\`

### Comandos de Corrección Rápida
\`\`\`bash
# Proteger todas las instancias críticas (tipos m5, c5, r5)
for profile in ancla azbeacons azcenit; do
  for region in us-east-1 us-west-2 eu-west-1; do
    aws ec2 describe-instances --profile \$profile --region \$region \\
      --filters "Name=instance-type,Values=m5.*,c5.*,r5.*" \\
                "Name=instance-state-name,Values=running" \\
      --query "Reservations[].Instances[?DisableApiTermination==\\\`false\\\`].InstanceId" \\
      --output text | xargs -n1 -I {} aws ec2 modify-instance-attribute \\
      --instance-id {} --disable-api-termination --profile \$profile --region \$region
  done
done
\`\`\`

---

## 📞 Contactos y Escalación

- **Responsable de Seguridad**: [Insertar contacto]
- **Administradores AWS**: [Insertar contactos]
- **Escalación Ejecutiva**: [Insertar contacto]
- **Soporte 24/7**: [Insertar contacto]

---

*Reporte generado automáticamente el $(date) | Próxima revisión recomendada: $(date -d "+30 days")*
EOF

# Mostrar resumen en pantalla
echo -e "${PURPLE}=== DASHBOARD EJECUTIVO CONSOLIDADO ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🏢 Perfiles analizados: ${GREEN}${#AVAILABLE_PROFILES[@]}${NC} (${AVAILABLE_PROFILES[*]})"
echo -e "🌍 Regiones cubiertas: ${GREEN}${#REGIONS[@]}${NC} (${REGIONS[*]})"
echo -e "🖥️ Total instancias EC2: ${GREEN}$GLOBAL_TOTAL_INSTANCES${NC}"
echo -e "🔒 Instancias protegidas: ${GREEN}$GLOBAL_PROTECTED_INSTANCES${NC} ($([ $GLOBAL_TOTAL_INSTANCES -gt 0 ] && echo "$((GLOBAL_PROTECTED_INSTANCES * 100 / GLOBAL_TOTAL_INSTANCES))" || echo "0")%)"
echo -e "⚠️ Sin protección: ${YELLOW}$GLOBAL_UNPROTECTED_INSTANCES${NC} ($([ $GLOBAL_TOTAL_INSTANCES -gt 0 ] && echo "$((GLOBAL_UNPROTECTED_INSTANCES * 100 / GLOBAL_TOTAL_INSTANCES))" || echo "0")%)"
echo -e "🔴 Críticas expuestas: ${RED}$GLOBAL_CRITICAL_UNPROTECTED${NC}"
echo -e "🚨 Violaciones totales: ${RED}$GLOBAL_VIOLATIONS${NC}"

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
    IFS='|' read -r account_id total_instances protected_instances unprotected_instances critical_protected critical_unprotected violations regions_with_instances <<< "${PROFILE_DATA[$profile]}"
    
    local compliance_score=${PROFILE_SCORES[$profile]}
    local status=${PROFILE_STATUS[$profile]}
    
    echo -e "${CYAN}📋 $profile${NC} (${BLUE}$account_id${NC})"
    
    case "$status" in
        NO_INSTANCES)
            echo -e "   ✅ Estado: ${GREEN}SIN INSTANCIAS${NC} | Compliance: ${GREEN}100/100${NC}"
            ;;
        COMPLIANT)
            echo -e "   🏆 Estado: ${GREEN}CONFORME${NC} | Compliance: ${GREEN}$compliance_score/100${NC}"
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
    
    echo -e "   📊 Instancias: ${BLUE}$total_instances${NC} | Protegidas: ${GREEN}$protected_instances${NC} | Críticas expuestas: ${RED}$critical_unprotected${NC}"
done

echo ""
echo -e "📁 Reporte JSON: ${GREEN}$CONSOLIDATED_REPORT${NC}"
echo -e "📊 Dashboard Ejecutivo: ${GREEN}$EXECUTIVE_DASHBOARD${NC}"

# Estado final organizacional
echo ""
if [ $GLOBAL_TOTAL_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}✅ ORGANIZACIÓN SIN INSTANCIAS EC2${NC}"
    echo -e "${BLUE}💡 No se requieren acciones de protección${NC}"
elif [ $GLOBAL_CRITICAL_UNPROTECTED -eq 0 ] && [ $GLOBAL_VIOLATIONS -eq 0 ]; then
    echo -e "${GREEN}🎉 ORGANIZACIÓN COMPLETAMENTE CONFORME${NC}"
    echo -e "${BLUE}💡 Todas las instancias críticas están protegidas${NC}"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 80 ]; then
    echo -e "${GREEN}✅ COMPLIANCE ORGANIZACIONAL SATISFACTORIO${NC}"
    echo -e "${BLUE}💡 Continuar con mejoras incrementales${NC}"
elif [ $GLOBAL_COMPLIANCE_SCORE -ge 60 ]; then
    echo -e "${YELLOW}⚠️ REQUIERE ATENCIÓN ORGANIZACIONAL${NC}"
    echo -e "${YELLOW}🔧 Implementar plan de mejora estructurado${NC}"
else
    echo -e "${RED}🚨 ESTADO CRÍTICO ORGANIZACIONAL${NC}"
    echo -e "${RED}🆘 Requiere intervención inmediata del liderazgo${NC}"
fi