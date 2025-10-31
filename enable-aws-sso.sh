#!/bin/bash
# ======================================================
# enable-aws-sso.sh
# Script para habilitar y configurar AWS SSO (IAM Identity Center)
# ======================================================

# Configuración
AWS_PROFILE="AZLOGICA"
AWS_REGION="us-east-1"
ACCOUNT_ID="669153057384"  # Account ID obtenido del análisis anterior

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔐 CONFIGURANDO AWS SSO (IAM Identity Center)${NC}"
echo "=================================================================="
echo "Perfil: $AWS_PROFILE | Región: $AWS_REGION | Account: $ACCOUNT_ID"
echo ""

# Función para verificar si AWS CLI está instalado
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        echo -e "${RED}❌ AWS CLI no está instalado. Por favor instálalo primero.${NC}"
        exit 1
    fi
    
    AWS_CLI_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    echo -e "${GREEN}✅ AWS CLI versión: $AWS_CLI_VERSION${NC}"
}

# Función para verificar credenciales actuales
check_current_credentials() {
    echo -e "${BLUE}🔍 Verificando credenciales actuales...${NC}"
    
    CURRENT_ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$CURRENT_ACCOUNT" ]; then
        echo -e "${GREEN}✅ Credenciales actuales válidas para Account: $CURRENT_ACCOUNT${NC}"
        
        # Verificar si ya está usando SSO
        SSO_CONFIG=$(aws configure get sso_start_url --profile "$AWS_PROFILE" 2>/dev/null)
        if [ ! -z "$SSO_CONFIG" ]; then
            echo -e "${YELLOW}⚠️ El perfil ya tiene configuración SSO: $SSO_CONFIG${NC}"
            echo -e "${BLUE}¿Deseas reconfigurar? (y/N)${NC}"
            read -r RECONFIGURE
            if [[ ! $RECONFIGURE =~ ^[Yy]$ ]]; then
                echo -e "${BLUE}Manteniendo configuración existente${NC}"
                return 0
            fi
        fi
    else
        echo -e "${YELLOW}⚠️ No hay credenciales válidas o perfil no configurado${NC}"
    fi
}

# Función para habilitar SSO en la cuenta
enable_sso_instance() {
    echo -e "${BLUE}🚀 Habilitando IAM Identity Center (SSO)...${NC}"
    
    # Verificar si SSO ya está habilitado
    SSO_INSTANCE=$(aws sso-admin list-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" --query 'Instances[0].InstanceArn' --output text 2>/dev/null)
    
    if [ "$SSO_INSTANCE" != "None" ] && [ ! -z "$SSO_INSTANCE" ]; then
        echo -e "${GREEN}✅ IAM Identity Center ya está habilitado${NC}"
        echo -e "${BLUE}Instance ARN: $SSO_INSTANCE${NC}"
        
        # Obtener Identity Store ID
        IDENTITY_STORE_ID=$(aws sso-admin list-instances --profile "$AWS_PROFILE" --region "$AWS_REGION" --query 'Instances[0].IdentityStoreId' --output text 2>/dev/null)
        echo -e "${BLUE}Identity Store ID: $IDENTITY_STORE_ID${NC}"
        
        return 0
    else
        echo -e "${YELLOW}⚠️ IAM Identity Center no está habilitado${NC}"
        echo -e "${BLUE}Habilitando IAM Identity Center...${NC}"
        
        # Crear instancia de SSO
        CREATE_RESULT=$(aws sso-admin create-instance --profile "$AWS_PROFILE" --region "$AWS_REGION" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ IAM Identity Center habilitado exitosamente${NC}"
            SSO_INSTANCE=$(echo "$CREATE_RESULT" | jq -r '.InstanceArn')
            echo -e "${BLUE}Instance ARN: $SSO_INSTANCE${NC}"
        else
            echo -e "${RED}❌ Error al habilitar IAM Identity Center${NC}"
            echo -e "${YELLOW}Nota: Es posible que necesites habilitarlo desde la consola web primero${NC}"
            return 1
        fi
    fi
}

# Función para configurar el perfil SSO
configure_sso_profile() {
    echo -e "${BLUE}⚙️ Configurando perfil SSO...${NC}"
    
    # Solicitar URL de SSO si no está configurada
    CURRENT_SSO_URL=$(aws configure get sso_start_url --profile "$AWS_PROFILE" 2>/dev/null)
    
    if [ -z "$CURRENT_SSO_URL" ]; then
        echo -e "${YELLOW}📝 Ingresa la URL de SSO start (ejemplo: https://d-xxxxxxxxxx.awsapps.com/start):${NC}"
        read -r SSO_START_URL
        
        if [ -z "$SSO_START_URL" ]; then
            echo -e "${RED}❌ URL de SSO requerida${NC}"
            return 1
        fi
    else
        SSO_START_URL="$CURRENT_SSO_URL"
        echo -e "${BLUE}Usando URL existente: $SSO_START_URL${NC}"
    fi
    
    # Configurar el perfil
    echo -e "${BLUE}🔧 Configurando perfil $AWS_PROFILE...${NC}"
    
    aws configure set sso_start_url "$SSO_START_URL" --profile "$AWS_PROFILE"
    aws configure set sso_region "$AWS_REGION" --profile "$AWS_PROFILE"
    aws configure set sso_account_id "$ACCOUNT_ID" --profile "$AWS_PROFILE"
    aws configure set sso_role_name "AdministratorAccess" --profile "$AWS_PROFILE"
    aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE"
    aws configure set output "json" --profile "$AWS_PROFILE"
    
    echo -e "${GREEN}✅ Perfil SSO configurado${NC}"
}

# Función para iniciar sesión con SSO
sso_login() {
    echo -e "${BLUE}🔑 Iniciando sesión con SSO...${NC}"
    
    aws sso login --profile "$AWS_PROFILE"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Inicio de sesión SSO exitoso${NC}"
        
        # Verificar credenciales después del login
        VERIFIED_ACCOUNT=$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query 'Account' --output text 2>/dev/null)
        if [ "$VERIFIED_ACCOUNT" = "$ACCOUNT_ID" ]; then
            echo -e "${GREEN}✅ Credenciales verificadas para Account: $VERIFIED_ACCOUNT${NC}"
        else
            echo -e "${YELLOW}⚠️ Account verificado: $VERIFIED_ACCOUNT (esperado: $ACCOUNT_ID)${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}❌ Error en el inicio de sesión SSO${NC}"
        return 1
    fi
}

# Función para mostrar el resumen de configuración
show_summary() {
    echo ""
    echo "=================================================================="
    echo -e "${GREEN}📋 RESUMEN DE CONFIGURACIÓN SSO${NC}"
    echo "=================================================================="
    echo -e "${BLUE}Perfil:${NC} $AWS_PROFILE"
    echo -e "${BLUE}Región:${NC} $AWS_REGION"
    echo -e "${BLUE}Account ID:${NC} $ACCOUNT_ID"
    
    SSO_URL=$(aws configure get sso_start_url --profile "$AWS_PROFILE" 2>/dev/null)
    SSO_ROLE=$(aws configure get sso_role_name --profile "$AWS_PROFILE" 2>/dev/null)
    
    echo -e "${BLUE}SSO Start URL:${NC} $SSO_URL"
    echo -e "${BLUE}SSO Role:${NC} $SSO_ROLE"
    echo ""
    echo -e "${YELLOW}🔔 PRÓXIMOS PASOS:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "1. Para usar este perfil en otros comandos:"
    echo "   aws [comando] --profile $AWS_PROFILE"
    echo ""
    echo "2. Para renovar credenciales cuando expiren:"
    echo "   aws sso login --profile $AWS_PROFILE"
    echo ""
    echo "3. Para configurar como perfil por defecto:"
    echo "   export AWS_PROFILE=$AWS_PROFILE"
    echo ""
    echo "4. Verificar configuración:"
    echo "   aws sts get-caller-identity --profile $AWS_PROFILE"
    echo ""
}

# Función principal
main() {
    check_aws_cli
    check_current_credentials
    enable_sso_instance
    configure_sso_profile
    sso_login
    
    if [ $? -eq 0 ]; then
        show_summary
        echo -e "${GREEN}🎉 AWS SSO configurado exitosamente para el perfil $AWS_PROFILE${NC}"
    else
        echo -e "${RED}❌ Error en la configuración de AWS SSO${NC}"
        exit 1
    fi
}

# Ejecutar función principal
main

