#!/bin/bash

# Script Name: registry-images-clean.sh
# Author: ghostwritten
# Date: 2024-9-18
# Description: This script is designed to facilitate the batch deletion of images from a Docker registry. Prior to executing the script, you must create a file named images.txt, which should contain the names of the images scheduled for deletion. For example, an entry in the file might look like: registry.demo.com/library/nginx:latest. 

name=`basename $0 .sh`

action=$1


images_list() {


image_repos=`cat registry-images-clean.txt  | awk -F '/' '{print $1}' |  uniq`

for image_repo in $image_repos
do 
 repositories=$(curl -q -s http://${image_repo}/v2/_catalog | jq -r '.repositories[]')

 if [[ -n $repositories ]] ; then
  echo "$image_repo 镜像仓库列表:"

  for repo in $repositories; do

    tags=$(curl -q -s http://${image_repo}/v2/${repo}/tags/list | jq -r '.tags[]')

    if [ -z "$tags" ]; then
        echo "  No tags found"
    else
        for tag in $tags; do
            echo "  $repo:$tag"
        done
    fi
  done
 else
   echo "$image_repo 镜像仓库是空库."
 fi
done

}

images_rm() {

while IFS= read -r line
do
    image_repo=$(echo "$line" | awk -F '/' '{print $1}')
    
    image_project=$(echo "$line" | awk -F '/' '{ if (NF > 2) print $(NF-1) "/"; else print "" }')


    image_name=$(echo "$line" | awk -F '/' '{print $NF}' | awk -F ':' '{print $1}')
    
    image_tag=$(echo "$line" | awk -F '/' '{print $NF}' | awk -F ':' '{print $2}')


    response=$(curl -s "http://${image_repo}/v2/${image_project}${image_name}/tags/list")
    if echo "$response" | jq -e ".tags | index(\"${image_tag}\")" > /dev/null; then
       echo "镜像 ${image_project}${image_name}:${image_tag} 存在，准备删除..."

       source_data=`docker inspect registry | jq -r '.[0].Mounts[] | select(.Type == "bind") | .Source'`
       MANIFEST_DIGEST=`ls ${source_data}/docker/registry/v2/repositories/${image_project}${image_name}/_manifests/tags/${image_tag}/index/sha256/`

       curl -s -I -X DELETE  "http://${image_repo}/v2/${image_project}${image_name}/manifests/sha256:${MANIFEST_DIGEST}" 2>&1 > /dev/null

    
      response=$(curl -s "http://${image_repo}/v2/${image_project}${image_name}/tags/list")
      if ! echo "$response" | jq -e '.tags | length > 0' > /dev/null; then
         rm -rf ${source_data}/docker/registry/v2/repositories/${image_project}${image_name}
      fi
    else
       echo "镜像 ${image_repo}/${image_project}${image_name}:${image_tag} 不存在。"
fi


done < registry-images-clean.txt


docker exec registry  bin/registry garbage-collect /etc/docker/registry/config.yml  >> /dev/null
docker restart registry


}

case $action in
 l|ls)
        images_list
        ;;
 d|rm)
        images_rm
        ;;
 *)
        echo "Usage: $name [ls|rm]"
        exit 1
        ;;
esac
exit 0
