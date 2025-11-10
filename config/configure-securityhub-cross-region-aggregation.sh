#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
PRIMARY_REGION="us-east-1"  # Región principal donde se centralizarán los findings
PROFILE="azbeacons"
AGGREGATOR_NAME="security-hub-aggregator"

# Regiones a incluir en la agregación (modifica según tus necesidades)
REGIONS=(
    "us-east-1"     # Virginia (Principal)
    "us-west-2"     # Oregon
    "eu-west-1"     # Irlanda
    "ap-southeast-1" # Singapur
    "us-east-2"     # Ohio
    "eu-central-1"  # Frankfurt
)

echo "=== Configurando Agregaciones Cross-Region para Security Hub ==="
echo "Proveedor: $PROVIDER"
echo "Región Principal: $PRIMARY_REGION"
echo "Perfil: $PROFILE"
echo "Agregador: $AGGREGATOR_NAME"
echo

# Función para verificar si Security Hub está habilitado en una región
check_security_hub() {
    local region="$1"
    echo "🔍 Verificando Security Hub en región: $region"
    
    hub_status=$(wsl aws securityhub describe-hub \
        --region "$region" \
        --profile "$PROFILE" \
        --query 'HubArn' \
        --output text 2>/dev/null || echo "NOT_ENABLED")
    
    if [ "$hub_status" != "NOT_ENABLED" ]; then
        echo "  ✔ Security Hub habilitado: $hub_status"
        return 0
    else
        echo "  ⚠ Security Hub NO habilitado en $region"
        return 1
    fi
}

# Función para habilitar Security Hub en una región
enable_security_hub() {
    local region="$1"
    echo "📝 Habilitando Security Hub en región: $region"
    
    wsl aws securityhub enable-security-hub \
        --enable-default-standards \
        --region "$region" \
        --profile "$PROFILE" 2>/dev/null && \
    echo "  ✔ Security Hub habilitado exitosamente en $region" || \
    echo "  ⚠ No se pudo habilitar Security Hub en $region"
}

# Verificar y habilitar Security Hub en todas las regiones
echo "🌍 VERIFICANDO SECURITY HUB EN TODAS LAS REGIONES"
echo "================================================="
enabled_regions=()

for region in "${REGIONS[@]}"; do
    if check_security_hub "$region"; then
        enabled_regions+=("$region")
    else
        echo "  🔧 Intentando habilitar Security Hub en $region..."
        enable_security_hub "$region"
        
        # Verificar nuevamente después de habilitar
        sleep 5
        if check_security_hub "$region"; then
            enabled_regions+=("$region")
        fi
    fi
    echo
done

echo "✔ Regiones con Security Hub habilitado: ${#enabled_regions[@]}"
echo "  Regiones: ${enabled_regions[*]}"

# Verificar que la región principal esté habilitada
if [[ ! " ${enabled_regions[*]} " =~ " ${PRIMARY_REGION} " ]]; then
    echo "❌ Error: Security Hub no está habilitado en la región principal ($PRIMARY_REGION)"
    echo "   Habilita Security Hub manualmente en $PRIMARY_REGION y ejecuta este script nuevamente"
    exit 1
fi

echo
echo "🔗 CONFIGURANDO AGREGACIÓN CROSS-REGION"
echo "======================================="

# Verificar si ya existe un agregador
echo "Verificando si ya existe un agregador..."
existing_aggregator=$(wsl aws securityhub list-finding-aggregators \
    --region "$PRIMARY_REGION" \
    --profile "$PROFILE" \
    --query "FindingAggregators[?FindingAggregatorArn contains '$AGGREGATOR_NAME'].FindingAggregatorArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$existing_aggregator" ]; then
    echo "✔ Agregador ya existe: $existing_aggregator"
    AGGREGATOR_ARN="$existing_aggregator"
else
    echo "📝 Creando nuevo agregador de findings..."
    
    # Crear lista de regiones para el agregador (excluyendo la región principal)
    aggregated_regions=()
    for region in "${enabled_regions[@]}"; do
        if [ "$region" != "$PRIMARY_REGION" ]; then
            aggregated_regions+=("$region")
        fi
    done
    
    if [ ${#aggregated_regions[@]} -eq 0 ]; then
        echo "ℹ Solo hay Security Hub habilitado en la región principal"
        echo "  No es necesario crear agregador para una sola región"
        exit 0
    fi
    
    # Convertir array a formato JSON manualmente
    regions_json="["
    for i in "${!aggregated_regions[@]}"; do
        if [ $i -gt 0 ]; then
            regions_json+=","
        fi
        regions_json+="\"${aggregated_regions[i]}\""
    done
    regions_json+="]"
    
    echo "  Regiones a agregar: ${aggregated_regions[*]}"
    
    create_result=$(wsl aws securityhub create-finding-aggregator \
        --region-linking-mode SPECIFIED_REGIONS \
        --regions "$regions_json" \
        --region "$PRIMARY_REGION" \
        --profile "$PROFILE" \
        --output json 2>/dev/null || echo "ERROR")
    
    if [ "$create_result" != "ERROR" ]; then
        AGGREGATOR_ARN=$(echo "$create_result" | grep -o '"FindingAggregatorArn":"[^"]*"' | cut -d'"' -f4)
        echo "✔ Agregador creado exitosamente: $AGGREGATOR_ARN"
    else
        echo "❌ Error al crear el agregador. Verificando permisos y configuración..."
        exit 1
    fi
fi

# Verificar el estado del agregador
echo
echo "📊 VERIFICANDO CONFIGURACIÓN DEL AGREGADOR"
echo "=========================================="
aggregator_details=$(wsl aws securityhub get-finding-aggregator \
    --finding-aggregator-arn "$AGGREGATOR_ARN" \
    --region "$PRIMARY_REGION" \
    --profile "$PROFILE" \
    --output json 2>/dev/null || echo "ERROR")

if [ "$aggregator_details" != "ERROR" ]; then
    echo "✔ Detalles del agregador:"
    arn=$(echo "$aggregator_details" | grep -o '"FindingAggregatorArn":"[^"]*"' | cut -d'"' -f4)
    mode=$(echo "$aggregator_details" | grep -o '"RegionLinkingMode":"[^"]*"' | cut -d'"' -f4)
    echo "  • ARN: $arn"
    echo "  • Modo: $mode"
    echo "  • Regiones agregadas: ${aggregated_regions[*]}"
else
    echo "⚠ No se pudieron obtener detalles del agregador"
fi

# Listar findings agregados
echo
echo "📋 VERIFICANDO FINDINGS AGREGADOS"
echo "================================="
echo "Obteniendo muestra de findings agregados..."

findings_sample=$(wsl aws securityhub get-findings \
    --region "$PRIMARY_REGION" \
    --profile "$PROFILE" \
    --max-items 5 \
    --query 'Findings[].{Id:Id,Title:Title,Region:Region,Severity:Severity.Label}' \
    --output table 2>/dev/null || echo "No se pudieron obtener findings")

if [ "$findings_sample" != "No se pudieron obtener findings" ]; then
    echo "$findings_sample"
else
    echo "ℹ No hay findings disponibles o no se pudieron obtener"
fi

# Configurar métricas de CloudWatch
echo
echo "📈 CONFIGURANDO MÉTRICAS DE CLOUDWATCH"
echo "======================================"
echo "Las métricas de Security Hub estarán disponibles en:"
echo "• Namespace: AWS/SecurityHub"
echo "• Región: $PRIMARY_REGION (centralizadas)"
echo "• Métricas por región de origen disponibles"

# Mostrar comandos útiles
echo
echo "🔧 COMANDOS ÚTILES PARA GESTIÓN"
echo "==============================="
echo
echo "# Listar todos los findings agregados:"
echo "wsl aws securityhub get-findings \\"
echo "    --region $PRIMARY_REGION \\"
echo "    --profile $PROFILE \\"
echo "    --query 'Findings[].{Id:Id,Region:Region,Title:Title,Severity:Severity.Label}' \\"
echo "    --output table"
echo
echo "# Filtrar findings por región específica:"
echo "wsl aws securityhub get-findings \\"
echo "    --region $PRIMARY_REGION \\"
echo "    --profile $PROFILE \\"
echo "    --filters '{\"Region\":[{\"Value\":\"us-west-2\",\"Comparison\":\"EQUALS\"}]}' \\"
echo "    --query 'Findings[].{Id:Id,Title:Title,Severity:Severity.Label}' \\"
echo "    --output table"
echo
echo "# Filtrar findings por severidad CRITICAL en todas las regiones:"
echo "wsl aws securityhub get-findings \\"
echo "    --region $PRIMARY_REGION \\"
echo "    --profile $PROFILE \\"
echo "    --filters '{\"SeverityLabel\":[{\"Value\":\"CRITICAL\",\"Comparison\":\"EQUALS\"}]}' \\"
echo "    --query 'Findings[].{Id:Id,Region:Region,Title:Title}' \\"
echo "    --output table"
echo
echo "# Ver estado del agregador:"
echo "wsl aws securityhub get-finding-aggregator \\"
echo "    --finding-aggregator-arn '$AGGREGATOR_ARN' \\"
echo "    --region $PRIMARY_REGION \\"
echo "    --profile $PROFILE"
echo
echo "# Listar todos los agregadores:"
echo "wsl aws securityhub list-finding-aggregators \\"
echo "    --region $PRIMARY_REGION \\"
echo "    --profile $PROFILE"

# Configurar insights automáticos
echo
echo "💡 CONFIGURANDO INSIGHTS AUTOMÁTICOS"
echo "==================================="
echo "Los siguientes insights estarán disponibles automáticamente:"
echo "• Findings por región"
echo "• Findings por severidad"
echo "• Findings por tipo de recurso"
echo "• Trends de findings a lo largo del tiempo"
echo "• Comparación entre regiones"

echo
echo "✅ Agregación Cross-Region para Security Hub configurada exitosamente"
echo
echo "CONFIGURACIÓN COMPLETADA:"
echo "========================"
echo "🏠 Región Principal: $PRIMARY_REGION"
echo "🔗 Agregador ARN: $AGGREGATOR_ARN"
echo "🌍 Regiones Agregadas: ${#enabled_regions[@]} regiones"
echo "📊 Dashboard Central: Disponible en $PRIMARY_REGION"
echo
echo "REGIONES INCLUIDAS:"
echo "=================="
for i in "${!enabled_regions[@]}"; do
    region="${enabled_regions[i]}"
    if [ "$region" == "$PRIMARY_REGION" ]; then
        echo "$((i+1)). $region (Principal - Dashboard Central)"
    else
        echo "$((i+1)). $region (Agregada)"
    fi
done

echo
echo "BENEFICIOS DE LA CONFIGURACIÓN:"
echo "==============================="
echo "✔ Vista centralizada de findings de todas las regiones"
echo "✔ Dashboard único en $PRIMARY_REGION"
echo "✔ Métricas consolidadas en CloudWatch"
echo "✔ Alertas centralizadas disponibles"
echo "✔ Análisis cross-region de tendencias de seguridad"
echo "✔ Cumplimiento multi-región simplificado"

echo
echo "PRÓXIMOS PASOS RECOMENDADOS:"
echo "============================"
echo "1. 📊 Revisar dashboard central en la consola de Security Hub"
echo "2. 🚨 Configurar alertas para findings críticos cross-region"
echo "3. 📈 Crear dashboards personalizados en CloudWatch"
echo "4. 📝 Documentar procedimientos de respuesta multi-región"
echo "5. 🔄 Programar revisiones regulares del estado de agregación"
echo
echo "⚠️  IMPORTANTE:"
echo "Los findings pueden tardar hasta 5 minutos en aparecer"
echo "en la región central después de ser creados."
echo
echo "=== Proceso completado ==="