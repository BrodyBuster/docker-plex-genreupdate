# docker-plex-genreupdate

Script that will update plex genres to IMDB genres. Based on docker install of plex. Run with a cron job 

I prefer to have a simple set of genres, not hundreds of genres and subgenre. This way I can easily setup smart collections based on genre. The script querries OMDBAPI using the movie IMDB ID to retrieve the genres. Then updates the plexdb with the correct genres for each movie.

# Requirements
1. Docker
2. Plex running in docker
3. TMDB API key
4. Filenames MUST contain *imdb-tt*. Example of naming convention using radarr: 
```
{Movie CleanTitle} {(Release Year)} [imdb-{ImdbId}]{[Quality Title]}{[MediaInfo AudioCodec}{ MediaInfo AudioChannels]}{[MediaInfo VideoCodec]}{-Release Group}
```
5. A method to 'touch' movies as they are placed into movie library. I use a radarr post process script that runs 'touch' on movies that are imported or upgraded




