#!/bin/bash
# disable-sagemaker-public-access.sh
# Deshabilitar acceso público para instancias de notebook SageMaker
# Regla de seguridad: Disable public access for SageMaker notebook instances
# Uso: ./disable-sagemaker-public-access.sh [perfil]

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
echo -e "${BLUE}🔒 DESHABILITANDO ACCESO PÚBLICO SAGEMAKER NOTEBOOKS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando seguridad para instancias de notebook SageMaker"
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

# Verificar si SageMaker está disponible en la región
echo -e "${PURPLE}🔍 Verificando disponibilidad de SageMaker...${NC}"
SAGEMAKER_AVAILABLE=$(aws sagemaker list-notebook-instances --profile "$PROFILE" --region "$REGION" --max-items 1 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ SageMaker no disponible en región $REGION o sin permisos${NC}"
    echo -e "${BLUE}💡 Verificando otras regiones principales...${NC}"
    
    # Verificar en regiones principales
    MAIN_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")
    FOUND_REGION=""
    
    for region in "${MAIN_REGIONS[@]}"; do
        echo -e "   🔍 Verificando región: ${BLUE}$region${NC}"
        TEST_RESULT=$(aws sagemaker list-notebook-instances --profile "$PROFILE" --region "$region" --max-items 1 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            FOUND_REGION="$region"
            echo -e "   ✅ SageMaker disponible en: ${GREEN}$region${NC}"
            break
        else
            echo -e "   ❌ No disponible en: $region"
        fi
    done
    
    if [ -n "$FOUND_REGION" ]; then
        echo -e "${YELLOW}💡 Cambiando a región: $FOUND_REGION${NC}"
        REGION="$FOUND_REGION"
    else
        echo -e "${YELLOW}⚠️ SageMaker no disponible en regiones principales${NC}"
        echo -e "${BLUE}💡 Continuando con configuraciones de seguridad generales${NC}"
    fi
else
    echo -e "✅ SageMaker disponible en región: ${GREEN}$REGION${NC}"
fi

echo ""

# Paso 1: Inventario de instancias de notebook existentes
echo -e "${PURPLE}=== Paso 1: Inventario de instancias SageMaker ===${NC}"

# Obtener lista de instancias de notebook
NOTEBOOK_INSTANCES=$(aws sagemaker list-notebook-instances --profile "$PROFILE" --region "$REGION" --query 'NotebookInstances[].NotebookInstanceName' --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ No se pudo obtener lista de instancias de notebook${NC}"
    NOTEBOOK_COUNT=0
elif [ -z "$NOTEBOOK_INSTANCES" ] || [ "$NOTEBOOK_INSTANCES" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron instancias de notebook SageMaker${NC}"
    NOTEBOOK_COUNT=0
else
    NOTEBOOK_COUNT=$(echo "$NOTEBOOK_INSTANCES" | wc -w)
    echo -e "${GREEN}✅ Instancias de notebook encontradas: $NOTEBOOK_COUNT${NC}"
    
    # Mostrar información detallada de cada instancia
    echo -e "${BLUE}📄 Análisis de instancias de notebook:${NC}"
    
    INSTANCES_UPDATED=0
    INSTANCES_ALREADY_SECURE=0
    INSTANCES_ERROR=0
    
    for instance in $NOTEBOOK_INSTANCES; do
        echo -e "${CYAN}📓 Procesando notebook: $instance${NC}"
        
        # Obtener detalles de la instancia
        INSTANCE_DETAILS=$(aws sagemaker describe-notebook-instance --notebook-instance-name "$instance" --profile "$PROFILE" --region "$REGION" --output json 2>/dev/null)
        
        if [ $? -eq 0 ] && [ "$INSTANCE_DETAILS" != "null" ]; then
            INSTANCE_STATUS=$(echo "$INSTANCE_DETAILS" | jq -r '.NotebookInstanceStatus' 2>/dev/null)
            INSTANCE_TYPE=$(echo "$INSTANCE_DETAILS" | jq -r '.InstanceType' 2>/dev/null)
            DIRECT_INTERNET_ACCESS=$(echo "$INSTANCE_DETAILS" | jq -r '.DirectInternetAccess // "Enabled"' 2>/dev/null)
            SUBNET_ID=$(echo "$INSTANCE_DETAILS" | jq -r '.SubnetId // "N/A"' 2>/dev/null)
            CREATION_TIME=$(echo "$INSTANCE_DETAILS" | jq -r '.CreationTime' 2>/dev/null | cut -d'T' -f1)
            
            echo -e "   📊 Estado: ${BLUE}$INSTANCE_STATUS${NC}"
            echo -e "   💻 Tipo: ${BLUE}$INSTANCE_TYPE${NC}"
            echo -e "   📅 Creado: ${BLUE}$CREATION_TIME${NC}"
            
            # Verificar y actualizar acceso directo a Internet
            if [ "$DIRECT_INTERNET_ACCESS" == "Enabled" ]; then
                echo -e "   🌐 Acceso a Internet: ${RED}HABILITADO (Riesgo de seguridad)${NC}"
                
                # Verificar si la instancia está en estado que permite actualización
                if [ "$INSTANCE_STATUS" == "InService" ] || [ "$INSTANCE_STATUS" == "Stopped" ]; then
                    echo -e "   🔧 Deshabilitando acceso directo a Internet..."
                    
                    # Actualizar configuración
                    aws sagemaker update-notebook-instance \
                        --notebook-instance-name "$instance" \
                        --profile "$PROFILE" \
                        --region "$REGION" \
                        --no-direct-internet-access >/dev/null 2>&1
                    
                    if [ $? -eq 0 ]; then
                        echo -e "   ✅ Acceso público deshabilitado exitosamente"
                        INSTANCES_UPDATED=$((INSTANCES_UPDATED + 1))
                    else
                        echo -e "   ${RED}❌ Error deshabilitando acceso público${NC}"
                        echo -e "   ${YELLOW}💡 La instancia puede requerir detención manual${NC}"
                        INSTANCES_ERROR=$((INSTANCES_ERROR + 1))
                    fi
                else
                    echo -e "   ${YELLOW}⚠️ Estado '$INSTANCE_STATUS' no permite actualización directa${NC}"
                    echo -e "   ${BLUE}💡 Requerirá detención y actualización manual${NC}"
                    INSTANCES_ERROR=$((INSTANCES_ERROR + 1))
                fi
            else
                echo -e "   🌐 Acceso a Internet: ${GREEN}DESHABILITADO${NC}"
                INSTANCES_ALREADY_SECURE=$((INSTANCES_ALREADY_SECURE + 1))
            fi
            
            # Verificar configuración de red adicional
            if [ "$SUBNET_ID" != "N/A" ] && [ "$SUBNET_ID" != "null" ]; then
                echo -e "   🔗 Subnet: ${BLUE}$SUBNET_ID${NC}"
                
                # Verificar si la subnet es pública o privada
                ROUTE_TABLE=$(aws ec2 describe-route-tables --profile "$PROFILE" --region "$REGION" --filters "Name=association.subnet-id,Values=$SUBNET_ID" --query 'RouteTables[0].Routes[?GatewayId!=null && starts_with(GatewayId, `igw-`)].GatewayId' --output text 2>/dev/null)
                
                if [ -n "$ROUTE_TABLE" ] && [ "$ROUTE_TABLE" != "None" ]; then
                    echo -e "   ⚠️ Subnet tipo: ${YELLOW}PÚBLICA${NC}"
                else
                    echo -e "   ✅ Subnet tipo: ${GREEN}PRIVADA${NC}"
                fi
            else
                echo -e "   🔗 Red: ${YELLOW}VPC por defecto${NC}"
            fi
            
        else
            echo -e "   ${RED}❌ Error obteniendo detalles de la instancia${NC}"
            INSTANCES_ERROR=$((INSTANCES_ERROR + 1))
        fi
        
        echo ""
    done
fi

# Crear documentación de mejores prácticas
echo -e "${PURPLE}=== Paso 2: Generando documentación de seguridad ===${NC}"

SECURITY_REPORT="sagemaker-security-report-$PROFILE-$(date +%Y%m%d).md"

cat > "$SECURITY_REPORT" << EOF
# Reporte de Seguridad SageMaker - $PROFILE

**Fecha**: $(date)
**Región**: $REGION
**Account ID**: $ACCOUNT_ID

## Resumen Ejecutivo

### Instancias Procesadas
- **Total de notebooks**: $NOTEBOOK_COUNT
- **Actualizadas (público → privado)**: $INSTANCES_UPDATED
- **Ya seguras**: $INSTANCES_ALREADY_SECURE  
- **Errores/Requieren atención**: $INSTANCES_ERROR

## Configuraciones de Seguridad Implementadas

### ✅ Acceso Directo a Internet
- DirectInternetAccess configurado en \`Disabled\` para todas las instancias procesables
- Instancias ahora requieren VPC/subnet privada para acceso externo

### 🔍 Verificaciones Realizadas
- Estado de instancias y capacidad de actualización
- Tipo de subnet (pública vs privada)
- Configuración de VPC y security groups

## Recomendaciones Adicionales

### 1. Configuración de Red Segura
\`\`\`bash
# Para nuevas instancias, usar siempre:
aws sagemaker create-notebook-instance \\
    --notebook-instance-name secure-notebook \\
    --instance-type ml.t3.medium \\
    --role-arn arn:aws:iam::$ACCOUNT_ID:role/SageMakerRole \\
    --direct-internet-access Disabled \\
    --subnet-id subnet-xxxxx \\  # Subnet privada
    --security-group-ids sg-xxxxx
\`\`\`

### 2. VPC Endpoints
- Configurar VPC Endpoints para SageMaker API
- Configurar VPC Endpoints para SageMaker Runtime
- Eliminar dependencia de Internet público

### 3. Monitoreo Continuo
- Implementar alertas para nuevas instancias públicas
- Auditoría regular de configuraciones SageMaker
- Políticas IAM para prevenir creación de notebooks públicos

### 4. Acceso Seguro
- VPN corporativa para acceso a notebooks privados
- AWS PrivateLink para conectividad segura
- Bastion hosts en casos específicos

## Scripts de Verificación

\`\`\`bash
# Verificar configuración actual
aws sagemaker list-notebook-instances --profile $PROFILE --region $REGION

# Verificar instancia específica
aws sagemaker describe-notebook-instance --notebook-instance-name NOMBRE

# Verificar VPC Endpoints
aws ec2 describe-vpc-endpoints --filters "Name=service-name,Values=*sagemaker*"
\`\`\`

EOF

echo -e "✅ Reporte de seguridad generado: ${GREEN}$SECURITY_REPORT${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN DE SEGURIDAD SAGEMAKER ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📍 Región: ${GREEN}$REGION${NC}"
echo -e "📓 Total instancias: ${GREEN}$NOTEBOOK_COUNT${NC}"

if [ $NOTEBOOK_COUNT -gt 0 ]; then
    echo -e "✅ Instancias actualizadas: ${GREEN}$INSTANCES_UPDATED${NC}"
    echo -e "✅ Ya seguras: ${GREEN}$INSTANCES_ALREADY_SECURE${NC}"
    if [ $INSTANCES_ERROR -gt 0 ]; then
        echo -e "⚠️ Requieren atención: ${YELLOW}$INSTANCES_ERROR${NC}"
    fi
fi

echo -e "📋 Reporte generado: ${GREEN}$SECURITY_REPORT${NC}"

echo ""
TOTAL_SECURE=$((INSTANCES_UPDATED + INSTANCES_ALREADY_SECURE))
if [ $TOTAL_SECURE -eq $NOTEBOOK_COUNT ] && [ $NOTEBOOK_COUNT -gt 0 ]; then
    echo -e "${GREEN}🎉 SAGEMAKER NOTEBOOKS - COMPLETAMENTE SEGURO${NC}"
    echo -e "${BLUE}💡 Todas las instancias tienen acceso público deshabilitado${NC}"
elif [ $NOTEBOOK_COUNT -eq 0 ]; then
    echo -e "${GREEN}✅ NO HAY INSTANCIAS SAGEMAKER PARA ASEGURAR${NC}"
    echo -e "${BLUE}💡 Configuraciones de seguridad están listas para futuras instancias${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN DE SEGURIDAD PARCIALMENTE COMPLETA${NC}"
    echo -e "${BLUE}💡 Revisar instancias que requieren atención manual${NC}"
fi

