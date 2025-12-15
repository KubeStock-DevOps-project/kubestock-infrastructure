"""
Lambda function to refresh Kubernetes join token via SSM Run Command.

This function:
1. Runs 'kubeadm token create' on the control plane via SSM Run Command
2. Updates the SSM Parameter Store with the new token
3. Logs the operation for auditing

Triggered by CloudWatch Events every 12 hours.
"""

import json
import boto3
import time
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Clients
ssm = boto3.client('ssm')
ec2 = boto3.client('ec2')


def get_control_plane_instance_id():
    """Find the control plane instance by tag."""
    response = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Name', 'Values': ['kubestock-control-plane']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )
    
    for reservation in response['Reservations']:
        for instance in reservation['Instances']:
            return instance['InstanceId']
    
    raise Exception("Control plane instance not found or not running")


def run_command_on_instance(instance_id, command):
    """Execute command on instance via SSM Run Command and wait for result."""
    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName='AWS-RunShellScript',
        Parameters={'commands': [command]},
        TimeoutSeconds=60
    )
    
    command_id = response['Command']['CommandId']
    logger.info(f"SSM command initiated: {command_id}")
    
    # Wait for command to complete
    max_attempts = 30
    for attempt in range(max_attempts):
        time.sleep(2)
        
        result = ssm.get_command_invocation(
            CommandId=command_id,
            InstanceId=instance_id
        )
        
        status = result['Status']
        if status == 'Success':
            return result['StandardOutputContent'].strip()
        elif status in ['Failed', 'Cancelled', 'TimedOut']:
            error_msg = result.get('StandardErrorContent', 'Unknown error')
            raise Exception(f"Command failed with status {status}: {error_msg}")
        
        logger.info(f"Waiting for command completion... attempt {attempt + 1}/{max_attempts}")
    
    raise Exception("Command timed out waiting for completion")


def handler(event, context):
    """Lambda handler to refresh Kubernetes join token."""
    logger.info("Starting token refresh...")
    
    try:
        # Get control plane instance ID
        instance_id = get_control_plane_instance_id()
        logger.info(f"Found control plane instance: {instance_id}")
        
        # Create new token via SSM Run Command
        new_token = run_command_on_instance(
            instance_id,
            'sudo kubeadm token create'
        )
        
        if not new_token or len(new_token) < 20:
            raise Exception(f"Invalid token received: {new_token}")
        
        logger.info(f"New token created (first 6 chars): {new_token[:6]}...")
        
        # Update SSM Parameter
        ssm.put_parameter(
            Name='/kubestock/join-token',
            Value=new_token,
            Type='SecureString',
            Overwrite=True,
            Description=f'Kubernetes join token - refreshed by Lambda'
        )
        
        logger.info("SSM parameter updated successfully")
        
        # Clean up old tokens (keep last 2)
        cleanup_result = run_command_on_instance(
            instance_id,
            'sudo kubeadm token list -o jsonpath="{.token}" 2>/dev/null | wc -w || echo "0"'
        )
        logger.info(f"Active tokens count: {cleanup_result}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Token refreshed successfully',
                'tokenPrefix': new_token[:6],
                'instanceId': instance_id
            })
        }
        
    except Exception as e:
        logger.error(f"Token refresh failed: {str(e)}")
        raise
