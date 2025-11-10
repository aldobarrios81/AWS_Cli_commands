#!/bin/bash
# verify-iam-hardware-mfa.sh
# Verificar habilitación de MFA de hardware para usuarios IAM
# Análisis de cumplimiento de mejores prácticas de seguridad

if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit, metrokia, AZLOGICA"
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
echo -e "${BLUE}🔐 VERIFICACIÓN MFA DE HARDWARE IAM${NC}"
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
USERS_WITH_MFA=0
USERS_WITHOUT_MFA=0
USERS_WITH_HARDWARE_MFA=0
USERS_WITH_VIRTUAL_MFA=0
INACTIVE_USERS=0

echo -e "${PURPLE}=== Análisis de MFA en Usuarios IAM ===${NC}"

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
            
            # Verificar si el usuario está activo (ha usado password recientemente)
            IS_ACTIVE=false
            if [ -n "$password_last_used" ] && [ "$password_last_used" != "None" ]; then
                LAST_USED_DAYS=$(( ($(date +%s) - $(date -d "${password_last_used%T*}" +%s)) / 86400 ))
                echo -e "   🔒 Último uso password: ${BLUE}${LAST_USED_DAYS} días atrás${NC}"
                
                if [ $LAST_USED_DAYS -le 90 ]; then
                    IS_ACTIVE=true
                else
                    echo -e "   ⚠️  Usuario inactivo (>90 días sin uso)"
                    INACTIVE_USERS=$((INACTIVE_USERS + 1))
                fi
            else
                echo -e "   🔒 Último uso password: ${YELLOW}Nunca / Sin password${NC}"
                INACTIVE_USERS=$((INACTIVE_USERS + 1))
            fi
            
            # Obtener dispositivos MFA del usuario
            MFA_DEVICES=$(aws iam list-mfa-devices \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'MFADevices[].[SerialNumber,EnableDate]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$MFA_DEVICES" ] && [ "$MFA_DEVICES" != "None" ]; then
                USERS_WITH_MFA=$((USERS_WITH_MFA + 1))
                echo -e "   ✅ MFA: ${GREEN}HABILITADO${NC}"
                
                # Analizar tipo de MFA
                HAS_HARDWARE_MFA=false
                HAS_VIRTUAL_MFA=false
                
                echo -e "   🔑 Dispositivos MFA:"
                while IFS=$'\t' read -r serial_number enable_date; do
                    if [ -n "$serial_number" ]; then
                        # Identificar tipo de MFA por el formato del serial number
                        if [[ "$serial_number" == arn:aws:iam::*:mfa/* ]]; then
                            echo -e "      📱 Virtual MFA: ${BLUE}$(basename "$serial_number")${NC}"
                            echo -e "         Habilitado: $(echo "$enable_date" | cut -d'T' -f1)"
                            HAS_VIRTUAL_MFA=true
                        elif [[ "$serial_number" =~ ^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$ ]] || [[ "$serial_number" =~ ^GAHT[0-9]{8}$ ]] || [[ "$serial_number" =~ ^GAKT[0-9]{8}$ ]]; then
                            echo -e "      🔐 Hardware MFA: ${GREEN}$serial_number${NC}"
                            echo -e "         Habilitado: $(echo "$enable_date" | cut -d'T' -f1)"
                            HAS_HARDWARE_MFA=true
                        else
                            echo -e "      🔒 MFA Device: ${BLUE}$serial_number${NC}"
                            echo -e "         Habilitado: $(echo "$enable_date" | cut -d'T' -f1)"
                            echo -e "         Tipo: ${YELLOW}No identificado${NC}"
                        fi
                    fi
                done <<< "$MFA_DEVICES"
                
                # Contabilizar tipo de MFA
                if [ "$HAS_HARDWARE_MFA" = true ]; then
                    USERS_WITH_HARDWARE_MFA=$((USERS_WITH_HARDWARE_MFA + 1))
                    echo -e "   🎯 Estado MFA: ${GREEN}HARDWARE MFA - ÓPTIMO${NC}"
                elif [ "$HAS_VIRTUAL_MFA" = true ]; then
                    USERS_WITH_VIRTUAL_MFA=$((USERS_WITH_VIRTUAL_MFA + 1))
                    echo -e "   🎯 Estado MFA: ${YELLOW}VIRTUAL MFA - ACEPTABLE${NC}"
                    echo -e "   💡 Recomendación: ${BLUE}Considerar migrar a Hardware MFA${NC}"
                else
                    echo -e "   🎯 Estado MFA: ${YELLOW}TIPO NO IDENTIFICADO${NC}"
                fi
                
            else
                USERS_WITHOUT_MFA=$((USERS_WITHOUT_MFA + 1))
                echo -e "   ❌ MFA: ${RED}NO HABILITADO${NC}"
                
                if [ "$IS_ACTIVE" = true ]; then
                    echo -e "   🚨 RIESGO ALTO: ${RED}Usuario activo sin MFA${NC}"
                else
                    echo -e "   ⚠️  RIESGO MEDIO: ${YELLOW}Usuario inactivo sin MFA${NC}"
                fi
                
                echo -e "   💡 Acción requerida: ${BLUE}Habilitar Hardware MFA${NC}"
            fi
            
            # Verificar grupos y políticas del usuario (para evaluar privilegios)
            USER_GROUPS=$(aws iam get-groups-for-user \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'Groups[].GroupName' \
                --output text 2>/dev/null)
            
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
            
            # Evaluar nivel de privilegios
            PRIVILEGE_LEVEL="BAJO"
            
            if echo "$USER_GROUPS $USER_POLICIES $INLINE_POLICIES" | grep -qi "admin\|power\|full"; then
                PRIVILEGE_LEVEL="ALTO"
            elif echo "$USER_GROUPS $USER_POLICIES $INLINE_POLICIES" | grep -qi "developer\|read\|write"; then
                PRIVILEGE_LEVEL="MEDIO"
            fi
            
            echo -e "   🔓 Nivel privilegios: ${BLUE}$PRIVILEGE_LEVEL${NC}"
            
            # Evaluación de riesgo general
            RISK_SCORE=0
            
            if [ "$USERS_WITHOUT_MFA" -gt 0 ] && [ "$IS_ACTIVE" = true ]; then
                RISK_SCORE=$((RISK_SCORE + 3))  # Sin MFA y activo
            elif [ "$USERS_WITHOUT_MFA" -gt 0 ]; then
                RISK_SCORE=$((RISK_SCORE + 1))  # Sin MFA pero inactivo
            fi
            
            if [ "$PRIVILEGE_LEVEL" = "ALTO" ]; then
                RISK_SCORE=$((RISK_SCORE + 2))
            elif [ "$PRIVILEGE_LEVEL" = "MEDIO" ]; then
                RISK_SCORE=$((RISK_SCORE + 1))
            fi
            
            if [ "$HAS_VIRTUAL_MFA" = true ] && [ "$PRIVILEGE_LEVEL" = "ALTO" ]; then
                RISK_SCORE=$((RISK_SCORE + 1))  # Admin con solo virtual MFA
            fi
            
            # Mostrar evaluación de riesgo
            if [ $RISK_SCORE -eq 0 ]; then
                echo -e "   🛡️  Evaluación riesgo: ${GREEN}BAJO (seguro)${NC}"
            elif [ $RISK_SCORE -le 2 ]; then
                echo -e "   🛡️  Evaluación riesgo: ${YELLOW}MEDIO${NC}"
            else
                echo -e "   🛡️  Evaluación riesgo: ${RED}ALTO - REQUIERE ATENCIÓN${NC}"
            fi
            
            echo ""
        fi
    done <<< "$IAM_USERS"
fi

echo ""

# Verificar configuración de política de passwords
echo -e "${PURPLE}=== Política de Passwords de la Cuenta ===${NC}"

PASSWORD_POLICY=$(aws iam get-account-password-policy \
    --profile "$PROFILE" \
    --query 'PasswordPolicy' \
    --output json 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$PASSWORD_POLICY" ]; then
    echo -e "✅ Política de passwords: ${GREEN}CONFIGURADA${NC}"
    
    # Extraer configuraciones clave
    REQUIRE_SYMBOLS=$(echo "$PASSWORD_POLICY" | jq -r '.RequireSymbols // false')
    REQUIRE_NUMBERS=$(echo "$PASSWORD_POLICY" | jq -r '.RequireNumbers // false')
    REQUIRE_UPPERCASE=$(echo "$PASSWORD_POLICY" | jq -r '.RequireUppercaseCharacters // false')
    REQUIRE_LOWERCASE=$(echo "$PASSWORD_POLICY" | jq -r '.RequireLowercaseCharacters // false')
    MIN_LENGTH=$(echo "$PASSWORD_POLICY" | jq -r '.MinimumPasswordLength // 0')
    MAX_AGE=$(echo "$PASSWORD_POLICY" | jq -r '.MaxPasswordAge // "null"')
    REUSE_PREVENTION=$(echo "$PASSWORD_POLICY" | jq -r '.PasswordReusePrevention // 0')
    
    echo -e "   📏 Longitud mínima: ${BLUE}$MIN_LENGTH caracteres${NC}"
    echo -e "   🔤 Complejidad: Símbolos($REQUIRE_SYMBOLS) Números($REQUIRE_NUMBERS) Mayúsculas($REQUIRE_UPPERCASE) Minúsculas($REQUIRE_LOWERCASE)"
    
    if [ "$MAX_AGE" != "null" ]; then
        echo -e "   ⏰ Expiración: ${BLUE}$MAX_AGE días${NC}"
    else
        echo -e "   ⏰ Expiración: ${YELLOW}Sin límite${NC}"
    fi
    
    echo -e "   🔁 Prevención reuso: ${BLUE}$REUSE_PREVENTION passwords${NC}"
    
else
    echo -e "❌ Política de passwords: ${RED}NO CONFIGURADA${NC}"
    echo -e "💡 Recomendación: ${BLUE}Configurar política de passwords robusta${NC}"
fi

echo ""

# Generar reporte de verificación
VERIFICATION_REPORT="iam-hardware-mfa-verification-$PROFILE-$(date +%Y%m%d-%H%M).json"

cat > "$VERIFICATION_REPORT" << EOF
{
  "verification_timestamp": "$(date -Iseconds)",
  "profile": "$PROFILE",
  "account_id": "$ACCOUNT_ID",
  "summary": {
    "total_users": $TOTAL_USERS,
    "users_with_mfa": $USERS_WITH_MFA,
    "users_without_mfa": $USERS_WITHOUT_MFA,
    "users_with_hardware_mfa": $USERS_WITH_HARDWARE_MFA,
    "users_with_virtual_mfa": $USERS_WITH_VIRTUAL_MFA,
    "inactive_users": $INACTIVE_USERS,
    "mfa_compliance": "$(if [ $TOTAL_USERS -eq 0 ]; then echo "NO_USERS"; elif [ $USERS_WITHOUT_MFA -eq 0 ]; then echo "FULLY_COMPLIANT"; else echo "PARTIAL_COMPLIANCE"; fi)",
    "hardware_mfa_adoption": "$(if [ $TOTAL_USERS -eq 0 ]; then echo "0%"; else echo "$(( USERS_WITH_HARDWARE_MFA * 100 / TOTAL_USERS ))%"; fi)"
  },
  "security_recommendations": [
    "Habilitar Hardware MFA para todos los usuarios activos",
    "Migrar usuarios con Virtual MFA a Hardware MFA",
    "Deshabilitar o eliminar usuarios inactivos",
    "Configurar política de passwords robusta",
    "Implementar rotación regular de credenciales",
    "Monitorear intentos de login sin MFA",
    "Educar usuarios sobre importancia de Hardware MFA"
  ],
  "hardware_mfa_benefits": [
    "Mayor resistencia a ataques de phishing",
    "No depende de dispositivos móviles",
    "Cumplimiento con estándares de seguridad empresarial",
    "Mayor confiabilidad en entornos críticos"
  ]
}
EOF

echo -e "📊 Reporte generado: ${GREEN}$VERIFICATION_REPORT${NC}"

# Comandos de remediación
if [ $USERS_WITHOUT_MFA -gt 0 ]; then
    echo ""
    echo -e "${PURPLE}=== Usuarios que requieren MFA ===${NC}"
    
    # Mostrar usuarios sin MFA
    while IFS=$'\t' read -r username created_date password_last_used; do
        if [ -n "$username" ] && [ "$username" != "None" ]; then
            MFA_CHECK=$(aws iam list-mfa-devices \
                --user-name "$username" \
                --profile "$PROFILE" \
                --query 'MFADevices[].SerialNumber' \
                --output text 2>/dev/null)
            
            if [ -z "$MFA_CHECK" ] || [ "$MFA_CHECK" == "None" ]; then
                echo -e "${YELLOW}⚠️  Usuario sin MFA: $username${NC}"
                
                # Verificar si está activo
                if [ -n "$password_last_used" ] && [ "$password_last_used" != "None" ]; then
                    LAST_USED_DAYS=$(( ($(date +%s) - $(date -d "${password_last_used%T*}" +%s)) / 86400 ))
                    if [ $LAST_USED_DAYS -le 90 ]; then
                        echo -e "   🚨 PRIORIDAD ALTA: Usuario activo (${LAST_USED_DAYS} días)"
                    else
                        echo -e "   ⚠️  Prioridad media: Usuario inactivo (${LAST_USED_DAYS} días)"
                    fi
                else
                    echo -e "   ℹ️  Prioridad baja: Sin uso de password"
                fi
                
                echo -e "   💡 Comandos para habilitar Hardware MFA:"
                echo -e "   ${BLUE}# 1. Crear dispositivo MFA virtual (temporal)${NC}"
                echo -e "   ${BLUE}aws iam create-virtual-mfa-device --virtual-mfa-device-name $username-mfa --profile $PROFILE${NC}"
                echo -e "   ${BLUE}# 2. Asociar dispositivo al usuario${NC}"
                echo -e "   ${BLUE}aws iam enable-mfa-device --user-name $username --serial-number arn:aws:iam::$ACCOUNT_ID:mfa/$username-mfa --authentication-code1 CODE1 --authentication-code2 CODE2 --profile $PROFILE${NC}"
                echo ""
            fi
        fi
    done <<< "$IAM_USERS"
    
    echo -e "${CYAN}📋 Pasos para implementar Hardware MFA:${NC}"
    echo -e "${BLUE}1. Adquirir dispositivos FIDO U2F/WebAuthn (YubiKey, etc.)${NC}"
    echo -e "${BLUE}2. Configurar dispositivos en la consola AWS${NC}"
    echo -e "${BLUE}3. Migrar usuarios de Virtual MFA a Hardware MFA${NC}"
    echo -e "${BLUE}4. Establecer políticas que requieran MFA${NC}"
fi

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN VERIFICACIÓN MFA DE HARDWARE ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "👥 Total usuarios: ${GREEN}$TOTAL_USERS${NC}"

if [ $TOTAL_USERS -gt 0 ]; then
    echo -e "✅ Con MFA habilitado: ${GREEN}$USERS_WITH_MFA${NC}"
    echo -e "❌ Sin MFA: ${RED}$USERS_WITHOUT_MFA${NC}"
    echo -e "🔐 Con Hardware MFA: ${GREEN}$USERS_WITH_HARDWARE_MFA${NC}"
    echo -e "📱 Con Virtual MFA: ${YELLOW}$USERS_WITH_VIRTUAL_MFA${NC}"
    echo -e "😴 Usuarios inactivos: ${BLUE}$INACTIVE_USERS${NC}"
    
    # Calcular porcentajes
    MFA_COMPLIANCE=$(( USERS_WITH_MFA * 100 / TOTAL_USERS ))
    HARDWARE_MFA_ADOPTION=$(( USERS_WITH_HARDWARE_MFA * 100 / TOTAL_USERS ))
    
    echo -e "📈 Cumplimiento MFA: ${GREEN}$MFA_COMPLIANCE%${NC}"
    echo -e "📈 Adopción Hardware MFA: ${GREEN}$HARDWARE_MFA_ADOPTION%${NC}"
fi

echo ""

# Estado final y recomendaciones
if [ $TOTAL_USERS -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: SIN USUARIOS IAM${NC}"
    echo -e "${BLUE}💡 No hay usuarios IAM para verificar${NC}"
elif [ $USERS_WITHOUT_MFA -eq 0 ] && [ $USERS_WITH_HARDWARE_MFA -eq $USERS_WITH_MFA ]; then
    echo -e "${GREEN}🎉 ESTADO: ÓPTIMO - 100% HARDWARE MFA${NC}"
    echo -e "${BLUE}💡 Todos los usuarios tienen Hardware MFA habilitado${NC}"
elif [ $USERS_WITHOUT_MFA -eq 0 ]; then
    echo -e "${YELLOW}⚠️ ESTADO: BUENO - MFA COMPLETO${NC}"
    echo -e "${BLUE}💡 Considerar migrar Virtual MFA a Hardware MFA${NC}"
else
    echo -e "${RED}🚨 ESTADO: REQUIERE ATENCIÓN INMEDIATA${NC}"
    echo -e "${YELLOW}💡 $USERS_WITHOUT_MFA usuario(s) sin MFA - RIESGO DE SEGURIDAD${NC}"
fi

echo -e "📋 Reporte detallado: ${GREEN}$VERIFICATION_REPORT${NC}"
echo ""