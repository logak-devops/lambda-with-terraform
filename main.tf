terraform {
	required_version = "~> 0.15.0"

	required_providers {
		archive = {
			source = "hashicorp/archive"
			version = "~> 2.0"
		}
		aws = {
			source  = "hashicorp/aws"
			version = "~> 3.0"
		}
	}
}

// 1) Provide your own access and secret keys so terraform can connect
//    and create AWS resources (e.g. our lambda function)
provider "aws" {
	shared_credentials_file = "/root/.aws/credential"
	region="us-east-1"
}

// 2) Setup our lambda parameters and .zip file that will be uploaded to AWS
locals {
	// The name of our lambda function when is created in AWS
	function_name = "hello-world-lambda"
	// When our lambda is run / invoked later on, run the "handler"
	// function exported from the "index" file
	handler = "index.handler"
	// Run our lambda in node v14
	runtime = "python3.8"
	// By default lambda only runs for a max of 3 seconds but our
	// "hello world" is printed after 5 seconds. So, we need to
	// increase how long we let our lambda run (e.g. 6 seconds)
	timeout = 6

	// The .zip file we will create and upload to AWS later on
	zip_file = "hello-world-lambda.zip"
}

// 3) Let terraform create a .zip file on your local computer which contains
//    only our "index.js" file by ignoring any Terraform files (e.g. our .zip)
data "archive_file" "zip" {
	excludes = [
		".env",
		".terraform",
		".terraform.lock.hcl",
		"main.tf",
		"terraform.tfstate",
		"terraform.tfstate.backup",
		local.zip_file,
	]
	source_dir = path.module
	type = "zip"

	// Create the .zip file in the same directory as the index.js file
	output_path = "${path.module}/${local.zip_file}"
}

// 4) Create an AWS IAM resource who will act as an intermediary between
//    our lambda and other AWS services such as Cloudwatch for "console.log"
data "aws_iam_policy_document" "default" {
	version = "2012-10-17"

	statement {
		// Let the IAM resource have temporary admin permissions to
		// add permissions for itself.
		// https://docs.aws.amazon.com/STS/latest/APIReference/API_AssumeRole.html
		actions = ["sts:AssumeRole"]
		effect = "Allow"

		// Let the IAM resource manage our (future) lambda resource
		// https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_principal.html#principal-services
		principals {
			identifiers = ["lambda.amazonaws.com"]
			type = "Service"
		}
	}
}
resource "aws_iam_role" "default" {
	// Create a IAM resource in AWS which is given the permissions detailed
	// in our above policy document

	assume_role_policy = data.aws_iam_policy_document.default.json
	// name = is randomly generated by terraform
}
resource "aws_iam_role_policy_attachment" "default" {
	// In addition to letting our IAM resource connect to our (future) lambda
	// function, we also want to let our IAM resource connect to other AWS services
	// like Cloudwatch for to see our "console.log"
	// https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html#permissions-executionrole-features

	policy_arn  = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
	role = aws_iam_role.default.name
}

// 5) Create our lambda function in AWS and upload our .zip with our code to it
resource "aws_lambda_function" "default" {
	// Function parameters we defined at the beginning
	function_name = local.function_name
	handler = local.handler
	runtime = local.runtime
	timeout = local.timeout

	// Upload the .zip file Terraform created to AWS
	filename = local.zip_file
	source_code_hash = data.archive_file.zip.output_base64sha256

	// Connect our IAM resource to our lambda function in AWS
	role = aws_iam_role.default.arn

	
	}
}

// 6) Use ClickFlow's public terrafore module to deploy your lambda for yo
module "hello-world-lambda" {
	source = "github.com/logak-devops/terraform-modules.git//v0.15/aws-lambda/v2"

	excluded_files = [
		".env",
		".terraform",
		".terraform.lock.hcl",
		"main.tf",
		"terraform.tfstate",
		"terraform.tfstate.backup",
	]
	handler = "index.handler"
	name = "hello-world-lambda-via-clickflow"
	runtime = "python3.8"
	source_directory = path.module
	timeout_after_seconds = 6
}
