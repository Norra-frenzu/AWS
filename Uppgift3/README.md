# AWS
### Description
In this exercise we will be working with Docker to create a webapplication with a loadbalancer and autoscaling group in AWS




```powershell
# Setup variables for script
$RepositoryNames = "docker-mynginx2023"
$Region = "eu-west-1"
$ContainerName = "mynginx2023" 
$Dir = "C:\AWS\Docker"

#Create our main directory for the exercies
mkdir $Dir && cd $Dir

#Check if necessary files and module e exist
if ((Test-Path .\dockerfile) -eq $false) {
    write-host "buildspec.yml don't exist on system, download it to main directory"
    Invoke-WebRequest -Uri https://github.com/larsappel/ECSDemo/raw/main/Dockerfile -OutFile .\dockerfile
    }
if ((Test-Path .\buildspec.yml) -eq $false) {
    write-host "buildspec.yml don't exist on system, download it to main directory"
    Invoke-WebRequest -Uri https://github.com/larsappel/ECSDemo/raw/main/buildspec.yml -OutFile .\buildspec.yml
    }
else {write-host "buildspec.yml exist in directory"} 
if ((Test-Path .\appspec.yml) -eq $false) {
    write-host "appspec.yml don't exist on system, download it to main directory"
    curl -O https://s3.amazonaws.com/aws-codedeploy-us-east-1/samples/latest/SampleApp_Linux.zip && tar -xf .\SampleApp_Linux.zip && Remove-Item .\SampleApp_Linux.zip
    }
else {write-host "appspec.yml exist in directory"}


#Create Docker build
docker build -t mynginx2023 .
docker exec -it mynginx2023 /bin/bash "dnf update -y; dnf install nginx -y"
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
(Get-Content .\buildspec.yml) -replace “<registry uri>”, “$($repo[0])” | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace “<image name>”, “$($repo[1])” | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace “<region>”, “$Region” | Set-Content .\buildspec.yml
(Get-Content .\buildspec.yml) -replace “MyContainerName”, “$ContainerName” | Set-Content .\buildspec.yml


Docker tag mynginx2023 $repo[0]/$RepositoryNames


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


