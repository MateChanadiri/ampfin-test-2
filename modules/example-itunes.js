// Demo module: iTunes public search API (30-second previews). Use it to test the pipeline.
// Contract: every function is optional and may be async. Return songs as
// { id, title, artist, album, artwork, url, duration }.
// home/new/radio return shelves: [{ title, items: [song] }]. search returns [song].
// Optional: resolve(song) -> url string, download(song) -> url string (falls back to resolve, then song.url).

function toSong(t) {
  return {
    id: t.trackId,
    title: t.trackName,
    artist: t.artistName,
    album: t.collectionName,
    artwork: (t.artworkUrl100 || '').replace('100x100', '600x600'),
    url: t.previewUrl
  };
}

async function find(term, limit) {
  const r = await fetch('https://itunes.apple.com/search?media=music&entity=song&limit=' + (limit || 25) + '&term=' + encodeURIComponent(term));
  const j = await r.json();
  return j.results.filter(function (t) { return t.previewUrl; }).map(toSong);
}

async function shelves(terms) {
  const out = [];
  for (const t of terms) out.push({ title: t, items: await find(t, 15) });
  return out;
}

module.exports = {
  name: 'iTunes Previews (demo)',
  home: function () { return shelves(['Top Hits', 'Pop', 'Hip-Hop']); },
  new: function () { return shelves(['New Music Friday', 'Fresh Finds']); },
  radio: function () { return shelves(['Chill', 'Workout', 'Focus']); },
  search: function (q) { return find(q, 30); }
};
