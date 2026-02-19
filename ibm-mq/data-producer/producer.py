#!/usr/bin/env python3
"""
Continuous Random Data Stream Producer for IBM MQ
Generates random transaction data and publishes to MQ queue
"""

import json
import random
import time
import os
from datetime import datetime
from faker import Faker
import pymqi

# Configuration from environment variables
MQ_HOST = os.getenv('MQ_HOST', 'ibm-mq.mq-kafka-integration.svc.cluster.local')
MQ_PORT = os.getenv('MQ_PORT', '1414')
MQ_QUEUE_MANAGER = os.getenv('MQ_QUEUE_MANAGER', 'QM1')
MQ_CHANNEL = os.getenv('MQ_CHANNEL', 'DEV.APP.SVRCONN')
MQ_QUEUE = os.getenv('MQ_QUEUE', 'KAFKA.IN')
MQ_USER = os.getenv('MQ_USER', 'app')
MQ_PASSWORD = os.getenv('MQ_PASSWORD', 'passw0rd')
MESSAGE_INTERVAL = int(os.getenv('MESSAGE_INTERVAL', '5'))  # seconds

fake = Faker()

def generate_transaction():
    """Generate random transaction data"""
    transaction_types = ['purchase', 'refund', 'payment', 'transfer', 'deposit', 'withdrawal']
    categories = ['electronics', 'clothing', 'food', 'services', 'utilities', 'entertainment']
    statuses = ['completed', 'pending', 'failed', 'processing']
    
    return {
        "transaction_id": fake.uuid4(),
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "customer_id": f"CUST-{random.randint(10000, 99999)}",
        "customer_name": fake.name(),
        "customer_email": fake.email(),
        "transaction_type": random.choice(transaction_types),
        "category": random.choice(categories),
        "amount": round(random.uniform(10.0, 5000.0), 2),
        "currency": random.choice(['USD', 'EUR', 'GBP']),
        "status": random.choice(statuses),
        "merchant_id": f"MERCH-{random.randint(1000, 9999)}",
        "merchant_name": fake.company(),
        "location": {
            "city": fake.city(),
            "country": fake.country(),
            "latitude": float(fake.latitude()),
            "longitude": float(fake.longitude())
        },
        "payment_method": random.choice(['credit_card', 'debit_card', 'paypal', 'bank_transfer', 'cash']),
        "device_type": random.choice(['mobile', 'web', 'pos', 'atm']),
        "ip_address": fake.ipv4(),
        "user_agent": fake.user_agent(),
        "metadata": {
            "session_id": fake.uuid4(),
            "referrer": fake.url(),
            "campaign_id": f"CAMP-{random.randint(100, 999)}"
        }
    }

def connect_to_mq():
    """Establish connection to IBM MQ"""
    print(f"Connecting to MQ: {MQ_HOST}:{MQ_PORT}")
    print(f"Queue Manager: {MQ_QUEUE_MANAGER}, Channel: {MQ_CHANNEL}")
    
    conn_info = f"{MQ_HOST}({MQ_PORT})"
    
    qmgr = pymqi.connect(
        MQ_QUEUE_MANAGER,
        MQ_CHANNEL,
        conn_info,
        MQ_USER,
        MQ_PASSWORD
    )
    
    print(f"✅ Connected to Queue Manager: {MQ_QUEUE_MANAGER}")
    return qmgr

def send_message(qmgr, queue_name, message_data):
    """Send a message to MQ queue"""
    queue = pymqi.Queue(qmgr, queue_name)
    
    # Convert to JSON string
    message_json = json.dumps(message_data, indent=2)
    
    # Put message to queue
    queue.put(message_json.encode('utf-8'))
    
    queue.close()
    return message_json

def main():
    """Main producer loop"""
    print("=" * 80)
    print("IBM MQ Random Data Stream Producer")
    print("=" * 80)
    print(f"Target Queue: {MQ_QUEUE}")
    print(f"Message Interval: {MESSAGE_INTERVAL} seconds")
    print("=" * 80)
    print()
    
    # Connect to MQ
    try:
        qmgr = connect_to_mq()
    except Exception as e:
        print(f"❌ Failed to connect to MQ: {e}")
        return
    
    message_count = 0
    
    try:
        while True:
            # Generate random transaction
            transaction = generate_transaction()
            
            # Send to MQ
            try:
                message_json = send_message(qmgr, MQ_QUEUE, transaction)
                message_count += 1
                
                print(f"📤 Message #{message_count} sent at {transaction['timestamp']}")
                print(f"   Transaction ID: {transaction['transaction_id']}")
                print(f"   Type: {transaction['transaction_type']} | Amount: {transaction['currency']} {transaction['amount']}")
                print(f"   Customer: {transaction['customer_name']} ({transaction['customer_id']})")
                print(f"   Status: {transaction['status']}")
                print("-" * 80)
                
            except Exception as e:
                print(f"❌ Failed to send message: {e}")
            
            # Wait before sending next message
            time.sleep(MESSAGE_INTERVAL)
            
    except KeyboardInterrupt:
        print("\n\n⚠️  Producer stopped by user")
    except Exception as e:
        print(f"\n❌ Error in producer loop: {e}")
    finally:
        try:
            qmgr.disconnect()
            print(f"\n✅ Disconnected from MQ. Total messages sent: {message_count}")
        except:
            pass

if __name__ == "__main__":
    main()
