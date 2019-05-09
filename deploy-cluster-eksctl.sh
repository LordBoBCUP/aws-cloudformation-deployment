#!/bin/bash

###################################################################
#Script Name	: deploy-cluster-eksctl.sh                                                                                              
#Description	: Using EKSCTL from Weave to deploy a new EKS
#               : cluster on AWS with the specified parameters.
#Args           : -r region -v version -                                                                                         
#Author       	: Alex Massey                                                
#Email         	: alex.massey@augensoftwaregroup.com                                           
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
declare -a valid_aws_ec2_instances

## Logging ##
LOGFILE=deploy-cluster-eksctl.sh.log
RETAIN_NUM_LINES=1000

## List of AWS EC2 Instances to choose from ##



########### FUNCTIONS ###########
function usage()
{
    echo "usage: ./storageclass.sh [[[-r region ] | [-h]]"
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
    valid_aws_ec2_instances[0]="c5.xlarge"

}

########### MAIN ###########
log started...

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

if [[ ${region,,} =~ $pattern ]] ; 
then
    # Set full region
    fullRegion="us-west-2"
else
  usage
  exit 1
fi


if [[ $clusterId =~ ^[1-9]$ ]];
then
    # Set the ClusterName Variable
    ClusterName="$clusterPrefix$fullRegion-p-cluster-$clusterId"
else 
    # Exit on error
    usage
    exit 1
fi

if ! [[ ${version,,} =~ $versionPattern ]] ; 
then
  usage
  exit 1
fi

if ! [[ ${nodeVolumeSize,,} =~ $nodeVolumeSizePattern ]] ; 
then
  usage
  exit 1
fi

if ! [[ ${numOfNodes,,} =~ $numberOfNodesPattern ]] ; 
then
  usage
  exit 1
fi

if [[ ! -f $sshKey ]];
then
  usage
  exit 1
fi

if [[ ! -f $template ]];
then
  usage
  exit 1
fi

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
let "max=$numOfNodes + 2"
sed -i -e "/maxSize:/ s/:.*/: $max/" $template
sed -i -e "/publicKeyPath:/ s/:.*/: ${sshKey//\//\\/}/" $template


#eksctl create cluster --name=$clusterName --version=$version --nodes=$numOfNodes --kubeconfig=$kubeConfig --node-type=$nodeType --node-volume-size=$nodeVolumeSize 
ERROR=$( { eksctl create cluster --config-file=$template } 2>&1 )

if [[ -z $ERROR ]];
then
  log An error has occurred. Error message is:
  log $ERROR
  exit 1
fi
log cluster was successfully deployed.
log attempting Cluster AutoScaler installation...



log completed...