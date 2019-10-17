#!/bin/env bash
DIR=~/.turbodl
if [ -d "$DIR" ]; then
    cd "$DIR"; rm complete/* errors/* today.txt titles.txt 2> /dev/null
else
    mkdir -p "$DIR"/complete "$DIR"/errors; cd "$DIR"
fi

if [ "$USER" != persie ]; then
COUNT=1; COUNT1=0
WP=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?page=$COUNT&per_page=100" || exit)
while [ $COUNT1 -lt 100 ]; do
    title=$(jq -r ".[$COUNT1].title.rendered" <<< "$WP" | sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#822[0-1];/\"/g; s/&amp;/\&/g")
    grep -q "$title" movie_list.txt || echo "$title" >> movie_list.txt
    COUNT1=$((COUNT1+1))
done
fi

if [ "$USER" != persie ]; then
    cat ~/turbodl/whitelist > ~/.turbodl/whitelist
    cat ~/turbodl/blacklist > ~/.turbodl/blacklist
fi

URL=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "https://lightdlmovies.blogspot.com/search/label/MOVIES" || exit)
output=$(grep ^'<a href=.*html.*title=.*</a>' <<< "$URL" | sed -e "s/'>.*//; s/.*title='//; s/<\/a>//")
output2=$(grep ^'<a href=.*html.*title=.*</a>' <<< "$URL" | sed "s/'>.*//")

if [ "$USER" != persie ]; then
    exec 3>&1 4>&2
    trap 'exec 2>&4 1>&3' 0 1 2 3
    exec 1>logs.txt 2>&1
fi
set -ex

while IFS= read -r "OUTPUT"; do
    echo -e "\\n$OUTPUT\\n-----------------------"
#if [ "$OUTPUT" != "What Happened to Monday 2017" ]; then continue; fi
    if grep "$OUTPUT" blacklist; then echo "$OUTPUT blacklisted"; continue; fi
    LINKS="$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s $(grep "$OUTPUT" <<< "$output2" | grep -o http.*html) | grep -o "<span style=\"font-family.*http.*mkv</a>" | sed "s/.*<a/<a/; s/a>.*/a>/; s/CLICK HERE FOR SUBTITLES /Subtitles/" || exit)"
    grep -qiE "(hd.*cm|HDCAM|HDTS).*mkv" <<< "$LINKS" && continue

    NAME=$(sed -e 's/  $//; s/ $//;s/\./ /g; s/[ -.][0-9][0-9][0-9][0-9].*//; s/ ([0-9][0-9][0-9][0-9]).*//' <<< "$OUTPUT")
    YEAR=$(grep -woE '([0-9][0-9][0-9][0-9]$|[0-9][0-9][0-9][0-9])' <<< "$OUTPUT" || echo 'null')
    grep -q 'null' <<< "$YEAR" && echo "$OUTPUT   --> year not found" >> 'today.txt' && continue

    TMDB_API=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "https://api.themoviedb.org/3/search/movie?api_key=0dec8436bb1b7de2bbcb1920ac31111f&query=$(sed "s/ /%20/g" <<< "$NAME")&page=1&year=$YEAR" || exit)
    if [ $(jq '.total_results' <<< "$TMDB_API") == 0 ]; then echo "$OUTPUT   -->   not found" >> today.txt; continue; fi
    A=0
    while [ "$A" -lt $(jq '.total_results' <<< "$TMDB_API") ]; do
        if grep -q "$YEAR" <<< $(jq -r ".results[$A].release_date" <<< "$TMDB_API"); then
            POSTER="https://image.tmdb.org/t/p/w500$(jq -r ".results[$A] | .poster_path" <<< "$TMDB_API")"
            TMDB_ID=$(jq -r ".results[$A] | .id" <<< ""$TMDB_API"")
            OVERVIEW=$(jq -r ".results[$A] | .overview" <<< "$TMDB_API")
            break
        else
            if [ $(jq '.total_results' <<< "$TMDB_API") == 1 ]; then
                POSTER="https://image.tmdb.org/t/p/w500$(jq -r ".results[$A] | .poster_path" <<< "$TMDB_API")"
                TMDB_ID=$(jq -r ".results[$A] | .id" <<< "$TMDB_API")
                OVERVIEW=$(jq -r ".results[$A] | .overview" <<< "$TMDB_API")
                break
            elif [ "$A" == $(jq '.total_results' <<< "$TMDB_API") ]; then
                echo "$OUTPUT   -->   not found" >> today.txt
                continue 2
            fi
            A=$((A+1))
        fi
    done
    A=0

    IMDB_ID=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s --header "Content-Type: application/json" --header "trakt-api-version: 2" --header "trakt-api-key: 64ba02e985f18ec3a00186209b3605cfbbeedf9890898e3a06b8e020111e8194" "https://api.trakt.tv/search/tmdb/$TMDB_ID?type=movie" | jq -r '.[0].movie.ids.imdb' || exit)
    ! grep -q 'tt' <<< "$IMDB_ID" && echo "$OUTPUT   --> IMDB error getting data" >> today.txt && continue

    OMDB_API=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?i=$IMDB_ID&plot=short&apikey=7759dbc7" || exit)
    grep "Error getting data" <<< "$OMDB_API" && echo "$OUTPUT   --> OMDB error getting data" >> today.txt && continue
    TITLE="$(jq -r ".Title" <<< "$OMDB_API") ($YEAR)"
    PLOT=$(jq -r '.Plot' <<< "$OMDB_API"); grep -q 'N/A' <<< "$PLOT" && PLOT="$OVERVIEW";CAST=$(jq -r '.Actors' <<< "$OMDB_API")
    GENRE=$(jq -r '.Genre' <<< "$OMDB_API"); if grep -qi 'documentary' <<< "$GENRE"; then continue; fi
    RATING=$(jq -r '.imdbRating' <<< "$OMDB_API")
    if [ "$RATING" == 'N/A' -o "$GENRE" == 'N/A' ]; then
        if ! grep -q "$OUTPUT" whitelist; then
            echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $YEAR" > errors/"$OUTPUT"
            curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "$POSTER" -o errors/"$TITLE".jpg
            if [ $(identify -format "%w" errors/"$TITLE".jpg)> /dev/null -gt 530 -o $(identify -format "%w" errors/"$TITLE".jpg)> /dev/null -lt 470 -o $(identify -format "%h" errors/"$TITLE".jpg)> /dev/null -gt 780 -o $(identify -format "%h" errors/"$TITLE".jpg)> /dev/null -lt 720 ]; then
            rm errors/"$TITLE".jpg; echo "$OUTPUT   -->   invalid image height/weight dimension & rating/genre" >> 'today.txt'
            continue
            fi
            echo "$OUTPUT   -->   rating/genre not available" >> 'today.txt'
            continue
        else
            #grep -q 'N/A' <<< "$RATING" && RATING=$(grep "$OUTPUT" whitelist | grep -oE '([0-9]\.[0-9]|[0-9][0-9]\.[0-9]|N/A)')
            grep -q 'N/A' <<< "$GENRE" && GENRE=$(grep "$OUTPUT" whitelist | sed 's/.*#//')
        fi
    else
        if grep -qiE '(horror|thriller)' <<< "$GENRE"; then
            if [ $(sed 's/\.//' <<< "$RATING") -lt 52 ] && ! grep -q "$OUTPUT" whitelist; then continue; fi
        else
            if [ $(sed 's/\.//' <<< "$RATING") -lt 55 ] && ! grep -q "$OUTPUT" whitelist; then continue; fi
        fi
    fi

    if grep -owiF "$TITLE" movie_list.txt; then
        WP_RESULTS=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?search=$(sed 's/[(-)]//g; s/ /%20/g' <<< "$TITLE")&per_page=5")

        while [[ "$A" != 6 ]]; do
            if grep -i "$(sed 's/ (.*)//' <<< "$TITLE")" <<< "$(jq -r ".[$A].title.rendered" <<< "$WP_RESULTS" | sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#822[0-1];/\"/g; s/&amp;/\&/g")"; then
                WP_LINKS=$(jq -r ".[$A].content.rendered" <<< "$WP_RESULTS" | grep -o '<a href.*</a>' || true)
                if grep -q 'http' <<< "$WP_LINKS"; then
                    LINKS2=$(sed "/CLICK HERE FOR SUBTITLES/d" <<< "$LINKS")
                    if [ "$(md5sum <<< "$WP_LINKS")" == "$(md5sum <<< "$LINKS2")" ]; then
                        continue 2
                    else
                        if [ "$USER" != persie ]; then
                            curl -s -X DELETE --user "looneytkp:Sgm4kv101413$" "https://turbodl.xyz/wp-json/wp/v2/posts/$(jq ".[$A].id" <<< "$WP_RESULTS")" 2> /dev/null
                            curl -s -X DELETE --user "looneytkp:Sgm4kv101413$" "https://turbodl.xyz/wp-json/wp/v2/media/$(jq ".[$A].featured_media" <<< "$WP_RESULTS")?force=true" 2> /dev/null
                        fi
                        echo "deleted $OUTPUT"
                    fi
                else
                    sed -i "/$TITLE/d" movie_list.txt
                fi
                break
            else
                A=$((A+1))
                if [ $A == 6 ]; then echo "$OUTPUT   -->   conflicting error" >> today.txt && continue 2; fi
            fi
        done
    fi

    curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "$POSTER" -o complete/"$TITLE".jpg || exit
    if [ $(identify -format "%w" complete/"$TITLE".jpg)> /dev/null -gt 530 -o $(identify -format "%w" complete/"$TITLE".jpg)> /dev/null -lt 470 -o $(identify -format "%h" complete/"$TITLE".jpg)> /dev/null -gt 780 -o $(identify -format "%h" complete/"$TITLE".jpg)> /dev/null -lt 700 ]; then
        echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\nDownload Links:\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $YEAR" > errors/"$OUTPUT"
        echo "$OUTPUT   -->   invalid image height/weight dimension" >> 'today.txt'
        continue
    fi

    if grep -qowiF "$TITLE" movie_list.txt; then echo "$TITLE  -->   updated" >> today.txt; else echo "$TITLE" >> today.txt && sed -i "1s/^/$TITLE\\n/" movie_list.txt; fi
    echo "$TITLE #$OUTPUT" >> titles.txt
    echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\nDownload Links:\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $YEAR" > complete/"$OUTPUT"
done <<< "$output"

if [ ! -e today.txt ]; then
    if [ "$USER" != persie ]; then
        echo | mutt -s 'turbodlbot | movies logs' -i logs.txt movie_list.txt -- persie@turbodl.xyz
    fi
    exit
fi
sed -i "1s/^/$(date)\\n--------------------------------\\n/" today.txt

if [ "$USER" != persie ]; then
    if [ -e titles.txt ]; then
        echo -e "\\n---sorting randomly---"
        SORTED_POSTS=$(sort -Rr < titles.txt)
        while IFS= read -r SORTED; do
            echo | mutt -s "$(sed 's/ #.*//' <<< "$SORTED")" -i complete/"$(grep -o '#.*' <<< "$SORTED" | sed 's/#//')" -a complete/"$(sed 's/ #.*//' <<< "$SORTED")".jpg -- Ud37asAUd8a7@turbodl.xyz
        done <<< "$SORTED_POSTS"
    fi

    if [ -z "$(ls -A errors)" ]; then
        echo | mutt -s 'turbodlbot | movies' -i today.txt -- persie@turbodl.xyz info@turbodl.xyz
    else
        echo | mutt -s 'turbodlbot | movies' -i today.txt -a errors/* -- persie@turbodl.xyz info@turbodl.xyz
    fi
    echo | mutt -s 'turbodlbot | movies logs' -i logs.txt movie_list.txt -- persie@turbodl.xyz
fi
