#!/bin/bash
# Movies must have *imdb-tt* in filename
# radarr naming scheme {Movie CleanTitle} {(Release Year)} [imdb-{ImdbId}]{[Quality Title]}{[MediaInfo AudioCodec}{ MediaInfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}

# Set all the variables

# Location of plex db
DATABASE="/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db"

# Movie library location
MOVIE_PATH="/mnt/movies"

# Backup location for plexdb
BACKUP_PATH="/mnt/backup/plex"

# api key
API="[api key]"

# plex server ip
PLEX_IP="192.168.0.100"

# name of plex container
PLEX_CONTAINER_NAME="plex"

# container list of all containers that should be stopped while writting to plex db
CONTAINERS="plex updatetool"

## Script Start ##
clear

# make sure api key is valid before proceeding
APITEST=$(curl -s -f "http://www.omdbapi.com/?apikey=$API&i=tt0113277&r=xml")
if [[ $APITEST ]]; then
    echo "API key is valid ... proceeding"
else
    echo "API key is NOT valid ... exiting"
    exit;
fi

# check to see if there is plex activity before proceeding
PLEX_ACTIVITY=$(curl --silent $PLEX_IP:32400/status/sessions | grep -c "MediaContainer size=\"0\"")
if [ "$PLEX_ACTIVITY" -eq 0 ]; then
    echo "Plex has active connections ... exiting"
    exit;
fi
echo "Plex has no active connections ... proceeding"

BACKUP_FILE="$BACKUP_PATH/$(date +%s)/"
LAST_START="1900-01-01 00:00:00"
MOVIE_PATH=$(realpath -s $MOVIE_PATH)
BACKUP_PATH=$(realpath -s $BACKUP_PATH)
SCRIPT=`realpath $0`
DATE_CREATED=$(date "+%Y-%m-%d %T")
echo "Script last run on $LAST_START"

unset FILE_LIST
unset IMDB_GENRE_LIST

# get the files from the movie path that are newer than the last time the script was run
# i use a post-process script for radarr to 'touch' the files on import and upgrade to 
# ensure they have the proper modification time

echo "Getting movies from $MOVIE_PATH"
declare -a FILE_LIST
while IFS= read -u 3 -d $'\0' -r file; do
    FILE_LIST+=( "$file" )
done 3< <(find $MOVIE_PATH -iname "*imdb-tt*" -type f -newermt "$LAST_START" -print0)
echo "Done getting movies"

MOVIE_COUNT=$(echo ${#FILE_LIST[@]})
if [ "$MOVIE_COUNT" -eq 0 ]; then
    echo "No new movies to process"
    sed -i -E "0,/(LAST_START=).*/{s|(LAST_START=).*|LAST_START=\"$DATE_CREATED\"|}" "$SCRIPT"
    exit;
fi
echo "Number of movies to process: $MOVIE_COUNT"

# stop any docker containers that might access the plex db
echo "Stopping Docker Containers"
docker stop $CONTAINERS

# backup the db and wait 10s for everything to shutdown before starting to mess with the db
echo "Backing up Plex DB to $BACKUP_FILE"
rsync -ah "$DATABASE" "$BACKUP_FILE"
chmod 777 -R "$BACKUP_FILE"
echo "Backup Complete"

# remove older backups
echo "Puring old backups"
find $BACKUP_PATH -type d -mtime +2 -exec rm -rf {} \;

# copy plex executables from the container
docker cp $PLEX_CONTAINER_NAME:/usr/lib/plexmediaserver/ /tmp/plexsql

# create alias for plex executables
shopt -s expand_aliases
alias sqlite3='/tmp/plexsql/Plex\ Media\ Server --sqlite'

# insert the imdb genres into the plex db if they are missing
echo "Inserting missing genres into tags table"
declare -a IMDB_GENRE_LIST=("Action" "Adventure" "Adult" "Animation" "Biography" "Comedy" "Crime" "Documentary" "Drama" "Family" "Fantasy" "Film-Noir" "Game-Show" "History" "Horror" "Musical" "Music" "Mystery" "News" "Reality-TV" "Romance" "Sci-Fi" "Short" "Sport" "Talk-Show" "Thriller" "War" "Western")
for genre in "${IMDB_GENRE_LIST[@]}"
  do
  TAGS_GENRE_ID=$(echo SELECT id FROM tags WHERE tag=\'"$genre"\' and tag_type=1| sqlite3 "$DATABASE") 
  if [ -z "$TAGS_GENRE_ID" ]
  then
      echo "Adding $genre to tags table"
      echo "insert into tags (tag, tag_type, created_at, updated_at) VALUES (\"$genre\",1,\"$DATE_CREATED\",\"$DATE_CREATED\")" | sqlite3 "$DATABASE"
      TAGS_GENRE_ID=$(echo SELECT id FROM tags WHERE tag=\'"$genre"\' and tag_type=1| sqlite3 "$DATABASE")
  fi
done
echo "Done inserting genres into tags table"

# start looping through the filenames and fixing the genres in plex db
echo "Processing Movies ..."
COUNTER=1
for X in "${FILE_LIST[@]}"; do
  IMDB_GUID=$(echo "$X" | grep -Po '(?<=imdb-)[^]]+')
  OMDB=$(curl -s -f "http://www.omdbapi.com/?apikey=$API&i=$IMDB_GUID&r=xml")
  TITLE=$(echo "$OMDB" | grep -oP 'title="\K[^"]+')
  IMDB_ID=$(echo "imdb://$IMDB_GUID")

  # get tag id and metadata_id associated with the imdb_guid
  # if the tag id is empty then it probably means there is a movie not matched correctly in plex
  TAG_ID=$(echo SELECT id FROM tags WHERE tag_type='314' and tag LIKE \"%"$IMDB_ID"%\" | sqlite3 "$DATABASE" 2>/dev/null)
  if [ -z "$TAG_ID" ]
  then
      echo "***** No match found in database for $TITLE ($IMDB_GUID). Possible mismatch between filename and plex *****"
      echo
      continue
  fi
  META_ID=$(echo SELECT metadata_item_id FROM taggings WHERE tag_id="$TAG_ID" | sqlite3 "$DATABASE")
  TITLE=$(echo SELECT title FROM metadata_items where library_section_id is 4 and id="$META_ID" | sqlite3 "$DATABASE") 

  # delete existing genres from the db
  echo delete from taggings where metadata_item_id="$META_ID" and tag_id in \(select id from tags where tag_type=1\) | sqlite3 "$DATABASE"

  # grab the genres from what omdb returned and format that correctly 
  # see what we can do to clean up the gnere grepping and awking so i only have one variable?!
  METDATA_ITEMS_GENRE=$(echo "$OMDB" | grep -oP 'genre="\K[^"]+' | sed  's/, /\|/g')
  TAGGINGS_GENRE=$(echo "$OMDB" | grep -oP 'genre="\K[^"]+')
  RATING=$(echo "$OMDB" | grep -oP 'imdbRating="\K[^"]+')
  GENRE_CLEAN=$(echo "$TAGGINGS_GENRE" | sed  's/, /\ /g')

  # print which movie is being processed to the screen
  echo
  echo "[$COUNTER]:$TITLE ($IMDB_GUID) ($RATING)"
  echo "TAG ID: $TAG_ID"
  echo "META ID: $META_ID"

  # loop through the genres and add to taggings table
  INDEX=0
  for Y in $GENRE_CLEAN; do
    echo "Adding $Y to taggings Table"
    TAGS_GENRE_ID=$(echo SELECT id FROM tags WHERE tag=\'"$Y"\' and tag_type=1| sqlite3 "$DATABASE")
    echo "insert into taggings (metadata_item_id, tag_id, \"index\", created_at) VALUES ($META_ID,$TAGS_GENRE_ID,$INDEX ,\"$DATE_CREATED\")" | sqlite3 "$DATABASE"
    INDEX=$((INDEX + 1))
  done

  # update the tags_genre field to match the genres assigned in taggings table
  echo "Updating tags_genre in metadata_items to: ${METDATA_ITEMS_GENRE}"
  echo UPDATE metadata_items SET tags_genre=\""${METDATA_ITEMS_GENRE}"\" WHERE id="$META_ID" | sqlite3 "$DATABASE"
  echo "Locking Genre and Collection Tags"
  echo  UPDATE metadata_items SET user_fields=\"lockedFields=15\|16\" WHERE id="$META_ID" | sqlite3 "$DATABASE"
  echo
  COUNTER=$((COUNTER + 1))
done

#remove plex docker executables
unalias -a sqlite3
rm -rf /tmp/plexsql

# restart the containers
echo "Restarting Docker Containers"
docker start $CONTAINERS

#Update last run time
sed -i -E "0,/(LAST_START=).*/{s|(LAST_START=).*|LAST_START=\"$DATE_CREATED\"|}" "$SCRIPT"
