if (!process.env.AWS_LAMBDA_FUNCTION_NAME) {
  try {
    await import('dotenv/config');
  } catch {}
}

const {
  SPOTIFY_CLIENT_ID,
  SPOTIFY_CLIENT_SECRET,
  SPOTIFY_REFRESH_TOKEN,
  DEFAULT_SPOTIFY_DEVICE_ID
} = process.env

export async function getAccessToken() {
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: SPOTIFY_REFRESH_TOKEN
  })

  const authHeader = Buffer
    .from(`${SPOTIFY_CLIENT_ID}:${SPOTIFY_CLIENT_SECRET}`)
    .toString('base64')

  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${authHeader}`,
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body
  })

  const json = await res.json()
  if (!res.ok) throw new Error(`Failed to refresh token: ${JSON.stringify(json)}`)
  // console.log('New access token:', json.access_token)
  return json.access_token
}

export async function getPlaylists(token) {
  let playlists = []
  let url = 'https://api.spotify.com/v1/me/playlists?limit=50'

  while (url) {
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` }
    })
    const data = await res.json()
    playlists = playlists.concat(data.items)
    url = data.next
  }

  return playlists
}

export function findPlaylistByName(playlists, name) {
  const lower = name.toLowerCase()
  const found = playlists.find(p => p.name.toLowerCase() === lower)

  if (!found) {
    // Try partial match
    return playlists.find(p => p.name.toLowerCase().includes(lower))
  }

  return found
}

async function startPlayback(token, playlistUri, preferredDeviceId) {
  if (preferredDeviceId) { console.log('Preferred device ID:', preferredDeviceId) }
  const tryPlay = async (deviceId = null) => {
    const url = deviceId
      ? `https://api.spotify.com/v1/me/player/play?device_id=${deviceId}`
      : `https://api.spotify.com/v1/me/player/play`

    const res = await fetch(url, {
      method: 'PUT',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ context_uri: playlistUri })
    })

    if (!res.ok) {
      const err = await res.json().catch(() => ({}))
      throw new Error(JSON.stringify(err))
    }
  }

  try {
    if (preferredDeviceId) {
      await tryPlay(preferredDeviceId)
      return
    }
  } catch (e) {
    console.warn('Preferred device playback failed, will fallback.', e?.message)
    // fall through to next step
  }

  try {
    await tryPlay() // no deviceId argument → no device_id param → implicit
    return
  } catch (e) {
    console.warn('Playback without device failed, will try default device if set.', e?.message)
    // fall through to default device attempt
  }

  // 3) If we got an error from #1 or #2, try DEFAULT_SPOTIFY_DEVICE_ID (if provided)
  if (DEFAULT_SPOTIFY_DEVICE_ID) {
    await tryPlay(DEFAULT_SPOTIFY_DEVICE_ID)
    return
  }

  // If no default is set or that failed as well, surface a clear error
  throw new Error('Failed to start playback using mapped, implicit, or default device.')
}

export async function handlePlayRequest(playlistName, alexaDeviceId /* the unique identifier after stripping common prefix */) {
  try {
    if (!playlistName || !playlistName.trim()) {
      return { success: false, message: "Playlist name required." }
    }
    const token = await getAccessToken()
    const playlists = await getPlaylists(token)
    const match = findPlaylistByName(playlists, playlistName)

    if (!match) {
      return {
        success: false,
        message: `Playlist not found: ${playlistName}`
      }
    }

    // Load the Alexa→Spotify device map (stored as a single-line JSON in .env)
    // Keys are the unique Alexa device IDs *without* the common "amzn1.ask.device." prefix
    let mappedSpotifyDeviceId = null
    const mapStr = process.env.ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP
    if (mapStr && alexaDeviceId) {
      try {
        const deviceMap = JSON.parse(mapStr)
        mappedSpotifyDeviceId = deviceMap[alexaDeviceId] || null
      } catch (e) {
        console.warn('Failed to parse ALEXA_DEVICE_ID_TO_SPOTIFY_DEVICE_ID_MAP:', e?.message)
      }
    }

    // Try mapped device (if present), then implicit, then DEFAULT_SPOTIFY_DEVICE_ID
    await startPlayback(token, match.uri, mappedSpotifyDeviceId)

    return {
      success: true,
      message: `OK, playing "${match.name}" on Spotify`
    }
  } catch (err) {
    console.error(err)
    return {
      success: false,
      message: `Error: ${err.message}`
    }
  }
}

// Alexa SkillKit entrypoint
export const handler = async (event) => {
  const alexaDeviceIdRaw = event?.context?.System?.device?.deviceId

  // Strip the common prefix so we work with the real identifier
  const alexaDeviceId = alexaDeviceIdRaw?.replace(/^amzn1\.ask\.device\./, "")
  console.log("Alexa deviceId:", alexaDeviceId)

  const playlistName = event?.request?.intent?.slots?.playlistName?.value
  const result = await handlePlayRequest(playlistName || '', alexaDeviceId)

  return {
    version: '1.0',
    response: {
      outputSpeech: {
        type: 'PlainText',
        text: result.message
      },
      shouldEndSession: true
    }
  }
}

// ✅ CLI entrypoint for local testing
if (import.meta.url === `file://${process.argv[1]}`) {
  const name = process.argv[2]
  if (!name) {
    console.error('Usage: node index.mjs "Playlist Name"')
    process.exit(1)
  }

  const result = await handlePlayRequest(name || '')
  console.log(result.success ? '✅' : '❌', result.message)
}