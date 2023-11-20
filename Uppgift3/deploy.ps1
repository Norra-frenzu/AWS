# check if required aws configure and program exist on system
if ((Get-Package | Where-Object name -Match "aws") -eq $null) {
    write-host -ForegroundColor Yellow  "System has not AWS CLI installad on in, please install it first and check if Docker desktop is also installad"
    break
    }
else {write-host -ForegroundColor Green  "AWS CLI is installed"}

if ((Get-Package | Where-Object name -Match "Docker Desktop") -eq $null) {
    write-host -ForegroundColor Yellow  "System has not Docker Desktop installad on in, please install it first and check if Docker desktop is also installad"
    break
    }
else {write-host -ForegroundColor Green  "Docker Desktop is installed"}

if ((test-path ~\.aws\credentials) -eq $false) {
    write-host -ForegroundColor Yellow  "System has not been configure with AWS configure, please do"
    break
}
else {write-host -ForegroundColor Green  "AWS CLI has been configure, continue"}



# Setup variables for script
$name = "mynginx2023"
$RepositoryNames = "$name-docker-repo"
$Region = (aws configure get region)
$ContainerName = "$name-Container" 
$Dir = "C:\AWS\Docker"
$dockerimage = "$name"
$dockername = "$name-Docker"
$Keyname = "fredrik"
$EC2name = "$name-docker"
$IAMRole = "EcrReadOnlyRole"
$secgrpname = "docker-http/ssh"
$CodeBuildRole ="codebuild2-$IAMRole"
$ECSrepo = "$name-ECS-Repo"
$accountID = (aws sts get-caller-identity --query 'Account' --output text)
$subnet = (aws ec2 describe-subnets --query 'Subnets[].SubnetId').trim("[","]",'"',","," ") | Where-Object {$_ -ne ""}
$TaskDefinition = "$name-task"
$ECScluster = "$name-cluster"
$ECSservice = "$name-Service"
$CodePipeline = "$ECSrepo"
$IAMCodePipeline = "AWSCodePipelineServiceRole-$Region-$CodePipeline"
$SecgrpLB = "$name-LB-http"
$LBName = "$name-LB"
$LBgrpName = "$name-LB-Grp"
$VpcID = (aws ec2 describe-subnets --query 'Subnets[0].VpcId' --output text)

#Create our main directory for the exercies
if ((test-path $dir) -eq $false) {mkdir $Dir}
cd $Dir

#Check if necessary files and module e exist
if ((Test-Path .\dockerfile) -eq $false) {
    write-host -ForegroundColor Yellow "dockerfile don't exist on system, download it to main directory"
    Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/dockerfile" -OutFile .\dockerfile
    }
else {write-host -ForegroundColor Green "dockerfile exist in directory"} 
if ((Test-Path .\buildspec.yml) -eq $false) {
    write-host -ForegroundColor Yellow "buildspec.yml don't exist on system, download it to main directory"
    Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/buildspec.yml" -OutFile .\buildspec.yml
    }
else {write-host -ForegroundColor Green "buildspec.yml exist in directory"} 
if ((Test-Path .\appspec.yml) -eq $false) {
    write-host -ForegroundColor Yellow "appspec.yml don't exist on system, download it to main directory"
    Invoke-WebRequest "https://s3.amazonaws.com/aws-codedeploy-us-east-1/samples/latest/SampleApp_Linux.zip" -OutFile .\SampleApp_Linux.zip; tar -xf .\SampleApp_Linux.zip; Remove-Item .\SampleApp_Linux.zip
    }
else {write-host -ForegroundColor Green "appspec.yml exist in directory"}

write-host -ForegroundColor Yellow "download index.html to main directory"
Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/index.html" -OutFile .\index.html


#Create Docker build and print the index file on docker container for a fast check if working
docker build -t $dockerimage .
docker run -d -p 80:80 --name $dockername $dockerimage
$dockerlocalhost = (docker exec -it $dockername /bin/bash -c "curl localhost")
$localhost = (Invoke-RestMethod localhost)
if ((Compare-Object -ReferenceObject $dockerlocalhost -DifferenceObject $localhost) -match $null) {write-host -ForegroundColor Green "Local docker container deployed correctly"}
else {
        Write-Host -ForegroundColor Red "Something went wrong with local docker deployment" 
        break
}


#Setup locally repository in our main directory and make the first commit to it
git init
git add .
git commit -m 'Add simple web site'

#Create Elastic Container Registry Repository
aws ecr create-repository --repository-name $RepositoryNames
$ECRrepo = ((aws ecr describe-repositories --repository-names $RepositoryNames --query 'repositories[0].repositoryUri').replace('"',"").split("/"))
if ((Test-Path .\buildspec.yml) -eq $false) {Invoke-WebRequest -Uri https://github.com/larsappel/ECSDemo/raw/main/buildspec.yml -OutFile .\buildspec.yml}
(Get-Content .\buildspec.yml) -replace "<registry uri>", "$($ECRrepo[0])" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<image name>", "$($ECRrepo[1])" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<region>", "$Region" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<MyContainerName>", "$ECSrepo" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<project-name>", "$ECSrepo" | Set-Content .\buildspec.yml


# craete a login link between AWS ECR user and Docker user
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $ECRrepo[0]

# Tag docker image with repo name and push to AWS ECR
Docker tag $dockerimage "$($ECRrepo[0])/$($RepositoryNames):latest"
docker push "$($ECRrepo[0])/$($RepositoryNames):latest"


aws ecr describe-images --repository-name $RepositoryNames


# check if IAM roles exist and create if not
$extRoles = (aws iam list-roles --query 'Roles[*].RoleName').trim()
if ($IAMRole -notcontains $extRoles) {
    write-host -ForegroundColor Yellow "download role.json to main directory"
    Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/role.json" -OutFile .\role.json
}
write-host -ForegroundColor Yellow "Create instance profile with role"
    aws iam create-instance-profile --instance-profile-name $IAMRole
    aws iam create-role --role-name $IAMRole --assume-role-policy-document file://role.json
    aws iam attach-role-policy --role-name $IAMRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam add-role-to-instance-profile --instance-profile-name $IAMRole --role-name $IAMRole

#

write-host -ForegroundColor Yellow "Setup userdata file for EC2 instances"
Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/userdata.txt" -OutFile .\userdata.txt
(Get-Content .\userdata.txt) -replace "<registry uri>", "$($ECRrepo[0])" | Set-Content .\userdata.txt
(Get-Content .\userdata.txt) -replace "<image name>", "$($ECRrepo[1])" | Set-Content .\userdata.txt

start-sleep -Seconds 5

aws ec2 create-security-group --description "$secgrpname" --group-name "$secgrpname"
aws ec2 authorize-security-group-ingress --group-name $secgrpname --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name $secgrpname --protocol tcp --port 22 --cidr 0.0.0.0/0
$secgrpid = (aws ec2 describe-security-groups --query 'SecurityGroups[].GroupId' --group-names $secgrpname).trim("[","]",'"',","," ") | Where-Object {$_ -ne ""}

write-host -ForegroundColor Yellow "Create a EC2 instances"
aws ec2 run-instances --image-id ami-07355fe79b493752d --count 1 --instance-type t2.micro --key-name $Keyname --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2name}]" --user-data "file://userdata.txt" --iam-instance-profile Name=$IAMRole --security-groups $secgrpname




#ECS
write-host -ForegroundColor Green "Configure IAM roles and policy"

Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/codedeployrole.json" -OutFile .\codedeployrole.json
aws iam create-role --role-name "$CodeBuildRole" --assume-role-policy-document file://codedeployrole.json
aws iam attach-role-policy --role-name "$CodeBuildRole" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

if ((Test-Path .\codebuild.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/CodeBuildBasePolicy.json -OutFile .\CodeBuildBasePolicy.json}
(Get-Content .\CodeBuildBasePolicy.json) -replace "<project-name>", "ECSrepo" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<Region>", "$Region" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<registry uri>", "$ECSrepo" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<account-id>", "$accountID" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<repo>", "$ECSrepo" | Set-Content .\CodeBuildBasePolicy.json

aws iam create-policy --policy-name "CodeBuildBasePolicy-$ECSrepo-$Region" --policy-document file://CodeBuildBasePolicy.json
$Arn = (aws iam list-policies --query "Policies[?PolicyName=='CodeBuildBasePolicy-$ECSrepo-$Region'].{ARN:Arn}" --output text)
aws iam attach-role-policy --role-name "$CodeBuildRole" --policy-arn $Arn



write-host -ForegroundColor Yellow "Configure local repo"
git init
git add .
git commit -m 'Add simple web site'

write-host -ForegroundColor Green "Setting up ECS repo"
aws codecommit create-repository --repository-name "$ECSrepo" --repository-description "$ECSrepo"
$CommitHTTP = ((aws codecommit get-repository --repository-name $ECSrepo --query 'repositoryMetadata.cloneUrlHttp').replace('"',''))
git remote add origin $CommitHTTP
git push -u origin master



# (Get-Content .\CodeBuildBasePolicy.json) -replace "<project-name>", "$EC2name-Project" | Set-Content .\CodeBuildBasePolicy.json
# (Get-Content .\CodeBuildBasePolicy.json) -replace "<Region>", "$Region" | Set-Content .\CodeBuildBasePolicy.json
# (Get-Content .\CodeBuildBasePolicy.json) -replace "<registry uri>", "$ECSrepo" | Set-Content .\CodeBuildBasePolicy.json
# aws iam create-policy --policy-name "CodeBuildBasePolicy-$ECSrepo-$Region" --policy-document file://CodeBuildBasePolicy.json



# Task-definitions

write-host -ForegroundColor Green "Preper for setting up Task-Definition"
echo '{
    "containerDefinitions": [
      {
        "name": "<container name>",
        "image": "<image>",
        "portMappings": [
            {
            "containerPort": 80,
            "hostPort": 80
        }
        ],
        "essential": true
      }
    ],
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"]
  }' > .\task-definition.json

(Get-Content .\task-definition.json) -replace "<image>", "$($ECRrepo[0])/$($ECRrepo[1])" | Set-Content .\task-definition.json
(Get-Content .\task-definition.json) -replace "<container name>", "$ECSrepo" | Set-Content .\task-definition.json
(Get-Content .\task-definition.json) -replace "<your-account-id>", "$accountID" | Set-Content .\task-definition.json

write-host -ForegroundColor Green "Start to create Task-Definition"
aws ecs register-task-definition --family "$TaskDefinition" --cli-input-json file://task-definition.json --cpu 256 --memory 512 --execution-role-arn arn:aws:iam::389058819117:role/ecsTaskExecutionRole

write-host -ForegroundColor Green "Preper for setting up Cluster Services"
# ClusterService

write-host -ForegroundColor Green "Set up ESC cluster"
aws ecs create-cluster --cluster-name "$ECScluster" --capacity-providers FARGATE --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1

echo '{
    "networkConfiguration": {
        "awsvpcConfiguration": {
            "subnets": [
                "<subnet-1>",
                "<subnet-2>",
                "<subnet-3>"
            ],
            "securityGroups": [
                "<secgrp>"
            ],
            "assignPublicIp": "ENABLED"
        }
    }
  }' > .\ClusterService.json

 

(Get-Content .\ClusterService.json) -replace "<task-name>", "$TaskDefinition" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<subnet-1>", "$($subnet[0])" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<subnet-2>", "$($subnet[1])" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<subnet-3>", "$($subnet[2])" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<secgrp>", "$secgrpid" | Set-Content .\ClusterService.json

write-host -ForegroundColor Green "Start to create Cluster Services"
aws ecs create-service --cluster "$ECScluster" --service-name "$ECSservice"  --cli-input-json file://ClusterService.json --desired-count 1 --task-definition "$TaskDefinition"


# CodeBuild

# if ((Test-Path .\CodebuilddPlusPolicy.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/CodebuilddPlusPolicy.json -OutFile .\CodebuilddPlusPolicy.json}
# (Get-Content .\CodebuilddPlusPolicy.json) -replace "<registry uri>", "$ECSrepo" | Set-Content .\CodebuilddPlusPolicy.json
# (Get-Content .\CodebuilddPlusPolicy.json) -replace "<service-role>", "arn:aws:iam::$($accountID):role/service-role/$CodeBuildRole" | Set-Content .\CodebuilddPlusPolicy.json
# (Get-Content .\CodebuilddPlusPolicy.json) -replace "<project-name>", "$EC2name-Project" | Set-Content .\CodebuilddPlusPolicy.json

write-host -ForegroundColor Yellow "adding missing policys to codebuild account"

Pause

if ((Test-Path .\codebuild.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/codebuild.json -OutFile .\codebuild.json}
(Get-Content .\codebuild.json) -replace "<registry uri>", "$ECSrepo" | Set-Content .\codebuild.json
(Get-Content .\codebuild.json) -replace "<service-role>", "$CodeBuildRole" | Set-Content .\codebuild.json
(Get-Content .\codebuild.json) -replace "<project-name>", "$ECSrepo" | Set-Content .\codebuild.json
(Get-Content .\codebuild.json) -replace "<Region>", "$Region " | Set-Content .\codebuild.json



aws codebuild create-project --cli-input-json file://codebuild.json

aws codebuild start-build --project-name $ECSrepo


# fetch S3 bucket

$S3BucketName = (aws s3api list-buckets --query 'Buckets[?contains(Name, `eu-west-1`)].Name' --output text)

# CodePipeline

write-host -ForegroundColor Yellow "Now to creating the pipeline"
write-host -ForegroundColor Yellow "set up Role and policy for CodePipeline"

if ((Test-Path .\CodePipelinePermissionPolicy.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/CodePipelinePermissionPolicy.json -OutFile .\CodePipelinePermissionPolicy.json}
aws iam create-policy --policy-name "$IAMCodePipeline" --policy-document file://CodePipelinePermissionPolicy.json
if ((Test-Path .\CodePipelineTrust.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/CodePipelineTrust.json -OutFile .\CodePipelineTrust.json}
aws iam create-role --path /service-role/ --role-name "$IAMCodePipeline" --assume-role-policy-document file://CodePipelineTrust.json
$CodePipelinePolicyArn = (aws iam list-policies --query "Policies[?PolicyName=='$IAMCodePipeline'].{ARN:Arn}" --output text)
$CodePipelineRoleArn = (aws iam list-roles --query "Roles[?RoleName=='$IAMCodePipeline'].{ARN:Arn}" --output text)
aws iam attach-role-policy --role-name "$IAMCodePipeline" --policy-arn $CodePipelinePolicyArn

if ((Test-Path .\pipelineconfigV2.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/pipelineconfigV2.json -OutFile .\pipelineconfigV2.json}
(Get-Content .\pipelineconfigV2.json) -replace "<Pipeline-name>", "$CodePipeline" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<account-id>", "$accountID" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<Region>", "$Region" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<ECS-repo>", "$ECSrepo" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<Cluster-name>", "$ECScluster" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<Cluster-service>", "$ECSservice" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<Build-arn>", "$CodePipelineRoleArn" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<s3-bucket>", "$S3BucketName" | Set-Content .\pipelineconfigV2.json


# Load-balancer
write-host -ForegroundColor "Prepering Secgrp, load-balancer and target-group"

aws ec2 describe-security-groups --query "SecurityGroups[?GroupName=='$SecgrpLB'].GroupId" --output text
aws ec2 create-security-group --description "$SecgrpLB" --group-name "$SecgrpLB"
aws ec2 authorize-security-group-ingress --group-name "$SecgrpLB" --protocol tcp --port 80 --cidr 0.0.0.0/0
aws elbv2 create-load-balancer --name $LBName --subnets $subnet[0] $subnet[1] $subnet[2] --security-groups (aws ec2 describe-security-groups --query "SecurityGroups[?GroupName=='$SecgrpLB'].GroupId" --output text) --region $Region
aws elbv2 create-target-group --name $LBgrpName --protocol HTTP --port 80 --target-type ip --vpc-id $VpcID --region $Region

(Get-Content .\pipelineconfigV2.json) -replace "<listenerArns>", "$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(DNSName, '$LBname')].DNSName" --output text)" | Set-Content .\pipelineconfigV2.json
(Get-Content .\pipelineconfigV2.json) -replace "<targetGroups>", "$LBgrpName" | Set-Content .\pipelineconfigV2.json


write-host -ForegroundColor Red "Now for the real pipeline"

aws codepipeline create-pipeline --cli-input-json file://pipelineconfigV2.json
