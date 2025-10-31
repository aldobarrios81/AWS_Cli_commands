#!/bin/bash
# verify-lambda-dead-letter-queues.sh
# Verificar configuraciones de Dead Letter Queues en funciones Lambda
# Validar que las funciones Lambda tengan DLQ configuradas para resiliencia

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
echo -e "${BLUE}🔍 VERIFICACIÓN LAMBDA DEAD LETTER QUEUES${NC}"
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
TOTAL_FUNCTIONS=0
FUNCTIONS_WITH_DLQ=0
FUNCTIONS_WITHOUT_DLQ=0
TOTAL_REGIONS=0
DLQ_QUEUES_FOUND=0

# Verificar regiones con funciones Lambda
REGIONS=("us-east-1" "us-west-2" "eu-west-1" "ap-southeast-1")
ACTIVE_REGIONS=()

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
        TOTAL_REGIONS=$((TOTAL_REGIONS + 1))
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin funciones Lambda"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron funciones Lambda en ninguna región${NC}"
    
    # Verificar si existen DLQ sin usar
    echo -e "${PURPLE}🔍 Verificando DLQ existentes...${NC}"
    for region in "${REGIONS[@]}"; do
        DLQ_QUEUES=$(aws sqs list-queues \
            --queue-name-prefix "lambda-dlq" \
            --profile "$PROFILE" \
            --region "$region" \
            --query 'QueueUrls' \
            --output text 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$DLQ_QUEUES" ] && [ "$DLQ_QUEUES" != "None" ]; then
            echo -e "⚠️ DLQ encontradas en ${YELLOW}$region${NC} sin funciones Lambda asociadas"
        fi
    done
    
    echo -e "${BLUE}💡 No se requiere verificación de DLQ${NC}"
    exit 0
fi

echo ""

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Análisis región: $CURRENT_REGION ===${NC}"
    
    # Verificar DLQ existentes en la región
    DLQ_QUEUES=$(aws sqs list-queues \
        --queue-name-prefix "lambda-dlq" \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'QueueUrls' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$DLQ_QUEUES" ] && [ "$DLQ_QUEUES" != "None" ]; then
        echo -e "✅ DLQ encontradas en región:"
        echo "$DLQ_QUEUES" | tr '\t' '\n' | while read -r queue_url; do
            if [ -n "$queue_url" ]; then
                DLQ_QUEUES_FOUND=$((DLQ_QUEUES_FOUND + 1))
                QUEUE_NAME=$(basename "$queue_url")
                echo -e "   📦 ${GREEN}$QUEUE_NAME${NC}"
                
                # Obtener estadísticas de la DLQ
                QUEUE_STATS=$(aws sqs get-queue-attributes \
                    --queue-url "$queue_url" \
                    --attribute-names ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible,MessageRetentionPeriod \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" \
                    --query 'Attributes.[ApproximateNumberOfMessages,ApproximateNumberOfMessagesNotVisible,MessageRetentionPeriod]' \
                    --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$QUEUE_STATS" ]; then
                    VISIBLE_MSGS=$(echo "$QUEUE_STATS" | cut -f1)
                    NOT_VISIBLE_MSGS=$(echo "$QUEUE_STATS" | cut -f2)
                    RETENTION=$(echo "$QUEUE_STATS" | cut -f3)
                    
                    echo -e "      📊 Mensajes visibles: ${BLUE}$VISIBLE_MSGS${NC}"
                    echo -e "      📊 Mensajes en procesamiento: ${BLUE}$NOT_VISIBLE_MSGS${NC}"
                    echo -e "      ⏰ Retención: ${BLUE}$(($RETENTION / 86400)) días${NC}"
                    
                    if [ "$VISIBLE_MSGS" -gt 0 ]; then
                        echo -e "      ⚠️ ${YELLOW}ATENCIÓN: Hay mensajes fallidos en la DLQ${NC}"
                    fi
                fi
            fi
        done
    else
        echo -e "⚠️ No se encontraron DLQ específicas de Lambda en región"
    fi
    
    echo ""
    
    # Obtener funciones Lambda y verificar DLQ
    LAMBDA_FUNCTIONS=$(aws lambda list-functions \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'Functions[].[FunctionName,Runtime,DeadLetterConfig.TargetArn,Timeout,MemorySize,LastModified]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener funciones Lambda en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}⚡ Funciones Lambda en $CURRENT_REGION:${NC}"
    
    while IFS=$'\t' read -r function_name runtime dlq_arn timeout memory last_modified; do
        if [ -n "$function_name" ] && [ "$function_name" != "None" ]; then
            TOTAL_FUNCTIONS=$((TOTAL_FUNCTIONS + 1))
            
            echo -e "${CYAN}📋 Función: $function_name${NC}"
            echo -e "   🔧 Runtime: ${BLUE}$runtime${NC}"
            echo -e "   ⏱️ Timeout: ${BLUE}${timeout}s${NC} | 💾 Memory: ${BLUE}${memory}MB${NC}"
            echo -e "   📅 Modificada: ${BLUE}$(echo "$last_modified" | cut -d'T' -f1)${NC}"
            
            # Verificar configuración de DLQ
            if [ -n "$dlq_arn" ] && [ "$dlq_arn" != "None" ]; then
                echo -e "   ✅ DLQ configurada: ${GREEN}$dlq_arn${NC}"
                FUNCTIONS_WITH_DLQ=$((FUNCTIONS_WITH_DLQ + 1))
                
                # Verificar tipo de DLQ (SQS o SNS)
                if [[ "$dlq_arn" =~ "sqs" ]]; then
                    echo -e "   📦 Tipo DLQ: ${GREEN}SQS Queue${NC}"
                elif [[ "$dlq_arn" =~ "sns" ]]; then
                    echo -e "   📧 Tipo DLQ: ${GREEN}SNS Topic${NC}"
                fi
                
                # Verificar si la DLQ existe
                if [[ "$dlq_arn" =~ "sqs" ]]; then
                    QUEUE_NAME=$(basename "$dlq_arn")
                    QUEUE_EXISTS=$(aws sqs get-queue-url \
                        --queue-name "$QUEUE_NAME" \
                        --profile "$PROFILE" \
                        --region "$CURRENT_REGION" \
                        --output text 2>/dev/null)
                    
                    if [ $? -eq 0 ]; then
                        echo -e "   ✅ DLQ verificada: ${GREEN}Existe y accesible${NC}"
                    else
                        echo -e "   ❌ DLQ problema: ${RED}No existe o sin acceso${NC}"
                    fi
                fi
                
            else
                echo -e "   ❌ DLQ: ${RED}NO CONFIGURADA${NC}"
                FUNCTIONS_WITHOUT_DLQ=$((FUNCTIONS_WITHOUT_DLQ + 1))
                
                # Análisis de riesgo basado en configuración
                RISK_LEVEL="BAJO"
                if [ "$timeout" -gt 300 ]; then  # > 5 minutos
                    RISK_LEVEL="ALTO"
                elif [ "$timeout" -gt 60 ]; then  # > 1 minuto
                    RISK_LEVEL="MEDIO"
                fi
                
                case $RISK_LEVEL in
                    "ALTO")
                        echo -e "   🔴 Riesgo: ${RED}ALTO${NC} - Función de larga duración sin DLQ"
                        ;;
                    "MEDIO")
                        echo -e "   🟡 Riesgo: ${YELLOW}MEDIO${NC} - Función sin DLQ"
                        ;;
                    "BAJO")
                        echo -e "   🟢 Riesgo: ${GREEN}BAJO${NC} - Función rápida sin DLQ"
                        ;;
                esac
            fi
            
            # Obtener métricas de errores recientes
            END_TIME=$(date -Iseconds)
            START_TIME=$(date -d '7 days ago' -Iseconds)
            
            ERROR_METRICS=$(aws cloudwatch get-metric-statistics \
                --namespace AWS/Lambda \
                --metric-name Errors \
                --dimensions Name=FunctionName,Value="$function_name" \
                --statistics Sum \
                --start-time "$START_TIME" \
                --end-time "$END_TIME" \
                --period 86400 \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Datapoints[*].Sum' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$ERROR_METRICS" ] && [ "$ERROR_METRICS" != "None" ]; then
                TOTAL_ERRORS=0
                for error_count in $ERROR_METRICS; do
                    TOTAL_ERRORS=$(echo "$TOTAL_ERRORS + $error_count" | bc 2>/dev/null || echo $((TOTAL_ERRORS + error_count)))
                done
                
                if [ "$TOTAL_ERRORS" -gt 0 ]; then
                    echo -e "   📊 Errores últimos 7 días: ${YELLOW}$TOTAL_ERRORS${NC}"
                    
                    if [ -z "$dlq_arn" ] || [ "$dlq_arn" == "None" ]; then
                        echo -e "   ⚠️ ${RED}CRÍTICO: Errores sin DLQ = pérdida de eventos${NC}"
                    fi
                else
                    echo -e "   📊 Errores últimos 7 días: ${GREEN}0${NC}"
                fi
            else
                echo -e "   📊 Métricas: ${BLUE}No disponibles${NC}"
            fi
            
            # Verificar configuraciones relacionadas
            FUNC_CONFIG=$(aws lambda get-function-configuration \
                --function-name "$function_name" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query '[ReservedConcurrencyLimit,Environment.Variables]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$FUNC_CONFIG" ]; then
                CONCURRENCY=$(echo "$FUNC_CONFIG" | cut -f1)
                if [ "$CONCURRENCY" != "None" ] && [ -n "$CONCURRENCY" ]; then
                    echo -e "   🔒 Concurrencia reservada: ${BLUE}$CONCURRENCY${NC}"
                fi
            fi
            
            echo ""
        fi
    done <<< "$LAMBDA_FUNCTIONS"
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION analizada${NC}"
    echo ""
done

# Verificar alarmas CloudWatch relacionadas con DLQ
echo -e "${PURPLE}=== Verificación Monitoreo CloudWatch ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    # Buscar alarmas relacionadas con Lambda DLQ
    DLQ_ALARMS=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix "Lambda-DLQ" \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'MetricAlarms[].[AlarmName,StateValue,StateReason]' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$DLQ_ALARMS" ] && [ "$DLQ_ALARMS" != "None" ]; then
        echo -e "✅ Alarmas DLQ en ${GREEN}$CURRENT_REGION${NC}:"
        
        while IFS=$'\t' read -r alarm_name state reason; do
            if [ -n "$alarm_name" ]; then
                case $state in
                    "OK")
                        echo -e "   ✅ ${GREEN}$alarm_name${NC}: $state"
                        ;;
                    "ALARM")
                        echo -e "   🚨 ${RED}$alarm_name${NC}: $state - $reason"
                        ;;
                    "INSUFFICIENT_DATA")
                        echo -e "   ⚠️ ${YELLOW}$alarm_name${NC}: $state"
                        ;;
                esac
            fi
        done <<< "$DLQ_ALARMS"
    else
        echo -e "⚠️ Sin alarmas DLQ configuradas en región: ${YELLOW}$CURRENT_REGION${NC}"
    fi
done

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="lambda-dlq-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "account_id": "$ACCOUNT_ID",
  "regions_analyzed": ${#ACTIVE_REGIONS[@]},
  "active_regions": [$(printf '"%s",' "${ACTIVE_REGIONS[@]}" | sed 's/,$//')]],
  "summary": {
    "total_functions": $TOTAL_FUNCTIONS,
    "functions_with_dlq": $FUNCTIONS_WITH_DLQ,
    "functions_without_dlq": $FUNCTIONS_WITHOUT_DLQ,
    "dlq_queues_found": $DLQ_QUEUES_FOUND,
    "dlq_compliance": "$(if [ $TOTAL_FUNCTIONS -eq 0 ]; then echo "NO_FUNCTIONS"; elif [ $FUNCTIONS_WITHOUT_DLQ -eq 0 ]; then echo "FULLY_COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "recommendations": [
    "Configurar DLQ para todas las funciones Lambda",
    "Implementar monitoreo CloudWatch para DLQ",
    "Establecer políticas de retención apropiadas",
    "Configurar alertas para mensajes en DLQ",
    "Implementar análisis regular de errores",
    "Considerar reprocessing automático donde sea apropiado"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ $FUNCTIONS_WITHOUT_DLQ -gt 0 ]; then
    echo -e "${PURPLE}=== Comandos de Remediación ===${NC}"
    echo -e "${CYAN}🔧 Para configurar DLQ automáticamente:${NC}"
    echo -e "${BLUE}./configure-lambda-dead-letter-queues.sh $PROFILE${NC}"
    
    echo -e "${CYAN}🔧 Comando manual para función específica:${NC}"
    echo -e "${BLUE}aws lambda update-function-configuration --function-name FUNCTION_NAME --dead-letter-config TargetArn=arn:aws:sqs:REGION:ACCOUNT:lambda-dlq-REGION --profile $PROFILE${NC}"
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN LAMBDA DLQ ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones activas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC} (${ACTIVE_REGIONS[*]})"
echo -e "⚡ Total funciones Lambda: ${GREEN}$TOTAL_FUNCTIONS${NC}"

if [ $TOTAL_FUNCTIONS -gt 0 ]; then
    echo -e "✅ Funciones con DLQ: ${GREEN}$FUNCTIONS_WITH_DLQ${NC}"
    if [ $FUNCTIONS_WITHOUT_DLQ -gt 0 ]; then
        echo -e "❌ Funciones sin DLQ: ${RED}$FUNCTIONS_WITHOUT_DLQ${NC}"
    fi
    echo -e "📦 DLQ encontradas: ${GREEN}$DLQ_QUEUES_FOUND${NC}"
    
    # Calcular porcentaje de cumplimiento
    DLQ_PERCENT=$((FUNCTIONS_WITH_DLQ * 100 / TOTAL_FUNCTIONS))
    echo -e "📈 Cumplimiento DLQ: ${GREEN}$DLQ_PERCENT%${NC}"
fi

echo ""

# Estado final
if [ $TOTAL_FUNCTIONS -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN FUNCIONES LAMBDA${NC}"
    echo -e "${BLUE}💡 No hay funciones para verificar${NC}"
elif [ $FUNCTIONS_WITHOUT_DLQ -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE CONFIGURADO${NC}"
    echo -e "${BLUE}💡 Todas las funciones Lambda tienen DLQ${NC}"
else
    echo -e "${RED}⚠️ ESTADO: REQUIERE CONFIGURACIÓN${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./configure-lambda-dead-letter-queues.sh $PROFILE${NC}"
fi

echo -e "📋 Reporte: ${GREEN}$VERIFICATION_REPORT${NC}"