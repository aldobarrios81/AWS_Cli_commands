#!/bin/bash
PROFILE="AZLOGICA"
echo "=== RESUMEN COMPLETO ACCESS KEYS - AZLOGICA ==="
echo "Account: 669153057384"
echo ""

TOTAL_USERS=0
USERS_WITH_MULTIPLE=0

for user in $(aws iam list-users --profile $PROFILE --query 'Users[].UserName' --output text); do
    TOTAL_USERS=$((TOTAL_USERS + 1))
    keys=$(aws iam list-access-keys --user-name "$user" --profile $PROFILE --query 'AccessKeyMetadata[?Status==`Active`].AccessKeyId' --output text 2>/dev/null | wc -w)
    
    if [ "$keys" -gt 1 ]; then
        USERS_WITH_MULTIPLE=$((USERS_WITH_MULTIPLE + 1))
        echo "❌ $user: $keys keys activas - NO CUMPLE"
    elif [ "$keys" -eq 1 ]; then
        echo "✅ $user: 1 key activa - CUMPLE"
    else
        echo "ℹ️  $user: 0 keys activas"
    fi
done

echo ""
echo "=== RESUMEN ==="
echo "Total usuarios: $TOTAL_USERS"
echo "Usuarios con múltiples keys: $USERS_WITH_MULTIPLE"
echo "Cumplimiento: $(( (TOTAL_USERS - USERS_WITH_MULTIPLE) * 100 / TOTAL_USERS ))%"
