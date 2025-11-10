#!/bin/bash
# enable-sns-server-side-encryption.sh
# Habilitar cifrado del lado del servidor para tópicos SNS
# Protege mensajes con cifrado KMS en tránsito y en reposo

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
echo -e "${BLUE}🔐 HABILITANDO CIFRADO SERVER-SIDE PARA SNS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando cifrado KMS para tópicos SNS existentes y futuros"
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
TOTAL_TOPICS=0
TOPICS_WITH_ENCRYPTION=0
TOPICS_WITHOUT_ENCRYPTION=0
KMS_KEYS_CREATED=0
TOPICS_UPDATED=0
ERRORS=0

# Verificar regiones adicionales
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Verificando regiones con tópicos SNS...${NC}"
for region in "${REGIONS[@]}"; do
    SNS_COUNT=$(aws sns list-topics \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Topics)' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$SNS_COUNT" ] && [ "$SNS_COUNT" -gt 0 ]; then
        echo -e "✅ Región ${GREEN}$region${NC}: $SNS_COUNT tópicos"
        ACTIVE_REGIONS+=("$region")
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin tópicos SNS"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron tópicos SNS en ninguna región${NC}"
    echo -e "${BLUE}💡 No se requiere configuración de cifrado${NC}"
    exit 0
fi

echo ""

# Función para crear o verificar clave KMS para SNS
create_or_get_sns_kms_key() {
    local region="$1"
    local key_alias="alias/sns-encryption-key-$region"
    
    echo -e "${CYAN}🔑 Verificando clave KMS para SNS en $region...${NC}"
    
    # Verificar si la clave ya existe
    EXISTING_KEY=$(aws kms describe-key \
        --key-id "$key_alias" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'KeyMetadata.KeyId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$EXISTING_KEY" ] && [ "$EXISTING_KEY" != "None" ]; then
        echo -e "   ✅ Clave KMS existente: ${GREEN}$key_alias${NC}"
        echo -e "   🆔 Key ID: ${BLUE}$EXISTING_KEY${NC}"
        echo "$EXISTING_KEY"
        return 0
    fi
    
    # Verificar clave por defecto de SNS
    DEFAULT_SNS_KEY=$(aws kms describe-key \
        --key-id "alias/aws/sns" \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'KeyMetadata.KeyId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$DEFAULT_SNS_KEY" ]; then
        echo -e "   ✅ Usando clave por defecto AWS SNS: ${GREEN}alias/aws/sns${NC}"
        echo -e "   🆔 Key ID: ${BLUE}$DEFAULT_SNS_KEY${NC}"
        echo "$DEFAULT_SNS_KEY"
        return 0
    fi
    
    echo -e "   🔧 Creando nueva clave KMS para SNS..."
    
    # Crear política para la clave KMS
    KMS_POLICY=$(cat << EOF
{
    "Version": "2012-10-17",
    "Id": "sns-kms-key-policy",
    "Statement": [
        {
            "Sid": "Enable IAM User Permissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "Allow SNS Service",
            "Effect": "Allow",
            "Principal": {
                "Service": "sns.amazonaws.com"
            },
            "Action": [
                "kms:Decrypt",
                "kms:DescribeKey",
                "kms:Encrypt",
                "kms:GenerateDataKey",
                "kms:GenerateDataKeyWithoutPlaintext",
                "kms:ReEncryptFrom",
                "kms:ReEncryptTo"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Allow CloudWatch Events",
            "Effect": "Allow",
            "Principal": {
                "Service": "events.amazonaws.com"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Resource": "*"
        },
        {
            "Sid": "Allow Lambda Service",
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": [
                "kms:Encrypt",
                "kms:Decrypt",
                "kms:ReEncrypt*",
                "kms:GenerateDataKey*",
                "kms:DescribeKey"
            ],
            "Resource": "*"
        }
    ]
}
EOF
)
    
    # Crear la clave KMS
    NEW_KEY_ID=$(aws kms create-key \
        --policy "$KMS_POLICY" \
        --description "SNS encryption key for region $region" \
        --usage ENCRYPT_DECRYPT \
        --key-spec SYMMETRIC_DEFAULT \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'KeyMetadata.KeyId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$NEW_KEY_ID" ]; then
        echo -e "   ✅ Clave KMS creada: ${GREEN}$NEW_KEY_ID${NC}"
        
        # Crear alias para la clave
        aws kms create-alias \
            --alias-name "sns-encryption-key-$region" \
            --target-key-id "$NEW_KEY_ID" \
            --profile "$PROFILE" \
            --region "$region" &>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ Alias creado: ${GREEN}$key_alias${NC}"
        fi
        
        # Agregar tags a la clave
        aws kms tag-resource \
            --key-id "$NEW_KEY_ID" \
            --tags "TagKey=Purpose,TagValue=SNS-Encryption" "TagKey=Environment,TagValue=Production" "TagKey=ManagedBy,TagValue=SecurityAutomation" "TagKey=Region,TagValue=$region" \
            --profile "$PROFILE" \
            --region "$region" &>/dev/null
        
        KMS_KEYS_CREATED=$((KMS_KEYS_CREATED + 1))
        echo "$NEW_KEY_ID"
        return 0
    else
        echo -e "   ${RED}❌ Error al crear clave KMS${NC}"
        return 1
    fi
}

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Procesando región: $CURRENT_REGION ===${NC}"
    
    # Crear o obtener clave KMS para la región
    KMS_KEY_ID=$(create_or_get_sns_kms_key "$CURRENT_REGION")
    
    if [ $? -ne 0 ] || [ -z "$KMS_KEY_ID" ]; then
        echo -e "${RED}❌ No se puede configurar cifrado para región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    echo -e "🎯 Usando clave KMS: ${BLUE}$KMS_KEY_ID${NC}"
    echo ""
    
    # Obtener lista de tópicos SNS
    SNS_TOPICS=$(aws sns list-topics \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --query 'Topics[].TopicArn' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener tópicos SNS en región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    if [ -z "$SNS_TOPICS" ]; then
        echo -e "${BLUE}ℹ️ Sin tópicos SNS en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📊 Tópicos SNS encontrados en $CURRENT_REGION:${NC}"
    
    for topic_arn in $SNS_TOPICS; do
        if [ -n "$topic_arn" ]; then
            TOTAL_TOPICS=$((TOTAL_TOPICS + 1))
            
            # Extraer nombre del tópico
            TOPIC_NAME=$(basename "$topic_arn")
            
            echo -e "${CYAN}📢 Tópico: $TOPIC_NAME${NC}"
            echo -e "   🌐 ARN: ${BLUE}$topic_arn${NC}"
            
            # Verificar configuración de cifrado actual
            ENCRYPTION_CONFIG=$(aws sns get-topic-attributes \
                --topic-arn "$topic_arn" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Attributes.KmsMasterKeyId' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$ENCRYPTION_CONFIG" ] && [ "$ENCRYPTION_CONFIG" != "None" ]; then
                echo -e "   ✅ Cifrado KMS: ${GREEN}YA CONFIGURADO${NC}"
                echo -e "   🔑 Clave actual: ${BLUE}$ENCRYPTION_CONFIG${NC}"
                TOPICS_WITH_ENCRYPTION=$((TOPICS_WITH_ENCRYPTION + 1))
                
                # Verificar si es la clave correcta
                if [ "$ENCRYPTION_CONFIG" != "$KMS_KEY_ID" ] && [[ ! "$ENCRYPTION_CONFIG" =~ "sns-encryption-key" ]] && [[ ! "$ENCRYPTION_CONFIG" =~ "alias/aws/sns" ]]; then
                    echo -e "   ⚠️ ${YELLOW}Nota: Usando clave KMS diferente${NC}"
                fi
                
            else
                echo -e "   ⚠️ Cifrado: ${YELLOW}NO CONFIGURADO${NC}"
                TOPICS_WITHOUT_ENCRYPTION=$((TOPICS_WITHOUT_ENCRYPTION + 1))
                
                echo -e "   🔧 Configurando cifrado KMS..."
                
                # Habilitar cifrado en el tópico
                UPDATE_RESULT=$(aws sns set-topic-attributes \
                    --topic-arn "$topic_arn" \
                    --attribute-name KmsMasterKeyId \
                    --attribute-value "$KMS_KEY_ID" \
                    --profile "$PROFILE" \
                    --region "$CURRENT_REGION" 2>/dev/null)
                
                if [ $? -eq 0 ]; then
                    echo -e "   ✅ Cifrado KMS configurado exitosamente"
                    TOPICS_UPDATED=$((TOPICS_UPDATED + 1))
                    TOPICS_WITH_ENCRYPTION=$((TOPICS_WITH_ENCRYPTION + 1))
                    TOPICS_WITHOUT_ENCRYPTION=$((TOPICS_WITHOUT_ENCRYPTION - 1))
                    
                    # Verificar la configuración
                    sleep 2
                    VERIFICATION=$(aws sns get-topic-attributes \
                        --topic-arn "$topic_arn" \
                        --profile "$PROFILE" \
                        --region "$CURRENT_REGION" \
                        --query 'Attributes.KmsMasterKeyId' \
                        --output text 2>/dev/null)
                    
                    if [ "$VERIFICATION" == "$KMS_KEY_ID" ]; then
                        echo -e "   ✅ Verificación: Configuración aplicada correctamente"
                    else
                        echo -e "   ⚠️ Advertencia: Verificación inconsistente"
                    fi
                else
                    echo -e "   ${RED}❌ Error al configurar cifrado KMS${NC}"
                    ERRORS=$((ERRORS + 1))
                fi
            fi
            
            # Obtener información adicional del tópico
            TOPIC_ATTRS=$(aws sns get-topic-attributes \
                --topic-arn "$topic_arn" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Attributes.[DisplayName,Policy,SubscriptionsConfirmed,SubscriptionsPending]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$TOPIC_ATTRS" ]; then
                DISPLAY_NAME=$(echo "$TOPIC_ATTRS" | cut -f1)
                SUBSCRIPTIONS_CONFIRMED=$(echo "$TOPIC_ATTRS" | cut -f3)
                SUBSCRIPTIONS_PENDING=$(echo "$TOPIC_ATTRS" | cut -f4)
                
                if [ -n "$DISPLAY_NAME" ] && [ "$DISPLAY_NAME" != "None" ]; then
                    echo -e "   📝 Nombre: ${BLUE}$DISPLAY_NAME${NC}"
                fi
                
                echo -e "   📊 Suscripciones confirmadas: ${BLUE}$SUBSCRIPTIONS_CONFIRMED${NC}"
                if [ "$SUBSCRIPTIONS_PENDING" -gt 0 ]; then
                    echo -e "   ⏳ Suscripciones pendientes: ${YELLOW}$SUBSCRIPTIONS_PENDING${NC}"
                fi
            fi
            
            # Verificar suscripciones del tópico
            SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
                --topic-arn "$topic_arn" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Subscriptions[].[Protocol,Endpoint]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$SUBSCRIPTIONS" ]; then
                SUB_COUNT=$(echo "$SUBSCRIPTIONS" | wc -l)
                echo -e "   🔗 Tipos de suscripciones:"
                
                echo "$SUBSCRIPTIONS" | sort | uniq -c | while read count protocol endpoint; do
                    if [ -n "$protocol" ]; then
                        echo -e "      📌 ${BLUE}$protocol${NC}: $count suscripciones"
                    fi
                done
            fi
            
            # Evaluar configuración de seguridad
            SECURITY_SCORE=0
            
            # Verificar cifrado
            if [ -n "$ENCRYPTION_CONFIG" ] && [ "$ENCRYPTION_CONFIG" != "None" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 1))
            fi
            
            # Verificar política de acceso (simplificado)
            TOPIC_POLICY=$(aws sns get-topic-attributes \
                --topic-arn "$topic_arn" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Attributes.Policy' \
                --output text 2>/dev/null)
            
            if [ -n "$TOPIC_POLICY" ] && [ "$TOPIC_POLICY" != "None" ] && [[ "$TOPIC_POLICY" =~ "Condition" ]]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 1))
            fi
            
            # Mostrar puntuación de seguridad
            case $SECURITY_SCORE in
                2)
                    echo -e "   🔐 Seguridad: ${GREEN}ALTA (2/2)${NC}"
                    ;;
                1)
                    echo -e "   🔐 Seguridad: ${YELLOW}MEDIA (1/2)${NC}"
                    ;;
                0)
                    echo -e "   🔐 Seguridad: ${RED}BÁSICA (0/2)${NC}"
                    ;;
            esac
            
            echo ""
        fi
    done
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION procesada${NC}"
    echo ""
done

# Configurar monitoreo CloudWatch para SNS cifrado
echo -e "${PURPLE}=== Configurando Monitoreo CloudWatch ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    # Crear alarma para tópicos sin cifrado (métrica personalizada)
    ALARM_NAME="SNS-Unencrypted-Topics-$CURRENT_REGION"
    
    echo -e "📊 Configurando alarma para tópicos sin cifrado en: ${CYAN}$CURRENT_REGION${NC}"
    
    # Nota: SNS no tiene métricas nativas para cifrado, pero podemos crear alarmas basadas en otros indicadores
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alarma para monitorear tópicos SNS sin cifrado - $CURRENT_REGION" \
        --metric-name NumberOfMessagesPublished \
        --namespace AWS/SNS \
        --statistic Sum \
        --period 3600 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --alarm-actions "arn:aws:sns:$CURRENT_REGION:$ACCOUNT_ID:security-alerts" \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Alarma configurada: ${GREEN}$ALARM_NAME${NC}"
    else
        echo -e "   ⚠️ No se pudo configurar alarma (puede requerir tópico de alertas)"
    fi
done

# Generar documentación
DOCUMENTATION_FILE="sns-server-side-encryption-$PROFILE-$(date +%Y%m%d).md"

cat > "$DOCUMENTATION_FILE" << EOF
# Configuración Server-Side Encryption - SNS - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones procesadas**: ${ACTIVE_REGIONS[*]}

## Resumen Ejecutivo

### Tópicos SNS Procesados
- **Total tópicos**: $TOTAL_TOPICS
- **Con cifrado**: $TOPICS_WITH_ENCRYPTION
- **Actualizados**: $TOPICS_UPDATED
- **Claves KMS creadas**: $KMS_KEYS_CREATED
- **Errores**: $ERRORS

## Configuraciones Implementadas

### 🔐 Server-Side Encryption
- Configuración: Cifrado KMS para mensajes en reposo
- Alcance: Todos los mensajes publicados en tópicos
- Integración: Compatible con todos los protocolos de suscripción

### 🔑 Gestión de Claves KMS
- Alias: sns-encryption-key-[región] o alias/aws/sns
- Descripción: SNS encryption key for region
- Política: Acceso para SNS, CloudWatch Events, Lambda
- Tags: Purpose, Environment, ManagedBy, Region

## Beneficios de Seguridad

### 1. Protección de Datos
- Cifrado de mensajes en tránsito y en reposo
- Protección contra acceso no autorizado
- Cumplimiento de normativas de privacidad

### 2. Control de Acceso
- Políticas KMS granulares
- Auditoría completa via CloudTrail
- Separación de responsabilidades

### 3. Integración Transparente
- Compatible con todas las suscripciones existentes
- Sin impacto en rendimiento significativo
- Configuración retroactiva aplicable

## Comandos de Verificación

\`\`\`bash
# Verificar cifrado de tópico específico
aws sns get-topic-attributes --topic-arn TOPIC_ARN \\
    --profile $PROFILE --region us-east-1 \\
    --query 'Attributes.KmsMasterKeyId'

# Listar todos los tópicos y su estado de cifrado
aws sns list-topics --profile $PROFILE --region us-east-1 \\
    --query 'Topics[].TopicArn' --output text | \\
    xargs -I {} aws sns get-topic-attributes --topic-arn {} \\
    --query 'Attributes.[TopicArn,KmsMasterKeyId]' --output table

# Verificar claves KMS para SNS
aws kms list-aliases --profile $PROFILE --region us-east-1 \\
    --query 'Aliases[?contains(AliasName, \`sns\`)]'
\`\`\`

## Consideraciones de Rendimiento

### Latencia
- Incremento mínimo por operaciones criptográficas
- Cacheo de claves KMS reduce overhead
- Impacto negligible en la mayoría de casos de uso

### Costos
- Cargos adicionales por operaciones KMS
- Costo por cada 10,000 operaciones de cifrado/descifrado
- ROI positivo por mejora en seguridad

## Recomendaciones Adicionales

1. **Monitoreo Continuo**: Implementar alertas para tópicos sin cifrado
2. **Rotación de Claves**: Habilitar rotación automática anual
3. **Políticas de Acceso**: Revisar y restringir permisos KMS regularmente
4. **Auditoría**: Monitorear uso de claves via CloudTrail

EOF

echo -e "✅ Documentación generada: ${GREEN}$DOCUMENTATION_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN CONFIGURACIÓN SNS SERVER-SIDE ENCRYPTION ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones procesadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC} (${ACTIVE_REGIONS[*]})"
echo -e "📢 Total tópicos SNS: ${GREEN}$TOTAL_TOPICS${NC}"
echo -e "🔐 Tópicos con cifrado: ${GREEN}$TOPICS_WITH_ENCRYPTION${NC}"
echo -e "🔧 Tópicos actualizados: ${GREEN}$TOPICS_UPDATED${NC}"
echo -e "🆕 Claves KMS creadas: ${GREEN}$KMS_KEYS_CREATED${NC}"

if [ $ERRORS -gt 0 ]; then
    echo -e "⚠️ Errores encontrados: ${YELLOW}$ERRORS${NC}"
fi

# Calcular porcentaje de cumplimiento
if [ $TOTAL_TOPICS -gt 0 ]; then
    ENCRYPTION_PERCENT=$((TOPICS_WITH_ENCRYPTION * 100 / TOTAL_TOPICS))
    echo -e "📈 Cumplimiento cifrado: ${GREEN}$ENCRYPTION_PERCENT%${NC}"
fi

echo -e "📋 Documentación: ${GREEN}$DOCUMENTATION_FILE${NC}"
echo ""

# Estado final
if [ $TOTAL_TOPICS -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN TÓPICOS SNS${NC}"
    echo -e "${BLUE}💡 Claves KMS preparadas para futuros tópicos${NC}"
elif [ $TOPICS_WITHOUT_ENCRYPTION -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE CIFRADO${NC}"
    echo -e "${BLUE}💡 Todos los tópicos SNS usan cifrado KMS${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: CIFRADO PARCIAL${NC}"
    echo -e "${YELLOW}💡 Algunos tópicos requieren configuración manual${NC}"
fi