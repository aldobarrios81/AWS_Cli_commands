#!/bin/bash
# verify-iam-support-role.sh
# Verificar existencia y configuración del rol IAM para soporte de AWS
# Análisis de cumplimiento de mejores prácticas de soporte

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
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
echo -e "${BLUE}🛠️ VERIFICACIÓN IAM SUPPORT ROLE${NC}"
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

# Nombres comunes para roles de soporte
COMMON_SUPPORT_ROLE_NAMES=(
    "AWS-TrustedSupportAccess"
    "AWSSupportAccess"
    "SupportRole"
    "AWS-Support-Role"
    "TrustedSupportRole"
    "AWSSupport"
)

# Variables de análisis
SUPPORT_ROLES_FOUND=0
SUPPORT_ROLES_LIST=()

echo -e "${PURPLE}=== Búsqueda de Roles de Soporte ===${NC}"

# Buscar todos los roles que contengan "support" en el nombre
ALL_SUPPORT_ROLES=$(aws iam list-roles \
    --profile "$PROFILE" \
    --query 'Roles[?contains(RoleName, `Support`) || contains(RoleName, `support`)].RoleName' \
    --output text 2>/dev/null)

if [ -n "$ALL_SUPPORT_ROLES" ] && [ "$ALL_SUPPORT_ROLES" != "None" ]; then
    echo -e "${GREEN}📊 Roles con 'Support' en el nombre encontrados:${NC}"
    for role in $ALL_SUPPORT_ROLES; do
        echo -e "   - ${CYAN}$role${NC}"
        SUPPORT_ROLES_LIST+=("$role")
        SUPPORT_ROLES_FOUND=$((SUPPORT_ROLES_FOUND + 1))
    done
    echo ""
else
    echo -e "${YELLOW}⚠️ No se encontraron roles con 'Support' en el nombre${NC}"
fi

# Verificar roles específicos recomendados
echo -e "${PURPLE}=== Verificación de Roles Recomendados ===${NC}"

RECOMMENDED_ROLE_EXISTS=false
RECOMMENDED_ROLE_NAME=""

for role_name in "${COMMON_SUPPORT_ROLE_NAMES[@]}"; do
    echo -e "🔍 Verificando rol: ${BLUE}$role_name${NC}"
    
    ROLE_INFO=$(aws iam get-role \
        --role-name "$role_name" \
        --profile "$PROFILE" \
        --query 'Role.{RoleName:RoleName,CreateDate:CreateDate,Description:Description}' \
        --output json 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$ROLE_INFO" ]; then
        RECOMMENDED_ROLE_EXISTS=true
        RECOMMENDED_ROLE_NAME="$role_name"
        echo -e "   ✅ ${GREEN}ENCONTRADO${NC}"
        
        # Extraer información del rol
        ROLE_CREATED=$(echo "$ROLE_INFO" | jq -r '.CreateDate' | cut -d'T' -f1)
        ROLE_DESCRIPTION=$(echo "$ROLE_INFO" | jq -r '.Description // "Sin descripción"')
        
        echo -e "   📅 Creado: ${BLUE}$ROLE_CREATED${NC}"
        echo -e "   📝 Descripción: ${BLUE}$ROLE_DESCRIPTION${NC}"
        
        # Verificar trust policy (assume role policy)
        TRUST_POLICY=$(aws iam get-role \
            --role-name "$role_name" \
            --profile "$PROFILE" \
            --query 'Role.AssumeRolePolicyDocument' \
            --output json 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$TRUST_POLICY" ]; then
            echo -e "   🔐 Trust Policy:"
            
            # Verificar si permite al servicio de soporte de AWS
            if echo "$TRUST_POLICY" | jq -r '.Statement[].Principal.Service[]? // empty' | grep -q "support.amazonaws.com"; then
                echo -e "      ✅ ${GREEN}Permite acceso al servicio AWS Support${NC}"
            else
                echo -e "      ⚠️ ${YELLOW}No configurado para servicio AWS Support${NC}"
            fi
            
            # Verificar si permite acceso a usuarios/roles específicos
            AWS_PRINCIPALS=$(echo "$TRUST_POLICY" | jq -r '.Statement[].Principal.AWS[]? // empty' 2>/dev/null)
            if [ -n "$AWS_PRINCIPALS" ]; then
                echo -e "      📋 Principals AWS autorizados:"
                echo "$AWS_PRINCIPALS" | while read principal; do
                    echo -e "         - ${BLUE}$principal${NC}"
                done
            fi
        fi
        
        # Verificar políticas adjuntas
        echo -e "   📋 Políticas adjuntas:"
        
        # Políticas administradas
        MANAGED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$role_name" \
            --profile "$PROFILE" \
            --query 'AttachedPolicies[].[PolicyName,PolicyArn]' \
            --output text 2>/dev/null)
        
        if [ -n "$MANAGED_POLICIES" ] && [ "$MANAGED_POLICIES" != "None" ]; then
            echo -e "      🔗 Políticas administradas:"
            while IFS=$'\t' read -r policy_name policy_arn; do
                if [ -n "$policy_name" ]; then
                    echo -e "         - ${GREEN}$policy_name${NC}"
                    
                    # Verificar si es la política de soporte de AWS
                    if [ "$policy_arn" = "arn:aws:iam::aws:policy/AWSSupportAccess" ]; then
                        echo -e "           ✅ ${GREEN}Política oficial de AWS Support${NC}"
                    elif [[ "$policy_arn" == *"Support"* ]]; then
                        echo -e "           ✅ ${BLUE}Política relacionada con soporte${NC}"
                    fi
                fi
            done <<< "$MANAGED_POLICIES"
        else
            echo -e "      ⚠️ ${YELLOW}Sin políticas administradas adjuntas${NC}"
        fi
        
        # Políticas inline
        INLINE_POLICIES=$(aws iam list-role-policies \
            --role-name "$role_name" \
            --profile "$PROFILE" \
            --query 'PolicyNames' \
            --output text 2>/dev/null)
        
        if [ -n "$INLINE_POLICIES" ] && [ "$INLINE_POLICIES" != "None" ] && [ "$INLINE_POLICIES" != "[]" ]; then
            echo -e "      📄 Políticas inline:"
            for policy in $INLINE_POLICIES; do
                echo -e "         - ${BLUE}$policy${NC}"
            done
        fi
        
        echo ""
        break
    else
        echo -e "   ❌ ${RED}NO ENCONTRADO${NC}"
    fi
done

echo ""

# Análisis de configuración de soporte
echo -e "${PURPLE}=== Análisis de Configuración de Soporte ===${NC}"

# Verificar plan de soporte (requiere permisos especiales)
echo -e "🔍 Verificando configuración de AWS Support..."

SUPPORT_CASES=$(aws support describe-cases \
    --profile "$PROFILE" \
    --query 'cases[0].caseId' \
    --output text --region us-east-1 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "✅ ${GREEN}API de AWS Support accesible${NC}"
    echo -e "💡 La cuenta tiene acceso a AWS Support API"
else
    echo -e "⚠️ ${YELLOW}API de AWS Support no accesible${NC}"
    echo -e "💡 Puede ser debido a plan de soporte básico o permisos insuficientes"
fi

# Verificar si hay roles que pueden asumir roles de soporte
echo -e ""
echo -e "🔍 Verificando usuarios/roles con capacidad de asumir roles de soporte..."

if [ "$RECOMMENDED_ROLE_EXISTS" = true ]; then
    echo -e "✅ Rol de soporte recomendado existe: ${GREEN}$RECOMMENDED_ROLE_NAME${NC}"
    
    # Buscar usuarios/roles que pueden asumir este rol
    USERS_WITH_ASSUME_ROLE=$(aws iam list-users \
        --profile "$PROFILE" \
        --query 'Users[].UserName' \
        --output text 2>/dev/null)
    
    if [ -n "$USERS_WITH_ASSUME_ROLE" ]; then
        echo -e "📋 Verificando usuarios con permisos sts:AssumeRole..."
        # Esta verificación requeriría revisar todas las políticas, lo cual es complejo
        echo -e "💡 ${BLUE}Revisar manualmente qué usuarios pueden asumir el rol de soporte${NC}"
    fi
else
    echo -e "❌ ${RED}No se encontró rol de soporte recomendado${NC}"
fi

echo ""

# Generar reporte
VERIFICATION_REPORT="iam-support-role-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "support_roles_found": $SUPPORT_ROLES_FOUND,
    "recommended_role_exists": $RECOMMENDED_ROLE_EXISTS,
    "recommended_role_name": "$RECOMMENDED_ROLE_NAME",
    "support_api_accessible": "$(if aws support describe-cases --profile "$PROFILE" --query 'cases[0].caseId' --output text --region us-east-1 >/dev/null 2>&1; then echo "true"; else echo "false"; fi)",
    "compliance_status": "$(if [ "$RECOMMENDED_ROLE_EXISTS" = true ]; then echo "COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "found_roles": [
$(IFS=,; printf '"%s"' "${SUPPORT_ROLES_LIST[*]}")
  ],
  "recommendations": [
    "Crear rol AWS-TrustedSupportAccess si no existe",
    "Adjuntar política AWSSupportAccess al rol",
    "Configurar trust policy para support.amazonaws.com",
    "Revisar permisos de usuarios para asumir rol de soporte",
    "Documentar procedimientos de escalación a AWS Support",
    "Considerar plan de soporte Business o Enterprise"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ "$RECOMMENDED_ROLE_EXISTS" = false ]; then
    echo ""
    echo -e "${PURPLE}=== Comandos de Remediación ===${NC}"
    echo -e "${CYAN}🔧 Para crear el rol de soporte recomendado:${NC}"
    echo ""
    echo -e "${BLUE}# 1. Crear el rol${NC}"
    echo -e "${BLUE}aws iam create-role \\${NC}"
    echo -e "${BLUE}  --role-name AWS-TrustedSupportAccess \\${NC}"
    echo -e "${BLUE}  --assume-role-policy-document '{${NC}"
    echo -e "${BLUE}    \"Version\": \"2012-10-17\",${NC}"
    echo -e "${BLUE}    \"Statement\": [${NC}"
    echo -e "${BLUE}      {${NC}"
    echo -e "${BLUE}        \"Effect\": \"Allow\",${NC}"
    echo -e "${BLUE}        \"Principal\": { \"Service\": \"support.amazonaws.com\" },${NC}"
    echo -e "${BLUE}        \"Action\": \"sts:AssumeRole\"${NC}"
    echo -e "${BLUE}      }${NC}"
    echo -e "${BLUE}    ]${NC}"
    echo -e "${BLUE}  }' \\${NC}"
    echo -e "${BLUE}  --description \"Role for AWS Support access\" \\${NC}"
    echo -e "${BLUE}  --profile $PROFILE${NC}"
    echo ""
    echo -e "${BLUE}# 2. Adjuntar política de soporte${NC}"
    echo -e "${BLUE}aws iam attach-role-policy \\${NC}"
    echo -e "${BLUE}  --role-name AWS-TrustedSupportAccess \\${NC}"
    echo -e "${BLUE}  --policy-arn arn:aws:iam::aws:policy/AWSSupportAccess \\${NC}"
    echo -e "${BLUE}  --profile $PROFILE${NC}"
    echo ""
    echo -e "${CYAN}🔧 O usar script existente (adaptado):${NC}"
    echo -e "${BLUE}# Editar create_support_roles.sh para cambiar perfil a $PROFILE${NC}"
    echo -e "${BLUE}./create_support_roles.sh${NC}"
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN IAM SUPPORT ROLE ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📊 Roles de soporte encontrados: ${GREEN}$SUPPORT_ROLES_FOUND${NC}"

if [ "$RECOMMENDED_ROLE_EXISTS" = true ]; then
    echo -e "✅ Rol recomendado: ${GREEN}$RECOMMENDED_ROLE_NAME${NC}"
else
    echo -e "❌ Rol recomendado: ${RED}NO ENCONTRADO${NC}"
fi

echo ""

# Estado final
if [ "$RECOMMENDED_ROLE_EXISTS" = true ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLIANT${NC}"
    echo -e "${BLUE}💡 Rol de soporte configurado correctamente${NC}"
    echo -e "${BLUE}💡 Verificar que usuarios apropiados pueden asumir el rol${NC}"
else
    echo -e "${RED}⚠️ ESTADO: NO COMPLIANT${NC}"
    echo -e "${YELLOW}💡 Se requiere crear rol de soporte AWS${NC}"
    echo -e "${YELLOW}💡 Ejecutar comandos de remediación arriba${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Información adicional sobre planes de soporte
echo ""
echo -e "${CYAN}📚 Información sobre AWS Support:${NC}"
echo -e "${BLUE}• Basic Support: Gratuito, sin acceso a API${NC}"
echo -e "${BLUE}• Developer Support: \$29/mes, acceso limitado a API${NC}"
echo -e "${BLUE}• Business Support: 10% facturación, acceso completo a API${NC}"
echo -e "${BLUE}• Enterprise Support: 15% facturación, TAM dedicado${NC}"
echo ""