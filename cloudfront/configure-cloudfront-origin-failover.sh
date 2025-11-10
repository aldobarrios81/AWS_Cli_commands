#!/bin/bash
# configure-cloudfront-origin-failover.sh
# Configuración de CloudFront Origin Failover para alta disponibilidad
# Implementa redundancia y failover automático entre orígenes primarios y secundarios

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Verificar argumentos
if [ $# -lt 1 ]; then
    echo "Uso: $0 <PERFIL_AWS> [REGION]"
    echo "Ejemplo: $0 ancla us-east-1"
    exit 1
fi

PROFILE="$1"
REGION="${2:-us-east-1}"

echo "=================================================================="
echo -e "${BLUE}🌐 CONFIGURANDO CLOUDFRONT ORIGIN FAILOVER${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "Implementando alta disponibilidad y redundancia en CloudFront"
echo ""

echo -e "${PURPLE}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
aws_version=$(aws --version 2>/dev/null | head -n1)
if [ $? -eq 0 ]; then
    echo -e "✅ AWS CLI encontrado: ${GREEN}$aws_version${NC}"
else
    echo -e "${RED}❌ AWS CLI no encontrado${NC}"
    exit 1
fi

# Verificar credenciales
echo -e "${PURPLE}🔐 Verificando credenciales para perfil '$PROFILE'...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$ACCOUNT_ID" ]; then
    echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
else
    echo -e "${RED}❌ Error de credenciales para perfil $PROFILE${NC}"
    exit 1
fi

# Verificar permisos CloudFront
echo -e "${PURPLE}🔒 Verificando permisos CloudFront...${NC}"
cloudfront_test=$(aws cloudfront list-distributions --profile "$PROFILE" --query 'DistributionList.Items[0].Id' --output text 2>/dev/null)
if [ $? -eq 0 ]; then
    echo -e "✅ Permisos CloudFront confirmados"
else
    echo -e "${RED}❌ Sin permisos CloudFront o error de acceso${NC}"
    exit 1
fi

echo ""

# Función para obtener distribuciones CloudFront
get_cloudfront_distributions() {
    local profile="$1"
    
    echo -e "${PURPLE}📋 Obteniendo distribuciones CloudFront...${NC}"
    
    local distributions=$(aws cloudfront list-distributions \
        --profile "$profile" \
        --query 'DistributionList.Items[].[Id,DomainName,Status,Enabled,Comment]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$distributions" ]; then
        echo -e "❌ No se encontraron distribuciones CloudFront"
        return 1
    fi
    
    echo -e "📊 Distribuciones encontradas:"
    echo "$distributions" | while IFS=$'\t' read -r id domain status enabled comment; do
        if [ -n "$id" ]; then
            local status_icon="❓"
            case "$status" in
                "Deployed") status_icon="✅" ;;
                "InProgress") status_icon="🔄" ;;
                *) status_icon="⚠️" ;;
            esac
            
            local enabled_icon="❌"
            [ "$enabled" = "True" ] && enabled_icon="✅"
            
            echo -e "   🌐 ${CYAN}$id${NC}"
            echo -e "      🔗 Dominio: ${BLUE}$domain${NC}"
            echo -e "      $status_icon Estado: ${GREEN}$status${NC}"
            echo -e "      $enabled_icon Habilitado: $enabled"
            echo -e "      💬 Descripción: $comment"
            echo ""
        fi
    done
}

# Función para analizar configuración de origen actual
analyze_origin_configuration() {
    local profile="$1"
    local distribution_id="$2"
    
    echo -e "${PURPLE}🔍 Analizando configuración de orígenes para distribución $distribution_id...${NC}"
    
    # Obtener configuración completa
    local config_file="/tmp/cloudfront-config-$distribution_id-$(date +%s).json"
    
    aws cloudfront get-distribution-config \
        --id "$distribution_id" \
        --profile "$profile" \
        --output json > "$config_file" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error obteniendo configuración de distribución $distribution_id${NC}"
        return 1
    fi
    
    # Extraer información de orígenes
    local origins=$(jq -r '.DistributionConfig.Origins.Items[] | "\(.Id)|\(.DomainName)|\(.CustomOriginConfig.OriginProtocolPolicy // .S3OriginConfig.OriginAccessIdentity // "N/A")"' "$config_file" 2>/dev/null)
    
    # Extraer información de grupos de orígenes
    local origin_groups=$(jq -r '.DistributionConfig.OriginGroups.Items[]? | "\(.Id)|\(.Members.Items[0].OriginId)|\(.Members.Items[1].OriginId // "NONE")|\(.FailoverCriteria.StatusCodes.Items | join(","))"' "$config_file" 2>/dev/null)
    
    echo -e "📊 Análisis de configuración:"
    echo ""
    
    echo -e "🎯 ${CYAN}ORÍGENES CONFIGURADOS:${NC}"
    if [ -n "$origins" ]; then
        echo "$origins" | while IFS='|' read -r origin_id domain_name config_info; do
            echo -e "   🌐 ID: ${BLUE}$origin_id${NC}"
            echo -e "      🔗 Dominio: ${GREEN}$domain_name${NC}"
            echo -e "      ⚙️ Configuración: $config_info"
            echo ""
        done
    else
        echo -e "   ${YELLOW}⚠️ No se pudieron obtener detalles de orígenes${NC}"
    fi
    
    echo -e "🔄 ${CYAN}GRUPOS DE FAILOVER:${NC}"
    if [ -n "$origin_groups" ] && [ "$origin_groups" != "" ]; then
        echo "$origin_groups" | while IFS='|' read -r group_id primary_origin secondary_origin status_codes; do
            echo -e "   🏷️ Grupo ID: ${BLUE}$group_id${NC}"
            echo -e "      1️⃣ Origen Primario: ${GREEN}$primary_origin${NC}"
            echo -e "      2️⃣ Origen Secundario: ${YELLOW}$secondary_origin${NC}"
            echo -e "      📊 Códigos Failover: ${CYAN}$status_codes${NC}"
            echo ""
        done
    else
        echo -e "   ${RED}❌ No hay grupos de origen configurados (Failover NO habilitado)${NC}"
        echo -e "   ${YELLOW}💡 Se recomienda configurar Origin Failover para alta disponibilidad${NC}"
    fi
    
    # Analizar comportamientos de cache
    echo -e "📋 ${CYAN}COMPORTAMIENTOS DE CACHE:${NC}"
    local behaviors=$(jq -r '.DistributionConfig.DefaultCacheBehavior.TargetOriginId as $default | 
                             [{"PathPattern": "Default", "OriginId": $default}] + 
                             [.DistributionConfig.CacheBehaviors.Items[]? | {"PathPattern": .PathPattern, "OriginId": .TargetOriginId}] | 
                             .[] | "\(.PathPattern)|\(.OriginId)"' "$config_file" 2>/dev/null)
    
    if [ -n "$behaviors" ]; then
        echo "$behaviors" | while IFS='|' read -r path_pattern origin_id; do
            echo -e "   📁 Patrón: ${BLUE}$path_pattern${NC} → Origen: ${GREEN}$origin_id${NC}"
        done
    else
        echo -e "   ${YELLOW}⚠️ No se pudieron obtener comportamientos de cache${NC}"
    fi
    
    # Guardar archivo de configuración para referencia
    echo ""
    echo -e "💾 Configuración guardada en: ${GREEN}$config_file${NC}"
    
    # Extraer ETag para futuras actualizaciones
    local etag=$(jq -r '.ETag' "$config_file" 2>/dev/null)
    echo -e "🏷️ ETag actual: ${CYAN}$etag${NC}"
    
    # Guardar información para uso posterior
    echo "$distribution_id|$config_file|$etag" > "/tmp/cf-distribution-info-$distribution_id.txt"
    
    return 0
}

# Función para crear configuración de Origin Group con Failover
create_origin_group_config() {
    local primary_origin="$1"
    local secondary_origin="$2"
    local group_id="$3"
    local status_codes="${4:-403,404,500,502,503,504}"
    
    echo -e "${PURPLE}🔧 Creando configuración de Origin Group...${NC}"
    
    # Generar configuración JSON para Origin Group
    local origin_group_config=$(cat << EOF
{
    "Id": "$group_id",
    "FailoverCriteria": {
        "StatusCodes": {
            "Quantity": $(echo "$status_codes" | tr ',' '\n' | wc -l),
            "Items": [$(echo "$status_codes" | sed 's/,/, /g')]
        }
    },
    "Members": {
        "Quantity": 2,
        "Items": [
            {
                "OriginId": "$primary_origin"
            },
            {
                "OriginId": "$secondary_origin"
            }
        ]
    }
}
EOF
)
    
    echo -e "✅ Configuración de Origin Group creada:"
    echo -e "   🏷️ ID del Grupo: ${BLUE}$group_id${NC}"
    echo -e "   1️⃣ Origen Primario: ${GREEN}$primary_origin${NC}"
    echo -e "   2️⃣ Origen Secundario: ${YELLOW}$secondary_origin${NC}"
    echo -e "   📊 Códigos de Failover: ${CYAN}$status_codes${NC}"
    
    echo "$origin_group_config"
}

# Función para configurar failover automático
configure_origin_failover() {
    local profile="$1"
    local distribution_id="$2"
    local primary_origin="$3"
    local secondary_origin="$4"
    local group_id="${5:-failover-group-$(date +%s)}"
    
    echo -e "${PURPLE}🔄 Configurando Origin Failover para distribución $distribution_id...${NC}"
    
    # Verificar que la información de distribución existe
    local info_file="/tmp/cf-distribution-info-$distribution_id.txt"
    if [ ! -f "$info_file" ]; then
        echo -e "${RED}❌ Información de distribución no encontrada. Ejecute primero el análisis.${NC}"
        return 1
    fi
    
    local config_info=$(cat "$info_file")
    IFS='|' read -r dist_id config_file etag <<< "$config_info"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}❌ Archivo de configuración no encontrado: $config_file${NC}"
        return 1
    fi
    
    echo -e "📋 Parámetros de configuración:"
    echo -e "   🆔 Distribución: ${BLUE}$distribution_id${NC}"
    echo -e "   1️⃣ Origen Primario: ${GREEN}$primary_origin${NC}"
    echo -e "   2️⃣ Origen Secundario: ${YELLOW}$secondary_origin${NC}"
    echo -e "   🏷️ ID del Grupo: ${CYAN}$group_id${NC}"
    echo ""
    
    # Verificar que los orígenes existen en la distribución
    echo -e "${PURPLE}🔍 Verificando orígenes existentes...${NC}"
    
    local primary_exists=$(jq -r --arg origin_id "$primary_origin" '.DistributionConfig.Origins.Items[] | select(.Id == $origin_id) | .Id' "$config_file" 2>/dev/null)
    local secondary_exists=$(jq -r --arg origin_id "$secondary_origin" '.DistributionConfig.Origins.Items[] | select(.Id == $origin_id) | .Id' "$config_file" 2>/dev/null)
    
    if [ "$primary_exists" != "$primary_origin" ]; then
        echo -e "${RED}❌ Origen primario '$primary_origin' no existe en la distribución${NC}"
        return 1
    fi
    
    if [ "$secondary_exists" != "$secondary_origin" ]; then
        echo -e "${RED}❌ Origen secundario '$secondary_origin' no existe en la distribución${NC}"
        return 1
    fi
    
    echo -e "✅ Ambos orígenes verificados exitosamente"
    echo ""
    
    # Crear nueva configuración con Origin Group
    local updated_config_file="/tmp/cloudfront-updated-config-$distribution_id-$(date +%s).json"
    
    # Generar configuración de Origin Group
    local origin_group_json=$(create_origin_group_config "$primary_origin" "$secondary_origin" "$group_id")
    
    # Actualizar configuración añadiendo el Origin Group
    echo -e "${PURPLE}🔧 Actualizando configuración de distribución...${NC}"
    
    jq --argjson origin_group "$origin_group_json" '
        .DistributionConfig.OriginGroups.Quantity = (.DistributionConfig.OriginGroups.Quantity // 0) + 1 |
        .DistributionConfig.OriginGroups.Items = (.DistributionConfig.OriginGroups.Items // []) + [$origin_group] |
        del(.ETag)
    ' "$config_file" > "$updated_config_file"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error actualizando configuración${NC}"
        return 1
    fi
    
    echo -e "✅ Configuración actualizada generada"
    echo ""
    
    # Mostrar resumen de cambios
    echo -e "${CYAN}📊 RESUMEN DE CAMBIOS:${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "🔄 Se añadirá Origin Group con ID: ${BLUE}$group_id${NC}"
    echo -e "1️⃣ Origen Primario: ${GREEN}$primary_origin${NC} (traffic normal)"
    echo -e "2️⃣ Origen Secundario: ${YELLOW}$secondary_origin${NC} (failover automático)"
    echo -e "📊 Códigos de failover: ${CYAN}403, 404, 500, 502, 503, 504${NC}"
    echo -e "⚡ Failover: Automático cuando el origen primario falle"
    echo ""
    
    # Preguntar confirmación
    echo -e "${YELLOW}⚠️ Esta operación modificará la distribución CloudFront${NC}"
    echo -e "${YELLOW}💡 Los cambios pueden tomar 15-30 minutos en propagarse globalmente${NC}"
    echo ""
    read -p "¿Desea continuar con la configuración? (y/N): " confirmation
    
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}❌ Configuración cancelada por el usuario${NC}"
        return 1
    fi
    
    # Aplicar configuración
    echo -e "${PURPLE}🚀 Aplicando configuración de Origin Failover...${NC}"
    
    local update_result=$(aws cloudfront update-distribution \
        --id "$distribution_id" \
        --distribution-config file://"$updated_config_file" \
        --if-match "$etag" \
        --profile "$profile" \
        --output json 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Origin Failover configurado exitosamente${NC}"
        
        # Extraer información de la respuesta
        local new_etag=$(echo "$update_result" | jq -r '.ETag' 2>/dev/null)
        local status=$(echo "$update_result" | jq -r '.Distribution.Status' 2>/dev/null)
        local domain=$(echo "$update_result" | jq -r '.Distribution.DomainName' 2>/dev/null)
        
        echo -e "🏷️ Nuevo ETag: ${CYAN}$new_etag${NC}"
        echo -e "📊 Estado: ${GREEN}$status${NC}"
        echo -e "🌐 Dominio: ${BLUE}$domain${NC}"
        echo ""
        
        # Guardar configuración de respaldo
        local backup_file="cloudfront-backup-$distribution_id-$(date +%Y%m%d-%H%M%S).json"
        cp "$config_file" "$backup_file"
        echo -e "💾 Respaldo de configuración original: ${GREEN}$backup_file${NC}"
        echo ""
        
        echo -e "${GREEN}🎉 CONFIGURACIÓN COMPLETADA${NC}"
        echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "✅ Origin Failover habilitado para distribución ${BLUE}$distribution_id${NC}"
        echo -e "🔄 Tiempo de propagación: ${YELLOW}15-30 minutos${NC}"
        echo -e "📈 Alta disponibilidad: ${GREEN}ACTIVADA${NC}"
        echo ""
        
        return 0
    else
        echo -e "${RED}❌ Error aplicando configuración de Origin Failover${NC}"
        
        # Intentar obtener más información del error
        local error_info=$(aws cloudfront update-distribution \
            --id "$distribution_id" \
            --distribution-config file://"$updated_config_file" \
            --if-match "$etag" \
            --profile "$profile" 2>&1)
        
        echo -e "${RED}Error detallado: $error_info${NC}"
        return 1
    fi
}

# Función para crear un origen secundario
create_secondary_origin() {
    local profile="$1"
    local distribution_id="$2"
    local origin_id="$3"
    local domain_name="$4"
    local origin_path="${5:-}"
    
    echo -e "${PURPLE}🆕 Creando origen secundario...${NC}"
    
    # Obtener configuración actual
    local info_file="/tmp/cf-distribution-info-$distribution_id.txt"
    if [ ! -f "$info_file" ]; then
        echo -e "${RED}❌ Información de distribución no encontrada${NC}"
        return 1
    fi
    
    local config_info=$(cat "$info_file")
    IFS='|' read -r dist_id config_file etag <<< "$config_info"
    
    # Crear configuración del nuevo origen
    local new_origin_config=$(cat << EOF
{
    "Id": "$origin_id",
    "DomainName": "$domain_name",
    "OriginPath": "$origin_path",
    "CustomOriginConfig": {
        "HTTPPort": 80,
        "HTTPSPort": 443,
        "OriginProtocolPolicy": "https-only",
        "OriginSslProtocols": {
            "Quantity": 2,
            "Items": ["TLSv1.2", "TLSv1.3"]
        }
    }
}
EOF
)
    
    # Actualizar configuración añadiendo el nuevo origen
    local updated_config_file="/tmp/cloudfront-updated-config-origin-$distribution_id-$(date +%s).json"
    
    jq --argjson new_origin "$new_origin_config" '
        .DistributionConfig.Origins.Quantity = .DistributionConfig.Origins.Quantity + 1 |
        .DistributionConfig.Origins.Items = .DistributionConfig.Origins.Items + [$new_origin] |
        del(.ETag)
    ' "$config_file" > "$updated_config_file"
    
    echo -e "✅ Configuración de origen secundario creada:"
    echo -e "   🆔 ID: ${BLUE}$origin_id${NC}"
    echo -e "   🌐 Dominio: ${GREEN}$domain_name${NC}"
    echo -e "   📁 Ruta: ${CYAN}$origin_path${NC}"
    
    echo "$updated_config_file|$etag"
}

# Función para verificar estado de failover
verify_failover_status() {
    local profile="$1"
    local distribution_id="$2"
    
    echo -e "${PURPLE}🔍 Verificando estado de Origin Failover...${NC}"
    
    # Obtener configuración actual
    local current_config=$(aws cloudfront get-distribution-config \
        --id "$distribution_id" \
        --profile "$profile" \
        --output json 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error obteniendo configuración actual${NC}"
        return 1
    fi
    
    # Verificar Origin Groups
    local origin_groups=$(echo "$current_config" | jq -r '.DistributionConfig.OriginGroups.Items[]? | "\(.Id)|\(.Members.Items[0].OriginId)|\(.Members.Items[1].OriginId)|\(.FailoverCriteria.StatusCodes.Items | join(","))"' 2>/dev/null)
    
    local status=$(echo "$current_config" | jq -r '.Distribution.Status' 2>/dev/null)
    local last_modified=$(echo "$current_config" | jq -r '.Distribution.LastModifiedTime' 2>/dev/null)
    
    echo -e "📊 Estado de la distribución:"
    echo -e "   🆔 ID: ${BLUE}$distribution_id${NC}"
    echo -e "   📊 Estado: ${GREEN}$status${NC}"
    echo -e "   📅 Última modificación: ${CYAN}$last_modified${NC}"
    echo ""
    
    if [ -n "$origin_groups" ] && [ "$origin_groups" != "" ]; then
        echo -e "${GREEN}✅ Origin Failover CONFIGURADO${NC}"
        echo ""
        echo -e "🔄 ${CYAN}GRUPOS DE FAILOVER ACTIVOS:${NC}"
        echo "$origin_groups" | while IFS='|' read -r group_id primary secondary codes; do
            echo -e "   🏷️ Grupo: ${BLUE}$group_id${NC}"
            echo -e "   1️⃣ Primario: ${GREEN}$primary${NC}"
            echo -e "   2️⃣ Secundario: ${YELLOW}$secondary${NC}"
            echo -e "   📊 Códigos: ${CYAN}$codes${NC}"
            echo ""
        done
        
        if [ "$status" = "Deployed" ]; then
            echo -e "${GREEN}🎉 Failover ACTIVO y DESPLEGADO${NC}"
            echo -e "${BLUE}💡 La alta disponibilidad está completamente funcional${NC}"
        else
            echo -e "${YELLOW}⏳ Failover configurado, esperando despliegue...${NC}"
            echo -e "${BLUE}💡 Estado actual: $status${NC}"
        fi
    else
        echo -e "${RED}❌ Origin Failover NO configurado${NC}"
        echo -e "${YELLOW}💡 Esta distribución no tiene redundancia de orígenes${NC}"
    fi
    
    return 0
}

# Función para generar reporte de configuración
generate_failover_report() {
    local profile="$1"
    local output_file="cloudfront-failover-report-$(date +%Y%m%d-%H%M%S).json"
    
    echo -e "${PURPLE}📊 Generando reporte de configuración de failover...${NC}"
    
    # Obtener todas las distribuciones
    local distributions=$(aws cloudfront list-distributions \
        --profile "$profile" \
        --query 'DistributionList.Items[].Id' \
        --output text 2>/dev/null)
    
    if [ -z "$distributions" ]; then
        echo -e "${RED}❌ No se encontraron distribuciones${NC}"
        return 1
    fi
    
    # Crear estructura base del reporte
    cat > "$output_file" << EOF
{
    "report_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "account_id": "$ACCOUNT_ID",
    "profile": "$profile",
    "cloudfront_distributions": []
}
EOF
    
    # Analizar cada distribución
    local temp_report="/tmp/cf-temp-report-$$.json"
    echo "[]" > "$temp_report"
    
    echo "$distributions" | while read -r dist_id; do
        if [ -n "$dist_id" ]; then
            echo -e "   🔍 Analizando distribución ${CYAN}$dist_id${NC}..."
            
            # Obtener configuración de la distribución
            local dist_config=$(aws cloudfront get-distribution-config \
                --id "$dist_id" \
                --profile "$profile" \
                --output json 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                # Extraer información relevante
                local domain=$(echo "$dist_config" | jq -r '.Distribution.DomainName')
                local status=$(echo "$dist_config" | jq -r '.Distribution.Status')
                local enabled=$(echo "$dist_config" | jq -r '.DistributionConfig.Enabled')
                local origins_count=$(echo "$dist_config" | jq -r '.DistributionConfig.Origins.Quantity')
                local origin_groups_count=$(echo "$dist_config" | jq -r '.DistributionConfig.OriginGroups.Quantity // 0')
                
                # Determinar estado de failover
                local failover_status="disabled"
                if [ "$origin_groups_count" -gt 0 ]; then
                    failover_status="enabled"
                fi
                
                # Crear entrada del reporte
                local dist_report=$(cat << EOF
{
    "distribution_id": "$dist_id",
    "domain_name": "$domain",
    "status": "$status",
    "enabled": $enabled,
    "origins_count": $origins_count,
    "origin_groups_count": $origin_groups_count,
    "failover_status": "$failover_status",
    "high_availability": $([ "$origin_groups_count" -gt 0 ] && echo "true" || echo "false")
}
EOF
)
                
                # Añadir al reporte temporal
                jq --argjson dist "$dist_report" '. += [$dist]' "$temp_report" > "${temp_report}.new"
                mv "${temp_report}.new" "$temp_report"
            fi
        fi
    done
    
    # Combinar reporte final
    jq --slurpfile distributions "$temp_report" '.cloudfront_distributions = $distributions[0]' "$output_file" > "${output_file}.final"
    mv "${output_file}.final" "$output_file"
    
    # Limpiar archivos temporales
    rm -f "$temp_report"
    
    echo -e "✅ Reporte generado: ${GREEN}$output_file${NC}"
    
    # Mostrar resumen
    local total_distributions=$(jq -r '.cloudfront_distributions | length' "$output_file")
    local with_failover=$(jq -r '.cloudfront_distributions | map(select(.failover_status == "enabled")) | length' "$output_file")
    local without_failover=$(jq -r '.cloudfront_distributions | map(select(.failover_status == "disabled")) | length' "$output_file")
    
    echo ""
    echo -e "${CYAN}📊 RESUMEN DEL REPORTE:${NC}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "📋 Total distribuciones: ${BLUE}$total_distributions${NC}"
    echo -e "✅ Con failover habilitado: ${GREEN}$with_failover${NC}"
    echo -e "❌ Sin failover: ${RED}$without_failover${NC}"
    
    local coverage_percent=0
    if [ "$total_distributions" -gt 0 ]; then
        coverage_percent=$((with_failover * 100 / total_distributions))
    fi
    echo -e "📈 Cobertura de alta disponibilidad: ${CYAN}$coverage_percent%${NC}"
    
    if [ "$without_failover" -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}⚠️ RECOMENDACIONES:${NC}"
        echo -e "• Configurar Origin Failover para las $without_failover distribuciones restantes"
        echo -e "• Implementar monitoreo de salud de orígenes"
        echo -e "• Configurar alertas para failover automático"
        echo -e "• Revisar regularmente la configuración de redundancia"
    else
        echo ""
        echo -e "${GREEN}🎉 ¡Excelente! Todas las distribuciones tienen failover configurado${NC}"
    fi
    
    return 0
}

# Función para mostrar menú interactivo
show_interactive_menu() {
    local profile="$1"
    
    while true; do
        echo ""
        echo -e "${CYAN}🌐 MENÚ CLOUDFRONT ORIGIN FAILOVER${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━���━━━━━━━━━━━━━━━"
        echo -e "${BLUE}1.${NC} 📋 Listar distribuciones CloudFront"
        echo -e "${BLUE}2.${NC} 🔍 Analizar configuración de distribución específica"
        echo -e "${BLUE}3.${NC} 🔄 Configurar Origin Failover"
        echo -e "${BLUE}4.${NC} 🆕 Crear origen secundario"
        echo -e "${BLUE}5.${NC} ✅ Verificar estado de failover"
        echo -e "${BLUE}6.${NC} 📊 Generar reporte de configuraciones"
        echo -e "${BLUE}7.${NC} ❌ Salir"
        echo ""
        
        read -p "Seleccione una opción (1-7): " choice
        
        case $choice in
            1)
                echo ""
                get_cloudfront_distributions "$profile"
                ;;
            2)
                echo ""
                read -p "Ingrese el ID de la distribución: " dist_id
                if [ -n "$dist_id" ]; then
                    analyze_origin_configuration "$profile" "$dist_id"
                else
                    echo -e "${RED}❌ ID de distribución requerido${NC}"
                fi
                ;;
            3)
                echo ""
                read -p "ID de la distribución: " dist_id
                read -p "ID del origen primario: " primary_origin
                read -p "ID del origen secundario: " secondary_origin
                read -p "ID del grupo de failover (opcional): " group_id
                
                if [ -n "$dist_id" ] && [ -n "$primary_origin" ] && [ -n "$secondary_origin" ]; then
                    # Primero analizar para obtener configuración actual
                    analyze_origin_configuration "$profile" "$dist_id"
                    # Luego configurar failover
                    configure_origin_failover "$profile" "$dist_id" "$primary_origin" "$secondary_origin" "$group_id"
                else
                    echo -e "${RED}❌ Todos los campos son requeridos${NC}"
                fi
                ;;
            4)
                echo ""
                read -p "ID de la distribución: " dist_id
                read -p "ID del nuevo origen: " origin_id
                read -p "Dominio del origen: " domain_name
                read -p "Ruta del origen (opcional): " origin_path
                
                if [ -n "$dist_id" ] && [ -n "$origin_id" ] && [ -n "$domain_name" ]; then
                    # Analizar primero para obtener configuración
                    analyze_origin_configuration "$profile" "$dist_id"
                    create_secondary_origin "$profile" "$dist_id" "$origin_id" "$domain_name" "$origin_path"
                else
                    echo -e "${RED}❌ ID de distribución, ID de origen y dominio son requeridos${NC}"
                fi
                ;;
            5)
                echo ""
                read -p "ID de la distribución: " dist_id
                if [ -n "$dist_id" ]; then
                    verify_failover_status "$profile" "$dist_id"
                else
                    echo -e "${RED}❌ ID de distribución requerido${NC}"
                fi
                ;;
            6)
                echo ""
                generate_failover_report "$profile"
                ;;
            7)
                echo -e "${GREEN}👋 ¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}❌ Opción inválida. Seleccione 1-7.${NC}"
                ;;
        esac
        
        echo ""
        read -p "Presione Enter para continuar..."
    done
}

# Función principal de ejecución
main() {
    # Verificar si hay argumentos adicionales para ejecución no interactiva
    if [ $# -gt 2 ]; then
        local action="$3"
        case "$action" in
            "list")
                get_cloudfront_distributions "$PROFILE"
                ;;
            "analyze")
                if [ $# -ge 4 ]; then
                    analyze_origin_configuration "$PROFILE" "$4"
                else
                    echo -e "${RED}❌ ID de distribución requerido para análisis${NC}"
                    exit 1
                fi
                ;;
            "configure")
                if [ $# -ge 6 ]; then
                    local dist_id="$4"
                    local primary="$5"
                    local secondary="$6"
                    local group_id="${7:-failover-group-$(date +%s)}"
                    
                    analyze_origin_configuration "$PROFILE" "$dist_id"
                    configure_origin_failover "$PROFILE" "$dist_id" "$primary" "$secondary" "$group_id"
                else
                    echo -e "${RED}❌ Parámetros insuficientes para configuración${NC}"
                    echo "Uso: $0 $PROFILE $REGION configure <dist_id> <primary_origin> <secondary_origin> [group_id]"
                    exit 1
                fi
                ;;
            "verify")
                if [ $# -ge 4 ]; then
                    verify_failover_status "$PROFILE" "$4"
                else
                    echo -e "${RED}❌ ID de distribución requerido para verificación${NC}"
                    exit 1
                fi
                ;;
            "report")
                generate_failover_report "$PROFILE"
                ;;
            *)
                echo -e "${RED}❌ Acción no reconocida: $action${NC}"
                echo "Acciones disponibles: list, analyze, configure, verify, report"
                exit 1
                ;;
        esac
    else
        # Modo interactivo
        show_interactive_menu "$PROFILE"
    fi
}

# Ejecutar función principal
main "$@"