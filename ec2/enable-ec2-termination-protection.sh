#!/bin/bash
# enable-ec2-termination-protection.sh
# Habilitar protección contra terminación para instancias EC2
# Protege instancias críticas contra eliminación accidental o maliciosa

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
echo -e "${BLUE}🔒 HABILITANDO PROTECCIÓN TERMINACIÓN EC2${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando protección contra terminación en instancias EC2"
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
TOTAL_INSTANCES=0
PROTECTED_INSTANCES=0
UNPROTECTED_INSTANCES=0
INSTANCES_UPDATED=0
ERRORS=0
CRITICAL_INSTANCES=0
NON_CRITICAL_INSTANCES=0

# Verificar regiones adicionales
REGIONS=("us-east-1" "us-west-2" "eu-west-1")
ACTIVE_REGIONS=()

echo ""
echo -e "${PURPLE}🌍 Verificando regiones con instancias EC2...${NC}"
for region in "${REGIONS[@]}"; do
    INSTANCE_COUNT=$(aws ec2 describe-instances \
        --profile "$PROFILE" \
        --region "$region" \
        --query 'length(Reservations[].Instances[])' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$INSTANCE_COUNT" ] && [ "$INSTANCE_COUNT" -gt 0 ]; then
        echo -e "✅ Región ${GREEN}$region${NC}: $INSTANCE_COUNT instancias"
        ACTIVE_REGIONS+=("$region")
    else
        echo -e "ℹ️ Región ${BLUE}$region${NC}: Sin instancias EC2"
    fi
done

if [ ${#ACTIVE_REGIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ No se encontraron instancias EC2 en ninguna región${NC}"
    echo -e "${BLUE}💡 No se requiere configuración de protección${NC}"
    exit 0
fi

echo ""

# Función para determinar criticidad de instancia
determine_instance_criticality() {
    local instance_id="$1"
    local instance_type="$2"
    local instance_name="$3"
    local tags="$4"
    local region="$5"
    
    local is_critical=false
    local criticality_reasons=()
    
    # Criterios de criticidad por tipo de instancia
    if [[ "$instance_type" =~ ^(t2\.micro|t3\.micro|t3a\.micro)$ ]]; then
        # Instancias pequeñas generalmente no críticas
        is_critical=false
    elif [[ "$instance_type" =~ ^(m5|m6|c5|c6|r5|r6) ]]; then
        # Instancias de producción típicamente críticas
        is_critical=true
        criticality_reasons+=("Tipo de instancia de producción")
    fi
    
    # Criterios por nombre
    if [[ "$instance_name" =~ (prod|production|critical|database|db|web|app|server) ]]; then
        is_critical=true
        criticality_reasons+=("Nombre indica ambiente de producción")
    fi
    
    # Criterios por tags
    if [[ "$tags" =~ Environment.*[Pp]rod ]]; then
        is_critical=true
        criticality_reasons+=("Tag de Environment=Production")
    fi
    
    if [[ "$tags" =~ Role.*(database|web|app|api|server) ]]; then
        is_critical=true
        criticality_reasons+=("Tag de Role crítico")
    fi
    
    if [[ "$tags" =~ Critical.*true ]]; then
        is_critical=true
        criticality_reasons+=("Tag Critical=true")
    fi
    
    # Verificar si tiene EIP asociada
    local eip_check=$(aws ec2 describe-addresses \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=instance-id,Values=$instance_id" \
        --query 'Addresses[0].PublicIp' \
        --output text 2>/dev/null)
    
    if [ -n "$eip_check" ] && [ "$eip_check" != "None" ]; then
        is_critical=true
        criticality_reasons+=("Tiene Elastic IP asociada")
    fi
    
    # Verificar si tiene volúmenes EBS adicionales
    local volume_count=$(aws ec2 describe-volumes \
        --profile "$PROFILE" \
        --region "$region" \
        --filters "Name=attachment.instance-id,Values=$instance_id" \
        --query 'length(Volumes)' \
        --output text 2>/dev/null)
    
    if [ -n "$volume_count" ] && [ "$volume_count" -gt 1 ]; then
        is_critical=true
        criticality_reasons+=("Múltiples volúmenes EBS")
    fi
    
    if [ "$is_critical" = true ]; then
        echo "CRITICAL|${criticality_reasons[*]}"
    else
        echo "NON_CRITICAL|Instancia de desarrollo/testing"
    fi
}

# Función para aplicar protección de terminación
apply_termination_protection() {
    local instance_id="$1"
    local region="$2"
    
    echo -e "   🔧 Habilitando protección de terminación..."
    
    PROTECTION_RESULT=$(aws ec2 modify-instance-attribute \
        --instance-id "$instance_id" \
        --disable-api-termination \
        --profile "$PROFILE" \
        --region "$region" 2>/dev/null)
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Protección habilitada exitosamente"
        return 0
    else
        echo -e "   ${RED}❌ Error al habilitar protección${NC}"
        return 1
    fi
}

# Procesar cada región activa
for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    echo -e "${PURPLE}=== Procesando región: $CURRENT_REGION ===${NC}"
    
    # Obtener instancias EC2 en ejecución
    INSTANCES_DATA=$(aws ec2 describe-instances \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" \
        --filters "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,DisableApiTermination,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Error al obtener instancias EC2 en región $CURRENT_REGION${NC}"
        ERRORS=$((ERRORS + 1))
        continue
    fi
    
    if [ -z "$INSTANCES_DATA" ]; then
        echo -e "${BLUE}ℹ️ Sin instancias EC2 en región $CURRENT_REGION${NC}"
        continue
    fi
    
    echo -e "${GREEN}📊 Instancias EC2 encontradas en $CURRENT_REGION:${NC}"
    
    while IFS=$'\t' read -r instance_id instance_type state termination_protection instance_name; do
        if [ -n "$instance_id" ]; then
            TOTAL_INSTANCES=$((TOTAL_INSTANCES + 1))
            
            # Si no hay nombre, usar ID como nombre
            if [ -z "$instance_name" ] || [ "$instance_name" = "None" ]; then
                instance_name="$instance_id"
            fi
            
            echo -e "${CYAN}🖥️ Instancia: $instance_name${NC}"
            echo -e "   🆔 ID: ${BLUE}$instance_id${NC}"
            echo -e "   📦 Tipo: ${BLUE}$instance_type${NC}"
            echo -e "   🔄 Estado: ${BLUE}$state${NC}"
            
            # Obtener información adicional de la instancia
            INSTANCE_DETAILS=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Reservations[0].Instances[0].[LaunchTime,SecurityGroups[0].GroupId,SubnetId,Tags]' \
                --output json 2>/dev/null)
            
            if [ $? -eq 0 ]; then
                LAUNCH_TIME=$(echo "$INSTANCE_DETAILS" | jq -r '.[0]' 2>/dev/null)
                SECURITY_GROUP=$(echo "$INSTANCE_DETAILS" | jq -r '.[1]' 2>/dev/null)
                SUBNET_ID=$(echo "$INSTANCE_DETAILS" | jq -r '.[2]' 2>/dev/null)
                TAGS_JSON=$(echo "$INSTANCE_DETAILS" | jq -r '.[3]' 2>/dev/null)
                
                if [ -n "$LAUNCH_TIME" ] && [ "$LAUNCH_TIME" != "null" ]; then
                    # Calcular antigüedad
                    LAUNCH_DATE=$(date -d "$LAUNCH_TIME" +%Y-%m-%d 2>/dev/null)
                    if [ -n "$LAUNCH_DATE" ]; then
                        echo -e "   📅 Lanzada: ${BLUE}$LAUNCH_DATE${NC}"
                    fi
                fi
                
                if [ -n "$SECURITY_GROUP" ] && [ "$SECURITY_GROUP" != "null" ]; then
                    echo -e "   🛡️ Security Group: ${BLUE}$SECURITY_GROUP${NC}"
                fi
                
                if [ -n "$SUBNET_ID" ] && [ "$SUBNET_ID" != "null" ]; then
                    echo -e "   🌐 Subnet: ${BLUE}$SUBNET_ID${NC}"
                fi
            fi
            
            # Verificar estado actual de protección
            if [ "$termination_protection" = "True" ] || [ "$termination_protection" = "true" ]; then
                echo -e "   ✅ Protección: ${GREEN}YA HABILITADA${NC}"
                PROTECTED_INSTANCES=$((PROTECTED_INSTANCES + 1))
            else
                echo -e "   ❌ Protección: ${RED}NO CONFIGURADA${NC}"
                UNPROTECTED_INSTANCES=$((UNPROTECTED_INSTANCES + 1))
                
                # Determinar criticidad de la instancia
                TAGS_STRING=$(echo "$TAGS_JSON" | jq -r 'map(select(.Key and .Value) | "\(.Key)=\(.Value)") | join(" ")' 2>/dev/null)
                CRITICALITY_RESULT=$(determine_instance_criticality "$instance_id" "$instance_type" "$instance_name" "$TAGS_STRING" "$CURRENT_REGION")
                
                IFS='|' read -r criticality_level criticality_reasons <<< "$CRITICALITY_RESULT"
                
                if [ "$criticality_level" = "CRITICAL" ]; then
                    echo -e "   🔴 Criticidad: ${RED}CRÍTICA${NC}"
                    echo -e "   📋 Razones: ${YELLOW}$criticality_reasons${NC}"
                    CRITICAL_INSTANCES=$((CRITICAL_INSTANCES + 1))
                else
                    echo -e "   🟡 Criticidad: ${YELLOW}NO CRÍTICA${NC}"
                    echo -e "   📋 Razones: ${BLUE}$criticality_reasons${NC}"
                    NON_CRITICAL_INSTANCES=$((NON_CRITICAL_INSTANCES + 1))
                fi
                
                # Aplicar protección automáticamente para instancias críticas
                # Para no críticas, mostrar recomendación
                if [ "$criticality_level" = "CRITICAL" ]; then
                    if apply_termination_protection "$instance_id" "$CURRENT_REGION"; then
                        INSTANCES_UPDATED=$((INSTANCES_UPDATED + 1))
                        PROTECTED_INSTANCES=$((PROTECTED_INSTANCES + 1))
                        UNPROTECTED_INSTANCES=$((UNPROTECTED_INSTANCES - 1))
                        
                        # Verificar la aplicación
                        sleep 2
                        VERIFICATION=$(aws ec2 describe-instance-attribute \
                            --instance-id "$instance_id" \
                            --attribute disableApiTermination \
                            --profile "$PROFILE" \
                            --region "$CURRENT_REGION" \
                            --query 'DisableApiTermination.Value' \
                            --output text 2>/dev/null)
                        
                        if [ "$VERIFICATION" = "True" ]; then
                            echo -e "   ✅ Verificación: Protección aplicada correctamente"
                        else
                            echo -e "   ⚠️ Advertencia: Verificación inconsistente"
                        fi
                    else
                        ERRORS=$((ERRORS + 1))
                    fi
                else
                    echo -e "   💡 ${BLUE}Recomendación: Evaluar si requiere protección${NC}"
                    echo -e "      Para habilitar manualmente:"
                    echo -e "      ${CYAN}aws ec2 modify-instance-attribute --instance-id $instance_id --disable-api-termination${NC}"
                fi
            fi
            
            # Verificar información adicional de seguridad
            
            # Verificar si tiene backup habilitado
            BACKUP_TAGS=$(echo "$TAGS_JSON" | jq -r 'map(select(.Key == "Backup" or .Key == "backup")) | .[].Value' 2>/dev/null)
            if [ -n "$BACKUP_TAGS" ] && [ "$BACKUP_TAGS" != "null" ]; then
                echo -e "   💾 Backup: ${GREEN}Configurado ($BACKUP_TAGS)${NC}"
            else
                echo -e "   💾 Backup: ${YELLOW}Sin configurar${NC}"
            fi
            
            # Verificar monitoring
            MONITORING=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Reservations[0].Instances[0].Monitoring.State' \
                --output text 2>/dev/null)
            
            if [ "$MONITORING" = "enabled" ]; then
                echo -e "   📊 Monitoring: ${GREEN}Habilitado${NC}"
            else
                echo -e "   📊 Monitoring: ${YELLOW}Básico${NC}"
            fi
            
            # Verificar si tiene roles IAM asociados
            IAM_ROLE=$(aws ec2 describe-instances \
                --instance-ids "$instance_id" \
                --profile "$PROFILE" \
                --region "$CURRENT_REGION" \
                --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
                --output text 2>/dev/null)
            
            if [ -n "$IAM_ROLE" ] && [ "$IAM_ROLE" != "None" ]; then
                ROLE_NAME=$(basename "$IAM_ROLE")
                echo -e "   👤 IAM Role: ${GREEN}$ROLE_NAME${NC}"
            else
                echo -e "   👤 IAM Role: ${YELLOW}Sin rol asociado${NC}"
            fi
            
            # Evaluar puntuación de seguridad
            SECURITY_SCORE=0
            
            # Verificar protección de terminación
            if [ "$termination_protection" = "True" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 25))
            fi
            
            # Verificar backup
            if [ -n "$BACKUP_TAGS" ] && [ "$BACKUP_TAGS" != "null" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 20))
            fi
            
            # Verificar monitoring
            if [ "$MONITORING" = "enabled" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 15))
            fi
            
            # Verificar IAM role
            if [ -n "$IAM_ROLE" ] && [ "$IAM_ROLE" != "None" ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 15))
            fi
            
            # Verificar tags
            TAG_COUNT=$(echo "$TAGS_JSON" | jq 'length' 2>/dev/null)
            if [ -n "$TAG_COUNT" ] && [ "$TAG_COUNT" -gt 2 ]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 10))
            fi
            
            # Verificar si está en VPC privada
            if [[ "$SUBNET_ID" =~ subnet- ]]; then
                SECURITY_SCORE=$((SECURITY_SCORE + 15))
            fi
            
            # Mostrar puntuación de seguridad
            case $SECURITY_SCORE in
                [8-9][0-9]|100)
                    echo -e "   🔐 Seguridad: ${GREEN}EXCELENTE ($SECURITY_SCORE/100)${NC}"
                    ;;
                [6-7][0-9])
                    echo -e "   🔐 Seguridad: ${GREEN}BUENA ($SECURITY_SCORE/100)${NC}"
                    ;;
                [4-5][0-9])
                    echo -e "   🔐 Seguridad: ${YELLOW}MEDIA ($SECURITY_SCORE/100)${NC}"
                    ;;
                [2-3][0-9])
                    echo -e "   🔐 Seguridad: ${YELLOW}BAJA ($SECURITY_SCORE/100)${NC}"
                    ;;
                *)
                    echo -e "   🔐 Seguridad: ${RED}CRÍTICA ($SECURITY_SCORE/100)${NC}"
                    ;;
            esac
            
            echo ""
        fi
    done <<< "$INSTANCES_DATA"
    
    echo -e "${GREEN}✅ Región $CURRENT_REGION procesada${NC}"
    echo ""
done

# Configurar monitoreo CloudWatch para instancias protegidas
echo -e "${PURPLE}=== Configurando Monitoreo CloudWatch ===${NC}"

for CURRENT_REGION in "${ACTIVE_REGIONS[@]}"; do
    # Crear alarma para cambios de protección de terminación
    ALARM_NAME="EC2-Termination-Protection-Changes-$CURRENT_REGION"
    
    echo -e "📊 Configurando alarma para cambios de protección en: ${CYAN}$CURRENT_REGION${NC}"
    
    # Nota: Esta alarma se basa en eventos de CloudTrail
    aws cloudwatch put-metric-alarm \
        --alarm-name "$ALARM_NAME" \
        --alarm-description "Alarma para detectar cambios en protección de terminación EC2 - $CURRENT_REGION" \
        --actions-enabled \
        --alarm-actions "arn:aws:sns:$CURRENT_REGION:$ACCOUNT_ID:security-alerts" \
        --metric-name "EC2TerminationProtectionChanges" \
        --namespace "Custom/Security" \
        --statistic Sum \
        --period 300 \
        --threshold 1 \
        --comparison-operator GreaterThanOrEqualToThreshold \
        --evaluation-periods 1 \
        --profile "$PROFILE" \
        --region "$CURRENT_REGION" &>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Alarma configurada: ${GREEN}$ALARM_NAME${NC}"
    else
        echo -e "   ⚠️ No se pudo configurar alarma (requiere tópico SNS y métricas personalizadas)"
    fi
done

# Generar reporte de tags recomendados para protección
echo -e "${PURPLE}=== Recomendaciones de Tags de Protección ===${NC}"

cat << 'EOF'
📋 Tags recomendados para instancias críticas:

🔴 Tags de Criticidad:
   • Critical=true
   • Environment=Production
   • Role=Database|WebServer|AppServer|API
   • Tier=Critical|High|Medium|Low

🛡️ Tags de Protección:
   • TerminationProtection=Enabled
   • Backup=Daily|Weekly|Monthly
   • MonitoringLevel=Enhanced|Basic
   • MaintenanceWindow=Sunday-2AM-4AM

👥 Tags de Responsabilidad:
   • Owner=TeamName
   • Contact=email@company.com
   • Project=ProjectName
   • CostCenter=12345

📊 Tags de Gestión:
   • AutoShutdown=Disabled
   • PatchGroup=Critical|Standard
   • ComplianceRequired=Yes|No
   • DataClassification=Confidential|Internal|Public
EOF

echo ""

# Generar documentación
DOCUMENTATION_FILE="ec2-termination-protection-$PROFILE-$(date +%Y%m%d).md"

cat > "$DOCUMENTATION_FILE" << EOF
# Configuración Protección Terminación EC2 - $PROFILE

**Fecha**: $(date)
**Account ID**: $ACCOUNT_ID
**Regiones procesadas**: ${ACTIVE_REGIONS[*]}

## Resumen Ejecutivo

### Instancias EC2 Procesadas
- **Total instancias**: $TOTAL_INSTANCES
- **Con protección**: $PROTECTED_INSTANCES
- **Sin protección**: $UNPROTECTED_INSTANCES
- **Actualizadas**: $INSTANCES_UPDATED
- **Críticas identificadas**: $CRITICAL_INSTANCES
- **No críticas**: $NON_CRITICAL_INSTANCES
- **Errores**: $ERRORS

## Configuraciones Implementadas

### 🔒 Protección de Terminación
- **Alcance**: Instancias críticas identificadas automáticamente
- **Criterios**: Tipo, nombre, tags, recursos asociados
- **Resultado**: Prevención de terminación accidental/maliciosa
- **Verificación**: Confirmación automática post-configuración

### 🎯 Criterios de Criticidad Aplicados

#### Instancias Consideradas Críticas:
1. **Tipos de producción**: m5, m6, c5, c6, r5, r6 series
2. **Nombres indicativos**: prod, production, critical, database, web, app, server
3. **Tags de ambiente**: Environment=Production
4. **Roles críticos**: database, web, app, api, server
5. **Recursos asociados**: Elastic IP, múltiples volúmenes EBS
6. **Configuración explícita**: Critical=true

#### Instancias No Críticas:
1. **Tipos de desarrollo**: t2.micro, t3.micro, t3a.micro
2. **Ambientes de testing**: dev, test, staging
3. **Instancias temporales**: Sin tags de identificación
4. **Recursos mínimos**: Un solo volumen EBS, sin EIP

## Beneficios Implementados

### 1. Prevención de Pérdidas de Datos
- Protección contra eliminación accidental por usuarios
- Prevención de terminación maliciosa
- Salvaguarda durante operaciones de mantenimiento
- Protección durante automatizaciones defectuosas

### 2. Continuidad del Negocio
- Mantenimiento de servicios críticos disponibles
- Prevención de interrupciones no planificadas
- Protección de sistemas de base de datos
- Conservación de configuraciones complejas

### 3. Cumplimiento y Auditoría
- Trazabilidad de cambios via CloudTrail
- Evidencia de controles preventivos
- Cumplimiento de políticas corporativas
- Documentación para auditorías externas

## Comandos de Verificación

\`\`\`bash
# Verificar protección de instancia específica
aws ec2 describe-instance-attribute --instance-id i-1234567890abcdef0 \\
    --attribute disableApiTermination \\
    --profile $PROFILE --region us-east-1

# Listar todas las instancias y su estado de protección
aws ec2 describe-instances --profile $PROFILE --region us-east-1 \\
    --query 'Reservations[].Instances[].[InstanceId,DisableApiTermination,Tags[?Key==\`Name\`].Value|[0]]' \\
    --output table

# Habilitar protección manualmente
aws ec2 modify-instance-attribute --instance-id INSTANCE_ID \\
    --disable-api-termination --profile $PROFILE --region us-east-1

# Deshabilitar protección (solo cuando sea necesario)
aws ec2 modify-instance-attribute --instance-id INSTANCE_ID \\
    --no-disable-api-termination --profile $PROFILE --region us-east-1
\`\`\`

## Consideraciones Operacionales

### Impacto en Usuarios
- **Usuarios finales**: Sin impacto en operaciones normales
- **Administradores**: Requieren pasos adicionales para terminación
- **Automatización**: Scripts deben incluir deshabilitación previa

### Procedimientos de Emergencia
1. **Terminación de emergencia**: Deshabilitar protección primero
2. **Mantenimiento programado**: Evaluar necesidad de protección temporal
3. **Migración de instancias**: Coordinar deshabilitación/habilitación
4. **Recuperación de desastres**: Incluir estado de protección en runbooks

## Recomendaciones Adicionales

1. **Monitoreo Continuo**: Implementar alertas para cambios de protección
2. **Revisión Periódica**: Evaluar criticidad de instancias mensualmente
3. **Documentación**: Mantener inventario actualizado de instancias críticas
4. **Capacitación**: Entrenar equipos en procedimientos con protección
5. **Automatización**: Incluir protección en plantillas de lanzamiento

### Scripts de Automatización Recomendados

\`\`\`bash
# Script para aplicar protección a nuevas instancias de producción
#!/bin/bash
if [[ "\$ENVIRONMENT" == "production" ]] && [[ "\$INSTANCE_TYPE" =~ ^(m5|c5|r5) ]]; then
    aws ec2 modify-instance-attribute --instance-id \$INSTANCE_ID --disable-api-termination
fi

# Script para verificar protección antes de terminación
#!/bin/bash
PROTECTION_STATUS=\$(aws ec2 describe-instance-attribute --instance-id \$INSTANCE_ID --attribute disableApiTermination --query 'DisableApiTermination.Value' --output text)
if [ "\$PROTECTION_STATUS" == "True" ]; then
    echo "¡Advertencia! Instancia protegida contra terminación"
    read -p "¿Continuar con la terminación? (yes/no): " confirm
    if [ "\$confirm" != "yes" ]; then
        echo "Terminación cancelada"
        exit 1
    fi
    aws ec2 modify-instance-attribute --instance-id \$INSTANCE_ID --no-disable-api-termination
fi
aws ec2 terminate-instances --instance-ids \$INSTANCE_ID
\`\`\`

EOF

echo -e "✅ Documentación generada: ${GREEN}$DOCUMENTATION_FILE${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN CONFIGURACIÓN EC2 TERMINATION PROTECTION ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "🌍 Regiones procesadas: ${GREEN}${#ACTIVE_REGIONS[@]}${NC} (${ACTIVE_REGIONS[*]})"
echo -e "🖥️ Total instancias EC2: ${GREEN}$TOTAL_INSTANCES${NC}"
echo -e "🔒 Instancias protegidas: ${GREEN}$PROTECTED_INSTANCES${NC}"
echo -e "🔧 Instancias actualizadas: ${GREEN}$INSTANCES_UPDATED${NC}"
echo -e "🔴 Instancias críticas: ${GREEN}$CRITICAL_INSTANCES${NC}"
echo -e "🟡 Instancias no críticas: ${GREEN}$NON_CRITICAL_INSTANCES${NC}"

if [ $ERRORS -gt 0 ]; then
    echo -e "⚠️ Errores encontrados: ${YELLOW}$ERRORS${NC}"
fi

# Calcular porcentaje de protección
if [ $TOTAL_INSTANCES -gt 0 ]; then
    PROTECTION_PERCENT=$((PROTECTED_INSTANCES * 100 / TOTAL_INSTANCES))
    echo -e "📈 Cobertura de protección: ${GREEN}$PROTECTION_PERCENT%${NC}"
    
    if [ $CRITICAL_INSTANCES -gt 0 ]; then
        CRITICAL_PROTECTION_PERCENT=$(((PROTECTED_INSTANCES - NON_CRITICAL_INSTANCES) * 100 / CRITICAL_INSTANCES))
        echo -e "🎯 Protección de críticas: ${GREEN}$CRITICAL_PROTECTION_PERCENT%${NC}"
    fi
fi

echo -e "📋 Documentación: ${GREEN}$DOCUMENTATION_FILE${NC}"
echo ""

# Estado final
if [ $TOTAL_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN INSTANCIAS EC2${NC}"
    echo -e "${BLUE}💡 No se requiere configuración de protección${NC}"
elif [ $UNPROTECTED_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE PROTEGIDO${NC}"
    echo -e "${BLUE}💡 Todas las instancias críticas tienen protección${NC}"
elif [ $CRITICAL_INSTANCES -eq 0 ]; then
    echo -e "${YELLOW}⚠️ ESTADO: SIN INSTANCIAS CRÍTICAS DETECTADAS${NC}"
    echo -e "${BLUE}💡 Revisar criterios de criticidad si es necesario${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: PROTECCIÓN PARCIAL${NC}"
    echo -e "${YELLOW}💡 Algunas instancias críticas pueden requerir protección manual${NC}"
fi