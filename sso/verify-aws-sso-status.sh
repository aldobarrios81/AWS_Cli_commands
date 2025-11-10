#!/bin/bash
# verify-aws-sso-status.sh
# Comprueba que AWS Single Sign-On esté habilitado en la cuenta (solo verificación)

PROFILE="metrokia"
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
echo -e "${CYAN}🔍 VERIFICACIÓN DE AWS SSO (IAM Identity Center)${NC}"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
echo -e "${BLUE}🔐 Verificando credenciales...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query 'Account' --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ ERROR: No se puede acceder al perfil '$PROFILE'${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# 1. Verificar si AWS SSO (Identity Center) está habilitado
echo -e "${BLUE}🏢 1. ESTADO DE AWS SSO (IDENTITY CENTER):${NC}"
SSO_INSTANCES=$(aws sso-admin list-instances --profile "$PROFILE" --region "$REGION" --query 'Instances[].{InstanceArn:InstanceArn,IdentityStoreId:IdentityStoreId,Status:Status}' --output text 2>/dev/null)

if [ $? -eq 0 ] && [ ! -z "$SSO_INSTANCES" ] && [ "$SSO_INSTANCES" != "None" ]; then
    echo -e "${GREEN}   ✅ AWS SSO (Identity Center) está HABILITADO${NC}"
    echo "$SSO_INSTANCES" | while read instance_arn identity_store_id status; do
        if [ ! -z "$instance_arn" ]; then
            echo -e "${GREEN}      • Instance ARN: $instance_arn${NC}"
            echo -e "${BLUE}        Identity Store ID: $identity_store_id${NC}"
            if [ ! -z "$status" ] && [ "$status" != "None" ]; then
                echo -e "${BLUE}        Estado: $status${NC}"
            fi
        fi
    done
    SSO_ENABLED=true
else
    echo -e "${RED}   ❌ AWS SSO (Identity Center) NO está habilitado${NC}"
    SSO_ENABLED=false
fi
echo ""

# 2. Verificar Permission Sets (si SSO está habilitado)
if [ "$SSO_ENABLED" = true ]; then
    echo -e "${BLUE}🎭 2. PERMISSION SETS CONFIGURADOS:${NC}"
    INSTANCE_ARN=$(echo "$SSO_INSTANCES" | head -1 | cut -f1)
    
    PERMISSION_SETS=$(aws sso-admin list-permission-sets --instance-arn "$INSTANCE_ARN" --profile "$PROFILE" --region "$REGION" --query 'PermissionSets' --output text 2>/dev/null)
    
    if [ ! -z "$PERMISSION_SETS" ] && [ "$PERMISSION_SETS" != "None" ]; then
        echo -e "${GREEN}   ✅ Permission Sets encontrados:${NC}"
        for ps_arn in $PERMISSION_SETS; do
            PS_NAME=$(aws sso-admin describe-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$ps_arn" --profile "$PROFILE" --region "$REGION" --query 'PermissionSet.Name' --output text 2>/dev/null)
            PS_DURATION=$(aws sso-admin describe-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$ps_arn" --profile "$PROFILE" --region "$REGION" --query 'PermissionSet.SessionDuration' --output text 2>/dev/null)
            
            echo -e "${GREEN}      • $PS_NAME${NC}"
            echo -e "${BLUE}        ARN: $ps_arn${NC}"
            if [ ! -z "$PS_DURATION" ] && [ "$PS_DURATION" != "None" ]; then
                echo -e "${BLUE}        Duración de sesión: $PS_DURATION${NC}"
            fi
        done
    else
        echo -e "${YELLOW}   ⚠️ No se encontraron Permission Sets configurados${NC}"
    fi
    echo ""
    
    # 3. Verificar Account Assignments
    echo -e "${BLUE}👥 3. ASIGNACIONES DE CUENTA:${NC}"
    ACCOUNT_ASSIGNMENTS=$(aws sso-admin list-account-assignments --instance-arn "$INSTANCE_ARN" --account-id "$ACCOUNT_ID" --profile "$PROFILE" --region "$REGION" --query 'AccountAssignments[].{PrincipalType:PrincipalType,PrincipalId:PrincipalId,PermissionSetArn:PermissionSetArn}' --output text 2>/dev/null)
    
    if [ ! -z "$ACCOUNT_ASSIGNMENTS" ] && [ "$ACCOUNT_ASSIGNMENTS" != "None" ]; then
        echo -e "${GREEN}   ✅ Asignaciones de cuenta encontradas:${NC}"
        echo "$ACCOUNT_ASSIGNMENTS" | while read principal_type principal_id permission_set_arn; do
            if [ ! -z "$principal_type" ]; then
                PS_NAME=$(aws sso-admin describe-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$permission_set_arn" --profile "$PROFILE" --region "$REGION" --query 'PermissionSet.Name' --output text 2>/dev/null)
                echo -e "${GREEN}      • Tipo: $principal_type | ID: $principal_id${NC}"
                echo -e "${BLUE}        Permission Set: $PS_NAME${NC}"
            fi
        done
    else
        echo -e "${YELLOW}   ⚠️ No se encontraron asignaciones de cuenta${NC}"
    fi
    echo ""
fi

# 4. Verificar configuración de perfil SSO en AWS CLI
echo -e "${BLUE}⚙️ 4. CONFIGURACIÓN DE PERFIL SSO:${NC}"
SSO_START_URL=$(aws configure get sso_start_url --profile "$PROFILE" 2>/dev/null)
SSO_REGION=$(aws configure get sso_region --profile "$PROFILE" 2>/dev/null)
SSO_ACCOUNT_ID=$(aws configure get sso_account_id --profile "$PROFILE" 2>/dev/null)
SSO_ROLE_NAME=$(aws configure get sso_role_name --profile "$PROFILE" 2>/dev/null)

if [ ! -z "$SSO_START_URL" ]; then
    echo -e "${GREEN}   ✅ Perfil configurado para SSO:${NC}"
    echo -e "${BLUE}      SSO Start URL: $SSO_START_URL${NC}"
    echo -e "${BLUE}      SSO Región: $SSO_REGION${NC}"
    echo -e "${BLUE}      SSO Account ID: $SSO_ACCOUNT_ID${NC}"
    echo -e "${BLUE}      SSO Role Name: $SSO_ROLE_NAME${NC}"
    PROFILE_SSO_CONFIGURED=true
else
    echo -e "${YELLOW}   ⚠️ Perfil NO configurado para SSO (usando credenciales tradicionales)${NC}"
    PROFILE_SSO_CONFIGURED=false
fi
echo ""

# 5. Verificar estado de sesión SSO (si está configurado)
if [ "$PROFILE_SSO_CONFIGURED" = true ]; then
    echo -e "${BLUE}🔑 5. ESTADO DE SESIÓN SSO:${NC}"
    
    # Intentar verificar credenciales actuales
    CURRENT_USER=$(aws sts get-caller-identity --profile "$PROFILE" --query 'Arn' --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$CURRENT_USER" ]; then
        if echo "$CURRENT_USER" | grep -q "assumed-role"; then
            echo -e "${GREEN}   ✅ Sesión SSO activa${NC}"
            echo -e "${BLUE}      Usuario actual: $CURRENT_USER${NC}"
        else
            echo -e "${YELLOW}   ⚠️ Usando credenciales no-SSO${NC}"
            echo -e "${BLUE}      Usuario actual: $CURRENT_USER${NC}"
        fi
    else
        echo -e "${RED}   ❌ No hay sesión activa - requiere login${NC}"
        echo -e "${BLUE}      Usar: aws sso login --profile $PROFILE${NC}"
    fi
    echo ""
fi

# Resumen final
echo "=================================================================="
echo -e "${CYAN}📊 RESUMEN DE VERIFICACIÓN AWS SSO${NC}"
echo "=================================================================="

# Calcular puntuación
SCORE=0
MAX_SCORE=100

if [ "$SSO_ENABLED" = true ]; then
    SCORE=$((SCORE + 40))
    echo -e "${GREEN}✅ AWS SSO habilitado: +40 pts${NC}"
else
    echo -e "${RED}❌ AWS SSO no habilitado: 0 pts${NC}"
fi

if [ "$PROFILE_SSO_CONFIGURED" = true ]; then
    SCORE=$((SCORE + 30))
    echo -e "${GREEN}✅ Perfil configurado para SSO: +30 pts${NC}"
else
    echo -e "${YELLOW}⚠️ Perfil no configurado para SSO: 0 pts${NC}"
fi

if [ ! -z "$PERMISSION_SETS" ] && [ "$PERMISSION_SETS" != "None" ]; then
    SCORE=$((SCORE + 20))
    echo -e "${GREEN}✅ Permission Sets configurados: +20 pts${NC}"
else
    echo -e "${YELLOW}⚠️ Permission Sets no configurados: 0 pts${NC}"
fi

if [ ! -z "$ACCOUNT_ASSIGNMENTS" ] && [ "$ACCOUNT_ASSIGNMENTS" != "None" ]; then
    SCORE=$((SCORE + 10))
    echo -e "${GREEN}✅ Asignaciones de cuenta: +10 pts${NC}"
else
    echo -e "${YELLOW}⚠️ Sin asignaciones de cuenta: 0 pts${NC}"
fi

echo ""
echo -e "${BLUE}🎯 PUNTUACIÓN TOTAL: $SCORE/$MAX_SCORE${NC}"

if [ $SCORE -ge 80 ]; then
    echo -e "${GREEN}🎉 EXCELENTE: AWS SSO completamente configurado${NC}"
elif [ $SCORE -ge 60 ]; then
    echo -e "${YELLOW}⚠️ BUENO: AWS SSO parcialmente configurado${NC}"
elif [ $SCORE -ge 40 ]; then
    echo -e "${YELLOW}📋 BÁSICO: AWS SSO habilitado pero requiere configuración${NC}"
else
    echo -e "${RED}❌ CRÍTICO: AWS SSO no implementado${NC}"
fi

echo ""
echo -e "${PURPLE}📋 ESTADO ACTUAL:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SSO_ENABLED" = true ]; then
    echo -e "${GREEN}• AWS SSO (Identity Center) está habilitado en la cuenta${NC}"
else
    echo -e "${RED}• AWS SSO (Identity Center) NO está habilitado${NC}"
fi

if [ "$PROFILE_SSO_CONFIGURED" = true ]; then
    echo -e "${GREEN}• El perfil '$PROFILE' está configurado para usar SSO${NC}"
else
    echo -e "${YELLOW}• El perfil '$PROFILE' usa credenciales tradicionales${NC}"
fi

echo ""
echo -e "${BLUE}🔔 PRÓXIMOS PASOS RECOMENDADOS:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SSO_ENABLED" = false ]; then
    echo "1. Habilitar AWS SSO desde la consola web o con permisos adecuados"
    echo "2. Configurar Identity Source (Internal o External)"
    echo "3. Crear Permission Sets"
    echo "4. Asignar usuarios/grupos a las cuentas"
fi

if [ "$PROFILE_SSO_CONFIGURED" = false ] && [ "$SSO_ENABLED" = true ]; then
    echo "1. Configurar el perfil para usar SSO:"
    echo "   aws configure sso --profile $PROFILE"
    echo "2. Realizar login inicial:"
    echo "   aws sso login --profile $PROFILE"
fi

echo ""
echo "=================================================================="
echo -e "${GREEN}🏁 VERIFICACIÓN COMPLETADA${NC}"
echo "=================================================================="