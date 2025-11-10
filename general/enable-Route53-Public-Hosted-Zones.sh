#!/bin/bash
# enable-route53-logging.sh
# Habilita Route53 Query Logging en todas las Hosted Zones públicas
# Perfil: xxxxxx | Región: us-east-1

PROFILE="azcenit"
REGION="us-east-1"

# CloudWatch Log Group para Route53 Query Logs
LOG_GROUP_PREFIX="/aws/route53"

echo "=== Habilitando Route53 Query Logging en todas las Hosted Zones públicas ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Log Group Prefix: $LOG_GROUP_PREFIX"
echo

# Obtener Account ID
ACCOUNT_ID=$(wsl aws sts get-caller-identity --profile $PROFILE --query Account --output text)
echo "✔ Account ID: $ACCOUNT_ID"

# Listar todas las hosted zones públicas
echo
echo "🔍 Obteniendo hosted zones públicas..."
ZONES_DATA=$(wsl aws route53 list-hosted-zones \
    --profile $PROFILE \
    --query 'HostedZones[?Config.PrivateZone==`false`].[Id,Name,ResourceRecordSetCount]' \
    --output text 2>/dev/null)

if [ -z "$ZONES_DATA" ]; then
    echo "ℹ No se encontraron hosted zones públicas en la cuenta"
    echo "=== Proceso completado ==="
    exit 0
fi

# Contar zonas encontradas
ZONE_COUNT=$(echo "$ZONES_DATA" | wc -l)
echo "✔ Encontradas $ZONE_COUNT hosted zones públicas"
echo

# Mostrar zonas encontradas
echo "Hosted zones públicas encontradas:"
echo "$ZONES_DATA" | while read -r zone_id zone_name record_count; do
    clean_zone_id=$(echo "$zone_id" | sed 's|/hostedzone/||')
    echo "  • ID: $clean_zone_id | Dominio: $zone_name | Records: $record_count"
done

echo
echo "🔧 Configurando Query Logging para cada hosted zone..."

# Procesar cada zona
echo "$ZONES_DATA" | while read -r zone_id zone_name record_count; do
    # Limpiar el ID de la zona (remover /hostedzone/ si existe)
    clean_zone_id=$(echo "$zone_id" | sed 's|/hostedzone/||')
    clean_zone_name=$(echo "$zone_name" | sed 's/\.$//')  # Remover punto final
    
    echo
    echo "📋 Procesando zona: $clean_zone_name ($clean_zone_id)"
    
    # Crear CloudWatch Log Group específico para esta zona
    log_group_name="$LOG_GROUP_PREFIX/$clean_zone_name"
    
    echo "  🔹 Creando CloudWatch Log Group: $log_group_name"
    wsl aws logs create-log-group \
        --log-group-name "$log_group_name" \
        --region $REGION \
        --profile $PROFILE 2>/dev/null && \
    echo "    ✔ Log Group creado exitosamente" || \
    echo "    ℹ Log Group ya existe o se creó automáticamente"
    
    # Configurar retención de logs (30 días por defecto)
    echo "  🔹 Configurando retención de logs (30 días)..."
    wsl aws logs put-retention-policy \
        --log-group-name "$log_group_name" \
        --retention-in-days 30 \
        --region $REGION \
        --profile $PROFILE 2>/dev/null && \
    echo "    ✔ Retención configurada" || \
    echo "    ⚠ No se pudo configurar retención"
    
    # Construir ARN del log group
    log_group_arn="arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$log_group_name"
    
    # Verificar si ya existe configuración de logging para esta zona
    existing_config=$(wsl aws route53 list-query-logging-configs \
        --hosted-zone-id "$clean_zone_id" \
        --profile $PROFILE \
        --query 'QueryLoggingConfigs[0].Id' \
        --output text 2>/dev/null)
    
    if [ "$existing_config" != "None" ] && [ -n "$existing_config" ]; then
        echo "  ℹ Ya existe configuración de logging para esta zona: $existing_config"
    else
        # Habilitar query logging
        echo "  🔹 Habilitando Route53 Query Logging..."
        create_result=$(wsl aws route53 create-query-logging-config \
            --hosted-zone-id "$clean_zone_id" \
            --cloud-watch-logs-log-group-arn "$log_group_arn" \
            --profile $PROFILE \
            --output json 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            config_id=$(echo "$create_result" | grep -o '"Id":"[^"]*"' | cut -d'"' -f4)
            echo "    ✔ Query Logging habilitado exitosamente"
            echo "    📄 Config ID: $config_id"
        else
            echo "    ❌ Error al habilitar Query Logging"
        fi
    fi
    
    echo "  ✔ Procesamiento completado para $clean_zone_name"
done

echo
echo "📊 INFORMACIÓN SOBRE LOS LOGS"
echo "============================="
echo "📍 Ubicación: CloudWatch Logs"
echo "📁 Log Groups: $LOG_GROUP_PREFIX/<domain-name>"
echo "🕒 Retención: 30 días"
echo "💰 Costo: Se aplican tarifas estándar de CloudWatch Logs"
echo
echo "📝 TIPOS DE CONSULTAS REGISTRADAS:"
echo "=================================="
echo "✔ Consultas DNS entrantes (queries)"
echo "✔ Respuestas DNS (responses)"
echo "✔ Dirección IP del cliente"
echo "✔ Timestamp de la consulta"
echo "✔ Tipo de registro solicitado"
echo "✔ Código de respuesta"
echo

echo "🔧 COMANDOS ÚTILES PARA ANÁLISIS:"
echo "================================="
echo
echo "# Ver logs en tiempo real de un dominio específico:"
echo "wsl aws logs tail '$LOG_GROUP_PREFIX/<domain-name>' --follow --region $REGION --profile $PROFILE"
echo
echo "# Buscar consultas por IP específica:"
echo "wsl aws logs filter-log-events \\"
echo "    --log-group-name '$LOG_GROUP_PREFIX/<domain-name>' \\"
echo "    --filter-pattern '{ \$.sourceip = \"192.168.1.1\" }' \\"
echo "    --region $REGION --profile $PROFILE"
echo
echo "# Buscar consultas por tipo de registro:"
echo "wsl aws logs filter-log-events \\"
echo "    --log-group-name '$LOG_GROUP_PREFIX/<domain-name>' \\"
echo "    --filter-pattern '{ \$.querytype = \"A\" }' \\"
echo "    --region $REGION --profile $PROFILE"
echo
echo "# Listar todas las configuraciones de logging activas:"
echo "wsl aws route53 list-query-logging-configs --profile $PROFILE"

echo
echo "✅ Route53 Query Logging configurado exitosamente"
echo
echo "CONFIGURACIÓN COMPLETADA:"
echo "========================"
echo "🌐 Hosted Zones Procesadas: $ZONE_COUNT"
echo "📋 Log Groups Creados: Uno por cada dominio"
echo "🕒 Retención: 30 días"
echo "📊 Monitoreo: Disponible en CloudWatch"
echo
echo "PRÓXIMOS PASOS:"
echo "==============="
echo "1. 📊 Revisar logs en CloudWatch después de unos minutos"
echo "2. 🚨 Configurar alertas para patrones sospechosos"
echo "3. 📈 Crear métricas personalizadas basadas en logs"
echo "4. 🔍 Analizar patrones de tráfico DNS regularmente"
echo
echo "⚠️  NOTA IMPORTANTE:"
echo "Los logs pueden tardar hasta 5 minutos en aparecer"
echo "después de habilitar la funcionalidad."
echo
echo "=== Proceso completado ==="

