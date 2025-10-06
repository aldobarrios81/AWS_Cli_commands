#!/bin/bash
# verify-sagemaker-security.sh
# Verificar configuraciones de seguridad para SageMaker
# Validar que todas las instancias tengan acceso público deshabilitado

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
echo -e "${BLUE}🔍 VERIFICACIÓN SEGURIDAD SAGEMAKER${NC}"
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
SECURE_INSTANCES=0
VULNERABLE_INSTANCES=0
ERROR_INSTANCES=0

# Verificar disponibilidad de SageMaker
echo -e "${PURPLE}🔍 Verificando disponibilidad de SageMaker...${NC}"
SAGEMAKER_TEST=$(aws sagemaker list-notebook-instances --profile "$PROFILE" --region "$REGION" --max-items 1 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ SageMaker no disponible en región $REGION${NC}"
    
    # Verificar otras regiones
    MAIN_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")
    for region in "${MAIN_REGIONS[@]}"; do
        echo -e "   🔍 Verificando región: ${BLUE}$region${NC}"
        TEST_RESULT=$(aws sagemaker list-notebook-instances --profile "$PROFILE" --region "$region" --max-items 1 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo -e "   ✅ SageMaker disponible en: ${GREEN}$region${NC}"
            REGION="$region"
            break
        else
            echo -e "   ❌ No disponible en: $region"
        fi
    done
fi

echo ""

# Obtener lista de instancias de notebook
echo -e "${PURPLE}=== Análisis de Instancias SageMaker ===${NC}"

NOTEBOOK_INSTANCES=$(aws sagemaker list-notebook-instances --profile "$PROFILE" --region "$REGION" --query 'NotebookInstances[].NotebookInstanceName' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener lista de instancias${NC}"
    exit 1
elif [ -z "$NOTEBOOK_INSTANCES" ] || [ "$NOTEBOOK_INSTANCES" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron instancias de notebook SageMaker${NC}"
    TOTAL_INSTANCES=0
else
    TOTAL_INSTANCES=$(echo "$NOTEBOOK_INSTANCES" | wc -w)
    echo -e "${GREEN}📊 Total instancias encontradas: $TOTAL_INSTANCES${NC}"
    echo ""
    
    # Analizar cada instancia
    for instance in $NOTEBOOK_INSTANCES; do
        echo -e "${CYAN}🔍 Analizando: $instance${NC}"
        
        # Obtener detalles de configuración de seguridad
        INSTANCE_DETAILS=$(aws sagemaker describe-notebook-instance --notebook-instance-name "$instance" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
        
        if [ $? -eq 0 ] && [ "$INSTANCE_DETAILS" != "null" ]; then
            # Extraer información de seguridad
            DIRECT_INTERNET=$(echo "$INSTANCE_DETAILS" | jq -r '.DirectInternetAccess // "Enabled"' 2>/dev/null)
            INSTANCE_STATUS=$(echo "$INSTANCE_DETAILS" | jq -r '.NotebookInstanceStatus' 2>/dev/null)
            INSTANCE_TYPE=$(echo "$INSTANCE_DETAILS" | jq -r '.InstanceType' 2>/dev/null)
            SUBNET_ID=$(echo "$INSTANCE_DETAILS" | jq -r '.SubnetId // "default"' 2>/dev/null)
            SECURITY_GROUPS=$(echo "$INSTANCE_DETAILS" | jq -r '.SecurityGroups[]? // empty' 2>/dev/null)
            CREATION_TIME=$(echo "$INSTANCE_DETAILS" | jq -r '.CreationTime' 2>/dev/null | cut -d'T' -f1)
            
            echo -e "   📊 Estado: ${BLUE}$INSTANCE_STATUS${NC}"
            echo -e "   💻 Tipo: ${BLUE}$INSTANCE_TYPE${NC}"
            echo -e "   📅 Creado: ${BLUE}$CREATION_TIME${NC}"
            
            # Verificar acceso directo a Internet
            if [ "$DIRECT_INTERNET" == "Disabled" ]; then
                echo -e "   ✅ Acceso directo: ${GREEN}DESHABILITADO${NC}"
                SECURE_INSTANCES=$((SECURE_INSTANCES + 1))
                SECURITY_STATUS="SEGURO"
            else
                echo -e "   ❌ Acceso directo: ${RED}HABILITADO${NC}"
                VULNERABLE_INSTANCES=$((VULNERABLE_INSTANCES + 1))
                SECURITY_STATUS="VULNERABLE"
            fi
            
            # Verificar configuración de red
            if [ "$SUBNET_ID" != "default" ] && [ "$SUBNET_ID" != "null" ]; then
                echo -e "   🔗 Subnet: ${BLUE}$SUBNET_ID${NC}"
                
                # Verificar si es subnet pública o privada
                ROUTE_TABLE=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --filters "Name=association.subnet-id,Values=$SUBNET_ID" --query 'RouteTables[0].Routes[?GatewayId!=null && starts_with(GatewayId, `igw-`)].GatewayId' --output text 2>/dev/null)
                
                if [ -n "$ROUTE_TABLE" ] && [ "$ROUTE_TABLE" != "None" ]; then
                    echo -e "   ⚠️ Tipo subnet: ${YELLOW}PÚBLICA${NC}"
                    if [ "$SECURITY_STATUS" == "SEGURO" ]; then
                        echo -e "   💡 Recomendación: Usar subnet privada"
                    fi
                else
                    echo -e "   ✅ Tipo subnet: ${GREEN}PRIVADA${NC}"
                fi
            else
                echo -e "   🔗 Red: ${YELLOW}VPC por defecto${NC}"
            fi
            
            # Verificar security groups si existen
            if [ -n "$SECURITY_GROUPS" ]; then
                SG_COUNT=$(echo "$SECURITY_GROUPS" | wc -l)
                echo -e "   🛡️ Security Groups: ${BLUE}$SG_COUNT configurados${NC}"
                
                # Verificar reglas de security groups
                for sg in $SECURITY_GROUPS; do
                    OPEN_RULES=$(aws ec2 describe-security-groups --profile "$PROFILE" --region "$REGION" --group-ids "$sg" --query 'SecurityGroups[0].IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]' --output text 2>/dev/null)
                    
                    if [ -n "$OPEN_RULES" ] && [ "$OPEN_RULES" != "None" ]; then
                        echo -e "   ⚠️ SG $sg: ${YELLOW}Reglas abiertas (0.0.0.0/0)${NC}"
                    fi
                done
            else
                echo -e "   🛡️ Security Groups: ${BLUE}Por defecto${NC}"
            fi
            
            # Estado general de seguridad
            if [ "$SECURITY_STATUS" == "SEGURO" ]; then
                echo -e "   🔐 Estado general: ${GREEN}SEGURO${NC}"
            else
                echo -e "   🚨 Estado general: ${RED}REQUIERE ACCIÓN${NC}"
            fi
            
        else
            echo -e "   ${RED}❌ Error obteniendo detalles${NC}"
            ERROR_INSTANCES=$((ERROR_INSTANCES + 1))
        fi
        
        echo ""
    done
fi

# Verificar configuraciones adicionales de SageMaker
echo -e "${PURPLE}=== Configuraciones Adicionales SageMaker ===${NC}"

# Verificar VPC Endpoints
echo -e "${CYAN}🔍 Verificando VPC Endpoints SageMaker...${NC}"
VPC_ENDPOINTS=$(aws ec2 describe-vpc-endpoints --profile "$PROFILE" --region "$REGION" --filters "Name=service-name,Values=*sagemaker*" --query 'VpcEndpoints[].ServiceName' --output text 2>/dev/null)

if [ -n "$VPC_ENDPOINTS" ] && [ "$VPC_ENDPOINTS" != "None" ]; then
    VPC_ENDPOINT_COUNT=$(echo "$VPC_ENDPOINTS" | wc -w)
    echo -e "✅ VPC Endpoints SageMaker: ${GREEN}$VPC_ENDPOINT_COUNT configurados${NC}"
    for endpoint in $VPC_ENDPOINTS; do
        echo -e "   📍 $endpoint"
    done
else
    echo -e "⚠️ VPC Endpoints SageMaker: ${YELLOW}No configurados${NC}"
    echo -e "💡 Recomendación: Configurar VPC Endpoints para tráfico privado"
fi

echo ""

# Verificar políticas IAM relacionadas con SageMaker
echo -e "${CYAN}🔍 Verificando roles IAM SageMaker...${NC}"
SAGEMAKER_ROLES=$(aws iam list-roles --profile "$PROFILE" --query 'Roles[?contains(RoleName, `SageMaker`) || contains(AssumeRolePolicyDocument, `sagemaker`)].RoleName' --output text 2>/dev/null)

if [ -n "$SAGEMAKER_ROLES" ] && [ "$SAGEMAKER_ROLES" != "None" ]; then
    ROLE_COUNT=$(echo "$SAGEMAKER_ROLES" | wc -w)
    echo -e "✅ Roles SageMaker encontrados: ${GREEN}$ROLE_COUNT${NC}"
    
    for role in $SAGEMAKER_ROLES; do
        echo -e "   👤 $role"
        
        # Verificar políticas attached
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --profile "$PROFILE" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null)
        
        if [ -n "$ATTACHED_POLICIES" ]; then
            POLICY_COUNT=$(echo "$ATTACHED_POLICIES" | wc -w)
            echo -e "      📋 Políticas: $POLICY_COUNT"
            
            # Verificar si tiene políticas muy permisivas
            if echo "$ATTACHED_POLICIES" | grep -q "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"; then
                echo -e "      ⚠️ ${YELLOW}Política muy permisiva: AmazonSageMakerFullAccess${NC}"
            fi
        fi
    done
else
    echo -e "⚠️ Roles SageMaker: ${YELLOW}No encontrados específicos${NC}"
fi

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="sagemaker-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "region": "$REGION",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "total_instances": $TOTAL_INSTANCES,
    "secure_instances": $SECURE_INSTANCES,
    "vulnerable_instances": $VULNERABLE_INSTANCES,
    "error_instances": $ERROR_INSTANCES,
    "security_compliance": "$(if [ $VULNERABLE_INSTANCES -eq 0 ] && [ $TOTAL_INSTANCES -gt 0 ]; then echo "COMPLIANT"; elif [ $TOTAL_INSTANCES -eq 0 ]; then echo "NO_INSTANCES"; else echo "NON_COMPLIANT"; fi)"
  },
  "recommendations": [
    "Deshabilitar acceso directo a Internet en todas las instancias",
    "Usar subnets privadas para instancias SageMaker",
    "Configurar VPC Endpoints para SageMaker API",
    "Revisar permisos IAM y usar principio de menor privilegio",
    "Implementar monitoreo continuo de configuraciones SageMaker"
  ]
}
EOF

echo -e "📊 Reporte de verificación generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN SAGEMAKER ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "📊 Total instancias: ${GREEN}$TOTAL_INSTANCES${NC}"

if [ $TOTAL_INSTANCES -gt 0 ]; then
    echo -e "✅ Instancias seguras: ${GREEN}$SECURE_INSTANCES${NC}"
    if [ $VULNERABLE_INSTANCES -gt 0 ]; then
        echo -e "❌ Instancias vulnerables: ${RED}$VULNERABLE_INSTANCES${NC}"
    fi
    if [ $ERROR_INSTANCES -gt 0 ]; then
        echo -e "⚠️ Instancias con error: ${YELLOW}$ERROR_INSTANCES${NC}"
    fi
    
    # Calcular porcentaje de cumplimiento
    if [ $TOTAL_INSTANCES -gt 0 ]; then
        COMPLIANCE_PERCENT=$((SECURE_INSTANCES * 100 / TOTAL_INSTANCES))
        echo -e "📈 Cumplimiento: ${GREEN}$COMPLIANCE_PERCENT%${NC}"
    fi
fi

echo ""

# Estado final
if [ $TOTAL_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN INSTANCIAS SAGEMAKER${NC}"
    echo -e "${BLUE}💡 No hay configuraciones que verificar${NC}"
elif [ $VULNERABLE_INSTANCES -eq 0 ] && [ $ERROR_INSTANCES -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE SEGURO${NC}"
    echo -e "${BLUE}💡 Todas las instancias SageMaker son seguras${NC}"
elif [ $VULNERABLE_INSTANCES -gt 0 ]; then
    echo -e "${RED}⚠️ ESTADO: REQUIERE ATENCIÓN${NC}"
    echo -e "${YELLOW}💡 Ejecutar: ./disable-sagemaker-public-access.sh $PROFILE${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: VERIFICACIÓN PARCIAL${NC}"
    echo -e "${BLUE}💡 Revisar instancias con errores${NC}"
fi

echo -e "📋 Reporte: ${GREEN}$VERIFICATION_REPORT${NC}"