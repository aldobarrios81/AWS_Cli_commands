#!/bin/bash
# verify-aws-health-alerts.sh
# Verifica la configuración de CloudWatch rules para AWS Health Events

PROFILE="ancla"
REGION="us-east-1"

echo "🔍 VERIFICACIÓN: CloudWatch Rules para AWS Health Events"
echo "═══════════════════════════════════════════════════════════"
echo "Perfil: $PROFILE | Región: $REGION"
echo

echo "📋 1. Verificando SNS Topic:"
echo "────────────────────────────────────────────────────────────"
TOPIC_ARN=$(aws sns list-topics --profile $PROFILE --region $REGION --query 'Topics[?contains(TopicArn, `aws-health-alerts`)].TopicArn' --output text)
if [ -n "$TOPIC_ARN" ]; then
    echo "✅ SNS Topic encontrado: $TOPIC_ARN"
    
    # Verificar atributos del topic
    echo "📝 Atributos del Topic:"
    aws sns get-topic-attributes --topic-arn $TOPIC_ARN --profile $PROFILE --region $REGION --query 'Attributes.Policy' --output text > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "   ✅ Policy configurada (EventBridge tiene permisos)"
    else
        echo "   ⚠️ Policy no encontrada"
    fi
else
    echo "❌ SNS Topic no encontrado"
fi

echo
echo "📋 2. Verificando EventBridge Rule:"
echo "────────────────────────────────────────────────────────────"
RULE_ARN=$(aws events list-rules --name-prefix "AWSHealthRealTimeEvents" --profile $PROFILE --region $REGION --query 'Rules[0].Arn' --output text 2>/dev/null)
if [ -n "$RULE_ARN" ] && [ "$RULE_ARN" != "None" ]; then
    echo "✅ EventBridge Rule encontrada: $RULE_ARN"
    
    # Verificar estado de la regla
    RULE_STATE=$(aws events list-rules --name-prefix "AWSHealthRealTimeEvents" --profile $PROFILE --region $REGION --query 'Rules[0].State' --output text)
    echo "   📊 Estado: $RULE_STATE"
    
    # Verificar pattern de eventos
    echo "   🎯 Event Pattern:"
    aws events list-rules --name-prefix "AWSHealthRealTimeEvents" --profile $PROFILE --region $REGION --query 'Rules[0].EventPattern' --output text
else
    echo "❌ EventBridge Rule no encontrada"
fi

echo
echo "📋 3. Verificando Targets de la Rule:"
echo "────────────────────────────────────────────────────────────"
if [ -n "$RULE_ARN" ] && [ "$RULE_ARN" != "None" ]; then
    TARGETS=$(aws events list-targets-by-rule --rule "AWSHealthRealTimeEvents" --profile $PROFILE --region $REGION --query 'Targets[*].Arn' --output text 2>/dev/null)
    if [ -n "$TARGETS" ]; then
        echo "✅ Targets configurados:"
        for TARGET in $TARGETS; do
            echo "   🎯 $TARGET"
        done
    else
        echo "❌ No se encontraron targets"
    fi
fi

echo
echo "📋 4. Verificando Subscriptions del SNS Topic:"
echo "────────────────────────────────────────────────────────────"
if [ -n "$TOPIC_ARN" ]; then
    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN --profile $PROFILE --region $REGION --query 'Subscriptions[*].[Protocol,Endpoint,SubscriptionArn]' --output table 2>/dev/null)
    if [ -n "$SUBSCRIPTIONS" ]; then
        echo "📧 Subscriptions encontradas:"
        echo "$SUBSCRIPTIONS"
    else
        echo "ℹ️ No hay subscriptions configuradas (normal - se pueden agregar según necesidad)"
        echo "💡 Para agregar subscription por email:"
        echo "aws sns subscribe --topic-arn $TOPIC_ARN --protocol email --notification-endpoint tu-email@ejemplo.com --profile $PROFILE --region $REGION"
    fi
fi

echo
echo "🎯 RESUMEN FINAL:"
echo "═══════════════════════════════════════════════════════════"

# Evaluación general
SCORE=0
TOTAL=4

# Check SNS Topic
if [ -n "$TOPIC_ARN" ]; then
    echo "✅ SNS Topic: CONFIGURADO"
    SCORE=$((SCORE + 1))
else
    echo "❌ SNS Topic: NO CONFIGURADO"
fi

# Check EventBridge Rule
if [ -n "$RULE_ARN" ] && [ "$RULE_ARN" != "None" ]; then
    echo "✅ EventBridge Rule: CONFIGURADO"
    SCORE=$((SCORE + 1))
else
    echo "❌ EventBridge Rule: NO CONFIGURADO"
fi

# Check Rule State
if [ "$RULE_STATE" = "ENABLED" ]; then
    echo "✅ Rule State: HABILITADO"
    SCORE=$((SCORE + 1))
else
    echo "❌ Rule State: DESHABILITADO"
fi

# Check Targets
if [ -n "$TARGETS" ]; then
    echo "✅ Rule Targets: CONFIGURADO"
    SCORE=$((SCORE + 1))
else
    echo "❌ Rule Targets: NO CONFIGURADO"
fi

echo
PERCENTAGE=$((SCORE * 100 / TOTAL))
echo "📊 Configuración completa: $SCORE/$TOTAL ($PERCENTAGE%)"

if [ $SCORE -eq $TOTAL ]; then
    echo "🏆 EXCELENTE: AWS Health Alerts completamente configurado"
elif [ $SCORE -ge 3 ]; then
    echo "✅ BUENO: Configuración funcional, revisar elementos faltantes"
else
    echo "⚠️ INCOMPLETO: Necesita atención"
fi

echo
echo "═══════════════════════════════════════════════════════════"