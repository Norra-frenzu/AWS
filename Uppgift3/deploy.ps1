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
$date = (get-date -UFormat %Y%m%d)
$name = "$date-mynginx2023"
$RepositoryNames = "$name-docker-repo"
$Region = (aws configure get region)
$ContainerName = "$name-Container" 
$Dir = "C:\AWS\Docker"
$dockerimage = "$name"
$dockername = "$name-Docker"
$Keyname = "fredrik"
$EC2name = "$name-docker"
$IAMRole = "$date-EcrReadOnlyRole"
$ContainerSecgrpName = "$date-Container-http/ssh"
$project = "$name-project"
$CodeBuildRole ="AWSCodePipeline-$project-$Region"
$CodeBuildPolicy = "CodeBuildBasePolicy-$project-$Region"
$ECSrepo = "$name-ECS-Repo"
$accountID = (aws sts get-caller-identity --query 'Account' --output text)
$subnet = (aws ec2 describe-subnets --query 'Subnets[].SubnetId').trim("[","]",'"',","," ") | Where-Object {$_ -ne ""}
$TaskDefinition = "$name-task"
$ECScluster = "$name-cluster"
$ECSservice = "$name-Service"
$CodePipeline = "$name-pipeline"
$IAMCodePipeline = "AWSCodePipeline-$name"
$SecgrpLB = "$name-LB-http"
$LBName1 = "$name-LB-1"
$LBgrpName = "$date-LB-Grp"
$Buildname = "$name-Build"
$VpcID = (aws ec2 describe-subnets --query 'Subnets[0].VpcId' --output text)
$S3BucketName = (aws s3api list-buckets --query 'Buckets[?contains(Name, `eu-west-1`)].Name' --output text)


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

# ------ Local Work been done -------
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
(Get-Content .\buildspec.yml) -replace "<MyContainerName>", "$ContainerName" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<project-name>", "$project" | Set-Content .\buildspec.yml


# craete a login link between AWS ECR user and Docker user
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $ECRrepo[0]

# Tag docker image with repo name and push to AWS ECR
Docker tag $dockerimage "$($ECRrepo[0])/$($RepositoryNames):latest"
docker push "$($ECRrepo[0])/$($RepositoryNames):latest"

# ------ End of Local Work been done -------


# -----SET UP IAM Roles and Policys-------
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

write-host -ForegroundColor Green "Configure IAM roles and policy"

Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/codedeployrole.json" -OutFile .\codedeployrole.json
aws iam create-role --role-name "$CodeBuildRole" --assume-role-policy-document file://codedeployrole.json
aws iam attach-role-policy --role-name "$CodeBuildRole" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

 ## Special write to json
if ((Test-Path .\CodeBuildBasePolicy.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/CodeBuildBasePolicy.json -OutFile .\CodeBuildBasePolicy.json}
(Get-Content .\CodeBuildBasePolicy.json) -replace "<project-name>", "$project" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<Region>", "$Region" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<account-id>", "$accountID" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<repo>", "$project" | Set-Content .\CodeBuildBasePolicy.json
(Get-Content .\CodeBuildBasePolicy.json) -replace "<ECS-repo>", "$ECSrepo" | Set-Content .\CodeBuildBasePolicy.json

aws iam create-policy --policy-name "$CodeBuildPolicy" --policy-document file://CodeBuildBasePolicy.json
$CodeBuildPolicyArn = (aws iam list-policies --query "Policies[?PolicyName=='$CodeBuildPolicy'].{ARN:Arn}" --output text)
aws iam attach-role-policy --role-name "$CodeBuildRole" --policy-arn $CodeBuildPolicyArn

write-host -ForegroundColor Yellow "set up Role and policy for CodePipeline"

if ((Test-Path .\CodePipelinePermissionPolicy.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/CodePipelinePermissionPolicy.json -OutFile .\CodePipelinePermissionPolicy.json}
aws iam create-policy --policy-name "$IAMCodePipeline" --policy-document file://CodePipelinePermissionPolicy.json
if ((Test-Path .\CodePipelineTrust.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/CodePipelineTrust.json -OutFile .\CodePipelineTrust.json}
aws iam create-role --path /service-role/ --role-name "$IAMCodePipeline" --assume-role-policy-document file://CodePipelineTrust.json
$CodePipelinePolicyArn = (aws iam list-policies --query "Policies[?PolicyName=='$IAMCodePipeline'].{ARN:Arn}" --output text)
$CodePipelineRoleArn = (aws iam list-roles --query "Roles[?RoleName=='$IAMCodePipeline'].{ARN:Arn}" --output text)
aws iam attach-role-policy --role-name "$IAMCodePipeline" --policy-arn $CodePipelinePolicyArn
aws iam attach-role-policy --role-name "$CodeBuildRole" --policy-arn $CodePipelinePolicyArn

# ------ End of Roles and policys -------
# ------ Setup Networking stuff -------

aws ec2 create-security-group --description "$SecgrpLB" --group-name "$SecgrpLB"
aws ec2 authorize-security-group-ingress --group-name "$SecgrpLB" --protocol tcp --port 80 --cidr 0.0.0.0/0
$SecgrpLBid = aws ec2 describe-security-groups --query "SecurityGroups[?GroupName=='$SecgrpLB'].GroupId" --output text

start-sleep -Seconds 5

aws ec2 create-security-group --description "$ContainerSecgrpName" --group-name "$ContainerSecgrpName"
aws ec2 authorize-security-group-ingress --group-name $ContainerSecgrpName --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name $ContainerSecgrpName --protocol tcp --port 22 --cidr 0.0.0.0/0
$secgrpid = (aws ec2 describe-security-groups --query 'SecurityGroups[].GroupId' --group-names $ContainerSecgrpName).trim("[","]",'"',","," ") | Where-Object {$_ -ne ""}


# Load-balancer

write-host -ForegroundColor Green "Set up ESC cluster"
aws ecs create-cluster --cluster-name "$ECScluster" --capacity-providers FARGATE --default-capacity-provider-strategy capacityProvider=FARGATE,weight=1

aws elbv2 create-load-balancer --name $LBName1 --subnets $subnet[0] $subnet[1] $subnet[2] --security-groups (aws ec2 describe-security-groups --query "SecurityGroups[?GroupName=='$SecgrpLB'].GroupId" --output text) --region $Region
aws elbv2 create-target-group --name $LBgrpName --protocol HTTP --port 80 --target-type ip --vpc-id $VpcID --region $Region

$LBArn =(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(DNSName, '$LBname1')].LoadBalancerArn" --output text)
$TargetGroupArn =(aws elbv2 describe-target-groups --query "TargetGroups[?TargetGroupName=='$LBgrpName'].TargetGroupArn" --output text)

aws elbv2 create-listener --load-balancer-arn $LBArn --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TargetGroupArn --region $Region
$ListnerArn = (aws elbv2 describe-listeners --load-balancer-arn $LBArn --query "Listeners[].ListenerArn" --output text)

# ------- End of Networking stuff -------

# ------- Creating some json file -------
  ### Task define
write-host -ForegroundColor Green "Preper for setting up Task-Definition"
write-host -ForegroundColor Yellow "write to task-definition"
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
(Get-Content .\task-definition.json) -replace "<container name>", "$ContainerName" | Set-Content .\task-definition.json
(Get-Content .\task-definition.json) -replace "<your-account-id>", "$accountID" | Set-Content .\task-definition.json


  ### CODEBUILD
  
  if ((Test-Path .\codebuild.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/codebuild.json -OutFile .\codebuild.json}
  (Get-Content .\codebuild.json) -replace "<Build-name>", "$Buildname" | Set-Content .\codebuild.json
  (Get-Content .\codebuild.json) -replace "<repo>", "$ECSrepo" | Set-Content .\codebuild.json
  (Get-Content .\codebuild.json) -replace "<service-role>", "$CodeBuildRole" | Set-Content .\codebuild.json
  (Get-Content .\codebuild.json) -replace "<project-name>", "$project" | Set-Content .\codebuild.json
  (Get-Content .\codebuild.json) -replace "<Region>", "$Region" | Set-Content .\codebuild.json

  ### ClusterService
  write-host -ForegroundColor Yellow "write to ClusterService"
echo '{
    "cluster": "<cluster-name>",
	"serviceName": "<Service-name>",
	"taskDefinition": "<task-name>",
	"loadBalancers": [
	{
		"targetGroupArn": "<TargetGroupArn>",
		"containerName": "<container-name>",
		"containerPort": 80
	}
	],
	"desiredCount": 1,
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
 write-host -ForegroundColor Yellow "Write to CloudService"
 if ((Test-Path .\ClusterService.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/codebuild.json -OutFile .\ClusterService.json}
(Get-Content .\ClusterService.json) -replace "<task-name>", "$TaskDefinition" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<subnet-1>", "$($subnet[0])" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<subnet-2>", "$($subnet[1])" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<subnet-3>", "$($subnet[2])" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<cluster-name>", "$($ECScluster[2])" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<Service-name>", "$($ECSservice)" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<TargetGroupArn>", "$($TargetGroupArn)" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<container-name>", "$ContainerName" | Set-Content .\ClusterService.json
(Get-Content .\ClusterService.json) -replace "<secgrp>", "$secgrpid" | Set-Content .\ClusterService.json


  ### ECS

  write-host -ForegroundColor Yellow "Write to  userdata file for EC2 instances"
if ((Test-Path .\userdata.txt) -eq $false) {Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/userdata.txt" -OutFile .\userdata.txt}
(Get-Content .\userdata.txt) -replace "<registry uri>", "$($ECRrepo[0])" | Set-Content .\userdata.txt
(Get-Content .\userdata.txt) -replace "<image name>", "$($ECRrepo[1])" | Set-Content .\userdata.txt

  ### pipelineconfig
  write-host -ForegroundColor Yellow "write to pipeline config"
if ((Test-Path .\pipelineconfig.json) -eq $false) {Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/pipelineconfig.json -OutFile .\pipelineconfig.json}
(Get-Content .\pipelineconfig.json) -replace "<Pipeline-name>", "$CodePipeline" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<account-id>", "$accountID" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<Region>", "$Region" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<ECS-repo>", "$ECSrepo" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<Cluster-name>", "$ECScluster" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<Cluster-service>", "$ECSservice" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<Build-arn>", "$CodePipelineRoleArn" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<s3-bucket>", "$S3BucketName" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<ProjectName>", "$project" | Set-Content .\pipelineconfig.json

(Get-Content .\pipelineconfig.json) -replace "<ProdListenerArns>", "$ListnerArn" | Set-Content .\pipelineconfig.json
(Get-Content .\pipelineconfig.json) -replace "<targetGroups>", "$LBgrpName" | Set-Content .\pipelineconfig.json

# ------- End of writing to json files-------


write-host -ForegroundColor Yellow "Configure local repo"
git init
git add .
git commit -m 'Add simple web site'

# ------- Commit to ESC Repo -------  

write-host -ForegroundColor Green "Setting up ECS repo"
aws codecommit create-repository --repository-name "$ECSrepo" --repository-description "$ECSrepo"
$CommitHTTP = ((aws codecommit get-repository --repository-name $ECSrepo --query 'repositoryMetadata.cloneUrlHttp').replace('"',''))
git remote add origin $CommitHTTP
git push -u origin master

# ------- Create a simple EC2 with user data ------
write-host -ForegroundColor Yellow "Create a EC2 instances"
aws ec2 run-instances --image-id ami-07355fe79b493752d --count 1 --instance-type t2.micro --key-name $Keyname --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2name}]" --user-data "file://userdata.txt" --iam-instance-profile Name=$IAMRole --security-groups $ContainerSecgrpName

# ------- End of simple EC2 with user data ------


# ------- Register task ------- 
write-host -ForegroundColor Green "Start to create Task-Definition"
aws ecs register-task-definition --family "$TaskDefinition" --cli-input-json file://task-definition.json --cpu 256 --memory 512 --execution-role-arn arn:aws:iam::389058819117:role/ecsTaskExecutionRole


# ------- Create Service ------
write-host -ForegroundColor Green "Preper for setting up Cluster Services"
# ClusterService
write-host -ForegroundColor Green "Start to create Cluster Services"
aws ecs create-service --cluster "$ECScluster" --service-name "$ECSservice"  --cli-input-json file://ClusterService.json --desired-count 1 --task-definition "$TaskDefinition"


# ------- Craeting project CodeBuild -------
Write-host -ForegroundColor Yellow "Start creating Project"
aws codebuild create-project --cli-input-json file://codebuild.json
Write-host -ForegroundColor Yellow "Start Build Project"
aws codebuild start-build --project-name $project


# ------- CodePipeline

write-host -ForegroundColor Yellow "Now to creating the pipeline"

write-host -ForegroundColor Red "Now for the real pipeline"

aws codepipeline create-pipeline --cli-input-json file://pipelineconfig.json

write-host -ForegroundColor Yellow  "Pipeline in progress"
Start-Sleep -Seconds 60

$pipelinestatus = (aws codepipeline get-pipeline-state --name $project --query 'stageStates[?latestExecution].actionStates[].latestExecution.status').trim("[","]",'"',","," ") | Where-Object {$_ -ne ""}
while ($pipelinestatus -contains "InProgress" ){
    
    write-host -ForegroundColor Yellow  "Pipeline in progress"
    start-sleep -Seconds 30
    $pipelinestatus = (aws codepipeline get-pipeline-state --name $project --query 'stageStates[?latestExecution].actionStates[].latestExecution.status').trim("[","]",'"',","," ") | Where-Object {$_ -ne ""}
}

if ($pipelinestatus -contains "Failed") {
    Write-Host -ForegroundColor Red "something went wrong with the pipeline"
    break
}
elseif ($pipelinestatus -contains "Abandoned") {
    Write-Host -ForegroundColor Red "Someone stopped the pipeline"
    break
}

Write-Host -ForegroundColor Green "Pipeline Succeeded"

$LBDNSName =aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(DNSName, '$LBname1')].DNSName" --output text
explorer http://$LBDNSName