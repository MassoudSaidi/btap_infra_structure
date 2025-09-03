# Terraform Infrastructure Deployment Procedure

## 1. Introduction

This document outlines the step-by-step procedure for deploying the application infrastructure using Terraform and Terragrunt. The infrastructure is defined as code and is organized into several modular components.

The deployment process is sequential and involves provisioning the following key components in order:

1.  **Core Infrastructure (ECS):** Deploys the Amazon ECS cluster, service, task definition, and associated networking resources.
2.  **Identity Management (Cognito):** Sets up an Amazon Cognito User Pool and Application Client for user authentication.
3.  **CI/CD Pipeline Integration (GitHub Actions):** Configures the necessary secrets in your GitHub repository to enable automated deployments.

Following this initial setup, subsequent application deployments are automated via a CI/CD pipeline triggered by Git tags.

## 2. Prerequisites

Before proceeding with the deployment, please ensure the following prerequisites are met:

*   **Terraform and Terragrunt:** Both tools must be installed on the machine from which you will be running the deployment commands.
*   **AWS Credentials:** The AWS CLI must be configured with an access key and secret key that have sufficient permissions to create the resources defined in the Terraform code.
*   **Git:** The project code must be cloned from the source repository to your local machine.
*   **Code Editor:** A code editor of your choice is needed to modify configuration files.

## 3. Pre-Deployment Configuration

Before initializing the deployment, you must configure several key parameters that define the environment.

### 3.1. Global Settings

Global settings that apply across all modules are defined in a central location.

1.  Navigate to the `modules/ecs-service/` directory.
2.  Open the `common.hcl` file.
3.  Review and update the following local variables as needed:

    ```hcl
    locals {
      # --- Global Settings ---
      aws_region        = "ca-central-1"  # Target AWS Region for all resources.
      company           = "btap"          # A short name for your company or project.
      cognito_app_name  = "btap-identity" # A name for the Cognito application.

      # --- Backend Configuration ---
      # Set this variable to switch between local and remote (S3) state storage.
      use_local_backend = true  # Set to false for a shared S3 backend.
      
      # ... (other settings)
    }
    ```

### 3.2. Environment-Specific Settings

Configure the settings specific to the environment you are deploying (e.g., `dev`).

1.  Navigate to the `live/dev/` directory.
2.  Open the `terragrunt.hcl` file.
3.  Modify the `project_name` and `environment` inputs to match your requirements.

## 4. Deployment Procedure

The deployment must be executed in the precise order outlined below, as subsequent steps depend on the outputs of earlier ones.

### Step 1: Deploy the Core ECS Infrastructure

This initial step provisions the main application infrastructure, including the ECS cluster, service, and load balancer.

1.  Open your terminal and change the directory to `live/dev`:
    ```bash
    cd live/dev
    ```
2.  Run the Terragrunt apply command:
    ```bash
    terragrunt apply
    ```
3.  Terragrunt will display a plan of the resources to be created. Review this plan carefully. If you agree with the changes, type `yes` and press Enter to proceed.

4.  Upon successful completion, the script will output several key values. **Please save these outputs, as they are required for the subsequent steps.**
    *   `application_url`
    *   `cluster_name`
    *   `ecs_service_name`
    *   `ecs_task_definition_family`

    > **Note:** If you need to retrieve these outputs again later without re-running the apply command, you can do so by running `terragrunt output` from the `live/dev` directory.

### Step 2: Deploy the Cognito Identity Service

This step creates the Cognito User Pool for managing user identities and authentication.

1.  In your terminal, change the directory to `bootstrap-cognito`:
    ```bash
    cd ../../bootstrap-cognito
    ```
2.  Open the `terraform.tfvars` file and update the following variables:
    ```hcl
    app_name        = "my-app"
    app_environment = "dev"
    ```
    > **Note:** The remaining inputs in this file are related to SSL and can be left as their default values for a development environment. Cognito requires SSL in a production setting.

3.  Run the Terragrunt apply command:
    ```bash
    terragrunt apply
    ```
4.  Review the plan and type `yes` to approve it.

5.  Upon completion, the script will output the Cognito resource identifiers. One of these, the `client_secret`, is marked as sensitive. To retrieve its value, run the following command:
    ```bash
    terraform output -raw client_secret
    ```
6.  **Securely store all the output values from this step**, including the retrieved client secret. You will need them for the final configuration step.

### Step 3: Configure GitHub Actions for CI/CD

This final step securely stores the infrastructure and Cognito details as secrets in your GitHub repository. The CI/CD pipeline will use these secrets to automate future application deployments.

1.  Change the directory to `bootstrap-git-actions`:
    ```bash
    cd ../bootstrap-git-actions
    ```
2.  If it doesn't already exist, rename the example variables file:
    ```bash
    mv terraform.tfvars.example terraform.tfvars
    ```
3.  Open the `terraform.tfvars` file and populate it with the outputs you saved from **Step 1** and **Step 2**.

    ```hcl
    # Deployment configuration values from Step 1
    ecs_cluster_name = "btap-app4-dev-cluster"
    ecs_service_name = "btap-app4-dev-service"
    ecs_task_family  = "btap-app4-dev-task"

    # Cognito configuration from Step 2
    cognito_region                = "ca-central-1"
    cognito_user_pool_id          = "ca-central-1_jxxxxxxxxxxxx8t"
    cognito_app_client_id         = "4osaxxxxxxxxxxxao9kus1t"
    cognito_app_public_client_id  = "407500xxxxxxxxxxxx5duupnv47a"
    cognito_app_client_secret     = "<your_retrieved_client_secret>"
    cognito_domain                = "https://btap-identity-dev-auth.auth.ca-central-1.amazoncognito.com"
    
    # Application URL from Step 1
    app_base_url = "http://btap-app4-dev-alb-1261227763.ca-central-1.elb.amazonaws.com"
    
    # Application Version (can be an initial version)
    version_string = "v1.0.0" 
    ```

4.  Run the Terragrunt apply command to initialize the GitHub repository secrets:
    ```bash
    terragrunt apply
    ```
5.  Review the plan and type `yes` to confirm. This will push the configured values to GitHub Actions secrets.

## 5. Post-Deployment: Automated Application Updates

With the infrastructure and CI/CD pipeline configured, deploying new versions of your application is now automated. The pipeline is triggered when a new version tag is pushed to the repository.

To deploy a new version:

1.  Create a Git tag for your new release. The tag must follow a semantic versioning pattern (e.g., `1.0.0`, `v1.0.0`).
    ```bash
    git tag 1.0.1
    ```
2.  Push the tag to the remote repository:
    ```bash
    git push origin 1.0.1
    ```

Pushing the tag will automatically trigger a GitHub Actions workflow that builds a new container image, pushes it to the container registry, and updates the ECS service to deploy the new version.