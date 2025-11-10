#!/bin/bash
# enable-cloudformation-stack-notifications.sh
# Configurar notificaciones de eventos para stacks de CloudFormation
# Regla de seguridad: Enable event notifications for CloudFormation stacks
# Uso: ./enable-cloudformation-stack-notifications.sh [perfil]

# Verificar parámetros
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, azlogica"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
REGION="us-east-1"
SNS_TOPIC_NAME="cloudformation-stack-notifications"

# Configurar email según el perfil
case "$PROFILE" in
    "ancla")
        EMAIL="felipe.castillo@azlogica.com"
        ;;
    "azbeacons")
        EMAIL="felipe.castillo@azlogica.com"
        ;;
    "azcenit")
        EMAIL="felipe.castillo@azlogica.com"
        ;;
    "metrokia")
        EMAIL="felipe.castillo@azlogica.com"
        ;;
    "azlogica")
        EMAIL="felipe.castillo@azlogica.com"
        ;;
    *)
        echo "Error: Perfil '$PROFILE' no válido"
        echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, azlogica"
        exit 1
        ;;
esac

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔒 HABILITANDO CLOUDFORMATION STACK NOTIFICATIONS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando notificaciones de eventos para stacks CloudFormation"
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

# Paso 1: Crear SNS Topic para CloudFormation eventos
echo -e "${PURPLE}=== Paso 1: Configurando SNS Topic para CloudFormation Events ===${NC}"

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
    
    # Configurar política del SNS Topic para permitir publicación desde CloudFormation
    echo -e "${BLUE}📋 Configurando política del SNS Topic...${NC}"
    
    SNS_POLICY='{
        "Version": "2012-10-17",
        "Id": "CloudFormationNotificationPolicy",
        "Statement": [
            {
                "Sid": "AllowCloudFormationPublish",
                "Effect": "Allow",
                "Principal": {
                    "Service": "cloudformation.amazonaws.com"
                },
                "Action": "SNS:Publish",
                "Resource": "'$SNS_TOPIC_ARN'",
                "Condition": {
                    "StringEquals": {
                        "aws:SourceAccount": "'$ACCOUNT_ID'"
                    }
                }
            },
            {
                "Sid": "AllowAccountOwnerAccess",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::'$ACCOUNT_ID':root"
                },
                "Action": [
                    "SNS:Subscribe",
                    "SNS:Receive",
                    "SNS:Publish",
                    "SNS:ListSubscriptionsByTopic",
                    "SNS:GetTopicAttributes",
                    "SNS:SetTopicAttributes"
                ],
                "Resource": "'$SNS_TOPIC_ARN'"
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

# Paso 2: Obtener lista de stacks CloudFormation
echo -e "${PURPLE}=== Paso 2: Analizando stacks CloudFormation existentes ===${NC}"

# Obtener lista de stacks activos (excluyendo stacks problemáticos)
STACKS=$(aws cloudformation list-stacks --profile "$PROFILE" --region "$REGION" --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE --query 'StackSummaries[].StackName' --output text 2>/dev/null | tr '\t' '\n' | grep -Ev "(amplify|CDK|SST|DynamoTemplate|cdk-)")

if [ -z "$STACKS" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron stacks CloudFormation compatibles${NC}"
    echo -e "${BLUE}💡 Las notificaciones se configurarán para futuros stacks${NC}"
    
    # Crear archivo de configuración para referencia futura
    cat > "cloudformation-notifications-config-$PROFILE.json" << EOF
{
    "NotificationARNs": [
        "$SNS_TOPIC_ARN"
    ],
    "Profile": "$PROFILE",
    "Region": "$REGION",
    "Description": "Configuración de notificaciones para stacks CloudFormation",
    "Usage": "Usar este SNS ARN al crear o actualizar stacks CloudFormation"
}
EOF
    
    echo -e "   ✅ Archivo de configuración creado: ${GREEN}cloudformation-notifications-config-$PROFILE.json${NC}"
    
else
    STACK_COUNT=$(echo "$STACKS" | wc -l)
    echo -e "✅ Stacks CloudFormation compatibles encontrados: ${GREEN}$STACK_COUNT stacks${NC}"
    
    # Mostrar información básica de stacks
    echo -e "${BLUE}📄 Lista de stacks CloudFormation compatibles:${NC}"
    
    for stack in $STACKS; do
        # Obtener información básica del stack
        STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'Stacks[0].StackStatus' --output text 2>/dev/null)
        NOTIFICATION_ARNS=$(aws cloudformation describe-stacks --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'Stacks[0].NotificationARNs' --output text 2>/dev/null)
        
        # Verificar si ya tiene notificaciones configuradas
        if [ -n "$NOTIFICATION_ARNS" ] && [ "$NOTIFICATION_ARNS" != "None" ]; then
            if echo "$NOTIFICATION_ARNS" | grep -q "$SNS_TOPIC_ARN"; then
                NOTIFICATION_STATUS="${GREEN}✅ Configurado${NC}"
            else
                NOTIFICATION_STATUS="${YELLOW}⚪ Otras notif.${NC}"
            fi
        else
            NOTIFICATION_STATUS="${RED}❌ Sin configurar${NC}"
        fi
        
        echo -e "   📚 ${CYAN}$stack${NC} (${BLUE}$STACK_STATUS${NC}) - $NOTIFICATION_STATUS"
    done
    
    echo ""
fi

# Paso 3: Configurar notificaciones para stacks compatibles
if [ -n "$STACKS" ]; then
    echo -e "${PURPLE}=== Paso 3: Configurando notificaciones para stacks compatibles ===${NC}"
    
    SUCCESS_STACKS=()
    ALREADY_CONFIGURED=()
    FAILED_STACKS=()
    
    for stack in $STACKS; do
        echo -e "${CYAN}🔧 Configurando stack: ${BLUE}$stack${NC}"
        
        # Verificar notificaciones actuales
        CURRENT_NOTIFICATIONS=$(aws cloudformation describe-stacks --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'Stacks[0].NotificationARNs' --output json 2>/dev/null)
        
        # Verificar si ya está configurado nuestro SNS
        if echo "$CURRENT_NOTIFICATIONS" | jq -r '.[]?' | grep -q "$SNS_TOPIC_ARN" 2>/dev/null; then
            echo -e "   ✅ Ya configurado con nuestro SNS Topic"
            ALREADY_CONFIGURED+=("$stack")
            continue
        fi
        
        # Preparar lista de ARNs (existentes + nuevo)
        if [ "$CURRENT_NOTIFICATIONS" == "[]" ] || [ "$CURRENT_NOTIFICATIONS" == "null" ]; then
            NOTIFICATION_ARNS="$SNS_TOPIC_ARN"
        else
            EXISTING_ARNS=$(echo "$CURRENT_NOTIFICATIONS" | jq -r '.[]' 2>/dev/null | tr '\n' ' ')
            NOTIFICATION_ARNS="$SNS_TOPIC_ARN $EXISTING_ARNS"
        fi
        
        # Intentar actualizar el stack
        echo -e "   🔄 Actualizando configuración de notificaciones..."
        
        aws cloudformation update-stack \
            --stack-name "$stack" \
            --use-previous-template \
            --notification-arns $NOTIFICATION_ARNS \
            --profile "$PROFILE" \
            --region "$REGION" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ Notificaciones configuradas exitosamente"
            SUCCESS_STACKS+=("$stack")
        else
            echo -e "   ${YELLOW}⚠️ No se pudo configurar (stack puede requerir parámetros)${NC}"
            FAILED_STACKS+=("$stack")
        fi
        
        echo ""
    done
fi

# Crear script helper para configuración manual
if [ ${#FAILED_STACKS[@]} -gt 0 ]; then
    echo -e "${PURPLE}=== Paso 4: Creando script para configuración manual ===${NC}"
    
    HELPER_SCRIPT="configure-cloudformation-notifications-manual-$PROFILE.sh"
    
    cat > "$HELPER_SCRIPT" << EOF
#!/bin/bash
# Configurar notificaciones manualmente para stacks que requieren parámetros
# Generado para perfil: $PROFILE

PROFILE="$PROFILE"
REGION="$REGION"
SNS_TOPIC_ARN="$SNS_TOPIC_ARN"

echo "Configurando notificaciones manualmente para stacks problemáticos..."
echo "SNS Topic ARN: \$SNS_TOPIC_ARN"
echo ""

# Stacks que requieren configuración manual
FAILED_STACKS=(${FAILED_STACKS[@]})

for stack in "\${FAILED_STACKS[@]}"; do
    echo "Stack: \$stack"
    echo "Comando sugerido:"
    echo "aws cloudformation update-stack \\\\"
    echo "  --stack-name \$stack \\\\"
    echo "  --use-previous-template \\\\"
    echo "  --notification-arns \$SNS_TOPIC_ARN \\\\"
    echo "  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \\\\"
    echo "  --profile \$PROFILE \\\\"
    echo "  --region \$REGION"
    echo ""
    echo "Si el stack requiere parámetros, obtenerlos con:"
    echo "aws cloudformation describe-stacks --stack-name \$stack --profile \$PROFILE --region \$REGION --query 'Stacks[0].Parameters'"
    echo ""
    echo "────────────────────────────────────────────────────────"
    echo ""
done
EOF
    
    chmod +x "$HELPER_SCRIPT"
    echo -e "✅ Script de configuración manual creado: ${GREEN}$HELPER_SCRIPT${NC}"
fi

echo ""

# Resumen final
echo -e "${PURPLE}=== RESUMEN DE CONFIGURACIÓN ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📧 SNS Topic: ${GREEN}$SNS_TOPIC_ARN${NC}"

if [ -n "$STACKS" ]; then
    echo -e "📚 Total stacks compatibles: ${GREEN}$STACK_COUNT${NC}"
    
    if [ ${#SUCCESS_STACKS[@]} -gt 0 ]; then
        echo -e "✅ Stacks configurados exitosamente: ${GREEN}${#SUCCESS_STACKS[@]}${NC}"
    fi
    
    if [ ${#ALREADY_CONFIGURED[@]} -gt 0 ]; then
        echo -e "✅ Stacks ya configurados: ${GREEN}${#ALREADY_CONFIGURED[@]}${NC}"
    fi
    
    if [ ${#FAILED_STACKS[@]} -gt 0 ]; then
        echo -e "⚠️ Stacks que requieren configuración manual: ${YELLOW}${#FAILED_STACKS[@]}${NC}"
    fi
else
    echo -e "📚 Stacks CloudFormation: ${YELLOW}No hay stacks compatibles${NC}"
fi

TOTAL_CONFIGURED=$((${#SUCCESS_STACKS[@]} + ${#ALREADY_CONFIGURED[@]}))

echo ""
if [ $TOTAL_CONFIGURED -gt 0 ] || [ -z "$STACKS" ]; then
    echo -e "${GREEN}🎉 CLOUDFORMATION STACK NOTIFICATIONS CONFIGURADAS${NC}"
    echo -e "${BLUE}💡 Sistema de notificaciones CloudFormation está activo${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN PARCIAL${NC}"
    echo -e "${BLUE}💡 Algunos stacks requieren configuración manual${NC}"
fi

echo "SNS Topic ARN usado: $SNS_TOPIC_ARN"
echo "✅ Proceso completado"

