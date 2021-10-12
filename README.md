# docker-plex-genreupdate

Script that will update plex genres to IMDB genres. Based on docker install of plex. Run with a cron job 

# Scope

I was never a big fan of the way plex handles genres. There are just too many for my personal taste. I prefer to have a simple set of genres, not hundreds of genres and subgenres. By keeping my genres more simple. I can easily setup smart collections based on genres. 

The script querries OMDBAPI using the movie IMDB ID to retrieve the genres. It then updates the plexdb, using plex's own sqlite, with the correct genres for each movie. It will need a method to determine which movies have been added since the last time the script was run, to avoid running a full update each time. Since I am using radarr to manage my movies, I uses a radarr post process script that runs 'touch' on movies that are imported. The script keeps track of the last timne it was run, and scans for any new movies that have been added since it's last run time.   

# Prerequisites
1. Docker
2. Plex running in docker
3. TMDB API key
4. Filenames MUST contain *imdb-tt*. Example of naming convention using radarr: 
```
{Movie CleanTitle} {(Release Year)} [imdb-{ImdbId}]{[Quality Title]}{[MediaInfo AudioCodec}{ MediaInfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}
```
5. A method to update each new movies created time as they are placed into movie library. 

# Installation
1. Save script to to /usr/local/bin/
2. Make sure it's executable (chmod +x)
3. Edit genreupdate.sh and change the variables to your environment. 
```
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
```
# Cron job (example runs every 6 hrs) 
```
0 */6 * * *     /usr/local/bin/genreupdate.sh
```


