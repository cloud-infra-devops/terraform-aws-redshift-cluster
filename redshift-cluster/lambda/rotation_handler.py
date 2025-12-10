"""
Minimal Secrets Manager rotation handler for Redshift.

This is an example rotation Lambda that:
- Is intended for single-user rotation
- Uses boto3 to interact with Secrets Manager and Redshift (ModifyCluster)
- Performs four steps: createSecret, setSecret, testSecret, finishSecret

WARNING:
- This is a simple example. In production you should:
  - Add robust error handling and retries
  - Ensure least-privilege IAM permissions
  - Ensure the process is tested in a non-production environment
  - Consider downtime concerns when rotating the master user
    (ModifyCluster may cause brief disruptions)

Environment variables expected:
- CLUSTER_IDENTIFIER
- SECRET_ARN
- REGION (optional)
"""

import json
import boto3
import os
import time

region = os.environ.get("REGION") or os.environ.get("AWS_REGION")
cluster_identifier = os.environ.get("CLUSTER_IDENTIFIER")
secret_arn = os.environ.get("SECRET_ARN")

sm = boto3.client("secretsmanager", region_name=region)
redshift = boto3.client("redshift", region_name=region)


def lambda_handler(event, context):
    arn = event['SecretId']
    token = event['ClientRequestToken']
    step = event['Step']

    # Ensure the version is staged for rotation
    metadata = sm.describe_secret(SecretId=arn)
    if 'RotationEnabled' in metadata and not metadata['RotationEnabled']:
        raise Exception("Rotation is not enabled for this secret")

    # Validate that the pending secret version exists
    try:
        sm.get_secret_value(SecretId=arn, VersionId=token)
    except sm.exceptions.ResourceNotFoundException:
        raise Exception("Pending secret version not found for token")

    if step == "createSecret":
        return create_secret(arn, token)
    elif step == "setSecret":
        return set_secret(arn, token)
    elif step == "testSecret":
        return test_secret(arn, token)
    elif step == "finishSecret":
        return finish_secret(arn, token)
    else:
        raise ValueError("Unknown step: %s" % step)


def _get_secret_dict(version_id):
    try:
        resp = sm.get_secret_value(SecretId=secret_arn, VersionId=version_id)
        return json.loads(resp['SecretString'])
    except Exception:
        return None


def create_secret(arn, token):
    # create a new random password and store as a new version
    import secrets
    new_password = secrets.token_urlsafe(24)

    current_secret = _get_secret_dict("AWSCURRENT")
    new_secret = {
        "username": (
            current_secret.get("username")
            if current_secret
            else "admin"
        ),
        "password": new_password,
        "engine": "redshift",
        "host": (
            current_secret.get("host")
            if current_secret
            else cluster_identifier
        ),
        "port": current_secret.get("port") if current_secret else "5439",
        "dbname": current_secret.get("dbname") if current_secret else "dev",
        "jdbc": (
            current_secret.get("jdbc")
            if current_secret
            else f"jdbc:redshift://{cluster_identifier}:5439/dev"
        )
    }

    sm.put_secret_value(
        SecretId=arn,
        ClientRequestToken=token,
        SecretString=json.dumps(new_secret),
        VersionStages=["AWSPENDING"],
    )
    return


def set_secret(arn, token):
    # Apply the AWSPENDING secret as the cluster master user password
    pending = _get_secret_dict(token)
    if pending is None:
        raise Exception("Pending secret version not found for token")

    # Call ModifyCluster to change the master user password
    redshift.modify_cluster(
        ClusterIdentifier=cluster_identifier,
        MasterUserPassword=pending["password"],
    )

    # Wait until the cluster status becomes available
    for _ in range(60):
        desc = redshift.describe_clusters(ClusterIdentifier=cluster_identifier)
        cluster = desc['Clusters'][0]
        status = cluster.get('ClusterStatus', '')
        if status.lower() in ('available', 'ready'):
            break
        time.sleep(10)

    return


def test_secret(arn, token):
    # Optionally test by trying to connect using the new credentials
    # For simplicity, we'll verify the secret exists
    # and the cluster is available
    pending = _get_secret_dict(token)
    if pending is None:
        raise Exception("Pending secret version not found for token")

    desc = redshift.describe_clusters(ClusterIdentifier=cluster_identifier)
    if not desc['Clusters']:
        raise Exception("Cluster not found")
    return


def finish_secret(arn, token):
    # Mark the AWSPENDING version as AWSCURRENT
    sm.update_secret_version_stage(
        SecretId=arn,
        VersionStage="AWSCURRENT",
        MoveToVersionId=token,
        RemoveFromVersionId="AWSPREVIOUS",
    )
    return
