import json
import boto3
import random
from datetime import datetime, timedelta
from decimal import Decimal
import uuid
import os


def lambda_handler(event, context):
    """
    Lambda function to generate synthetic e-commerce data and send to Kinesis
    """
    # Initialize AWS services
    kinesis = boto3.client('kinesis')
    dynamodb = boto3.resource('dynamodb')

    # Get environment variables
    stream_name = os.environ['KINESIS_STREAM_NAME']
    orders_table_name = os.environ.get('DYNAMODB_ORDERS_TABLE')
    customers_table_name = os.environ.get('DYNAMODB_CUSTOMERS_TABLE')

    # Sample data for generation
    products = [
        'Laptop', 'Smartphone', 'Tablet', 'Headphones', 'Smartwatch',
        'Camera', 'Keyboard', 'Mouse', 'Monitor', 'Speaker',
        'USB Drive', 'External HDD', 'Webcam', 'Microphone', 'Router',
        'Printer', 'Scanner', 'Desk Lamp', 'Power Bank', 'Cable Set'
    ]

    categories = [
        'Electronics', 'Computers', 'Accessories', 'Audio', 'Networking',
        'Storage', 'Mobile', 'Gaming', 'Office', 'Smart Home'
    ]

    locations = ['NY', 'CA', 'TX', 'FL', 'IL', 'PA', 'OH', 'GA', 'NC', 'MI']

    payment_methods = ['Credit Card', 'Debit Card',
                       'PayPal', 'Apple Pay', 'Google Pay', 'Amazon Pay']
    shipping_methods = ['Standard', 'Express',
                        'Next Day', 'Two Day', 'Economy']
    device_types = ['Mobile', 'Desktop', 'Tablet', 'App iOS', 'App Android']

    # Generate customer if needed
    customers_table = dynamodb.Table(
        customers_table_name) if customers_table_name else None

    records_generated = 0
    errors = []

    # Parse event body if it's from API Gateway
    try:
        if 'body' in event and event['body']:
            body = json.loads(event['body'])
            num_records = int(body.get('num_records', 10))
        else:
            num_records = int(event.get('num_records', 10))
    except:
        num_records = 10

    # Limit records per invocation
    num_records = min(num_records, 100)

    for i in range(num_records):
        try:
            # Generate customer data
            customer_id = f'cust_{random.randint(1000, 9999)}'
            customer_age = random.randint(18, 70)
            customer_location = random.choice(locations)

            # Store customer if table exists
            if customers_table:
                customer_data = {
                    'customer_id': customer_id,
                    'age': customer_age,
                    'location': customer_location,
                    'created_date': datetime.now().isoformat(),
                    'loyalty_tier': random.choice(['Bronze', 'Silver', 'Gold', 'Platinum']),
                    'email': f'{customer_id}@example.com',
                    'total_purchases': 0,
                    'last_purchase_date': datetime.now().isoformat()
                }
                try:
                    customers_table.put_item(Item=customer_data)
                except Exception as e:
                    print(f"Error storing customer: {str(e)}")

            # Generate order data
            product = random.choice(products)
            category = random.choice(categories)
            quantity = random.randint(1, 5)
            base_price = round(random.uniform(10, 2000), 2)
            discount_percentage = random.choice([0, 5, 10, 15, 20, 25])

            # Calculate prices
            subtotal = round(base_price * quantity, 2)
            discount_amount = round(subtotal * (discount_percentage / 100), 2)
            total_amount = round(subtotal - discount_amount, 2)

            # Generate timestamps with some variation
            order_date = datetime.now() - timedelta(
                days=random.randint(0, 7),
                hours=random.randint(0, 23),
                minutes=random.randint(0, 59)
            )

            order = {
                'order_id': str(uuid.uuid4()),
                'customer_id': customer_id,
                'product_name': product,
                'category': category,
                'quantity': quantity,
                'price': base_price,
                'subtotal': subtotal,
                'discount_percentage': discount_percentage,
                'discount_amount': discount_amount,
                'total_amount': total_amount,
                'order_date': order_date.isoformat(),
                'customer_age': customer_age,
                'customer_location': customer_location,
                'payment_method': random.choice(payment_methods),
                'shipping_method': random.choice(shipping_methods),
                'is_prime_member': random.choice([True, False]),
                'device_type': random.choice(device_types),
                'session_duration_seconds': random.randint(30, 1800),
                'items_viewed': random.randint(1, 20),
                'is_returning_customer': random.choice([True, False]),
                'referral_source': random.choice(['Direct', 'Google', 'Facebook', 'Email', 'Instagram']),
                'promo_code_used': random.choice([None, 'SAVE10', 'FREESHIP', 'WELCOME20']),
                'estimated_delivery_days': random.randint(2, 7)
            }

            # Send to Kinesis
            response = kinesis.put_record(
                StreamName=stream_name,
                Data=json.dumps(order, default=str),
                PartitionKey=order['customer_id']
            )

            records_generated += 1
            print(
                f"Sent order {order['order_id']} to Kinesis - Shard: {response.get('ShardId')}")

        except Exception as e:
            error_msg = f"Error generating record {i}: {str(e)}"
            print(error_msg)
            errors.append(error_msg)

    # Prepare response
    response_body = {
        'message': f'Successfully generated {records_generated} records',
        'records_generated': records_generated,
        'stream_name': stream_name,
        'timestamp': datetime.now().isoformat()
    }

    if errors:
        response_body['errors'] = errors[:10]  # Limit error messages

    return {
        'statusCode': 200 if records_generated > 0 else 500,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': json.dumps(response_body)
    }
