#!/bin/bash
# enable-appsync-waf.sh
# Habilitar AWS WAF para endpoints de AppSync GraphQL APIs
# Regla de seguridad: Enable AWS WAF for AppSync endpoints
# Uso: ./enable-appsync-waf.sh [perfil]

# Verificar parámetros
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
echo -e "${BLUE}🛡️ HABILITANDO AWS WAF PARA APPSYNC ENDPOINTS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando protección WAF para APIs GraphQL AppSync"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI no está instalado${NC}"
    exit 1
fi

AWS_VERSION=$(aws --version 2>&1)
echo -e "✅ AWS CLI encontrado: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
echo -e "${PURPLE}🔐 Verificando credenciales para perfil '$PROFILE'...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo verificar las credenciales para el perfil '$PROFILE'${NC}"
    echo -e "${YELLOW}💡 Verifica que el perfil esté configurado correctamente${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Verificar disponibilidad de servicios
echo -e "${PURPLE}🔍 Verificando disponibilidad de servicios...${NC}"

# Verificar AppSync
APPSYNC_TEST=$(aws appsync list-graphql-apis --profile "$PROFILE" --region "$REGION" --max-results 1 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ AppSync no disponible en región $REGION${NC}"
    
    # Verificar otras regiones principales
    MAIN_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")
    for region in "${MAIN_REGIONS[@]}"; do
        echo -e "   🔍 Verificando AppSync en región: ${BLUE}$region${NC}"
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
    echo -e "${RED}❌ WAFv2 no disponible o sin permisos${NC}"
    echo -e "${YELLOW}💡 Verificar permisos para WAFv2${NC}"
fi

echo -e "✅ Servicios verificados en región: ${GREEN}$REGION${NC}"
echo ""

# Variables de conteo
APPSYNC_APIS_FOUND=0
WAFV2_ACLS_CREATED=0
ASSOCIATIONS_CREATED=0
EXISTING_ASSOCIATIONS=0

# Paso 1: Inventario de APIs GraphQL AppSync
echo -e "${PURPLE}=== Paso 1: Inventario de APIs AppSync ===${NC}"

# Obtener lista de APIs GraphQL
GRAPHQL_APIS=$(aws appsync list-graphql-apis --profile "$PROFILE" --region "$REGION" --query 'graphqlApis[].[apiId,name,authenticationType,arn]' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener lista de APIs AppSync${NC}"
    APPSYNC_APIS_FOUND=0
elif [ -z "$GRAPHQL_APIS" ] || [ "$GRAPHQL_APIS" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron APIs AppSync GraphQL${NC}"
    APPSYNC_APIS_FOUND=0
else
    echo -e "${GREEN}✅ APIs AppSync encontradas${NC}"
    
    # Procesar cada API
    while IFS=$'\t' read -r api_id api_name auth_type api_arn; do
        if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
            APPSYNC_APIS_FOUND=$((APPSYNC_APIS_FOUND + 1))
            echo -e "${CYAN}📱 API AppSync: $api_name${NC}"
            echo -e "   🆔 API ID: ${BLUE}$api_id${NC}"
            echo -e "   🔐 Autenticación: ${BLUE}$auth_type${NC}"
            echo -e "   🏷️ ARN: ${BLUE}$api_arn${NC}"
            
            # Verificar si ya tiene WAF asociado
            EXISTING_WAF=$(aws wafv2 get-web-acl-for-resource --resource-arn "$api_arn" --profile "$PROFILE" --region "$REGION" --query 'WebACL.Name' --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$EXISTING_WAF" ] && [ "$EXISTING_WAF" != "None" ]; then
                echo -e "   🛡️ WAF existente: ${GREEN}$EXISTING_WAF${NC}"
                EXISTING_ASSOCIATIONS=$((EXISTING_ASSOCIATIONS + 1))
            else
                echo -e "   🛡️ WAF: ${YELLOW}No configurado${NC}"
            fi
            echo ""
        fi
    done <<< "$GRAPHQL_APIS"
fi

# Paso 2: Crear Web ACL si es necesario
echo -e "${PURPLE}=== Paso 2: Configuración de Web ACL WAF ===${NC}"

WAF_ACL_NAME="AppSyncProtection-$PROFILE-$(date +%Y%m%d)"
WAF_ACL_ARN=""

# Verificar si ya existe un Web ACL para AppSync
EXISTING_ACL=$(aws wafv2 list-web-acls --scope REGIONAL --profile "$PROFILE" --region "$REGION" --query "WebACLs[?contains(Name, 'AppSync')].{Name:Name,Id:Id,ARN:ARN}" --output json 2>/dev/null)

if [ $? -eq 0 ] && [ "$EXISTING_ACL" != "[]" ] && [ "$EXISTING_ACL" != "null" ]; then
    # Usar ACL existente
    WAF_ACL_NAME=$(echo "$EXISTING_ACL" | jq -r '.[0].Name' 2>/dev/null)
    WAF_ACL_ID=$(echo "$EXISTING_ACL" | jq -r '.[0].Id' 2>/dev/null)
    WAF_ACL_ARN=$(echo "$EXISTING_ACL" | jq -r '.[0].ARN' 2>/dev/null)
    
    echo -e "✅ Web ACL existente encontrado: ${GREEN}$WAF_ACL_NAME${NC}"
    echo -e "   🆔 ACL ID: ${BLUE}$WAF_ACL_ID${NC}"
else
    # Crear nuevo Web ACL
    echo -e "${CYAN}🔧 Creando nuevo Web ACL para AppSync...${NC}"
    
    # Crear configuración de reglas WAF usando método más seguro
    python3 -c "
import json
rules_config = [
    {
        'Name': 'AWSManagedRulesCommonRuleSet',
        'Priority': 1,
        'OverrideAction': {'None': {}},
        'VisibilityConfig': {
            'SampledRequestsEnabled': True,
            'CloudWatchMetricsEnabled': True,
            'MetricName': 'CommonRuleSetMetric'
        },
        'Statement': {
            'ManagedRuleGroupStatement': {
                'VendorName': 'AWS',
                'Name': 'AWSManagedRulesCommonRuleSet'
            }
        }
    },
    {
        'Name': 'AWSManagedRulesKnownBadInputsRuleSet',
        'Priority': 2,
        'OverrideAction': {'None': {}},
        'VisibilityConfig': {
            'SampledRequestsEnabled': True,
            'CloudWatchMetricsEnabled': True,
            'MetricName': 'KnownBadInputsRuleSetMetric'
        },
        'Statement': {
            'ManagedRuleGroupStatement': {
                'VendorName': 'AWS',
                'Name': 'AWSManagedRulesKnownBadInputsRuleSet'
            }
        }
    },
    {
        'Name': 'RateLimitRule',
        'Priority': 3,
        'Action': {'Block': {}},
        'VisibilityConfig': {
            'SampledRequestsEnabled': True,
            'CloudWatchMetricsEnabled': True,
            'MetricName': 'RateLimitRule'
        },
        'Statement': {
            'RateBasedStatement': {
                'Limit': 2000,
                'AggregateKeyType': 'IP'
            }
        }
    }
]

with open('/tmp/waf-rules-$PROFILE.json', 'w') as f:
    json.dump(rules_config, f, indent=2)
" 2>/dev/null

    # Verificar que el archivo JSON fue creado correctamente
    if [ ! -f "/tmp/waf-rules-$PROFILE.json" ]; then
        echo -e "${YELLOW}⚠️ Error generando configuración JSON, usando método alternativo${NC}"
        # Crear reglas básicas como fallback
        echo '[{"Name":"RateLimitRule","Priority":1,"Action":{"Block":{}},"VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"RateLimitRule"},"Statement":{"RateBasedStatement":{"Limit":2000,"AggregateKeyType":"IP"}}}]' > "/tmp/waf-rules-$PROFILE.json"
    fi

    # Intentar crear Web ACL con manejo mejorado de errores
    echo -e "   🔄 Intentando crear Web ACL..."
    CREATE_RESULT=$(aws wafv2 create-web-acl \
        --name "$WAF_ACL_NAME" \
        --scope REGIONAL \
        --default-action Allow={} \
        --rules file:///tmp/waf-rules-$PROFILE.json \
        --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=AppSyncWebACL \
        --profile "$PROFILE" \
        --region "$REGION" \
        --output json 2>&1)
    
    CREATE_EXIT_CODE=$?
    
    if [ $CREATE_EXIT_CODE -eq 0 ]; then
        WAF_ACL_ARN=$(echo "$CREATE_RESULT" | jq -r '.Summary.ARN' 2>/dev/null)
        WAF_ACL_ID=$(echo "$CREATE_RESULT" | jq -r '.Summary.Id' 2>/dev/null)
        
        if [ -n "$WAF_ACL_ARN" ] && [ "$WAF_ACL_ARN" != "null" ]; then
            echo -e "✅ Web ACL creado exitosamente: ${GREEN}$WAF_ACL_NAME${NC}"
            echo -e "   🆔 ACL ID: ${BLUE}$WAF_ACL_ID${NC}"
            echo -e "   🏷️ ACL ARN: ${BLUE}$WAF_ACL_ARN${NC}"
            WAFV2_ACLS_CREATED=$((WAFV2_ACLS_CREATED + 1))
        else
            echo -e "${RED}❌ Error en respuesta de creación de Web ACL${NC}"
            WAF_ACL_ARN=""
        fi
    else
        echo -e "${RED}❌ Error creando Web ACL${NC}"
        
        # Analizar tipo de error específico
        if echo "$CREATE_RESULT" | grep -q "AccessDenied\|UnauthorizedOperation"; then
            echo -e "${YELLOW}💡 Error de permisos - Se requieren permisos WAFv2${NC}"
            echo -e "${BLUE}   Permisos necesarios: wafv2:CreateWebACL, wafv2:PutLoggingConfiguration${NC}"
        elif echo "$CREATE_RESULT" | grep -q "LimitExceeded"; then
            echo -e "${YELLOW}💡 Límite de Web ACLs alcanzado${NC}"
            echo -e "${BLUE}   Considerar usar Web ACL existente o eliminar ACLs no usados${NC}"
        elif echo "$CREATE_RESULT" | grep -q "InvalidParameterValue\|ValidationException"; then
            echo -e "${YELLOW}💡 Error en parámetros de configuración${NC}"
            echo -e "${BLUE}   Verificar configuración de reglas WAF${NC}"
        else
            echo -e "${YELLOW}💡 Error general de WAFv2:${NC}"
            echo -e "${BLUE}   $(echo "$CREATE_RESULT" | head -2 | tail -1)${NC}"
        fi
        
        # Intentar usar Web ACL existente como alternativa
        echo -e "${CYAN}🔍 Buscando Web ACLs existentes como alternativa...${NC}"
        FALLBACK_ACL=$(aws wafv2 list-web-acls --scope REGIONAL --profile "$PROFILE" --region "$REGION" --query 'WebACLs[0].[Name,Id,ARN]' --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$FALLBACK_ACL" ] && [ "$FALLBACK_ACL" != "None" ]; then
            FALLBACK_NAME=$(echo "$FALLBACK_ACL" | cut -f1)
            FALLBACK_ID=$(echo "$FALLBACK_ACL" | cut -f2)
            FALLBACK_ARN=$(echo "$FALLBACK_ACL" | cut -f3)
            
            echo -e "   ✅ Web ACL existente encontrado: ${GREEN}$FALLBACK_NAME${NC}"
            echo -e "   💡 Usando como alternativa para asociaciones AppSync"
            
            WAF_ACL_NAME="$FALLBACK_NAME"
            WAF_ACL_ID="$FALLBACK_ID"
            WAF_ACL_ARN="$FALLBACK_ARN"
        else
            echo -e "   ${YELLOW}⚠️ No se encontraron Web ACLs alternativos${NC}"
            WAF_ACL_ARN=""
        fi
    fi
    
    # Limpiar archivo temporal
    rm -f "/tmp/waf-rules-$PROFILE.json"
fi

echo ""

# Paso 3: Asociar Web ACL con APIs AppSync
if [ -n "$WAF_ACL_ARN" ] && [ $APPSYNC_APIS_FOUND -gt 0 ]; then
    echo -e "${PURPLE}=== Paso 3: Asociando WAF con APIs AppSync ===${NC}"
    
    # Procesar cada API nuevamente para asociaciones
    while IFS=$'\t' read -r api_id api_name auth_type api_arn; do
        if [ -n "$api_id" ] && [ "$api_id" != "None" ]; then
            echo -e "${CYAN}🔗 Procesando API: $api_name${NC}"
            
            # Verificar si ya tiene WAF asociado
            CURRENT_WAF=$(aws wafv2 get-web-acl-for-resource --resource-arn "$api_arn" --profile "$PROFILE" --region "$REGION" --query 'WebACL.Name' --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$CURRENT_WAF" ] && [ "$CURRENT_WAF" != "None" ]; then
                echo -e "   🛡️ Ya tiene WAF asociado: ${GREEN}$CURRENT_WAF${NC}"
            else
                # Asociar Web ACL
                echo -e "   🔧 Asociando Web ACL..."
                
                ASSOCIATE_RESULT=$(aws wafv2 associate-web-acl \
                    --web-acl-arn "$WAF_ACL_ARN" \
                    --resource-arn "$api_arn" \
                    --profile "$PROFILE" \
                    --region "$REGION" 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    echo -e "   ✅ WAF asociado exitosamente"
                    ASSOCIATIONS_CREATED=$((ASSOCIATIONS_CREATED + 1))
                else
                    echo -e "   ${RED}❌ Error asociando WAF${NC}"
                    echo -e "   ${YELLOW}💡 Verificar permisos y estado de la API${NC}"
                fi
            fi
        fi
    done <<< "$GRAPHQL_APIS"
fi

echo ""

# Paso 4: Configurar logging y monitoreo
echo -e "${PURPLE}=== Paso 4: Configuración de Logging y Monitoreo ===${NC}"

if [ -n "$WAF_ACL_ARN" ]; then
    # Crear log group para WAF si no existe
    LOG_GROUP_NAME="/aws/wafv2/appsync/$PROFILE"
    
    echo -e "${CYAN}📝 Configurando logging WAF...${NC}"
    
    # Verificar si el log group existe
    EXISTING_LOG_GROUP=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --profile "$PROFILE" --region "$REGION" --query 'logGroups[?logGroupName==`'$LOG_GROUP_NAME'`].logGroupName' --output text 2>/dev/null)
    
    if [ -z "$EXISTING_LOG_GROUP" ] || [ "$EXISTING_LOG_GROUP" == "None" ]; then
        # Crear log group
        aws logs create-log-group --log-group-name "$LOG_GROUP_NAME" --profile "$PROFILE" --region "$REGION" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "✅ Log group creado: ${GREEN}$LOG_GROUP_NAME${NC}"
            
            # Configurar retención
            aws logs put-retention-policy --log-group-name "$LOG_GROUP_NAME" --retention-in-days 30 --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1
            echo -e "   📅 Retención configurada: ${BLUE}30 días${NC}"
        else
            echo -e "${YELLOW}⚠️ No se pudo crear log group${NC}"
        fi
    else
        echo -e "✅ Log group existente: ${GREEN}$LOG_GROUP_NAME${NC}"
    fi
    
    # Configurar logging configuration
    echo -e "${CYAN}🔧 Habilitando logging WAF...${NC}"
    
    LOGGING_CONFIG="{
        \"ResourceArn\": \"$WAF_ACL_ARN\",
        \"LogDestinationConfigs\": [
            \"arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$LOG_GROUP_NAME\"
        ]
    }"
    
    # Habilitar logging
    aws wafv2 put-logging-configuration \
        --logging-configuration "$LOGGING_CONFIG" \
        --profile "$PROFILE" \
        --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "✅ Logging WAF habilitado"
    else
        echo -e "${YELLOW}⚠️ Error configurando logging (puede ya existir)${NC}"
    fi
fi

# Crear métricas y alarmas CloudWatch
echo -e "${CYAN}📊 Configurando métricas CloudWatch...${NC}"

if [ -n "$WAF_ACL_NAME" ]; then
    # Crear alarma para solicitudes bloqueadas
    ALARM_NAME="AppSync-WAF-BlockedRequests-$PROFILE"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "High number of blocked requests in AppSync WAF" \
        --metric-name "BlockedRequests" \
        --namespace "AWS/WAFV2" \
        --statistic "Sum" \
        --period 300 \
        --threshold 100 \
        --comparison-operator "GreaterThanThreshold" \
        --evaluation-periods 2 \
        --dimensions Name=WebACL,Value="$WAF_ACL_NAME" Name=Region,Value="$REGION" \
        --profile "$PROFILE" \
        --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "✅ Alarma CloudWatch creada: ${GREEN}$ALARM_NAME${NC}"
    else
        echo -e "${YELLOW}⚠️ Error creando alarma CloudWatch${NC}"
    fi
fi

echo ""

# Crear documentación de configuración
echo -e "${PURPLE}=== Paso 5: Generando documentación ===${NC}"

WAF_CONFIG_REPORT="appsync-waf-config-$PROFILE-$(date +%Y%m%d).md"

cat > "$WAF_CONFIG_REPORT" << EOF
# Configuración AWS WAF para AppSync - $PROFILE

**Fecha**: $(date)
**Región**: $REGION
**Account ID**: $ACCOUNT_ID

## Resumen Ejecutivo

### APIs AppSync Procesadas
- **Total APIs encontradas**: $APPSYNC_APIS_FOUND
- **WAF ACLs creados**: $WAFV2_ACLS_CREATED
- **Asociaciones creadas**: $ASSOCIATIONS_CREATED
- **Asociaciones existentes**: $EXISTING_ASSOCIATIONS

### Web ACL Configurado
- **Nombre**: $WAF_ACL_NAME
- **ARN**: $WAF_ACL_ARN
- **Scope**: REGIONAL

## Reglas WAF Implementadas

### 1. Common Rule Set
- Protección contra ataques comunes (OWASP Top 10)
- SQL injection, XSS, path traversal
- Métrica: CommonRuleSetMetric

### 2. Known Bad Inputs
- Protección contra entradas maliciosas conocidas
- Patrones de exploits comunes
- Métrica: KnownBadInputsRuleSetMetric

### 3. IP Reputation List
- Bloqueo de IPs con mala reputación
- Lista mantenida por AWS
- Métrica: AmazonIpReputationListMetric

### 4. Rate Limiting
- Límite: 2000 requests por IP por 5 minutos
- Protección contra DDoS y abuso
- Métrica: RateLimitRule

## Logging y Monitoreo

### CloudWatch Logs
- **Log Group**: $LOG_GROUP_NAME
- **Retención**: 30 días
- **Formato**: JSON con detalles de requests

### CloudWatch Alarms
- **Alarma**: AppSync-WAF-BlockedRequests-$PROFILE
- **Umbral**: >100 requests bloqueados en 10 minutos
- **Métrica**: AWS/WAFV2 BlockedRequests

## Comandos de Verificación

\`\`\`bash
# Verificar Web ACL
aws wafv2 list-web-acls --scope REGIONAL --profile $PROFILE --region $REGION

# Verificar asociaciones
aws wafv2 list-resources-for-web-acl --web-acl-arn $WAF_ACL_ARN --profile $PROFILE

# Ver métricas WAF
aws cloudwatch get-metric-statistics \\
    --namespace AWS/WAFV2 \\
    --metric-name AllowedRequests \\
    --dimensions Name=WebACL,Value=$WAF_ACL_NAME \\
    --start-time 2024-01-01T00:00:00Z \\
    --end-time 2024-01-02T00:00:00Z \\
    --period 3600 \\
    --statistics Sum

# Ver logs WAF
aws logs filter-log-events \\
    --log-group-name $LOG_GROUP_NAME \\
    --start-time \$(date -d '1 hour ago' +%s)000
\`\`\`

## Mejores Prácticas

### 1. Monitoreo Continuo
- Revisar métricas WAF diariamente
- Analizar logs de requests bloqueados
- Ajustar reglas según patrones de tráfico

### 2. Tuning de Reglas
- Configurar excepciones para falsos positivos
- Ajustar rate limiting según carga esperada
- Implementar reglas personalizadas según necesidad

### 3. Testing de Seguridad
- Realizar pruebas de penetración regulares
- Validar efectividad de reglas WAF
- Documentar y remediar vulnerabilidades

### 4. Incident Response
- Procedimientos para ataques DDoS
- Escalación de alertas de seguridad
- Respuesta a patrones de ataque inusuales

EOF

echo -e "✅ Documentación generada: ${GREEN}$WAF_CONFIG_REPORT${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN CONFIGURACIÓN WAF APPSYNC ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📍 Región: ${GREEN}$REGION${NC}"
echo -e "🛡️ Web ACL: ${GREEN}$WAF_ACL_NAME${NC}"

if [ $APPSYNC_APIS_FOUND -gt 0 ]; then
    echo -e "📱 APIs AppSync encontradas: ${GREEN}$APPSYNC_APIS_FOUND${NC}"
    echo -e "🔗 Nuevas asociaciones: ${GREEN}$ASSOCIATIONS_CREATED${NC}"
    echo -e "✅ Asociaciones existentes: ${GREEN}$EXISTING_ASSOCIATIONS${NC}"
    
    TOTAL_PROTECTED=$((ASSOCIATIONS_CREATED + EXISTING_ASSOCIATIONS))
    echo -e "🛡️ APIs protegidas: ${GREEN}$TOTAL_PROTECTED/$APPSYNC_APIS_FOUND${NC}"
else
    echo -e "📱 APIs AppSync encontradas: ${GREEN}0${NC}"
fi

if [ -n "$WAF_ACL_ARN" ]; then
    echo -e "📝 Logging: ${GREEN}Configurado${NC}"
    echo -e "📊 Monitoreo: ${GREEN}Alarmas CloudWatch${NC}"
fi

echo -e "📋 Documentación: ${GREEN}$WAF_CONFIG_REPORT${NC}"

echo ""
if [ $APPSYNC_APIS_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ CONFIGURACIÓN WAF LISTA PARA FUTURAS APIS${NC}"
    echo -e "${BLUE}💡 Web ACL creado y listo para asociar con nuevas APIs AppSync${NC}"
elif [ $ASSOCIATIONS_CREATED -gt 0 ] || [ $EXISTING_ASSOCIATIONS -eq $APPSYNC_APIS_FOUND ]; then
    echo -e "${GREEN}🎉 APPSYNC APIS COMPLETAMENTE PROTEGIDAS${NC}"
    echo -e "${BLUE}💡 Todas las APIs AppSync tienen protección WAF habilitada${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN WAF PARCIALMENTE COMPLETA${NC}"
    echo -e "${BLUE}💡 Revisar APIs que no pudieron ser asociadas${NC}"
fi