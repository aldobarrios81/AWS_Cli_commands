#!/bin/bash
# ======================================================
# enable-aws-sso.sh
# Script para habilitar AWS SSO con perfil y región fijos
# ======================================================

# Nombre del perfil
AWS_PROFILE="azcenit"
# Región por defecto
AWS_REGION="us-east-1"

echo "=== Habilitando AWS SSO con perfil: $AWS_PROFILE en región: $AWS_REGION ==="

# Configura el perfil en AWS CLI
aws configure set sso_start_url "https://<tu-sso-domain>.awsapps.com/start" --profile $AWS_PROFILE
aws configure set sso_region $AWS_REGION --profile $AWS_PROFILE
aws configure set region $AWS_REGION --profile $AWS_PROFILE
aws configure set output json --profile $AWS_PROFILE

echo "Configuración guardada. Ahora inicia sesión con SSO..."

# Inicia sesión con SSO
aws sso login --profile $AWS_PROFILE

if [ $? -eq 0 ]; then
    echo "✅ Inicio de sesión con SSO exitoso para el perfil $AWS_PROFILE"
else
    echo "❌ Error en el inicio de sesión con SSO"
    exit 1
fi

