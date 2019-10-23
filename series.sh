#!/bin/env bash
DIR=~/.turbodl
if [ -d "$DIR" ]; then
    cd "$DIR"; rm complete/* errors/* today.txt titles.txt links 2> /dev/null
else
    mkdir -p "$DIR"/complete "$DIR"/errors; cd "$DIR"
fi

if [ "$USER" != persie ]; then
COUNT=1; COUNT1=0
WP=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://series.turbodl.xyz/wp-json/wp/v2/posts?page=$COUNT&per_page=100" || exit)
while [ $COUNT1 -lt 100 ]; do
    title=$(jq -r ".[$COUNT1].title.rendered" <<< "$WP" | sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#822[0-1];/\"/g; s/&amp;/\&/g")
    grep -q "$title" series_list.txt || echo "$title" >> series_list.txt
    COUNT1=$((COUNT1+1))
done
fi

if [ "$USER" != persie ]; then
    cat ~/turbodl/whitelist > ~/.turbodl/whitelist
    cat ~/turbodl/blacklist > ~/.turbodl/blacklist
fi

URL=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "https://www.lightdl.xyz/search/label/TV%20SERIES")
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
    if grep ^"$OUTPUT" blacklist; then echo "$OUTPUT blacklisted"; continue; fi
set +x
    SITE=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s $(grep "$OUTPUT" <<< "$output2" | grep -o http.*html))
#set -x
    LINKS="$(grep -oiE "(<span style=\"font-family.*http.*a>|<a href=.*S[0-9][0-9]E[0-9][0-9].*</a>)" <<< "$SITE" | sed "s/.*<a/<a/; s/a>.*/a>/; s/CLICK HERE FOR SUBTITLES /Subtitles/")"
    grep -qiE "(hd.*cm|HDCAM|HDTS).*mkv" <<< "$LINKS" && continue
set -x
    YEAR=$(sed '0,/class=.*post-body/d; /CLICK ON.* LINK.* BELOW TO DOWNLOAD/,$d' <<< "$SITE" | grep -oE '(Release.*[0-9][0-9][0-9][0-9]|[0-9][0-9][0-9][0-9]<br />)' | grep -o '[0-9][0-9][0-9][0-9]' || echo null)
    grep -q 'null' <<< "$YEAR" && echo "$OUTPUT   -->   year not found" >> today.txt && continue
    NAME=$(sed -e 's/  $//; s/ $//; s/\./ /g; s/ (Tv-Series)//' <<< "$OUTPUT")

    TMDB_API=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "https://api.themoviedb.org/3/search/tv?api_key=0dec8436bb1b7de2bbcb1920ac31111f&query=$(sed "s/ /%20/g" <<< "$NAME")&page=1&year=$YEAR")

    if [ $(jq '.total_results' <<< "$TMDB_API") == 0 ]; then echo "$OUTPUT   -->   not found" >> today.txt; continue; fi
    A=0
    while [ "$A" -lt $(jq '.total_results' <<< "$TMDB_API") ]; do
        if grep -q "$YEAR" <<< $(jq -r ".results[$A].first_air_date" <<< "$TMDB_API"); then
            POSTER="https://image.tmdb.org/t/p/w500$(jq -r ".results[$A] | .poster_path" <<< "$TMDB_API")"
            if grep -q 'null' <<< "$POSTER"; then echo "$OUTPUT   -->   no poster" >> today.txt && continue; fi
            TMDB_ID=$(jq -r ".results[$A] | .id" <<< ""$TMDB_API"")
            OVERVIEW=$(jq -r ".results[$A] | .overview" <<< "$TMDB_API")
            break
        elif grep -q "$((YEAR+1))" <<< $(jq -r ".results[$A].first_air_date" <<< "$TMDB_API"); then
            POSTER="https://image.tmdb.org/t/p/w500$(jq -r ".results[$A] | .poster_path" <<< "$TMDB_API")"
            if grep -q 'null' <<< "$POSTER"; then echo "$OUTPUT   -->   no poster" >> today.txt && continue; fi
            TMDB_ID=$(jq -r ".results[$A] | .id" <<< ""$TMDB_API"")
            OVERVIEW=$(jq -r ".results[$A] | .overview" <<< "$TMDB_API")
            break
        else
            if [ $(jq '.total_results' <<< "$TMDB_API") == 1 ]; then
                POSTER="https://image.tmdb.org/t/p/w500$(jq -r ".results[$A] | .poster_path" <<< "$TMDB_API")"
                if grep -q 'null' <<< "$POSTER"; then echo "$OUTPUT   -->   no poster" >> today.txt && continue; fi
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

    IMDB_ID=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s --header "Content-Type: application/json" --header "trakt-api-version: 2" --header "trakt-api-key: 64ba02e985f18ec3a00186209b3605cfbbeedf9890898e3a06b8e020111e8194" "https://api.trakt.tv/search/tmdb/$TMDB_ID?type=show" | jq -r '.[0].show.ids.imdb')
    ! grep -q 'tt' <<< "$IMDB_ID" && echo "$OUTPUT   --> IMDB error getting data" >> today.txt && continue

    OMDB_API=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -H "Accept: application/json" -H "Content-Type: application/json" "http://www.omdbapi.com/?i=$IMDB_ID&plot=short&apikey=7759dbc7")
    grep "Error getting data" <<< "$OMDB_API" && echo "$OUTPUT   --> OMDB error getting data" >> today.txt && continue
    YEAR=$(jq -r '.Year' <<< $OMDB_API)
    TITLE="$(jq -r ".Title" <<< "$OMDB_API") ($YEAR)"
    PLOT=$(jq -r '.Plot' <<< "$OMDB_API"); grep -q 'N/A' <<< "$PLOT" && PLOT="$OVERVIEW"; CAST=$(jq -r '.Actors' <<< "$OMDB_API")
    GENRE=$(jq -r '.Genre' <<< "$OMDB_API"); if grep -qi 'documentary' <<< "$GENRE"; then continue; fi
    RATING=$(jq -r '.imdbRating' <<< "$OMDB_API")
    if [ "$RATING" == 'N/A' -o "$GENRE" == 'N/A' ]; then
        if ! grep -q ^"$OUTPUT" whitelist; then
            echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $(sed 's/–/, /' <<< $YEAR)" > errors/"$OUTPUT"
            curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s "$POSTER" -o errors/"$TITLE".jpg
            if [ $(identify -format "%w" errors/"$TITLE".jpg)> /dev/null -gt 530 -o $(identify -format "%w" errors/"$TITLE".jpg)> /dev/null -lt 470 -o $(identify -format "%h" errors/"$TITLE".jpg)> /dev/null -gt 780 -o $(identify -format "%h" errors/"$TITLE".jpg)> /dev/null -lt 720 ]; then
            rm errors/"$TITLE".jpg; echo "$OUTPUT   -->   invalid image height/weight dimension & rating/genre" >> today.txt
            continue
            fi
            echo "$OUTPUT   -->   rating/genre not available" >> today.txt
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

    touch MD5SUM
    if ! grep -q "$OUTPUT=" MD5SUM; then echo "$OUTPUT=$(md5sum <<< "$LINKS")" >> MD5SUM; fi

    if grep -owF "$TITLE" series_list.txt; then
set +x
        WP_RESULTS=$(curl --connect-timeout 5 --max-time 10 --retry 5 --retry-delay 0 --retry-max-time 40 -s -X GET "https://series.turbodl.xyz/wp-json/wp/v2/posts?search=$(sed 's/[(-)]//g; s/ /%20/g' <<< "$TITLE")&per_page=5")
set -x

        while [[ "$A" != 6 ]]; do
            if grep "$(sed 's/ (.*)//' <<< "$TITLE")" <<< "$(jq -r ".[$A].title.rendered" <<< "$WP_RESULTS" | sed -e "s/&#8211;/-/g; s/&#8217;/'/g; s/&#038;/\&/g; s/&#8216;/'/g; s/&#822[0-1];/\"/g; s/&amp;/\&/g")"; then
                WP_LINKS=$(jq -r ".[$A].content.rendered" <<< "$WP_RESULTS" | grep -o '<a href.*</a>' || true)
                if grep -q 'http' <<< "$WP_LINKS"; then
                    LINKS2=$(sed "/CLICK HERE FOR SUBTITLES/d; /target.*self.*Load more/d" <<< "$LINKS")
                    if [ "$(grep "$OUTPUT=" MD5SUM | sed 's/.*=//')" == "$(md5sum <<< "$LINKS2")" ]; then
                        continue 2
                    else
                        if [ "$USER" != persie ]; then
                            curl -s -X DELETE --user "looneytkp:Sgm4kv101413$" "https://series.turbodl.xyz/wp-json/wp/v2/posts/$(jq ".[$A].id" <<< "$WP_RESULTS")?force=true" 2> /dev/null
                            curl -s -X DELETE --user "looneytkp:Sgm4kv101413$" "https://series.turbodl.xyz/wp-json/wp/v2/media/$(jq ".[$A].featured_media" <<< "$WP_RESULTS")?force=true" 2> /dev/null
                        fi
                        sed -i "s/$OUTPUT=.*/$OUTPUT=$(md5sum <<< "$LINKS2")/" MD5SUM
                        echo "deleted $OUTPUT"
                    fi
                else
                    sed -i "/$TITLE/d" series_list.txt
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
        echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\n$LINKS\\n</div>\\n\\nTags: $GENRE, $(sed 's/–/, /' <<< $YEAR)" > errors/"$OUTPUT"
        echo "$OUTPUT   -->   invalid image height/weight dimension" >> today.txt
        continue
    fi

    if grep -qowF "$TITLE" series_list.txt; then echo "$TITLE   -->   updated" >> today.txt; else echo "$TITLE" >> today.txt && sed -i "1s/^/$TITLE\\n/" series_list.txt; fi
    echo "$TITLE #$OUTPUT" >> titles.txt

    touch links; D=1
    while true; do
        if [ $D -gt 9 ]; then
            if grep -qiE "s$D.*(480p|720p|1080p)" <<< "$LINKS"; then
                if ! grep -qi "Season $D" links; then echo -e "<h1>Season $D</h1>" >> links; fi
                if grep -qi "s$D.*480p" <<< "$LINKS"; then
                    echo -e "\\n480p\\n$(grep -i "s$D.*480p" <<< "$LINKS")" >> links
                fi
                if grep -qi "s$D.*720p" <<< "$LINKS"; then
                    echo -e "\\n720p\\n$(grep -i "s$D.*720p" <<< "$LINKS")" >> links
                fi
                if grep -qi "s$D.*1080p" <<< "$LINKS"; then
                    echo -e "\\n1080p\\n$(grep -i "s$D.*1080p" <<< "$LINKS")" >> links
                fi
            elif grep -qi "s$D" <<< "$LINKS"; then
                echo -e "\\n$(grep -i "s$D" <<< "$LINKS")" >> links
            else
                break
            fi
        else
            if grep -qiE "s0$D.*(480p|720p|1080p)" <<< "$LINKS"; then
                if ! grep -qi "Season 0$D" links; then echo -e "<h1>Season 0$D</h1>" >> links; fi
                if grep -qi "s0$D.*480p" <<< "$LINKS"; then
                    echo -e "\\n480p\\n$(grep -i "s0$D.*480p" <<< "$LINKS")" >> links
                fi
                if grep -qi "s0$D.*720p" <<< "$LINKS"; then
                    echo -e "\\n720p\\n$(grep -i "s0$D.*720p" <<< "$LINKS")" >> links
                fi
                if grep -qi "s0$D.*1080p" <<< "$LINKS"; then
                    echo -e "\\n1080p\\n$(grep -i "s0$D.*1080p" <<< "$LINKS")" >> links
                fi
            elif grep -qi "s0$D" <<< "$LINKS"; then
                echo -e "\\n$(grep -i "s0$D" <<< "$LINKS")" >> links
            else
                break
            fi
        fi
        D=$((D+1))
    done

set +x
    echo -e "<div style=\"text-align: center;\">\\n$PLOT\\n\\nIMDB Rating: $RATING\\nCast: $CAST\\nGenre: $GENRE\\n\\nDownload Links:\\n$(cat links)\\n</div>\\n\\nTags: $GENRE, $(sed 's/–/, /' <<< "$YEAR")" > complete/"$OUTPUT"
set -x
    rm links

done <<< "$output"

if [ ! -e today.txt ]; then
    if [ "$USER" != persie ]; then
        echo | mutt -s 'turbodlbot | series logs' -i logs.txt series_list.txt -- persie@turbodl.xyz
    fi
    exit
fi
sed -i "1s/^/$(date)\\n--------------------------------\\n/" today.txt

if [ "$USER" != persie ]; then
    if [ -e titles.txt ]; then
        echo -e "\\n---sorting randomly---"
        SORTED_POSTS=$(sort -Rr < titles.txt)
        while IFS= read -r SORTED; do
            echo | mutt -s "$(sed 's/ #.*//' <<< "$SORTED")" -i complete/"$(grep -o '#.*' <<< "$SORTED" | sed 's/#//')" -a complete/"$(sed 's/ #.*//' <<< "$SORTED")".jpg -- Ahd8s7a8a9skA@turbodl.xyz
        done <<< "$SORTED_POSTS"
    fi

    if [ -z "$(ls -A errors)" ]; then
        echo | mutt -s 'turbodlbot | series' -i today.txt -- persie@turbodl.xyz info@turbodl.xyz
    else
        echo | mutt -s 'turbodlbot | series' -i today.txt -a errors/* -- persie@turbodl.xyz info@turbodl.xyz
    fi
    echo | mutt -s 'turbodlbot | series logs' -i logs.txt series_list.txt -- persie@turbodl.xyz
fi
