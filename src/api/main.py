import boto3
import json
import os

import logging
import json

sqs = boto3.client("sqs")
cognito = boto3.client("cognito-idp")

QUEUE_URL = os.getenv("SQS_QUEUE_URL")
CLIENT_ID = os.getenv("COGNITO_CLIENT_ID")
USERPOOL_ID = os.getenv("COGNITO_USERPOOL_ID")


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
