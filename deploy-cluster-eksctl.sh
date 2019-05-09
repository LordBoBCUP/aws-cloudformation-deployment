#!/bin/bash

###################################################################
#Script Name	  : deploy-cluster-eksctl.sh                                                                                              
#Description	  : Using EKSCTL from Weave to deploy a new EKS
#               : cluster on AWS with the specified parameters.
#Args           : -r region -v version -                                                                                         
#Author       	: Alex Massey                                                
#Email         	: alex.massey@augensoftwaregroup.com 
#Notes          : Assumes you have eksctl & helm installed                                         
###################################################################

########### VARIABLES ###########
region=
regexPattern="^\bap1|\bap2|\beu1|\beu2|\bus1|\bus2$"
versionPattern="^[0-9]+\.[1][0-2]$"
nodeVolumeSizePattern="^[2-9][0-9]$"
numberOfNodesPattern="^[1-9]$"
version=
clusterPrefix='mx-'
clusterId=
clusterName=
numOfNodes=
nodeType=
nodeVolumeSize=
template=
sshKey=
declare -A valid_aws_ec2_instances

## Logging ##
LOGFILE=deploy-cluster-eksctl.sh.log
RETAIN_NUM_LINES=1000



########### FUNCTIONS ###########
function usage()
{
    echo "usage: ./storageclass.sh [[[-r region ] | [-h]]"
}

function printUsageAndExit() {
  usage
  exit 1
}

function logsetup {
    TMP=$(tail -n $RETAIN_NUM_LINES $LOGFILE 2>/dev/null) && echo "${TMP}" > $LOGFILE
    exec > >(tee -a $LOGFILE)
    exec 2>&1
}

function log {
    echo "[$(date --rfc-3339=seconds)]: $*"
}

function populate_aws_ec2_instances() {
  ## List of AWS EC2 Instances to choose from ##
  valid_aws_ec2_instances['ap1']='ap-northeast-1'
  valid_aws_ec2_instances['ap2']='ap-southeast-2'
  valid_aws_ec2_instances['eu1']='eu-west-2'
  valid_aws_ec2_instances['eu2']='eu-central-1'
  valid_aws_ec2_instances['us1']='us-west-2'
  valid_aws_ec2_instances['us2']='us-east-2'
}

function validateInput() {
  if [[ ${region,,} =~ $pattern ]] ; 
  then
    # Set full region
    reg=${region,,}
    fullRegion=${valid_aws_ec2_instances[$reg]}
    log $fullRegion
  else
    printUsageAndExit
  fi


  if [[ $clusterId =~ ^[1-9]$ ]];
  then
    # Set the ClusterName Variable
    ClusterName="$clusterPrefix$fullRegion-p-cluster-$clusterId"
  else 
    # Exit on error
    printUsageAndExit
  fi

  if ! [[ ${version,,} =~ $versionPattern ]] ; 
  then
    printUsageAndExit
  fi

  if ! [[ ${nodeVolumeSize,,} =~ $nodeVolumeSizePattern ]] ; 
  then
    printUsageAndExit
  fi

  if ! [[ ${numOfNodes,,} =~ $numberOfNodesPattern ]] ; 
  then
    printUsageAndExit
  fi

  if [[ ! -f $sshKey ]];
  then
    printUsageAndExit
  fi

  if [[ ! -f $template ]];
  then
    printUsageAndExit
  fi
}

function setEKSCTLTemplate() {
  nodeGroupName=$ClusterName-ng-$clusterId

  #sed -i -e "/region =/ s/= .*/= $region/" /home/alex/.aws/config
  sed -i -e "/name:/ s/:.*/: $ClusterName/" $template
  sed -i -e "/region:/ s/:.*/: $fullRegion/" $template
  sed -i -e "/version:/ s/:.*/: $version/" $template

  sed -i -e "/- name:/ s/:.*/: $nodeGroupName/" $template
  sed -i -e "/instanceType:/ s/:.*/: $nodeType/" $template
  sed -i -e "/volumeSize:/ s/:.*/: $nodeVolumeSize/" $template
  sed -i -e "/desiredCapacity:/ s/:.*/: $numOfNodes/" $template
  sed -i -e "/minSize:/ s/:.*/: 1/" $template
  #let "max=$numOfNodes + 2"
  sed -i -e "/maxSize:/ s/:.*/: 10/" $template
  sed -i -e "/publicKeyPath:/ s/:.*/: ${sshKey//\//\\/}/" $template
  #sed -i -e "/tags:/ s/:.*/: \{k8s.io\/cluster-autoscaler\/enabled:\'\',k8s.io\/cluster-autoscaler:$ClusterName\}/" $template # May not be required as we can pass the --asg-access command to the executable.
}


function executeEKSCTL() {
  #eksctl create cluster --name=$clusterName --version=$version --nodes=$numOfNodes --kubeconfig=$kubeConfig --node-type=$nodeType --node-volume-size=$nodeVolumeSize 
  ERROR=$({ eksctl create cluster --config-file=$template } 2>&1)

  if [[ -z $ERROR ]];
  then
    log An error has occurred. Error message is
    log $ERROR
    exit 1
  fi
}

function downloadAndExtractHelmChart(){
  helm repo update
  helm fetch stable/cluster-autoscaler --untar true --untardir $ClusterName
}


function setCAHelmChartValues(){
  cwd=$(pwd)
  sed -i -e "/clusterName:/ s/:.*/: $ClusterName/" $cwd/$ClusterName/cluster-autoscaler/values.yaml
  sed -i -e "/awsRegion:/ s/:.*/: $fullRegion/" $cwd/$ClusterName/cluster-autoscaler/values.yaml
  sed -i -e "/sslCertPath:/ s/:.*/: \/etc\/kubernetes\/pki\/ca.crt/" $cwd/$ClusterName/cluster-autoscaler/values.yaml
  sed -i -e "/create:/ s/:.*/: true/" $cwd/$ClusterName/cluster-autoscaler/values.yaml
}

function executeCAHelmChart(){
  cwd="$(pwd)/$ClusterName/cluster-autoscaler"
  ERROR=$({ helm install stable/cluster-autoscaler -f $cwd/values.yaml --name cluster-autoscaler --namespace default } 2>&1)

  if [[ -z $ERROR ]];
  then
    log An error has occurred. Error message is
    log $ERROR
    exit 1
  fi
}

########### MAIN ###########

function Main() {
  log started...

  log validating user parameters...

  populate_aws_ec2_instances  
  validateInput

  log executing EKSCTL to create the cluster... 

  setEKSCTLTemplate
  #executeEKSCTL

  log cluster was successfully deployed.
  log attempting Cluster AutoScaler installation...

  # Download the Helm Chart to deploy
  log Downloading helm chart and extracting to $ClusterName
  downloadAndExtractHelmChart
  
  # Modify the values.yaml file 
  log Modifying helm chart values.yaml
  setCAHelmChartValues
  
  # Excute & return helm chart
  log running Cluster Autoscaler Helm Chart
  #executeCAHelmChart

  log completed...
}

while [ "$1" != "" ]; do
    case $1 in
        -r | --region )         shift
                                region=$1
                                ;;
        -v | --version )        shift
                                version=$1
                                ;;
        -c | --clusterId )      shift
                                clusterId=$1
                                ;;
        -s | --storage )        shift
                                nodeVolumeSize=$1
                                ;;   
        -t | --nodeType )       shift
                                nodeType=$1
                                ;;   
        -n | --numberOfNodes )  shift
                                numOfNodes=$1
                                ;;         
        -k | --sshkey )         shift
                                sshKey=$1
                                ;;                                                            
        -h | --help )           shift
                                usage
                                ;;
        -a | --template )       shift
                                template=$1
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
  done


Main
