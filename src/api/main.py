import boto3
import json
import os
import uuid

import logging
import json

sqs = boto3.client("sqs")
cognito = boto3.client("cognito-idp")
dynamodb_resource = boto3.resource("dynamodb")

QUEUE_URL = os.getenv("SQS_QUEUE_URL")
CLIENT_ID = os.getenv("COGNITO_CLIENT_ID")
USERPOOL_ID = os.getenv("COGNITO_USERPOOL_ID")


def get_entry_from_username(username):
    table = dynamodb_resource.Table("Jobs")

    if not table:
        None

    response = table.scan(
        FilterExpression=boto3.dynamodb.conditions.Attr("username").eq(username)
    )
    
    return response.get("Items", [])

def get_jobs(event, context):
    logging.error("get_job")

    query_params = event.get("queryStringParameters", {})

    username = query_params.get("username", None)

    if username is None:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "username is required"}),
        }

    res = get_entry_from_username(username)

    if res == None:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": "Unexpected error"}),
        }
    else:
        return {
            "statusCode": 200,
            "body": json.dumps(res),
        }


def create_job(event, context):
    logging.error("create_job")

    try:
        body = json.loads(event["body"])
        username = body.get("username")

        if username is None:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "username is required"}),
            }
        
        res = get_entry_from_username(username)

        if res is None:
            return {
                "statusCode": 500,
                "body": json.dumps({"error": "Unexpected error"}),
            }

        elif len(res) == 0:        
            table = dynamodb_resource.Table("Jobs")

            entry = {"job_id": str(uuid.uuid4()), "username": username, "status": "CREATED"}

            table.put_item(
                Item=entry
            )

            sqs.send_message(
                QueueUrl=QUEUE_URL,
                MessageBody=json.dumps(entry),
            )

        return {
            "statusCode": 200,
            "body": json.dumps({"message": "Job enqueued successfully"}),
        }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": f"Internal Server Error"}),
        }


def login(event, context):
    try:
        body = json.loads(event["body"])
        username = body["username"]
        password = body["password"]

        # Authenticate user using Cognito
        response = cognito.initiate_auth(
            AuthFlow="USER_PASSWORD_AUTH",
            ClientId=CLIENT_ID,
            AuthParameters={"USERNAME": username, "PASSWORD": password},
        )

        # Return authentication tokens
        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "access_token": response["AuthenticationResult"]["AccessToken"],
                    "id_token": response["AuthenticationResult"]["IdToken"],
                    "refresh_token": response["AuthenticationResult"]["RefreshToken"],
                    "expires_in": response["AuthenticationResult"]["ExpiresIn"],
                    "token_type": response["AuthenticationResult"]["TokenType"],
                }
            ),
        }

    except cognito.exceptions.NotAuthorizedException:
        return {
            "statusCode": 401,
            "body": json.dumps({"error": "Invalid username or password."}),
        }

    except cognito.exceptions.UserNotFoundException:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": "User does not exist."}),
        }

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


def register(event, context):
    try:
        body = json.loads(event["body"])
        username = body["username"]
        password = body["password"]
        email = body["email"]

        response = cognito.sign_up(
            ClientId=CLIENT_ID,
            Username=username,
            Password=password,
            UserAttributes=[{"Name": "email", "Value": email}],
        )

        cognito.admin_confirm_sign_up(UserPoolId=USERPOOL_ID, Username=username)

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "message": "User registered successfully!",
                    "user_id": response["UserSub"],
                }
            ),
        }

    except cognito.exceptions.UsernameExistsException:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Username already exists."}),
        }

    except cognito.exceptions.InvalidPasswordException:
        return {
            "statusCode": 400,
            "body": json.dumps(
                {"error": "Password does not meet policy requirements."}
            ),
        }

    except Exception as e:
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


routes = {
    "/jobs": {
        "GET": get_jobs,
        "POST": create_job,
    },
    "/login": {"POST": login},
    "/signup": {"POST": register},
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
