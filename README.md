# "My Playlist" Alexa skill (for Spotify)

A custom Alexa skill that plays your Spotify playlists reliably — unlike Amazon's broken-ass Spotify skill.

## Features
- Say: "Alexa, tell [non-music-sounding invocation name] to [extra intent word required here] X" where X is your playlist name, e.g. "Alexa, tell P.L. to play vibe coding"
- Actually finds and plays your playlist named X (screw you, Jeff Bezos)

## Folders
- `lambda/`: Node.js AWS Lambda code
- `alexa/`: Alexa Skill interaction model (JSON)
- `deploy/`: Helper scripts

## Environment Variables (Lambda)
Set these in the AWS console or `.env`:
- `SPOTIFY_CLIENT_ID`
- `SPOTIFY_CLIENT_SECRET`
- `SPOTIFY_REFRESH_TOKEN`

## Prereqs
- aws cli (signed in)
- spotify api credentials (client id, secret, refresh token)

## Installation
```
cp example.env .env
# edit .env
# LAMBDA_FUNCTION_NAME must have a value
./deploy/create-lambda-role.sh
# populate LAMBDA_ROLE_ARN in `.env`
# populate SPOTIFY_* .env values

# test it locally
npm i
node ./lambda/index.mjs "playlist name here"

# deploy the function to aws lambda
./deploy/publish.sh

# test the lambda deployment
./lambda/logs.sh
./lambda/invoke.sh "playlist name here"
```

### Create Alexa Skill

#### Invocation name
#### Intents
##### Utterances

## Mapping Alexa devices to Spotify devices

If you want to ensure the Alexa device you spoke to is the one that the playlist starts playing on, you need to provide a map to translate Alexa device IDs to Spotify device IDs (otherwise, whatever device Spotify is active on will be used, and lacking that, the default device id you provided will be used) 

### Fetching your Alexa device IDs
Only method I know right now is to log it from a request handler, so uncomment the `console.log` from `lambda.index.mjs`, run `deploy/publish.sh`, then `lambda/logs.sh` and then invoke the Alexa skill from a real Alexa device on the same Amazon account, and its ID should appear in the logs.

### Fetching your Spotify device IDs
```
curl -X GET "https://api.spotify.com/v1/me/player/devices" -H "Authorization: Bearer ACCESS_TOKEN_HERE"
```
(You may well want to `console.log` a fresh access token from the same lambda function, except for this one you can invoke it directly via aws cli or locally via `node lambda/index.mjs`)

Once you have your IDs, fill in the `ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP` env var.