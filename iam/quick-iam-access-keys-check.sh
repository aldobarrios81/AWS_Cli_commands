#!/bin/bash
# quick-iam-access-keys-check.sh
# Verificación rápida de access keys IAM para múltiples keys activas

PROFILE="metrokia"

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

# Para cada usuario, verificar access keys
aws iam list-users --profile "$PROFILE" --query 'Users[].UserName' --output text | while read username; do
    if [ -n "$username" ]; then
        TOTAL_USERS=$((TOTAL_USERS + 1))
        echo "Usuario: $username"
        
        # Obtener access keys activas
        ACTIVE_KEYS=$(aws iam list-access-keys --user-name "$username" --profile "$PROFILE" --query 'AccessKeyMetadata[?Status==`Active`].[AccessKeyId,Status,CreateDate]' --output table 2>/dev/null)
        
        # Contar keys activas
        ACTIVE_COUNT=$(aws iam list-access-keys --user-name "$username" --profile "$PROFILE" --query 'AccessKeyMetadata[?Status==`Active`].AccessKeyId' --output text 2>/dev/null | wc -w)
        
        if [ "$ACTIVE_COUNT" -eq 0 ]; then
            echo "  ℹ️ Sin access keys activas"
        elif [ "$ACTIVE_COUNT" -eq 1 ]; then
            echo "  ✅ UNA access key activa (CUMPLE)"
            echo "$ACTIVE_KEYS" | grep -v "AccessKeyId" | grep -v "^$"
        else
            echo "  ❌ MÚLTIPLES access keys activas: $ACTIVE_COUNT (NO CUMPLE)"
            echo "$ACTIVE_KEYS" | grep -v "AccessKeyId" | grep -v "^$"
            USERS_WITH_MULTIPLE_KEYS=$((USERS_WITH_MULTIPLE_KEYS + 1))
            
            # Mostrar comando de corrección
            FIRST_KEY=$(aws iam list-access-keys --user-name "$username" --profile "$PROFILE" --query 'AccessKeyMetadata[?Status==`Active`].AccessKeyId' --output text | awk '{print $1}')
            echo "  💡 Para desactivar una key:"
            echo "     aws iam update-access-key --user-name $username --access-key-id $FIRST_KEY --status Inactive --profile $PROFILE"
        fi
        
        # Verificar MFA
        MFA_COUNT=$(aws iam list-mfa-devices --user-name "$username" --profile "$PROFILE" --query 'MFADevices' --output text 2>/dev/null | wc -w)
        if [ "$MFA_COUNT" -gt 0 ]; then
            echo "  ✅ MFA habilitado"
        else
            echo "  ⚠️ MFA no habilitado"
        fi
        
        echo ""
    fi
done

echo "=== RESUMEN ==="
echo "Total usuarios: $TOTAL_USERS"
echo "Usuarios con múltiples keys: $USERS_WITH_MULTIPLE_KEYS"

if [ "$USERS_WITH_MULTIPLE_KEYS" -eq 0 ]; then
    echo "✅ ESTADO: COMPLIANT - Ningún usuario tiene múltiples access keys"
else
    echo "❌ ESTADO: NO COMPLIANT - $USERS_WITH_MULTIPLE_KEYS usuario(s) requieren atención"
fi