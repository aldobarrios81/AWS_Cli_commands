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

echo "=== Limpieza de Security Groups No Utilizados ==="
echo "Perfil: $PROFILE  |  Account ID: $ACCOUNT_ID  |  Región: $REGION"
echo ""

# Contadores
TOTAL_SGS=0
UNUSED_SGS=0
DELETED_SGS=0
IN_USE_SGS=0

echo "🔍 1. Analizando todos los Security Groups..."

# Obtener todos los security groups (excluyendo el default de la VPC por defecto)
ALL_SGS=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query "SecurityGroups[?GroupName!='default'].{GroupId:GroupId,GroupName:GroupName,VpcId:VpcId}" \
    --output json)

TOTAL_SGS=$(echo "$ALL_SGS" | jq '. | length')
echo "   📊 Total Security Groups encontrados: $TOTAL_SGS"
echo ""

echo "🔍 2. Identificando Security Groups no utilizados..."

for row in $(echo "${ALL_SGS}" | jq -c '.[]'); do
    SG_ID=$(echo $row | jq -r '.GroupId')
    SG_NAME=$(echo $row | jq -r '.GroupName')
    VPC_ID=$(echo $row | jq -r '.VpcId')
    
    echo "   🔍 Verificando: $SG_NAME ($SG_ID)"
    
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
        echo "      ✅ En uso"
        if [ -n "$EC2_INSTANCES" ]; then echo "         - Instancias EC2: $(echo $EC2_INSTANCES | tr '\t' ' ')"; fi
        if [ -n "$NETWORK_INTERFACES" ]; then echo "         - Interfaces de red: $(echo $NETWORK_INTERFACES | tr '\t' ' ')"; fi
        if [ -n "$ELB_CLASSIC" ]; then echo "         - ELB Classic: $(echo $ELB_CLASSIC | tr '\t' ' ')"; fi
        if [ -n "$ELB_V2" ]; then echo "         - ALB/NLB: $(echo $ELB_V2 | tr '\t' ' ')"; fi
        if [ -n "$REFERENCED_BY" ]; then echo "         - Referenciado por otros SGs"; fi
        IN_USE_SGS=$((IN_USE_SGS + 1))
    else
        echo "      ❌ NO UTILIZADO - Candidato para eliminación"
        UNUSED_SGS=$((UNUSED_SGS + 1))
        
        # Intentar eliminar
        echo "      🗑️  Eliminando Security Group..."
        if aws ec2 delete-security-group \
            --group-id "$SG_ID" \
            --region "$REGION" \
            --profile "$PROFILE" 2>/dev/null; then
            echo "      ✅ ELIMINADO: $SG_NAME ($SG_ID)"
            DELETED_SGS=$((DELETED_SGS + 1))
        else
            echo "      ⚠️  ERROR: No se pudo eliminar (puede tener dependencias ocultas)"
        fi
    fi
    echo ""
done

echo "=================================================================="
echo "📊 RESUMEN DE LIMPIEZA DE SECURITY GROUPS - ${PROFILE^^}"
echo "=================================================================="
echo "📈 Total Security Groups analizados: $TOTAL_SGS"
echo "✅ Security Groups en uso: $IN_USE_SGS"
echo "❌ Security Groups no utilizados encontrados: $UNUSED_SGS"
echo "🗑️  Security Groups eliminados: $DELETED_SGS"

if [ $DELETED_SGS -gt 0 ]; then
    echo ""
    echo "🎉 ¡Limpieza completada! Se eliminaron $DELETED_SGS security groups no utilizados"
else
    if [ $UNUSED_SGS -eq 0 ]; then
        echo ""
        echo "🎉 ¡Excelente! No se encontraron security groups no utilizados"
    else
        echo ""
        echo "⚠️  Se encontraron security groups no utilizados pero no se pudieron eliminar"
        echo "   Esto puede deberse a dependencias ocultas o permisos insuficientes"
    fi
fi

echo ""
echo "🔧 RECOMENDACIONES:"
echo "==================="
echo "1. Revisar periódicamente los security groups para mantener limpio el entorno"
echo "2. Usar tags descriptivos para identificar el propósito de cada security group"
echo "3. Implementar políticas de lifecycle management para recursos temporales"
echo "4. Considerar usar AWS Config Rules para detectar automáticamente recursos no utilizados"

echo ""
echo "=== Proceso completado ✅ ==="

