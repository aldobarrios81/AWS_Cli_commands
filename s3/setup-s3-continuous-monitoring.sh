#!/bin/bash

# Configuración de Monitoreo Continuo para Auto-Remediación S3 Logging
# Crea CloudWatch Event Rules, Lambda Functions y SNS Topics

set -e

PROFILE="ancla"
REGION="us-east-1"
LAMBDA_FUNCTION_NAME="S3-Auto-Remediation-Logging"
SNS_TOPIC_NAME="S3-Logging-Remediation-Alerts"
EVENT_RULE_NAME="S3-Bucket-Creation-Monitor"

echo "=== Configurando Monitoreo Continuo para S3 Auto-Remediación ==="
echo "Perfil: $PROFILE | Región: $REGION"
echo ""

# Obtener Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --region $REGION --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

echo ""
echo "=== 1. Creando SNS Topic para Alertas ==="
SNS_TOPIC_ARN=$(aws sns create-topic \
    --name "$SNS_TOPIC_NAME" \
    --profile $PROFILE \
    --region $REGION \
    --query 'TopicArn' \
    --output text)

echo "✔ SNS Topic creado: $SNS_TOPIC_ARN"

# Configurar política del SNS Topic
cat > /tmp/sns-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "$SNS_TOPIC_ARN"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "$SNS_TOPIC_ARN"
    }
  ]
}
EOF

aws sns set-topic-attributes \
    --topic-arn "$SNS_TOPIC_ARN" \
    --attribute-name Policy \
    --attribute-value file:///tmp/sns-policy.json \
    --profile $PROFILE \
    --region $REGION

echo ""
echo "=== 2. Creando IAM Role para Lambda Function ==="

# Crear rol para Lambda
cat > /tmp/lambda-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

LAMBDA_ROLE_NAME="S3-Auto-Remediation-Lambda-Role"
aws iam create-role \
    --role-name "$LAMBDA_ROLE_NAME" \
    --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
    --profile $PROFILE 2>/dev/null || echo "Rol ya existe"

# Política para Lambda
cat > /tmp/lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLogging",
        "s3:PutBucketLogging",
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "$SNS_TOPIC_ARN"
    }
  ]
}
EOF

aws iam put-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-name "S3AutoRemediationPolicy" \
    --policy-document file:///tmp/lambda-policy.json \
    --profile $PROFILE

LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"
echo "✔ IAM Role creado: $LAMBDA_ROLE_ARN"

echo ""
echo "=== 3. Creando Lambda Function ==="

# Código de la Lambda Function
cat > /tmp/lambda-function.py << 'EOF'
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client('s3')
sns_client = boto3.client('sns')

def lambda_handler(event, context):
    """
    Auto-remediación para S3 Bucket Logging
    Detecta buckets nuevos o modificados sin logging y los configura automáticamente
    """
    
    try:
        # Procesar evento de CloudWatch
        if 'Records' in event:
            for record in event['Records']:
                if record.get('eventSource') == 'aws:s3':
                    bucket_name = record['s3']['bucket']['name']
                    process_bucket(bucket_name)
        
        # Procesar evento directo (para testing)
        elif 'bucket_name' in event:
            process_bucket(event['bucket_name'])
        
        # Procesar evento de CloudWatch Events
        elif 'source' in event and event['source'] == 'aws.s3':
            if event.get('detail-type') == 'AWS API Call via CloudTrail':
                if event['detail']['eventName'] == 'CreateBucket':
                    bucket_name = event['detail']['requestParameters']['bucketName']
                    process_bucket(bucket_name)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Auto-remediation completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error in auto-remediation: {str(e)}")
        send_alert(f"Error in S3 auto-remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_bucket(bucket_name):
    """Procesa un bucket específico para auto-remediación"""
    
    # Skip buckets de logs
    if 'access-logs' in bucket_name or 'logs' in bucket_name.lower():
        logger.info(f"Skipping logs bucket: {bucket_name}")
        return
    
    try:
        # Verificar logging actual
        logging_response = s3_client.get_bucket_logging(Bucket=bucket_name)
        
        if 'LoggingEnabled' in logging_response:
            logger.info(f"Bucket {bucket_name} already has logging enabled")
            return
            
    except s3_client.exceptions.NoSuchBucket:
        logger.warning(f"Bucket {bucket_name} no longer exists")
        return
    except Exception as e:
        logger.warning(f"Could not check logging for {bucket_name}: {str(e)}")
    
    # Aplicar auto-remediación
    try:
        # Obtener región del bucket
        bucket_location = s3_client.get_bucket_location(Bucket=bucket_name)
        bucket_region = bucket_location.get('LocationConstraint') or 'us-east-1'
        
        # Bucket de logs centralizado
        account_id = boto3.client('sts').get_caller_identity()['Account']
        log_bucket = f"s3-access-logs-{account_id}-{bucket_region}"
        
        # Configurar logging
        logging_config = {
            'LoggingEnabled': {
                'TargetBucket': log_bucket,
                'TargetPrefix': f'{bucket_name}/access-logs/'
            }
        }
        
        s3_client.put_bucket_logging(
            Bucket=bucket_name,
            BucketLoggingStatus=logging_config
        )
        
        message = f"Auto-remediation applied: Logging enabled for bucket {bucket_name}"
        logger.info(message)
        send_alert(message, success=True)
        
    except Exception as e:
        error_message = f"Failed to apply auto-remediation for bucket {bucket_name}: {str(e)}"
        logger.error(error_message)
        send_alert(error_message, success=False)

def send_alert(message, success=None):
    """Envía alertas via SNS"""
    try:
        subject = "S3 Auto-Remediation Alert"
        if success is True:
            subject = "✅ S3 Auto-Remediation Success"
        elif success is False:
            subject = "❌ S3 Auto-Remediation Failed"
        
        sns_client.publish(
            TopicArn=os.environ.get('SNS_TOPIC_ARN'),
            Subject=subject,
            Message=message
        )
    except Exception as e:
        logger.error(f"Failed to send SNS alert: {str(e)}")
EOF

# Crear ZIP para Lambda
cd /tmp
zip lambda-function.zip lambda-function.py

# Crear Lambda Function
aws lambda create-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime python3.9 \
    --role "$LAMBDA_ROLE_ARN" \
    --handler lambda-function.lambda_handler \
    --zip-file fileb://lambda-function.zip \
    --timeout 60 \
    --environment Variables="{SNS_TOPIC_ARN=$SNS_TOPIC_ARN}" \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "Lambda function already exists"

LAMBDA_FUNCTION_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
echo "✔ Lambda Function creada: $LAMBDA_FUNCTION_ARN"

echo ""
echo "=== 4. Creando CloudWatch Event Rule ==="

# Event Rule para detectar creación de buckets S3
cat > /tmp/event-pattern.json << EOF
{
  "source": ["aws.s3"],
  "detail-type": ["AWS API Call via CloudTrail"],
  "detail": {
    "eventSource": ["s3.amazonaws.com"],
    "eventName": ["CreateBucket", "PutBucketLogging"]
  }
}
EOF

aws events put-rule \
    --name "$EVENT_RULE_NAME" \
    --event-pattern file:///tmp/event-pattern.json \
    --state ENABLED \
    --description "Monitor S3 bucket creation and logging changes for auto-remediation" \
    --profile $PROFILE \
    --region $REGION

# Dar permisos a CloudWatch Events para invocar Lambda
aws lambda add-permission \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id "AllowExecutionFromCloudWatchEvents" \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${REGION}:${ACCOUNT_ID}:rule/${EVENT_RULE_NAME}" \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "Permission already exists"

# Agregar Lambda como target del Event Rule
aws events put-targets \
    --rule "$EVENT_RULE_NAME" \
    --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN" \
    --profile $PROFILE \
    --region $REGION

echo "✔ CloudWatch Event Rule creada: $EVENT_RULE_NAME"

# Limpiar archivos temporales
rm -f /tmp/*.json /tmp/*.py /tmp/*.zip

echo ""
echo "=== Configuración de Monitoreo Continuo Completada ✅ ==="
echo ""
echo "📋 Componentes Creados:"
echo "   🔔 SNS Topic: $SNS_TOPIC_ARN"
echo "   👤 IAM Role: $LAMBDA_ROLE_ARN"
echo "   ⚡ Lambda Function: $LAMBDA_FUNCTION_ARN"
echo "   📅 CloudWatch Rule: $EVENT_RULE_NAME"
echo ""
echo "🚀 El sistema ahora monitorea automáticamente:"
echo "   - Creación de nuevos buckets S3"
echo "   - Cambios en configuración de logging"
echo "   - Aplica auto-remediación automáticamente"
echo "   - Envía alertas via SNS"
echo ""
echo "📧 Para recibir alertas, suscríbase al SNS Topic:"
echo "   aws sns subscribe --topic-arn $SNS_TOPIC_ARN --protocol email --notification-endpoint your-email@domain.com"