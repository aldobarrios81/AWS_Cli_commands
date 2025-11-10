#!/bin/bash

# Verificar que se proporcione el perfil como parámetro
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    exit 1
fi

PROFILE="$1"
REGION="us-east-1"

# Verificar credenciales
if ! aws sts get-caller-identity --profile "$PROFILE" > /dev/null 2>&1; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$PROFILE")

echo "=== Verificación de Security Groups No Utilizados ==="
echo "Perfil: $PROFILE  |  Account ID: $ACCOUNT_ID  |  Región: $REGION"
echo ""

# Contadores
TOTAL_SGS=0
UNUSED_SGS=0
IN_USE_SGS=0

echo "🔍 Analizando Security Groups..."

# Obtener todos los security groups (excluyendo el default de la VPC por defecto)
ALL_SGS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "SecurityGroups[?GroupName!='default'].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}" \
    --output json)

TOTAL_SGS=$(echo "$ALL_SGS" | jq '. | length')
echo "   📊 Total Security Groups encontrados: $TOTAL_SGS"
echo ""

# Lista de security groups no utilizados
UNUSED_LIST=""

for row in $(echo "${ALL_SGS}" | jq -c '.[]'); do
    SG_ID=$(echo $row | jq -r '.GroupId')
    SG_NAME=$(echo $row | jq -r '.GroupName')
    VPC_ID=$(echo $row | jq -r '.VpcId')
    
    # Verificar si está asociado a instancias EC2
    EC2_INSTANCES=$(aws ec2 describe-instances \
        --region "$REGION" \
        --profile "$PROFILE" \
        --filters "Name=instance.group-id,Values=$SG_ID" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null)
    
    # Verificar si está asociado a interfaces de red
    NETWORK_INTERFACES=$(aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --profile "$PROFILE" \
        --filters "Name=group-id,Values=$SG_ID" \
        --query "NetworkInterfaces[].NetworkInterfaceId" \
        --output text 2>/dev/null)
    
    # Verificar si está asociado a load balancers
    ELB_CLASSIC=$(aws elb describe-load-balancers \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "LoadBalancerDescriptions[?contains(SecurityGroups, '$SG_ID')].LoadBalancerName" \
        --output text 2>/dev/null)
    
    ELB_V2=$(aws elbv2 describe-load-balancers \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "LoadBalancers[?contains(SecurityGroups, '$SG_ID')].LoadBalancerName" \
        --output text 2>/dev/null)
    
    # Verificar si está referenciado por otros security groups
    REFERENCED_BY=$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query "SecurityGroups[].IpPermissions[].UserIdGroupPairs[?GroupId=='$SG_ID'].GroupId" \
        --output text 2>/dev/null)
    
    # Determinar si está en uso
    if [ -n "$EC2_INSTANCES" ] || [ -n "$NETWORK_INTERFACES" ] || [ -n "$ELB_CLASSIC" ] || [ -n "$ELB_V2" ] || [ -n "$REFERENCED_BY" ]; then
        IN_USE_SGS=$((IN_USE_SGS + 1))
    else
        UNUSED_SGS=$((UNUSED_SGS + 1))
        UNUSED_LIST="${UNUSED_LIST}   • $SG_NAME ($SG_ID) - VPC: $VPC_ID\n"
    fi
done

echo "=================================================================="
echo "📊 RESUMEN DE SECURITY GROUPS - ${PROFILE^^}"
echo "=================================================================="
echo "📈 Total Security Groups analizados: $TOTAL_SGS"
echo "✅ Security Groups en uso: $IN_USE_SGS"
echo "❌ Security Groups no utilizados: $UNUSED_SGS"

if [ $UNUSED_SGS -gt 0 ]; then
    echo ""
    echo "🚨 SECURITY GROUPS NO UTILIZADOS ENCONTRADOS:"
    echo "=============================================="
    echo -e "$UNUSED_LIST"
    echo ""
    echo "🔧 ACCIONES RECOMENDADAS:"
    echo "========================"
    echo "1. Revisar cada security group para confirmar que no está en uso"
    echo "2. Ejecutar script de limpieza para eliminar los no utilizados"
    echo "3. Implementar tags para mejor identificación de propósito"
else
    echo ""
    echo "🎉 ¡Excelente! No se encontraron security groups no utilizados"
    echo "   Todos los security groups están siendo utilizados correctamente"
fi

echo ""
echo "=== Verificación completada ✅ ==="