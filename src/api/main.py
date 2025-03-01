import boto3
import json
import os

import logging
import json

sqs = boto3.client("sqs")

QUEUE_URL = os.getenv("SQS_QUEUE_URL")


def get_jobs(event, context):
    logging.error("get_job")

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "GET request received"}),
    }


def create_job(event, context):
    logging.error("create_job")

    response = sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(event["body"]),
    )

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "POST request received"}),
    }


routes = {
    "/jobs": {
        "GET": get_jobs,
        "POST": create_job,
    }
}


def handle(event, context):

    method, path = event["routeKey"].split(" ")

    try:
        return routes[path][method](event, context)

    except KeyError:
        logging.error(f"Route {method} {path} not found")

        return {
            "statusCode": 404,
            "body": json.dumps({"message": "Not Found"}),
        }
