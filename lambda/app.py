import json, os, time, io
import boto3
import pyqrcode

TABLE_NAME = os.environ["TABLE_NAME"]
QR_BUCKET  = os.environ["QR_BUCKET"]

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)
s3 = boto3.client("s3")

def handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path   = event.get("requestContext", {}).get("http", {}).get("path", "/")

    if path == "/urls" and method == "POST":
        body = json.loads(event.get("body") or "{}")
        target_url = body.get("url")
        code = body.get("code") or str(int(time.time()))

        item = {
            "userId": "demo",
            "shortCode": code,
            "targetUrl": target_url,
            "createdAt": int(time.time())
        }
        table.put_item(Item=item)

        qr = pyqrcode.create(target_url)
        buffer = io.BytesIO()
        qr.png(buffer, scale=6)
        s3.put_object(Bucket=QR_BUCKET, Key=f"{code}.png", Body=buffer.getvalue(), ContentType="image/png")

        return {"statusCode": 200, "body": json.dumps({"code": code})}

    return {"statusCode": 404, "body": "Not Found"}
