# AWS
### Description
In this exercise we will be working with Docker to create a webapplication with a loadbalancer and autoscaling group in AWS




```powershell
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

# Setup variables for script
$RepositoryNames = "docker-mynginx2023"
$Region = (aws configure get region)
$ContainerName = "mynginx2023" 
$Dir = "C:\AWS\Docker"
$dockerimage = "mynginx2023"
$dockername = "MyNginx"

#Create our main directory for the exercies
if ((test-path $dir) -eq $false) {mkdir $Dir}
cd $Dir

#Check if necessary files and module e exist
if ((Test-Path .\dockerfile) -eq $false) {
    write-host -ForegroundColor Yellow "dockerfile don't exist on system, download it to main directory"
    Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/dockerfile -OutFile .\dockerfile
    }
else {write-host -ForegroundColor Green "dockerfile exist in directory"} 
if ((Test-Path .\buildspec.yml) -eq $false) {
    write-host -ForegroundColor Yellow "buildspec.yml don't exist on system, download it to main directory"
    Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/buildspec.yml -OutFile .\buildspec.yml
    }
else {write-host -ForegroundColor Green "buildspec.yml exist in directory"} 
if ((Test-Path .\appspec.yml) -eq $false) {
    write-host -ForegroundColor Yellow "appspec.yml don't exist on system, download it to main directory"
    curl -O https://s3.amazonaws.com/aws-codedeploy-us-east-1/samples/latest/SampleApp_Linux.zip; tar -xf .\SampleApp_Linux.zip; Remove-Item .\SampleApp_Linux.zip
    }
else {write-host -ForegroundColor Green "appspec.yml exist in directory"}

write-host -ForegroundColor Yellow "download index.html to main directory"
Invoke-WebRequest -Uri https://github.com/Norra-frenzu/AWS/raw/main/lib/buildspec.yml -OutFile .\buildspec.yml


#Create Docker build and print the index file on docker container for a fast check if working
docker build -t $dockerimage .
docker run -d -p 80:80 --name $dockername $dockerimage
$dockerlocalhost = (docker exec -it $dockername /bin/bash -c "curl localhost")
$localhost = (Invoke-RestMethod localhost)
if ((Compare-Object -ReferenceObject $dockerlocalhost -DifferenceObject $localhost) -match "test") {write-host -ForegroundColor Green "Local docker container deployed correctly"}
else {
        Write-Host -ForegroundColor Red "Something went wrong with local docker deployment" 
        break
}

write-host "test"
# docker run -lt mynginx2023 /bin/bash

#Setup locally repository in our main directory and make the first commit to it
git init
git add .
git commit -m 'Add simple web site'



#Create CodeCommit Rpository 
aws codecommit create-repository --repository-name $RepositoryNames --repository-description "$RepositoryNames"



git remote add origin https://git-codecommit.eu-west-1.amazonaws.com/v1/repos/$RepositoryNames
git push -u origin main

#git clone https://git-codecommit.eu-west-1.amazonaws.com/v1/repos/$RepositoryNames

#Create Elastic Container Registry Repository
aws ecr create-repository --repository-name $RepositoryNames
$repo = ((aws ecr describe-repositories --repository-names $RepositoryNames --query 'repositories[0].repositoryUri').replace('"',"").split("/"))
if ((Test-Path .\buildspec.yml) -eq $false) {Invoke-WebRequest -Uri https://github.com/larsappel/ECSDemo/raw/main/buildspec.yml -OutFile .\buildspec.yml}
(Get-Content .\buildspec.yml) -replace "<registry uri>", "$($repo[0])" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<image name>", "$($repo[1])" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "<region>", "$Region" | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace "MyContainerName", "$ContainerName" | Set-Content .\buildspec.yml


Docker tag $dockerimage $repo[0]/$RepositoryNames


aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin $repo[0]
docker push $repo[0]/$RepositoryNames:latest

aws ecr describe-images --repository-name $RepositoryNames
```


### userdata
```bash
#!/bin/bash
# Install docker
dnf update -y
dnf install docker -y
systemctl start docker
systemctl enable docker
# Install ECR credential helper
dnf install -y amazon-ecr-credential-helper
mkdir -p /root/.docker
cat <<EOF > /root/.docker/config.json
{
"credsStore": "ecr-login"
}
EOF
# Run docker container
docker run -d -p 80:80 389058819117.dkr.ecr.eu-west-1.amazonaws.com/docker-mynginx2023

```


