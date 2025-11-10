#!/bin/bash
# verify-iam-access-keys.sh
# Verificar que los usuarios IAM no tengan más de una clave de acceso activa
# Análisis de seguridad para cumplimiento de mejores prácticas

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia"
    exit 1
fi

# Configuración del perfil
PROFILE="$1"
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
echo -e "${BLUE}🔑 VERIFICACIÓN IAM ACCESS KEYS${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo ""

# Verificar credenciales
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: Credenciales no válidas para perfil '$PROFILE'${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Variables de conteo
TOTAL_USERS=0
USERS_WITH_KEYS=0
USERS_WITH_SINGLE_KEY=0
USERS_WITH_MULTIPLE_KEYS=0
USERS_WITHOUT_KEYS=0
TOTAL_ACTIVE_KEYS=0
TOTAL_INACTIVE_KEYS=0

echo -e "${PURPLE}=== Análisis de Access Keys IAM ===${NC}"

# Obtener lista de usuarios IAM
IAM_USERS=$(aws iam list-users \
    --profile "$PROFILE" \
    --query 'Users[].[UserName,CreateDate,PasswordLastUsed]' \
    --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener usuarios IAM${NC}"
    exit 1
elif [ -z "$IAM_USERS" ] || [ "$IAM_USERS" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron usuarios IAM${NC}"
    TOTAL_USERS=0
else
    echo -e "${GREEN}📊 Usuarios IAM encontrados:${NC}"
    echo ""
    
    while IFS=$'\t' read -r username created_date password_last_used; do
        if [ -n "$username" ] && [ "$username" != "None" ]; then
            TOTAL_USERS=$((TOTAL_USERS + 1))
            
            echo -e "${CYAN}👤 Usuario: $username${NC}"
            echo -e "   📅 Creado: ${BLUE}$(echo "$created_date" | cut -d'T' -f1)${NC}"
            
            # Verificar última vez que se usó password
            if [ -n "$password_last_used" ] && [ "$password_last_used" != "None" ]; then
                echo -e "   🔒 Último uso password: ${BLUE}$(echo "$password_last_used" | cut -d'T' -f1)${NC}"
            else
                echo -e "   🔒 Último uso password: ${YELLOW}Nunca / Sin password${NC}"
            fi
            
            # Obtener access keys del usuario
            ACCESS_KEYS=$(aws iam list-access-keys \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'AccessKeyMetadata[].[AccessKeyId,Status,CreateDate]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$ACCESS_KEYS" ] && [ "$ACCESS_KEYS" != "None" ]; then
                USERS_WITH_KEYS=$((USERS_WITH_KEYS + 1))
                
                # Contar keys activas e inactivas
                ACTIVE_KEYS=0
                INACTIVE_KEYS=0
                
                echo -e "   🔑 Access Keys:"
                
                while IFS=$'\t' read -r key_id status create_date; do
                    if [ -n "$key_id" ]; then
                        KEY_AGE_DAYS=$(( ($(date +%s) - $(date -d "${create_date%T*}" +%s)) / 86400 ))
                        
                        if [ "$status" == "Active" ]; then
                            ACTIVE_KEYS=$((ACTIVE_KEYS + 1))
                            TOTAL_ACTIVE_KEYS=$((TOTAL_ACTIVE_KEYS + 1))
                            
                            # Verificar si la key es muy antigua (más de 90 días)
                            if [ $KEY_AGE_DAYS -gt 90 ]; then
                                echo -e "      ⚠️  ${key_id} - ${GREEN}ACTIVA${NC} (${YELLOW}${KEY_AGE_DAYS} días${NC})"
                            else
                                echo -e "      ✅ ${key_id} - ${GREEN}ACTIVA${NC} (${KEY_AGE_DAYS} días)"
                            fi
                            
                            # Verificar último uso (requiere permisos adicionales)
                            LAST_USED=$(aws iam get-access-key-last-used \
                                --access-key-id "$key_id" \
                                --profile "$PROFILE" \
                                --query 'AccessKeyLastUsed.LastUsedDate' \
                                --output text 2>/dev/null)
                            
                            if [ $? -eq 0 ] && [ -n "$LAST_USED" ] && [ "$LAST_USED" != "None" ]; then
                                LAST_USED_DAYS=$(( ($(date +%s) - $(date -d "${LAST_USED%T*}" +%s)) / 86400 ))
                                if [ $LAST_USED_DAYS -gt 90 ]; then
                                    echo -e "         📅 Último uso: ${YELLOW}${LAST_USED_DAYS} días atrás${NC}"
                                else
                                    echo -e "         📅 Último uso: ${BLUE}${LAST_USED_DAYS} días atrás${NC}"
                                fi
                            else
                                echo -e "         📅 Último uso: ${YELLOW}No disponible${NC}"
                            fi
                        else
                            INACTIVE_KEYS=$((INACTIVE_KEYS + 1))
                            TOTAL_INACTIVE_KEYS=$((TOTAL_INACTIVE_KEYS + 1))
                            echo -e "      ❌ ${key_id} - ${RED}INACTIVA${NC} (${KEY_AGE_DAYS} días)"
                        fi
                    fi
                done <<< "$ACCESS_KEYS"
                
                # Evaluación de seguridad por usuario
                if [ $ACTIVE_KEYS -eq 0 ]; then
                    echo -e "   ℹ️  Estado: ${BLUE}Sin keys activas${NC}"
                elif [ $ACTIVE_KEYS -eq 1 ]; then
                    echo -e "   ✅ Estado: ${GREEN}UNA key activa (CUMPLE)${NC}"
                    USERS_WITH_SINGLE_KEY=$((USERS_WITH_SINGLE_KEY + 1))
                else
                    echo -e "   ❌ Estado: ${RED}MÚLTIPLES keys activas (${ACTIVE_KEYS}) - NO CUMPLE${NC}"
                    echo -e "   💡 Acción requerida: ${YELLOW}Desactivar $((ACTIVE_KEYS - 1)) key(s)${NC}"
                    USERS_WITH_MULTIPLE_KEYS=$((USERS_WITH_MULTIPLE_KEYS + 1))
                fi
                
            else
                echo -e "   ℹ️  Access Keys: ${BLUE}Ninguna${NC}"
                USERS_WITHOUT_KEYS=$((USERS_WITHOUT_KEYS + 1))
            fi
            
            # Verificar MFA habilitado
            MFA_DEVICES=$(aws iam list-mfa-devices \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'MFADevices[].SerialNumber' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$MFA_DEVICES" ] && [ "$MFA_DEVICES" != "None" ]; then
                echo -e "   ✅ MFA: ${GREEN}HABILITADO${NC}"
            else
                echo -e "   ⚠️  MFA: ${YELLOW}DESHABILITADO${NC}"
            fi
            
            # Verificar grupos del usuario
            USER_GROUPS=$(aws iam get-groups-for-user \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'Groups[].GroupName' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$USER_GROUPS" ] && [ "$USER_GROUPS" != "None" ]; then
                GROUP_COUNT=$(echo "$USER_GROUPS" | wc -w)
                echo -e "   👥 Grupos: ${BLUE}$GROUP_COUNT grupo(s)${NC}"
            else
                echo -e "   👥 Grupos: ${YELLOW}Ninguno${NC}"
            fi
            
            # Verificar políticas directas
            USER_POLICIES=$(aws iam list-attached-user-policies \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'AttachedPolicies[].PolicyName' \
                --output text 2>/dev/null)
            
            INLINE_POLICIES=$(aws iam list-user-policies \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'PolicyNames' \
                --output text 2>/dev/null)
            
            TOTAL_POLICIES=0
            if [ -n "$USER_POLICIES" ] && [ "$USER_POLICIES" != "None" ]; then
                TOTAL_POLICIES=$((TOTAL_POLICIES + $(echo "$USER_POLICIES" | wc -w)))
            fi
            if [ -n "$INLINE_POLICIES" ] && [ "$INLINE_POLICIES" != "None" ] && [ "$INLINE_POLICIES" != "[]" ]; then
                TOTAL_POLICIES=$((TOTAL_POLICIES + $(echo "$INLINE_POLICIES" | wc -w)))
            fi
            
            if [ $TOTAL_POLICIES -gt 0 ]; then
                echo -e "   📋 Políticas directas: ${BLUE}$TOTAL_POLICIES${NC}"
            else
                echo -e "   📋 Políticas directas: ${GREEN}Ninguna (buena práctica)${NC}"
            fi
            
            echo ""
        fi
    done <<< "$IAM_USERS"
fi

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="iam-access-keys-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "total_users": $TOTAL_USERS,
    "users_with_keys": $USERS_WITH_KEYS,
    "users_without_keys": $USERS_WITHOUT_KEYS,
    "users_with_single_key": $USERS_WITH_SINGLE_KEY,
    "users_with_multiple_keys": $USERS_WITH_MULTIPLE_KEYS,
    "total_active_keys": $TOTAL_ACTIVE_KEYS,
    "total_inactive_keys": $TOTAL_INACTIVE_KEYS,
    "compliance_status": "$(if [ $USERS_WITH_MULTIPLE_KEYS -eq 0 ]; then echo "COMPLIANT"; else echo "NON_COMPLIANT"; fi)"
  },
  "security_recommendations": [
    "Desactivar access keys adicionales para usuarios con múltiples keys",
    "Rotar access keys regularmente (cada 90 días)",
    "Habilitar MFA para todos los usuarios",
    "Usar roles IAM en lugar de access keys cuando sea posible",
    "Monitorear uso de access keys regularmente",
    "Eliminar access keys inactivas antiguas",
    "Implementar políticas de rotación automática"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ $USERS_WITH_MULTIPLE_KEYS -gt 0 ]; then
    echo ""
    echo -e "${PURPLE}=== Usuarios que requieren atención ===${NC}"
    
    # Volver a procesar para mostrar solo los problemáticos
    while IFS=$'\t' read -r username created_date password_last_used; do
        if [ -n "$username" ] && [ "$username" != "None" ]; then
            ACCESS_KEYS=$(aws iam list-access-keys \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'AccessKeyMetadata[?Status==`Active`].AccessKeyId' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$ACCESS_KEYS" ]; then
                ACTIVE_COUNT=$(echo "$ACCESS_KEYS" | wc -w)
                if [ $ACTIVE_COUNT -gt 1 ]; then
                    echo -e "${YELLOW}⚠️  Usuario: $username${NC}"
                    echo -e "   🔑 Keys activas: ${RED}$ACTIVE_COUNT${NC}"
                    echo -e "   💡 Comando para desactivar una key:"
                    FIRST_KEY=$(echo "$ACCESS_KEYS" | awk '{print $1}')
                    echo -e "   ${BLUE}aws iam update-access-key --user-name $username --access-key-id $FIRST_KEY --status Inactive --profile $PROFILE${NC}"
                    echo ""
                fi
            fi
        fi
    done <<< "$IAM_USERS"
    
    echo -e "${CYAN}🔧 Para aplicar correcciones automáticas:${NC}"
    echo -e "${BLUE}./deactivate-iam-access-keys-$PROFILE.sh${NC}"
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN IAM ACCESS KEYS ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "👥 Total usuarios: ${GREEN}$TOTAL_USERS${NC}"

if [ $TOTAL_USERS -gt 0 ]; then
    echo -e "🔑 Usuarios con access keys: ${GREEN}$USERS_WITH_KEYS${NC}"
    echo -e "📵 Usuarios sin access keys: ${BLUE}$USERS_WITHOUT_KEYS${NC}"
    echo -e "✅ Con UNA key activa: ${GREEN}$USERS_WITH_SINGLE_KEY${NC}"
    if [ $USERS_WITH_MULTIPLE_KEYS -gt 0 ]; then
        echo -e "❌ Con MÚLTIPLES keys activas: ${RED}$USERS_WITH_MULTIPLE_KEYS${NC}"
    fi
    echo -e "🔑 Total keys activas: ${BLUE}$TOTAL_ACTIVE_KEYS${NC}"
    echo -e "🔑 Total keys inactivas: ${BLUE}$TOTAL_INACTIVE_KEYS${NC}"
    
    # Calcular porcentaje de cumplimiento
    if [ $USERS_WITH_KEYS -gt 0 ]; then
        COMPLIANCE_PERCENT=$(( (USERS_WITH_SINGLE_KEY + USERS_WITHOUT_KEYS) * 100 / TOTAL_USERS ))
        echo -e "📈 Cumplimiento: ${GREEN}$COMPLIANCE_PERCENT%${NC}"
    fi
fi

echo ""

# Estado final
if [ $TOTAL_USERS -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN USUARIOS IAM${NC}"
    echo -e "${BLUE}💡 No hay usuarios IAM para verificar${NC}"
elif [ $USERS_WITH_MULTIPLE_KEYS -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: COMPLETAMENTE COMPLIANT${NC}"
    echo -e "${BLUE}💡 Ningún usuario tiene múltiples access keys activas${NC}"
else
    echo -e "${RED}⚠️ ESTADO: REQUIERE ATENCIÓN${NC}"
    echo -e "${YELLOW}💡 $USERS_WITH_MULTIPLE_KEYS usuario(s) con múltiples keys activas${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$VERIFICATION_REPORT${NC}"
echo ""