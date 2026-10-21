#!/bin/bash
# filepath: /home/alvaro/Workspace/biosoundslab_validate/scripts/create_extra_tables.sh

# Script to create partitioned inference results table and view
# Usage: ./create_extra_tables.sh <container_name> <db_user> <db_password>

set -e  # Exit on error

# Check arguments
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <container_name> <db_user> <db_password>"
    echo "Example: $0 biosoundslab-db ecomon mypassword"
    exit 1
fi

CONTAINER_NAME=$1
DB_USER=$2
DB_PASSWORD=$3
DB_NAME="ecomon"

# Configurable partition settings
PARTITION_COUNT=${PARTITION_COUNT:-200}
RECORDS_PER_PARTITION=${RECORDS_PER_PARTITION:-25000}

echo "Creating partitioned table and view"
echo "Using database: $DB_NAME in container: $CONTAINER_NAME"
echo "Partition count: $PARTITION_COUNT"
echo "Records per partition: $RECORDS_PER_PARTITION"

# Create SQL script
SQL_SCRIPT=$(cat <<EOF
-- 1. Create new schema for partitions
CREATE SCHEMA IF NOT EXISTS "mir_partitions";

-- 2. Create partitioned table in public schema
CREATE TABLE public."model_inference_results_pt_record" (
    id bigint NOT NULL DEFAULT nextval('model_inference_results_id_seq'::regclass),
    record_id bigint NOT NULL,
    model_id integer NOT NULL,
    label_id integer NOT NULL,
    start_time numeric(9,4) NOT NULL,
    end_time numeric(9,4) NOT NULL,
    confidence real NOT NULL,
    PRIMARY KEY (record_id, id)
) PARTITION BY RANGE (record_id);

-- 3. Create partitions in the new schema using a loop
DO \$\$
DECLARE
    partition_num integer;
    partition_count integer := ${PARTITION_COUNT};
    range_size integer := ${RECORDS_PER_PARTITION};
    range_start bigint;
    range_end bigint;
    partition_name text;
    digit_width integer := GREATEST(3, length(partition_count::text));
BEGIN
    IF partition_count < 1 THEN
        RAISE EXCEPTION 'partition_count must be at least 1';
    END IF;
    -- Create first partition with MINVALUE or MAXVALUE when there is only one partition
    partition_name := 'model_inference_results_p' || lpad('1', digit_width, '0');
    IF partition_count = 1 THEN
        EXECUTE format(
            'CREATE TABLE "mir_partitions".%I
             PARTITION OF public."model_inference_results_pt_record"
             FOR VALUES FROM (MINVALUE) TO (MAXVALUE)',
            partition_name
        );
    ELSE
        EXECUTE format(
            'CREATE TABLE "mir_partitions".%I
             PARTITION OF public."model_inference_results_pt_record"
             FOR VALUES FROM (MINVALUE) TO (%s)',
            partition_name,
            range_size
        );

        -- Create intermediate partitions
        FOR partition_num IN 2..(partition_count - 1) LOOP
            range_start := (partition_num - 1) * range_size;
            range_end := partition_num * range_size;
            partition_name := 'model_inference_results_p' || lpad(partition_num::text, digit_width, '0');

            EXECUTE format(
                'CREATE TABLE "mir_partitions".%I
                 PARTITION OF public."model_inference_results_pt_record"
                 FOR VALUES FROM (%s) TO (%s)',
                partition_name,
                range_start,
                range_end
            );
        END LOOP;

        -- Create last partition with MAXVALUE
        range_start := (partition_count - 1) * range_size;
        partition_name := 'model_inference_results_p' || lpad(partition_count::text, digit_width, '0');
        EXECUTE format(
            'CREATE TABLE "mir_partitions".%I
             PARTITION OF public."model_inference_results_pt_record"
             FOR VALUES FROM (%s) TO (MAXVALUE)',
            partition_name,
            range_start
        );
    END IF;
END \$\$;

-- 4. Create view that selects from this partitioned table
CREATE OR REPLACE VIEW public."model_inference_results_view" AS
SELECT
    id,
    model_id,
    record_id,
    label_id,
    start_time,
    end_time,
    confidence
FROM public."model_inference_results_pt_record";

-- 5. Add indexes on the partitioned table (will be created on all partitions automatically)
CREATE INDEX IF NOT EXISTS "idx_mir_pt_record_model_id"
    ON public."model_inference_results_pt_record" (model_id);
CREATE INDEX IF NOT EXISTS "idx_mir_pt_record_label_id"
    ON public."model_inference_results_pt_record" (label_id);
CREATE INDEX IF NOT EXISTS "idx_mir_pt_record_confidence"
    ON public."model_inference_results_pt_record" (confidence);
CREATE INDEX IF NOT EXISTS "idx_mir_pt_record_times"
    ON public."model_inference_results_pt_record" (start_time, end_time);

-- 6. Create model_inference_results_max_confidence table and indexes
CREATE TABLE IF NOT EXISTS public."model_inference_results_max_confidence" (
    id bigint NOT NULL,
    record_id bigint NOT NULL,
    model_id integer NOT NULL,
    label_id integer NOT NULL,
    start_time numeric(9,4) NOT NULL,
    end_time numeric(9,4) NOT NULL,
    confidence real NOT NULL,
    CONSTRAINT model_inference_results_max_confidence_pkey
      PRIMARY KEY (record_id, label_id, model_id)
);

CREATE INDEX IF NOT EXISTS "idx_mir_max_conf_compound"
  ON public."model_inference_results_max_confidence" (model_id, label_id, confidence DESC, record_id);
CREATE INDEX IF NOT EXISTS "idx_mir_max_conf_label"
  ON public."model_inference_results_max_confidence" (label_id, confidence DESC);
CREATE INDEX IF NOT EXISTS "idx_mir_max_conf_model"
  ON public."model_inference_results_max_confidence" (model_id);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public."model_inference_results_pt_record" TO $DB_USER;
GRANT SELECT ON public."model_inference_results_view" TO $DB_USER;
GRANT SELECT, INSERT, UPDATE, DELETE ON public."model_inference_results_max_confidence" TO $DB_USER;
GRANT USAGE ON SCHEMA "mir_partitions" TO $DB_USER;
EOF
)

# Execute SQL in Docker container
echo "Executing SQL script..."
docker exec -i "$CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" <<< "$SQL_SCRIPT"

if [ $? -eq 0 ]; then
    echo "✓ Successfully created partitioned table and view"
    echo "  - Table: public.model_inference_results_pt_record"
    echo "  - View: public.model_inference_results_view"
    echo "  - Schema: mir_partitions (with ${PARTITION_COUNT} partitions)"
else
    echo "✗ Failed to create partitioned table and view"
    exit 1
fi
