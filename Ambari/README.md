# Ambari3 installation instructions
Followed along with this youtube video:
https://www.youtube.com/watch?v=Ao95xAGsA20

Scripts based on this repo:
https://github.com/call518/ambari-3.0-hadoop-ops-course

Other useful information can be found here:
https://ambari.apache.org/docs/3.0.0/quick-start/environment-setup/docker-environment-setup

Major differences is the streamlined installation for Windows environments, and minor bug fixes to scripts and docker-compose file


## <a name="start"></a> Start the containers
```
docker compose up -d
```

## Run the Scripts
If on windows:
```
.\run.ps1
```

If on *nix:
```
# Makes all the script executable, pre-requisite
find . -name "*.sh" -exec chmod +x {} \;

./run.sh
```

## Setup Cluster
You can now login to http://localhost:8080 (U: admin, P: admin) to setup the cluster

### Configuration
* When asked for the baseURL, supply http://bigtop-hostname0.demo.local. Your OS is Redhat 8 based.
* When asked for installation nodes, list all nodes:
```
bigtop-hostname0.demo.local
bigtop-hostname1.demo.local
bigtop-hostname2.demo.local
bigtop-hostname3.demo.local
```
* To get the SSH private key from Host 0:
```
docker exec -it bigtop-hostname0 bash -c 'cat ~/.ssh/id_rsa'
```
* Restart Ambari if you encounter any issues:
```
docker exec -it bigtop-hostname0 bash -c 'ambari-server restart'
```

# Installing on AWS

### Created instance:
m4.2xlarge with Amazon Linux 2 100 GB storage Moviri and Ambari Security Groups

[Installing Docker AL2](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-docker.html)

AWS Installs Docker 25.0.8 by default, which doesn't install `docker compose` by default.

[Installing Docker Compose plugin on Linux](https://docs.docker.com/compose/install/linux/#install-the-plugin-manually)

Follow the [Run the Script](#start) documentation to run on linux