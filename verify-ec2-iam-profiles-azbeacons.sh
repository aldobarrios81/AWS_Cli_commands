#!/bin/bash
# Script de verificación rápida para perfiles IAM en EC2

PROFILE="$1"
REGION="us-east-1"

if [ -z "$PROFILE" ]; then
    echo "Uso: $0 [perfil]"
    exit 1
fi

echo "=== Verificación IAM Instance Profiles - $PROFILE ==="

# Instancias sin perfil
echo "Instancias SIN perfil IAM:"
aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[?!IamInstanceProfile].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
    --output table

echo ""

# Instancias con perfil
echo "Instancias CON perfil IAM:"
aws ec2 describe-instances --profile "$PROFILE" --region "$REGION" \
    --filters "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[].Instances[?IamInstanceProfile].[InstanceId,State.Name,IamInstanceProfile.Arn,Tags[?Key==`Name`].Value|[0]]' \
    --output table
