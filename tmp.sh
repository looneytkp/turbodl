#!/bin/env bash
set -ex
COUNT=1; COUNT1=0
echo '---script starts above this---' > ~/.tmp/'movie list.txt'
while true; do
    curl -s -o ~/.tmp/file.x -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?page=$COUNT&per_page=100"
    if grep -q 'rest_post_invalid_page_number' ~/.tmp/file.x; then break; fi
    while [ $COUNT1 -lt 100 ]; do
		title=$(cat ~/.tmp/file.x | jq -r ".[$COUNT1].title.rendered" | sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#8220;/\"/g; s/&#8221;/\"/g; s/&amp;/\&/g; s/ [UPDATED]//")
        if [ "$title" == null ]; then break; fi
        echo "$title" >> ~/.tmp/'movie list.txt'
        COUNT1=$((COUNT1+1))
    done
    COUNT1=0; COUNT=$((COUNT+1))
done
