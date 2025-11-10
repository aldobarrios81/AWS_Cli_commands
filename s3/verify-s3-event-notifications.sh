#!/bin/bash
# verify-s3-event-notifications.sh
# Verificar configuración de notificaciones de eventos S3
# Regla de seguridad: Verify S3 event notifications
# Uso: ./verify-s3-event-notifications.sh [perfil]

# Verificar parámetros
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
REGION="us-east-1"
SNS_TOPIC_NAME="s3-event-notifications"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICANDO S3 EVENT NOTIFICATIONS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Verificando configuración de notificaciones de eventos S3"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo verificar las credenciales para el perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# Verificar SNS Topic
echo -e "${PURPLE}=== Verificando SNS Topic para S3 Events ===${NC}"
SNS_TOPIC_ARN=$(aws sns list-topics --profile "$PROFILE" --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text 2>/dev/null)

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo -e "${RED}❌ SNS Topic '$SNS_TOPIC_NAME' no encontrado${NC}"
    echo -e "${YELLOW}💡 Ejecuta primero el script de configuración${NC}"
    exit 1
else
    echo -e "${GREEN}✅ SNS Topic encontrado: $SNS_TOPIC_ARN${NC}"
    echo -e "   ARN: ${BLUE}$SNS_TOPIC_ARN${NC}"
    
    # Verificar política del SNS Topic
    echo -e "${BLUE}📋 Verificando política del SNS Topic...${NC}"
    SNS_POLICY=$(aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" --query 'Attributes.Policy' --output text 2>/dev/null)
    
    if [ -n "$SNS_POLICY" ] && [ "$SNS_POLICY" != "None" ]; then
        # Verificar si la política permite publicación desde S3
        S3_PERMISSION=$(echo "$SNS_POLICY" | jq -r '.Statement[]? | select(.Principal.Service == "s3.amazonaws.com") | .Effect' 2>/dev/null)
        
        if [ "$S3_PERMISSION" == "Allow" ]; then
            echo -e "   ✅ Política configurada correctamente para S3"
        else
            echo -e "   ${YELLOW}⚠️ Política no configurada para S3${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠️ No se pudo verificar la política del SNS Topic${NC}"
    fi
    
    # Verificar suscripciones
    echo -e "${BLUE}📧 Suscripciones configuradas:${NC}"
    aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" --output table --query 'Subscriptions[*].[Endpoint,Protocol,SubscriptionArn]' 2>/dev/null
fi
echo ""

# Verificar buckets S3 y sus notificaciones
echo -e "${PURPLE}=== Verificando buckets S3 y notificaciones ===${NC}"

# Obtener lista de buckets
BUCKETS=$(aws s3api list-buckets --profile "$PROFILE" --query 'Buckets[].Name' --output text 2>/dev/null)

if [ -z "$BUCKETS" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron buckets S3${NC}"
    exit 0
fi

BUCKET_COUNT=$(echo "$BUCKETS" | wc -w)
echo -e "${GREEN}✅ Buckets S3 encontrados: $BUCKET_COUNT buckets${NC}"

# Estadísticas globales
BUCKETS_WITH_NOTIFICATIONS=0
BUCKETS_WITH_SNS_NOTIFICATIONS=0
TOTAL_NOTIFICATIONS=0
BUCKETS_WITH_ERRORS=0

echo -e "${BLUE}📊 Análisis detallado de buckets S3:${NC}"
echo ""

for bucket in $BUCKETS; do
    echo -e "${CYAN}📦 Analizando bucket: $bucket${NC}"
    
    # Verificar región del bucket
    BUCKET_REGION=$(aws s3api get-bucket-location --bucket "$bucket" --profile "$PROFILE" --query 'LocationConstraint' --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "   ${RED}❌ Error accediendo al bucket (permisos insuficientes)${NC}"
        BUCKETS_WITH_ERRORS=$((BUCKETS_WITH_ERRORS + 1))
        continue
    fi
    
    if [ "$BUCKET_REGION" == "None" ] || [ -z "$BUCKET_REGION" ]; then
        BUCKET_REGION="us-east-1"
    fi
    
    echo -e "   📍 Región: ${BLUE}$BUCKET_REGION${NC}"
    
    # Obtener configuración de notificaciones
    NOTIFICATION_CONFIG=$(aws s3api get-bucket-notification-configuration --bucket "$bucket" --profile "$PROFILE" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "   ${RED}❌ Error obteniendo configuración de notificaciones${NC}"
        BUCKETS_WITH_ERRORS=$((BUCKETS_WITH_ERRORS + 1))
        continue
    fi
    
    # Analizar configuraciones de notificaciones
    TOPIC_CONFIGS=$(echo "$NOTIFICATION_CONFIG" | jq -c '.TopicConfigurations[]?' 2>/dev/null)
    QUEUE_CONFIGS=$(echo "$NOTIFICATION_CONFIG" | jq -c '.QueueConfigurations[]?' 2>/dev/null)
    LAMBDA_CONFIGS=$(echo "$NOTIFICATION_CONFIG" | jq -c '.LambdaConfigurations[]?' 2>/dev/null)
    
    # Contar configuraciones
    TOPIC_COUNT=0
    QUEUE_COUNT=0
    LAMBDA_COUNT=0
    SNS_NOTIFICATIONS_FOR_BUCKET=0
    
    if [ -n "$TOPIC_CONFIGS" ]; then
        TOPIC_COUNT=$(echo "$TOPIC_CONFIGS" | wc -l)
        
        # Verificar si alguna configuración apunta a nuestro SNS Topic
        while IFS= read -r topic_config; do
            if [ -n "$topic_config" ]; then
                TOPIC_ARN=$(echo "$topic_config" | jq -r '.TopicArn' 2>/dev/null)
                EVENTS=$(echo "$topic_config" | jq -r '.Events[]' 2>/dev/null | tr '\n' ' ')
                CONFIG_ID=$(echo "$topic_config" | jq -r '.Id // "N/A"' 2>/dev/null)
                
                if [ "$TOPIC_ARN" == "$SNS_TOPIC_ARN" ]; then
                    SNS_NOTIFICATIONS_FOR_BUCKET=$((SNS_NOTIFICATIONS_FOR_BUCKET + 1))
                    echo -e "   ✅ Notificación SNS configurada (ID: ${GREEN}$CONFIG_ID${NC})"
                    echo -e "      📋 Eventos: ${BLUE}$EVENTS${NC}"
                else
                    echo -e "   📄 Otra notificación SNS: ${YELLOW}$(basename "$TOPIC_ARN")${NC} (ID: $CONFIG_ID)"
                    echo -e "      📋 Eventos: ${BLUE}$EVENTS${NC}"
                fi
            fi
        done <<< "$TOPIC_CONFIGS"
    fi
    
    if [ -n "$QUEUE_CONFIGS" ]; then
        QUEUE_COUNT=$(echo "$QUEUE_CONFIGS" | wc -l)
        echo -e "   📄 Notificaciones SQS configuradas: ${BLUE}$QUEUE_COUNT${NC}"
    fi
    
    if [ -n "$LAMBDA_CONFIGS" ]; then
        LAMBDA_COUNT=$(echo "$LAMBDA_CONFIGS" | wc -l)
        echo -e "   📄 Notificaciones Lambda configuradas: ${BLUE}$LAMBDA_COUNT${NC}"
    fi
    
    # Estadísticas del bucket
    BUCKET_TOTAL_NOTIFICATIONS=$((TOPIC_COUNT + QUEUE_COUNT + LAMBDA_COUNT))
    
    if [ $BUCKET_TOTAL_NOTIFICATIONS -gt 0 ]; then
        BUCKETS_WITH_NOTIFICATIONS=$((BUCKETS_WITH_NOTIFICATIONS + 1))
        TOTAL_NOTIFICATIONS=$((TOTAL_NOTIFICATIONS + BUCKET_TOTAL_NOTIFICATIONS))
        echo -e "   📊 Total notificaciones en bucket: ${GREEN}$BUCKET_TOTAL_NOTIFICATIONS${NC}"
    else
        echo -e "   ${YELLOW}⚪ Sin notificaciones configuradas${NC}"
    fi
    
    if [ $SNS_NOTIFICATIONS_FOR_BUCKET -gt 0 ]; then
        BUCKETS_WITH_SNS_NOTIFICATIONS=$((BUCKETS_WITH_SNS_NOTIFICATIONS + 1))
    fi
    
    # Verificar información adicional del bucket
    echo -e "${BLUE}   🔍 Información adicional del bucket:${NC}"
    
    # Verificar versionado
    VERSIONING=$(aws s3api get-bucket-versioning --bucket "$bucket" --profile "$PROFILE" --query 'Status' --output text 2>/dev/null)
    if [ -n "$VERSIONING" ] && [ "$VERSIONING" != "None" ]; then
        echo -e "      📦 Versionado: ${GREEN}$VERSIONING${NC}"
    else
        echo -e "      📦 Versionado: ${YELLOW}Deshabilitado${NC}"
    fi
    
    # Verificar cifrado
    ENCRYPTION=$(aws s3api get-bucket-encryption --bucket "$bucket" --profile "$PROFILE" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' --output text 2>/dev/null)
    if [ -n "$ENCRYPTION" ] && [ "$ENCRYPTION" != "None" ]; then
        echo -e "      🔒 Cifrado: ${GREEN}$ENCRYPTION${NC}"
    else
        echo -e "      🔒 Cifrado: ${YELLOW}No configurado${NC}"
    fi
    
    # Verificar logging de acceso
    ACCESS_LOGGING=$(aws s3api get-bucket-logging --bucket "$bucket" --profile "$PROFILE" --query 'LoggingEnabled.TargetBucket' --output text 2>/dev/null)
    if [ -n "$ACCESS_LOGGING" ] && [ "$ACCESS_LOGGING" != "None" ]; then
        echo -e "      📋 Access Logging: ${GREEN}Habilitado${NC} → $ACCESS_LOGGING"
    else
        echo -e "      📋 Access Logging: ${YELLOW}Deshabilitado${NC}"
    fi
    
    # Verificar tamaño aproximado del bucket
    OBJECT_COUNT=$(aws s3api list-objects-v2 --bucket "$bucket" --profile "$PROFILE" --query 'KeyCount' --output text 2>/dev/null)
    if [ -n "$OBJECT_COUNT" ] && [ "$OBJECT_COUNT" != "None" ]; then
        echo -e "      📊 Objetos: ${BLUE}$OBJECT_COUNT${NC}"
    fi
    
    echo ""
done

# Verificar integración con otros servicios
echo -e "${PURPLE}=== Verificando integración con otros servicios ===${NC}"

# Verificar CloudTrail para eventos de S3
echo -e "${BLUE}🔍 Verificando CloudTrail para eventos S3:${NC}"
CLOUDTRAIL_TRAILS=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[?IncludeGlobalServiceEvents==`true`].[Name,S3BucketName,IncludeGlobalServiceEvents]' --output table 2>/dev/null)

if [ -n "$CLOUDTRAIL_TRAILS" ]; then
    echo -e "   ✅ CloudTrail configurado para eventos globales:"
    echo "$CLOUDTRAIL_TRAILS"
    
    # Verificar eventos de datos S3
    TRAILS_WITH_S3=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[].Name' --output text 2>/dev/null)
    
    if [ -n "$TRAILS_WITH_S3" ]; then
        echo -e "   ${BLUE}📋 Verificando eventos de datos S3:${NC}"
        for trail in $TRAILS_WITH_S3; do
            S3_DATA_EVENTS=$(aws cloudtrail get-event-selectors --trail-name "$trail" --profile "$PROFILE" --region "$REGION" --query 'EventSelectors[].DataResources[?Type==`AWS::S3::Object`]' --output text 2>/dev/null)
            
            if [ -n "$S3_DATA_EVENTS" ]; then
                echo -e "      ✅ Trail '$trail' - Eventos de datos S3 habilitados"
            else
                echo -e "      ⚪ Trail '$trail' - Solo eventos de gestión"
            fi
        done
    fi
else
    echo -e "   ${YELLOW}⚠️ CloudTrail no configurado o sin eventos globales${NC}"
fi

# Verificar AWS Config para S3
echo -e "${BLUE}🔍 Verificando AWS Config para S3:${NC}"
CONFIG_RULES_S3=$(aws configservice describe-config-rules --profile "$PROFILE" --region "$REGION" --query 'ConfigRules[?contains(Source.SourceIdentifier, `S3`) || contains(ConfigRuleName, `s3`)].ConfigRuleName' --output text 2>/dev/null)

if [ -n "$CONFIG_RULES_S3" ] && [ "$CONFIG_RULES_S3" != "None" ]; then
    echo -e "   ✅ Reglas de AWS Config para S3 encontradas:"
    S3_RULES_COUNT=$(echo "$CONFIG_RULES_S3" | wc -w)
    echo -e "   📊 Total de reglas S3: ${GREEN}$S3_RULES_COUNT${NC}"
    
    for rule in $CONFIG_RULES_S3; do
        echo -e "      📋 $rule"
    done
else
    echo -e "   ${YELLOW}⚠️ No se encontraron reglas de AWS Config específicas para S3${NC}"
fi

echo ""

# Resumen final
echo -e "${PURPLE}=== RESUMEN DE VERIFICACIÓN ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -n "$SNS_TOPIC_ARN" ]; then
    echo -e "✅ SNS Topic: ${GREEN}CONFIGURADO${NC} - $SNS_TOPIC_ARN"
else
    echo -e "❌ SNS Topic: ${RED}NO CONFIGURADO${NC}"
fi

echo -e "📦 Total buckets S3: ${GREEN}$BUCKET_COUNT${NC}"
echo -e "📊 Buckets con notificaciones: ${GREEN}$BUCKETS_WITH_NOTIFICATIONS${NC}"
echo -e "📧 Buckets con notificaciones SNS configuradas: ${GREEN}$BUCKETS_WITH_SNS_NOTIFICATIONS${NC}"
echo -e "📋 Total de configuraciones de notificación: ${GREEN}$TOTAL_NOTIFICATIONS${NC}"

if [ $BUCKETS_WITH_ERRORS -gt 0 ]; then
    echo -e "❌ Buckets con errores de acceso: ${RED}$BUCKETS_WITH_ERRORS${NC}"
fi

# Calcular porcentaje de cobertura
if [ $BUCKET_COUNT -gt 0 ]; then
    COVERAGE_PERCENTAGE=$(( (BUCKETS_WITH_SNS_NOTIFICATIONS * 100) / BUCKET_COUNT ))
    echo -e "📊 Cobertura de notificaciones SNS: ${GREEN}$COVERAGE_PERCENTAGE%${NC}"
fi

echo ""
if [ $BUCKETS_WITH_SNS_NOTIFICATIONS -gt 0 ] && [ -n "$SNS_TOPIC_ARN" ]; then
    echo -e "${GREEN}🎉 S3 EVENT NOTIFICATIONS - CONFIGURACIÓN ACTIVA${NC}"
    echo -e "${BLUE}💡 Los eventos de S3 están generando notificaciones${NC}"
    
    if [ $BUCKETS_WITH_SNS_NOTIFICATIONS -lt $BUCKET_COUNT ]; then
        UNCONFIGURED_BUCKETS=$((BUCKET_COUNT - BUCKETS_WITH_SNS_NOTIFICATIONS))
        echo -e "${YELLOW}⚠️ Faltan $UNCONFIGURED_BUCKETS buckets por configurar${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN INCOMPLETA O FALTANTE${NC}"
    echo -e "${BLUE}💡 Ejecuta el script de configuración para habilitar S3 event notifications${NC}"
fi

echo ""
echo -e "${BLUE}📋 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Configurar notificaciones en buckets faltantes si es necesario"
echo "2. Probar las notificaciones con eventos de prueba"
echo "3. Implementar filtros específicos por prefijo/sufijo de objetos"
echo "4. Configurar procesamiento automatizado de eventos (Lambda)"
echo "5. Establecer procedimientos de respuesta a eventos críticos"
echo "6. Integrar con sistemas de monitoreo y alertas existentes"
echo "7. Revisar y optimizar la configuración de eventos periódicamente"