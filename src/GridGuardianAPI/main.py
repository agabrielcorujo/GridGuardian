
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from mangum import Mangum
import boto3
import os

app = FastAPI(title="GridGuardian API")

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(
    os.environ.get("TABLE_NAME", "GridGuardian")
)

class Report(BaseModel):
    zipcode: str
    condition: str
    timestamp: str


@app.get("/")
def root():
    return {"message": "GridGuardian API running!"}


@app.get("/health")
def health():
    return {"status": "healthy"}


@app.get("/reports/{zipcode}")
def get_reports(zipcode: str):
    response = table.query(
        KeyConditionExpression=boto3.dynamodb.conditions.Key(
            "zipcode"
        ).eq(zipcode)
    )
    return response["Items"]


@app.post("/reports")
def create_report(report: Report):
    item = {
        "zipcode": report.zipcode,
        "condition-timestamp": (
            f"{report.condition}#{report.timestamp}"
        ),
    }

    table.put_item(Item=item)
    return {"success": True, "report": item}


# This is the Lambda entry point
handler = Mangum(app)

