#!/bin/bash
# verify-appsync-waf.sh
# Verificar configuraciones de AWS WAF para APIs AppSync
# Validar que todas las APIs GraphQL tengan protección WAF

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
echo -e "${BLUE}🔍 VERIFICACIÓN WAF APPSYNC${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Variables de conteo
TOTAL_APIS=0
PROTECTED_APIS=0
UNPROTECTED_APIS=0
TOTAL_WAF_ACLS=0

# Verificar disponibilidad de servicios
echo -e "${PURPLE}🔍 Verificando disponibilidad de servicios...${NC}"

# Verificar AppSync
APPSYNC_TEST=$(aws appsync list-graphql-apis --profile "$PROFILE" --region "$REGION" --max-results 1 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ AppSync no disponible en región $REGION${NC}"
    
    # Verificar otras regiones principales
    MAIN_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")
    for region in "${MAIN_REGIONS[@]}"; do
        echo -e "   🔍 Verificando región: ${BLUE}$region${NC}"
        TEST_RESULT=$(aws appsync list-graphql-apis --profile "$PROFILE" --region "$region" --max-results 1 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ AppSync disponible en: ${GREEN}$region${NC}"
            REGION="$region"
            break
        else
            echo -e "   ❌ No disponible en: $region"
        fi
    done
fi

# Verificar WAFv2
WAFV2_TEST=$(aws wafv2 list-web-acls --scope REGIONAL --profile "$PROFILE" --region "$REGION" --max-items 1 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ WAFv2 no disponible o sin permisos${NC}"
fi

echo ""

# Análisis de Web ACLs existentes
echo -e "${PURPLE}=== Análisis de Web ACLs WAF ===${NC}"

# Obtener lista de Web ACLs
WAF_ACLS=$(aws wafv2 list-web-acls --scope REGIONAL --profile "$PROFILE" --region "$REGION" --query 'WebACLs[].[Name,Id,ARN]' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener Web ACLs${NC}"
elif [ -z "$WAF_ACLS" ] || [ "$WAF_ACLS" == "None" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron Web ACLs WAF${NC}"
    TOTAL_WAF_ACLS=0
else
    echo -e "${GREEN}📊 Web ACLs encontrados:${NC}"
    
    while IFS=$'\t' read -r acl_name acl_id acl_arn; do
        if [ -n "$acl_name" ] && [ "$acl_name" != "None" ]; then
            TOTAL_WAF_ACLS=$((TOTAL_WAF_ACLS + 1))
            echo -e "${CYAN}🛡️ Web ACL: $acl_name${NC}"
            echo -e "   🆔 ID: ${BLUE}$acl_id${NC}"
            
            # Verificar recursos asociados
            ASSOCIATED_RESOURCES=$(aws wafv2 list-resources-for-web-acl --web-acl-arn "$acl_arn" --profile "$PROFILE" --region "$REGION" --query 'ResourceArns[]' --output text 2>/dev/null)
            
            if [ -n "$ASSOCIATED_RESOURCES" ] && [ "$ASSOCIATED_RESOURCES" != "None" ]; then
                RESOURCE_COUNT=$(echo "$ASSOCIATED_RESOURCES" | wc -w)
                echo -e "   🔗 Recursos asociados: ${GREEN}$RESOURCE_COUNT${NC}"
                
                # Verificar si hay APIs AppSync asociadas
                APPSYNC_RESOURCES=$(echo "$ASSOCIATED_RESOURCES" | grep -o "arn:aws:appsync:[^:]*:[^:]*:apis/[^[:space:]]*" | wc -l)
                if [ $APPSYNC_RESOURCES -gt 0 ]; then
                    echo -e "   📱 APIs AppSync protegidas: ${GREEN}$APPSYNC_RESOURCES${NC}"
                fi
            else
                echo -e "   🔗 Recursos asociados: ${YELLOW}Ninguno${NC}"
            fi
            
            # Verificar reglas configuradas
            WEB_ACL_DETAILS=$(aws wafv2 get-web-acl --scope REGIONAL --id "$acl_id" --name "$acl_name" --profile "$PROFILE" --region "$REGION" --query 'WebACL.Rules[].Name' --output text 2>/dev/null)
            
            if [ -n "$WEB_ACL_DETAILS" ] && [ "$WEB_ACL_DETAILS" != "None" ]; then
                RULE_COUNT=$(echo "$WEB_ACL_DETAILS" | wc -w)
                echo -e "   📋 Reglas configuradas: ${BLUE}$RULE_COUNT${NC}"
                
                # Verificar reglas específicas de seguridad
                if echo "$WEB_ACL_DETAILS" | grep -q "AWSManagedRulesCommonRuleSet"; then
                    echo -e "      ✅ Common Rule Set"
                fi
                if echo "$WEB_ACL_DETAILS" | grep -q "AWSManagedRulesKnownBadInputsRuleSet"; then
                    echo -e "      ✅ Known Bad Inputs"
                fi
                if echo "$WEB_ACL_DETAILS" | grep -q "AWSManagedRulesAmazonIpReputationList"; then
                    echo -e "      ✅ IP Reputation List"
                fi
                if echo "$WEB_ACL_DETAILS" | grep -q "RateLimit"; then
                    echo -e "      ✅ Rate Limiting"
                fi
            fi
            echo ""
        fi
    done <<< "$WAF_ACLS"
fi

# Análisis de APIs AppSync
echo -e "${PURPLE}=== Análisis de APIs AppSync ===${NC}"

# Obtener lista de APIs GraphQL
GRAPHQL_APIS=$(aws appsync list-graphql-apis --profile "$PROFILE" --region "$REGION" --query 'graphqlApis[].[apiId,name,authenticationType,arn]' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener APIs AppSync${NC}"
elif [ -z "$GRAPHQL_APIS" ] || [ "$GRAPHQL_APIS" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron APIs AppSync GraphQL${NC}"
    TOTAL_APIS=0
else
    echo -e "${GREEN}📊 APIs AppSync encontradas:${NC}"
    
    while IFS=$'\t' read -r api_id api_name auth_type api_arn; do
        if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
            TOTAL_APIS=$((TOTAL_APIS + 1))
            echo -e "${CYAN}📱 API: $api_name${NC}"
            echo -e "   🆔 API ID: ${BLUE}$api_id${NC}"
            echo -e "   🔐 Autenticación: ${BLUE}$auth_type${NC}"
            
            # Verificar estado de protección WAF
            WAF_PROTECTION=$(aws wafv2 get-web-acl-for-resource --resource-arn "$api_arn" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
            
            if [ $? -eq 0 ] && [ "$WAF_PROTECTION" != "null" ]; then
                WAF_NAME=$(echo "$WAF_PROTECTION" | jq -r '.WebACL.Name' 2>/dev/null)
                WAF_ID=$(echo "$WAF_PROTECTION" | jq -r '.WebACL.Id' 2>/dev/null)
                
                echo -e "   ✅ Protección WAF: ${GREEN}$WAF_NAME${NC}"
                echo -e "   🛡️ WAF ID: ${BLUE}$WAF_ID${NC}"
                PROTECTED_APIS=$((PROTECTED_APIS + 1))
                
                # Verificar métricas WAF
                BLOCKED_REQUESTS=$(aws cloudwatch get-metric-statistics \
                    --namespace AWS/WAFV2 \
                    --metric-name BlockedRequests \
                    --dimensions Name=WebACL,Value="$WAF_NAME" Name=Region,Value="$REGION" \
                    --start-time "$(date -d '24 hours ago' -Iseconds)" \
                    --end-time "$(date -Iseconds)" \
                    --period 86400 \
                    --statistics Sum \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --query 'Datapoints[0].Sum' \
                    --output text 2>/dev/null)
                
                if [ -n "$BLOCKED_REQUESTS" ] && [ "$BLOCKED_REQUESTS" != "None" ] && [ "$BLOCKED_REQUESTS" != "null" ]; then
                    echo -e "   📊 Requests bloqueados (24h): ${YELLOW}$BLOCKED_REQUESTS${NC}"
                else
                    echo -e "   📊 Requests bloqueados (24h): ${GREEN}0${NC}"
                fi
                
            else
                echo -e "   ❌ Protección WAF: ${RED}NO CONFIGURADA${NC}"
                UNPROTECTED_APIS=$((UNPROTECTED_APIS + 1))
            fi
            
            # Verificar configuraciones adicionales de seguridad
            echo -e "   🔍 Verificando configuraciones adicionales..."
            
            # Verificar logging de API
            API_LOGGING=$(aws appsync get-graphql-api --api-id "$api_id" --profile "$PROFILE" --region "$REGION" --query 'graphqlApi.logConfig.cloudWatchLogsRoleArn' --output text 2>/dev/null)
            
            if [ -n "$API_LOGGING" ] && [ "$API_LOGGING" != "None" ] && [ "$API_LOGGING" != "null" ]; then
                echo -e "      ✅ API Logging habilitado"
            else
                echo -e "      ⚠️ API Logging: ${YELLOW}No configurado${NC}"
            fi
            
            # Verificar configuración de endpoint
            API_URIS=$(aws appsync get-graphql-api --api-id "$api_id" --profile "$PROFILE" --region "$REGION" --query 'graphqlApi.uris' --output json 2>/dev/null)
            
            if [ -n "$API_URIS" ] && [ "$API_URIS" != "null" ]; then
                GRAPHQL_URI=$(echo "$API_URIS" | jq -r '.GRAPHQL // empty' 2>/dev/null)
                if [ -n "$GRAPHQL_URI" ]; then
                    echo -e "      🌐 Endpoint GraphQL: ${BLUE}$GRAPHQL_URI${NC}"
                fi
            fi
            
            echo ""
        fi
    done <<< "$GRAPHQL_APIS"
fi

# Verificar configuración de logging WAF
echo -e "${PURPLE}=== Configuración de Logging WAF ===${NC}"

if [ $TOTAL_WAF_ACLS -gt 0 ]; then
    # Verificar log groups WAF
    WAF_LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/wafv2" --profile "$PROFILE" --region "$REGION" --query 'logGroups[].logGroupName' --output text 2>/dev/null)
    
    if [ -n "$WAF_LOG_GROUPS" ] && [ "$WAF_LOG_GROUPS" != "None" ]; then
        LOG_GROUP_COUNT=$(echo "$WAF_LOG_GROUPS" | wc -w)
        echo -e "✅ Log groups WAF encontrados: ${GREEN}$LOG_GROUP_COUNT${NC}"
        
        for log_group in $WAF_LOG_GROUPS; do
            echo -e "   📝 $log_group"
            
            # Verificar retención
            RETENTION=$(aws logs describe-log-groups --log-group-name-prefix "$log_group" --profile "$PROFILE" --region "$REGION" --query 'logGroups[0].retentionInDays' --output text 2>/dev/null)
            
            if [ -n "$RETENTION" ] && [ "$RETENTION" != "None" ]; then
                echo -e "      📅 Retención: ${BLUE}$RETENTION días${NC}"
            else
                echo -e "      📅 Retención: ${YELLOW}Sin límite${NC}"
            fi
        done
    else
        echo -e "⚠️ Log groups WAF: ${YELLOW}No configurados${NC}"
    fi
else
    echo -e "⚠️ No hay Web ACLs para verificar logging"
fi

echo ""

# Verificar alarmas CloudWatch
echo -e "${PURPLE}=== Alarmas CloudWatch WAF ===${NC}"

WAF_ALARMS=$(aws cloudwatch describe-alarms --alarm-name-prefix "AppSync-WAF" --profile "$PROFILE" --region "$REGION" --query 'MetricAlarms[].[AlarmName,StateValue,MetricName]' --output text 2>/dev/null)

if [ -n "$WAF_ALARMS" ] && [ "$WAF_ALARMS" != "None" ]; then
    ALARM_COUNT=$(echo "$WAF_ALARMS" | wc -l)
    echo -e "✅ Alarmas WAF encontradas: ${GREEN}$ALARM_COUNT${NC}"
    
    while IFS=$'\t' read -r alarm_name alarm_state metric_name; do
        if [ -n "$alarm_name" ]; then
            echo -e "   🚨 $alarm_name"
            echo -e "      📊 Métrica: ${BLUE}$metric_name${NC}"
            
            if [ "$alarm_state" == "OK" ]; then
                echo -e "      ✅ Estado: ${GREEN}$alarm_state${NC}"
            elif [ "$alarm_state" == "ALARM" ]; then
                echo -e "      🚨 Estado: ${RED}$alarm_state${NC}"
            else
                echo -e "      ⚠️ Estado: ${YELLOW}$alarm_state${NC}"
            fi
        fi
    done <<< "$WAF_ALARMS"
else
    echo -e "⚠️ Alarmas WAF: ${YELLOW}No configuradas${NC}"
fi

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="appsync-waf-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "total_appsync_apis": $TOTAL_APIS,
    "protected_apis": $PROTECTED_APIS,
    "unprotected_apis": $UNPROTECTED_APIS,
    "total_waf_acls": $TOTAL_WAF_ACLS,
    "protection_compliance": "$(if [ $TOTAL_APIS -eq 0 ]; then echo "NO_APIS"; elif [ $UNPROTECTED_APIS -eq 0 ]; then echo "FULLY_COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "recommendations": [
    "Configurar WAF para todas las APIs AppSync",
    "Implementar reglas managed de AWS en WAF",
    "Configurar rate limiting apropiado",
    "Habilitar logging WAF para análisis",
    "Crear alarmas CloudWatch para monitoreo",
    "Revisar métricas de requests bloqueados regularmente"
  ]
}
EOF

echo -e "📊 Reporte de verificación generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN WAF APPSYNC ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "🛡️ Web ACLs WAF: ${GREEN}$TOTAL_WAF_ACLS${NC}"
echo -e "📱 APIs AppSync: ${GREEN}$TOTAL_APIS${NC}"

if [ $TOTAL_APIS -gt 0 ]; then
    echo -e "✅ APIs protegidas: ${GREEN}$PROTECTED_APIS${NC}"
    if [ $UNPROTECTED_APIS -gt 0 ]; then
        echo -e "❌ APIs sin protección: ${RED}$UNPROTECTED_APIS${NC}"
    fi
    
    # Calcular porcentaje de protección
    if [ $TOTAL_APIS -gt 0 ]; then
        PROTECTION_PERCENT=$((PROTECTED_APIS * 100 / TOTAL_APIS))
        echo -e "📈 Cobertura WAF: ${GREEN}$PROTECTION_PERCENT%${NC}"
    fi
fi

echo ""

# Estado final
if [ $TOTAL_APIS -eq 0 ]; then
    if [ $TOTAL_WAF_ACLS -gt 0 ]; then
        echo -e "${GREEN}✅ ESTADO: WAF CONFIGURADO, SIN APIS${NC}"
        echo -e "${BLUE}💡 Protección WAF lista para futuras APIs AppSync${NC}"
    else
        echo -e "${YELLOW}⚠️ ESTADO: SIN APIS NI WAF${NC}"
        echo -e "${BLUE}💡 No hay APIs AppSync para proteger${NC}"
    fi
elif [ $UNPROTECTED_APIS -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE PROTEGIDO${NC}"
    echo -e "${BLUE}💡 Todas las APIs AppSync tienen protección WAF${NC}"
elif [ $PROTECTED_APIS -gt 0 ]; then
    echo -e "${YELLOW}⚠️ ESTADO: PROTECCIÓN PARCIAL${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-appsync-waf.sh $PROFILE${NC}"
else
    echo -e "${RED}❌ ESTADO: SIN PROTECCIÓN WAF${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./enable-appsync-waf.sh $PROFILE${NC}"
fi

echo -e "📋 Reporte: ${GREEN}$VERIFICATION_REPORT${NC}"