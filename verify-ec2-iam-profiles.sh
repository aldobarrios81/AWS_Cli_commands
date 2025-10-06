#!/bin/bash
# verify-ec2-iam-profiles.sh
# Verificar que todas las instancias EC2 tengan perfiles IAM adjuntados
# Validar configuraciones de seguridad para acceso a AWS

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
echo -e "${BLUE}🔍 VERIFICACIÓN IAM INSTANCE PROFILES - EC2${NC}"
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
TOTAL_INSTANCES=0
INSTANCES_WITH_PROFILE=0
INSTANCES_WITHOUT_PROFILE=0
RUNNING_WITHOUT_PROFILE=0
STOPPED_WITHOUT_PROFILE=0

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

echo ""

# Análisis de instancias EC2
echo -e "${PURPLE}=== Análisis de Instancias EC2 ===${NC}"

# Obtener instancias activas (running y stopped)
INSTANCES_DATA=$(aws ec2 describe-instances \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=instance-state-name,Values=running,stopped,stopping,starting" \
    --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,IamInstanceProfile.Arn,Tags[?Key==`Name`].Value|[0],LaunchTime,Platform]' \
    --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener instancias EC2${NC}"
elif [ -z "$INSTANCES_DATA" ] || [ "$INSTANCES_DATA" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron instancias EC2 activas${NC}"
    TOTAL_INSTANCES=0
else
    echo -e "${GREEN}📊 Instancias EC2 encontradas:${NC}"
    
    while IFS=$'\t' read -r instance_id state instance_type iam_profile instance_name launch_time platform; do
        if [ -n "$instance_id" ] && [ "$instance_id" != "None" ]; then
            TOTAL_INSTANCES=$((TOTAL_INSTANCES + 1))
            
            # Limpiar nombres
            if [ -z "$instance_name" ] || [ "$instance_name" == "None" ]; then
                instance_name="Sin nombre"
            fi
            
            if [ -z "$platform" ] || [ "$platform" == "None" ]; then
                platform="Linux"
            fi
            
            echo -e "${CYAN}💻 Instancia: $instance_name${NC}"
            echo -e "   🆔 ID: ${BLUE}$instance_id${NC}"
            echo -e "   ⚡ Estado: ${BLUE}$state${NC}"
            echo -e "   💻 Tipo: ${BLUE}$instance_type${NC}"
            echo -e "   🖥️ OS: ${BLUE}$platform${NC}"
            echo -e "   📅 Lanzada: ${BLUE}$(echo "$launch_time" | cut -d'T' -f1)${NC}"
            
            # Verificar perfil IAM
            if [ -n "$iam_profile" ] && [ "$iam_profile" != "None" ] && [ "$iam_profile" != "null" ]; then
                PROFILE_NAME=$(echo "$iam_profile" | awk -F'/' '{print $NF}')
                echo -e "   ✅ IAM Profile: ${GREEN}$PROFILE_NAME${NC}"
                INSTANCES_WITH_PROFILE=$((INSTANCES_WITH_PROFILE + 1))
                
                # Verificar validez del perfil
                PROFILE_DETAILS=$(aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" --profile "$PROFILE" --query 'InstanceProfile.[InstanceProfileName,Roles[].RoleName]' --output text 2>/dev/null)
                
                if [ $? -eq 0 ] && [ -n "$PROFILE_DETAILS" ]; then
                    ROLE_NAMES=$(echo "$PROFILE_DETAILS" | cut -f2-)
                    if [ -n "$ROLE_NAMES" ] && [ "$ROLE_NAMES" != "None" ]; then
                        ROLE_COUNT=$(echo "$ROLE_NAMES" | wc -w)
                        echo -e "   🎭 Roles asociados: ${GREEN}$ROLE_COUNT${NC}"
                        
                        # Verificar políticas de cada rol
                        for role in $ROLE_NAMES; do
                            echo -e "      👤 Rol: $role"
                            
                            # Verificar políticas managed
                            MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --profile "$PROFILE" --query 'AttachedPolicies[].PolicyName' --output text 2>/dev/null)
                            
                            if [ -n "$MANAGED_POLICIES" ] && [ "$MANAGED_POLICIES" != "None" ]; then
                                POLICY_COUNT=$(echo "$MANAGED_POLICIES" | wc -w)
                                echo -e "         📋 Políticas managed: ${BLUE}$POLICY_COUNT${NC}"
                                
                                # Verificar políticas comunes de seguridad
                                if echo "$MANAGED_POLICIES" | grep -q "CloudWatchAgentServerPolicy"; then
                                    echo -e "         ✅ CloudWatch monitoring"
                                fi
                                if echo "$MANAGED_POLICIES" | grep -q "AmazonSSMManagedInstanceCore"; then
                                    echo -e "         ✅ SSM management"
                                fi
                            fi
                            
                            # Verificar políticas inline
                            INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --profile "$PROFILE" --query 'PolicyNames[]' --output text 2>/dev/null)
                            
                            if [ -n "$INLINE_POLICIES" ] && [ "$INLINE_POLICIES" != "None" ]; then
                                INLINE_COUNT=$(echo "$INLINE_POLICIES" | wc -w)
                                echo -e "         📄 Políticas inline: ${BLUE}$INLINE_COUNT${NC}"
                            fi
                        done
                    else
                        echo -e "   ⚠️ Perfil sin roles: ${YELLOW}Configuración inválida${NC}"
                    fi
                else
                    echo -e "   ❌ Perfil: ${RED}No accesible o eliminado${NC}"
                fi
                
            else
                echo -e "   ❌ IAM Profile: ${RED}NO CONFIGURADO${NC}"
                INSTANCES_WITHOUT_PROFILE=$((INSTANCES_WITHOUT_PROFILE + 1))
                
                if [ "$state" == "running" ]; then
                    echo -e "   🚨 Riesgo: ${RED}Instancia corriendo sin perfil IAM${NC}"
                    RUNNING_WITHOUT_PROFILE=$((RUNNING_WITHOUT_PROFILE + 1))
                elif [ "$state" == "stopped" ]; then
                    echo -e "   🔧 Acción: ${YELLOW}Disponible para configurar${NC}"
                    STOPPED_WITHOUT_PROFILE=$((STOPPED_WITHOUT_PROFILE + 1))
                fi
            fi
            
            # Verificar configuraciones adicionales de seguridad
            echo -e "   🔍 Verificaciones adicionales:"
            
            # Verificar security groups
            SECURITY_GROUPS=$(aws ec2 describe-instances --instance-ids "$instance_id" --profile "$PROFILE" --region "$REGION" --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null)
            
            if [ -n "$SECURITY_GROUPS" ]; then
                SG_COUNT=$(echo "$SECURITY_GROUPS" | wc -w)
                echo -e "      🛡️ Security Groups: ${BLUE}$SG_COUNT configurados${NC}"
                
                # Verificar reglas problemáticas (0.0.0.0/0)
                for sg in $SECURITY_GROUPS; do
                    OPEN_RULES=$(aws ec2 describe-security-groups --group-ids "$sg" --profile "$PROFILE" --region "$REGION" --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]' --output text 2>/dev/null)
                    
                    if [ -n "$OPEN_RULES" ] && [ "$OPEN_RULES" != "None" ]; then
                        echo -e "      ⚠️ SG $sg: ${YELLOW}Reglas abiertas (0.0.0.0/0)${NC}"
                    fi
                done
            fi
            
            # Verificar EBS encryption
            EBS_ENCRYPTED=$(aws ec2 describe-instances --instance-ids "$instance_id" --profile "$PROFILE" --region "$REGION" --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.Encrypted' --output text 2>/dev/null)
            
            if [ "$EBS_ENCRYPTED" == "True" ]; then
                echo -e "      💾 EBS: ${GREEN}Encriptado${NC}"
            elif [ "$EBS_ENCRYPTED" == "False" ]; then
                echo -e "      💾 EBS: ${YELLOW}Sin encriptar${NC}"
            fi
            
            echo ""
        fi
    done <<< "$INSTANCES_DATA"
fi

# Análisis de perfiles IAM disponibles
echo -e "${PURPLE}=== Análisis de Perfiles IAM Disponibles ===${NC}"

# Obtener perfiles de instancia existentes
IAM_PROFILES=$(aws iam list-instance-profiles --profile "$PROFILE" --query 'InstanceProfiles[].[InstanceProfileName,Arn,Roles[].RoleName]' --output text 2>/dev/null)

if [ -z "$IAM_PROFILES" ] || [ "$IAM_PROFILES" == "None" ]; then
    echo -e "${YELLOW}⚠️ No se encontraron perfiles de instancia IAM${NC}"
    echo -e "${BLUE}💡 Recomendación: Crear perfiles IAM para las instancias${NC}"
else
    PROFILE_COUNT=0
    echo -e "${GREEN}📊 Perfiles IAM disponibles:${NC}"
    
    while IFS=$'\t' read -r profile_name profile_arn role_names; do
        if [ -n "$profile_name" ]; then
            PROFILE_COUNT=$((PROFILE_COUNT + 1))
            echo -e "   👤 $profile_name"
            
            if [ -n "$role_names" ] && [ "$role_names" != "None" ]; then
                ROLE_COUNT=$(echo "$role_names" | wc -w)
                echo -e "      🎭 Roles: ${GREEN}$ROLE_COUNT asociados${NC}"
                
                # Mostrar uso del perfil
                USAGE_COUNT=$(aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" --filters "Name=iam-instance-profile.arn,Values=$profile_arn" --query 'Reservations[].Instances[]' --output text 2>/dev/null | wc -l)
                echo -e "      🔗 Usado por: ${BLUE}$USAGE_COUNT instancias${NC}"
            else
                echo -e "      ⚠️ ${YELLOW}Sin roles asociados${NC}"
            fi
        fi
    done <<< "$IAM_PROFILES"
    
    echo -e "📈 Total perfiles: ${GREEN}$PROFILE_COUNT${NC}"
fi

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="ec2-iam-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "total_instances": $TOTAL_INSTANCES,
    "instances_with_profile": $INSTANCES_WITH_PROFILE,
    "instances_without_profile": $INSTANCES_WITHOUT_PROFILE,
    "running_without_profile": $RUNNING_WITHOUT_PROFILE,
    "stopped_without_profile": $STOPPED_WITHOUT_PROFILE,
    "compliance": "$(if [ $TOTAL_INSTANCES -eq 0 ]; then echo "NO_INSTANCES"; elif [ $INSTANCES_WITHOUT_PROFILE -eq 0 ]; then echo "FULLY_COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "recommendations": [
    "Adjuntar perfiles IAM a todas las instancias EC2",
    "Crear perfiles específicos por función (web, db, worker)",
    "Implementar principio de menor privilegio",
    "Usar políticas AWS managed cuando sea posible",
    "Configurar CloudWatch y SSM para monitoreo",
    "Auditar permisos regularmente"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ $INSTANCES_WITHOUT_PROFILE -gt 0 ]; then
    echo -e "${PURPLE}=== Comandos de Remediación ===${NC}"
    
    if [ $STOPPED_WITHOUT_PROFILE -gt 0 ]; then
        echo -e "${CYAN}🔧 Para instancias detenidas:${NC}"
        echo -e "${BLUE}./attach-iam-instance-profiles.sh $PROFILE${NC}"
    fi
    
    if [ $RUNNING_WITHOUT_PROFILE -gt 0 ]; then
        echo -e "${YELLOW}⚠️ Para instancias corriendo:${NC}"
        echo -e "${BLUE}1. Detener instancia manualmente${NC}"
        echo -e "${BLUE}2. Ejecutar script de adjunción${NC}"
        echo -e "${BLUE}3. Reiniciar instancia${NC}"
    fi
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN IAM PROFILES ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "💻 Total instancias: ${GREEN}$TOTAL_INSTANCES${NC}"

if [ $TOTAL_INSTANCES -gt 0 ]; then
    echo -e "✅ Con perfil IAM: ${GREEN}$INSTANCES_WITH_PROFILE${NC}"
    echo -e "❌ Sin perfil IAM: ${RED}$INSTANCES_WITHOUT_PROFILE${NC}"
    
    if [ $INSTANCES_WITHOUT_PROFILE -gt 0 ]; then
        echo -e "🏃 Corriendo sin perfil: ${RED}$RUNNING_WITHOUT_PROFILE${NC}"
        echo -e "🛑 Detenidas sin perfil: ${YELLOW}$STOPPED_WITHOUT_PROFILE${NC}"
    fi
    
    # Calcular porcentaje de cumplimiento
    if [ $TOTAL_INSTANCES -gt 0 ]; then
        COMPLIANCE_PERCENT=$((INSTANCES_WITH_PROFILE * 100 / TOTAL_INSTANCES))
        echo -e "📈 Cumplimiento: ${GREEN}$COMPLIANCE_PERCENT%${NC}"
    fi
fi

echo ""

# Estado final
if [ $TOTAL_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN INSTANCIAS EC2${NC}"
    echo -e "${BLUE}💡 No hay instancias para verificar${NC}"
elif [ $INSTANCES_WITHOUT_PROFILE -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE CUMPLIENTE${NC}"
    echo -e "${BLUE}💡 Todas las instancias tienen perfiles IAM${NC}"
elif [ $RUNNING_WITHOUT_PROFILE -eq 0 ]; then
    echo -e "${YELLOW}⚠️ ESTADO: REMEDIACIÓN DISPONIBLE${NC}"
    echo -e "${BLUE}💡 Ejecutar: ./attach-iam-instance-profiles.sh $PROFILE${NC}"
else
    echo -e "${RED}❌ ESTADO: RIESGO DE SEGURIDAD${NC}"
    echo -e "${YELLOW}💡 Instancias corriendo sin perfiles IAM requieren atención inmediata${NC}"
fi

echo -e "📋 Reporte: ${GREEN}$VERIFICATION_REPORT${NC}"