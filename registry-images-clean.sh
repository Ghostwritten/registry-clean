#!/bin/bash

# 脚本名称: registry-images-clean.sh
# 作者: ghostwritten
# 日期: 2024-09-18
# 描述: 此脚本用于批量删除 Docker 注册表中的镜像。
# 必须存在一个名为 images.txt 的文件，其中包含待删除的镜像名称。

name=$(basename "$0" .sh)
registry_url="${REGISTRY_URL:-http://localhost}" # 更改为默认的注册表 URL
images_file="registry-images-clean.txt"

# 检查 images_file 是否存在且不为空
if [[ ! -f $images_file || ! -s $images_file ]]; then
    echo "错误: 文件 '$images_file' 不存在或为空。"
    exit 1
fi

action=$1

# 解析镜像详细信息的函数
parse_image() {
    local line="$1"
    echo "$line" | awk -F '/' '{print $1, $(NF-1) "/", $NF}' OFS=' ' | awk -F ':' '{print $1, $2}'
}

images_list() {
    local image_repos=$(awk -F '/' '{print $1}' "$images_file" | uniq)

    for image_repo in $image_repos; do 
        repositories=$(curl -s "${registry_url}/${image_repo}/v2/_catalog" | jq -r '.repositories[]')
        if [[ -n $repositories ]]; then
            echo "$image_repo 镜像仓库列表:"
            for repo in $repositories; do
                tags=$(curl -s "${registry_url}/${image_repo}/v2/${repo}/tags/list" | jq -r '.tags[]')
                if [ -z "$tags" ]; then
                    echo "  没有找到标签"
                else
                    for tag in $tags; do
                        echo "  $repo:$tag"
                    done
                fi
            done
        else
            echo "$image_repo 是空库。"
        fi
    done
}

images_rm() {
    while IFS= read -r line; do
        read -r image_repo image_project image_name <<< $(parse_image "$line")
        image_tag=$(echo "$line" | awk -F ':' '{print $2}')

        response=$(curl -s "${registry_url}/${image_repo}/v2/${image_project}${image_name}/tags/list")
        if echo "$response" | jq -e ".tags | index(\"${image_tag}\")" > /dev/null; then
            echo "镜像 ${image_project}${image_name}:${image_tag} 存在，准备删除..."

            source_data=$(docker inspect registry | jq -r '.[0].Mounts[] | select(.Type == "bind") | .Source')
            MANIFEST_DIGEST=$(ls "${source_data}/docker/registry/v2/repositories/${image_project}${image_name}/_manifests/tags/${image_tag}/index/sha256/")

            curl -s -I -X DELETE "${registry_url}/${image_project}${image_name}/manifests/sha256:${MANIFEST_DIGEST}" > /dev/null

            response=$(curl -s "${registry_url}/${image_repo}/v2/${image_project}${image_name}/tags/list")
            if ! echo "$response" | jq -e '.tags | length > 0' > /dev/null; then
                rm -rf "${source_data}/docker/registry/v2/repositories/${image_project}${image_name}"
            fi
        else
            echo "镜像 ${image_repo}/${image_project}${image_name}:${image_tag} 不存在。"
        fi
    done < "$images_file"

    docker exec registry bin/registry garbage-collect /etc/docker/registry/config.yml > /dev/null
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
        echo "用法: $name [ls|rm]"
        exit 1
        ;;
esac
exit 0
