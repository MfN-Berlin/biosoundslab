# Automation

Automation is controlled through Airflow. The Airflow UI can be accessed at: http://localhost/biosoundslab_next/airflow

## PostgreSQL Backup DAG

### Overview
The `postgres_weekly_backup` DAG performs automated weekly SQL dumps of the PostgreSQL database with compression, chunking, verification, and rotation management.

### Schedule
- **Frequency**: Weekly (every Friday at 21:00)
- **Max Active Runs**: 1 (prevents overlapping backup operations)

### Tasks

#### 1. Create Backup (`create_backup`)
- **Type**: BashOperator (NoTemplateBashOperator)
- **Function**:
  - Executes `pg_dump` to create a SQL dump of the PostgreSQL database
  - Creates a timestamped dump directory: `sql_dump_YYYYMMDD_HHMMSS`
  - Writes the dump file: `dump_YYYYMMDD_HHMMSS.sql`
  - Stores the timestamp in `/backup/current_timestamp.txt` for subsequent tasks
- **Configuration**:
  - Uses environment variables: `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`
  - Backup location: `/backup` directory in the container
  - Format: Plain SQL dump

#### 2. Compress Backup (`compress_backup`)
- **Type**: BashOperator (NoTemplateBashOperator)
- **Function**:
  - Reads the timestamp from the previous task
  - Creates a tar.gz stream of the SQL dump file and splits it into chunks
  - Removes the original uncompressed SQL dump file to save space
- **Output**: `/backup/backup_YYYYMMDD_HHMMSS/sql_dump_YYYYMMDD_HHMMSS.tar.gz.part0000` (and subsequent parts)

#### 3. Verify Backup (`verify_backup`)
- **Type**: BashOperator (NoTemplateBashOperator)
- **Function**:
  - Verifies backup directory exists and chunk files are present
  - Ensures all chunks are non-empty and totals size across chunks
  - Validates chunk sequence (basic completeness check)

#### 4. Rotate Backups (`rotate_backups`)
- **Type**: BashOperator (NoTemplateBashOperator)
- **Function**:
  - Lists all existing backup directories sorted by date (newest first)
  - Keeps only the `MAX_BACKUPS` most recent backups
  - Deletes older backups to manage disk space
  - Cleans up the temporary timestamp file
- **Configuration**: Uses `MAX_BACKUPS` environment variable (default: 3)

#### Time required for backup
The time required for running a backup is relatively long, so backups have to be planed, specifically the transfer to a safe location requires consideration.

| Task | Approximate duration in hh:mm |
|---|---|
| Dumping DB to files  | 06:00 |
| Compressing files to archive | 12:00 |
| Checking compressed archive | 00:30 |
| Manually transfer to safe location | 04:30 |
| Total time for full backup  | 23:00 |


### Task Dependencies
After the backup is terminated, the file should be downloaded from the server and stored in a safe location ("Z"). To manually copy the backup, do `rsync -P denbi-gpu:source-path destination-path-on-Z` where denbi-gpu is your SSH configuration to connect to the server. Make sure there is enough space on destination-path-on-Z.

### Restoring a backup
see: backup_restoration.txt

## Create Report DAG

### Overview
The `create_report` DAG generates a comprehensive workflow status report that tracks the data processing pipeline from raw WAV files through database import to BirdNET model inference. This report provides visibility into data flow, processing status, and potential bottlenecks across all monitoring sites.

### Schedule
- **Frequency**: Daily at 03:00 AM
- **Catchup**: Disabled (only runs for current date)

### Purpose
The DAG creates a daily snapshot of the system's data processing status by:
1. Scanning file system for WAV files
2. Comparing file counts with database records
3. Tracking BirdNET model inference progress
4. Identifying processing bottlenecks and data discrepancies
5. Storing historical reports for trend analysis

### Tasks

#### 1. Get Sites from Database (`get_sites_from_db`)
- **Type**: Python task
- **Function**: Fetches all site IDs and prefixes from the `sites` table
- **Output**: List of dictionaries with `site_id` and `prefix`

#### 2. Create Report Table (`create_report_table`)
- **Type**: Python task
- **Function**:
  - Creates the `workflow_reports` table if it doesn't exist
  - Defines schema with columns for all workflow metrics
  - Creates indexes on `report_date`, `site_id`, and `prefix` for query performance
- **Table Schema**:
  - `id`: Primary key
  - `report_date`: Timestamp of report generation
  - `prefix`: Site prefix (e.g., "TEST")
  - `site_id`: Foreign key to sites table
  - `wav_size_bytes`: Total size of WAV files in bytes
  - `wav_count`: Number of WAV files
  - `record_count`: Number of database records
  - `db_import`: Import status ("ready", "ready with losses", "pending", or empty)
  - `birdid_medium_processed`: Count of records processed by BirdNET
  - `birdid_medium`: BirdNET processing status
  - `birdid_medium_visible`: Count of records with max confidence scores (visible in UI)
  - `visible_in_ui`: Boolean flag for UI visibility
  - `created_at`: Record creation timestamp

#### 3. Get Record Counts (`get_record_counts_from_db`)
- **Type**: Python task
- **Function**: Queries the `records` table to count imported records per site
- **Output**: Dictionary mapping `site_id` to record count

#### 4. Get BirdNET Processed Counts (`get_birdid_medium_processed_counts`)
- **Type**: Python task
- **Function**:
  - Counts unique records that have been processed by BirdNET (model_id=3)
  - Queries `model_inference_logs` table
- **Output**: Dictionary mapping `site_id` to processed record count

#### 5. Get BirdNET Visible Counts (`get_birdid_medium_visible_counts`)
- **Type**: Python task
- **Function**:
  - Counts records with max confidence scores (visible in UI)
  - Queries `model_inference_results_max_confidence` table for model_id=3
- **Output**: Dictionary mapping `site_id` to visible record count

#### 6. Get Running Inference Jobs (`get_running_inference_jobs`)
- **Type**: Python task
- **Function**:
  - Identifies sites with currently running BirdNET inference jobs
  - Queries `jobs` table for status='running' and topic='model_inference_site'
  - Extracts site_id from job metadata JSON
- **Output**: Set of site IDs with active inference jobs

#### 7. Create Report (`create_report`)
- **Type**: Python task
- **Function**:
  - Walks the `/data` directory tree
  - Identifies first-level subdirectories (site prefixes)
  - Lists files in each directory
- **Output**: List of dictionaries with directory path, files, and root path

#### 8. List WAV Files (`list_wavs`)
- **Type**: Python task
- **Function**: Counts WAV files (`.wav` extension) in each directory
- **Output**: List with directory, WAV count, and root path

#### 9. Calculate WAV Sizes (`calculate_wav_sizes`)
- **Type**: Python task
- **Function**:
  - Calculates total size of all WAV files per directory
  - Handles file access errors gracefully with warnings
- **Output**: List with directory, WAV count, and total size in bytes

#### 10. Aggregate by Prefix (`aggregate_wav_data_by_prefix`)
- **Type**: Python task
- **Function**:
  - Groups WAV counts and sizes by site prefix
  - Matches prefixes to site IDs using the sites lookup
  - Aggregates multiple subdirectories under the same prefix
- **Output**: List of aggregated data per prefix with site_id

#### 11. Calculate Import Statuses (`calculate_import_statuses`)
- **Type**: Python task
- **Function**:
  - Calculates `db_import` status by comparing WAV count to record count
  - Calculates `birdid_medium` status by comparing record count to processed count
  - Status logic:
    - **Empty**: No records in database
    - **"ready"**: Counts match exactly (difference = 0)
    - **"ready with losses"**: Difference ≤ 10 files
    - **"pending"**: Difference > 10 files
    - **"running"**: Active inference job detected
- **Configuration**: `MAX_DIFF = 10` (acceptable difference threshold)
- **Output**: Enriched data with status fields

#### 12. Transform Data (`transform_data`)
- **Type**: Python task
- **Function**:
  - Converts list to pandas DataFrame
  - Orders columns for consistent output
  - Sorts by prefix alphabetically
- **Output**: Sorted DataFrame

#### 13. Print Report (`print_report`)
- **Type**: Python task
- **Function**:
  - Logs detailed report to Airflow logs
  - Formats file sizes in MB
  - Shows all metrics per site
- **Output**: Log entries (no return value)

#### 14. Save Report to Database (`save_report_to_db`)
- **Type**: Python task
- **Function**:
  - Deletes today's existing report (prevents duplicates on re-runs)
  - Cleans up reports older than 30 days
  - Inserts new report rows into `workflow_reports` table
  - One row per site/prefix
- **Output**: Count of rows inserted

## Populate Max Confidence Table DAG

### Overview

The `Populate_Max_Table_Test` DAG creates and maintains a materialized table (`model_inference_results_max_confidence`) containing the maximum confidence inference results for each unique combination of `record_id`, `label_id`, and `model_id` from 200 partitioned source tables. This optimized table significantly improves query performance for the dashboard by pre-computing the highest confidence predictions.

### Purpose

- **Performance Optimization**: Pre-aggregates maximum confidence values to avoid expensive window functions in queries
- **Incremental Processing**: Only processes partitions with new data, reducing processing time
- **Zero Downtime**: Uses a staging table pattern to ensure the main table is always available
- **Data Integrity**: Preserves existing data when partitions are skipped
- **Monitoring**: Tracks processing history and performance metrics

### Schedule

- **Frequency**: Daily at 4:00 AM (Monday to Friday)
- **Timezone**: UTC
- **Catchup**: Disabled

### DAG Structure

#### Tasks

1. **ensure_and_clear_tables** - Setup and initialization
2. **process_all_partitions** - Data processing
3. **summarize_migration** - Performance reporting
4. **swap_tables** - Data deployment

#### Task Dependencies
ensure_and_clear_tables >> process_all_partitions >> summarize_migration >> swap_tables

Notes
* The DAG preserves all existing data during merges
* Progress tracking is never cleared, providing historical metrics
* Staging table may contain data from incomplete runs (handled by UPSERT logic)
* First run behavior differs (rename vs merge)
* Designed for model_id = 3 only (modify filter if needed)
* Zero downtime: Main table always available for queries during processing


============================

## Run Inferences DAG
Automates the process of running machine learning model inferences on data stored in a PostgreSQL database.

### Overview
The DAG runs at 9:00 PM on weekdays (Monday through Friday) and orchestrates the process of identifying which machine learning models need to run inferences, then triggers those inference jobs through an API.

### Detailed Workflow
1. check_report_table_exists: Verifies if the required workflow_reports table exists in the database

Action: Executes a SQL query to check if the table exists in the public schema

Output: Returns a boolean indicating whether the table exists

2. get_models_needing_processing: Identifies which models need to run inferences

Action: Queries the workflow_reports table for models with:
Status of 'pending' or 'partial'
The most recent report date
Records that still need processing (calculated as record_count - model_processed - skipped_records)

Filtering: Limits to 2 models per run (configurable)

Output: Returns a list of dictionaries containing:
* site_id: The site identifier
* model_name: The name of the model
* records_to_process: Number of records needing inference

3. trigger_inference_job: Triggers inference jobs for each model that needs processing

Action: For each model identified:
Looks up the model ID from the models table
Determines the date range for inference (default: last 6 months, or the actual date range of available data)
Constructs a GraphQL mutation request
Sends the request to an API endpoint (configured via API_URL environment variable)
Handles the API response

Output: Returns the job ID if successful, or None if failed
Technical Details
API Integration: Uses GraphQL to trigger inference jobs through a POST request
Date Handling: Automatically determines the appropriate date range for each inference job
Error Handling: Includes basic error handling for API requests and missing configurations

Security: Respects SSL verification settings via API_VERIFY_SSL environment variable

Logging: Provides detailed logging at each step of the process

Purpose
This DAG serves as an automated pipeline to:

* Identify which machine learning models need to run on which data
* Trigger those inference jobs through an API
* Handle the scheduling and orchestration of these jobs

The workflow is designed to be efficient by only processing models that have pending or partially completed work, and by limiting the number of models processed in each run.