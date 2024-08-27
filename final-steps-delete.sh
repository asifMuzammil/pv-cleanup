#!/bin/bash

# Variables
PASS="Abcd1234"
output_file="filtered_pvs.txt"
USER="ubuntu"

# Clear the output file if it already exists
#> $output_file

# Fetch and filter PVs based on the specified criteria
echo "Fetching and filtering PVs..."
filtered_pvs=$(sudo kubectl get pv -o json | jq -r '
   .items[] |
    select(.status.phase == "Released") |
    select(.spec.persistentVolumeReclaimPolicy == "Retain") | select(.spec.claimRef.namespace == "sm-kubegres") |
   .metadata.name + " " + (.spec.storageClassName // "N/A") + " " +
   (.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values | if length > 0 then .[] else "NoNodeAffinity" end) + " " +
   (.spec.local.path // "NoPath")
')

# Check if there are any filtered PVs
if [ -z "$filtered_pvs" ]; then
    echo "No PVs match the specified criteria."
    exit 0
fi

# Debugging: Print the filtered PVs
echo "Filtered PVs:"
echo "$filtered_pvs"

readarray -t filtered_pvs_array <<< "$filtered_pvs"

# Iterate over the filtered PVs and perform the necessary actions
for line in "${filtered_pvs_array[@]}"; do
    read -a arr <<< "$line"
    pv_name=${arr[0]}
    storage_class=${arr[1]}
    node=${arr[2]}
    path=${arr[3]}

    # Debugging: Print extracted values
    echo -e "Processing PV:\n"
    echo "PV Name: $pv_name"
    echo "Storage Class: $storage_class"
    echo "Node: $node"
    echo "Path: $path"

    # SSH to the node and verify the path
    if [ -n "$node" ] && [ "$node" != "NoNodeAffinity" ] && [ "$path" != "NoPath" ]; then
        echo "Accessing node: $node to verify path: $path and print current working directory"

        ssh_output=$(sshpass -p "${PASS}" ssh -o StrictHostKeyChecking=no ${USER}@${node} "
            if [ -d '$path' ]; then
                echo -e 'Path $path exists on node $node. Path Found Job Done: $path \n'
                #sudo rm -r  "$path"
                exit 0
            else
                echo 'Path $path does NOT exist on node $node.'
                exit 1
            fi
        ")

        # Output SSH response for debugging
        echo "$ssh_output"

        if [ $? -eq 0 ]; then
            echo -e "Path confirmed. Moving to the next PV \n."
            #sudo kubectl delete pv "$pv_name" #uncommit this line if want to delete pv
        else
            echo "Path not found. Moving to the next PV."
            #sudo kubectl delete pv "$pv_name" #uncommit this line if want to delete pv
        fi
    else
        echo "Node or Path is not defined for PV: $pv_name"
    fi

    # Continue to the next PV after checking the current one
done

echo "All PVs processed."
