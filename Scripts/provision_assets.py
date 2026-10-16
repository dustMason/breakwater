#!/usr/bin/env python3
"""Create a dedicated, public-read-only S3 bucket for the asset library."""
import json
import os
import re

import boto3


def main():
    bucket = os.environ.get("BREAKWATER_ASSET_BUCKET", "")
    account = os.environ.get("BREAKWATER_AWS_ACCOUNT_ID", "")
    region = os.environ.get("BREAKWATER_AWS_REGION", "us-west-2")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", bucket):
        raise ValueError("Set a valid BREAKWATER_ASSET_BUCKET")
    if not re.fullmatch(r"\d{12}", account):
        raise ValueError("Set the 12-digit BREAKWATER_AWS_ACCOUNT_ID")
    # In us-east-1, CreateBucket can succeed for a bucket already owned by the
    # caller and reset its ACL. Refuse that special case rather than risk
    # modifying any existing bucket.
    if region == "us-east-1":
        raise ValueError("Choose a region other than us-east-1 for a new asset bucket")
    session = boto3.Session(region_name=region)
    if session.client("sts").get_caller_identity()["Account"] != account:
        raise RuntimeError("AWS credentials do not match BREAKWATER_AWS_ACCOUNT_ID")
    s3 = session.client("s3")
    arguments = {"Bucket": bucket}
    if region != "us-east-1":
        arguments["CreateBucketConfiguration"] = {"LocationConstraint": region}
    # Creation must succeed; never modify a pre-existing bucket.
    s3.create_bucket(**arguments)
    s3.put_public_access_block(Bucket=bucket, ExpectedBucketOwner=account,
        PublicAccessBlockConfiguration={"BlockPublicAcls": True, "IgnorePublicAcls": True,
                                        "BlockPublicPolicy": False, "RestrictPublicBuckets": False})
    s3.put_bucket_cors(Bucket=bucket, ExpectedBucketOwner=account, CORSConfiguration={
        "CORSRules": [{"AllowedOrigins": ["*"], "AllowedMethods": ["GET", "HEAD"],
                       "AllowedHeaders": ["Range"], "MaxAgeSeconds": 86400}]})
    policy = {"Version": "2012-10-17", "Statement": [{
        "Sid": "ReadPublishedAssets", "Effect": "Allow", "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": [f"arn:aws:s3:::{bucket}/catalog.json", f"arn:aws:s3:::{bucket}/objects/*"],
    }]}
    s3.put_bucket_policy(Bucket=bucket, ExpectedBucketOwner=account, Policy=json.dumps(policy))
    print("Created the asset bucket with read-only access to published objects.")


if __name__ == "__main__":
    main()
