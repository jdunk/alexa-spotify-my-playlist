#!/bin/bash
set -euo pipefail

ROLE_NAME="lambda-my-playlist-exec-role"
TRUST_POLICY_FILE="lambda-trust-policy.json"
POLICY_ARN="arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

# 1. Write trust policy
cat > "$TRUST_POLICY_FILE" <<EOF
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

# 2. Create the IAM role
echo "🛠️  Creating IAM role: $ROLE_NAME"
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file://"$TRUST_POLICY_FILE"

# 3. Attach CloudWatch Logs policy
echo "🔗 Attaching AWSLambdaBasicExecutionRole policy"
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "$POLICY_ARN"

# 4. Fetch and print the role ARN
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
echo "✅ Role created: $LAMBDA_ROLE_ARN"

# 5. Cleanup
rm "$TRUST_POLICY_FILE"

# 6. Export (optional)
echo "📤 Exporting LAMBDA_ROLE_ARN for use in deployment..."
echo "export LAMBDA_ROLE_ARN=$LAMBDA_ROLE_ARN"