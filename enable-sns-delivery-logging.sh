#!/bin/bash
# enable-sns-delivery-logging-fixed.sh
# Habilita Delivery Logging solo en subscriptions válidas soportadas

PROFILE="xxxxxxx"
REGION="us-east-1"

echo "=== Habilitando SNS Delivery Logging en todas las subscriptions ==="
echo "Perfil: $PROFILE | Región: $REGION"

TOPICS=$(aws sns list-topics --profile $PROFILE --region $REGION --query 'Topics[*].TopicArn' --output text)

for TOPIC_ARN in $TOPICS; do
    echo "-> Topic: $TOPIC_ARN"

    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
        --topic-arn $TOPIC_ARN \
        --profile $PROFILE \
        --region $REGION \
        --query 'Subscriptions[*].SubscriptionArn' \
        --output text)

    if [ -z "$SUBSCRIPTIONS" ]; then
        echo "   ⚠ No hay subscriptions"
        continue
    fi

    for SUB_ARN in $SUBSCRIPTIONS; do
        # Validar que el ARN tenga al menos 6 elementos separados por ":"
        if [ $(echo "$SUB_ARN" | awk -F: '{print NF}') -lt 6 ]; then
            echo "   ⚠ ARN inválido: $SUB_ARN. Se omite."
            continue
        fi

        PROTOCOL=$(aws sns get-subscription-attributes \
            --subscription-arn $SUB_ARN \
            --profile $PROFILE \
            --region $REGION \
            --query 'Attributes.Protocol' \
            --output text)

        if [[ "$PROTOCOL" =~ ^(sqs|lambda|http|https)$ ]]; then
            POLICY='{
                "healthyRetryPolicy": {
                    "numRetries": 5,
                    "minDelayTarget": 20,
                    "maxDelayTarget": 20,
                    "numMaxDelayRetries": 0,
                    "numNoDelayRetries": 0,
                    "numMinDelayRetries": 0,
                    "backoffFunction": "linear"
                }
            }'

            aws sns set-subscription-attributes \
                --subscription-arn $SUB_ARN \
                --attribute-name DeliveryPolicy \
                --attribute-value "$POLICY" \
                --profile $PROFILE \
                --region $REGION

            echo "   ✔ Logging habilitado para subscription: $SUB_ARN ($PROTOCOL)"
        else
            echo "   ⚠ Protocolo $PROTOCOL no soporta DeliveryPolicy. Se omite."
        fi
    done
done

echo "=== Proceso completado ✅ ==="

