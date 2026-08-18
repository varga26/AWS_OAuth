import os
import requests
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

cloudwatch = boto3.client('cloudwatch')
URL = os.environ.get('URL_TO_CHECK', '')

def check_url(url: str) -> bool:
    try:
        response = requests.get(url, headers={'User-Agent': 'Mozilla/5.0'}, timeout=10)
        return response.status_code == 200
    except requests.exceptions.RequestException as e:
        logger.error(f"URL Check failed: {e}")
        return False

def put_cloudwatch_metric(is_up: bool, function_name: str):
    metric_value = 0 if is_up else 1
    try:
        cloudwatch.put_metric_data(
            Namespace='Custom/HealthCheck',
            MetricData=[
                {
                    'MetricName': 'HealthCheckStatus',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': function_name
                        },
                    ],
                    'Value': metric_value,
                    'Unit': 'Count'
                },
            ]
        )
        logger.info(f"Sent metric HealthCheckStatus={metric_value} to CloudWatch")
    except Exception as e:
        logger.error(f"Failed to send CloudWatch metric: {e}", exc_info=True)

def lambda_handler(event, context):
    if not URL:
        logger.error("Environment variable URL_TO_CHECK is empty or not set!")
        return {"status": "error", "message": "Missing URL"}

    logger.info(f"Checking URL: {URL}")
    is_up = check_url(URL)
    
    if is_up:
        logger.info("Site is UP.")
    else:
        logger.warning("Site is DOWN.")
        
    put_cloudwatch_metric(is_up, context.function_name)
    return {
        "status": "success",
        "is_up": is_up
    }