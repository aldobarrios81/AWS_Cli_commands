#!/bin/bash
# configure-lambda-dead-letter-queues.sh
# Configurar Dead Letter Queues (DLQ) para funciones Lambda
# Mejora la resiliencia y observabilidad de funciones serverless

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
echo -e "${BLUE}🔧 CONFIGURANDO DEAD LETTER QUEUES PARA LAMBDA${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando DLQ para mejorar resiliencia de funciones Lambda"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
AWS_VERSION=$(aws --version 2>/dev/null | head -1)
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error: AWS CLI no encontrado${NC}"
    exit 1
fi
echo -e "✅ AWS CLI encontrado: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
echo -e "🔐 Verificando credenciales para perfil '$PROFILE'..."
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"

# Variables de conteo
TOTAL_FUNCTIONS=0
FUNCTIONS_WITH_DLQ=0
FUNCTIONS_WITHOUT_DLQ=0
DLQ_CREATED=0
DLQ_CONFIGURED=0
ERRORS=0

# Verificar regiones adicionales
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Verificando regiones con funciones Lambda...${NC}"
for region in "${REGIONS[@]}"; do
    LAMBDA_COUNT=$(aws lambda list-functions \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Functions)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$LAMBDA_COUNT" ] && [ "$LAMBDA_COUNT" -gt 0 ]; then
        echo -e "✅ Región ${GREEN}$region${NC}: $LAMBDA_COUNT funciones"
        ACTIVE_REGIONS+=("$region")
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin funciones Lambda"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron funciones Lambda en ninguna región${NC}"
    echo -e "${BLUE}💡 No se requiere configuración de DLQ${NC}"
    exit 0
fi

echo ""

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Procesando región: $CURRENT_REGION ===${NC}"
    
    # Obtener lista de funciones Lambda
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'Functions[].[FunctionName,Runtime,DeadLetterConfig.TargetArn]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener funciones Lambda en región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    if [ -z "$LAMBDA_FUNCTIONS" ]; then
        echo -e "${BLUE}ℹ️ Sin funciones Lambda en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📊 Funciones Lambda encontradas en $CURRENT_REGION:${NC}"
    
    # Buscar DLQ disponibles en la región
    DLQ_ARN=""
    DLQ_NAME=""
    
    # Primero buscar DLQ existentes con nombres estándar
    STANDARD_DLQ_NAMES=("lambda-dlq-$CURRENT_REGION" "MyLambdaDLQ" "LambdaDeadLetterQueue" "lambda-dlq")
    
    for dlq_name in "${STANDARD_DLQ_NAMES[@]}"; do
        EXISTING_DLQ=$(aws sqs get-queue-url \
            --queue-name "$dlq_name" \
            --profile "$PROFILE" \
            --region "$CURRENT_REGION" \
            --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$EXISTING_DLQ" ]; then
            echo -e "✅ DLQ existente encontrada: ${GREEN}$dlq_name${NC}"
            DLQ_NAME="$dlq_name"
            
            # Obtener ARN de la DLQ existente
            DLQ_ARN=$(aws sqs get-queue-attributes \
                --queue-url "$EXISTING_DLQ" \
                --attribute-names QueueArn \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Attributes.QueueArn' \
                --output text 2>/dev/null)
            break
        fi
    done
    
    # Si no se encontró DLQ existente, crear una nueva
    if [ -z "$DLQ_ARN" ]; then
        DLQ_NAME="lambda-dlq-$CURRENT_REGION"
        echo -e "${CYAN}🔧 Creando DLQ: $DLQ_NAME${NC}"
        
        # Crear la DLQ con manejo mejorado de errores
        CREATE_RESULT=$(aws sqs create-queue \
            --queue-name "$DLQ_NAME" \
            --attributes '{
                "MessageRetentionPeriod": "1209600",
                "VisibilityTimeoutSeconds": "60",
                "ReceiveMessageWaitTimeSeconds": "20"
            }' \
            --profile "$PROFILE" \
            --region "$CURRENT_REGION" \
            --output json 2>&1)
        
        if [ $? -eq 0 ]; then
            DLQ_URL=$(echo "$CREATE_RESULT" | jq -r '.QueueUrl' 2>/dev/null)
            if [ -n "$DLQ_URL" ] && [ "$DLQ_URL" != "null" ]; then
                echo -e "   ✅ DLQ creada exitosamente: $DLQ_URL"
                DLQ_CREATED=$((DLQ_CREATED + 1))
                
                # Obtener ARN de la nueva DLQ
                DLQ_ARN=$(aws sqs get-queue-attributes \
                    --queue-url "$DLQ_URL" \
                    --attribute-names QueueArn \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" \
                    --query 'Attributes.QueueArn' \
                    --output text 2>/dev/null)
                
                # Agregar tags a la DLQ
                aws sqs tag-queue \
                    --queue-url "$DLQ_URL" \
                    --tags "Purpose=Lambda-DLQ,Environment=Production,ManagedBy=SecurityAutomation,Region=$CURRENT_REGION" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" &>/dev/null
            else
                echo -e "   ${RED}❌ Error: Respuesta de creación inválida${NC}"
                ERRORS=$((ERRORS + 1))
                continue
            fi
        else
            echo -e "   ${YELLOW}⚠️ No se puede crear DLQ nueva. Buscando alternativas...${NC}"
            
            # Buscar cualquier DLQ existente en la región
            ALL_QUEUES=$(aws sqs list-queues \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'QueueUrls[*]' \
                --output text 2>/dev/null)
            
            if [ -n "$ALL_QUEUES" ]; then
                for queue_url in $ALL_QUEUES; do
                    queue_name=$(basename "$queue_url")
                    if [[ "$queue_name" =~ [Dd][Ll][Qq] ]] || [[ "$queue_name" =~ [Dd]ead ]] || [[ "$queue_name" =~ [Ll]etter ]]; then
                        echo -e "   ✅ Usando DLQ existente: ${GREEN}$queue_name${NC}"
                        DLQ_NAME="$queue_name"
                        
                        DLQ_ARN=$(aws sqs get-queue-attributes \
                            --queue-url "$queue_url" \
                            --attribute-names QueueArn \
                            --profile "$PROFILE" \
                            --region "$CURRENT_REGION" \
                            --query 'Attributes.QueueArn' \
                            --output text 2>/dev/null)
                        break
                    fi
                done
            fi
            
            if [ -z "$DLQ_ARN" ]; then
                echo -e "   ${RED}❌ No se puede configurar DLQ para región $CURRENT_REGION${NC}"
                echo -e "   ${YELLOW}💡 Crear manualmente una DLQ o verificar permisos SQS${NC}"
                ERRORS=$((ERRORS + 1))
                continue
            fi
        fi
    fi
    
    echo -e "🎯 DLQ ARN: ${BLUE}$DLQ_ARN${NC}"
    echo ""
    
    # Procesar cada función Lambda
    while IFS=$'\t' read -r function_name runtime current_dlq_arn; do
        if [ -n "$function_name" ] && [ "$function_name" != "None" ]; then
            TOTAL_FUNCTIONS=$((TOTAL_FUNCTIONS + 1))
            
            echo -e "${CYAN}⚡ Función: $function_name${NC}"
            echo -e "   🔧 Runtime: ${BLUE}$runtime${NC}"
            
            # Verificar si ya tiene DLQ configurada
            if [ -n "$current_dlq_arn" ] && [ "$current_dlq_arn" != "None" ]; then
                echo -e "   ✅ DLQ ya configurada: ${GREEN}$current_dlq_arn${NC}"
                FUNCTIONS_WITH_DLQ=$((FUNCTIONS_WITH_DLQ + 1))
            else
                echo -e "   ⚠️ Sin DLQ configurada"
                FUNCTIONS_WITHOUT_DLQ=$((FUNCTIONS_WITHOUT_DLQ + 1))
                
                # Configurar DLQ para la función
                echo -e "   🔧 Configurando DLQ..."
                
                UPDATE_RESULT=$(aws lambda update-function-configuration \
                    --function-name "$function_name" \
                    --dead-letter-config "TargetArn=$DLQ_ARN" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" \
                    --query 'FunctionName' \
                    --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$UPDATE_RESULT" ]; then
                    echo -e "   ✅ DLQ configurada exitosamente"
                    DLQ_CONFIGURED=$((DLQ_CONFIGURED + 1))
                    FUNCTIONS_WITH_DLQ=$((FUNCTIONS_WITH_DLQ + 1))
                    FUNCTIONS_WITHOUT_DLQ=$((FUNCTIONS_WITHOUT_DLQ - 1))
                    
                    # Verificar la configuración
                    sleep 2
                    VERIFICATION=$(aws lambda get-function-configuration \
                        --function-name "$function_name" \
                        --profile "$PROFILE" \
                        --region "$CURRENT_REGION" \
                        --query 'DeadLetterConfig.TargetArn' \
                        --output text 2>/dev/null)
                    
                    if [ "$VERIFICATION" == "$DLQ_ARN" ]; then
                        echo -e "   ✅ Verificación: Configuración aplicada correctamente"
                    else
                        echo -e "   ⚠️ Advertencia: Verificación inconsistente"
                    fi
                else
                    echo -e "   ${RED}❌ Error al configurar DLQ${NC}"
                    ERRORS=$((ERRORS + 1))
                fi
            fi
            
            # Obtener información adicional de la función
            FUNC_INFO=$(aws lambda get-function-configuration \
                --function-name "$function_name" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query '[Timeout,MemorySize,LastModified]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$FUNC_INFO" ]; then
                echo -e "   ℹ️ Timeout: $(echo $FUNC_INFO | cut -f1)s | Memory: $(echo $FUNC_INFO | cut -f2)MB | Modified: $(echo $FUNC_INFO | cut -f3 | cut -d'T' -f1)"
            fi
            
            echo ""
        fi
    done <<< "$LAMBDA_FUNCTIONS"
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION procesada${NC}"
    echo ""
done

# Configurar CloudWatch Alarms para monitorear las DLQ
echo -e "${PURPLE}=== Configurando Monitoreo CloudWatch ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    DLQ_NAME="lambda-dlq-$CURRENT_REGION"
    
    # Crear alarma para mensajes en DLQ
    ALARM_NAME="Lambda-DLQ-Messages-$CURRENT_REGION"
    
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alarma para mensajes en Dead Letter Queue de Lambda - $CURRENT_REGION" \
        --metric-name ApproximateNumberOfVisibleMessages \
        --namespace AWS/SQS \
        --statistic Average \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "arn:aws:sns:$CURRENT_REGION:$ACCOUNT_ID:security-alerts" \
        --dimensions Name=QueueName,Value="$DLQ_NAME" \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "✅ Alarma CloudWatch creada para región: ${GREEN}$CURRENT_REGION${NC}"
    else
        echo -e "⚠️ Advertencia: No se pudo crear alarma para región: $CURRENT_REGION"
    fi
done

# Generar documentación
DOCUMENTATION_FILE="lambda-dlq-configuration-$PROFILE-$(date +%Y%m%d).md"

cat > "$DOCUMENTATION_FILE" << EOF
# Configuración Dead Letter Queues - Lambda - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones procesadas**: ${ACTIVE_REGIONS[*]}

## Resumen Ejecutivo

### Funciones Lambda Procesadas
- **Total funciones**: $TOTAL_FUNCTIONS
- **Con DLQ**: $FUNCTIONS_WITH_DLQ
- **DLQ creadas**: $DLQ_CREATED
- **DLQ configuradas**: $DLQ_CONFIGURED
- **Errores**: $ERRORS

## Configuraciones Implementadas

### 🔄 Dead Letter Queues
- Configuración: SQS como DLQ para funciones fallidas
- Retención de mensajes: 14 días
- Timeout de visibilidad: 60 segundos

### 📊 Monitoreo CloudWatch
- Alarmas para mensajes en DLQ
- Notificaciones automáticas vía SNS
- Métricas de disponibilidad

## Beneficios de Resiliencia

### 1. Recuperación de Errores
- Captura de eventos fallidos
- Análisis post-mortem disponible
- Reprocessing manual disponible

### 2. Observabilidad Mejorada
- Visibilidad de fallos de función
- Métricas de tasa de error
- Alertas proactivas

### 3. Debugging Facilitado
- Preservación de payloads fallidos
- Contexto completo de errores
- Trazabilidad de eventos

## Comandos de Verificación

\`\`\`bash
# Listar funciones y sus DLQ
aws lambda list-functions --profile $PROFILE --region us-east-1 \\
    --query 'Functions[].[FunctionName,DeadLetterConfig.TargetArn]' \\
    --output table

# Verificar mensajes en DLQ
aws sqs get-queue-attributes \\
    --queue-url https://sqs.us-east-1.amazonaws.com/$ACCOUNT_ID/lambda-dlq-us-east-1 \\
    --attribute-names ApproximateNumberOfMessages \\
    --profile $PROFILE

# Monitorear alarmas CloudWatch
aws cloudwatch describe-alarms \\
    --alarm-names "Lambda-DLQ-Messages-us-east-1" \\
    --profile $PROFILE --region us-east-1
\`\`\`

## Recomendaciones Adicionales

1. **Monitoreo Regular**: Revisar DLQ semanalmente
2. **Análisis de Fallos**: Investigar patrones de errores
3. **Optimización**: Ajustar timeout y memoria según análisis
4. **Automatización**: Implementar reprocessing automático donde sea apropiado

EOF

echo -e "✅ Documentación generada: ${GREEN}$DOCUMENTATION_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN CONFIGURACIÓN LAMBDA DLQ ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones procesadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC} (${ACTIVE_REGIONS[*]})"
echo -e "⚡ Total funciones Lambda: ${GREEN}$TOTAL_FUNCTIONS${NC}"
echo -e "✅ Funciones con DLQ: ${GREEN}$FUNCTIONS_WITH_DLQ${NC}"
echo -e "🔧 DLQ configuradas: ${GREEN}$DLQ_CONFIGURED${NC}"
echo -e "🆕 DLQ creadas: ${GREEN}$DLQ_CREATED${NC}"

if [ $ERRORS -gt 0 ]; then
    echo -e "⚠️ Errores encontrados: ${YELLOW}$ERRORS${NC}"
fi

# Calcular porcentaje de cumplimiento
if [ $TOTAL_FUNCTIONS -gt 0 ]; then
    DLQ_PERCENT=$((FUNCTIONS_WITH_DLQ * 100 / TOTAL_FUNCTIONS))
    echo -e "📈 Cumplimiento DLQ: ${GREEN}$DLQ_PERCENT%${NC}"
fi

echo -e "📋 Documentación: ${GREEN}$DOCUMENTATION_FILE${NC}"
echo ""

# Estado final
if [ $TOTAL_FUNCTIONS -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN FUNCIONES LAMBDA${NC}"
    echo -e "${BLUE}💡 No hay funciones para configurar${NC}"
elif [ $FUNCTIONS_WITHOUT_DLQ -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE CONFIGURADO${NC}"
    echo -e "${BLUE}💡 Todas las funciones Lambda tienen DLQ${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: PARCIALMENTE CONFIGURADO${NC}"
    echo -e "${YELLOW}💡 Algunas funciones requieren configuración manual${NC}"
fi