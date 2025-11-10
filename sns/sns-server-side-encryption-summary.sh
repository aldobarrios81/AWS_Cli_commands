#!/bin/bash
# sns-server-side-encryption-summary.sh
# Resumen consolidado de cifrado server-side para SNS across all profiles
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
echo -e "${BLUE}📊 RESUMEN CONSOLIDADO - SNS SERVER-SIDE ENCRYPTION${NC}"
echo "=========================================================================="
echo -e "Análisis multi-perfil de cifrado KMS para tópicos SNS"
echo -e "Generado: $(date)"
echo ""

# Profiles y regiones a analizar
PROFILES=("ancla" "azbeacons" "azcenit")
REGIONS=("us-east-1" "us-west-2" "eu-west-1")

# Variables globales de resumen
GLOBAL_TOTAL_TOPICS=0
GLOBAL_ENCRYPTED_TOPICS=0
GLOBAL_UNENCRYPTED_TOPICS=0
GLOBAL_CUSTOMER_MANAGED_KEYS=0
GLOBAL_AWS_MANAGED_KEYS=0
GLOBAL_ACTIVE_PROFILES=0
GLOBAL_ACTIVE_REGIONS=0

# Arrays para almacenar datos por perfil
declare -A PROFILE_DATA
declare -A REGION_DATA

# Función para verificar acceso al perfil
check_profile_access() {
    local profile="$1"
    aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null
}

# Función para contar tópicos por región
count_topics_in_region() {
    local profile="$1"
    local region="$2"
    
    aws sns list-topics \
        --profile "$profile" \
        --region "$region" \
        --query 'length(Topics)' \
        --output text 2>/dev/null
}

# Función para analizar cifrado de tópicos
analyze_topics_encryption() {
    local profile="$1"
    local region="$2"
    local encrypted=0
    local unencrypted=0
    local customer_managed=0
    local aws_managed=0
    
    # Obtener lista de tópicos
    local topics=$(aws sns list-topics \
        --profile "$profile" \
        --region "$region" \
        --query 'Topics[].TopicArn' \
        --output text 2>/dev/null)
    
    if [ -n "$topics" ]; then
        for topic_arn in $topics; do
            if [ -n "$topic_arn" ]; then
                # Verificar cifrado
                local encryption_key=$(aws sns get-topic-attributes \
                    --topic-arn "$topic_arn" \
                    --profile "$profile" \
                    --region "$region" \
                    --query 'Attributes.KmsMasterKeyId' \
                    --output text 2>/dev/null)
                
                if [ -n "$encryption_key" ] && [ "$encryption_key" != "None" ]; then
                    encrypted=$((encrypted + 1))
                    
                    # Determinar tipo de clave
                    if [[ "$encryption_key" =~ "alias/aws/sns" ]]; then
                        aws_managed=$((aws_managed + 1))
                    else
                        customer_managed=$((customer_managed + 1))
                    fi
                else
                    unencrypted=$((unencrypted + 1))
                fi
            fi
        done
    fi
    
    echo "$encrypted|$unencrypted|$customer_managed|$aws_managed"
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
        PROFILE_DATA["$profile"]="ERROR|0|0|0|0|0"
        continue
    fi
    
    echo -e "   ✅ Account ID: ${GREEN}$account_id${NC}"
    GLOBAL_ACTIVE_PROFILES=$((GLOBAL_ACTIVE_PROFILES + 1))
    
    # Variables por perfil
    profile_total=0
    profile_encrypted=0
    profile_unencrypted=0
    profile_customer_managed=0
    profile_aws_managed=0
    profile_active_regions=0
    
    # Analizar cada región
    for region in "${REGIONS[@]}"; do
        topic_count=$(count_topics_in_region "$profile" "$region")
        
        if [ -n "$topic_count" ] && [ "$topic_count" -gt 0 ]; then
            echo -e "   📍 ${GREEN}$region${NC}: $topic_count tópicos"
            profile_active_regions=$((profile_active_regions + 1))
            
            # Analizar cifrado en la región
            encryption_result=$(analyze_topics_encryption "$profile" "$region")
            IFS='|' read -r encrypted unencrypted customer_managed aws_managed <<< "$encryption_result"
            
            profile_total=$((profile_total + topic_count))
            profile_encrypted=$((profile_encrypted + encrypted))
            profile_unencrypted=$((profile_unencrypted + unencrypted))
            profile_customer_managed=$((profile_customer_managed + customer_managed))
            profile_aws_managed=$((profile_aws_managed + aws_managed))
            
            # Estadísticas por región
            region_key="$profile-$region"
            REGION_DATA["$region_key"]="$topic_count|$encrypted|$unencrypted|$customer_managed|$aws_managed"
            
            if [ "$encrypted" -eq "$topic_count" ]; then
                echo -e "      🔐 Cifrado: ${GREEN}100% ($encrypted/$topic_count)${NC}"
            elif [ "$encrypted" -gt 0 ]; then
                percent=$((encrypted * 100 / topic_count))
                echo -e "      🔐 Cifrado: ${YELLOW}$percent% ($encrypted/$topic_count)${NC}"
            else
                echo -e "      🔐 Cifrado: ${RED}0% (0/$topic_count)${NC}"
            fi
            
        else
            echo -e "   📍 ${BLUE}$region${NC}: Sin tópicos SNS"
        fi
    done
    
    # Guardar datos del perfil
    PROFILE_DATA["$profile"]="$account_id|$profile_total|$profile_encrypted|$profile_unencrypted|$profile_customer_managed|$profile_aws_managed"
    
    # Sumar a totales globales
    GLOBAL_TOTAL_TOPICS=$((GLOBAL_TOTAL_TOPICS + profile_total))
    GLOBAL_ENCRYPTED_TOPICS=$((GLOBAL_ENCRYPTED_TOPICS + profile_encrypted))
    GLOBAL_UNENCRYPTED_TOPICS=$((GLOBAL_UNENCRYPTED_TOPICS + profile_unencrypted))
    GLOBAL_CUSTOMER_MANAGED_KEYS=$((GLOBAL_CUSTOMER_MANAGED_KEYS + profile_customer_managed))
    GLOBAL_AWS_MANAGED_KEYS=$((GLOBAL_AWS_MANAGED_KEYS + profile_aws_managed))
    
    # Mostrar resumen del perfil
    if [ $profile_total -gt 0 ]; then
        profile_percent=$((profile_encrypted * 100 / profile_total))
        echo -e "   📊 Total: ${GREEN}$profile_total${NC} tópicos, Cifrado: ${GREEN}$profile_percent%${NC}"
    else
        echo -e "   📊 ${BLUE}Sin tópicos SNS en este perfil${NC}"
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
echo -e "🌍 Regiones con tópicos: ${GREEN}$GLOBAL_ACTIVE_REGIONS${NC}"
echo -e "📢 Total tópicos SNS: ${GREEN}$GLOBAL_TOTAL_TOPICS${NC}"

if [ $GLOBAL_TOTAL_TOPICS -gt 0 ]; then
    GLOBAL_ENCRYPTION_PERCENT=$((GLOBAL_ENCRYPTED_TOPICS * 100 / GLOBAL_TOTAL_TOPICS))
    
    echo -e "🔐 Tópicos cifrados: ${GREEN}$GLOBAL_ENCRYPTED_TOPICS${NC} (${GREEN}$GLOBAL_ENCRYPTION_PERCENT%${NC})"
    echo -e "❌ Sin cifrar: ${RED}$GLOBAL_UNENCRYPTED_TOPICS${NC}"
    echo -e "🔑 Claves customer-managed: ${GREEN}$GLOBAL_CUSTOMER_MANAGED_KEYS${NC}"
    echo -e "🔑 Claves AWS-managed: ${BLUE}$GLOBAL_AWS_MANAGED_KEYS${NC}"
else
    echo -e "${BLUE}ℹ️ No se encontraron tópicos SNS en ningún perfil${NC}"
fi

echo ""

# Tabla comparativa por perfil
echo -e "${PURPLE}=== COMPARATIVA POR PERFIL ===${NC}"
printf "%-12s %-15s %-8s %-8s %-10s %-8s %-8s\n" "PERFIL" "ACCOUNT_ID" "TÓPICOS" "CIFRADOS" "% CIFRADO" "CUST-KMS" "AWS-KMS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

for profile in "${PROFILES[@]}"; do
    data="${PROFILE_DATA[$profile]}"
    
    if [[ "$data" == ERROR* ]]; then
        printf "%-12s %-15s %-8s %-8s %-10s %-8s %-8s\n" "$profile" "ERROR" "-" "-" "-" "-" "-"
    else
        IFS='|' read -r account_id total encrypted unencrypted customer_managed aws_managed <<< "$data"
        
        if [ "$total" -gt 0 ]; then
            percent=$((encrypted * 100 / total))
            printf "%-12s %-15s %-8s %-8s %-10s %-8s %-8s\n" "$profile" "$account_id" "$total" "$encrypted" "${percent}%" "$customer_managed" "$aws_managed"
        else
            printf "%-12s %-15s %-8s %-8s %-10s %-8s %-8s\n" "$profile" "$account_id" "0" "-" "-" "-" "-"
        fi
    fi
done

echo ""

# Análisis de riesgos
echo -e "${PURPLE}=== ANÁLISIS DE RIESGOS ===${NC}"

RISK_LEVEL="BAJO"
RISK_COLOR="$GREEN"
RISK_ISSUES=()

if [ $GLOBAL_UNENCRYPTED_TOPICS -gt 0 ]; then
    if [ $GLOBAL_UNENCRYPTED_TOPICS -eq $GLOBAL_TOTAL_TOPICS ]; then
        RISK_LEVEL="CRÍTICO"
        RISK_COLOR="$RED"
        RISK_ISSUES+=("Ningún tópico SNS tiene cifrado habilitado")
    elif [ $GLOBAL_ENCRYPTION_PERCENT -lt 50 ]; then
        RISK_LEVEL="ALTO"
        RISK_COLOR="$RED"
        RISK_ISSUES+=("Menos del 50% de tópicos están cifrados")
    elif [ $GLOBAL_ENCRYPTION_PERCENT -lt 80 ]; then
        RISK_LEVEL="MEDIO"
        RISK_COLOR="$YELLOW"
        RISK_ISSUES+=("Cifrado parcial implementado ($GLOBAL_ENCRYPTION_PERCENT%)")
    fi
fi

if [ $GLOBAL_CUSTOMER_MANAGED_KEYS -eq 0 ] && [ $GLOBAL_AWS_MANAGED_KEYS -gt 0 ]; then
    RISK_ISSUES+=("Solo se usan claves AWS-managed (menor control)")
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

if [ $GLOBAL_UNENCRYPTED_TOPICS -gt 0 ]; then
    echo -e "${YELLOW}🔧 ACCIÓN REQUERIDA:${NC}"
    echo -e "1. Ejecutar cifrado en perfiles con tópicos desprotegidos:"
    
    for profile in "${PROFILES[@]}"; do
        data="${PROFILE_DATA[$profile]}"
        if [[ "$data" != ERROR* ]]; then
            IFS='|' read -r account_id total encrypted unencrypted customer_managed aws_managed <<< "$data"
            
            if [ "$unencrypted" -gt 0 ]; then
                echo -e "   ${CYAN}./enable-sns-server-side-encryption.sh $profile${NC}"
            fi
        fi
    done
    
    echo ""
fi

echo -e "${GREEN}💡 MEJORES PRÁCTICAS:${NC}"
echo "1. 🔑 Usar claves KMS customer-managed para mayor control"
echo "2. 📊 Implementar monitoreo CloudWatch para tópicos"
echo "3. 🔄 Configurar rotación automática de claves KMS"
echo "4. 🏷️ Aplicar tags consistentes para gestión"
echo "5. 📋 Revisar políticas de acceso regularmente"
echo "6. 🔍 Auditar configuraciones trimestralmente"

echo ""

# Comandos útiles
echo -e "${PURPLE}=== COMANDOS ÚTILES ===${NC}"
echo -e "${CYAN}# Verificar estado actual de cifrado:${NC}"
echo -e "for profile in ancla azbeacons azcenit; do"
echo -e "    echo \"=== \$profile ===\""
echo -e "    ./verify-sns-server-side-encryption.sh \$profile"
echo -e "done"
echo ""

echo -e "${CYAN}# Habilitar cifrado en todos los perfiles:${NC}"
echo -e "for profile in ancla azbeacons azcenit; do"
echo -e "    ./enable-sns-server-side-encryption.sh \$profile"
echo -e "done"
echo ""

echo -e "${CYAN}# Verificar claves KMS disponibles:${NC}"
echo -e "aws kms list-aliases --profile PROFILE --region us-east-1 \\"
echo -e "    --query 'Aliases[?contains(AliasName, \`sns\`)]'"

# Generar reporte JSON consolidado
CONSOLIDATED_REPORT="sns-encryption-consolidated-$(date +%Y%m%d-%H%M).json"

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
        "total_topics": $GLOBAL_TOTAL_TOPICS,
        "encrypted_topics": $GLOBAL_ENCRYPTED_TOPICS,
        "unencrypted_topics": $GLOBAL_UNENCRYPTED_TOPICS,
        "encryption_percentage": $((GLOBAL_TOTAL_TOPICS > 0 ? GLOBAL_ENCRYPTED_TOPICS * 100 / GLOBAL_TOTAL_TOPICS : 0))
    },
    "kms_distribution": {
        "customer_managed_keys": $GLOBAL_CUSTOMER_MANAGED_KEYS,
        "aws_managed_keys": $GLOBAL_AWS_MANAGED_KEYS
    },
    "risk_assessment": {
        "level": "$RISK_LEVEL",
        "unencrypted_topics_exist": $((GLOBAL_UNENCRYPTED_TOPICS > 0)),
        "compliance_status": "$([ $GLOBAL_UNENCRYPTED_TOPICS -eq 0 ] && echo "COMPLIANT" || echo "NON_COMPLIANT")"
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
        IFS='|' read -r account_id total encrypted unencrypted customer_managed aws_managed <<< "$data"
        
        echo "        \"$profile\": {" >> "$CONSOLIDATED_REPORT"
        echo "            \"account_id\": \"$account_id\"," >> "$CONSOLIDATED_REPORT"
        echo "            \"total_topics\": $total," >> "$CONSOLIDATED_REPORT"
        echo "            \"encrypted_topics\": $encrypted," >> "$CONSOLIDATED_REPORT"
        echo "            \"unencrypted_topics\": $unencrypted," >> "$CONSOLIDATED_REPORT"
        echo "            \"customer_managed_keys\": $customer_managed," >> "$CONSOLIDATED_REPORT"
        echo "            \"aws_managed_keys\": $aws_managed," >> "$CONSOLIDATED_REPORT"
        echo "            \"encryption_percentage\": $((total > 0 ? encrypted * 100 / total : 0))" >> "$CONSOLIDATED_REPORT"
        echo -n "        }" >> "$CONSOLIDATED_REPORT"
    fi
done

cat >> "$CONSOLIDATED_REPORT" << EOF

    },
    "recommendations": [
        {
            "priority": "HIGH",
            "action": "Enable KMS encryption for unencrypted topics",
            "applicable": $((GLOBAL_UNENCRYPTED_TOPICS > 0))
        },
        {
            "priority": "MEDIUM", 
            "action": "Migrate to customer-managed KMS keys",
            "applicable": $((GLOBAL_AWS_MANAGED_KEYS > 0 && GLOBAL_CUSTOMER_MANAGED_KEYS == 0))
        },
        {
            "priority": "LOW",
            "action": "Implement CloudWatch monitoring",
            "applicable": true
        }
    ]
}
EOF

echo -e "✅ Reporte consolidado generado: ${GREEN}$CONSOLIDATED_REPORT${NC}"
echo ""

# Estado final
echo -e "${PURPLE}=== ESTADO FINAL ===${NC}"
if [ $GLOBAL_TOTAL_TOPICS -eq 0 ]; then
    echo -e "${BLUE}ℹ️ SIN TÓPICOS SNS EN NINGÚN PERFIL${NC}"
elif [ $GLOBAL_UNENCRYPTED_TOPICS -eq 0 ]; then
    echo -e "${GREEN}🎉 CIFRADO COMPLETO EN TODOS LOS PERFILES${NC}"
    echo -e "${BLUE}💡 Todos los tópicos SNS implementan cifrado KMS${NC}"
else
    echo -e "${YELLOW}⚠️ CIFRADO PARCIAL ($GLOBAL_ENCRYPTION_PERCENT% completado)${NC}"
    echo -e "${YELLOW}💡 $GLOBAL_UNENCRYPTED_TOPICS tópicos requieren configuración${NC}"
fi