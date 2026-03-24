# Get your node ID
docker exec garage /garage node id

# Assign the node to a zone with some capacity
docker exec garage /garage layout assign -z dc1 -c 10G <NODE_ID>

# Preview and apply the layout
docker exec garage /garage layout show
docker exec garage /garage layout apply --version 1

# Create an access key
docker exec garage /garage key create garage-key

# Create a bucket
docker exec garage /garage bucket create lakehouse

# Grant the key access to the bucket
docker exec garage /garage bucket allow --read --write --owner lakehouse --key garage-key
