#!/bin/bash
# quick-mfa-check.sh
# Verificación rápida de MFA para usuarios IAM

PROFILE="$1"

if [ -z "$PROFILE" ]; then
    echo "Uso: $0 [perfil]"
    exit 1
fi

echo "=== VERIFICACIÓN RÁPIDA MFA - PERFIL $PROFILE ==="
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Contadores
TOTAL_USERS=0
WITH_MFA=0
WITHOUT_MFA=0
HARDWARE_MFA=0
VIRTUAL_MFA=0

echo "=== Análisis de MFA por Usuario ==="

# Obtener lista de usuarios
USERS_LIST=$(aws iam list-users --profile "$PROFILE" --query 'Users[].UserName' --output text)

for username in $USERS_LIST; do
    if [ -n "$username" ]; then
        TOTAL_USERS=$((TOTAL_USERS + 1))
        echo "👤 Usuario: $username"
        
        # Verificar MFA
        MFA_DEVICES=$(aws iam list-mfa-devices --user-name "$username" --profile "$PROFILE" --query 'MFADevices[].[SerialNumber]' --output text 2>/dev/null)
        
        if [ -n "$MFA_DEVICES" ] && [ "$MFA_DEVICES" != "None" ]; then
            WITH_MFA=$((WITH_MFA + 1))
            echo "  ✅ MFA: HABILITADO"
            
            # Identificar tipo de MFA
            while read -r serial; do
                if [ -n "$serial" ]; then
                    if [[ "$serial" == arn:aws:iam::*:mfa/* ]]; then
                        echo "  📱 Tipo: Virtual MFA"
                        VIRTUAL_MFA=$((VIRTUAL_MFA + 1))
                    elif [[ "$serial" =~ ^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]] || [[ "$serial" =~ ^GA[HK]T[0-9]{8}$ ]]; then
                        echo "  🔐 Tipo: Hardware MFA"
                        HARDWARE_MFA=$((HARDWARE_MFA + 1))
                    else
                        echo "  🔒 Tipo: $serial"
                    fi
                fi
            done <<< "$MFA_DEVICES"
        else
            WITHOUT_MFA=$((WITHOUT_MFA + 1))
            echo "  ❌ MFA: NO HABILITADO"
        fi
        echo ""
    fi
done

echo "=== RESUMEN EJECUTIVO ==="
echo "🔐 Account: $ACCOUNT_ID"
echo "👥 Total usuarios: $TOTAL_USERS"
echo "✅ Con MFA: $WITH_MFA"
echo "❌ Sin MFA: $WITHOUT_MFA"
echo "🔐 Hardware MFA: $HARDWARE_MFA"
echo "📱 Virtual MFA: $VIRTUAL_MFA"

# Calcular porcentajes
if [ "$TOTAL_USERS" -gt 0 ]; then
    MFA_PERCENT=$(( WITH_MFA * 100 / TOTAL_USERS ))
    HARDWARE_PERCENT=$(( HARDWARE_MFA * 100 / TOTAL_USERS ))
    echo "📈 Cumplimiento MFA: $MFA_PERCENT%"
    echo "📈 Hardware MFA: $HARDWARE_PERCENT%"
fi

echo ""

# Estado final
if [ "$WITHOUT_MFA" -eq 0 ] && [ "$HARDWARE_MFA" -eq "$WITH_MFA" ]; then
    echo "🎉 ESTADO: ÓPTIMO - 100% Hardware MFA"
elif [ "$WITHOUT_MFA" -eq 0 ]; then
    echo "✅ ESTADO: BUENO - MFA completo, migrar a Hardware"
else
    echo "⚠️ ESTADO: REQUIERE ATENCIÓN - $WITHOUT_MFA usuarios sin MFA"
fi