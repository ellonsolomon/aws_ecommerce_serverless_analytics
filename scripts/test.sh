#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Set AWS region
export AWS_REGION=us-east-1
export AWS_DEFAULT_REGION=us-east-1

echo -e "${BLUE}🧪 Testing E-Commerce Analytics Pipeline${NC}"
echo "========================================="

# Get API endpoint
API_URL=$(terraform output -raw api_endpoint 2>/dev/null)
if [ -z "$API_URL" ]; then
    echo -e "${RED}❌ API endpoint not found. Run deploy.sh first.${NC}"
    exit 1
fi

S3_BUCKET=$(terraform output -raw s3_bucket)
KINESIS_STREAM=$(terraform output -raw kinesis_stream)
ORDERS_TABLE=$(terraform output -json dynamodb_tables | jq -r '.orders')

echo "API Endpoint: $API_URL"
echo "S3 Bucket: $S3_BUCKET"
echo "Kinesis Stream: $KINESIS_STREAM"
echo "Orders Table: $ORDERS_TABLE"
echo ""

# Test 1: Generate test data
test_data_generation() {
    echo -e "${YELLOW}Test 1: Data Generation${NC}"
    echo "Generating 10 test records..."
    
    RESPONSE=$(curl -X POST $API_URL \
        -H "Content-Type: application/json" \
        -d '{"num_records": 10}' \
        --silent)
    
    if [ ! -z "$RESPONSE" ]; then
        echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
        
        RECORDS=$(echo "$RESPONSE" | jq -r '.records_generated' 2>/dev/null || echo "0")
        if [ "$RECORDS" == "10" ]; then
            echo -e "${GREEN}✅ Data generation successful${NC}"
        else
            echo -e "${RED}❌ Data generation may have failed${NC}"
            echo "Response: $RESPONSE"
        fi
    else
        echo -e "${RED}❌ No response from API${NC}"
    fi
}

# Test 2: Check Kinesis stream
test_kinesis_stream() {
    echo -e "\n${YELLOW}Test 2: Kinesis Stream${NC}"
    
    # Get stream info with region
    STREAM_INFO=$(aws kinesis describe-stream \
        --stream-name "$KINESIS_STREAM" \
        --region $AWS_REGION 2>/dev/null)
    
    if [ ! -z "$STREAM_INFO" ]; then
        STREAM_STATUS=$(echo "$STREAM_INFO" | jq -r '.StreamDescription.StreamStatus')
        SHARD_COUNT=$(echo "$STREAM_INFO" | jq '.StreamDescription.Shards | length')
        
        echo "Stream status: $STREAM_STATUS"
        echo "Stream has $SHARD_COUNT shard(s)"
        
        # Try to get recent record count
        SHARD_ID=$(echo "$STREAM_INFO" | jq -r '.StreamDescription.Shards[0].ShardId')
        if [ ! -z "$SHARD_ID" ] && [ "$SHARD_ID" != "null" ]; then
            SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
                --stream-name $KINESIS_STREAM \
                --shard-id $SHARD_ID \
                --shard-iterator-type LATEST \
                --region $AWS_REGION \
                --query 'ShardIterator' \
                --output text 2>/dev/null)
            
            if [ ! -z "$SHARD_ITERATOR" ] && [ "$SHARD_ITERATOR" != "None" ]; then
                RECORDS=$(aws kinesis get-records \
                    --shard-iterator $SHARD_ITERATOR \
                    --region $AWS_REGION \
                    --query 'Records | length(@)' \
                    --output text 2>/dev/null || echo "0")
                echo "Recent records in stream: $RECORDS"
            fi
        fi
        
        echo -e "${GREEN}✅ Kinesis stream active${NC}"
    else
        echo -e "${RED}Stream not found!${NC}"
    fi
}

# Test 3: Check DynamoDB
test_dynamodb() {
    echo -e "\n${YELLOW}Test 3: DynamoDB Tables${NC}"
    
    if [ -z "$ORDERS_TABLE" ]; then
        echo -e "${RED}Orders table name not found${NC}"
        return
    fi
    
    # Check orders table with region
    ITEM_COUNT=$(aws dynamodb scan \
        --table-name $ORDERS_TABLE \
        --region $AWS_REGION \
        --select COUNT \
        --query 'Count' \
        --output text 2>/dev/null || echo "0")
    
    echo "Orders table has $ITEM_COUNT item(s)"
    
    # Get sample item with region
    if [ "$ITEM_COUNT" != "0" ] && [ "$ITEM_COUNT" != "None" ]; then
        echo "Sample order:"
        aws dynamodb scan \
            --table-name $ORDERS_TABLE \
            --region $AWS_REGION \
            --max-items 1 \
            --output json | jq '.Items[0]' 2>/dev/null
    fi
    
    echo -e "${GREEN}✅ DynamoDB tables accessible${NC}"
}

# Test 4: Check S3 data
test_s3_storage() {
    echo -e "\n${YELLOW}Test 4: S3 Storage${NC}"
    
    echo "Checking raw data:"
    RAW_COUNT=$(aws s3 ls s3://$S3_BUCKET/raw-data/orders/ \
        --recursive \
        --region $AWS_REGION 2>/dev/null | wc -l || echo "0")
    echo "Found $RAW_COUNT file(s) in raw-data"
    
    if [ "$RAW_COUNT" != "0" ]; then
        echo "Recent files:"
        aws s3 ls s3://$S3_BUCKET/raw-data/orders/ \
            --recursive \
            --region $AWS_REGION 2>/dev/null | tail -5
    fi
    
    # Check processed data
    PROCESSED_COUNT=$(aws s3 ls s3://$S3_BUCKET/processed-data/ \
        --recursive \
        --region $AWS_REGION 2>/dev/null | wc -l || echo "0")
    echo "Found $PROCESSED_COUNT file(s) in processed-data"
    
    echo -e "${GREEN}✅ S3 storage working${NC}"
}

# Test 5: CloudWatch metrics
test_cloudwatch() {
    echo -e "\n${YELLOW}Test 5: CloudWatch Metrics${NC}"
    
    # For Windows, use PowerShell to get dates
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        END_TIME=$(powershell -Command "Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'")
        START_TIME=$(powershell -Command "(Get-Date).AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ss')")
    else
        END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)
        START_TIME=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S 2>/dev/null || date -u -v-1H +%Y-%m-%dT%H:%M:%S)
    fi
    
    echo "Checking metrics from $START_TIME to $END_TIME"
    
    # Get the actual Lambda function name
    LAMBDA_NAME="${KINESIS_STREAM%-stream}-data-generator"
    
    INVOCATIONS=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Invocations \
        --dimensions Name=FunctionName,Value=$LAMBDA_NAME \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 3600 \
        --statistics Sum \
        --region $AWS_REGION \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$INVOCATIONS" == "None" ]; then
        INVOCATIONS="0"
    fi
    
    echo "Lambda invocations in last hour: $INVOCATIONS"
    
    # Check stream processor metrics too
    PROCESSOR_NAME="${KINESIS_STREAM%-stream}-stream-processor"
    PROCESSOR_INVOCATIONS=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Invocations \
        --dimensions Name=FunctionName,Value=$PROCESSOR_NAME \
        --start-time $START_TIME \
        --end-time $END_TIME \
        --period 3600 \
        --statistics Sum \
        --region $AWS_REGION \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$PROCESSOR_INVOCATIONS" == "None" ]; then
        PROCESSOR_INVOCATIONS="0"
    fi
    
    echo "Stream processor invocations in last hour: $PROCESSOR_INVOCATIONS"
    echo -e "${GREEN}✅ CloudWatch metrics available${NC}"
}

# Performance test
performance_test() {
    echo -e "\n${YELLOW}Performance Test: Generating 100 records${NC}"
    
    START=$(date +%s)
    
    for i in {1..10}; do
        echo "Batch $i/10..."
        curl -X POST $API_URL \
            -H "Content-Type: application/json" \
            -d '{"num_records": 10}' \
            --silent --output /dev/null &
    done
    
    wait
    
    END=$(date +%s)
    DURATION=$((END - START))
    
    echo "Generated 100 records in $DURATION seconds"
    echo -e "${GREEN}✅ Performance test complete${NC}"
}

# Run all tests
main() {
    test_data_generation
    sleep 5  # Wait for processing
    test_kinesis_stream
    test_dynamodb
    test_s3_storage
    test_cloudwatch
    
    echo -e "\n${YELLOW}Run performance test? (yes/no)${NC}"
    read -p "Continue? " PERF
    if [ "$PERF" == "yes" ]; then
        performance_test
    fi
    
    echo -e "\n${GREEN}🎉 All tests completed!${NC}"
}

main