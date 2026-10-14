import { AudioPlayer } from './audio.js';
import { PadGesture } from './gestures.js';

const $ = id => document.getElementById(id);
const storageKey = 'breakwater.web.v1';
let saved = {};
try { saved = JSON.parse(localStorage.getItem(storageKey)) || {}; } catch { /* Private browsing or invalid saved data. */ }
const bounded = (value, fallback, min, max) => Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;
let tempo = bounded(saved.tempo, 120, 30, 300);
let volume = bounded(saved.volume, .8, 0, 1);
const disabled = new Set(Array.isArray(saved.disabled) ? saved.disabled.filter(Number.isInteger) : []);
let songs = [], samples = [], song = null;
let editing = false, loading = false, desired = [], request = 0;
let state = { playing: false, active: null, beat: 0, progress: 0, pending: false, queue: [] };
let pads = new Map();
let lastAnnouncement = '';
const gesture = new PadGesture();
const scrollTouches = new Map();
const taps = [];

function persist() {
  try { localStorage.setItem(storageKey, JSON.stringify({ tempo, volume, song: song?.id, disabled: [...disabled] })); }
  catch { announce('Browser storage is unavailable. Pad exclusions will last for this visit.'); }
}
function announce(text) { if (text !== lastAnnouncement) { $('announcer').textContent = text; lastAnnouncement = text; } }
function notice(text = '', retry = false, progress = false) {
  $('notice').hidden = !text;
  $('notice-text').textContent = text;
  $('retry').hidden = !retry;
  $('loading-progress').hidden = !progress;
}

const audio = new AudioPlayer(next => {
  state = next;
  paint();
}, (done, total) => {
  if (!loading) return;
  $('loading-progress').max = total;
  $('loading-progress').value = done;
  notice(`Loading loops · ${done} / ${total}`, false, true);
}, message => {
  request++;
  loading = false;
  desired = [];
  state = { ...state, playing: false, pending: false };
  notice(message || 'Audio paused by your browser. Press Play to continue.');
  paint();
});
audio.setTempo(tempo);
audio.setVolume(volume);
$('tempo').value = tempo;
$('volume').value = volume;

function waveform(values) {
  const upper = values.map((value, i) => `${i * 100 / (values.length - 1)},${50 - value * 47}`);
  const lower = values.map((value, i) => `${i * 100 / (values.length - 1)},${50 + value * 47}`).reverse();
  return `M${upper.join(' L')} L${lower.join(' L')} Z`;
}

function showSong(id) {
  song = songs.find(item => item.id === id) || songs[0];
  $('song').value = song.id;
  $('artist').textContent = song.artist;
  $('source-bpm').textContent = `≈${song.sourceBPM}`;
  $('source-bpm').title = song.sourceBPMRange ? `Loop range: ${song.sourceBPMRange.join('–')} BPM. ${song.timingNote || ''}` : 'Approximate source tempo';
  $('grid').setAttribute('aria-label', `${song.name} loop pads`);
  gesture.cancel();
  scrollTouches.clear();
  pads = new Map();
  const fragment = document.createDocumentFragment();
  for (const sample of song.loops) {
    const pad = document.createElement('button');
    pad.type = 'button';
    pad.className = 'pad';
    pad.dataset.id = sample.id;
    pad.title = `${song.name} · ${sample.sourceStart}–${sample.sourceEnd} · ${sample.bpm.toFixed(1)} BPM`;
    // Numeric waveform data and metadata come from the bundled catalog.
    pad.innerHTML = `<span class="sweep"></span><span class="pad-header"><span class="pad-number">${String(sample.number).padStart(2, '0')}</span><span class="pad-bars">${sample.bars} ${sample.bars === 1 ? 'bar' : 'bars'}</span></span><svg class="waveform" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><path d="${waveform(sample.waveform)}"/></svg><span class="pad-status"></span>`;
    pads.set(sample.id, { element: pad, status: pad.querySelector('.pad-status'), sample });
    fragment.append(pad);
  }
  $('grid').replaceChildren(fragment);
  layout();
  paint();
  persist();
}

function layout() {
  const grid = $('grid');
  const width = grid.clientWidth;
  const columns = width < 460 ? 3 : width < 650 ? 4 : width > grid.clientHeight * 1.12 ? 6 : 5;
  grid.style.setProperty('--columns', columns);
  grid.style.setProperty('--rows', Math.ceil((song?.loops.length || 30) / columns));
  grid.classList.toggle('scrollable', grid.scrollHeight > grid.clientHeight + 1);
  updateHint();
}
new ResizeObserver(layout).observe($('grid'));

function updateHint() {
  $('hint').textContent = editing ? 'Tap pads to exclude or restore them. Changes are saved on this browser.'
    : $('grid').classList.contains('scrollable') ? 'Tap a pad to play. Swipe to browse; hold several pads to make a cycle.'
    : 'Tap a pad to play. Drag across pads, Shift-click, or hold several to make a cycle.';
}

function paint() {
  const queue = loading ? desired : state.queue;
  for (const [id, { element, status, sample }] of pads) {
    const excluded = disabled.has(id);
    const playing = state.playing && state.active === id;
    const order = queue.indexOf(id);
    const pending = (state.pending || loading) && order >= 0;
    element.classList.toggle('playing', playing);
    element.classList.toggle('queued', order >= 0 && !playing);
    element.classList.toggle('pending', pending);
    element.classList.toggle('excluded', excluded);
    element.setAttribute('aria-disabled', String(excluded && !editing));
    element.setAttribute('aria-pressed', String(playing));
    if (playing) element.style.setProperty('--progress', state.progress);
    let label = '';
    if (editing) label = excluded ? 'RESTORE' : 'EXCLUDE';
    else if (excluded) label = 'EXCLUDED';
    else if (loading && order >= 0) label = `${order + 1} · LOADING`;
    else if (playing) label = pending ? `${order + 1} · NEXT BAR` : `PLAYING${order >= 0 && queue.length > 1 ? ` · ${order + 1}` : ''}`;
    else if (order >= 0 && state.playing) label = `${order + 1} · ${pending ? 'NEXT BAR' : 'CYCLE'}`;
    status.textContent = label;
    element.setAttribute('aria-label', `Loop ${sample.number}, ${sample.bars} ${sample.bars === 1 ? 'bar' : 'bars'}${label ? `, ${label.toLowerCase()}` : ''}`);
  }
  const playing = state.playing;
  $('transport').classList.toggle('running', playing || loading);
  $('transport-label').textContent = playing || loading ? 'Stop' : 'Play';
  $('transport').setAttribute('aria-label', playing || loading ? 'Stop' : 'Play');
  $('transport-icon').setAttribute('d', playing || loading ? 'M5 5H19V19H5Z' : 'M7 4 20 12 7 20Z');
  const current = samples.find(sample => sample.id === state.active);
  $('playing-label').textContent = playing && current ? `${current.songName} · ${String(current.number).padStart(2, '0')}` : loading ? 'Loading samples' : 'Pick a loop';
  $('playing-label').title = $('playing-label').textContent;
  [...document.querySelectorAll('.beat-dots i')].forEach((dot, index) => dot.classList.toggle('on', playing && Math.floor(state.beat) % 4 === index));
  if (playing && current) announce(`Playing ${current.songName}, loop ${current.number}`);
}

async function select(ids) {
  desired = [...new Set(ids)].filter(id => !disabled.has(id));
  if (!desired.length) return;
  const attempt = ++request;
  const selected = samples.filter(sample => desired.includes(sample.id));
  loading = selected.some(sample => !audio.loaded.has(sample.id));
  paint();
  try {
    await audio.unlock();
    await audio.load(selected, disabled, (done, total) => {
      if (attempt !== request || !loading) return;
      $('loading-progress').max = total;
      $('loading-progress').value = done;
      notice(`Loading loops · ${done} / ${total}`, false, true);
    });
    if (attempt !== request) return;
    loading = false;
    desired = desired.filter(id => !disabled.has(id));
    if (desired.length) {
      audio.queue(desired);
      notice();
      announce(state.playing ? `Queued ${desired.length} loop${desired.length === 1 ? '' : 's'} for the next bar` : 'Starting playback');
    }
    paint();
  } catch (error) {
    if (attempt !== request) return;
    loading = false;
    notice(error.message, true);
    paint();
  }
}

function stop() {
  request++;
  loading = false;
  desired = [];
  audio.stop();
  state = { ...state, playing: false, pending: false };
  gesture.cancel();
  scrollTouches.clear();
  notice();
  paint();
  announce('Stopped');
}
function toggleDisabled(id) {
  if (disabled.has(id)) disabled.delete(id); else disabled.add(id);
  audio.enable(id, !disabled.has(id));
  desired = desired.filter(item => !disabled.has(item));
  persist();
  paint();
}
function padAt(target) { return target instanceof Element ? target.closest('.pad') : null; }
$('grid').addEventListener('pointerdown', event => {
  const pad = padAt(event.target);
  if (!pad || (event.pointerType === 'mouse' && event.button !== 0)) return;
  const id = Number(pad.dataset.id);
  // On small screens, leave vertical touch scrolling to the browser. A tap
  // launches on release; a drag scrolls without accidentally launching pads.
  if (event.pointerType === 'touch' && $('grid').classList.contains('scrollable')) {
    scrollTouches.set(event.pointerId, { id, x: event.clientX, y: event.clientY });
    if (!editing && !disabled.has(id)) gesture.begin(event.pointerId, id);
    return;
  }
  event.preventDefault();
  pad.focus({ preventScroll: true });
  if (editing) { toggleDisabled(id); return; }
  if (disabled.has(id)) return;
  pad.setPointerCapture(event.pointerId);
  select(gesture.begin(event.pointerId, id, event.shiftKey, desired.length ? desired : state.queue));
});
$('grid').addEventListener('pointermove', event => {
  const touch = scrollTouches.get(event.pointerId);
  if (touch) {
    if (Math.hypot(event.clientX - touch.x, event.clientY - touch.y) > 8) {
      scrollTouches.delete(event.pointerId);
      gesture.end(event.pointerId);
    }
    return;
  }
  if (editing || !gesture.held.has(event.pointerId)) return;
  const pad = padAt(document.elementFromPoint(event.clientX, event.clientY));
  if (!pad || !pad.closest('#grid') || disabled.has(Number(pad.dataset.id))) return;
  const ids = gesture.move(event.pointerId, Number(pad.dataset.id));
  if (ids) select(ids);
});
for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
  $('grid').addEventListener(type, event => {
    const touch = scrollTouches.get(event.pointerId);
    if (type === 'pointerup' && touch) {
      if (editing) toggleDisabled(touch.id);
      else if (!disabled.has(touch.id)) select([...gesture.order]);
    }
    scrollTouches.delete(event.pointerId);
    gesture.end(event.pointerId);
  });
}
window.addEventListener('blur', () => { gesture.cancel(); scrollTouches.clear(); });
$('grid').addEventListener('contextmenu', event => event.preventDefault());
$('grid').addEventListener('click', event => {
  // Native keyboard and assistive-technology activation produces detail 0.
  if (event.detail !== 0) return;
  const pad = padAt(event.target);
  if (!pad) return;
  const id = Number(pad.dataset.id);
  if (editing) toggleDisabled(id);
  else if (!disabled.has(id)) select(event.shiftKey ? [...(desired.length ? desired : state.queue), id] : [id]);
});
$('grid').addEventListener('keydown', event => {
  const offsets = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -Number($('grid').style.getPropertyValue('--columns')), ArrowDown: Number($('grid').style.getPropertyValue('--columns')) };
  if (!(event.key in offsets)) return;
  const items = [...pads.values()].map(item => item.element);
  const index = items.indexOf(event.target);
  if (index < 0) return;
  event.preventDefault();
  items[Math.min(items.length - 1, Math.max(0, index + offsets[event.key]))].focus();
});

$('song').addEventListener('change', () => showSong($('song').value));
$('transport').addEventListener('click', () => {
  if (state.playing || loading) { stop(); return; }
  const cycle = state.queue.filter(id => !disabled.has(id));
  const first = song.loops.find(sample => !disabled.has(sample.id));
  if (cycle.length) select(cycle);
  else if (first) select([first.id]);
  else notice('Every pad on this page is excluded. Use Edit pads to restore a loop.');
});
$('retry').addEventListener('click', () => {
  if (!songs.length) loadCatalog();
  else select(desired.length ? desired : [song.loops.find(sample => !disabled.has(sample.id))?.id].filter(Number.isInteger));
});
$('edit').addEventListener('click', () => {
  editing = !editing;
  gesture.cancel();
  scrollTouches.clear();
  $('edit').textContent = editing ? 'Done' : 'Edit pads';
  $('edit').setAttribute('aria-pressed', String(editing));
  $('grid').classList.toggle('editing', editing);
  updateHint();
  paint();
});
function setTempo(value) {
  tempo = Math.round(bounded(value, tempo, 30, 300) * 10) / 10;
  $('tempo').value = tempo;
  audio.setTempo(tempo);
  persist();
}
$('tempo').addEventListener('change', () => setTempo($('tempo').valueAsNumber));
$('tempo').addEventListener('keydown', event => { if (event.key === 'Enter') { setTempo($('tempo').valueAsNumber); $('tempo').blur(); } });
$('source-tempo').addEventListener('click', () => { if (song) setTempo(song.sourceBPM); });
$('tap-tempo').addEventListener('click', () => {
  const now = performance.now();
  if (taps.length && now - taps.at(-1) > 2000) taps.length = 0;
  taps.push(now);
  if (taps.length > 6) taps.shift();
  if (taps.length > 1) setTempo(60000 * (taps.length - 1) / (now - taps[0]));
  announce(taps.length > 1 ? `Tempo ${tempo} BPM` : 'Tap again to set tempo');
});
$('volume').addEventListener('input', () => { volume = Number($('volume').value); audio.setVolume(volume); persist(); });
document.addEventListener('keydown', event => {
  if (event.code === 'Space' && !['INPUT', 'SELECT', 'BUTTON', 'TEXTAREA'].includes(event.target.tagName)) {
    event.preventDefault();
    $('transport').click();
  }
});
window.addEventListener('pagehide', stop);

async function loadCatalog() {
  notice();
  try {
    const response = await fetch(new URL('./Samples/catalog.json', import.meta.url));
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const catalog = await response.json();
    if (!Array.isArray(catalog) || !catalog.length || catalog.some(item => !Array.isArray(item.loops) || !item.loops.length)) throw new Error('Empty sample catalog');
    songs = catalog;
    samples = songs.flatMap(item => item.loops.map(sample => ({ ...sample, songName: item.name })));
    $('song').replaceChildren(...songs.map(item => new Option(`${item.name}`, item.id)));
    $('song').disabled = $('transport').disabled = $('edit').disabled = false;
    $('grid').setAttribute('aria-busy', 'false');
    showSong(saved.song);
  } catch (error) {
    $('grid').setAttribute('aria-busy', 'false');
    notice(`The sample library couldn't load. Check your connection and retry. (${error.message})`, true);
  }
}
loadCatalog();
