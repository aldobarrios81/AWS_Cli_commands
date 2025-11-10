#!/bin/bash
# quick-iam-access-keys-check-azlogica.sh
# Verificación rápida de access keys IAM para el perfil AZLOGICA

PROFILE="AZLOGICA"

echo "=== VERIFICACIÓN RÁPIDA IAM ACCESS KEYS - PERFIL $PROFILE ==="
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Listar usuarios IAM
echo "Usuarios IAM encontrados:"
aws iam list-users --profile "$PROFILE" --query 'Users[].[UserName,CreateDate]' --output table

echo ""
echo "=== Análisis de Access Keys por Usuario ==="

USERS_WITH_MULTIPLE_KEYS=0
TOTAL_USERS=0
TOTAL_ACTIVE_KEYS=0

# Obtener lista de usuarios
USERS_LIST=$(aws iam list-users --profile "$PROFILE" --query 'Users[].UserName' --output text)

for username in $USERS_LIST; do
    if [ -n "$username" ]; then
        TOTAL_USERS=$((TOTAL_USERS + 1))
        echo "👤 Usuario: $username"
        
        # Obtener access keys activas
        ACTIVE_KEYS_LIST=$(aws iam list-access-keys --user-name "$username" --profile "$PROFILE" --query 'AccessKeyMetadata[?Status==`Active`].[AccessKeyId,CreateDate]' --output text 2>/dev/null)
        
        # Contar keys activas
        ACTIVE_COUNT=$(echo "$ACTIVE_KEYS_LIST" | grep -v "^$" | wc -l)
        TOTAL_ACTIVE_KEYS=$((TOTAL_ACTIVE_KEYS + ACTIVE_COUNT))
        
        if [ "$ACTIVE_COUNT" -eq 0 ]; then
            echo "  ℹ️  Sin access keys activas"
        elif [ "$ACTIVE_COUNT" -eq 1 ]; then
            echo "  ✅ UNA access key activa (CUMPLE)"
            echo "  🔑 Key activa:"
            echo "$ACTIVE_KEYS_LIST" | while read keyid createdate; do
                if [ -n "$keyid" ]; then
                    KEY_AGE_DAYS=$(( ($(date +%s) - $(date -d "${createdate%T*}" +%s)) / 86400 ))
                    echo "     - $keyid (${KEY_AGE_DAYS} días)"
                fi
            done
        else
            echo "  ❌ MÚLTIPLES access keys activas: $ACTIVE_COUNT (NO CUMPLE)"
            USERS_WITH_MULTIPLE_KEYS=$((USERS_WITH_MULTIPLE_KEYS + 1))
            echo "  🔑 Keys activas:"
            echo "$ACTIVE_KEYS_LIST" | while read keyid createdate; do
                if [ -n "$keyid" ]; then
                    KEY_AGE_DAYS=$(( ($(date +%s) - $(date -d "${createdate%T*}" +%s)) / 86400 ))
                    echo "     - $keyid (${KEY_AGE_DAYS} días)"
                fi
            done
            
            # Mostrar comando de corrección para la primera key
            FIRST_KEY=$(echo "$ACTIVE_KEYS_LIST" | head -1 | awk '{print $1}')
            echo "  💡 Para desactivar una key:"
            echo "     aws iam update-access-key --user-name $username --access-key-id $FIRST_KEY --status Inactive --profile $PROFILE"
        fi
        
        # Verificar MFA
        MFA_DEVICES=$(aws iam list-mfa-devices --user-name "$username" --profile "$PROFILE" --query 'MFADevices[].SerialNumber' --output text 2>/dev/null)
        if [ -n "$MFA_DEVICES" ] && [ "$MFA_DEVICES" != "None" ]; then
            echo "  ✅ MFA habilitado"
        else
            echo "  ⚠️  MFA no habilitado"
        fi
        
        # Verificar último acceso
        LAST_ACTIVITY=$(aws iam get-user --user-name "$username" --profile "$PROFILE" --query 'User.PasswordLastUsed' --output text 2>/dev/null)
        if [ -n "$LAST_ACTIVITY" ] && [ "$LAST_ACTIVITY" != "None" ]; then
            LAST_DAYS=$(( ($(date +%s) - $(date -d "${LAST_ACTIVITY%T*}" +%s)) / 86400 ))
            echo "  📅 Último uso password: ${LAST_DAYS} días atrás"
        else
            echo "  📅 Password nunca usado o no disponible"
        fi
        
        echo ""
    fi
done

echo "=== RESUMEN EJECUTIVO ==="
echo "🔐 Account ID: $ACCOUNT_ID"
echo "👥 Total usuarios: $TOTAL_USERS"
echo "🔑 Total access keys activas: $TOTAL_ACTIVE_KEYS" 
echo "❌ Usuarios con múltiples keys: $USERS_WITH_MULTIPLE_KEYS"

# Calcular porcentaje de cumplimiento
if [ "$TOTAL_USERS" -gt 0 ]; then
    COMPLIANT_USERS=$((TOTAL_USERS - USERS_WITH_MULTIPLE_KEYS))
    COMPLIANCE_PERCENT=$((COMPLIANT_USERS * 100 / TOTAL_USERS))
    echo "📈 Cumplimiento: $COMPLIANCE_PERCENT%"
fi

echo ""

if [ "$USERS_WITH_MULTIPLE_KEYS" -eq 0 ]; then
    echo "✅ ESTADO: COMPLIANT"
    echo "💡 Ningún usuario tiene múltiples access keys activas"
else
    echo "❌ ESTADO: NO COMPLIANT"
    echo "💡 $USERS_WITH_MULTIPLE_KEYS usuario(s) requieren corrección"
    echo ""
    echo "🔧 ACCIONES REQUERIDAS:"
    echo "  1. Desactivar access keys adicionales"
    echo "  2. Verificar que las aplicaciones funcionen con una sola key"
    echo "  3. Eliminar keys inactivas después de confirmar que no se usan"
fi

echo ""
echo "📋 Reporte generado: $(date)"