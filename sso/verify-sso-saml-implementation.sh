#!/bin/bash
# verify-sso-saml-implementation.sh
# Evalúa si se ha implementado inicio de sesión único (SSO) mediante un proveedor SAML

PROFILE="AZLOGICA"
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
echo -e "${CYAN}🔐 EVALUACIÓN DE IMPLEMENTACIÓN SSO CON SAML${NC}"
echo "=================================================================="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
echo -e "${BLUE}🔐 Verificando credenciales...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --region "$REGION" --query 'Account' --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ ERROR: No se puede acceder al perfil '$PROFILE'${NC}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# 1. Verificar Identity Providers SAML
echo -e "${BLUE}🏢 1. PROVEEDORES DE IDENTIDAD SAML:${NC}"
SAML_PROVIDERS=$(aws iam list-saml-providers --profile "$PROFILE" --query 'SAMLProviderList[].{Arn:Arn,ValidUntil:ValidUntil,CreateDate:CreateDate}' --output text 2>/dev/null)

if [ ! -z "$SAML_PROVIDERS" ] && [ "$SAML_PROVIDERS" != "None" ]; then
    echo -e "${GREEN}   ✅ Proveedores SAML configurados:${NC}"
    echo "$SAML_PROVIDERS" | while read arn valid_until create_date; do
        if [ ! -z "$arn" ]; then
            PROVIDER_NAME=$(echo "$arn" | sed 's/.*saml-provider\///')
            echo -e "${GREEN}      • $PROVIDER_NAME${NC}"
            echo -e "${BLUE}        ARN: $arn${NC}"
            echo -e "${BLUE}        Válido hasta: $valid_until${NC}"
            echo -e "${BLUE}        Creado: $create_date${NC}"
        fi
    done
    SAML_CONFIGURED=true
else
    echo -e "${RED}   ❌ No se encontraron proveedores SAML configurados${NC}"
    SAML_CONFIGURED=false
fi
echo ""

# 2. Verificar Identity Providers OIDC
echo -e "${BLUE}🌐 2. PROVEEDORES DE IDENTIDAD OIDC:${NC}"
OIDC_PROVIDERS=$(aws iam list-open-id-connect-providers --profile "$PROFILE" --query 'OpenIDConnectProviderList[].{Arn:Arn}' --output text 2>/dev/null)

if [ ! -z "$OIDC_PROVIDERS" ] && [ "$OIDC_PROVIDERS" != "None" ]; then
    echo -e "${GREEN}   ✅ Proveedores OIDC configurados:${NC}"
    echo "$OIDC_PROVIDERS" | while read arn; do
        if [ ! -z "$arn" ]; then
            PROVIDER_URL=$(echo "$arn" | sed 's/.*oidc-provider\///')
            echo -e "${GREEN}      • $PROVIDER_URL${NC}"
            echo -e "${BLUE}        ARN: $arn${NC}"
            
            # Obtener detalles del proveedor OIDC
            THUMBPRINTS=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" --profile "$PROFILE" --query 'ThumbprintList' --output text 2>/dev/null)
            CLIENT_IDS=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" --profile "$PROFILE" --query 'ClientIDList' --output text 2>/dev/null)
            
            if [ ! -z "$THUMBPRINTS" ]; then
                echo -e "${BLUE}        Thumbprints: $THUMBPRINTS${NC}"
            fi
            if [ ! -z "$CLIENT_IDS" ]; then
                echo -e "${BLUE}        Client IDs: $CLIENT_IDS${NC}"
            fi
        fi
    done
    OIDC_CONFIGURED=true
else
    echo -e "${RED}   ❌ No se encontraron proveedores OIDC configurados${NC}"
    OIDC_CONFIGURED=false
fi
echo ""

# 3. Verificar Roles IAM para SSO
echo -e "${BLUE}🎭 3. ROLES IAM PARA SSO:${NC}"
SSO_ROLES=$(aws iam list-roles --profile "$PROFILE" --query 'Roles[?contains(AssumeRolePolicyDocument, `saml`) || contains(AssumeRolePolicyDocument, `oidc`) || contains(RoleName, `SSO`) || contains(RoleName, `SAML`) || contains(RoleName, `OIDC`)].{RoleName:RoleName,CreateDate:CreateDate,Arn:Arn}' --output text 2>/dev/null)

if [ ! -z "$SSO_ROLES" ] && [ "$SSO_ROLES" != "None" ]; then
    echo -e "${GREEN}   ✅ Roles configurados para SSO:${NC}"
    echo "$SSO_ROLES" | while read role_name create_date arn; do
        if [ ! -z "$role_name" ]; then
            echo -e "${GREEN}      • $role_name${NC}"
            echo -e "${BLUE}        ARN: $arn${NC}"
            echo -e "${BLUE}        Creado: $create_date${NC}"
            
            # Verificar si el role tiene políticas adjuntas
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role_name" --profile "$PROFILE" --query 'AttachedPolicies[].PolicyName' --output text 2>/dev/null)
            if [ ! -z "$ATTACHED_POLICIES" ]; then
                echo -e "${BLUE}        Políticas: $ATTACHED_POLICIES${NC}"
            fi
        fi
    done
    SSO_ROLES_CONFIGURED=true
else
    echo -e "${YELLOW}   ⚠️ No se encontraron roles específicos para SSO${NC}"
    echo -e "${BLUE}      (Puede que usen roles genéricos)${NC}"
    SSO_ROLES_CONFIGURED=false
fi
echo ""

# 4. Verificar AWS SSO (Identity Center)
echo -e "${BLUE}🏢 4. AWS SSO (IDENTITY CENTER):${NC}"
# Nota: AWS SSO opera a nivel de organización, no de cuenta individual
SSO_INSTANCES=$(aws sso-admin list-instances --profile "$PROFILE" --query 'Instances[].{InstanceArn:InstanceArn,IdentityStoreId:IdentityStoreId}' --output text 2>/dev/null)

if [ ! -z "$SSO_INSTANCES" ] && [ "$SSO_INSTANCES" != "None" ]; then
    echo -e "${GREEN}   ✅ AWS SSO (Identity Center) configurado:${NC}"
    echo "$SSO_INSTANCES" | while read instance_arn identity_store_id; do
        if [ ! -z "$instance_arn" ]; then
            echo -e "${GREEN}      • Instance ARN: $instance_arn${NC}"
            echo -e "${BLUE}        Identity Store ID: $identity_store_id${NC}"
        fi
    done
    AWS_SSO_CONFIGURED=true
else
    echo -e "${YELLOW}   ⚠️ AWS SSO (Identity Center) no detectado en esta región${NC}"
    echo -e "${BLUE}      (Puede estar configurado en otra región o no tener permisos)${NC}"
    AWS_SSO_CONFIGURED=false
fi
echo ""

# 5. Buscar evidencias de federación en CloudTrail
echo -e "${BLUE}📋 5. EVIDENCIAS DE FEDERACIÓN EN CLOUDTRAIL (últimas 24 horas):${NC}"

# Buscar eventos de AssumeRoleWithSAML y AssumeRoleWithWebIdentity
if command -v date >/dev/null 2>&1; then
    if date --version >/dev/null 2>&1; then
        # GNU date (Linux)
        START_TIME=$(date -u -d '24 hours ago' '+%Y-%m-%dT%H:%M:%SZ')
    else
        # BSD date (macOS)
        START_TIME=$(date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ')
    fi
    
    echo -e "${BLUE}   Buscando eventos desde: $START_TIME${NC}"
    
    # Buscar en CloudTrail logs
    LOG_GROUPS=$(aws logs describe-log-groups --profile "$PROFILE" --region "$REGION" --query 'logGroups[?contains(logGroupName, `cloudtrail`) || contains(logGroupName, `CloudTrail`) || contains(logGroupName, `trail`)].logGroupName' --output text 2>/dev/null)
    
    if [ ! -z "$LOG_GROUPS" ] && [ "$LOG_GROUPS" != "None" ]; then
        FEDERATION_EVENTS_FOUND=false
        for group in $LOG_GROUPS; do
            # Buscar eventos de SAML
            SAML_EVENTS=$(aws logs filter-log-events \
                --profile "$PROFILE" --region "$REGION" \
                --log-group-name "$group" \
                --start-time $(date -d "$START_TIME" +%s)000 \
                --filter-pattern '{ $.eventName = "AssumeRoleWithSAML" }' \
                --query 'events[].{Time:eventTime,User:userIdentity.principalId,SourceIP:sourceIPAddress}' \
                --output text 2>/dev/null | head -5)
            
            if [ ! -z "$SAML_EVENTS" ]; then
                FEDERATION_EVENTS_FOUND=true
                echo -e "${GREEN}   ✅ Eventos SAML encontrados en $group:${NC}"
                echo "$SAML_EVENTS" | while read event_time user source_ip; do
                    if [ ! -z "$event_time" ]; then
                        READABLE_TIME=$(date -d @$((event_time/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Tiempo no disponible")
                        echo -e "${GREEN}      • $READABLE_TIME - Usuario: $user desde $source_ip${NC}"
                    fi
                done
            fi
            
            # Buscar eventos de Web Identity (OIDC)
            OIDC_EVENTS=$(aws logs filter-log-events \
                --profile "$PROFILE" --region "$REGION" \
                --log-group-name "$group" \
                --start-time $(date -d "$START_TIME" +%s)000 \
                --filter-pattern '{ $.eventName = "AssumeRoleWithWebIdentity" }' \
                --query 'events[].{Time:eventTime,User:userIdentity.principalId,SourceIP:sourceIPAddress}' \
                --output text 2>/dev/null | head -5)
            
            if [ ! -z "$OIDC_EVENTS" ]; then
                FEDERATION_EVENTS_FOUND=true
                echo -e "${GREEN}   ✅ Eventos OIDC encontrados en $group:${NC}"
                echo "$OIDC_EVENTS" | while read event_time user source_ip; do
                    if [ ! -z "$event_time" ]; then
                        READABLE_TIME=$(date -d @$((event_time/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "Tiempo no disponible")
                        echo -e "${GREEN}      • $READABLE_TIME - Usuario: $user desde $source_ip${NC}"
                    fi
                done
            fi
        done
        
        if [ "$FEDERATION_EVENTS_FOUND" = false ]; then
            echo -e "${YELLOW}   ⚠️ No se detectaron eventos de federación en las últimas 24 horas${NC}"
        fi
    else
        echo -e "${YELLOW}   ⚠️ No se pueden verificar eventos (no hay CloudTrail Log Groups)${NC}"
    fi
else
    echo -e "${YELLOW}   ⚠️ No se pueden verificar eventos (comando 'date' no disponible)${NC}"
fi
echo ""

# 6. Análisis de configuración de usuarios IAM vs SSO
echo -e "${BLUE}👥 6. ANÁLISIS DE USUARIOS IAM:${NC}"
IAM_USERS=$(aws iam list-users --profile "$PROFILE" --query 'Users[].{UserName:UserName,CreateDate:CreateDate,PasswordLastUsed:PasswordLastUsed}' --output text 2>/dev/null | wc -l)
ACTIVE_USERS=$(aws iam list-users --profile "$PROFILE" --query 'Users[?PasswordLastUsed!=null].UserName' --output text 2>/dev/null | wc -w)

echo -e "${BLUE}   Total usuarios IAM: $IAM_USERS${NC}"
echo -e "${BLUE}   Usuarios con login reciente: $ACTIVE_USERS${NC}"

if [ "$IAM_USERS" -gt 10 ] && [ "$SAML_CONFIGURED" = false ] && [ "$OIDC_CONFIGURED" = false ]; then
    echo -e "${YELLOW}   ⚠️ Muchos usuarios IAM sin SSO configurado - considerar implementar SSO${NC}"
elif [ "$IAM_USERS" -le 5 ] && ([ "$SAML_CONFIGURED" = true ] || [ "$OIDC_CONFIGURED" = true ]); then
    echo -e "${GREEN}   ✅ Buena configuración: SSO implementado con pocos usuarios IAM${NC}"
fi
echo ""

# Resumen y recomendaciones
echo "=================================================================="
echo -e "${CYAN}🎯 RESUMEN DE EVALUACIÓN SSO/SAML${NC}"
echo "=================================================================="

# Calcular puntuación
SCORE=0
MAX_SCORE=100

if [ "$SAML_CONFIGURED" = true ]; then
    SCORE=$((SCORE + 30))
    echo -e "${GREEN}✅ Proveedores SAML: Configurados (+30 pts)${NC}"
else
    echo -e "${RED}❌ Proveedores SAML: No configurados (0 pts)${NC}"
fi

if [ "$OIDC_CONFIGURED" = true ]; then
    SCORE=$((SCORE + 20))
    echo -e "${GREEN}✅ Proveedores OIDC: Configurados (+20 pts)${NC}"
else
    echo -e "${YELLOW}⚠️ Proveedores OIDC: No configurados (0 pts)${NC}"
fi

if [ "$SSO_ROLES_CONFIGURED" = true ]; then
    SCORE=$((SCORE + 25))
    echo -e "${GREEN}✅ Roles SSO: Configurados (+25 pts)${NC}"
else
    echo -e "${YELLOW}⚠️ Roles SSO: No identificados (0 pts)${NC}"
fi

if [ "$AWS_SSO_CONFIGURED" = true ]; then
    SCORE=$((SCORE + 25))
    echo -e "${GREEN}✅ AWS SSO: Configurado (+25 pts)${NC}"
else
    echo -e "${YELLOW}⚠️ AWS SSO: No detectado (0 pts)${NC}"
fi

echo ""
echo -e "${BLUE}📊 PUNTUACIÓN TOTAL: $SCORE/$MAX_SCORE${NC}"

if [ $SCORE -ge 75 ]; then
    echo -e "${GREEN}🎉 EXCELENTE: SSO bien implementado${NC}"
elif [ $SCORE -ge 50 ]; then
    echo -e "${YELLOW}⚠️ PARCIAL: SSO parcialmente implementado${NC}"
elif [ $SCORE -ge 25 ]; then
    echo -e "${YELLOW}📋 BÁSICO: Implementación básica de SSO${NC}"
else
    echo -e "${RED}❌ CRÍTICO: SSO no implementado${NC}"
fi

echo ""
echo -e "${PURPLE}📋 RECOMENDACIONES:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SAML_CONFIGURED" = false ] && [ "$OIDC_CONFIGURED" = false ]; then
    echo -e "${YELLOW}1. Implementar SSO con proveedor SAML o OIDC${NC}"
    echo "   - Azure AD, Google Workspace, Okta, etc."
    echo ""
fi

if [ "$AWS_SSO_CONFIGURED" = false ]; then
    echo -e "${YELLOW}2. Considerar AWS SSO (Identity Center) para gestión centralizada${NC}"
    echo "   - Especialmente útil para múltiples cuentas AWS"
    echo ""
fi

if [ "$IAM_USERS" -gt 10 ]; then
    echo -e "${YELLOW}3. Reducir usuarios IAM directos${NC}"
    echo "   - Migrar usuarios a SSO"
    echo "   - Usar roles federados en lugar de usuarios IAM"
    echo ""
fi

echo -e "${BLUE}4. Habilitar CloudTrail para monitorear eventos de federación${NC}"
echo ""
echo -e "${BLUE}5. Implementar políticas de rol con permisos mínimos${NC}"
echo ""
echo -e "${BLUE}6. Configurar MFA en el proveedor de identidad${NC}"
echo ""

echo "=================================================================="
echo -e "${GREEN}🏁 ANÁLISIS COMPLETADO${NC}"
echo "=================================================================="