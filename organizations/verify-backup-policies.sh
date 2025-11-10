#!/bin/bash
# verify-backup-policies.sh
# Verifica políticas de respaldo a nivel de AWS Organizations

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
    exit 1
fi

PROFILE="$1"
REGION="us-east-1"

echo "=================================================================="
echo "🏢 VERIFICACIÓN AWS ORGANIZATIONS BACKUP POLICIES"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo "Verificando políticas de respaldo a nivel de organización"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo "❌ Error: Credenciales no válidas para perfil '$PROFILE'"
    exit 1
fi

echo "✅ Account ID: $ACCOUNT_ID"
echo ""

# Verificar si la cuenta es parte de una organización
echo "🔍 Verificando membresía en AWS Organizations..."

ORG_INFO=$(aws organizations describe-organization --profile "$PROFILE" --query '[Id,MasterAccountId,FeatureSet]' --output text 2>/dev/null)
exit_code=$?

if [ $exit_code -eq 0 ] && [ -n "$ORG_INFO" ]; then
    IFS=$'\t' read -r ORG_ID MASTER_ACCOUNT FEATURE_SET <<< "$ORG_INFO"
    echo "✅ Cuenta es parte de una organización"
    echo "   🏢 Organization ID: $ORG_ID"
    echo "   👑 Master Account: $MASTER_ACCOUNT"
    echo "   🎯 Feature Set: $FEATURE_SET"
    
    # Verificar si es la cuenta master
    if [ "$ACCOUNT_ID" = "$MASTER_ACCOUNT" ]; then
        echo "   ⭐ Esta es la cuenta MASTER de la organización"
        IS_MASTER=true
    else
        echo "   📋 Esta es una cuenta MIEMBRO de la organización"
        IS_MASTER=false
    fi
else
    echo "⚠️ La cuenta no es parte de una organización AWS"
    echo "💡 Para implementar políticas de backup a nivel organizacional, primero debe configurar AWS Organizations"
    echo ""
    echo "🔧 Comandos sugeridos:"
    echo "1. Crear organización: aws organizations create-organization --profile $PROFILE"
    echo "2. Habilitar servicios confiables para backup"
    exit 0
fi

echo ""

# Verificar servicios habilitados en la organización
echo "🔧 Verificando servicios habilitados..."

if [ "$IS_MASTER" = true ]; then
    # Verificar si AWS Backup está habilitado como servicio confiable
    ENABLED_SERVICES=$(aws organizations list-aws-service-access-for-organization --profile "$PROFILE" --query 'EnabledServicePrincipals[].ServicePrincipal' --output text 2>/dev/null)
    
    if [[ "$ENABLED_SERVICES" =~ "backup.amazonaws.com" ]]; then
        echo "   ✅ AWS Backup habilitado como servicio confiable"
        BACKUP_SERVICE_ENABLED=true
    else
        echo "   ❌ AWS Backup NO está habilitado como servicio confiable"
        BACKUP_SERVICE_ENABLED=false
    fi
    
    if [[ "$ENABLED_SERVICES" =~ "config.amazonaws.com" ]]; then
        echo "   ✅ AWS Config habilitado como servicio confiable"
    else
        echo "   ⚠️ AWS Config no está habilitado (recomendado para compliance)"
    fi
else
    echo "   ℹ️ Como cuenta miembro, no se pueden verificar servicios de la organización"
    BACKUP_SERVICE_ENABLED="unknown"
fi

echo ""

# Verificar backup plans organizacionales
echo "🔄 Verificando configuración AWS Backup organizacional..."

BACKUP_PLANS=$(aws backup list-backup-plans --profile "$PROFILE" --region "$REGION" --query 'BackupPlansList[].{Name:BackupPlanName,Id:BackupPlanId}' --output json 2>/dev/null)

if [ $? -eq 0 ] && [ "$BACKUP_PLANS" != "[]" ]; then
    PLAN_COUNT=$(echo "$BACKUP_PLANS" | jq length)
    echo "   📋 $PLAN_COUNT backup plans configurados"
    
    echo "$BACKUP_PLANS" | jq -r '.[] | "      • \(.Name) (ID: \(.Id))"'
else
    echo "   ❌ No se encontraron backup plans configurados"
fi

echo ""

# Resumen final
echo "=================================================================="
echo "📊 RESUMEN: AWS ORGANIZATIONS BACKUP POLICIES - METROKIA"
echo "=================================================================="

if [ $exit_code -eq 0 ]; then
    echo "🌐 Estado: MIEMBRO DE ORGANIZACIÓN"
    
    if [ "$IS_MASTER" = true ]; then
        echo "👑 Tipo: CUENTA MASTER"
        
        if [ "$BACKUP_SERVICE_ENABLED" = true ]; then
            echo "🔄 Backup organizacional: HABILITADO"
        else
            echo "🔄 Backup organizacional: NO HABILITADO"
        fi
    else
        echo "📋 Tipo: CUENTA MIEMBRO"
    fi
else
    echo "🌐 Estado: NO ES MIEMBRO DE ORGANIZACIÓN"
fi

echo ""
echo "💡 PRÓXIMOS PASOS:"

if [ $exit_code -ne 0 ]; then
    echo "1. Configurar AWS Organizations"
    echo "2. Habilitar servicios de backup"
elif [ "$BACKUP_SERVICE_ENABLED" != "true" ] && [ "$IS_MASTER" = true ]; then
    echo "1. Habilitar AWS Backup como servicio confiable"
    echo "2. Configurar políticas de backup organizacionales"
else
    echo "1. Verificar cobertura de backup en cuentas"
    echo "2. Implementar monitoreo de compliance"
fi

echo ""
echo "🎯 Verificación completada"
