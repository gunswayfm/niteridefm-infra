# NiteRide.FM Multi-Channel Architecture Design

**Date**: 2026-02-10
**Status**: Final - All Decisions Resolved
**Author**: Jesse Pifer + Claude
**Validated**: 2026-02-10 - Corrections applied from live server inspection
**Deep Dive**: 2026-02-11 - 4 parallel agents explored full codebase + infra architecture

---

## 1. Problem Statement

NiteRide.FM currently operates Channel 1 as a 24/7 cyberpunk streaming channel. The original channel system was designed with multi-channel in mind but never fully materialized. Channel 1 is up and running; we now need to:

1. Build Channel 2 as a fully independent streaming channel
2. Create a repeatable process for onlining additional channels (up to 9)
3. Update the admin panel to properly manage all channels from a unified interface
4. Update the public stream player to support channel switching

## 2. Current State Assessment

### What exists and works (Channel 1)

**Database Layer** - Well-structured for multi-channel:
- `Channels` table (id 1-9, per-channel commercial config, daypart config, RTMP keys, theme colors)
- `ChannelStates` tracks current mode (vod/live/commercial) per channel
- `Schedules` has `channel_id` FK with index (`idx_schedules_channel_time`)
- `ProgramChannelAssignments` links shows to channels with daypart restrictions
- `ChannelCommercials` junction table exists (but empty - commercials not yet linked to channels)
- Channel 1 row fully configured and active

**Backend Services** - Mostly channel-parameterized:
- `SchedulerService`, `AlgorithmControlService`, `SimpleSchedulerService` all accept `channelId`
- Stitcher writes to Redis at `channel:{channelId}:timeline` / `channel:{channelId}:live_timeline`
- `PlaylistBuilder.buildPlaylist(channelId, quality)` reads from channel-specific Redis keys
- Admin routes for schedule, primetime, commercials, shows accept channel parameters

**Frontend Admin** - Has channel selection UI:
- `ChannelSwitcher` component (buttons 1-9, active/inactive states via API)
- `SchedulePage` uses `selectedChannel` state, passes to API calls
- `ChannelsPage` shows management grid for all 9 channel slots
- `StreamsPage` has channel-specific RTMP configuration

### What is hollow or missing

**Playlist Generator** - Hardcoded to Channel 1:
- All routes in `index.js` are `/ch1/*.m3u8`
- Always calls `builder.buildPlaylist(1, quality)`
- No `/ch2/` or dynamic routes exist

**PM2 Ecosystem** - Mixed channel-awareness:
- `playlist-generator-ch1` hardcoded to `/ch1/` routes, always calls `buildPlaylist(1, quality)`
- `stream-guard` hardcoded to `http://localhost:9050/ch1/playlist.m3u8`
- `stream-monitor` already reads `MONITOR_CHANNEL_ID` env (defaults to '1'), but Redis key `stream:health:monitor` lacks channel scoping
- `cdn-prewarmer` already reads `CHANNEL_ID` env (line 39 in server.js) - **ready for multi-channel**
- `streaming-core` scheduler job loops all active channels from DB - **ready for multi-channel**
- `rtmp-receiver` authenticates stream key to get channel_id - **ready for multi-channel**
- `admin-service` fully channel-aware API - **ready for multi-channel**
- `live-controller` **DOES NOT EXIST** in codebase (placeholder in ecosystem.config.js)
- `storage-service` **DOES NOT EXIST** in codebase (placeholder in ecosystem.config.js)

**HLS Directory Structure** - Partially channel-aware:
```
/var/www/hls/
  ch1/           <-- Channel 1 HLS output (channel-prefixed, good)
  ch1-comm/      <-- Channel 1 commercials (channel-prefixed, good)
  ch1-vod/       <-- Channel 1 VOD (channel-prefixed, good)
  segments/      <-- NOT channel-scoped
    audio/
    breaks/
    episodes/
    live/
    slate/
    stingers/
```

**Nginx CDN Config** - Single channel:
- `cdn.niteride.fm.conf` routes `/stream/` to port 9050 (single playlist generator)
- `/segments/` serves from flat directory, no channel routing

**Content Services** - Channel unaware, filesystem-only:
- Two separate upload/segmentation paths exist (potential inconsistency):
  - `library-upload.js` in admin-service: inline FFmpeg segmentation during upload (single-quality copy-codec video + AAC audio)
  - `content-segmenter` service: batch multi-quality segmentation on startup (1080p/720p/360p/audio via single-pass FFmpeg)
- `storage-service` **DOES NOT EXIST** in codebase - it's a placeholder in ecosystem.config.js
- `tusd` (resumable uploads, port 8444) is also **NOT implemented**
- All content writes to `/var/www/hls/segments/` without channel prefixes
- `library-upload.js` uses multer to save to local filesystem (`/opt/niteride/uploads`)
- **No S3/object storage integration exists** - all content lives on the local VPS disk
- Timeline segment URLs are **relative** (`/segments/episodes/...`), not absolute - portable across CDN configs
- This is a blocker for shared library across VPSes (see Section 5.2 prerequisite)

**Commercials** - Not linked to channels:
- `ChannelCommercials` junction table has 0 rows
- Commercials are currently global

**Chat** - Not channel-aware:
- **Zero** `channel_id` fields across all 4 chat models (ChatMessage, ChatBan, ChatSettings, ChatEmote)
- Chat service is a **TypeScript app** in `niteridefm-fe/backend/services/chat-service/` running on the Web Server (port 4000)
  - Has its own Sequelize models: ChatMessage, ChatBan, ChatSettings, ChatEmote
  - Connects to **Web Server's local Postgres** at `localhost:5432` (confirmed from `.env.example`)
  - `streaming-core/src/services/chat-socket.js` in the BE repo is **orphaned** - never imported anywhere
- No Socket.IO rooms at all - all messages broadcast globally via `io.emit()` (not `io.to(room).emit()`)
- Chat settings (slow mode, emote-only, disabled) are global, not per-channel
- Chat emotes are global across all channels

**Frontend Player** - Single channel:
- `PublicStreamPage.tsx` HLS URL hardcoded: `` const STREAM_URL = `${CDN_URL}/stream/ch1/playlist.m3u8` ``
- Player is **Vidstack Media Player** (not hls.js directly) with HLS.js config for buffering/latency
- No channel selector for viewers
- `ChannelSwitcher` component communicates via props (`selectedChannel`, `onChannelChange`), not context/zustand

## 3. Architecture Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Channel VPS model | Separate VPS per channel | Full isolation, independent scaling, independent failure domains |
| Content library | **Shared** via S3 | Shows may play across channels. **Requires S3 migration** (est. 8-13 days). Each VPS segments locally from shared S3 source. |
| Commercials | **Per-channel assignments** | Wire up existing `ChannelCommercials` junction table. Each channel gets its own commercial pool. |
| Stingers | **Per-program** (no channel scoping needed) | Stingers are assigned to programs via `ShowStingerPairAssignment`. Since programs are assigned to channels, stingers follow naturally. |
| Admin interface | Unified on Web Server | Single admin at niteride.fm/admin, gateway routes to correct VPS |
| Chat location | Centralized on Web Server | Channel-scoped messages via Socket.IO rooms. **Bans and emotes are global** across all channels. |
| CDN model | Per-channel subdomain | `cdn-ch{N}.niteride.fm`, cache isolation, independent origins. Ch1 fully migrates from `cdn.niteride.fm` to `cdn-ch1.niteride.fm` (allows testing channel infra without spinning up Ch2). |
| Grid | Channel-agnostic | Community layer stays global, no changes needed |
| Channel 2 content | Empty at launch | Admin panel used to add content. No seed data for shows/episodes. |

## 4. High-Level Architecture

```
+-----------------------------------------------------------+
|              WEB SERVER (194.247.183.37)                   |
|                                                           |
|  niteride.fm/admin   --> Admin UI (unified, all channels) |
|  niteride.fm/stream  --> Player (channel selector)        |
|                                                           |
|  API Gateway: routes /api/v1/{resource}?channel=N         |
|    to the correct Channel VPS via Channel Registry        |
|                                                           |
|  Channel Registry: channel_id -> VPS endpoint mapping     |
|                                                           |
|  Chat Service: Socket.IO with channel-scoped rooms        |
|    chat-ch1, chat-ch2, etc.                               |
|                                                           |
|  Identity Service: Supabase JWT (shared all channels)     |
+----------+----------------------------+------------------+
           |                            |
    +------v------+             +-------v------+
    | CHANNEL 1   |             | CHANNEL 2    |
    | VPS         |             | VPS          |
    | (existing)  |             | (new)        |
    | 194.247.    |             | ???.???.     |
    | 182.249     |             | ???.???      |
    |             |             |              |
    | Redis       |             | Redis        |
    | Postgres    |             | Postgres     |
    | PM2 Stack   |             | PM2 Stack    |
    | HLS Output  |             | HLS Output   |
    | Nginx/SSL   |             | Nginx/SSL    |
    +------+------+             +------+-------+
           |                           |
    cdn-ch1.niteride.fm         cdn-ch2.niteride.fm
      (GCore CDN)                 (GCore CDN)
```

## 5. Detailed Design

### 5.1 Web Server: Channel Registry & API Gateway

> **Current State**: The Web Server (194.247.183.37) already acts as an API gateway.
> Its nginx config (`/etc/nginx/sites-enabled/niteride.fm.conf`) proxies admin routes
> directly to the stream server at `http://194.247.182.249:3002`. The change here
> is evolving this single-destination proxy into a multi-destination router using
> the Channel Registry.
>
> Services already on the Web Server:
> - `niteride-backend` (port 3000) - Public API
> - `identity-service` (port 3001) - Auth/users
> - `guide-service` (port 3105) - Connects REMOTELY to Stream Server DB via `GUIDE_DATABASE_URL`. Read-only EPG service, already channel-parameterized (`:channelId` route). Keep it.
> - `chat-service` (port 4000) - TypeScript chat app (niteridefm-fe repo)

#### Channel Registry

New database table on the Web Server:

```sql
CREATE TABLE channel_registry (
  channel_id    INTEGER PRIMARY KEY,
  name          VARCHAR(100) NOT NULL,
  api_url       VARCHAR(255) NOT NULL,    -- e.g. http://194.247.182.249:3002
  cdn_base_url  VARCHAR(255) NOT NULL,    -- e.g. https://cdn-ch1.niteride.fm
  is_active     BOOLEAN DEFAULT false,
  theme_color   VARCHAR(7),               -- hex color for UI
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Seed data
INSERT INTO channel_registry VALUES
  (1, 'Channel 1', 'http://194.247.182.249:3002', 'https://cdn-ch1.niteride.fm', true, '#00ff00'),
  (2, 'Channel 2', 'http://NEW_VPS_IP:3002', 'https://cdn-ch2.niteride.fm', false, '#ff00ff');
```

#### API Gateway Middleware

**Migration from current state**: Today, the Web Server nginx has a single `proxy_pass http://194.247.182.249:3002` for all admin routes. This must be replaced with channel-aware routing.

> **Deep-dive finding**: `niteride-backend` already uses axios-based proxying at `channels.js:375-466`
> (proxies to Stream Orchestrator). Nginx currently allows 10GB uploads with `proxy_request_buffering off`.
> Routing 10GB file uploads through a Node.js proxy layer creates memory/reliability risks.

Two implementation options:

**Option A (Recommended for MVP): Nginx map-based routing**:
1. Nginx `map` directive resolves `$arg_channel` to the correct VPS backend
2. Zero Node.js overhead - sub-millisecond routing decisions
3. Native websocket support, native large file upload support
4. Requires `nginx -s reload` when adding channels (acceptable for channels 1-3)

```nginx
# /etc/nginx/conf.d/channel_routing.conf
map $arg_channel $channel_backend {
    default     http://194.247.182.249:3002;  # Channel 1
    1           http://194.247.182.249:3002;
    2           http://NEW_VPS_IP:3002;
}

location ~ ^/api/v1/(admin|library|schedule|commercials|primetime|programs|obs-servers|settings|system|diagnostics|stingers|stinger-pairs|shows|channels) {
    proxy_pass $channel_backend;
    # ... standard proxy headers
}
```

**Option B (Future, channels 4+): Node.js proxy middleware** in `niteride-backend` (port 3000):
1. Database-driven routing via Channel Registry lookup
2. Dynamic channel provisioning without nginx reloads
3. Centralized logging, retry logic, fallback handling
4. **Risk**: Must use streaming (not buffering) for file uploads, or bypass Node.js for upload routes

```
Request flow (Option A - nginx map):
  Browser -> niteride.fm/api/v1/schedule?channel=2
    -> Web Server nginx (map lookup: channel=2 -> VPS IP)
      -> Proxy to http://NEW_VPS_IP:3002/api/v1/schedule
        -> Response back to browser

Request flow (Option B - Node.js):
  Browser -> niteride.fm/api/v1/schedule?channel=2
    -> Web Server nginx -> niteride-backend (port 3000)
      -> Channel Registry DB lookup -> http://NEW_VPS_IP:3002
        -> axios proxy to VPS admin-service
          -> Response back to browser
```

**Hybrid approach**: Start with nginx map (Option A) for channels 1-3, build Node.js gateway (Option B) when dynamic provisioning is needed.

Endpoints that are channel-routed (based on current nginx regex):
- `/api/v1/admin/*`
- `/api/v1/library/*`
- `/api/v1/schedule/*`
- `/api/v1/commercials/*`
- `/api/v1/primetime/*`
- `/api/v1/programs/*`
- `/api/v1/settings/*`
- `/api/v1/diagnostics/*`
- `/api/v1/stingers/*`
- `/api/v1/stinger-pairs/*`
- `/api/v1/shows/*`
- `/api/v1/channels/*` (refers to channel config on that VPS)
- `/api/v1/guide/*`
- `/api/v1/live/*`
- `/api/v1/obs-servers/*`
- `/api/v1/system/*`

Endpoints that stay on the Web Server (NOT channel-routed):
- `/api/v1/auth/*` (Identity Service)
- `/api/v1/chat/*` (Chat Service)
- `/api/v1/grid/*` (Grid/Lemmy proxy)
- `/api/v1/channel-registry/*` (new - returns channel list with CDN URLs)

#### New API: Channel Registry Endpoint

```
GET /api/v1/channel-registry
Response:
{
  "channels": [
    {
      "id": 1,
      "name": "Channel 1",
      "cdn_base_url": "https://cdn-ch1.niteride.fm",
      "is_active": true,
      "theme_color": "#00ff00"
    },
    {
      "id": 2,
      "name": "Channel 2",
      "cdn_base_url": "https://cdn-ch2.niteride.fm",
      "is_active": true,
      "theme_color": "#ff00ff"
    }
  ]
}
```

The frontend uses this to:
- Populate the channel switcher (replacing current `/api/v1/channels` call which goes to the stream VPS)
- Resolve the correct CDN URL for the HLS player
- Know which channels are active

### 5.2 Channel VPS: The "Channel Template"

Each Channel VPS runs the identical PM2 service stack:

```
playlist-generator    (port 9050)  - HLS playlist generation          [NEEDS: route parameterization]
streaming-core        (internal)   - Stitcher engine, scheduler engine [READY: loops active channels]
stream-guard          (internal)   - Stream health monitoring          [NEEDS: env-based URL]
stream-monitor        (internal)   - Stream metrics                    [NEEDS: Redis key scoping]
cdn-prewarmer         (port 9061)  - CDN cache warming                 [READY: reads CHANNEL_ID env]
content-segmenter     (internal)   - FFmpeg multi-quality segmentation [READY: processes all unsegmented]
rtmp-receiver         (port 1936)  - Live RTMP ingest                  [READY: multi-channel auth]
admin-service         (port 3002)  - Admin API                         [READY: channel-aware routes]
```

> **Note**: `live-controller` and `storage-service` referenced in ecosystem.config.js **do not exist** in the codebase.
> If S3 migration is pursued, `storage-service` would need to be built from scratch.
> No RTMP nginx config exists in the repo - it's managed externally on the stream server.
> No `docker-compose.yml` exists - Redis/Postgres/pgAdmin containers are managed externally.

#### Environment Configuration

Each VPS has `/opt/niteride/.env` with:

```env
NODE_ENV=production
CHANNEL_ID=2                          # <-- The key differentiator
CHANNEL_NAME="Channel 2"
DATABASE_URL=postgresql://postgres:PASSWORD@localhost:5432/niteridefm_dev
REDIS_URL=redis://localhost:6379
ADMIN_PORT=3002

# Auth (shared across all channels)
SUPABASE_JWT_SECRET=...
SERVICE_KEY=niteride-secret
IDENTITY_SERVICE_URL=http://194.247.183.37:3001

# Monitoring
MONITOR_BASE_URL=https://niteride.fm
MONITOR_CHANNEL_ID=2

# CDN
CDN_BASE_URL=https://cdn-ch2.niteride.fm

# Ports
PORT=9050                             # Playlist generator
RTMP_PORT=1936                        # RTMP receiver
HEALTH_PORT=9003                      # RTMP health check

# Channel-specific paths
HLS_OUTPUT_PATH=/var/www/hls/ch2
HLS_SEGMENTS_DIR=/var/www/hls/segments

# Local upload/processing paths
UPLOAD_DIR=/opt/niteride/uploads

# S3 (only if shared library approach chosen - see Phase 0)
# S3_BUCKET=niteride-media
# S3_ACCESS_KEY=...
# S3_SECRET_KEY=...
```

> **PREREQUISITE: S3 Migration (Decision: Shared library via S3)**
>
> Shows may play across channels, so a shared content library is required.
> Currently, library uploads go directly to the local filesystem via multer:
> - `library-upload.js` saves to `/opt/niteride/uploads/incoming`
> - Processed files move to `/opt/niteride/uploads/processed`
> - HLS segments write to `/var/www/hls/segments/episodes/`
> - Note: Two separate segmentation paths exist (see Section 2 - Content Services)
>
> There is **no S3 integration** today. The upload pipeline must be migrated:
> 1. Upload to local temp directory (as today)
> 2. Process/transcode locally (as today)
> 3. **NEW**: Upload processed segments to S3 bucket
> 4. **NEW**: Build `storage-service` from scratch (does not exist yet) to prefetch segments from S3
>
> See Phase 0 for full S3 migration scope (est. 8-13 days).

#### Code Changes Required in niteridefm-be

**playlist-generator/index.js** - Dynamic routes from CHANNEL_ID:

```javascript
const CHANNEL_ID = parseInt(process.env.CHANNEL_ID || '1');
const CH_PREFIX = `ch${CHANNEL_ID}`;

// Replace hardcoded /ch1/ routes:
app.get(`/${CH_PREFIX}/1080p.m3u8`, authenticate, requireQuality('1080p'), createQualityEndpoint('1080p'));
app.get(`/${CH_PREFIX}/720p.m3u8`, authenticate, requireQuality('720p'), createQualityEndpoint('720p'));
app.get(`/${CH_PREFIX}/360p.m3u8`, authenticate, requireQuality('360p'), createQualityEndpoint('360p'));
app.get(`/${CH_PREFIX}/audio.m3u8`, authenticate, createQualityEndpoint('audio'));
app.get(`/${CH_PREFIX}/playlist.m3u8`, authenticate, requireQuality('720p'), createQualityEndpoint('720p'));
app.get(`/${CH_PREFIX}/master.m3u8`, authenticate, (req, res) => { ... });

// createQualityEndpoint uses CHANNEL_ID instead of hardcoded 1:
const createQualityEndpoint = (quality) => async (req, res) => {
  const playlist = await builder.buildPlaylist(CHANNEL_ID, quality);
  sendPlaylistResponse(res, playlist);
};
```

**ecosystem.config.js** - Parameterized names:

```javascript
const CHANNEL_ID = process.env.CHANNEL_ID || '1';

module.exports = {
  apps: [
    {
      name: `playlist-generator`,  // No longer ch1-suffixed
      script: 'index.js',
      cwd: 'services/playlist-generator',
      env: { NODE_ENV: 'production', PORT: 9050, CHANNEL_ID }
    },
    // ... same for all other services
  ]
};
```

**Admin-service audit** - Ensure no hardcoded channelId=1 defaults. Services should read CHANNEL_ID from env when no explicit channelId is provided in the request.

**Commercials route** (`admin-service/src/routes/commercials.js`) - **Currently has no channel filtering at all.** GET `/api/v1/commercials` returns all commercials globally. The `ChannelCommercials` junction table exists in the schema but has 0 rows and is not queried. Required changes:
- Add `channel_id` filter to GET `/api/v1/commercials` using the `ChannelCommercials` table
- Wire up commercial assignment per channel in the admin UI
- Alternatively, keep commercials global and let the stitcher-engine's existing per-channel config handle selection

**Frontend admin pages audit** (reference implementation: `SchedulePage.tsx` uses inline channel selector + `selectedChannel` state):
- `CommercialPage.tsx` - **Not channel-aware.** No channel selector, no `channelId` passed to any child component. **Needs work.**
- `StreamsPage.tsx` - **Partially channel-aware.** Has inline channel selector and `selectedChannel` state, but SSAI metrics are global and RTMP tab ignores selected channel.
- `DiagnosticsPage.tsx` - System-wide by design (health, services, CDN, asset integrity). **No channel selector needed.**
- `LibraryPage.tsx` and `ShowsPage.tsx` - **DO NOT EXIST** as standalone pages. `ShowsTable` exists as a component only.
- `ChannelSwitcher` component communicates via props, not context/zustand. Pattern: `selectedChannel: number` + `onChannelChange` callback.

#### Channel VPS Provisioning Steps

1. Spin up Ubuntu 24.04 VPS
2. Install dependencies: Node.js 20+, Docker, Docker Compose, nginx, FFmpeg, PM2
3. Clone `niteridefm-be` repo
4. Configure `/opt/niteride/.env` with CHANNEL_ID=N and channel-specific values
5. Start Docker containers (Redis, Postgres, pgAdmin)
6. Run database migrations + seed Channel N row in Channels table
7. Configure nginx with SSL (Let's Encrypt) for `cdn-chN.niteride.fm`
8. Start PM2 services
9. Configure GCore CDN resource for `cdn-chN.niteride.fm` pointing to VPS origin
10. Register channel in Web Server's Channel Registry
11. Set `is_active=true` in Channel Registry to go live

This process should be captured in a provisioning script in the `niteridefm-infra` repo for repeatability.

### 5.3 Chat: Channel-Scoped Rooms

> **Current Architecture**: The active chat service is a **TypeScript app** located at
> `niteridefm-fe/backend/services/chat-service/`, running on the Web Server (port 4000).
> It has its own Sequelize models (ChatMessage, ChatBan, ChatSettings, ChatEmote) and
> connects to Postgres via `DATABASE_URL`. The `chat-socket.js` in `niteridefm-be/services/
> streaming-core/` appears to be legacy/unused.
>
> The Web Server nginx routes `/api/v1/chat/*` and Socket.IO to `localhost:4000`.

**Database migration** on the chat-service's Web Server Postgres database:

```sql
-- Messages: scoped per channel
ALTER TABLE chat_messages ADD COLUMN channel_id INTEGER NOT NULL DEFAULT 1;
CREATE INDEX idx_chat_messages_channel ON chat_messages(channel_id);

-- Settings: scoped per channel (slow mode, emote-only, etc.)
ALTER TABLE chat_settings ADD COLUMN channel_id INTEGER NOT NULL DEFAULT 1;
DROP INDEX IF EXISTS chat_settings_setting_key_key;
CREATE UNIQUE INDEX chat_settings_channel_key ON chat_settings(channel_id, setting_key);

-- Bans: GLOBAL (no channel_id needed - decision: bans apply across all channels)
-- No migration needed for chat_bans

-- Emotes: GLOBAL (no channel_id needed - decision: shared emote set across all channels)
-- No migration needed for chat_emotes
```

**chat-service TypeScript changes** (in `niteridefm-fe/backend/services/chat-service/src/`):

The Socket.IO handler needs channel-scoped room management:

```typescript
// Connection: client sends channelId
socket.on('join-channel', (channelId: number) => {
  // Leave all chat rooms first
  socket.rooms.forEach(room => {
    if (room.startsWith('chat-ch')) socket.leave(room);
  });
  socket.join(`chat-ch${channelId}`);
  socket.data.channelId = channelId;
});

// Messages scoped to channel
socket.on('chat:send', async (data) => {
  const channelId = socket.data.channelId || 1;
  // Save with channel_id
  const msg = await ChatMessage.create({ ...data, channel_id: channelId });
  io.to(`chat-ch${channelId}`).emit('chat:message', msg);
});

// Channel switch (no reconnect needed - just room switch)
socket.on('switch-channel', (newChannelId: number) => {
  socket.leave(`chat-ch${socket.data.channelId}`);
  socket.join(`chat-ch${newChannelId}`);
  socket.data.channelId = newChannelId;
});
```

**Frontend useChat hook**: Add `channelId` parameter. On channel switch, emit `switch-channel` event.

### 5.4 CDN: Per-Channel Subdomains

Each channel gets its own CDN subdomain for cache isolation:

```
cdn-ch1.niteride.fm  ->  GCore CDN  ->  194.247.182.249 (Channel 1 VPS origin)
cdn-ch2.niteride.fm  ->  GCore CDN  ->  NEW_VPS_IP (Channel 2 VPS origin)
```

**Nginx on each Channel VPS** (same structure as current `cdn.niteride.fm.conf`):

```nginx
server {
    listen 80 default_server;
    server_name cdn-chN.niteride.fm _;

    # Dynamic playlists -> playlist-generator
    location /stream/ {
        proxy_pass http://localhost:9050/;
        # ... (same config as current)
    }

    # Static segments
    location /segments/ {
        alias /var/www/hls/segments/;
        # ... (same config as current)
    }
}
```

**GCore CDN setup per channel:**
1. Create new CDN resource in GCore dashboard
2. Set origin to Channel VPS IP
3. Configure SSL for `cdn-chN.niteride.fm`
4. Configure ACME challenge routing on the VPS nginx

**DNS:**
```
cdn-ch1.niteride.fm  CNAME  gcore-cdn-endpoint-ch1
cdn-ch2.niteride.fm  CNAME  gcore-cdn-endpoint-ch2
```

### 5.5 Frontend: Player Channel Switching

**Public stream page changes:**

1. Fetch channel list from Channel Registry endpoint
2. Render `ChannelSwitcher` component above/beside player
3. On channel select:
   - Load new HLS source: `${channel.cdn_base_url}/stream/ch${channelId}/master.m3u8`
   - Switch chat room via Socket.IO
   - Update now-playing metadata query
   - Persist selected channel to localStorage

**Key components affected:**
- `PublicStreamPageV2.tsx` - Add ChannelSwitcher, dynamic stream URL
- `useChat.ts` / `chatStore.ts` - Add channelId param, room switching
- `useChannelGuide.ts` - Already takes channelId, route through gateway
- `CurrentProgramTile.tsx` - Already takes channelId, no change needed
- `apiClient.ts` - Add channel param to admin API calls

**API client pattern for admin pages:**

> **Deep-dive finding**: An interceptor approach was considered but rejected. Some endpoints are
> system-wide (health, CDN, services) and should NOT receive channel params. The filtering logic
> would be fragile. Instead, pass `channelId` explicitly in each API call - this matches the
> existing `SchedulePage` pattern and is clearer about intent.

```typescript
// Explicit channelId in API calls (preferred pattern - matches SchedulePage)
const { data } = useQuery({
  queryKey: ['schedule', selectedChannel],
  queryFn: () => apiClient.get(`/schedule/${selectedChannel}?hours=${hours}`)
});

// For endpoints that need channel as query param:
apiClient.get(`/commercials?channel=${selectedChannel}`)
```

### 5.6 Monitoring

Each Channel VPS should report to the existing Grafana/Loki monitoring server (194.247.182.159):

- Promtail on each VPS ships logs to Loki with `channel=N` label
- Grafana dashboards filtered by channel
- stream-probe on monitoring server pings each channel's health endpoint

## 6. Migration Plan: Channel 1

Channel 1 (194.247.182.249) needs minor updates to work within the new architecture:

1. **Playlist generator**: Parameterize routes (read CHANNEL_ID from env, default to 1)
2. **Ecosystem config**: Remove `-ch1` suffix from process names
3. **CDN transition**: Fully migrate from `cdn.niteride.fm` to `cdn-ch1.niteride.fm` (validates channel infra before Ch2)
4. **.env**: Add `CHANNEL_ID=1` explicitly
5. **Nginx**: Update `server_name` to include `cdn-ch1.niteride.fm`

These changes are backward-compatible and can be deployed before Channel 2 exists.

## 7. Implementation Order

### Phase 0: S3 Storage Migration (prerequisite - shared library decided)
- Add S3 SDK to admin-service, modify `library-upload.js` to upload processed segments to S3 after local FFmpeg
- Build `storage-service` from scratch (does not exist yet) for segment prefetch from S3 to local cache
- Consolidate two upload paths: `library-upload.js` (inline FFmpeg) and `content-segmenter` (batch) should use consistent pipeline
- Migrate existing segments from `/var/www/hls/segments/` to S3 bucket
- Update stitcher-engine URL building to work with S3-backed segments
- Estimated effort: 8-13 days

### Phase 1: Foundation (no user-visible changes)
- Add Channel Registry table to Web Server database
- Update Web Server nginx admin proxy: add `map $arg_channel` routing (Option A)
- Parameterize playlist-generator routes (CHANNEL_ID env var)
- Parameterize stream-guard PLAYLIST_URL (env var)
- Add channel scoping to stream-monitor Redis key (`stream:health:monitor:ch${channelId}`)
- Parameterize ecosystem.config.js (remove `-ch1` suffix, add CHANNEL_ID env)
- Audit admin-service for hardcoded channelId=1
- Add channel filtering to commercials API (wire up `ChannelCommercials` table)
- Add `selectedChannel` state to CommercialPage (DiagnosticsPage is intentionally global, LibraryPage/ShowsPage don't exist)
- Create docker-compose.yml for Redis/Postgres/pgAdmin (currently managed externally, not in repo)
- Document RTMP nginx config (currently not in repo)
- Create provisioning script in niteridefm-infra

### Phase 2: Chat + Frontend prep
- Add channel_id to chat tables (migration on chat-service's Web Server database)
- Update chat-service TypeScript code for channel-scoped Socket.IO rooms (replace global `io.emit()` with `io.to(room).emit()`)
- Update frontend admin API calls to pass channelId explicitly (not interceptor)
- Add ChannelSwitcher to public stream page (replace hardcoded `ch1` in HLS URL)
- Update useChat hook to pass channelId on socket connection + room switching
- Remove orphaned `streaming-core/src/services/chat-socket.js`

### Phase 3: Channel 2 VPS
- Provision new VPS
- Deploy full PM2 stack with CHANNEL_ID=2
- Configure CDN subdomain
- Register in Channel Registry
- Test end-to-end

### Phase 4: Channel 1 CDN migration
- Add cdn-ch1.niteride.fm as CDN alias
- Update frontend to use new CDN URL pattern
- Deprecate old cdn.niteride.fm (or keep as alias for ch1)

### Phase 5: Go live
- Activate Channel 2 in Channel Registry
- Monitor and validate

## 8. Open Questions

All questions resolved as of 2026-02-11.

| # | Question | Decision | Notes |
|---|----------|----------|-------|
| 1 | Shared library vs per-VPS | **Shared via S3** | Shows may play across channels. S3 migration required (est. 8-13 days). |
| 2 | Commercials per channel | **Per-channel assignments** | Wire up `ChannelCommercials` junction table. |
| 3 | Stingers per channel | **Per-program** (no channel scoping needed) | Stingers attach to programs via `ShowStingerPairAssignment`. Programs are assigned to channels, so stingers follow naturally. No additional channel scoping required. |
| 4 | Channel 1 CDN domain | **Fully migrate** to `cdn-ch1.niteride.fm` | Enables testing channel infra on Ch1 before spinning up Ch2. |
| 5 | VPS provider | **Same provider** | User will provide IP + root credentials for initial setup. |
| 6 | Content for Channel 2 | **Empty at launch** | Content added via admin panel after provisioning. No seed data for shows/episodes. |
| 7 | Chat bans | **Global** across all channels | A ban in any channel applies everywhere. `chat_bans.channel_id` stays NULL for global bans. |
| 8 | Chat emotes | **Global** across all channels | All channels share the same emote set. No `channel_id` needed on emotes. |
| 9 | Chat database location | **Web Server local Postgres** | Confirmed from `.env.example` - `localhost:5432`. Centralized naturally. |
| 10 | Guide service | **Keep it** | Connects remotely to Stream Server DB, read-only EPG, already has `:channelId` route. |

## Appendix A: Validation Findings (2026-02-10)

The following issues were identified during a live server inspection and codebase validation pass. All corrections have been applied to the sections above.

| # | Finding | Severity | Section Updated |
|---|---------|----------|-----------------|
| 1 | Web Server (194.247.183.37) IS the existing API gateway - nginx already proxies admin routes to stream server. Design initially described this as building from scratch. | High | 5.1 |
| 2 | Chat service is TypeScript in `niteridefm-fe/backend/services/chat-service/`, NOT `chat-socket.js` in streaming-core. Runs on Web Server port 4000. | High | 2, 5.3 |
| 3 | No S3 storage exists. Library uploads use multer to local filesystem (`/opt/niteride/uploads`). Shared library requires S3 migration. | Critical | 3, 5.2 |
| 4 | Commercials API has zero channel filtering. `ChannelCommercials` junction table is empty and unused. | Medium | 5.2 |
| 5 | `guide-service` still running on Web Server port 3105 despite ecosystem.config.js comment claiming decommission. | Low | 5.1, 8 |
| 6 | Admin frontend pages (DiagnosticsPage, CommercialPage, LibraryPage) don't pass channelId. Only SchedulePage has the pattern. | Medium | 5.2 |
| 7 | Web Server runs 4 PM2 services: niteride-backend (3000), identity-service (3001), guide-service (3105), chat-service (4000). | Info | 5.1 |
| 8 | Stream server nginx has a stale/redundant `niteride.fm` config from before the architecture was split. | Low | - |

## Appendix B: Deep-Dive Findings (2026-02-11)

4 parallel code-explorer agents performed full codebase analysis against ARCHITECTURE.md.

### New Discoveries

| # | Finding | Impact | Resolution |
|---|---------|--------|------------|
| 9 | `storage-service` does NOT exist in codebase - placeholder in ecosystem.config.js | Design referenced it as existing service | Removed from VPS template. Must be built if S3 migration pursued. |
| 10 | `live-controller` does NOT exist in codebase - placeholder in ecosystem.config.js | Design listed it in VPS template | Removed from VPS template. |
| 11 | `tusd` (resumable uploads, port 8444) NOT implemented | Design may have assumed it existed | Noted as non-existent. |
| 12 | Two separate upload/segmentation paths: `library-upload.js` (inline FFmpeg) and `content-segmenter` (batch multi-quality) | Potential inconsistency in segment quality/format | Documented. Consider consolidating to single path. |
| 13 | Chat has ZERO `channel_id` fields across all 4 models. Uses global `io.emit()`, no Socket.IO rooms at all. | Deeper than "no channel scoping" - no room infrastructure exists | Updated chat section with precise scope of work. |
| 14 | `guide-service` connects REMOTELY to Stream Server DB via `GUIDE_DATABASE_URL` | Resolves open question #3 - keep it, already works | Resolved in Open Questions. |
| 15 | Chat-service connects to Web Server's local Postgres (confirmed from `.env.example`) | Resolves open question #9 - centralized naturally | Resolved in Open Questions. |
| 16 | `niteride-backend` already uses axios proxying at `channels.js:375-466` | Proves proxy pattern exists, but nginx map is better for MVP | Updated API Gateway to recommend nginx map. |
| 17 | Web Server and Stream Server have SEPARATE PostgreSQL instances (not shared) | Critical for understanding data flow | Added to architecture context. |
| 18 | 10GB file upload support via nginx `proxy_request_buffering off` | Node.js proxy would need streaming, risk of memory issues | Drives nginx map recommendation over Node.js proxy. |
| 19 | `PublicStreamPage.tsx` HLS URL hardcoded: `` `${CDN_URL}/stream/ch1/playlist.m3u8` `` | Must be parameterized for channel switching | Updated frontend player section. |
| 20 | Player is Vidstack Media Player (not raw hls.js) | Affects how we implement channel switching | Updated frontend player section. |
| 21 | `LibraryPage.tsx` and `ShowsPage.tsx` DO NOT EXIST as standalone pages | Design referenced them as needing channel selectors | Corrected in admin pages audit. |
| 22 | `DiagnosticsPage.tsx` is system-wide by design - no channel selector needed | Previously listed as needing channel awareness | Corrected in admin pages audit. |
| 23 | `StreamsPage.tsx` already partially channel-aware (has selector + `selectedChannel` state) | Better than initially assessed | Updated in admin pages audit. |
| 24 | Legacy `chat-socket.js` in streaming-core is orphaned - never imported anywhere | Safe to delete, reduces confusion | Added cleanup to Phase 2. |
| 25 | No `docker-compose.yml` in repo - containers managed externally | VPS template needs one for reproducibility | Added to Phase 1 tasks. |
| 26 | No RTMP nginx config in repo | Must be documented for VPS template | Added to Phase 1 tasks. |
| 27 | `stream-monitor` Redis key `stream:health:monitor` lacks channel scoping | Would collide in shared Redis (though each VPS has own Redis) | Added fix to Phase 1 for correctness. |
| 28 | Timeline segment URLs are relative (`/segments/...`), not absolute | Good for portability across CDN configs | Noted in Content Services section. |
| 29 | Databases are separate: Web Server has own Postgres, Stream Server has own Postgres | guide-service bridges them via remote connection | Added to architecture context. |

### Channel-Readiness Scorecard

| Component | Status | Notes |
|-----------|--------|-------|
| Database schema | READY | Fully channel-scoped with FKs and indexes |
| Scheduler/Stitcher | READY | channelId parameter, loops active channels |
| RTMP Receiver | READY | Multi-channel auth via stream key |
| Admin Service API | READY | Channel-aware routes |
| CDN Prewarmer | READY | Reads CHANNEL_ID env |
| Stream Monitor | NEEDS FIX | Redis key needs channel scoping |
| Playlist Generator | BLOCKED | Hardcoded /ch1/ routes |
| Stream Guard | BLOCKED | Hardcoded ch1 URL |
| Nginx CDN Config | BLOCKED | Single channel only |
| Content Storage | BLOCKED | Local filesystem only (if shared library needed) |
| Chat Service | BLOCKED | No channel_id in any model, no Socket.IO rooms |
| Frontend Player | BLOCKED | Hardcoded ch1 HLS URL |
| Frontend Admin | PARTIAL | Only SchedulePage + StreamsPage are channel-aware |
