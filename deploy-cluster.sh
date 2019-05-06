#!/bin/bash

###################################################################
#Script Name	: deploy-cluster.sh                                                                                              
#Description	: Deploys an EKS Cluster to AWS using the specified
#               : Parameters.                                                                                 
#Args           : None                                                                                          
#Author       	: Alex Massey                                                
#Email         	: alex.massey@augensoftwaregroup.com                                           
###################################################################

########### VARIABLES ###########
region='ap-northeast-1'
clusterName='mx-ap-northeast-1-p-cluster-1'
VpcBlock='192.168.0.0/16'
Subnet01Block='192.168.64.0/18'
Subnet02Block='192.168.128.0/18'
Subnet03Block='192.168.192.0/18'
VpcTemplateURL='https://raw.githubusercontent.com/LordBoBCUP/aws-cloudformation-deployment/master/1-vpc.yml'
ServiceRoleTemplateURL='https://raw.githubusercontent.com/LordBoBCUP/aws-cloudformation-deployment/master/1-vpc.yml'
WorkerNodeTemplateURL='https://raw.githubusercontent.com/LordBoBCUP/aws-cloudformation-deployment/master/1-vpc.yml'

LOGFILE=deploy-cluster.sh.log
RETAIN_NUM_LINES=1000

########### FUNCTIONS ###########
function logsetup {
    TMP=$(tail -n $RETAIN_NUM_LINES $LOGFILE 2>/dev/null) && echo "${TMP}" > $LOGFILE
    exec > >(tee -a $LOGFILE)
    exec 2>&1
}

function log {
    echo "[$(date --rfc-3339=seconds)]: $*"
}

function validateTemplate() {
    result=$(aws cloudformation validate-template --template-body $1 --output json) 
    if (result | jq has("Error")) {
        log Template Validation has failed for Template $1
        return 1
    } 
    log Template Validation has passed for Template $1
    return 0
}

function executeVpcTemplate() {
    result=$(aws cloudformation wait stack-create-complete --template-body $VpcTemplateURL --paramters ParameterKey=VpcBlock,ParameterValue=$VpcBlock ParameterKey=Subnet01Block,ParameterValue=$Subnet01Block ParameterKey=Subnet02Block,ParameterValue=$Subnet02Block ParameterKey=Subnet03Block,ParameterValue=$Subnet03Block --output json)
    if ($result | jq has("StackId")) {
        log VPC Template Successfully Deployed
        return 0
    }
    log VPC Template was not successfully deployed. Exiting. Error: $result
    return 1
}

function executeServiceRoleTemplate() {
    result=$(aws cloudformation wait stack-create-complete create-stack --template-body $ServiceRoleTemplateURL --output json)
    if ($result | jq has("StackId")) {
        log ServiceRole Template Successfully Deployed
        return 0
    }
    log ServiceRole Template was not successfully deployed. Exiting. Error: $result
    return 1
}



########### Main ###########
function Main() {
    # Setup Logging
    logsetup()

    # Validate VPC Template
    log Validating VPC Template
    if (validateTemplate $VpcTemplateURL == 0) {
        # Execute VPC Template
        log Executing VPC Template
        VpcTemplateResult=executeVpcTemplate($VpcTemplateURL)
    }

    # Validate Service Role Template
    if (validateTemplate $VpcTemplateURL == 0) {
        # Execute Service Role Template
        VpcTemplateResult=executeVpcTemplate($VpcTemplateURL)
    }

        # Validate Worker Node Template
    if (validateTemplate $VpcTemplateURL == 0) {
        # Execute Worker Node Template
        VpcTemplateResult=executeVpcTemplate($VpcTemplateURL)
    }
}

Main







aws cloudformation create-stack --name "$clusterName-ServiceRole" --region $region --template-body $ServiceRoleTemplateURL --parameters 

aws cloudformation create-stack --name "$clusterName-WorkerNodes" --region $region --template-body $WorkerNodeTemplateURL --parameters 