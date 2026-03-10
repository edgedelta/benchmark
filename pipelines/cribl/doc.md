How can I create an HTTP input, s3 destination and a pipeline without using UI. I can use cribl cli or cribl api with curl commands
To create an HTTP input, S3 destination, and a pipeline without using the UI, you can use the Cribl API with curl commands. Below are the steps and corresponding curl commands:

1. Create an HTTP Input
To create an HTTP input, use the following curl command:

For Cribl.Cloud and Hybrid:
curl --request POST \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/my-worker-group/system/inputs" \
--header "Authorization: Bearer ${token}" \
--header "Content-Type: application/json" \
--data '{
  "id": "in_http_10200",
  "type": "http",
  "disabled": false,
  "port": 10200
}'
For On-Prem:
curl --request POST \
--url "https://${hostname}:${port}/api/v1/m/my-worker-group/system/inputs" \
--header "Authorization: Bearer ${token}" \
--header "Content-Type: application/json" \
--data '{
  "id": "in_http_10200",
  "type": "http",
  "disabled": false,
  "port": 10200
}'
2. Create an S3 Destination
To create an S3 destination, use the following curl command. Replace placeholder values like your-aws-api-key and your-aws-bucket-name with your actual AWS credentials and bucket name.

For Cribl.Cloud and Hybrid:
curl --request POST \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/my-worker-group/system/outputs" \
--header "Authorization: Bearer ${token}" \
--header "Content-Type: application/json" \
--data '{
  "id": "out_s3",
  "type": "s3",
  "awsAuthenticationMethod": "manual",
  "awsApiKey": "your-aws-api-key",
  "awsSecretKey": "your-aws-secret-key",
  "region": "us-east-2",
  "bucket": "your-aws-bucket-name",
  "compress": "gzip",
  "compressionLevel": "best_speed",
  "stagePath": "$CRIBL_HOME/state/outputs/staging",
  "emptyDirCleanupSec": 300
}'
For On-Prem:
curl --request POST \
--url "https://${hostname}:${port}/api/v1/m/my-worker-group/system/outputs" \
--header "Authorization: Bearer ${token}" \
--header "Content-Type: application/json" \
--data '{
  "id": "out_s3",
  "type": "s3",
  "awsAuthenticationMethod": "manual",
  "awsApiKey": "your-aws-api-key",
  "awsSecretKey": "your-aws-secret-key",
  "region": "us-east-2",
  "bucket": "your-aws-bucket-name",
  "compress": "gzip",
  "compressionLevel": "best_speed",
  "stagePath": "$CRIBL_HOME/state/outputs/staging",
  "emptyDirCleanupSec": 300
}'
3. Create a Pipeline
To create a pipeline that filters events and keeps only the eventSource and eventID fields, use the following curl command:

For Cribl.Cloud and Hybrid:
curl --request POST \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/my-worker-group/pipelines" \
--header "Authorization: Bearer ${token}" \
--header "Content-Type: application/json" \
--data '{
  "id": "my_pipeline",
  "conf": {
    "asyncFuncTimeout": 1000,
    "functions": [
      {
        "filter": "true",
        "conf": {
          "remove": ["*"],
          "keep": ["eventSource", "eventID"]
        },
        "id": "eval",
        "final": true
      }
    ]
  }
}'
For On-Prem:
curl --request POST \
--url "https://${hostname}:${port}/api/v1/m/my-worker-group/pipelines" \
--header "Authorization: Bearer ${token}" \
--header "Content-Type: application/json" \
--data '{
  "id": "my_pipeline",
  "conf": {
    "asyncFuncTimeout": 1000,
    "functions": [
      {
        "filter": "true",
        "conf": {
          "remove": ["*"],
          "keep": ["eventSource", "eventID"]
        },
        "id": "eval",
        "final": true
      }
    ]
  }
}'
Notes:
Replace placeholders like ${workspaceName}, ${organizationId}, ${hostname}, ${port}, and ${token} with your actual values.
After creating these resources, ensure you deploy the configurations to the Worker Group to make them active.
For more details, refer to the API documentation in my knowledgebase.

How can I connect these HTTP input and s3 destination with the pipeline for Cribl cloud, I don't use on-prem
To connect the HTTP input and S3 destination with a pipeline in Cribl.Cloud, you need to configure a Route. A Route connects a Source (HTTP input) to a Destination (S3) through a Pipeline. Below are the steps to achieve this:

1. Create a Route
Use the Cribl API to create a Route that links the HTTP input, pipeline, and S3 destination.

API Request:
curl --request POST \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/${worker_group}/routes" \
--header "Authorization: Bearer ${token}" \
--header "Content-Type: application/json" \
--data '{
  "id": "http_to_s3_route",
  "filter": "true", 
  "pipeline": "my_pipeline", 
  "input": "in_http_10200", 
  "output": "out_s3"
}'
Explanation:
id: Unique identifier for the Route (e.g., http_to_s3_route).
filter: Set to "true" to allow all events to pass through. You can customize this with a condition if needed.
pipeline: The ID of the pipeline you created (e.g., my_pipeline).
input: The ID of the HTTP input (e.g., in_http_10200).
output: The ID of the S3 destination (e.g., out_s3).
2. Deploy the Configuration
After creating the Route, deploy the configuration to make it active.

API Request:
curl --request POST \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/${worker_group}/deploy" \
--header "Authorization: Bearer ${token}"
3. Verify the Configuration
Navigate to the Cribl.Cloud UI and check the Data Routes section to confirm the Route is active.
Ensure the HTTP input is receiving data, the pipeline is processing it, and the S3 destination is storing the output.
Notes:
Replace placeholders like ${workspaceName}, ${organizationId}, ${worker_group}, and ${token} with your actual Cribl.Cloud values.
Ensure the HTTP input, S3 destination, and pipeline are already created as per your earlier setup.

How can I delete these route, HTTP input, s3 destination and pipeline after my tests are completed
To delete the Route, HTTP input, S3 destination, and pipeline after your tests are completed in Cribl.Cloud, you can use the Cribl API with curl commands. Below are the steps and corresponding commands:

1. Delete the Route
To delete the Route, use the following curl command:

curl --request DELETE \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/${worker_group}/routes/http_to_s3_route" \
--header "Authorization: Bearer ${token}"
Replace http_to_s3_route with the ID of the Route you created.

2. Delete the HTTP Input
To delete the HTTP input, use the following curl command:

curl --request DELETE \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/${worker_group}/system/inputs/in_http_10200" \
--header "Authorization: Bearer ${token}"
Replace in_http_10200 with the ID of the HTTP input you created.

3. Delete the S3 Destination
To delete the S3 destination, use the following curl command:

curl --request DELETE \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/${worker_group}/system/outputs/out_s3" \
--header "Authorization: Bearer ${token}"
Replace out_s3 with the ID of the S3 destination you created.

4. Delete the Pipeline
To delete the pipeline, use the following curl command:

curl --request DELETE \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/${worker_group}/pipelines/my_pipeline" \
--header "Authorization: Bearer ${token}"
Replace my_pipeline with the ID of the pipeline you created.

Notes:
Replace placeholders like ${workspaceName}, ${organizationId}, ${worker_group}, and ${token} with your actual Cribl.Cloud values.
Ensure you deploy the configuration after making these deletions to apply the changes.
To deploy the configuration, use:

curl --request POST \
--url "https://${workspaceName}-${organizationId}.cribl.cloud/api/v1/m/${worker_group}/deploy" \
--header "Authorization: Bearer ${token}"