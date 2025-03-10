import boto3
import os
import json

from time import sleep
import logging
import asyncio

import maigret
from maigret.result import MaigretCheckStatus
from maigret.sites import MaigretDatabase


QUEUE_URL = os.getenv("SQS_QUEUE_URL", "not_found")

sqs = boto3.client("sqs", region_name="us-east-1")
dynamodb_resource = boto3.resource("dynamodb", region_name="us-east-1")

MAIGRET_DB_FILE_URL = (
    "https://raw.githubusercontent.com/soxoj/maigret/main/maigret/resources/data.json"
)


def setup_logger(log_level, name):
    logger = logging.getLogger(name)
    logger.setLevel(log_level)
    return logger


async def maigret_search(username):
    logger = setup_logger(logging.WARNING, "maigret")

    db = MaigretDatabase().load_from_http(MAIGRET_DB_FILE_URL)

    sites = db.ranked_sites_dict(top=1500)

    results = await maigret.search(
        username=username,
        site_dict=sites,
        timeout=30,
        logger=logger,
        id_type="username",
    )
    return results


async def receive_messages():
    while True:
        try:
            response = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=1,
                WaitTimeSeconds=10,
                VisibilityTimeout=30,
            )

            messages = response.get("Messages", [])

            if not messages:
                logging.info("No events to consume")
                sleep(10)

                continue

            for message in messages:
                content = json.loads(message["Body"])

                username = content["username"]
                job_id = content["job_id"]

                logging.info(f"Received message: {content}")

                results = await maigret_search(username)

                report = ""
                for site, data in results.items():

                    if data["status"].status != MaigretCheckStatus.CLAIMED:
                        continue

                    url = data["url_user"]
                    account_link = f"[{site}]({url})"

                    if not data.get("is_similar"):
                        report += f"{account_link}\n"

                table = dynamodb_resource.Table("Jobs")
                response = table.get_item(Key={"job_id": job_id})
                item = response.get("Item")

                if item:
                    item["status"] = "COMPLETED"
                    item["description"] = report
                    table.put_item(Item=item) 

                sqs.delete_message(
                    QueueUrl=QUEUE_URL, ReceiptHandle=message["ReceiptHandle"]
                )

        except Exception as e:
            logging.info(e)


if __name__ == "__main__":

    logging.basicConfig(
        format="[%(filename)s:%(lineno)d] %(levelname)-3s  %(asctime)s      %(message)s",
        datefmt="%H:%M:%S",
        level=logging.INFO,
    )

    asyncio.run(receive_messages())
