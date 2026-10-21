# Enter new data

This howto documents entering new data after a fresh installation. To install BioSoundsLab, follow the instructions in INSTALL_PROD.md.

Open the new BioSoundsLab installation in a browser. Go to the "Locations" page. Create a new location by clicking on the "+" button (next to the search field).

Once the new location is created, go to the "Sites" page. Create a new site by clicking on the "+" button (next to the search field). In the location pulldown, select the newly created location.

Go to the page "Models" and add a model definition TO DO: explain this in more detail.

# Updating model definitions
After adding tables or changing table definitions in the local database, open the Hasura UI, the export the metadata:
```
cd hasura
~/bin/hasura/hasura metadata export
```

then commit the changes to Git.

Once the updated metadata has been Git-pulled on the server, run this command to import the new metadata definitions into Hasura
`docker compose -f docker-compose.production.yaml run --rm db-migrate`
