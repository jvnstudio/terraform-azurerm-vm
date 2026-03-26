def shouldDeploy(String targetEnv, String stageEnv) {
  def order = ['dev', 'uat', 'prod']
  return order.indexOf(stageEnv) <= order.indexOf(targetEnv)
}

pipeline {
  agent any

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  parameters {
    choice(
      name: 'PROMOTE_TO',
      choices: ['dev', 'uat', 'prod'],
      description: 'Highest environment to deploy in this run.'
    )
    booleanParam(
      name: 'RUN_ANSIBLE',
      defaultValue: true,
      description: 'Run the Ansible playbooks after each Terraform apply.'
    )
  }

  environment {
    TF_IN_AUTOMATION = 'true'
    ANSIBLE_FORCE_COLOR = 'true'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Init And Validate') {
      steps {
        sh 'terraform fmt -check -recursive'
        sh 'terraform init -input=false'
        sh 'terraform validate'
      }
    }

    stage('Deploy Dev') {
      when {
        expression { shouldDeploy(params.PROMOTE_TO, 'dev') }
      }
      steps {
        script {
          deployEnvironment('dev', 'environments/dev/terraform.tfvars', params.RUN_ANSIBLE)
        }
      }
    }

    stage('Deploy UAT') {
      when {
        expression { shouldDeploy(params.PROMOTE_TO, 'uat') }
      }
      steps {
        script {
          deployEnvironment('uat', 'environments/uat/terraform.tfvars', params.RUN_ANSIBLE)
        }
      }
    }

    stage('Approve Prod') {
      when {
        expression { params.PROMOTE_TO == 'prod' }
      }
      steps {
        input message: 'Promote the current commit to production?', ok: 'Deploy prod'
      }
    }

    stage('Deploy Prod') {
      when {
        expression { params.PROMOTE_TO == 'prod' }
      }
      steps {
        script {
          deployEnvironment('prod', 'environments/prod/terraform.tfvars', params.RUN_ANSIBLE)
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts artifacts: 'tfplan-*.txt, ansible/inventories/**/*.ini', allowEmptyArchive: true
    }
    cleanup {
      sh 'rm -f tfplan-* tfplan-*.txt'
    }
  }
}

def deployEnvironment(String envName, String tfvarsFile, boolean runAnsible) {
  withCredentials([
    string(credentialsId: 'azure-arm-client-id', variable: 'ARM_CLIENT_ID'),
    string(credentialsId: 'azure-arm-client-secret', variable: 'ARM_CLIENT_SECRET'),
    string(credentialsId: 'azure-arm-subscription-id', variable: 'ARM_SUBSCRIPTION_ID'),
    string(credentialsId: 'azure-arm-tenant-id', variable: 'ARM_TENANT_ID'),
    sshUserPrivateKey(credentialsId: 'azure-vm-ssh-key', keyFileVariable: 'JENKINS_SSH_KEY', usernameVariable: 'JENKINS_SSH_USER')
  ]) {
    sh """#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.ssh"
cp "$JENKINS_SSH_KEY" "$HOME/.ssh/azure_rsa"
chmod 600 "$HOME/.ssh/azure_rsa"
ssh-keygen -y -f "$HOME/.ssh/azure_rsa" > "$HOME/.ssh/azure_rsa.pub"
chmod 644 "$HOME/.ssh/azure_rsa.pub"

az login --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant "$ARM_TENANT_ID" \
  --output none
az account set --subscription "$ARM_SUBSCRIPTION_ID"

if terraform workspace select ${envName}; then
  echo "Using existing Terraform workspace ${envName}"
else
  terraform workspace new ${envName}
fi

terraform plan -input=false -no-color -out=tfplan-${envName} -var-file=${tfvarsFile}
terraform show -no-color tfplan-${envName} > tfplan-${envName}.txt
terraform apply -input=false -auto-approve tfplan-${envName}
"""

    if (runAnsible) {
      sh """#!/usr/bin/env bash
set -euo pipefail
cd ansible
ansible-playbook -i inventories/${envName}/hosts.ini site.yml
"""
    }
  }
}
