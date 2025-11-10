#!/bin/bash
# attach-iam-instance-profiles.sh
# Adjuntar perfiles de instancia IAM a instancias EC2
# Regla de seguridad: Attach IAM instance profile to EC2 instances
# Uso: ./attach-iam-instance-profiles.sh [perfil]

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
echo -e "${BLUE}🔐 ADJUNTANDO IAM INSTANCE PROFILES A EC2${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando perfiles de instancia para acceso seguro a AWS"
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

# Verificar disponibilidad de EC2
echo -e "${PURPLE}🔍 Verificando disponibilidad de EC2...${NC}"
EC2_TEST=$(aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" --max-items 1 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ EC2 no disponible en región $REGION${NC}"
    
    # Verificar otras regiones principales
    MAIN_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")
    for region in "${MAIN_REGIONS[@]}"; do
        echo -e "   🔍 Verificando región: ${BLUE}$region${NC}"
        TEST_RESULT=$(aws ec2 describe-instances --profile "$PROFILE" --region "$region" --max-items 1 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ EC2 disponible en: ${GREEN}$region${NC}"
            REGION="$region"
            break
        else
            echo -e "   ❌ No disponible en: $region"
        fi
    done
fi

echo -e "✅ EC2 disponible en región: ${GREEN}$REGION${NC}"
echo ""

# Variables de conteo
TOTAL_INSTANCES=0
INSTANCES_WITH_PROFILE=0
INSTANCES_WITHOUT_PROFILE=0
PROFILES_ATTACHED=0
INSTANCES_STOPPED=0

# Paso 1: Inventario de instancias EC2
echo -e "${PURPLE}=== Paso 1: Inventario de instancias EC2 ===${NC}"

# Obtener lista de instancias EC2
INSTANCES_DATA=$(aws ec2 describe-instances \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,IamInstanceProfile.Arn,Tags[?Key==`Name`].Value|[0],LaunchTime]' \
    --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener lista de instancias EC2${NC}"
    TOTAL_INSTANCES=0
elif [ -z "$INSTANCES_DATA" ] || [ "$INSTANCES_DATA" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron instancias EC2${NC}"
    TOTAL_INSTANCES=0
else
    echo -e "${GREEN}✅ Instancias EC2 encontradas${NC}"
    
    # Procesar cada instancia
    while IFS=$'\t' read -r instance_id state instance_type iam_profile instance_name launch_time; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            TOTAL_INSTANCES=$((TOTAL_INSTANCES + 1))
            
            # Limpiar nombres
            if [ -z "$instance_name" ] || [ "$instance_name" == "None" ]; then
                instance_name="Sin nombre"
            fi
            
            echo -e "${CYAN}💻 Instancia: $instance_name${NC}"
            echo -e "   🆔 Instance ID: ${BLUE}$instance_id${NC}"
            echo -e "   ⚡ Estado: ${BLUE}$state${NC}"
            echo -e "   💻 Tipo: ${BLUE}$instance_type${NC}"
            echo -e "   📅 Lanzada: ${BLUE}$(echo "$launch_time" | cut -d'T' -f1)${NC}"
            
            # Verificar perfil IAM
            if [ -n "$iam_profile" ] && [ "$iam_profile" != "None" ] && [ "$iam_profile" != "null" ]; then
                PROFILE_NAME=$(echo "$iam_profile" | awk -F'/' '{print $NF}')
                echo -e "   ✅ IAM Profile: ${GREEN}$PROFILE_NAME${NC}"
                INSTANCES_WITH_PROFILE=$((INSTANCES_WITH_PROFILE + 1))
                
                # Verificar si el perfil existe y está accesible
                PROFILE_EXISTS=$(aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" --profile "$PROFILE" --query 'InstanceProfile.InstanceProfileName' --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$PROFILE_EXISTS" ]; then
                    echo -e "   ✅ Perfil verificado: ${GREEN}Válido${NC}"
                else
                    echo -e "   ⚠️ Perfil: ${YELLOW}No accesible o eliminado${NC}"
                fi
            else
                echo -e "   ❌ IAM Profile: ${RED}NO CONFIGURADO${NC}"
                INSTANCES_WITHOUT_PROFILE=$((INSTANCES_WITHOUT_PROFILE + 1))
                
                # Marcar para adjuntar perfil si está corriendo
                if [ "$state" == "running" ]; then
                    echo -e "   🎯 Acción: ${YELLOW}Requiere perfil IAM${NC}"
                elif [ "$state" == "stopped" ]; then
                    echo -e "   🎯 Acción: ${BLUE}Disponible para configurar${NC}"
                    INSTANCES_STOPPED=$((INSTANCES_STOPPED + 1))
                else
                    echo -e "   🎯 Estado: ${YELLOW}$state - No disponible${NC}"
                fi
            fi
            echo ""
        fi
    done <<< "$INSTANCES_DATA"
fi

# Paso 2: Verificar perfiles IAM disponibles
echo -e "${PURPLE}=== Paso 2: Perfiles IAM Disponibles ===${NC}"

# Obtener lista de perfiles de instancia IAM
IAM_PROFILES=$(aws iam list-instance-profiles --profile "$PROFILE" --query 'InstanceProfiles[].[InstanceProfileName,Arn,CreateDate]' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener perfiles IAM${NC}"
elif [ -z "$IAM_PROFILES" ] || [ "$IAM_PROFILES" == "None" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron perfiles de instancia IAM${NC}"
    
    # Crear un perfil básico por defecto
    echo -e "${CYAN}🔧 Creando perfil de instancia IAM por defecto...${NC}"
    
    DEFAULT_PROFILE_NAME="EC2-BasicInstanceProfile-$PROFILE"
    DEFAULT_ROLE_NAME="EC2-BasicRole-$PROFILE"
    
    # Crear rol IAM básico
    TRUST_POLICY='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Principal": {
                    "Service": "ec2.amazonaws.com"
                },
                "Action": "sts:AssumeRole"
            }
        ]
    }'
    
    echo -e "   🔧 Creando rol IAM: $DEFAULT_ROLE_NAME"
    aws iam create-role \
        --role-name "$DEFAULT_ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Basic role for EC2 instances" \
        --profile "$PROFILE" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "   ✅ Rol IAM creado: ${GREEN}$DEFAULT_ROLE_NAME${NC}"
        
        # Adjuntar políticas básicas
        aws iam attach-role-policy \
            --role-name "$DEFAULT_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" \
            --profile "$PROFILE" >/dev/null 2>&1
        
        aws iam attach-role-policy \
            --role-name "$DEFAULT_ROLE_NAME" \
            --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" \
            --profile "$PROFILE" >/dev/null 2>&1
        
        echo -e "   ✅ Políticas básicas adjuntadas"
        
        # Crear perfil de instancia
        echo -e "   🔧 Creando perfil de instancia: $DEFAULT_PROFILE_NAME"
        aws iam create-instance-profile \
            --instance-profile-name "$DEFAULT_PROFILE_NAME" \
            --profile "$PROFILE" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            # Agregar rol al perfil
            aws iam add-role-to-instance-profile \
                --instance-profile-name "$DEFAULT_PROFILE_NAME" \
                --role-name "$DEFAULT_ROLE_NAME" \
                --profile "$PROFILE" >/dev/null 2>&1
            
            echo -e "   ✅ Perfil de instancia creado: ${GREEN}$DEFAULT_PROFILE_NAME${NC}"
            
            # Actualizar lista de perfiles
            sleep 2
            IAM_PROFILES=$(aws iam list-instance-profiles --profile "$PROFILE" --query 'InstanceProfiles[].[InstanceProfileName,Arn,CreateDate]' --output text 2>/dev/null)
        else
            echo -e "   ${RED}❌ Error creando perfil de instancia${NC}"
        fi
    else
        echo -e "   ${RED}❌ Error creando rol IAM${NC}"
    fi
else
    echo -e "${GREEN}✅ Perfiles de instancia IAM encontrados${NC}"
fi

# Mostrar perfiles disponibles
if [ -n "$IAM_PROFILES" ] && [ "$IAM_PROFILES" != "None" ]; then
    echo -e "${BLUE}📋 Perfiles IAM disponibles:${NC}"
    
    PROFILE_COUNT=0
    DEFAULT_INSTANCE_PROFILE=""
    
    while IFS=$'\t' read -r profile_name profile_arn create_date; do
        if [ -n "$profile_name" ]; then
            PROFILE_COUNT=$((PROFILE_COUNT + 1))
            echo -e "   👤 $profile_name"
            echo -e "      🏷️ ARN: ${BLUE}$profile_arn${NC}"
            echo -e "      📅 Creado: ${BLUE}$(echo "$create_date" | cut -d'T' -f1)${NC}"
            
            # Verificar roles asociados
            ASSOCIATED_ROLES=$(aws iam get-instance-profile --instance-profile-name "$profile_name" --profile "$PROFILE" --query 'InstanceProfile.Roles[].RoleName' --output text 2>/dev/null)
            
            if [ -n "$ASSOCIATED_ROLES" ] && [ "$ASSOCIATED_ROLES" != "None" ]; then
                ROLE_COUNT=$(echo "$ASSOCIATED_ROLES" | wc -w)
                echo -e "      🎭 Roles: ${GREEN}$ROLE_COUNT asociados${NC}"
                
                # Usar como perfil por defecto si no tenemos uno
                if [ -z "$DEFAULT_INSTANCE_PROFILE" ]; then
                    DEFAULT_INSTANCE_PROFILE="$profile_name"
                fi
            else
                echo -e "      🎭 Roles: ${YELLOW}Sin roles asociados${NC}"
            fi
            echo ""
        fi
    done <<< "$IAM_PROFILES"
    
    echo -e "📊 Total perfiles disponibles: ${GREEN}$PROFILE_COUNT${NC}"
fi

# Paso 3: Adjuntar perfiles a instancias sin perfil
if [ $INSTANCES_WITHOUT_PROFILE -gt 0 ] && [ -n "$DEFAULT_INSTANCE_PROFILE" ]; then
    echo -e "${PURPLE}=== Paso 3: Adjuntando perfiles IAM ===${NC}"
    
    echo -e "${CYAN}🔧 Usando perfil por defecto: ${GREEN}$DEFAULT_INSTANCE_PROFILE${NC}"
    
    # Procesar instancias sin perfil
    while IFS=$'\t' read -r instance_id state instance_type iam_profile instance_name launch_time; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            # Solo procesar instancias sin perfil IAM
            if [ -z "$iam_profile" ] || [ "$iam_profile" == "None" ] || [ "$iam_profile" == "null" ]; then
                
                if [ -z "$instance_name" ] || [ "$instance_name" == "None" ]; then
                    instance_name="Sin nombre"
                fi
                
                echo -e "${CYAN}🔧 Procesando: $instance_name ($instance_id)${NC}"
                echo -e "   Estado: ${BLUE}$state${NC}"
                
                if [ "$state" == "stopped" ]; then
                    echo -e "   🎯 Adjuntando perfil IAM..."
                    
                    # Adjuntar perfil de instancia
                    ATTACH_RESULT=$(aws ec2 associate-iam-instance-profile \
                        --instance-id "$instance_id" \
                        --iam-instance-profile Name="$DEFAULT_INSTANCE_PROFILE" \
                        --profile "$PROFILE" \
                        --region "$REGION" 2>&1)
                    
                    if [ $? -eq 0 ]; then
                        echo -e "   ✅ Perfil IAM adjuntado exitosamente"
                        PROFILES_ATTACHED=$((PROFILES_ATTACHED + 1))
                    else
                        echo -e "   ${RED}❌ Error adjuntando perfil IAM${NC}"
                        
                        # Analizar error específico
                        if echo "$ATTACH_RESULT" | grep -q "InvalidState"; then
                            echo -e "   ${YELLOW}💡 Estado de instancia no permite modificación${NC}"
                        elif echo "$ATTACH_RESULT" | grep -q "UnauthorizedOperation"; then
                            echo -e "   ${YELLOW}💡 Permisos insuficientes para adjuntar perfil${NC}"
                        else
                            echo -e "   ${YELLOW}💡 $(echo "$ATTACH_RESULT" | head -1)${NC}"
                        fi
                    fi
                    
                elif [ "$state" == "running" ]; then
                    echo -e "   ⚠️ Instancia corriendo: ${YELLOW}Requiere detención${NC}"
                    echo -e "   💡 Manual: Detener instancia, adjuntar perfil, reiniciar"
                    
                else
                    echo -e "   ⚠️ Estado '$state': ${YELLOW}No disponible para modificar${NC}"
                fi
                
                echo ""
            fi
        fi
    done <<< "$INSTANCES_DATA"
    
elif [ $INSTANCES_WITHOUT_PROFILE -gt 0 ]; then
    echo -e "${PURPLE}=== Paso 3: Sin perfiles IAM disponibles ===${NC}"
    echo -e "${YELLOW}⚠️ Se encontraron instancias sin perfil pero no hay perfiles IAM para adjuntar${NC}"
    echo -e "${BLUE}💡 Crear perfiles de instancia IAM antes de ejecutar este script${NC}"
fi

# Paso 4: Generar documentación y comandos
echo -e "${PURPLE}=== Paso 4: Generando documentación ===${NC}"

IAM_PROFILE_REPORT="ec2-iam-profiles-$PROFILE-$(date +%Y%m%d).md"

cat > "$IAM_PROFILE_REPORT" << EOF
# Reporte IAM Instance Profiles - EC2 - $PROFILE

**Fecha**: $(date)
**Región**: $REGION
**Account ID**: $ACCOUNT_ID

## Resumen Ejecutivo

### Instancias EC2 Procesadas
- **Total instancias**: $TOTAL_INSTANCES
- **Con perfil IAM**: $INSTANCES_WITH_PROFILE
- **Sin perfil IAM**: $INSTANCES_WITHOUT_PROFILE
- **Perfiles adjuntados**: $PROFILES_ATTACHED
- **Instancias detenidas disponibles**: $INSTANCES_STOPPED

## Configuraciones Implementadas

### ✅ Perfiles IAM Adjuntados
- Perfil por defecto usado: $DEFAULT_INSTANCE_PROFILE
- Instancias configuradas: $PROFILES_ATTACHED
- Acceso seguro a servicios AWS sin credenciales hardcoded

### 🔍 Políticas Recomendadas por Perfil
\`\`\`json
{
  "CloudWatch": "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  "SSM": "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  "S3ReadOnly": "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
\`\`\`

## Comandos de Verificación

### Verificar perfiles de instancia
\`\`\`bash
# Listar instancias con sus perfiles IAM
aws ec2 describe-instances --profile $PROFILE --region $REGION \\
    --query 'Reservations[].Instances[].[InstanceId,IamInstanceProfile.Arn,Tags[?Key==\`Name\`].Value|[0]]' \\
    --output table

# Verificar perfil específico
aws iam get-instance-profile --instance-profile-name PROFILE_NAME --profile $PROFILE

# Ver roles asociados a perfil
aws iam get-instance-profile --instance-profile-name PROFILE_NAME --profile $PROFILE \\
    --query 'InstanceProfile.Roles[].RoleName' --output text
\`\`\`

### Adjuntar perfil a instancia manualmente
\`\`\`bash
# Para instancia detenida
aws ec2 associate-iam-instance-profile \\
    --instance-id i-xxxxxxxxx \\
    --iam-instance-profile Name=PROFILE_NAME \\
    --profile $PROFILE --region $REGION

# Para instancia corriendo (requiere reinicio)
aws ec2 stop-instances --instance-ids i-xxxxxxxxx --profile $PROFILE --region $REGION
# Esperar que se detenga
aws ec2 associate-iam-instance-profile \\
    --instance-id i-xxxxxxxxx \\
    --iam-instance-profile Name=PROFILE_NAME \\
    --profile $PROFILE --region $REGION
aws ec2 start-instances --instance-ids i-xxxxxxxxx --profile $PROFILE --region $REGION
\`\`\`

## Mejores Prácticas

### 1. Principio de Menor Privilegio
- Crear perfiles específicos por función (web, db, monitoring)
- Adjuntar solo políticas necesarias
- Revisar permisos regularmente

### 2. Perfiles Comunes Recomendados
\`\`\`bash
# Servidor web básico
- CloudWatchAgentServerPolicy
- AmazonS3ReadOnlyAccess (para assets)

# Servidor de base de datos
- CloudWatchAgentServerPolicy
- AmazonSSMManagedInstanceCore

# Servidor de procesamiento
- CloudWatchAgentServerPolicy
- AmazonS3FullAccess (bucket específico)
- AmazonSQSFullAccess (queue específica)
\`\`\`

### 3. Monitoreo y Auditoria
- CloudTrail para auditar cambios de perfiles
- Config Rules para verificar cumplimiento
- Alarmas para instancias sin perfil

### 4. Automatización
- Launch Templates con perfiles preconfigurados
- Auto Scaling Groups con perfiles por defecto
- Terraform/CloudFormation para IaC

## Scripts de Creación de Perfiles Personalizados

### Perfil para Servidor Web
\`\`\`bash
# Crear rol
aws iam create-role --role-name WebServerRole \\
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Service": "ec2.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }]
    }'

# Adjuntar políticas
aws iam attach-role-policy --role-name WebServerRole \\
    --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Crear perfil de instancia
aws iam create-instance-profile --instance-profile-name WebServerProfile

# Asociar rol con perfil
aws iam add-role-to-instance-profile \\
    --instance-profile-name WebServerProfile \\
    --role-name WebServerRole
\`\`\`

EOF

echo -e "✅ Documentación generada: ${GREEN}$IAM_PROFILE_REPORT${NC}"

# Crear script de verificación rápida
VERIFY_SCRIPT="verify-ec2-iam-profiles-$PROFILE.sh"

cat > "$VERIFY_SCRIPT" << 'EOF'
#!/bin/bash
# Script de verificación rápida para perfiles IAM en EC2

PROFILE="$1"
REGION="us-east-1"

if [ -z "$PROFILE" ]; then
    echo "Uso: $0 [perfil]"
    exit 1
fi

echo "=== Verificación IAM Instance Profiles - $PROFILE ==="

# Instancias sin perfil
echo "Instancias SIN perfil IAM:"
aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[?!IamInstanceProfile].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
    --output table

echo ""

# Instancias con perfil
echo "Instancias CON perfil IAM:"
aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[?IamInstanceProfile].[InstanceId,State.Name,IamInstanceProfile.Arn,Tags[?Key==`Name`].Value|[0]]' \
    --output table
EOF

chmod +x "$VERIFY_SCRIPT"
echo -e "✅ Script de verificación: ${GREEN}$VERIFY_SCRIPT${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN IAM INSTANCE PROFILES ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📍 Región: ${GREEN}$REGION${NC}"
echo -e "💻 Total instancias: ${GREEN}$TOTAL_INSTANCES${NC}"

if [ $TOTAL_INSTANCES -gt 0 ]; then
    echo -e "✅ Con perfil IAM: ${GREEN}$INSTANCES_WITH_PROFILE${NC}"
    echo -e "❌ Sin perfil IAM: ${RED}$INSTANCES_WITHOUT_PROFILE${NC}"
    echo -e "🔧 Perfiles adjuntados: ${GREEN}$PROFILES_ATTACHED${NC}"
    
    # Calcular porcentaje de cumplimiento
    if [ $TOTAL_INSTANCES -gt 0 ]; then
        TOTAL_WITH_PROFILES=$((INSTANCES_WITH_PROFILE + PROFILES_ATTACHED))
        COMPLIANCE_PERCENT=$((TOTAL_WITH_PROFILES * 100 / TOTAL_INSTANCES))
        echo -e "📈 Cumplimiento: ${GREEN}$COMPLIANCE_PERCENT%${NC}"
    fi
fi

echo -e "📋 Documentación: ${GREEN}$IAM_PROFILE_REPORT${NC}"
echo -e "🔍 Verificación: ${GREEN}$VERIFY_SCRIPT${NC}"

echo ""
if [ $TOTAL_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}✅ NO HAY INSTANCIAS EC2 PARA CONFIGURAR${NC}"
    echo -e "${BLUE}💡 Configuraciones listas para futuras instancias${NC}"
elif [ $INSTANCES_WITHOUT_PROFILE -eq 0 ]; then
    echo -e "${GREEN}🎉 TODAS LAS INSTANCIAS TIENEN PERFILES IAM${NC}"
    echo -e "${BLUE}💡 Configuración de seguridad completada${NC}"
elif [ $PROFILES_ATTACHED -gt 0 ]; then
    echo -e "${GREEN}✅ PERFILES IAM ADJUNTADOS EXITOSAMENTE${NC}"
    echo -e "${BLUE}💡 Revisar instancias corriendo que requieren reinicio${NC}"
else
    echo -e "${YELLOW}⚠️ ALGUNAS INSTANCIAS REQUIEREN PERFILES IAM${NC}"
    echo -e "${BLUE}💡 Ejecutar script de verificación para detalles${NC}"
fi