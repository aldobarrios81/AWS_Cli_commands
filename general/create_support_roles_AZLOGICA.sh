#!/bin/bash
# create_support_roles_AZLOGICA.sh
# Crear rol IAM de soporte personalizado para perfil AZLOGICA
# Implementa mejores prácticas de AWS Support

PROFILE="AZLOGICA"
REGION="us-east-1"
ROLE_NAME="AWS-TrustedSupportAccess"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🛠️ CREANDO IAM SUPPORT ROLE${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo -e "Rol: ${GREEN}$ROLE_NAME${NC}"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Verificar si el rol ya existe
echo -e "${PURPLE}🔍 Verificando si el rol ya existe...${NC}"
EXISTING_ROLE=$(aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'Role.RoleName' --output text 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$EXISTING_ROLE" ]; then
    echo -e "${YELLOW}⚠️ El rol '$ROLE_NAME' ya existe${NC}"
    echo -e "¿Deseas continuar y actualizar la configuración? (y/N): "
    read -r confirm
    if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
        echo -e "${BLUE}Operación cancelada${NC}"
        exit 0
    fi
    UPDATE_MODE=true
else
    echo -e "${GREEN}✅ El rol no existe, procediendo con la creación${NC}"
    UPDATE_MODE=false
fi

echo ""

# Crear archivo de trust policy
TRUST_POLICY_FILE="support-trust-policy-temp.json"
cat > "$TRUST_POLICY_FILE" << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAWSSupportService",
      "Effect": "Allow",
      "Principal": {
        "Service": "support.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Sid": "AllowCrossAccountSupport",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalType": "User"
        }
      }
    }
  ]
}
EOF

echo -e "${CYAN}📋 Trust Policy creada:${NC}"
cat "$TRUST_POLICY_FILE" | jq '.'
echo ""

if [ "$UPDATE_MODE" = false ]; then
    echo -e "${PURPLE}🔧 Creando rol: $ROLE_NAME${NC}"
    
    aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document "file://$TRUST_POLICY_FILE" \
      --description "Rol para acceso de AWS Support con capacidades cross-account" \
      --max-session-duration 3600 \
      --profile "$PROFILE" \
      --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Rol creado exitosamente${NC}"
    else
        echo -e "${RED}❌ Error al crear el rol${NC}"
        rm -f "$TRUST_POLICY_FILE"
        exit 1
    fi
else
    echo -e "${PURPLE}🔧 Actualizando trust policy del rol existente${NC}"
    
    aws iam update-assume-role-policy \
      --role-name "$ROLE_NAME" \
      --policy-document "file://$TRUST_POLICY_FILE" \
      --profile "$PROFILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Trust policy actualizada exitosamente${NC}"
    else
        echo -e "${RED}❌ Error al actualizar trust policy${NC}"
        rm -f "$TRUST_POLICY_FILE"
        exit 1
    fi
fi

# Limpiar archivo temporal
rm -f "$TRUST_POLICY_FILE"
echo ""

# Adjuntar política administrada de AWS Support
echo -e "${PURPLE}🔗 Adjuntando política AWSSupportAccess${NC}"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AWSSupportAccess \
  --profile "$PROFILE" \
  --region "$REGION"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Política AWSSupportAccess adjuntada exitosamente${NC}"
else
    echo -e "${RED}❌ Error al adjuntar política AWSSupportAccess${NC}"
    exit 1
fi

# Opcional: Adjuntar política adicional para casos avanzados
echo ""
echo -e "${PURPLE}🔗 Adjuntando política adicional para Trusted Advisor${NC}"

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/job-function/SupportUser \
  --profile "$PROFILE" \
  --region "$REGION"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Política SupportUser adjuntada exitosamente${NC}"
else
    echo -e "${YELLOW}⚠️ Error al adjuntar política SupportUser (puede que ya esté adjuntada)${NC}"
fi

echo ""

# Verificar la configuración final
echo -e "${PURPLE}🔍 Verificando configuración final del rol${NC}"

# Obtener información del rol
ROLE_INFO=$(aws iam get-role \
    --role-name "$ROLE_NAME" \
    --profile "$PROFILE" \
    --query 'Role.{Arn:Arn,CreateDate:CreateDate,Description:Description}' \
    --output json)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}📊 Información del rol:${NC}"
    echo "$ROLE_INFO" | jq '.'
else
    echo -e "${RED}❌ Error al verificar información del rol${NC}"
fi

# Verificar políticas adjuntas
echo -e "${GREEN}📋 Políticas adjuntas:${NC}"
ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME" \
    --profile "$PROFILE" \
    --output table)

echo "$ATTACHED_POLICIES"

echo ""

# Crear script de verificación
VERIFICATION_SCRIPT="verify-support-role-$ROLE_NAME.sh"
cat > "$VERIFICATION_SCRIPT" << EOF
#!/bin/bash
# Script de verificación generado automáticamente
echo "=== Verificación del rol $ROLE_NAME ==="
echo "Perfil: $PROFILE"
echo "Cuenta: $ACCOUNT_ID"
echo ""

# Verificar rol
aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'Role.{RoleName:RoleName,Arn:Arn}' --output table

# Verificar políticas
echo ""
echo "Políticas adjuntas:"
aws iam list-attached-role-policies --role-name "$ROLE_NAME" --profile "$PROFILE" --output table

# Verificar trust policy
echo ""
echo "Trust Policy:"
aws iam get-role --role-name "$ROLE_NAME" --profile "$PROFILE" --query 'Role.AssumeRolePolicyDocument' --output json | jq '.'
EOF

chmod +x "$VERIFICATION_SCRIPT"
echo -e "${CYAN}📝 Script de verificación creado: ${GREEN}$VERIFICATION_SCRIPT${NC}"

echo ""
echo "=================================================================="
echo -e "${GREEN}🎉 ROL DE SOPORTE CREADO EXITOSAMENTE${NC}"
echo "=================================================================="
echo -e "✅ Rol: ${GREEN}$ROLE_NAME${NC}"
echo -e "✅ Perfil: ${GREEN}$PROFILE${NC}"
echo -e "✅ Cuenta: ${GREEN}$ACCOUNT_ID${NC}"
echo ""
echo -e "${BLUE}📋 Características del rol:${NC}"
echo -e "  • Permite acceso al servicio AWS Support"
echo -e "  • Permite acceso cross-account desde la misma cuenta"
echo -e "  • Políticas: AWSSupportAccess + SupportUser"
echo -e "  • Duración máxima de sesión: 1 hora"
echo ""
echo -e "${BLUE}🔧 Para verificar:${NC}"
echo -e "  ./$VERIFICATION_SCRIPT"
echo ""
echo -e "${BLUE}🔗 Para asumir el rol:${NC}"
echo -e "  aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME --role-session-name support-session --profile $PROFILE"
echo ""
echo -e "${BLUE}💡 Próximos pasos recomendados:${NC}"
echo -e "  1. Verificar que el rol funciona correctamente"
echo -e "  2. Documentar el procedimiento de uso"
echo -e "  3. Configurar usuarios autorizados para asumir el rol"
echo -e "  4. Establecer procedimientos de auditoría"
echo ""