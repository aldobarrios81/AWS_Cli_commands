#!/bin/bash
# ecr-kms-summary.sh
# Verificar estado de cifrado KMS en repositorios ECR para todos los perfiles

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

PROFILES=("ancla" "azbeacons" "azcenit")
REGIONS=("us-east-1" "us-west-2" "eu-west-1")

echo "=================================================================="
echo -e "${BLUE}🔍 RESUMEN ECR KMS ENCRYPTION - TODOS LOS PERFILES${NC}"
echo "=================================================================="
echo -e "Fecha: ${GREEN}$(date)${NC}"
echo ""

# Variables de resumen
TOTAL_ACCOUNTS=0
ACCOUNTS_WITH_ECR=0
TOTAL_REPOSITORIES=0
KMS_REPOSITORIES=0
AES256_REPOSITORIES=0
AVAILABLE_KMS_KEYS=0

for profile in "${PROFILES[@]}"; do
    echo -e "${PURPLE}=== Perfil: $profile ===${NC}"
    
    # Verificar credenciales
    ACCOUNT_ID=$(aws sts get-caller-identity --profile "$profile" --query Account --output text 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
        echo -e "❌ Error: Credenciales no válidas para perfil '$profile'"
        continue
    fi
    
    echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
    TOTAL_ACCOUNTS=$((TOTAL_ACCOUNTS + 1))
    
    PROFILE_HAS_ECR=false
    PROFILE_REPOSITORIES=0
    PROFILE_KMS_REPOS=0
    PROFILE_AES256_REPOS=0
    PROFILE_KMS_KEYS=0
    
    # Verificar cada región
    for region in "${REGIONS[@]}"; do
        # Verificar repositorios ECR
        ECR_REPOS=$(aws ecr describe-repositories \
            --profile "$profile" \
            --region "$region" \
            --query 'repositories[].[repositoryName,encryptionConfiguration.encryptionType]' \
            --output text 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            continue
        fi
        
        if [ -z "$ECR_REPOS" ] || [ "$ECR_REPOS" == "None" ]; then
            continue
        fi
        
        PROFILE_HAS_ECR=true
        echo -e "🌍 Región: ${CYAN}$region${NC}"
        
        while IFS=$'\t' read -r repo_name encryption_type; do
            if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
                PROFILE_REPOSITORIES=$((PROFILE_REPOSITORIES + 1))
                
                if [ "$encryption_type" == "KMS" ]; then
                    echo -e "  ✅ ${GREEN}$repo_name${NC} (KMS)"
                    PROFILE_KMS_REPOS=$((PROFILE_KMS_REPOS + 1))
                else
                    echo -e "  ⚠️ ${YELLOW}$repo_name${NC} (AES256)"
                    PROFILE_AES256_REPOS=$((PROFILE_AES256_REPOS + 1))
                fi
            fi
        done <<< "$ECR_REPOS"
        
        # Verificar claves KMS disponibles
        KMS_KEYS=$(aws kms list-aliases \
            --profile "$profile" \
            --region "$region" \
            --query 'Aliases[?contains(AliasName, `ecr`)]' \
            --output text 2>/dev/null)
        
        if [ -n "$KMS_KEYS" ] && [ "$KMS_KEYS" != "None" ]; then
            KEY_COUNT=$(echo "$KMS_KEYS" | wc -l)
            PROFILE_KMS_KEYS=$((PROFILE_KMS_KEYS + KEY_COUNT))
            echo -e "  🔑 Claves KMS ECR: ${BLUE}$KEY_COUNT${NC}"
        fi
    done
    
    if [ "$PROFILE_HAS_ECR" = true ]; then
        ACCOUNTS_WITH_ECR=$((ACCOUNTS_WITH_ECR + 1))
        TOTAL_REPOSITORIES=$((TOTAL_REPOSITORIES + PROFILE_REPOSITORIES))
        KMS_REPOSITORIES=$((KMS_REPOSITORIES + PROFILE_KMS_REPOS))
        AES256_REPOSITORIES=$((AES256_REPOSITORIES + PROFILE_AES256_REPOS))
        AVAILABLE_KMS_KEYS=$((AVAILABLE_KMS_KEYS + PROFILE_KMS_KEYS))
        
        echo -e "📊 Resumen perfil:"
        echo -e "   Total repositorios: ${BLUE}$PROFILE_REPOSITORIES${NC}"
        echo -e "   Con KMS: ${GREEN}$PROFILE_KMS_REPOS${NC}"
        if [ $PROFILE_AES256_REPOS -gt 0 ]; then
            echo -e "   Con AES256: ${YELLOW}$PROFILE_AES256_REPOS${NC}"
        fi
        echo -e "   Claves KMS: ${BLUE}$PROFILE_KMS_KEYS${NC}"
        
        # Calcular cumplimiento del perfil
        if [ $PROFILE_REPOSITORIES -gt 0 ]; then
            PROFILE_KMS_COMPLIANCE=$((PROFILE_KMS_REPOS * 100 / PROFILE_REPOSITORIES))
            echo -e "   Cumplimiento KMS: ${GREEN}$PROFILE_KMS_COMPLIANCE%${NC}"
        fi
        
        # Estado del perfil
        if [ $PROFILE_AES256_REPOS -eq 0 ] && [ $PROFILE_REPOSITORIES -gt 0 ]; then
            echo -e "   Estado: ${GREEN}TOTALMENTE CIFRADO${NC}"
        elif [ $PROFILE_KMS_REPOS -gt 0 ]; then
            echo -e "   Estado: ${YELLOW}CIFRADO MIXTO${NC}"
        else
            echo -e "   Estado: ${YELLOW}SOLO AES256${NC}"
        fi
    else
        echo -e "✅ Sin repositorios ECR"
        
        # Verificar si hay claves KMS preparadas
        for region in "${REGIONS[@]}"; do
            KMS_PREPARED=$(aws kms list-aliases \
                --profile "$profile" \
                --region "$region" \
                --query 'Aliases[?contains(AliasName, `ecr`)]' \
                --output text 2>/dev/null)
            
            if [ -n "$KMS_PREPARED" ] && [ "$KMS_PREPARED" != "None" ]; then
                echo -e "🔑 Claves KMS preparadas en: ${BLUE}$region${NC}"
                AVAILABLE_KMS_KEYS=$((AVAILABLE_KMS_KEYS + 1))
            fi
        done
    fi
    
    echo ""
done

# Resumen general
echo -e "${PURPLE}=== RESUMEN GENERAL ECR KMS ENCRYPTION ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "📊 Total cuentas verificadas: ${GREEN}$TOTAL_ACCOUNTS${NC}"
echo -e "🏢 Cuentas con ECR: ${GREEN}$ACCOUNTS_WITH_ECR${NC}"
echo -e "📦 Total repositorios ECR: ${GREEN}$TOTAL_REPOSITORIES${NC}"

if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    echo -e "🔐 Con cifrado KMS: ${GREEN}$KMS_REPOSITORIES${NC}"
    if [ $AES256_REPOSITORIES -gt 0 ]; then
        echo -e "⚠️ Con AES256: ${YELLOW}$AES256_REPOSITORIES${NC}"
    fi
    
    # Calcular porcentajes
    KMS_COMPLIANCE=$((KMS_REPOSITORIES * 100 / TOTAL_REPOSITORIES))
    echo -e "📈 Cumplimiento KMS general: ${GREEN}$KMS_COMPLIANCE%${NC}"
fi

echo -e "🔑 Claves KMS disponibles: ${BLUE}$AVAILABLE_KMS_KEYS${NC}"

echo ""

# Análisis de limitaciones ECR
echo -e "${PURPLE}=== LIMITACIONES DE AWS ECR ===${NC}"
echo -e "⚠️ ${YELLOW}Repositorios existentes:${NC}"
echo -e "   • No se puede cambiar cifrado de AES256 a KMS"
echo -e "   • Requiere recreación del repositorio"
echo -e "   • Migración manual de imágenes"
echo ""
echo -e "✅ ${GREEN}Repositorios nuevos:${NC}"
echo -e "   • Configuración KMS disponible en creación"
echo -e "   • Scripts helper generados automáticamente"
echo -e "   • Claves KMS personalizadas recomendadas"

echo ""

# Recomendaciones
echo -e "${PURPLE}=== RECOMENDACIONES ESTRATÉGICAS ===${NC}"

if [ $AES256_REPOSITORIES -gt 0 ]; then
    echo -e "🔄 ${CYAN}Migración gradual:${NC}"
    echo -e "   1. Crear nuevos repositorios con KMS"
    echo -e "   2. Migrar imágenes críticas primero"
    echo -e "   3. Deprecar repositorios AES256 gradualmente"
    echo ""
fi

echo -e "🔧 ${CYAN}Configuración técnica:${NC}"
echo -e "   • Crear claves KMS dedicadas por región"
echo -e "   • Usar alias descriptivos (ecr-encryption-key-region)"
echo -e "   • Configurar políticas de acceso restrictivas"
echo -e "   • Habilitar rotación automática"

echo ""
echo -e "📋 ${CYAN}Scripts disponibles:${NC}"
echo -e "   🔍 Verificación: ${BLUE}./verify-ecr-kms-encryption.sh [perfil]${NC}"
echo -e "   🔧 Configuración: ${BLUE}./enable-ecr-kms-encryption.sh [perfil]${NC}"

# Estado final
echo ""
if [ $TOTAL_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}✅ ESTADO: PREPARADO PARA KMS${NC}"
    echo -e "${BLUE}💡 Claves y scripts listos para futuros repositorios${NC}"
elif [ $AES256_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}🎉 ESTADO: CIFRADO KMS COMPLETO${NC}"
    echo -e "${BLUE}💡 Todos los repositorios usan cifrado KMS${NC}"
else
    echo -e "${YELLOW}⚠️ ESTADO: MIGRACIÓN REQUERIDA${NC}"
    echo -e "${YELLOW}💡 $AES256_REPOSITORIES repositorios requieren migración a KMS${NC}"
    
    # Estrategia de migración
    echo ""
    echo -e "${CYAN}🎯 Estrategia de migración recomendada:${NC}"
    echo -e "   1. Evaluar criticidad de imágenes existentes"
    echo -e "   2. Crear repositorios KMS para nuevas imágenes"
    echo -e "   3. Migrar imágenes por prioridad de seguridad"
    echo -e "   4. Documentar y comunicar cronograma"
fi

# Generar comando de siguiente paso
echo ""
echo -e "${CYAN}🚀 Próximo paso recomendado:${NC}"
if [ $AES256_REPOSITORIES -gt 0 ]; then
    echo -e "${BLUE}# Ejecutar configuración KMS para un perfil específico${NC}"
    echo -e "${BLUE}./enable-ecr-kms-encryption.sh [perfil]${NC}"
else
    echo -e "${BLUE}# Verificar configuración actual${NC}"
    echo -e "${BLUE}./verify-ecr-kms-encryption.sh [perfil]${NC}"
fi