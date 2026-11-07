# Modules

A module is a `.js` file (CommonJS). Add it in the app: any tab → account button (top right) → **Add Module**, or the button on an empty Home tab.

Every function is optional and may be `async`. `fetch(url, {method, headers, body})` and `setTimeout` are available.

```js
module.exports = {
  name: "My Source",
  home:   async () => [{ title: "Top", items: [song] }],   // Home tab
  new:    async () => [{ title: "Fresh", items: [song] }],   // New tab
  radio:  async () => [{ title: "Chill", items: [song] }],   // Radio tab
  search: async (query) => [song],                           // Search tab
  resolve:  async (song) => "https://…/audio.mp3",           // audio URL, needed if song.url is missing/expiring
  download: async (song) => "https://…/audio.mp3",           // download URL (falls back to resolve, then song.url)
  lyrics:   async (song) => "[00:12.30]line one\n[00:15.00]line two"  // LRC text, or [{ time, text }]
};
// song = { id, title, artist, album, artwork, url, duration, trackNumber, disc, year, albumId, artistId }
```

`id` and `title` are the only required song fields. Albums and artists are built from `album`/`artist`.
Downloads use the normal AmpFin download button on albums and playlists.
See `modules/example-itunes.js` for a working example.
