# Installing an BioSoundsLab instance for development
Instructions for installing BioSoundsLab on Linux.

System requirements for development:
* 8-16GB RAM
* 4+ CPU cores
* Sudo access

Required software
* Git
* Docker and Docker-Compose
* Python and Conda (Miniconda3 suffices)

Clone the repository and checkout the desired branch
```
git clone git@github.com:MfN-Berlin/biosoundslab.git biosoundslab
cd biosoundslab
git checkout main
```

Make a copy of the environment variables file for development
```
cp env-default .env
```

Open the `.env` file in an editor and set at least:
* DB_NAME=ecomon
* BASE_DATA_DIRECTORY=./Data
* PGBACKUP_PATH=/tmp
* SUB_PATH=/biosoundslab

Create a python environment with python3.11 and poetry
```
conda create -n biosoundslab python=3.11
conda activate biosoundslab
curl -sSL https://install.python-poetry.org | python3 -
sudo apt install libsecret-1-0 libsecret-1-dev dbus-user-session
python3 -m pip install --upgrade secretstorage keyrings.alt
conda deactivate
conda activate biosoundslab
```

Start Docker containers
```
docker compose -f docker-compose.yaml up -d
```

Install backend dependencies
```
cd backend
poetry install --with dev
poetry run update-labels
```

Install frontend dependencies
```
cd ../frontend/
npm install
```

Create extra database schemas and views
```
cd ../
/scripts/create_extra_tables.sh biosoundslab-db-1 ecomon ecomon
```

## Start the application
In the folder where you clobned the source
```
./scripts/biosoundslab-dev.sh start
tail -n1000 -f /tmp/biosoundslab.log
```

You can now open the application in a browser on http://localhost:3000/biosoundslab

## Editing
In the development environment, changes to the folders frontend and backend are reflected immediately.

Traefik will route http://localhost/biosoundslab to the frontend, http://localhost/static/files to the backend files endpoint and http://localhost/biosoundslab/api/v1/graphql to the hasura graphql endpoint

If you want to do changes on Hasura Metadata, you can open the Hasura UI at http://localhost:8080/console/login

If you want to see scheduled jobs, you can open the Airflow UI at http://localhost/biosoundslab/airflow/login/
