#!/bin/bash
API_URL=$(terraform output -raw api_endpoint)

# Generate 1000 records in parallel batches
echo "Generating test data..."
for i in {1..20}; do
  curl -X POST $API_URL \
    -H "Content-Type: application/json" \
    -d '{"num_records": 50}' \
    --silent --output /dev/null &
done

wait
echo "Generated 1000 records"