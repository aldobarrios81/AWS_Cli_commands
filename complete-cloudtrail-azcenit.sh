#!/bin/bash
# complete-cloudtrail-azcenit.sh
# Completar configuración de CloudTrail para azcenit con CloudWatch Logs

PROFILE="azcenit"
REGION="us-east-1"
TRAIL_NAME="azcenit-management-events"
LOG_GROUP_NAME="/aws/cloudtrail/azcenit-trail"
ROLE_NAME="CloudTrailLogsRole-azcenit"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=================================================================="
echo -e "${BLUE}🔧 COMPLETANDO CONFIGURACIÓN DE CLOUDTRAIL - AZCENIT${NC}"
echo "=================================================================="
echo "Perfil: $PROFILE"
echo "Trail: $TRAIL_NAME"
echo "Log Group: $LOG_GROUP_NAME"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text)
echo -e "${GREEN}✅ Account ID: $ACCOUNT_ID${NC}"
echo ""

# Paso 1: Crear CloudWatch Log Group
echo -e "${BLUE}📋 Paso 1: Creando CloudWatch Log Group...${NC}"

aws logs create-log-group \
    --log-group-name "$LOG_GROUP_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Log Group creado: $LOG_GROUP_NAME${NC}"
else
    echo -e "${YELLOW}⚠️ Log Group ya existe o error en creación${NC}"
fi

# Paso 2: Crear IAM Role para CloudTrail Logs
echo -e "${BLUE}🔑 Paso 2: Configurando IAM Role para CloudTrail...${NC}"

# Política de confianza para el role
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudtrail.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}'

# Crear el role
aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --profile "$PROFILE" 2>/dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ IAM Role creado: $ROLE_NAME${NC}"
else
    echo -e "${YELLOW}⚠️ IAM Role ya existe${NC}"
fi

# Política para logs
LOG_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:PutLogEvents",
        "logs:CreateLogGroup",
        "logs:CreateLogStream"
      ],
      "Resource": "arn:aws:logs:'$REGION':'$ACCOUNT_ID':log-group:'$LOG_GROUP_NAME':*"
    }
  ]
}'

# Adjuntar política al role
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "CloudTrailLogsPolicy" \
    --policy-document "$LOG_POLICY" \
    --profile "$PROFILE"

echo -e "${GREEN}✅ Política de logs adjuntada al role${NC}"

# Paso 3: Actualizar CloudTrail para usar CloudWatch Logs
echo -e "${BLUE}📝 Paso 3: Configurando CloudTrail para usar CloudWatch Logs...${NC}"

ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$ROLE_NAME"

aws cloudtrail update-trail \
    --name "$TRAIL_NAME" \
    --cloud-watch-logs-log-group-arn "arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:$LOG_GROUP_NAME:*" \
    --cloud-watch-logs-role-arn "$ROLE_ARN" \
    --profile "$PROFILE" \
    --region "$REGION"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ CloudTrail actualizado para usar CloudWatch Logs${NC}"
else
    echo -e "${RED}❌ Error actualizando CloudTrail${NC}"
    exit 1
fi

# Paso 4: Verificar configuración
echo -e "${BLUE}🔍 Paso 4: Verificando configuración...${NC}"

TRAIL_STATUS=$(aws cloudtrail describe-trails \
    --trail-name-list "$TRAIL_NAME" \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'trailList[0].{LogGroup:CloudWatchLogsLogGroupArn,Role:CloudWatchLogsRoleArn}' \
    --output text)

echo "Configuración CloudTrail:"
echo "  - Log Group ARN: $(echo $TRAIL_STATUS | cut -f1)"
echo "  - Role ARN: $(echo $TRAIL_STATUS | cut -f2)"

# Verificar que el trail esté logging
aws cloudtrail start-logging \
    --name "$TRAIL_NAME" \
    --profile "$PROFILE" \
    --region "$REGION"

echo ""
echo "=================================================================="
echo -e "${GREEN}🎉 CONFIGURACIÓN DE CLOUDTRAIL COMPLETADA${NC}"
echo "=================================================================="
echo "CloudTrail: $TRAIL_NAME"
echo "Log Group: $LOG_GROUP_NAME" 
echo "IAM Role: $ROLE_NAME"
echo ""
echo -e "${YELLOW}📋 PRÓXIMO PASO:${NC}"
echo "Ahora puedes ejecutar el script de root account monitoring:"
echo "./setup-root-account-usage-monitoring.sh"
echo ""