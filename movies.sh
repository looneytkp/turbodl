#!/bin/env bash
DIR=~/.turbodl
if [ -d "$DIR" ]; then
    cd "$DIR"; rm movies/* errors/* today.txt output* info file.x data titles.txt 2> /dev/null
else
    mkdir -p "$DIR"/movies "$DIR"/errors; cd "$DIR"
fi

COUNT=1; COUNT1=0
WP=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?page=$COUNT&per_page=100")
while [ $COUNT1 -lt 100 ]; do
    title=$(jq -r ".[$COUNT1].title.rendered" <<< "$WP"| sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#822[0-1];/\"/g; s/&amp;/\&/g")
    COUNT1=$((COUNT1+1))
done

URL=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "https://lightdlmovies.blogspot.com/search/label/MOVIES")
output=$(grep ^'<a href=.*html.*title=.*</a>' <<< "$URL" | sed -e "s/'>.*//; s/.*title='//; s/<\/a>//")
output2=$(grep ^'<a href=.*html.*title=.*</a>' <<< "$URL" | sed "s/'>.*//")
echo -e ""$(date)"\\n--------------------------------" > 'today.txt'

if [ "$USER" != persie ]; then
    exec 3>&1 4>&2
    trap 'exec 2>&4 1>&3' 0 1 2 3
    exec 1>logs.txt 2>&1
fi
set -ex

while IFS= read -r OUTPUT; do
    echo -e "\\n$OUTPUT\\n-----------------------"
    LINKS=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s $(grep "$OUTPUT" <<< "$output2" | grep -o http.*html) | grep ^"<span style=\"font-family.*http.*a>" | sed "s/.*<a/<a/; s/a>.*/a>/; s/CLICK HERE FOR SUBTITLES /Subtitles/")
    grep -qiE "(hd.*cm|HDCAM).*mkv" <<< "$LINKS" && continue

    NAME=$(sed -e 's/  $//; s/ $//;s/\./ /g; s/[ -.][0-9][0-9][0-9][0-9].*//' <<< "$OUTPUT")
    YEAR=$(grep -woE '([0-9][0-9][0-9][0-9]$|[0-9][0-9][0-9][0-9])' <<< "$OUTPUT" || echo 'null')
    grep -q 'null' <<< "$YEAR" && echo "$OUTPUT   --> year not found" >> 'today.txt' && continue

    TMDB_API=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "https://api.themoviedb.org/3/search/movie?api_key=0dec8436bb1b7de2bbcb1920ac31111f&query=$(sed "s/ /%20/g" <<< "$NAME")&page=1&year=$YEAR")
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

    IMDB_ID=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s --header "Content-Type: application/json" --header "trakt-api-version: 2" --header "trakt-api-key: 64ba02e985f18ec3a00186209b3605cfbbeedf9890898e3a06b8e020111e8194" "https://api.trakt.tv/search/tmdb/$TMDB_ID?type=movie" | jq -r '.[].movie.ids.imdb')
    ! grep 'tt' <<< "$IMDB_ID" && TODAY+=("$OUTPUT   --> year not found") && continue

    OMDB_API=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?i=$IMDB_ID&plot=short&apikey=7759dbc7")
    TITLE="$(jq -r ".Title" <<< "$OMDB_API") ($YEAR)"
    PLOT=$(jq -r '.Plot' <<< "$OMDB_API"); grep -q 'N/A' <<< "$PLOT" && PLOT="$OVERVIEW";CAST=$(jq -r '.Actors' <<< "$OMDB_API")
    GENRE=$(jq -r '.Genre' <<< "$OMDB_API"); if grep -qi 'documentary' <<< "$GENRE"; then continue; fi
    RATING=$(jq -r '.imdbRating' <<< "$OMDB_API")
    if [ "$RATING" == 'N/A' -o "$GENRE" == 'N/A' ]; then
        echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $YEAR" > errors/"$OUTPUT"
        curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "$POSTER" -o errors/"$TITLE".jpg
        if [ $(identify -format "%w" errors/"$TITLE".jpg)> /dev/null -gt 530 -o $(identify -format "%w" errors/"$TITLE".jpg)> /dev/null -lt 470 -o $(identify -format "%h" errors/"$TITLE".jpg)> /dev/null -gt 780 -o $(identify -format "%h" errors/"$TITLE".jpg)> /dev/null -lt 720 ]; then
            rm errors/"$TITLE".jpg; echo "$OUTPUT   -->   invalid image height/weight dimension & rating/genre" >> 'today.txt'
            continue
        fi
        echo "$OUTPUT   -->   rating/genre not available" >> 'today.txt'
        continue
    elif [ $(sed 's/\.//' <<< "$RATING") -lt 55 ]; then
        continue
    fi

    if grep -owF "$TITLE" list.txt; then
        WP_RESULTS=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://turbodl.xyz/wp-json/wp/v2/posts?search=$(sed 's/[(-)]//g; s/ /%20/g' <<< "$TITLE")&per_page=5")

        while [[ "$A" != 6 ]]; do
            if grep "$(sed 's/ (.*)//' <<< "$TITLE")" <<< "$(jq -r ".[$A].title.rendered" <<< "$WP_RESULTS")"; then
                WP_LINKS=$(jq -r ".[$A].content.rendered" <<< "$WP_RESULTS" | grep -o '<a href.*</a>' || true)
                if grep -q 'http' <<< "$WP_LINKS"; then
                    LINKS2=$(sed "/CLICK HERE FOR SUBTITLES/d" <<< "$LINKS")
                    if [ "$(md5sum <<< "$WP_LINKS")" == "$(md5sum <<< "$LINKS2")" ]; then
                        continue 2
                    else
                        if [ "$USER" != persie ]; then
                            curl -s -X DELETE --user "looneytkp:Sgm4kv101413$" "https://turbodl.xyz/wp-json/wp/v2/posts/$(jq '.[].id' <<< "$WP_RESULTS")"
                            curl -s -X DELETE --user "looneytkp:Sgm4kv101413$" "https://turbodl.xyz/wp-json/wp/v2/media/$((POST_ID+1))?force=true"
                        fi
                        echo "deleted $OUTPUT2"
                    fi
                else
                    sed -i "/$TITLE/d" list.txt
                fi
                break
            else
                A=$((A+1))
                if [ $A == 6 ]; then echo "$OUTPUT   -->   conflicting error" >> today.txt && continue 2; fi
            fi
        done

    fi

    curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "$POSTER" -o movies/"$TITLE".jpg
    if [ $(identify -format "%w" movies/"$TITLE".jpg)> /dev/null -gt 530 -o $(identify -format "%w" movies/"$TITLE".jpg)> /dev/null -lt 470 -o $(identify -format "%h" movies/"$TITLE".jpg)> /dev/null -gt 780 -o $(identify -format "%h" movies/"$TITLE".jpg)> /dev/null -lt 700 ]; then
        echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $B" > errors/"$OUTPUT"
        echo "$OUTPUT   -->   invalid image height/weight dimension" >> 'today.txt'
        continue
    fi

    if grep -qowF "$TITLE" list.txt; then echo "$TITLE  -->   updated" >> 'today.txt'; else echo "$TITLE" >> 'today.txt' && sed -i "1s/^/$TITLE\\n/" list.txt; fi
    echo "$TITLE #$OUTPUT" >> titles.txt
    echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $YEAR" > movies/"$OUTPUT"
done <<< "$output"

if [ "$USER" != persie ]; then
    if [ -e titles.txt ]; then
        echo -e "\\n---sorting randomly---"
        SORTED_POSTS=$(sort -Rr < titles.txt)
        while IFS= read -r SORTED; do
            echo | mutt -s "$(sed 's/ #.*//' <<< "$SORTED")" -i movies/"$(grep -o '#.*' <<< "$SORTED" | sed 's/#//')" -a movies/"$(grep -o '#.*' <<< "$SORTED" | sed 's/#//')".jpg -- Ud37asAUd8a7@turbodl.xyz
        done <<< "$SORTED_POSTS"
    fi

    if [ -z "$(ls -A errors)" ]; then
        echo | mutt -s 'turbodlbot | movies' -i today.txt -- persie@turbodl.xyz info@turbodl.xyz
    else
        echo | mutt -s 'turbodlbot | movies' -i today.txt -a errors/* -- persie@turbodl.xyz info@turbodl.xyz
    fi
    echo | mutt -s 'turbodlbot | movies logs' -i logs.txt list.txt -- persie@turbodl.xyz
fi
