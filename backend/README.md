# BioSoundsLab Monitoring Data Analysis Backend

All User requests go through the hasura graphql api and then call by hasura webhooks
All longer running tasks are executed by the celery worker and storing results in the database

## Project structure

- `src/backend/api` - FastAPI application
- `src/backend/worker` - Celery worker all tasks are defined here
- `src/backend/shared` - Shared code between api and worker
- `src/backend/scripts` - Scripts for generating models and dummy data, insert labeles from csv

## Key Technologies

- **FastAPI**: Modern, high-performance web framework for building APIs
- **SQLAlchemy**: SQL toolkit and ORM
- **Celery**: Distributed task queue for handling background jobs
- **Redis**: Message broker for Celery and caching
- **Pydantic**: Data validation and settings management
- **Pandas**: Data manipulation and analysis
- **SoundFile/Pydub**: Audio file processing libraries

## Development

### Scripts

- generate-models - generate pydantic models from database `poetry run generate-models`
- generate-dummy-data - generate dummy data for testing `poetry run generate-dummy-data`
- download-labels - download labels from CSV `poetry run download-labels`
- update-labels - update labels from CSV `poetry run update-labels`
- create-model-seeds - create model seeds `poetry run create-model-seeds`
- create-seeds - create seeds `poetry run create-seeds`
