# Installing an Ecomon instance for development
Instructions for installing Ecomon on a Linux server.

## System requirements for production:
* 250GB+ RAM
* 25+ CPU cores
* 2+ GPU
* 8TB on a fast disk to hold the database
* 70TB+ to store audio data and for backups, e.g. on a 3fs storage
* Sudo access

Required software
* CUDA Version: 12.4
* Git
* Docker and Docker-Compose

## Clone the repository into the desired directory (ecomon_SITENAME_MODELNAME)
```
sudo GIT_SSH_COMMAND='ssh -i path-to-your-id_rsa' git clone git@github.com:MfN-Berlin/ecomon.git ecomon_SITENAME_MODELNAME
sudo chown -R "$USER":akwamo ecomon_SITENAME_MODELNAME
cd ecomon_SITENAME_MODELNAME
```
Check that you are on the correct branch: `git status` should give "new-main"

## Configuration
Make a copy of the environment variables file for development
```
cp env-production .env
```

Open the `.env` file in an editor and set at least:
* DB_PASSWORD=secure-password
* DB_ROOT_PASSWORD=secure-password
* BASE_DATA_DIRECTORY=path-to-audio-dir  # needs 50TB+, e.g. on 3fs storage
* PGBACKUP_PATH=path-to-backup-dir  # needs 20TB+, e.g. on 3fs storage
* DOMAIN=your-domain-or-ip
* SUB_PATH=/your-subpath  # if you change this, then you will have to rebuild the frotend container
* PGDATA_PATH=path-to-custom-place-for-database-data  # important: db needs 8TB+ on fast disk
* AIRFLOW_ADMIN_PASSWORD=secure-password
* HASURA_ADMIN_SECRET=secure-password
* HASURA_URL=pdefault-docker-compose-gateway (typically 172.17.0.1, used by Dashboard)
* USE_GPU=1  # 1, 2, or all
* TMP_DIR=/mnt/akwamotmp/your-subpath # this should be unique, and should exist
* PGBACKUP_PATH=/mnt/akwamodb/unique-name # this should be unique, and should exist, and by convention the name should end with "_backup"
* Make sute PROTOCOL is https

Make sure that these are the same in .env and/or docker-compose.production.yaml:
* The port in .env HASURA_URL should be unique and the port exposed by the graphql-engine service in docker.compose.production.yaml
* Port to dashboard service
* Port to DB service should be unique. This port does not need to be maped in docker.compose.production.yaml for the system to work, only if you want to tunnel to the database for debugging or extra queries.

Check that PGDATA_PATH exista and contains wav data.
Check that TMP_DIR, PGBACKUP_PATH exist, is not used by another instance, or else create it.

Give the redis service in docker-compose.production.yaml a unique name

In .env, set the ENTRY_PORT to the port this instance of ecomon should listen to. This is the entry port that your reverse-proxy (which might be on another machine) is mapping the URL https://your-ip-adress/SUB_PATH to.

## Multiple instances
If you need multiple instances of ecomon, then the recommended solution is to put each instance in its own virtual machine.

However, if you need to install multiple instances on the same (virtual) machine, you will need to make a local fork of the repository, and rebuild the frontend container, after setting the environment variables as above.

(again, only do this when installing multiple instances on the same VM)
```
git branch NAME-OF-INSTANCE
git checkout NAME-OF-INSTANCE
cd frontend
docker build -f Dockerfile -t ghcr.io/mfn-berlin/ecomon-frontend:NAME-OF-INSTANCE .
```

Edit `docker-compose.production.yml` and set the image name of the frontend service to: `ghcr.io/mfn-berlin/ecomon-frontend:NAME-OF-INSTANCE`.

## Start Docker containers
```
docker compose -f docker-compose.production.yaml up -d
```
This should start these containers:
* NAME-OF-INSTANCE-dashboard-1
* NAME-OF-INSTANCE-airflow-1
* NAME-OF-INSTANCE-db-migrate-1
* NAME-OF-INSTANCE-api-1
* NAME-OF-INSTANCE-traefik-1
* NAME-OF-INSTANCE-worker-1
* NAME-OF-INSTANCE-frontend-1
* redis-NAME-OF-INSTANCE
* NAME-OF-INSTANCE-graphql-engine-1
* NAME-OF-INSTANCE-db-1

And these networks:
* NAME-OF-INSTANCE_ecomon
* NAME-OF-INSTANCE_traefik-ingress

## Database
Make sure the database is writing to the PGDATA_PATH set in .env.

Run the script `scripts/create_extra_tables.sh` to create the partitioned tables for holding the inferences. These tables are partitioned, as Hasura doesn´t handle partitioned tables, these have to be created manually.

The default configuration is to create 200 partitions each holding the inferences generated from 25.000 records. So ideally the number of records should not exceed 5.000.000. Depending on the expected number of inferences per record and the total number of records, you can change the parameters PARTITION_COUNT and RECORDS_PER_PARTITION inside the script. These parameters will affect the performance of the system in a great measure, so give them a thought before starting the script.

So for example

`PARTITION_COUNT=200 RECORDS_PER_PARTITION=25000 ./scripts/create_extra_tables.sh NAME-OF-INSTANCE-db-1 ecomon passwd`

The site should now be accessible. See docs folder on how to enter new data.

## Troubleshooting
To see what's running, cd into the installation directory and do:
`docker compose ps`

To see some logs, do:
`docker logs -f -n1000 NAME-OF-DOCKER-CONTAINER`, the "worker" container is a good place to start.
