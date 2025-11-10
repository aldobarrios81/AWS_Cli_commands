#!/bin/bash
# enable-ecr-tag-immutability.sh
# Habilitar inmutabilidad de tags para repositorios ECR
# Regla de seguridad: Enable tag immutability for ECR repositories
# Uso: ./enable-ecr-tag-immutability.sh [perfil]

# Verificar parámetros
if [ $# -eq 0 ]; then
    echo "Uso: $0 [perfil]"
    echo "Perfiles disponibles: ancla, azbeacons, azcenit"
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
echo -e "${BLUE}🔒 HABILITANDO TAG IMMUTABILITY EN ECR${NC}"
echo "=================================================================="
echo -e "Perfil: ${GREEN}$PROFILE${NC} | Región: ${GREEN}$REGION${NC}"
echo "Configurando inmutabilidad de tags para repositorios ECR"
echo ""

# Verificar prerrequisitos
echo -e "${PURPLE}🔍 Verificando prerrequisitos...${NC}"

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}❌ AWS CLI no está instalado${NC}"
    exit 1
fi

AWS_VERSION=$(aws --version 2>&1)
echo -e "✅ AWS CLI encontrado: ${GREEN}$AWS_VERSION${NC}"

# Verificar credenciales
echo -e "${PURPLE}🔐 Verificando credenciales para perfil '$PROFILE'...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}❌ Error: No se pudo verificar las credenciales para el perfil '$PROFILE'${NC}"
    echo -e "${YELLOW}💡 Verifica que el perfil esté configurado correctamente${NC}"
    exit 1
fi

echo -e "✅ Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo ""

# Verificar disponibilidad de ECR
echo -e "${PURPLE}🔍 Verificando disponibilidad de ECR...${NC}"
ECR_TEST=$(aws ecr describe-repositories --profile "$PROFILE" --region "$REGION" --max-items 1 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ ECR no disponible en región $REGION${NC}"
    
    # Verificar otras regiones principales
    MAIN_REGIONS=("us-west-2" "eu-west-1" "ap-southeast-1")
    FOUND_REGION=""
    
    for region in "${MAIN_REGIONS[@]}"; do
        echo -e "   🔍 Verificando región: ${BLUE}$region${NC}"
        TEST_RESULT=$(aws ecr describe-repositories --profile "$PROFILE" --region "$region" --max-items 1 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            FOUND_REGION="$region"
            echo -e "   ✅ ECR disponible en: ${GREEN}$region${NC}"
            break
        else
            echo -e "   ❌ No disponible en: $region"
        fi
    done
    
    if [ -n "$FOUND_REGION" ]; then
        echo -e "${YELLOW}💡 Cambiando a región: $FOUND_REGION${NC}"
        REGION="$FOUND_REGION"
    else
        echo -e "${YELLOW}⚠️ ECR no disponible en regiones principales${NC}"
        echo -e "${BLUE}💡 Continuando con configuraciones generales${NC}"
    fi
else
    echo -e "✅ ECR disponible en región: ${GREEN}$REGION${NC}"
fi

echo ""

# Variables de conteo
TOTAL_REPOSITORIES=0
REPOSITORIES_WITH_IMMUTABILITY=0
REPOSITORIES_UPDATED=0
REPOSITORIES_ERROR=0

# Paso 1: Inventario de repositorios ECR
echo -e "${PURPLE}=== Paso 1: Inventario de repositorios ECR ===${NC}"

# Obtener lista de repositorios ECR
ECR_REPOSITORIES=$(aws ecr describe-repositories \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'repositories[].[repositoryName,repositoryUri,imageTagMutability,createdAt]' \
    --output text 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️ Error al obtener repositorios ECR${NC}"
    TOTAL_REPOSITORIES=0
elif [ -z "$ECR_REPOSITORIES" ] || [ "$ECR_REPOSITORIES" == "None" ]; then
    echo -e "${GREEN}✅ No se encontraron repositorios ECR${NC}"
    TOTAL_REPOSITORIES=0
else
    echo -e "${GREEN}✅ Repositorios ECR encontrados${NC}"
    
    # Procesar cada repositorio
    while IFS=$'\t' read -r repo_name repo_uri tag_mutability created_at; do
        if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
            TOTAL_REPOSITORIES=$((TOTAL_REPOSITORIES + 1))
            
            echo -e "${CYAN}📦 Repositorio: $repo_name${NC}"
            echo -e "   🌐 URI: ${BLUE}$repo_uri${NC}"
            echo -e "   📅 Creado: ${BLUE}$(echo "$created_at" | cut -d'T' -f1)${NC}"
            
            # Verificar configuración de inmutabilidad actual
            if [ "$tag_mutability" == "IMMUTABLE" ]; then
                echo -e "   ✅ Tag Immutability: ${GREEN}HABILITADO${NC}"
                REPOSITORIES_WITH_IMMUTABILITY=$((REPOSITORIES_WITH_IMMUTABILITY + 1))
            else
                echo -e "   ❌ Tag Immutability: ${RED}DESHABILITADO${NC}"
                echo -e "   🎯 Acción: ${YELLOW}Requiere configuración${NC}"
            fi
            
            # Obtener información adicional del repositorio
            REPO_DETAILS=$(aws ecr describe-repositories \
                --repository-names "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'repositories[0].[imageScanningConfiguration.scanOnPush,encryptionConfiguration.encryptionType]' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$REPO_DETAILS" ]; then
                SCAN_ON_PUSH=$(echo "$REPO_DETAILS" | cut -f1)
                ENCRYPTION_TYPE=$(echo "$REPO_DETAILS" | cut -f2)
                
                echo -e "   🔍 Scan on Push: ${BLUE}$SCAN_ON_PUSH${NC}"
                echo -e "   🔐 Encryption: ${BLUE}$ENCRYPTION_TYPE${NC}"
            fi
            
            # Verificar número de imágenes
            IMAGE_COUNT=$(aws ecr list-images \
                --repository-name "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'length(imageIds)' \
                --output text 2>/dev/null)
            
            if [ $? -eq 0 ] && [ -n "$IMAGE_COUNT" ]; then
                echo -e "   📊 Imágenes: ${BLUE}$IMAGE_COUNT${NC}"
                
                # Verificar tags únicos vs duplicados
                UNIQUE_TAGS=$(aws ecr list-images \
                    --repository-name "$repo_name" \
                    --profile "$PROFILE" \
                    --region "$REGION" \
                    --query 'length(imageIds[?imageTag])' \
                    --output text 2>/dev/null)
                
                if [ -n "$UNIQUE_TAGS" ] && [ "$UNIQUE_TAGS" -gt 0 ]; then
                    echo -e "   🏷️ Imágenes con tags: ${BLUE}$UNIQUE_TAGS${NC}"
                fi
            fi
            
            echo ""
        fi
    done <<< "$ECR_REPOSITORIES"
fi

# Paso 2: Habilitar inmutabilidad en repositorios que no la tienen
if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    REPOSITORIES_TO_UPDATE=$((TOTAL_REPOSITORIES - REPOSITORIES_WITH_IMMUTABILITY))
    
    if [ $REPOSITORIES_TO_UPDATE -gt 0 ]; then
        echo -e "${PURPLE}=== Paso 2: Habilitando Tag Immutability ===${NC}"
        echo -e "${CYAN}🔧 Repositorios a actualizar: $REPOSITORIES_TO_UPDATE${NC}"
        
        # Procesar repositorios que necesitan actualización
        while IFS=$'\t' read -r repo_name repo_uri tag_mutability created_at; do
            if [ -n "$repo_name" ] && [ "$repo_name" != "None" ] && [ "$tag_mutability" != "IMMUTABLE" ]; then
                
                echo -e "${CYAN}🔧 Configurando: $repo_name${NC}"
                
                # Habilitar inmutabilidad de tags
                UPDATE_RESULT=$(aws ecr put-image-tag-mutability \
                    --repository-name "$repo_name" \
                    --image-tag-mutability IMMUTABLE \
                    --profile "$PROFILE" \
                    --region "$REGION" 2>&1)
                
                if [ $? -eq 0 ]; then
                    echo -e "   ✅ Tag Immutability habilitado exitosamente"
                    REPOSITORIES_UPDATED=$((REPOSITORIES_UPDATED + 1))
                    
                    # Verificar que el cambio se aplicó correctamente
                    VERIFICATION=$(aws ecr describe-repositories \
                        --repository-names "$repo_name" \
                        --profile "$PROFILE" \
                        --region "$REGION" \
                        --query 'repositories[0].imageTagMutability' \
                        --output text 2>/dev/null)
                    
                    if [ "$VERIFICATION" == "IMMUTABLE" ]; then
                        echo -e "   ✅ Verificación: ${GREEN}Configuración aplicada correctamente${NC}"
                    else
                        echo -e "   ⚠️ Verificación: ${YELLOW}Configuración pendiente de propagación${NC}"
                    fi
                else
                    echo -e "   ${RED}❌ Error habilitando inmutabilidad${NC}"
                    
                    # Analizar tipo de error
                    if echo "$UPDATE_RESULT" | grep -q "RepositoryNotFound"; then
                        echo -e "   ${YELLOW}💡 Repositorio no encontrado${NC}"
                    elif echo "$UPDATE_RESULT" | grep -q "AccessDenied\|UnauthorizedOperation"; then
                        echo -e "   ${YELLOW}💡 Permisos insuficientes para ECR${NC}"
                    else
                        echo -e "   ${YELLOW}💡 $(echo "$UPDATE_RESULT" | head -1)${NC}"
                    fi
                    
                    REPOSITORIES_ERROR=$((REPOSITORIES_ERROR + 1))
                fi
                
                echo ""
            fi
        done <<< "$ECR_REPOSITORIES"
    else
        echo -e "${PURPLE}=== Paso 2: Verificación completada ===${NC}"
        echo -e "${GREEN}✅ Todos los repositorios ya tienen Tag Immutability habilitado${NC}"
    fi
fi

# Paso 3: Configuraciones adicionales de seguridad
echo -e "${PURPLE}=== Paso 3: Configuraciones Adicionales de Seguridad ===${NC}"

if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    echo -e "${CYAN}🔧 Verificando configuraciones complementarias...${NC}"
    
    # Verificar y configurar scanning automático si no está habilitado
    REPOS_WITHOUT_SCAN=0
    
    while IFS=$'\t' read -r repo_name repo_uri tag_mutability created_at; do
        if [ -n "$repo_name" ] && [ "$repo_name" != "None" ]; then
            
            # Verificar configuración de scan actual
            SCAN_CONFIG=$(aws ecr describe-repositories \
                --repository-names "$repo_name" \
                --profile "$PROFILE" \
                --region "$REGION" \
                --query 'repositories[0].imageScanningConfiguration.scanOnPush' \
                --output text 2>/dev/null)
            
            if [ "$SCAN_CONFIG" != "True" ]; then
                REPOS_WITHOUT_SCAN=$((REPOS_WITHOUT_SCAN + 1))
                
                echo -e "   🔍 Habilitando scan automático para: $repo_name"
                
                # Habilitar scan on push
                aws ecr put-image-scanning-configuration \
                    --repository-name "$repo_name" \
                    --image-scanning-configuration scanOnPush=true \
                    --profile "$PROFILE" \
                    --region "$REGION" >/dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    echo -e "      ✅ Scan automático habilitado"
                else
                    echo -e "      ${YELLOW}⚠️ Error habilitando scan automático${NC}"
                fi
            fi
        fi
    done <<< "$ECR_REPOSITORIES"
    
    if [ $REPOS_WITHOUT_SCAN -eq 0 ]; then
        echo -e "✅ Todos los repositorios tienen scan automático habilitado"
    else
        echo -e "🔧 Configurado scan automático en: ${GREEN}$REPOS_WITHOUT_SCAN repositorios${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ No hay repositorios ECR para configurar${NC}"
fi

# Generar documentación
echo -e "${PURPLE}=== Paso 4: Generando documentación ===${NC}"

ECR_IMMUTABILITY_REPORT="ecr-tag-immutability-$PROFILE-$(date +%Y%m%d).md"

cat > "$ECR_IMMUTABILITY_REPORT" << EOF
# Reporte Tag Immutability - ECR - $PROFILE

**Fecha**: $(date)
**Región**: $REGION
**Account ID**: $ACCOUNT_ID

## Resumen Ejecutivo

### Repositorios ECR Procesados
- **Total repositorios**: $TOTAL_REPOSITORIES
- **Con inmutabilidad**: $((REPOSITORIES_WITH_IMMUTABILITY + REPOSITORIES_UPDATED))
- **Actualizados**: $REPOSITORIES_UPDATED
- **Errores**: $REPOSITORIES_ERROR

## Configuraciones Implementadas

### ✅ Tag Immutability
- Configuración: \`imageTagMutability: IMMUTABLE\`
- Previene sobrescritura accidental de tags
- Asegura integridad de artefactos

### 🔍 Image Scanning
- Configuración: \`scanOnPush: true\`
- Análisis automático de vulnerabilidades
- Integración con Security Hub

## Beneficios de Seguridad

### 1. Integridad de Artefactos
- Prevención de sobrescritura accidental
- Trazabilidad completa de versiones
- Auditoría mejorada

### 2. Supply Chain Security
- Previene manipulación de imágenes
- Tags no pueden ser alterados post-push
- Rollback seguro disponible

## Comandos de Verificación

\`\`\`bash
# Listar repositorios y configuración
aws ecr describe-repositories --profile $PROFILE --region $REGION \\
    --query 'repositories[].[repositoryName,imageTagMutability]' \\
    --output table

# Verificar repositorio específico
aws ecr describe-repositories --repository-names REPO_NAME --profile $PROFILE
\`\`\`

EOF

echo -e "✅ Documentación generada: ${GREEN}$ECR_IMMUTABILITY_REPORT${NC}"

# Resumen final
echo ""
echo -e "${PURPLE}=== RESUMEN ECR TAG IMMUTABILITY ===${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "🔐 Account ID: ${GREEN}$ACCOUNT_ID${NC}"
echo -e "📍 Región: ${GREEN}$REGION${NC}"
echo -e "📦 Total repositorios: ${GREEN}$TOTAL_REPOSITORIES${NC}"

if [ $TOTAL_REPOSITORIES -gt 0 ]; then
    TOTAL_WITH_IMMUTABILITY=$((REPOSITORIES_WITH_IMMUTABILITY + REPOSITORIES_UPDATED))
    echo -e "✅ Con inmutabilidad: ${GREEN}$TOTAL_WITH_IMMUTABILITY${NC}"
    echo -e "🔧 Actualizados: ${GREEN}$REPOSITORIES_UPDATED${NC}"
    
    if [ $REPOSITORIES_ERROR -gt 0 ]; then
        echo -e "❌ Errores: ${RED}$REPOSITORIES_ERROR${NC}"
    fi
    
    # Calcular porcentaje de cumplimiento
    if [ $TOTAL_REPOSITORIES -gt 0 ]; then
        COMPLIANCE_PERCENT=$((TOTAL_WITH_IMMUTABILITY * 100 / TOTAL_REPOSITORIES))
        echo -e "📈 Cumplimiento: ${GREEN}$COMPLIANCE_PERCENT%${NC}"
    fi
fi

echo -e "📋 Documentación: ${GREEN}$ECR_IMMUTABILITY_REPORT${NC}"

echo ""
if [ $TOTAL_REPOSITORIES -eq 0 ]; then
    echo -e "${GREEN}✅ NO HAY REPOSITORIOS ECR PARA CONFIGURAR${NC}"
    echo -e "${BLUE}💡 Configuraciones listas para futuros repositorios${NC}"
elif [ $REPOSITORIES_ERROR -eq 0 ] && [ $REPOSITORIES_UPDATED -ge 0 ]; then
    echo -e "${GREEN}🎉 TAG IMMUTABILITY COMPLETAMENTE CONFIGURADO${NC}"
    echo -e "${BLUE}💡 Todos los repositorios ECR son seguros e inmutables${NC}"
else
    echo -e "${YELLOW}⚠️ CONFIGURACIÓN PARCIALMENTE COMPLETA${NC}"
    echo -e "${BLUE}💡 Revisar repositorios con errores${NC}"
fi

