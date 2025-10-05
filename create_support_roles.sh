#!/bin/bash
PROFILE="azcenit"
REGION="us-east-1"
ROLE_NAME="AWS-TrustedSupportAccess"

echo "=== Creando IAM Support Role: $ROLE_NAME ==="

aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": { "Service": "support.amazonaws.com" },
        "Action": "sts:AssumeRole"
      }
    ]
  }' \
  --description "Role that grants AWS Support limited access to help troubleshoot issues" \
  --max-session-duration 3600 \
  --profile "$PROFILE" \
  --region "$REGION"

echo "=== Adjuntando política administrada AWSSupportAccess ==="

aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/AWSSupportAccess \
  --profile "$PROFILE" \
  --region "$REGION"

echo "=== Rol $ROLE_NAME creado y con política AWSSupportAccess adjunta ==="

