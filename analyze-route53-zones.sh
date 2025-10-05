#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
PROFILE="ancla"
REGION="us-east-1"

echo "=== ANÁLISIS COMPLETO DE ROUTE53 HOSTED ZONES ==="
echo "Proveedor: $PROVIDER"
echo "Perfil: $PROFILE"
echo "Región: $REGION"
echo

# Obtener información de la cuenta
ACCOUNT_ID=$(wsl aws sts get-caller-identity --profile $PROFILE --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"

# Función para listar todas las hosted zones
list_all_zones() {
    echo
    echo "🔍 ANÁLISIS COMPLETO DE HOSTED ZONES"
    echo "==================================="
    
    # Obtener todas las hosted zones
    all_zones=$(wsl aws route53 list-hosted-zones \
        --profile $PROFILE \
        --query 'HostedZones[].[Id,Name,Config.PrivateZone,ResourceRecordSetCount]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$all_zones" ]; then
        echo "ℹ No se encontraron hosted zones en la cuenta"
        return
    fi
    
    # Contar zonas por tipo
    total_zones=$(echo "$all_zones" | wc -l)
    public_zones=$(echo "$all_zones" | grep -c "False" || echo "0")
    private_zones=$(echo "$all_zones" | grep -c "True" || echo "0")
    
    echo "📊 RESUMEN DE HOSTED ZONES:"
    echo "  Total: $total_zones"
    echo "  Públicas: $public_zones"
    echo "  Privadas: $private_zones"
    echo
    
    if [ "$public_zones" -gt 0 ]; then
        echo "🌐 HOSTED ZONES PÚBLICAS:"
        echo "$all_zones" | grep "False" | while read -r zone_id zone_name is_private record_count; do
            clean_zone_id=$(echo "$zone_id" | sed 's|/hostedzone/||')
            clean_zone_name=$(echo "$zone_name" | sed 's/\.$//')
            echo "  • Dominio: $clean_zone_name"
            echo "    ID: $clean_zone_id"
            echo "    Records: $record_count"
            
            # Verificar si ya tiene logging habilitado
            logging_config=$(wsl aws route53 list-query-logging-configs \
                --hosted-zone-id "$clean_zone_id" \
                --profile $PROFILE \
                --query 'QueryLoggingConfigs[0].Id' \
                --output text 2>/dev/null || echo "None")
            
            if [ "$logging_config" != "None" ] && [ -n "$logging_config" ]; then
                echo "    ✔ Query Logging: HABILITADO (Config: $logging_config)"
            else
                echo "    ❌ Query Logging: NO HABILITADO"
            fi
            echo
        done
    fi
    
    if [ "$private_zones" -gt 0 ]; then
        echo "🔒 HOSTED ZONES PRIVADAS:"
        echo "$all_zones" | grep "True" | while read -r zone_id zone_name is_private record_count; do
            clean_zone_id=$(echo "$zone_id" | sed 's|/hostedzone/||')
            clean_zone_name=$(echo "$zone_name" | sed 's/\.$//')
            echo "  • Dominio: $clean_zone_name (Privada)"
            echo "    ID: $clean_zone_id"
            echo "    Records: $record_count"
            echo
        done
    fi
}

# Función para verificar configuraciones de logging existentes
check_existing_logging() {
    echo
    echo "📋 CONFIGURACIONES DE LOGGING EXISTENTES"
    echo "========================================"
    
    logging_configs=$(wsl aws route53 list-query-logging-configs \
        --profile $PROFILE \
        --output json 2>/dev/null || echo "{\"QueryLoggingConfigs\":[]}")
    
    config_count=$(echo "$logging_configs" | grep -o '"Id"' | wc -l || echo "0")
    
    if [ "$config_count" -eq 0 ]; then
        echo "ℹ No hay configuraciones de Query Logging activas"
    else
        echo "✔ Encontradas $config_count configuraciones de logging activas:"
        echo
        echo "$logging_configs" | grep -E '"Id"|"HostedZoneId"|"CloudWatchLogsLogGroupArn"' | \
        sed 's/.*"Id": *"\([^"]*\)".*/Config ID: \1/' | \
        sed 's/.*"HostedZoneId": *"\([^"]*\)".*/  Zone ID: \1/' | \
        sed 's/.*"CloudWatchLogsLogGroupArn": *"\([^"]*\)".*/  Log Group: \1/' || \
        echo "  (Detalles no disponibles)"
    fi
}

# Función para mostrar CloudWatch Log Groups relacionados
check_cloudwatch_logs() {
    echo
    echo "📊 CLOUDWATCH LOG GROUPS DE ROUTE53"
    echo "==================================="
    
    route53_logs=$(wsl aws logs describe-log-groups \
        --log-group-name-prefix "/aws/route53" \
        --region $REGION \
        --profile $PROFILE \
        --query 'logGroups[].{Name:logGroupName,Size:storedBytes,Retention:retentionInDays}' \
        --output table 2>/dev/null || echo "No se encontraron log groups")
    
    if [ "$route53_logs" != "No se encontraron log groups" ]; then
        echo "$route53_logs"
    else
        echo "ℹ No se encontraron log groups de Route53 en CloudWatch"
    fi
}

# Función para mostrar métricas disponibles
show_available_metrics() {
    echo
    echo "📈 MÉTRICAS DE CLOUDWATCH DISPONIBLES"
    echo "==================================="
    echo "Una vez habilitado el logging, estarán disponibles:"
    echo "• Namespace: AWS/Route53Resolver (para queries)"
    echo "• Métricas personalizadas basadas en logs"
    echo "• Filtros de métricas para patrones específicos"
    echo
    echo "Ejemplos de métricas útiles:"
    echo "• Número de queries por dominio"
    echo "• Queries por tipo de registro (A, AAAA, MX, etc.)"
    echo "• Queries por ubicación geográfica"
    echo "• Errores de DNS (NXDOMAIN, SERVFAIL)"
}

# Ejecutar análisis
list_all_zones
check_existing_logging
check_cloudwatch_logs
show_available_metrics

echo
echo "🛠️ ACCIONES RECOMENDADAS"
echo "========================"
echo "1. 📝 Si no tienes hosted zones públicas:"
echo "   - Crea hosted zones para tus dominios"
echo "   - Ejecuta './enable-Route53-Public-Hosted-Zones.sh' después"
echo
echo "2. 🔧 Si tienes hosted zones sin logging:"
echo "   - Ejecuta './enable-Route53-Public-Hosted-Zones.sh'"
echo "   - Verifica la configuración en CloudWatch"
echo
echo "3. 📊 Para monitoreo avanzado:"
echo "   - Configura dashboards en CloudWatch"
echo "   - Crea alertas para patrones sospechosos"
echo "   - Implementa análisis de tráfico DNS"

echo
echo "🔧 COMANDOS ÚTILES"
echo "=================="
echo
echo "# Crear una hosted zone pública (ejemplo):"
echo "wsl aws route53 create-hosted-zone \\"
echo "    --name 'example.com' \\"
echo "    --caller-reference \$(date +%s) \\"
echo "    --profile $PROFILE"
echo
echo "# Ver logs en tiempo real:"
echo "wsl aws logs tail '/aws/route53/<domain>' --follow --region $REGION --profile $PROFILE"
echo
echo "# Listar todas las configuraciones de logging:"
echo "wsl aws route53 list-query-logging-configs --profile $PROFILE"
echo
echo "# Deshabilitar logging para una zona:"
echo "wsl aws route53 delete-query-logging-config --id <config-id> --profile $PROFILE"

echo
echo "✅ Análisis de Route53 Hosted Zones completado"
echo
echo "ESTADO ACTUAL:"
echo "=============="
if list_all_zones | grep -q "HOSTED ZONES PÚBLICAS"; then
    echo "🌐 Hay hosted zones públicas configuradas"
    if check_existing_logging | grep -q "configuraciones de logging activas"; then
        echo "✔ Query Logging está habilitado"
        echo "🎯 Estado: ÓPTIMO"
    else
        echo "⚠ Query Logging NO está habilitado"
        echo "🎯 Estado: REQUIERE CONFIGURACIÓN"
    fi
else
    echo "ℹ No hay hosted zones públicas"
    echo "🎯 Estado: SIN DOMINIOS PÚBLICOS"
fi

echo
echo "=== Proceso completado ==="