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
$RepositoryNames = "docker-mynginx2023"
$Region = (aws configure get region)
$ContainerName = "mynginx2023" 
$Dir = "C:\AWS\Docker"
$dockerimage = "mynginx2023"
$dockername = "MyNginx"
$Keyname = "fredrik"
$EC2name = "Docker-nginx"
$IAMRole = "testEcrReadOnlyRole"
$secgrpname = "docker-http/ssh"

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
Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/buildspec.yml" -OutFile .\buildspec.yml


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
$repo = ((aws ecr describe-repositories --repository-names $RepositoryNames --query 'repositories[0].repositoryUri').replace('"',"").split("/"))
if ((Test-Path .\buildspec.yml) -eq $false) {Invoke-WebRequest -Uri https://github.com/larsappel/ECSDemo/raw/main/buildspec.yml -OutFile .\buildspec.yml}
(Get-Content .\buildspec.yml) -replace "<registry uri>", "$($repo[0])" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<image name>", "$($repo[1])" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<region>", "$Region" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "MyContainerName", "$ContainerName" | Set-Content .\buildspec.yml

# craete a login link between AWS ECR user and Docker user
aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $repo[0]

# Tag docker image with repo name and push to AWS ECR
Docker tag $dockerimage "$($repo[0])/$($RepositoryNames):latest"
docker push "$($repo[0])/$($RepositoryNames):latest"


aws ecr describe-images --repository-name $RepositoryNames


# check if IAM roles exist and create if not
$extRoles = (aws iam list-roles --query 'Roles[*].RoleName').trim()
if ($IAMRole -notcontains $extRoles) {
    write-host -ForegroundColor Yellow "download role.json to main directory"
    Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/role.json" -OutFile .\role.json
    # aws iam create-instance-profile --instance-profile-name $IAMRole
    # aws iam create-role --role-name $IAMRole --assume-role-policy-document file://role.json
    # aws iam attach-role-policy --role-name $IAMRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    # aws iam add-role-to-instance-profile --instance-profile-name $IAMRole --role-name $IAMRole
}
write-host -ForegroundColor Yellow "Create instance profile with role"
    aws iam create-instance-profile --instance-profile-name $IAMRole
    aws iam create-role --role-name $IAMRole --assume-role-policy-document file://role.json
    aws iam attach-role-policy --role-name $IAMRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam add-role-to-instance-profile --instance-profile-name $IAMRole --role-name $IAMRole

#

write-host -ForegroundColor Yellow "Setup userdata file for EC2 instances"
Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/userdata.txt" -OutFile .\userdata.txt
(Get-Content .\userdata.txt) -replace "<registry uri>", "$($repo[0])" | Set-Content .\userdata.txt
(Get-Content .\userdata.txt) -replace "<image name>", "$($repo[1])" | Set-Content .\userdata.txt

start-sleep -Seconds 5

aws ec2 create-security-group --description "$secgrpname" --group-name "$secgrpname"
aws ec2 authorize-security-group-ingress --group-name $secgrpname --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-name $secgrpname --protocol tcp --port 22 --cidr 0.0.0.0/0

write-host -ForegroundColor Yellow "Create a EC2 instances"
aws ec2 run-instances --image-id ami-07355fe79b493752d --count 1 --instance-type t2.micro --key-name $Keyname --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$EC2name}]" --user-data "file://userdata.txt" --iam-instance-profile Name=$IAMRole --security-groups $secgrpname




#ECS
Invoke-WebRequest -Uri "https://github.com/Norra-frenzu/AWS/raw/main/lib/codedeployrole.json" -OutFile .\codedeployrole.json
aws iam create-role --path /service-role/ --role-name "codebuild2-$IAMRole" --assume-role-policy-document file://codedeployrole.json
aws iam attach-role-policy --role-name "codebuild2-$IAMRole" --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser
aws iam attach-role-policy --role-name "codebuild2-$IAMRole" --policy-arn arn:aws:iam::389058819117:policy/service-role/CodeBuildBasePolicy-docker-nginx-eu-west-1
aws iam attach-role-policy --role-name "codebuild2-$IAMRole" --policy-arn arn:aws:iam::389058819117:policy/service-role/CodeBuildVpcPolicy-docker-nginx-eu-west-1

git init
git add .
git commit -m 'Add simple web site'

aws codecommit create-repository --repository-name "$RepositoryNames-ECS" --repository-description "$RepositoryNames-ECS"
$CommitHTTP = ((aws codecommit get-repository --repository-name $RepositoryNames-ECS --query 'repositoryMetadata.cloneUrlHttp').replace('"',''))
git remote add origin $CommitHTTP
git push -u origin master


