#!/bin/bash
# enable-s3-event-notifications.sh
# Configurar notificaciones de eventos para buckets S3
# Regla de seguridad: Enable S3 event notifications
# Uso: ./enable-s3-event-notifications.sh [perfil]

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
EMAIL="felipe.castillo@azlogica.com"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔒 HABILITANDO S3 EVENT NOTIFICATIONS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando notificaciones de eventos para buckets S3"
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

# Paso 1: Crear SNS Topic para S3 eventos
echo -e "${PURPLE}=== Paso 1: Configurando SNS Topic para S3 Events ===${NC}"

# Verificar si el SNS topic existe
SNS_TOPIC_ARN=$(aws sns list-topics --profile "$PROFILE" --region "$REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text 2>/dev/null)

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo -e "${YELLOW}📝 Creando SNS Topic: $SNS_TOPIC_NAME${NC}"
    SNS_TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --profile "$PROFILE" --region "$REGION" --query TopicArn --output text 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$SNS_TOPIC_ARN" ]; then
        echo -e "${RED}❌ Error creando SNS Topic${NC}"
        exit 1
    fi
    
    echo -e "✅ SNS Topic creado: ${GREEN}$SNS_TOPIC_ARN${NC}"
    
    # Configurar política del SNS Topic para permitir publicación desde S3
    echo -e "${BLUE}📋 Configurando política del SNS Topic...${NC}"
    
    SNS_POLICY='{
        "Version": "2012-10-17",
        "Id": "S3EventNotificationPolicy",
        "Statement": [
            {
                "Sid": "AllowS3Publish",
                "Effect": "Allow",
                "Principal": {
                    "Service": "s3.amazonaws.com"
                },
                "Action": "SNS:Publish",
                "Resource": "'$SNS_TOPIC_ARN'",
                "Condition": {
                    "StringEquals": {
                        "aws:SourceAccount": "'$ACCOUNT_ID'"
                    }
                }
            }
        ]
    }'
    
    # Aplicar política
    aws sns set-topic-attributes \
        --topic-arn "$SNS_TOPIC_ARN" \
        --attribute-name Policy \
        --attribute-value "$SNS_POLICY" \
        --profile "$PROFILE" \
        --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Política del SNS Topic configurada exitosamente"
    else
        echo -e "   ${YELLOW}⚠️ Advertencia: Error configurando política SNS${NC}"
    fi
    
else
    echo -e "✅ SNS Topic existente: ${GREEN}$SNS_TOPIC_ARN${NC}"
fi

# Configurar suscripción de email
echo -e "${BLUE}📬 Configurando suscripción de email...${NC}"

# Verificar si ya existe la suscripción
EXISTING_SUBSCRIPTION=$(aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" --query "Subscriptions[?Endpoint=='$EMAIL' && Protocol=='email'].SubscriptionArn" --output text 2>/dev/null)

if [ -z "$EXISTING_SUBSCRIPTION" ] || [ "$EXISTING_SUBSCRIPTION" == "None" ]; then
    echo -e "   📧 Creando suscripción para: ${BLUE}$EMAIL${NC}"
    aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol email --notification-endpoint "$EMAIL" --profile "$PROFILE" --region "$REGION" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Suscripción creada exitosamente"
        echo -e "   ${YELLOW}⚠️ Revisa tu email para confirmar la suscripción${NC}"
    else
        echo -e "   ${RED}❌ Error creando suscripción${NC}"
    fi
else
    echo -e "   ✅ Suscripción de email ya existe para: ${BLUE}$EMAIL${NC}"
    
    # Verificar estado de la suscripción
    SUBSCRIPTION_STATUS=$(aws sns get-subscription-attributes --subscription-arn "$EXISTING_SUBSCRIPTION" --profile "$PROFILE" --region "$REGION" --query 'Attributes.PendingConfirmation' --output text 2>/dev/null)
    
    if [ "$SUBSCRIPTION_STATUS" == "true" ]; then
        echo -e "   ${YELLOW}⚠️ Suscripción pendiente de confirmación${NC}"
    else
        echo -e "   ✅ Suscripción confirmada y activa"
    fi
fi

echo ""

# Paso 2: Obtener lista de buckets S3
echo -e "${PURPLE}=== Paso 2: Analizando buckets S3 existentes ===${NC}"

# Obtener lista de buckets
BUCKETS=$(aws s3api list-buckets --profile "$PROFILE" --query 'Buckets[].Name' --output text 2>/dev/null)

if [ -z "$BUCKETS" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron buckets S3 en la cuenta${NC}"
    echo -e "${BLUE}💡 Las notificaciones se configurarán cuando se creen nuevos buckets${NC}"
    exit 0
fi

BUCKET_COUNT=$(echo "$BUCKETS" | wc -w)
echo -e "✅ Buckets S3 encontrados: ${GREEN}$BUCKET_COUNT buckets${NC}"

# Mostrar lista de buckets con información básica
echo -e "${BLUE}📄 Lista de buckets S3:${NC}"
for bucket in $BUCKETS; do
    # Verificar región del bucket
    BUCKET_REGION=$(aws s3api get-bucket-location --bucket "$bucket" --profile "$PROFILE" --query 'LocationConstraint' --output text 2>/dev/null)
    
    if [ "$BUCKET_REGION" == "None" ] || [ -z "$BUCKET_REGION" ]; then
        BUCKET_REGION="us-east-1"
    fi
    
    # Verificar si ya tiene notificaciones configuradas
    EXISTING_NOTIFICATIONS=$(aws s3api get-bucket-notification-configuration --bucket "$bucket" --profile "$PROFILE" --query 'TopicConfigurations[].TopicArn' --output text 2>/dev/null)
    
    if [ -n "$EXISTING_NOTIFICATIONS" ] && [ "$EXISTING_NOTIFICATIONS" != "None" ]; then
        NOTIFICATION_STATUS="${GREEN}✅ Configurado${NC}"
        NOTIFICATION_COUNT=$(echo "$EXISTING_NOTIFICATIONS" | wc -w)
        NOTIFICATION_INFO="($NOTIFICATION_COUNT notificaciones)"
    else
        NOTIFICATION_STATUS="${YELLOW}⚪ Sin configurar${NC}"
        NOTIFICATION_INFO=""
    fi
    
    echo -e "   📦 ${CYAN}$bucket${NC} (${BLUE}$BUCKET_REGION${NC}) - $NOTIFICATION_STATUS $NOTIFICATION_INFO"
done

echo ""

# Paso 3: Configurar notificaciones para buckets
echo -e "${PURPLE}=== Paso 3: Configurando notificaciones de eventos S3 ===${NC}"

BUCKETS_CONFIGURED=0
BUCKETS_SKIPPED=0
BUCKETS_ERRORS=0

for bucket in $BUCKETS; do
    echo -e "${BLUE}🔧 Configurando notificaciones para bucket: ${CYAN}$bucket${NC}"
    
    # Verificar región del bucket
    BUCKET_REGION=$(aws s3api get-bucket-location --bucket "$bucket" --profile "$PROFILE" --query 'LocationConstraint' --output text 2>/dev/null)
    
    if [ "$BUCKET_REGION" == "None" ] || [ -z "$BUCKET_REGION" ]; then
        BUCKET_REGION="us-east-1"
    fi
    
    # Verificar notificaciones existentes
    EXISTING_CONFIG=$(aws s3api get-bucket-notification-configuration --bucket "$bucket" --profile "$PROFILE" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "   ${RED}❌ Error accediendo al bucket (permisos insuficientes)${NC}"
        BUCKETS_ERRORS=$((BUCKETS_ERRORS + 1))
        continue
    fi
    
    # Verificar si ya existe configuración para nuestro SNS Topic
    EXISTING_SNS_CONFIG=$(echo "$EXISTING_CONFIG" | jq -r '.TopicConfigurations[]? | select(.TopicArn == "'$SNS_TOPIC_ARN'") | .TopicArn' 2>/dev/null)
    
    if [ -n "$EXISTING_SNS_CONFIG" ]; then
        echo -e "   ✅ Notificaciones ya configuradas para este SNS Topic"
        BUCKETS_SKIPPED=$((BUCKETS_SKIPPED + 1))
        continue
    fi
    
    # Crear configuración de notificaciones
    # Preservar configuraciones existentes y agregar la nueva
    EXISTING_TOPICS=$(echo "$EXISTING_CONFIG" | jq -c '.TopicConfigurations // []' 2>/dev/null)
    EXISTING_QUEUES=$(echo "$EXISTING_CONFIG" | jq -c '.QueueConfigurations // []' 2>/dev/null)
    EXISTING_LAMBDAS=$(echo "$EXISTING_CONFIG" | jq -c '.LambdaConfigurations // []' 2>/dev/null)
    
    # Configuración de eventos críticos de S3
    NEW_NOTIFICATION_CONFIG='{
        "TopicConfigurations": [
            {
                "Id": "S3EventNotification-'$(date +%s)'",
                "TopicArn": "'$SNS_TOPIC_ARN'",
                "Events": [
                    "s3:ObjectCreated:*",
                    "s3:ObjectRemoved:*",
                    "s3:ObjectRestore:*",
                    "s3:Replication:*",
                    "s3:ObjectAcl:Put",
                    "s3:BucketNotification"
                ]
            }
        ]
    }'
    
    # Si hay configuraciones existentes, combinarlas
    if [ "$EXISTING_TOPICS" != "[]" ] && [ -n "$EXISTING_TOPICS" ]; then
        COMBINED_TOPICS=$(echo "$EXISTING_TOPICS" | jq '. + [{"Id": "S3EventNotification-'$(date +%s)'", "TopicArn": "'$SNS_TOPIC_ARN'", "Events": ["s3:ObjectCreated:*", "s3:ObjectRemoved:*", "s3:ObjectRestore:*", "s3:Replication:*", "s3:ObjectAcl:Put", "s3:BucketNotification"]}]' 2>/dev/null)
    else
        COMBINED_TOPICS='[{"Id": "S3EventNotification-'$(date +%s)'", "TopicArn": "'$SNS_TOPIC_ARN'", "Events": ["s3:ObjectCreated:*", "s3:ObjectRemoved:*", "s3:ObjectRestore:*", "s3:Replication:*", "s3:ObjectAcl:Put", "s3:BucketNotification"]}]'
    fi
    
    # Construir configuración completa
    FULL_CONFIG=$(jq -n \
        --argjson topics "$COMBINED_TOPICS" \
        --argjson queues "$EXISTING_QUEUES" \
        --argjson lambdas "$EXISTING_LAMBDAS" \
        '{
            "TopicConfigurations": $topics,
            "QueueConfigurations": $queues,
            "LambdaConfigurations": $lambdas
        }' 2>/dev/null)
    
    # Aplicar configuración
    echo "$FULL_CONFIG" | aws s3api put-bucket-notification-configuration \
        --bucket "$bucket" \
        --notification-configuration file:///dev/stdin \
        --profile "$PROFILE" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Notificaciones configuradas exitosamente"
        echo -e "   📋 Eventos monitoreados:"
        echo -e "      • Object Created (todas las variantes)"
        echo -e "      • Object Removed (eliminaciones)"
        echo -e "      • Object Restore (restauraciones)"
        echo -e "      • Replication events (replicación)"
        echo -e "      • Object ACL changes (cambios de permisos)"
        echo -e "      • Bucket notifications (notificaciones del bucket)"
        BUCKETS_CONFIGURED=$((BUCKETS_CONFIGURED + 1))
    else
        echo -e "   ${RED}❌ Error configurando notificaciones${NC}"
        echo -e "   ${YELLOW}💡 Verifica permisos y que el bucket no esté en otra región${NC}"
        BUCKETS_ERRORS=$((BUCKETS_ERRORS + 1))
    fi
    
    echo ""
done

# Paso 4: Configurar notificaciones a nivel de cuenta (opcional)
echo -e "${PURPLE}=== Paso 4: Configuraciones adicionales ===${NC}"

# Crear función Lambda simple para procesar eventos (opcional)
echo -e "${BLUE}📝 Configuraciones de seguridad adicionales:${NC}"

# Verificar si CloudTrail está capturando eventos de S3
echo -e "${CYAN}🔍 Verificando integración con CloudTrail...${NC}"

CLOUDTRAIL_S3_EVENTS=$(aws cloudtrail describe-trails --profile "$PROFILE" --region "$REGION" --query 'trailList[?IncludeGlobalServiceEvents==`true`].[Name,S3BucketName,IncludeGlobalServiceEvents]' --output table 2>/dev/null)

if [ -n "$CLOUDTRAIL_S3_EVENTS" ]; then
    echo -e "   ✅ CloudTrail configurado para eventos globales"
    echo "$CLOUDTRAIL_S3_EVENTS"
else
    echo -e "   ${YELLOW}⚠️ CloudTrail no configurado para eventos S3${NC}"
fi

# Verificar configuración de AWS Config para S3
echo -e "${CYAN}🔍 Verificando integración con AWS Config...${NC}"

CONFIG_RULES_S3=$(aws configservice describe-config-rules --profile "$PROFILE" --region "$REGION" --query 'ConfigRules[?contains(Source.SourceIdentifier, `S3`) || contains(ConfigRuleName, `s3`)].ConfigRuleName' --output text 2>/dev/null)

if [ -n "$CONFIG_RULES_S3" ] && [ "$CONFIG_RULES_S3" != "None" ]; then
    echo -e "   ✅ Reglas de AWS Config para S3 encontradas:"
    for rule in $CONFIG_RULES_S3; do
        echo -e "      📋 $rule"
    done
else
    echo -e "   ${YELLOW}⚠️ No se encontraron reglas de AWS Config específicas para S3${NC}"
fi

echo ""

# Resumen final
echo -e "${PURPLE}=== RESUMEN DE CONFIGURACIÓN ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📧 SNS Topic: ${GREEN}$SNS_TOPIC_ARN${NC}"
echo -e "📦 Total buckets S3: ${GREEN}$BUCKET_COUNT${NC}"
echo -e "✅ Buckets configurados: ${GREEN}$BUCKETS_CONFIGURED${NC}"
echo -e "⚪ Buckets ya configurados: ${YELLOW}$BUCKETS_SKIPPED${NC}"
echo -e "❌ Buckets con errores: ${RED}$BUCKETS_ERRORS${NC}"

echo ""
if [ $BUCKETS_CONFIGURED -gt 0 ] || [ $BUCKETS_SKIPPED -gt 0 ]; then
    echo -e "${GREEN}🎉 S3 EVENT NOTIFICATIONS CONFIGURADAS EXITOSAMENTE${NC}"
    echo -e "${BLUE}💡 Los eventos de S3 generarán notificaciones automáticas${NC}"
else
    echo -e "${YELLOW}⚠️ NO SE PUDIERON CONFIGURAR NOTIFICACIONES${NC}"
    echo -e "${BLUE}💡 Revisa permisos y configuración de buckets${NC}"
fi

echo ""

echo -e "${YELLOW}📋 EVENTOS S3 QUE ACTIVARÁN NOTIFICACIONES:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 Creación de objetos:"
echo "   • s3:ObjectCreated:Put - Objetos subidos via PUT"
echo "   • s3:ObjectCreated:Post - Objetos subidos via POST"
echo "   • s3:ObjectCreated:Copy - Objetos copiados"
echo "   • s3:ObjectCreated:CompleteMultipartUpload - Uploads multiparte"
echo ""
echo "🗑️  Eliminación de objetos:"
echo "   • s3:ObjectRemoved:Delete - Eliminación permanente"
echo "   • s3:ObjectRemoved:DeleteMarkerCreated - Marcador de eliminación"
echo ""
echo "🔄 Operaciones avanzadas:"
echo "   • s3:ObjectRestore:Post/Completed - Restauraciones de Glacier"
echo "   • s3:Replication:* - Eventos de replicación"
echo "   • s3:ObjectAcl:Put - Cambios en ACLs de objetos"
echo ""
echo "📊 Eventos del bucket:"
echo "   • s3:BucketNotification - Cambios en configuración de notificaciones"
echo ""

echo -e "${BLUE}📋 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Confirmar suscripción de email si está pendiente"
echo "2. Probar las notificaciones subiendo/eliminando un objeto de prueba"
echo "3. Configurar filtros adicionales por prefijo/sufijo si es necesario"
echo "4. Implementar procesamiento automatizado de eventos (Lambda)"
echo "5. Establecer procedimientos de respuesta a eventos críticos"
echo "6. Configurar retención y archivado de notificaciones"
echo "7. Integrar con sistemas de monitoreo y SIEM existentes"