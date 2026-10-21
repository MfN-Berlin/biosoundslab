# Transfer data from another instance of Ecomon

Once a new instance of BioSoundsLab has been setup (see: INSTALL_DEV.md, INSTALL_PRID.md), you might want to transfer existing data into it.

1. Make a binary backup of the original database
```
pg_basebackup -Uecomon -D /path/to/backup/directory -P
```

2. If in a production environment, point the environment variable PGDATA_PATH in .env to the binary backup.

3. Start the containers for the new BioSoundsLab instance. The database container should start and keep running, with the data from the backup. Other containers might not start at this point, ignore them for now.

4. Exec into the container where the database is running, open the databse in psql, change the password of the BioSoundsLab user to what is set in .env.
```
docker exec -ti database-container bash
psql -Umy_user -decomon
\du
ALTER USER my_user WITH PASSWORD 'new_password';
```
* 'my_user' shuld correspond with DB_USERNAME as set in .env.
* 'new_password' should correspond to DB_PASSWORD as set in .env.

5. Restart the containers. Now all containers should run.

# Transfer specific records
Instead of transfering the complete database, you can transfer specific records selected by site and date

This will export the relevant data from into these csv files
```
locations.csv
model_inference_logs.csv
models.csv
records.csv
site_directories.csv
site_reports.csv  sites.csv
```

## Usage

Export all data (original behavior)

`./export_minimal_data.sh container_name user password site_prefix`

Export data from a specific date onwards

`./export_minimal_data.sh container_name user password site_prefix ecomon 01.01.2025`

Export data between two dates (inclusive)

`./export_minimal_data.sh container_name user password site_prefix ecomon 01.01.2025 31.01.2025`

Export data up to a specific date

`./export_minimal_data.sh container_name user password site_prefix ecomon "" 31.12.2025`

Then import the data into the new database:

```
docker cp  <export_dir> <container_name>:/tmp
./import_minimal_data.sh <container_name> <db_user> <db_password> /tmp/<export_dir>
```
For more options see ./import_minimal_data.sh

# Transfer inference data from another instance of BioSoundsLab

**export_model_inference_results.sh**

The script scripts/export_model_inference_results.sh exports inference results of a given location and model(s) to CSV. Then use psql to import the CSV into the new database. See inline documentation in the script for examples.

**export_model_inference_logs.sh**

The script scripts/export_model_inference_logs.sh exports model inference logs from a PostgreSQL database to a CSV file for a specific site. It accepts command-line arguments to connect to either a local PostgreSQL database or one running in a Docker container, specifying credentials, database name, and the target site ID. The script then queries the database and exports the results to a CSV file.

**export_mir_max_confidence.sh**

This script exports the maximum confidence values from model inference results max confidence table for a specific site to a CSV file. It allows users to specify connection details for a PostgreSQL database, either locally or within a Docker container, using command-line arguments. The script processes these arguments, connects to the database, and generates a CSV file containing the desired data.
