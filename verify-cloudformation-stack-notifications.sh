#!/bin/bash
# verify-cloudformation-stack-notifications.sh
# Verificar configuración de notificaciones para stacks CloudFormation
# Regla de seguridad: Verify CloudFormation stack notifications
# Uso: ./verify-cloudformation-stack-notifications.sh [perfil]

# Verificar parámetros
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
REGION="us-east-1"
SNS_TOPIC_NAME="cloudformation-stack-notifications"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔍 VERIFICANDO CLOUDFORMATION STACK NOTIFICATIONS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Verificando configuración de notificaciones CloudFormation"
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
echo -e "${PURPLE}=== Verificando SNS Topic para CloudFormation Events ===${NC}"
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
        # Verificar si la política permite publicación desde CloudFormation
        CF_PERMISSION=$(echo "$SNS_POLICY" | jq -r '.Statement[]? | select(.Principal.Service == "cloudformation.amazonaws.com") | .Effect' 2>/dev/null)
        
        if [ "$CF_PERMISSION" == "Allow" ]; then
            echo -e "   ✅ Política configurada correctamente para CloudFormation"
        else
            echo -e "   ${YELLOW}⚠️ Política no configurada para CloudFormation${NC}"
        fi
    else
        echo -e "   ${YELLOW}⚠️ No se pudo verificar la política del SNS Topic${NC}"
    fi
    
    # Verificar suscripciones
    echo -e "${BLUE}📧 Suscripciones configuradas:${NC}"
    aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --profile "$PROFILE" --region "$REGION" --output table --query 'Subscriptions[*].[Endpoint,Protocol,SubscriptionArn]' 2>/dev/null
fi
echo ""

# Verificar stacks CloudFormation y sus notificaciones
echo -e "${PURPLE}=== Verificando stacks CloudFormation y notificaciones ===${NC}"

# Obtener todos los stacks (incluyendo los no compatibles para análisis completo)
ALL_STACKS=$(aws cloudformation list-stacks --profile "$PROFILE" --region "$REGION" --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE --query 'StackSummaries[].StackName' --output text 2>/dev/null)

if [ -z "$ALL_STACKS" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron stacks CloudFormation${NC}"
    exit 0
fi

TOTAL_STACKS=$(echo "$ALL_STACKS" | wc -w)
echo -e "${GREEN}✅ Stacks CloudFormation encontrados: $TOTAL_STACKS stacks${NC}"

# Filtrar stacks compatibles
COMPATIBLE_STACKS=$(echo "$ALL_STACKS" | tr ' ' '\n' | grep -Ev "(amplify|CDK|SST|DynamoTemplate|cdk-)")
INCOMPATIBLE_STACKS=$(echo "$ALL_STACKS" | tr ' ' '\n' | grep -E "(amplify|CDK|SST|DynamoTemplate|cdk-)")

COMPATIBLE_COUNT=$(echo "$COMPATIBLE_STACKS" | wc -l)
INCOMPATIBLE_COUNT=$(echo "$INCOMPATIBLE_STACKS" | wc -l)

if [ -z "$COMPATIBLE_STACKS" ]; then
    COMPATIBLE_COUNT=0
fi

if [ -z "$INCOMPATIBLE_STACKS" ]; then
    INCOMPATIBLE_COUNT=0
fi

echo -e "${BLUE}📊 Análisis de compatibilidad:${NC}"
echo -e "   📚 Stacks compatibles: ${GREEN}$COMPATIBLE_COUNT${NC}"
echo -e "   📚 Stacks no compatibles (Amplify/CDK): ${YELLOW}$INCOMPATIBLE_COUNT${NC}"

# Estadísticas globales
STACKS_WITH_NOTIFICATIONS=0
STACKS_WITH_OUR_SNS=0
STACKS_WITHOUT_NOTIFICATIONS=0
STACKS_WITH_OTHER_NOTIFICATIONS=0

echo ""
echo -e "${BLUE}📊 Análisis detallado de stacks compatibles:${NC}"
echo ""

if [ $COMPATIBLE_COUNT -gt 0 ]; then
    # Crear tabla de análisis
    printf "%-35s %-20s %-15s %-25s\n" "Stack Name" "Status" "Created" "Notifications"
    echo "─────────────────────────────────────────────────────────────────────────────────────────────────"
    
    for stack in $COMPATIBLE_STACKS; do
        echo -e "${CYAN}📚 Analizando stack: $stack${NC}"
        
        # Obtener información del stack
        STACK_INFO=$(aws cloudformation describe-stacks --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'Stacks[0]' --output json 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo -e "   ${RED}❌ Error accediendo al stack${NC}"
            continue
        fi
        
        STACK_STATUS=$(echo "$STACK_INFO" | jq -r '.StackStatus' 2>/dev/null)
        CREATION_TIME=$(echo "$STACK_INFO" | jq -r '.CreationTime' 2>/dev/null | cut -d'T' -f1)
        NOTIFICATION_ARNS=$(echo "$STACK_INFO" | jq -r '.NotificationARNs[]?' 2>/dev/null)
        
        # Analizar notificaciones
        if [ -n "$NOTIFICATION_ARNS" ]; then
            STACKS_WITH_NOTIFICATIONS=$((STACKS_WITH_NOTIFICATIONS + 1))
            
            # Verificar si incluye nuestro SNS
            if echo "$NOTIFICATION_ARNS" | grep -q "$SNS_TOPIC_ARN"; then
                STACKS_WITH_OUR_SNS=$((STACKS_WITH_OUR_SNS + 1))
                NOTIFICATION_STATUS="✅ Configurado"
                echo -e "   ✅ Nuestro SNS Topic configurado"
            else
                STACKS_WITH_OTHER_NOTIFICATIONS=$((STACKS_WITH_OTHER_NOTIFICATIONS + 1))
                OTHER_COUNT=$(echo "$NOTIFICATION_ARNS" | wc -l)
                NOTIFICATION_STATUS="⚪ Otras ($OTHER_COUNT)"
                echo -e "   ⚪ Otras notificaciones SNS configuradas:"
            fi
            
            # Mostrar todos los ARNs configurados
            echo "$NOTIFICATION_ARNS" | while read arn; do
                if [ -n "$arn" ]; then
                    TOPIC_NAME=$(basename "$arn")
                    if [ "$arn" == "$SNS_TOPIC_ARN" ]; then
                        echo -e "      ✅ $TOPIC_NAME (nuestro topic)"
                    else
                        echo -e "      📄 $TOPIC_NAME"
                    fi
                fi
            done
        else
            STACKS_WITHOUT_NOTIFICATIONS=$((STACKS_WITHOUT_NOTIFICATIONS + 1))
            NOTIFICATION_STATUS="❌ Sin configurar"
            echo -e "   ❌ Sin notificaciones configuradas"
        fi
        
        # Información adicional del stack
        echo -e "   📊 Estado: ${BLUE}$STACK_STATUS${NC}"
        echo -e "   📅 Creado: ${BLUE}$CREATION_TIME${NC}"
        
        # Verificar recursos del stack
        RESOURCE_COUNT=$(aws cloudformation describe-stack-resources --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'length(StackResources)' --output text 2>/dev/null)
        if [ -n "$RESOURCE_COUNT" ]; then
            echo -e "   📦 Recursos: ${BLUE}$RESOURCE_COUNT${NC}"
        fi
        
        # Verificar eventos recientes
        RECENT_EVENTS=$(aws cloudformation describe-stack-events --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'StackEvents[0:2].[Timestamp,ResourceStatus,ResourceType]' --output table 2>/dev/null)
        if [ -n "$RECENT_EVENTS" ]; then
            echo -e "   🕒 Eventos recientes:"
            echo "$RECENT_EVENTS" | tail -n +3 | head -n 3 | while read line; do
                echo -e "      📋 $line"
            done
        fi
        
        echo ""
    done
else
    echo -e "${YELLOW}⚠️ No hay stacks compatibles para analizar${NC}"
fi

# Análisis de stacks no compatibles
if [ $INCOMPATIBLE_COUNT -gt 0 ]; then
    echo -e "${BLUE}📊 Stacks no compatibles (no se configuran notificaciones):${NC}"
    
    for stack in $INCOMPATIBLE_STACKS; do
        STACK_TYPE="Desconocido"
        
        if echo "$stack" | grep -q "amplify"; then
            STACK_TYPE="Amplify"
        elif echo "$stack" | grep -q -i "cdk"; then
            STACK_TYPE="CDK"
        elif echo "$stack" | grep -q "SST"; then
            STACK_TYPE="SST"
        elif echo "$stack" | grep -q "DynamoTemplate"; then
            STACK_TYPE="DynamoDB Template"
        fi
        
        echo -e "   🚫 ${YELLOW}$stack${NC} ($STACK_TYPE)"
    done
    echo ""
fi

# Verificar eventos recientes de CloudFormation a nivel de cuenta
echo -e "${PURPLE}=== Verificando actividad reciente de CloudFormation ===${NC}"

# Buscar eventos de los últimos 7 días en stacks con notificaciones
RECENT_ACTIVITY=0

if [ $STACKS_WITH_OUR_SNS -gt 0 ]; then
    echo -e "${BLUE}🔍 Verificando eventos recientes en stacks con notificaciones:${NC}"
    
    for stack in $COMPATIBLE_STACKS; do
        # Verificar si este stack tiene nuestras notificaciones
        HAS_OUR_SNS=$(aws cloudformation describe-stacks --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'Stacks[0].NotificationARNs' --output text 2>/dev/null | grep -c "$SNS_TOPIC_ARN")
        
        if [ "$HAS_OUR_SNS" -gt 0 ]; then
            # Buscar eventos de los últimos 7 días
            RECENT_EVENTS_COUNT=$(aws cloudformation describe-stack-events --stack-name "$stack" --profile "$PROFILE" --region "$REGION" --query 'length(StackEvents[?Timestamp > `'$(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ)'`])' --output text 2>/dev/null)
            
            if [ -n "$RECENT_EVENTS_COUNT" ] && [ "$RECENT_EVENTS_COUNT" -gt 0 ]; then
                RECENT_ACTIVITY=$((RECENT_ACTIVITY + RECENT_EVENTS_COUNT))
                echo -e "   📊 $stack: ${BLUE}$RECENT_EVENTS_COUNT eventos${NC} (últimos 7 días)"
            fi
        fi
    done
    
    if [ $RECENT_ACTIVITY -gt 0 ]; then
        echo -e "   📈 Total eventos recientes: ${GREEN}$RECENT_ACTIVITY${NC}"
    else
        echo -e "   📊 No hay actividad reciente en stacks monitoreados"
    fi
else
    echo -e "${YELLOW}⚠️ No hay stacks con nuestras notificaciones para monitorear${NC}"
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

echo -e "📚 Total stacks CloudFormation: ${GREEN}$TOTAL_STACKS${NC}"
echo -e "📊 Stacks compatibles: ${GREEN}$COMPATIBLE_COUNT${NC}"
echo -e "📊 Stacks no compatibles: ${YELLOW}$INCOMPATIBLE_COUNT${NC}"

if [ $COMPATIBLE_COUNT -gt 0 ]; then
    echo -e "✅ Stacks con nuestras notificaciones: ${GREEN}$STACKS_WITH_OUR_SNS${NC}"
    echo -e "⚪ Stacks con otras notificaciones: ${YELLOW}$STACKS_WITH_OTHER_NOTIFICATIONS${NC}"
    echo -e "❌ Stacks sin notificaciones: ${RED}$STACKS_WITHOUT_NOTIFICATIONS${NC}"
    
    # Calcular porcentaje de cobertura
    if [ $COMPATIBLE_COUNT -gt 0 ]; then
        COVERAGE_PERCENTAGE=$(( (STACKS_WITH_OUR_SNS * 100) / COMPATIBLE_COUNT ))
        echo -e "📊 Cobertura de notificaciones: ${GREEN}$COVERAGE_PERCENTAGE%${NC}"
    fi
fi

if [ $RECENT_ACTIVITY -gt 0 ]; then
    echo -e "📈 Actividad reciente monitoreable: ${GREEN}$RECENT_ACTIVITY eventos${NC}"
fi

echo ""
if [ $STACKS_WITH_OUR_SNS -gt 0 ] && [ -n "$SNS_TOPIC_ARN" ]; then
    echo -e "${GREEN}🎉 CLOUDFORMATION NOTIFICATIONS - CONFIGURACIÓN ACTIVA${NC}"
    echo -e "${BLUE}💡 Los eventos de CloudFormation están siendo monitoreados${NC}"
    
    if [ $STACKS_WITH_OUR_SNS -lt $COMPATIBLE_COUNT ]; then
        UNCONFIGURED_STACKS=$((COMPATIBLE_COUNT - STACKS_WITH_OUR_SNS))
        echo -e "${YELLOW}⚠️ Faltan $UNCONFIGURED_STACKS stacks por configurar${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN INCOMPLETA O FALTANTE${NC}"
    echo -e "${BLUE}💡 Ejecuta el script de configuración para habilitar CloudFormation notifications${NC}"
fi

echo ""
echo -e "${BLUE}📋 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Configurar notificaciones en stacks faltantes si es necesario"
echo "2. Probar las notificaciones actualizando un stack de prueba"
echo "3. Establecer procedimientos de respuesta a fallos de stack"
echo "4. Integrar notificaciones con sistemas de CI/CD"
echo "5. Documentar el proceso para el equipo de desarrollo"
echo "6. Configurar filtros adicionales si hay demasiado ruido"
echo "7. Revisar y optimizar las notificaciones periódicamente"