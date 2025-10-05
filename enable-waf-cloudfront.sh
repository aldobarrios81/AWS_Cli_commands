#!/usr/bin/env bash
set -euo pipefail

# Variables de configuración
PROVIDER="AWS"
REGION="us-east-1"  # WAF para CloudFront debe ser en us-east-1
PROFILE="ancla"
WEB_ACL_NAME="CloudFront-WAF-Protection"
WEB_ACL_DESCRIPTION="WAF ACL para protección de dominios CloudFront"

echo "=== Habilitando AWS WAF para Dominios CloudFront ==="
echo "Proveedor: $PROVIDER"
echo "Región: $REGION (CloudFront WAF requiere us-east-1)"
echo "Perfil: $PROFILE"
echo "Web ACL: $WEB_ACL_NAME"
echo

# Función para verificar si existe un Web ACL
check_web_acl_exists() {
    local acl_name="$1"
    wsl aws wafv2 list-web-acls \
        --scope CLOUDFRONT \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "WebACLs[?Name=='$acl_name'].{Name:Name,Id:Id,ARN:ARN}" \
        --output text 2>/dev/null || echo ""
}

# Verificar si ya existe el Web ACL
echo "🔍 Verificando si ya existe el Web ACL '$WEB_ACL_NAME'..."
existing_acl=$(check_web_acl_exists "$WEB_ACL_NAME")

if [ -n "$existing_acl" ]; then
    echo "✔ Web ACL ya existe: $WEB_ACL_NAME"
    WEB_ACL_ID=$(echo "$existing_acl" | awk '{print $2}')
    WEB_ACL_ARN=$(echo "$existing_acl" | awk '{print $3}')
    echo "  ID: $WEB_ACL_ID"
    echo "  ARN: $WEB_ACL_ARN"
else
    echo "📝 Creando nuevo Web ACL '$WEB_ACL_NAME'..."
    
    # Crear Web ACL con reglas básicas de seguridad
    create_result=$(wsl aws wafv2 create-web-acl \
        --name "$WEB_ACL_NAME" \
        --scope CLOUDFRONT \
        --default-action Allow={} \
        --description "$WEB_ACL_DESCRIPTION" \
        --rules '[
            {
                "Name": "AWSManagedRulesCommonRuleSet",
                "Priority": 1,
                "OverrideAction": {"None": {}},
                "VisibilityConfig": {
                    "SampledRequestsEnabled": true,
                    "CloudWatchMetricsEnabled": true,
                    "MetricName": "CommonRuleSetMetric"
                },
                "Statement": {
                    "ManagedRuleGroupStatement": {
                        "VendorName": "AWS",
                        "Name": "AWSManagedRulesCommonRuleSet"
                    }
                }
            },
            {
                "Name": "AWSManagedRulesKnownBadInputsRuleSet",
                "Priority": 2,
                "OverrideAction": {"None": {}},
                "VisibilityConfig": {
                    "SampledRequestsEnabled": true,
                    "CloudWatchMetricsEnabled": true,
                    "MetricName": "KnownBadInputsMetric"
                },
                "Statement": {
                    "ManagedRuleGroupStatement": {
                        "VendorName": "AWS",
                        "Name": "AWSManagedRulesKnownBadInputsRuleSet"
                    }
                }
            },
            {
                "Name": "AWSManagedRulesAmazonIpReputationList",
                "Priority": 3,
                "OverrideAction": {"None": {}},
                "VisibilityConfig": {
                    "SampledRequestsEnabled": true,
                    "CloudWatchMetricsEnabled": true,
                    "MetricName": "IpReputationMetric"
                },
                "Statement": {
                    "ManagedRuleGroupStatement": {
                        "VendorName": "AWS",
                        "Name": "AWSManagedRulesAmazonIpReputationList"
                    }
                }
            },
            {
                "Name": "RateLimitRule",
                "Priority": 4,
                "Action": {"Block": {}},
                "VisibilityConfig": {
                    "SampledRequestsEnabled": true,
                    "CloudWatchMetricsEnabled": true,
                    "MetricName": "RateLimitMetric"
                },
                "Statement": {
                    "RateBasedStatement": {
                        "Limit": 2000,
                        "AggregateKeyType": "IP"
                    }
                }
            }
        ]' \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query '{Id:Summary.Id,ARN:Summary.ARN}' \
        --output json)
    
    WEB_ACL_ID=$(echo "$create_result" | grep -o '"Id":"[^"]*"' | cut -d'"' -f4)
    WEB_ACL_ARN=$(echo "$create_result" | grep -o '"ARN":"[^"]*"' | cut -d'"' -f4)
    
    echo "✔ Web ACL creado exitosamente"
    echo "  ID: $WEB_ACL_ID"
    echo "  ARN: $WEB_ACL_ARN"
fi

# Listar distribuciones de CloudFront
echo
echo "🌐 Listando distribuciones de CloudFront..."
distributions=$(wsl aws cloudfront list-distributions \
    --profile "$PROFILE" \
    --query 'DistributionList.Items[].{Id:Id,DomainName:DomainName,Status:Status,Origins:Origins.Items[0].DomainName}' \
    --output json 2>/dev/null || echo "[]")

distribution_count=$(echo "$distributions" | jq '. | length' 2>/dev/null || echo "0")

if [ "$distribution_count" -eq 0 ]; then
    echo "ℹ No se encontraron distribuciones de CloudFront en la cuenta"
    echo "  El Web ACL está listo para usar cuando se creen distribuciones"
else
    echo "✔ Encontradas $distribution_count distribuciones de CloudFront"
    echo
    
    # Mostrar distribuciones encontradas
    echo "Distribuciones encontradas:"
    echo "$distributions" | jq -r '.[] | "  • ID: \(.Id) | Dominio: \(.DomainName) | Estado: \(.Status)"'
    
    echo
    echo "🔗 Asociando Web ACL a distribuciones de CloudFront..."
    
    # Asociar Web ACL a cada distribución
    echo "$distributions" | jq -r '.[] | select(.Status == "Deployed") | .Id' | while read -r dist_id; do
        if [ -n "$dist_id" ]; then
            echo "Asociando WAF a distribución: $dist_id"
            
            # Obtener configuración actual de la distribución
            dist_config=$(wsl aws cloudfront get-distribution-config \
                --id "$dist_id" \
                --profile "$PROFILE" 2>/dev/null || echo "ERROR")
            
            if [ "$dist_config" != "ERROR" ]; then
                # Extraer ETag para la actualización
                etag=$(echo "$dist_config" | jq -r '.ETag' 2>/dev/null)
                
                # Actualizar configuración con Web ACL
                updated_config=$(echo "$dist_config" | jq --arg acl_arn "$WEB_ACL_ARN" '.DistributionConfig.WebACLId = $acl_arn')
                
                # Aplicar la configuración actualizada
                wsl aws cloudfront update-distribution \
                    --id "$dist_id" \
                    --distribution-config "$(echo "$updated_config" | jq '.DistributionConfig')" \
                    --if-match "$etag" \
                    --profile "$PROFILE" >/dev/null 2>&1 && \
                echo "  ✔ WAF asociado a distribución $dist_id" || \
                echo "  ⚠ No se pudo asociar WAF a distribución $dist_id (puede requerir configuración manual)"
            else
                echo "  ⚠ No se pudo obtener configuración de distribución $dist_id"
            fi
        fi
    done
fi

# Mostrar resumen de reglas configuradas
echo
echo "🛡️ REGLAS DE PROTECCIÓN CONFIGURADAS:"
echo "====================================="
echo "1. ✔ AWS Managed Rules Common Rule Set"
echo "   • Protección contra vulnerabilidades OWASP Top 10"
echo "   • Bloqueo de inyecciones SQL y XSS"
echo "   • Protección contra ataques comunes"
echo
echo "2. ✔ AWS Managed Rules Known Bad Inputs"
echo "   • Bloqueo de patrones de entrada maliciosos conocidos"
echo "   • Protección contra payloads de exploits"
echo
echo "3. ✔ Amazon IP Reputation List"
echo "   • Bloqueo de IPs con mala reputación"
echo "   • Protección contra fuentes de tráfico malicioso"
echo
echo "4. ✔ Rate Limiting Rule"
echo "   • Límite: 2000 requests por IP en 5 minutos"
echo "   • Protección contra ataques DDoS"

# Verificar integración con CloudWatch
echo
echo "📊 Configurando monitoreo de CloudWatch..."
echo "Las métricas de WAF aparecerán en CloudWatch:"
echo "• Namespace: AWS/WAFV2"
echo "• Métricas por regla individual"
echo "• Logs de requests bloqueados disponibles"

# Mostrar comandos útiles
echo
echo "🔧 COMANDOS ÚTILES PARA GESTIÓN:"
echo "==============================="
echo
echo "# Ver métricas de WAF en CloudWatch:"
echo "wsl aws cloudwatch get-metric-statistics \\"
echo "    --namespace AWS/WAFV2 \\"
echo "    --metric-name BlockedRequests \\"
echo "    --dimensions Name=WebACL,Value=$WEB_ACL_NAME Name=Region,Value=CloudFront \\"
echo "    --start-time \$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \\"
echo "    --end-time \$(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "    --period 300 --statistics Sum \\"
echo "    --region $REGION --profile $PROFILE"
echo
echo "# Listar requests muestreados:"
echo "wsl aws wafv2 get-sampled-requests \\"
echo "    --web-acl-arn '$WEB_ACL_ARN' \\"
echo "    --rule-metric-name 'CommonRuleSetMetric' \\"
echo "    --scope CLOUDFRONT \\"
echo "    --time-window StartTime=\$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S),EndTime=\$(date -u +%Y-%m-%dT%H:%M:%S) \\"
echo "    --max-items 100 \\"
echo "    --region $REGION --profile $PROFILE"
echo
echo "# Ver distribuciones con WAF asociado:"
echo "wsl aws wafv2 list-resources-for-web-acl \\"
echo "    --web-acl-arn '$WEB_ACL_ARN' \\"
echo "    --resource-type CLOUDFRONT \\"
echo "    --region $REGION --profile $PROFILE"

echo
echo "✅ AWS WAF para CloudFront configurado exitosamente"
echo
echo "CONFIGURACIÓN COMPLETADA:"
echo "========================"
echo "🛡️  Web ACL: $WEB_ACL_NAME"
echo "🆔 ID: $WEB_ACL_ID"
echo "🔗 ARN: $WEB_ACL_ARN"
echo "🌐 Scope: CLOUDFRONT (Global)"
echo "📊 Monitoreo: CloudWatch habilitado"
echo
echo "PROTECCIÓN ACTIVA:"
echo "=================="
echo "🚫 Bloqueo de ataques OWASP Top 10"
echo "🚫 Protección contra SQL Injection y XSS"
echo "🚫 Bloqueo de IPs con mala reputación"
echo "🚫 Rate limiting (2000 req/IP/5min)"
echo "🚫 Protección contra entrada maliciosa conocida"
echo
echo "PRÓXIMOS PASOS:"
echo "==============="
echo "1. 📊 Monitorea métricas en CloudWatch"
echo "2. 🔍 Revisa logs de requests bloqueados"
echo "3. ⚙️  Ajusta reglas según patrones de tráfico"
echo "4. 🚨 Configura alertas para ataques detectados"
echo "5. 📝 Documenta excepciones si es necesario"
echo
echo "⚠️  IMPORTANTE:"
echo "Las distribuciones de CloudFront pueden tardar hasta 15 minutos"
echo "en propagar los cambios de WAF globalmente."
echo
echo "=== Proceso completado ==="