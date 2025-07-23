# octosql-etcd

etcd is the central data store for any OpenShift/K8s cluster. While most OpenShift clusters will never have their etcd clusters touched or read by a human, some situations (e.g., clusters in distress due to huge numbers of events or CRDs, etc.) may require users to take a snapshot of a cluster's etcd and analyze it. This repo builds a container image with the tools (i.e., [OctoSQL](https://github.com/cube2222/octosql) and its [etcdsnapshot plugin](https://github.com/tjungblu/octosql-plugin-etcdsnapshot)) for such an analysis.

[quay.io/abyrne_openshift/octosql-etcd:latest](https://quay.io/repository/abyrne_openshift/octosql-etcd) will always contain the latest state of this repo's `main` branch.

## Quick Start
If you already have an etcd snapshot on hand, run the following commands to quickly use this tool. Skip to the next sections for detailed snapshotting and usage instructions.
```bash
SNAPSHOT_DIR=/path/to/directory/containing/etcd.snapshot

docker run -it --rmi --network none -v $SNAPSHOT_DIR:/snapshot:Z quay.io/abyrne_openshift/octosql-etcd:latest

# Once inside the container...
cd /snapshot
octosql -ojson "SELECT * FROM etcd.snapshot?meta=true"
# Example output: {"size":88145920,"sizeInUse":75288576,"sizeFree":128...
```

## Collecting an etcd snapshot
> [!CAUTION]
> etcd snapshots contain _mountains_ of unencrypted sensitive data, including authentication tokens, secrets, configmaps. Handle snapshot files with extreme caution, avoid copying them outside of control plane nodes, and ensure you delete all snapshot artifacts after analysis.

If you're logged into an OpenShift/k8s control plane node (e.g., via SSH or via debug pod after running `chroot /host`), run the following commands to collect an etcd snapshot.
```bash
ETCDCTL_CONTAINER_ID=$(crictl ps --name=etcdctl -o json | jq -r .containers[0].id)
TMP_DIR=$(mktemp -d)

crictl exec $ETCDCTL_CONTAINER_ID /bin/sh -c "unset ETCDCTL_ENDPOINTS; etcdctl snapshot save etcd.snapshot; gzip -f etcd.snapshot"
crictl exec $ETCDCTL_CONTAINER_ID /bin/cat etcd.snapshot.gz | gunzip > $TMP_DIR/etcd.snapshot
crictl exec $ETCDCTL_CONTAINER_ID /bin/rm etcd.snapshot.gz

echo "Snapshot saved to $TMP_DIR/etcd.snapshot"
```

## Loading the snapshot into OctoSQL
We'll use [OctoSQL](https://github.com/cube2222/octosql) and its [etcdsnapshot plugin](https://github.com/tjungblu/octosql-plugin-etcdsnapshot) to analyze the snapshot. This allows us to explore etcd as if it's a read-only SQL database. You can pull down this repo's container image and run it directly on the control plane node using the following command.
```bash
podman run -it --rmi --network none -v $TMP_DIR:/snapshot:Z quay.io/abyrne_openshift/octosql-etcd:latest
```

Once inside the container, run the following commands to ensure the snapshot is readable.
> [!TIP]
> octosql has trouble with special characters (including dashes) in the path to the snapshot file, and the snapshot file must end in `.snapshot`. If you didn't follow the exact commands above, you may want to rename/move your snapshot file such that it shows up at `/snapshot/etcd.snapshot` once inside the container.
```bash
# Run these inside the container image
cd /snapshot
octosql -ojson "SELECT * FROM etcd.snapshot?meta=true"
# Example output:
# {"size":88145920,"sizeInUse":75288576,"sizeFree":12857344,"fragmentationRatio":0.145864312267658,"fragmentationBytes":12857344,"totalKeys":25467,"totalRevisions":25450,"maxRevision":88921,"minRevision":0,"revisionRange":88921,"avgRevisionsPerKey":1.0883510092370852,"defaultQuota":8589934592,"quotaUsageRatio":0.01026153564453125,"quotaUsagePercent":1.026153564453125,"quotaRemaining":8501788672,"totalValueSize":59279509,"averageValueSize":2327,"largestValueSize":544474,"smallestValueSize":0,"keysWithMultipleRevisions":151,"uniqueKeys":23384,"keysWithLeases":15797,"activeLeases":366,"estimatedCompactionSavings":3312109}
```
If you see output similar to the sample above, then you're all set to begin your analysis! If you instead get an error, then double-check that the snapshot file is properly named and located (see tip above).

## Analyzing the snapshot
As mentioned earlier, we'll use SQL to examine the etcd snapshot. Use the `--describe` flag to see the "columns" of the "database."
```bash
$ octosql "SELECT * FROM etcd.snapshot" --describe
+-------------------+-----------------+------------+
|       name        |      type       | time_field |
+-------------------+-----------------+------------+
| 'apigroup'        | 'NULL | String' | false      |
| 'apiserverPrefix' | 'NULL | String' | false      |
| 'createRevision'  | 'Int'           | false      |
| 'key'             | 'String'        | false      |
| 'lease'           | 'Int'           | false      |
| 'modRevision'     | 'Int'           | false      |
| 'name'            | 'NULL | String' | false      |
| 'namespace'       | 'NULL | String' | false      |
| 'resourceType'    | 'NULL | String' | false      |
| 'value'           | 'String'        | false      |
| 'valueSize'       | 'Int'           | false      |
| 'version'         | 'Int'           | false      |
+-------------------+-----------------+------------+
```
Feel free to dust off your SQL-fu and use the column names above to build your own queries. Alternatively, see the examples given in the [etcdsnapshot plugin docs](https://github.com/tjungblu/octosql-plugin-etcdsnapshot/blob/main/README.md#examples).

🔑 **Note**: `key` is a reserved word in OctoSQL, so direct references to the "key" column will result in a syntax error. If your queries need to work with "key", place an alias right after the snapshot filename (e.g., `SELECT myalias.key FROM etcd.snapshot myalias`). 

## Cleaning up
When you're done with your analysis, `exit` the container, delete the temporary snapshot directory, and purge the OctoSQL image.
```bash
# Double-check assumptions
echo $AM_I_CONTAINER # run exit if this returns "yes"
echo $TMP_DIR # manually locate the snapshot directory if this is unset

# Delete snapshot
rm -rfi $TMP_DIR

# Attempt to delete cached image 
# (expected to fail if you used `--rmi` with `podman run`)
podman image rm quay.io/abyrne_openshift/octosql-etcd:latest
```
