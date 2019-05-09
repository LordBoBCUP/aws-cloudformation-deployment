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
VpcTemplateURL='https://raw.githubusercontent.com/LordBoBCUP/aws-cloudformation-deployment/master/1-vpc.yml'
ServiceRoleTemplateURL='https://raw.githubusercontent.com/LordBoBCUP/aws-cloudformation-deployment/master/1-vpc.yml'
WorkerNodeTemplateURL='https://raw.githubusercontent.com/LordBoBCUP/aws-cloudformation-deployment/master/1-vpc.yml'

## VPC ##
VpcBlock='192.168.0.0/16'
Subnet01Block='192.168.64.0/18'
Subnet02Block='192.168.128.0/18'
Subnet03Block='192.168.192.0/18'

## Worker Node ##
keyname=$clusterName-keypair
NodeImageId='ami-0bfedee6a7845c26d' # Based on Region https://docs.aws.amazon.com/eks/latest/userguide/eks-optimized-ami.html
NodeInstanceType='c5.xlarge'
NodeAutoScalingGroupMinSize=1
NodeAutoScalingGroupMaxSize=2 # has to be +1 of NodeAutoScalingGroupMinSize
NodeAutoScalingGroupDesiredCapacity=1
NodeVolumeSize=20
BootstrapArguments=""
NodeGroupName='$clusterName-NodeGroup'
ClusterControlPlaneSecurityGroup=  # Comes from the VPC Template Outputs
VpcId='' # Comes from the VPC Template Outputs
Subets='' # Comes from the VPC Template Outputs
PublicIp= # Comes from the VPC Templates Outputs

## Logging ##
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

function executeWorkerNodeTemplate() {
    result=$(aws cloudformation wait stack-create-complete create-stack --template-body $ServiceRoleTemplateURL --output json)
    if ($result | jq has("StackId")) {
        log ServiceRole Template Successfully Deployed
        return 0
    }
    log ServiceRole Template was not successfully deployed. Exiting. Error: $result
    return 1
}

function createKeyPair() {
    result=$(aws ec2 create-key-pair --region ap-northeast-1 --key-name $clusterName-keypair --output json)
    if ($result | jq has('KeyMaterial')){
        $result | jq '.KeyMaterial' > $keypair.pem
        log Keypair Private Key is:
        log result | jq .KeyMaterial
        return 0
    }
    log Failed to create KeyPair. Exiting. Error: $result
    return 1
}

function createEKSCluster() {
    result=$(aws eks --region $region create-cluster --name $clusterName )
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
        if (executeVpcTemplate($VpcTemplateURL) == 1)
            exit 1
        }
    }

    # Validate Service Role Template
    log Validating ServiceRole Template
    if (validateTemplate $VpcTemplateURL == 0) {
        # Execute Service Role Template
        log Executing Service Role Template
        if (executeServiceRoleTemplate($VpcTemplateURL) == 1){
            exit 1
        }

    }

    # Create KeyPair in Region for New Cluster
    if (createKeyPair() == 1){
        exit 1
    }

    # Create the EKS cluster
    log Creating EKS Cluster
    if (createEKSCluster() == 1){
        exit 1
    }

    # Loop while the cluster is created
    {
        log Waiting for cluster to be ready ...
        sleep 60
    } do (aws eks --region $region describe-cluster --name $clusterName --query cluster.status)

    # Validate Worker Node Template
    log Validating Worker Node Template
    if (validateTemplate $VpcTemplateURL == 0) {
        # Execute Worker Node Template
        log Executing Worker Node Template
        if (executeWorkerNodeTemplate($VpcTemplateURL) == 1 ){
            exit 1
        }
    }
}

Main







aws cloudformation create-stack --name "$clusterName-ServiceRole" --region $region --template-body $ServiceRoleTemplateURL --parameters 

aws cloudformation create-stack --name "$clusterName-WorkerNodes" --region $region --template-body $WorkerNodeTemplateURL --parameters 