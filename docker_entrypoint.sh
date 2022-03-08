#!/bin/bash
echo "Entry point to CKG Docker"
cd /CKG

echo "Loading database"
# TODO mount the database directory as a volume and skip loading if it is already there
mkdir -p /var/lib/neo4j/data/backup
wget -O /var/lib/neo4j/data/backup/ckg_latest_4.2.3.dump https://datashare.biochem.mpg.de/s/kCW7uKZYTfN8mwg/download
mkdir -p /var/lib/neo4j/data/databases/graph.db
sudo -u neo4j neo4j-admin load --from=/var/lib/neo4j/data/backup/ckg_latest_4.2.3.dump --database=graph.db --force
rm -rf /var/lib/neo4j/data/backup

echo "Starting Neo4j"
service neo4j start &
service neo4j status

while ! [[ `wget -S --spider http://localhost:7474  2>&1 | grep 'HTTP/1.1 200 OK'` ]]; do
echo "Database not ready"
sleep 45
done

echo "Database ready"
echo "Creating Test user in the database"
python3 ckg/graphdb_builder/builder/create_user.py -u test_user -d test_user -n test -e test@ckg.com -a test -p 12345678

echo "Running jupyterHub"
jupyterhub -f /etc/jupyterhub/jupyterhub.py --no-ssl &

echo "Running redis-server"
service redis-server start

echo "Running celery queues"
cd ckg/report_manager
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=1 -E -Q creation --uid 1500 --gid nginx &
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=3 -E -Q compute --uid 1500 --gid nginx &
celery -A ckg.report_manager.worker worker --loglevel=INFO --concurrency=1 -E -Q update --uid 1500 --gid nginx &

echo "Initiating CKG app"
cd /CKG
nginx && uwsgi --ini /etc/uwsgi/apps-enabled/uwsgi.ini --uid 1500 --gid nginx
