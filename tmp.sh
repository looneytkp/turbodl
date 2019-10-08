#!/bin/env bash
set -ex
COUNT=1; COUNT1=0
echo '---script starts above this---' > ~/.turbodl/list.txt
while true; do
    POSTS=$(curl -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?page=$COUNT&per_page=100")
    if grep -q 'rest_post_invalid_page_number' <<< "$POSTS"; then break; fi
    while [ $COUNT1 -lt 100 ]; do
		title=$(jq -r ".[$COUNT1].title.rendered" <<< "$POSTS" | sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#822[0-1];/\"/g; s/&amp;/\&/g")
        if [ "$title" == null ]; then break; fi
        echo "$title" >> ~/.turbodl/list.txt
        COUNT1=$((COUNT1+1))
    done
    COUNT1=0; COUNT=$((COUNT+1))
done
