import { AudioPlayer } from './audio.js';
import { assetBase, assetURL } from './assets.js';
import { filterFromPosition, positionFromFilter, waveformBars } from './clip-controls.js';

const $ = id => document.getElementById(id);
const storageKey = 'breakwater.web.v1';
let saved = {};
try { saved = JSON.parse(localStorage.getItem(storageKey)) || {}; } catch { /* Private browsing or invalid saved data. */ }
const bounded = (value, fallback, min, max) => Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;
let tempo = bounded(saved.tempo, 120, 30, 300);
let volume = bounded(saved.volume, .8, 0, 1);
const disabled = new Set(Array.isArray(saved.disabled) ? saved.disabled.filter(Number.isInteger) : []);
const partMasks = saved.partMasks && typeof saved.partMasks === 'object' ? saved.partMasks : {};
let filterMode = 0, filterHz = 1200;
const partFailures = new Map();
let songs = [], samples = [], song = null;
let editing = false, loading = false, request = 0;
let state = { playing: false, active: null, activeLoops: [], activeTokens: [], beat: 0, progress: 0, pending: false, queue: [] };
let arrangement = [], selectedToken = null, nextToken = 1, pointer = null;
let pads = new Map();
let lastAnnouncement = '';
const taps = [];

function persist() {
  try { localStorage.setItem(storageKey, JSON.stringify({ tempo, volume, song: song?.id, disabled: [...disabled], partMasks })); }
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
  prepareUpcoming();
}, (done, total) => {
  if (!loading) return;
  $('loading-progress').max = total;
  $('loading-progress').value = done;
  notice(`Loading loops · ${done} / ${total}`, false, true);
}, message => {
  request++;
  loading = false;
  state = { ...state, playing: false, pending: false };
  notice(message || 'Audio paused by your browser. Press Play to continue.');
  paint();
});
audio.setTempo(tempo);
audio.setVolume(volume);
$('tempo').value = tempo;
$('volume').value = volume;

function waveform(values, middle = 50, scale = 47) {
  const upper = values.map((value, i) => `${i * 100 / (values.length - 1)},${middle - value * scale}`);
  const lower = values.map((value, i) => `${i * 100 / (values.length - 1)},${middle + value * scale}`).reverse();
  return `M${upper.join(' L')} L${lower.join(' L')} Z`;
}

function showSong(id) {
  song = songs.find(item => item.id === id) || songs[0];
  if (!song) return;
  $('song-name').textContent = song.name;
  $('artist').textContent = song.artist;
  $('source-bpm').textContent = `≈${song.sourceBPM}`;
  $('source-bpm').title = song.sourceBPMRange ? `Loop range: ${song.sourceBPMRange.join('–')} BPM. ${song.timingNote || ''}` : 'Approximate source tempo';
  document.querySelectorAll('.folder').forEach(folder => folder.classList.toggle('active', folder.dataset.song === song.id));
  persist();
}
function buildLibrary() {
  pads = new Map();
  const fragment = document.createDocumentFragment();
  for (const source of songs) {
    const folder = document.createElement('details'); folder.className = 'folder'; folder.dataset.song = source.id;
    const summary = document.createElement('summary');
    const title = document.createElement('span'); title.className = 'folder-title'; title.textContent = source.name;
    const bpm = document.createElement('span'); bpm.className = 'folder-bpm'; bpm.textContent = `≈${source.sourceBPM} BPM`;
    summary.append(title, bpm); folder.append(summary);
    folder.addEventListener('toggle', () => { if (folder.open) showSong(source.id); });
    const list = document.createElement('div'); list.className = 'folder-loops';
    for (const sample of source.loops) {
      const pad = document.createElement('button'); pad.type = 'button'; pad.className = 'pad'; pad.dataset.id = sample.id;
      pad.setAttribute('aria-describedby', 'keyboard-help');
      pad.title = `${source.name} · ${sample.sourceStart}–${sample.sourceEnd} · ${sample.bpm.toFixed(1)} BPM`;
      pad.innerHTML = `<span class="pad-number">${String(sample.number).padStart(2, '0')}</span><svg class="waveform" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><path d="${waveform(sample.waveform)}"/></svg><span class="pad-bars">${sample.bars} ${sample.bars === 1 ? 'bar' : 'bars'}</span><span class="pad-status"></span>`;
      pads.set(sample.id, { element: pad, status: pad.querySelector('.pad-status'), sample }); list.append(pad);
    }
    folder.append(list); fragment.append(folder);
    if (source.id === (saved.song || songs[0].id)) folder.open = true;
  }
  $('grid').replaceChildren(fragment);
  showSong(saved.song); paintLibrary(); paint();
}
function layout() {}

function songMask(item = song) { return (Number.isInteger(partMasks[item?.id]) ? partMasks[item.id] : 15) & 15; }
function allClips() { return arrangement.flat(); }
function selectedClip() { return allClips().find(clip => clip.token === selectedToken); }
function sampleFor(id) { return samples.find(sample => sample.id === id); }
function formatHz(hz) { return hz >= 1000 ? `${(hz / 1000).toFixed(1)} kHz` : `${Math.round(hz)} Hz`; }
function sliderPosition(hz) { return Math.round(1000 * Math.log(hz / 40) / Math.log(18000 / 40)); }
function renderPartStatus() {
  const clip = selectedClip();
  const failure = clip && partFailures.get(clip.id);
  let message = '';
  if (failure && clip.mask !== 15) message = `Parts could not load (${failure}). The full mix remains available.`;
  else if (clip && clip.mask !== 15 && state.playing && audio.partInFlight.has(clip.id)) {
    message = clip.mask === 0 ? 'Preparing parts · all layers are off' : 'Preparing parts · full mix plays until ready';
  }
  $('part-message').textContent = message;
  $('part-notice').hidden = !message;
  $('retry-parts').hidden = !failure || clip.mask === 15;
}

function selectClip(token) {
  selectedToken = token;
  document.querySelectorAll('.clip-row').forEach(row => {
    const selected = Number(row.dataset.token) === token;
    row.classList.toggle('selected', selected);
    row.querySelector('[data-select]')?.setAttribute('aria-pressed', String(selected));
  });
  renderPartStatus();
}

function prepareUpcoming() {
  if (!state.playing) return;
  const index = arrangement.findIndex(step => step.some(clip => (state.activeTokens || []).includes(clip.token)));
  const upcoming = [...(arrangement[index] || []), ...(arrangement[(index + 1) % arrangement.length] || []), ...(selectedClip() ? [selectedClip()] : [])];
  const ids = [...new Set(upcoming.filter(clip => clip.mask !== 15).map(clip => clip.id))];
  audio.pinParts([...new Set([...(state.activeLoops || []), ...ids])]);
  for (const id of ids) {
    const sample = sampleFor(id);
    if (!sample || !audio.loaded.has(id) || audio.partCache.has(id) || audio.partInFlight.has(id) || partFailures.has(id)) continue;
    audio.loadParts(sample).then(() => { renderPartStatus(); }).catch(error => {
      partFailures.set(id, error.message); renderPartStatus();
    });
  }
  renderPartStatus();
}

function updateHint() {
  $('hint').textContent = editing ? 'Select a loop in the library to exclude or restore it. Changes are saved.'
    : 'Drop at a step edge to insert; drop beneath a clip to layer. Each clip has its own mix controls.';
}
let zoom = 1;
function applyZoom() {
  $('arrangement-items').style.setProperty('--zoom', zoom);
}
new ResizeObserver(applyZoom).observe($('arrangement-items'));

function renderClipWaveform(svg, sample, clip, beats) {
  const bars = waveformBars(sample.waveform, sample.parts?.waveforms, clip.mask);
  const paths = (key) => bars.map((bar, index) => {
    const amplitude = bar[key] * 43, x = (index + 0.5) * 100 / bars.length;
    return `M${x.toFixed(2)} ${(50 - amplitude).toFixed(2)} V${(50 + amplitude).toFixed(2)}`;
  }).join(' ');
  const fraction = (sample.beats || 4) / beats;
  svg.innerHTML = Array.from({length: Math.ceil(1 / fraction)}, (_, repeat) =>
    `<g transform="translate(${repeat * fraction * 100} 0) scale(${fraction} 1)"><path class="wave-ghost" d="${paths('full')}"/><path class="wave-enabled" d="${paths('enabled')}"/></g>`).join('');
}

function filterLabel(clip) {
  if (clip.filterType === 0) return 'Off';
  return `${clip.filterType === 1 ? 'LPF' : 'HPF'} ${formatHz(clip.filterHz)}`;
}
function updateClipFilterUI(row, clip) {
  const input = row.querySelector('[data-filter]'), value = filterLabel(clip);
  input.value = Math.round(positionFromFilter(clip.filterType, clip.filterHz) * 100);
  input.setAttribute('aria-valuetext', value);
  row.querySelector('.filter-value').textContent = clip.filterType ? value.replace('F ', ' ') : 'OFF';
  row.querySelector('.dial-pointer').style.transform = `rotate(${Number(input.value) * 1.35}deg)`;
}
function updateClipPartsUI(row, clip, sample, beats) {
  row.querySelectorAll('[data-part]').forEach(button => button.setAttribute('aria-pressed', String(!!(clip.mask & (1 << Number(button.dataset.part))))));
  const all = row.querySelector('[data-parts-all]');
  all.textContent = clip.mask === 15 ? 'ALL OFF' : 'ALL ON';
  all.setAttribute('aria-label', `${clip.mask === 15 ? 'Mute' : 'Enable'} all parts for ${sample.songName}, loop ${sample.number}`);
  renderClipWaveform(row.querySelector('.clip-waveform'), sample, clip, beats);
}

function paintArrangement() {
  const container = $('arrangement-items'); const content = document.createElement('div'); content.className = 'timeline-content';
  if (arrangement.length) content.style.minWidth = `${arrangement.length * 270 + 76}px`;
  let firstBar = 1;
  function gap(index) {
    const slot = document.createElement('div'); slot.className = 'arrangement-gap'; slot.dataset.index = index;
    slot.setAttribute('aria-hidden', 'true'); slot.textContent = '+'; return slot;
  }
  if (!arrangement.length) {
    const empty = document.createElement('div'); empty.className = 'arrangement-empty'; empty.dataset.index = '0';
    empty.textContent = 'Drag a loop here to start your sequence'; content.append(empty);
  } else arrangement.forEach((step, index) => {
    if (index === 0) content.append(gap(index));
    const beats = Math.max(...step.map(clip => sampleFor(clip.id)?.beats || 4));
    const group = document.createElement('div'); group.className = 'sequence-step'; group.dataset.step = index; group.style.flexGrow = beats;
    const heading = document.createElement('div'); heading.className = 'step-heading';
    heading.textContent = `BAR ${firstBar} · ${beats / 4} ${beats === 4 ? 'BAR' : 'BARS'}`; group.append(heading);
    firstBar += beats / 4;
    for (const clip of step) {
      const sample = sampleFor(clip.id); if (!sample) continue;
      const source = songs.find(item => item.id === sample.songID);
      const labels = source?.partLabels?.length === 4 ? source.partLabels : ['Kick', 'Snare', 'Toms', 'Cymbals'];
      const row = document.createElement('div'); row.className = 'clip-row'; row.dataset.token = clip.token; row.dataset.beats = beats;
      row.classList.toggle('selected', clip.token === selectedToken);
      const display = document.createElement('div'); display.className = 'clip-display';
      const title = document.createElement('div'); title.className = 'clip-title';
      const label = document.createElement('span'); label.className = 'clip-label'; label.textContent = `${String(sample.number).padStart(2, '0')} · ${sample.songName}`;
      const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'clip-remove'; remove.dataset.remove = clip.token;
      remove.setAttribute('aria-label', `Remove ${sample.songName}, loop ${sample.number}, from step ${index + 1}`); remove.textContent = '×';
      title.append(label, remove);
      const choose = document.createElement('button'); choose.type = 'button'; choose.className = 'clip-select'; choose.dataset.select = clip.token;
      choose.setAttribute('aria-pressed', String(clip.token === selectedToken));
      choose.setAttribute('aria-label', `Select ${sample.songName}, loop ${sample.number}, step ${index + 1}`);
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); svg.setAttribute('viewBox', '0 0 100 100'); svg.setAttribute('preserveAspectRatio', 'none'); svg.classList.add('clip-waveform'); svg.setAttribute('aria-hidden', 'true');
      choose.append(svg); display.append(title, choose);
      const controls = document.createElement('div'); controls.className = 'clip-parts'; controls.setAttribute('role', 'group'); controls.setAttribute('aria-label', `Parts for ${sample.songName}, loop ${sample.number}`);
      const all = document.createElement('button'); all.type = 'button'; all.dataset.partsAll = clip.token; all.disabled = !sample.parts; controls.append(all);
      const grid = document.createElement('div'); grid.className = 'clip-parts-grid';
      labels.forEach((name, part) => {
        const button = document.createElement('button'); button.type = 'button'; button.dataset.part = part; button.disabled = !sample.parts;
        button.textContent = name === 'Cymbals' ? 'CYM' : name.toUpperCase();
        button.setAttribute('aria-label', `${name} for ${sample.songName}, loop ${sample.number}, step ${index + 1}`);
        button.title = `${name}: approximate separated layer`; grid.append(button);
      });
      controls.append(grid);
      const filter = document.createElement('div'); filter.className = 'clip-filter';
      const filterTitle = document.createElement('span'); filterTitle.className = 'control-title'; filterTitle.textContent = 'FILTER';
      const dial = document.createElement('div'); dial.className = 'filter-dial';
      dial.innerHTML = '<span class="dial-face" aria-hidden="true"><span class="dial-pointer"></span></span>';
      const filterInput = document.createElement('input'); filterInput.type = 'range'; filterInput.min = '-100'; filterInput.max = '100'; filterInput.step = '1'; filterInput.dataset.filter = clip.token;
      filterInput.setAttribute('aria-label', `Filter for ${sample.songName}, loop ${sample.number}, step ${index + 1}`); filterInput.setAttribute('aria-describedby', 'filter-help');
      dial.append(filterInput);
      const filterValue = document.createElement('span'); filterValue.className = 'filter-value';
      const filterSides = document.createElement('span'); filterSides.className = 'filter-sides'; filterSides.textContent = 'LP · HP';
      filter.append(filterTitle, dial, filterValue, filterSides);
      const level = document.createElement('label'); level.className = 'clip-level';
      const levelLabel = document.createElement('span'); levelLabel.className = 'control-title'; levelLabel.textContent = 'LVL';
      const slider = document.createElement('input'); slider.type = 'range'; slider.min = '0'; slider.max = '100'; slider.step = '1';
      slider.value = Math.round((clip.level ?? 1) * 100); slider.dataset.level = clip.token;
      slider.setAttribute('aria-label', `Level for ${sample.songName}, loop ${sample.number}, step ${index + 1}`);
      const sliderArea = document.createElement('span'); sliderArea.className = 'level-slider'; sliderArea.append(slider);
      const value = document.createElement('output'); value.className = 'clip-level-value'; value.textContent = `${slider.value}%`;
      level.append(levelLabel, sliderArea, value); row.append(display, controls, filter, level); group.append(row);
      updateClipPartsUI(row, clip, sample, beats); updateClipFilterUI(row, clip);
    }
    const target = document.createElement('div'); target.className = 'layer-target'; target.textContent = '+ Drop a layer'; group.append(target);
    content.append(group);
  });
  if (arrangement.length) content.append(gap(arrangement.length));
  container.replaceChildren(content);
  const bars = firstBar - 1, clips = allClips().length;
  $('sequence-detail').textContent = arrangement.length ? `${bars} ${bars === 1 ? 'bar' : 'bars'} · ${clips} ${clips === 1 ? 'clip' : 'clips'}` : 'Drop loops here to build a sequence';
  $('clear-arrangement').disabled = !arrangement.length; applyZoom(); paintArrangementState(); renderPartStatus();
}
function paintArrangementState() {
  const tokens = state.playing ? state.activeTokens || [] : [];
  document.querySelectorAll('.clip-row').forEach(row => {
    const index = tokens.indexOf(Number(row.dataset.token)); row.classList.toggle('active', index >= 0);
    if (index >= 0) row.style.setProperty('--progress', state.activeProgress?.[index] ?? 0);
  });
  document.querySelectorAll('.sequence-step').forEach(group => group.classList.toggle('active', [...group.querySelectorAll('.clip-row')].some(row => tokens.includes(Number(row.dataset.token)))));
}
function paintLibrary() {
  for (const [id, { element, status, sample }] of pads) {
    const excluded = disabled.has(id); element.classList.toggle('excluded', excluded);
    element.setAttribute('aria-disabled', String(excluded && !editing));
    const label = editing ? (excluded ? 'RESTORE' : 'EXCLUDE') : excluded ? 'EXCLUDED' : '';
    status.textContent = label;
    element.setAttribute('aria-label', `${sampleFor(id)?.songName}, loop ${sample.number}, ${sample.bars} ${sample.bars === 1 ? 'bar' : 'bars'}${label ? `, ${label.toLowerCase()}` : ''}`);
  }
}
function paint() {
  const playing = state.playing;
  $('transport').classList.toggle('running', playing || loading);
  $('transport-label').textContent = playing || loading ? 'Stop' : 'Play';
  $('transport').setAttribute('aria-label', playing || loading ? 'Stop' : 'Play');
  $('transport-icon').setAttribute('d', playing || loading ? 'M5 5H19V19H5Z' : 'M7 4 20 12 7 20Z');
  $('nudge-earlier').disabled = $('nudge-later').disabled = !playing || state.active === null;
  const current = samples.find(sample => sample.id === state.active);
  if (playing && current) announce(`Playing ${current.songName}, loop ${current.number}`);
  paintArrangementState();
}

async function submitArrangement(start = true) {
  const clips = arrangement.flatMap((step, index) => step.map(clip => ({ ...clip, step: index })));
  const wasLoading = loading;
  const attempt = ++request;
  if (!clips.length) { loading = false; audio.arrange([]); notice(); paint(); return; }
  if (!start && !state.playing && !wasLoading) { loading = false; paint(); return; }
  const selected = samples.filter(sample => clips.some(clip => clip.id === sample.id));
  audio.pinParts([...(state.activeLoops || []), ...clips.filter(clip => clip.mask !== 15).map(clip => clip.id)]);
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
    audio.arrange(arrangement.flatMap((step, index) => step.map(clip => ({ ...clip, step: index }))).filter(clip => !disabled.has(clip.id)));
    notice();
    announce(state.playing ? 'Sequence update queued for the next bar' : 'Starting playback');
    prepareUpcoming();
    paint();
  } catch (error) {
    if (attempt !== request) return;
    loading = false;
    notice(error.message, true);
    paint();
  }
}

function newClip(id) {
  const sample = sampleFor(id);
  return { id, token: nextToken++, mask: songMask({ id: sample?.songID }), filterType: 0, filterHz: 1200, level: 1 };
}
function addSample(id, index, layer = false, replace = false) {
  if (disabled.has(id) || !sampleFor(id)) return;
  if (!replace && allClips().length >= 64) { notice('The sequence can hold up to 64 samples.'); return; }
  if (layer && arrangement[index]?.length >= 8) { notice('A step can contain up to 8 layers.'); return; }
  const clip = newClip(id);
  if (replace) arrangement = [[clip]];
  else if (layer && arrangement[index]) arrangement[index].push(clip);
  else arrangement.splice(Math.max(0, Math.min(index, arrangement.length)), 0, [clip]);
  selectedToken = clip.token;
  paintArrangement();
  submitArrangement();
}

function stop() {
  request++;
  loading = false;
  audio.stop();
  state = { ...state, playing: false, pending: false };
  clearPointer();
  notice();
  paint();
  announce('Stopped');
}
function toggleDisabled(id) {
  if (disabled.has(id)) disabled.delete(id); else disabled.add(id);
  audio.enable(id, !disabled.has(id));
  if (disabled.has(id)) {
    arrangement = arrangement.map(step => step.filter(clip => clip.id !== id)).filter(step => step.length);
    if (!selectedClip()) selectedToken = null;
    paintArrangement(); submitArrangement(false);
  }
  persist();
  paintLibrary(); paint();
}
function padAt(target) { return target instanceof Element ? target.closest('.pad') : null; }
function clearPointer() {
  pointer = null; $('drag-preview').hidden = true;
  document.querySelectorAll('.drop-active, .drop-before, .drop-after').forEach(element => element.classList.remove('drop-active', 'drop-before', 'drop-after'));
}
function dropAt(x, y) {
  const target = document.elementFromPoint(x, y);
  if (!(target instanceof Element)) return null;
  const slot = target.closest('.arrangement-gap, .arrangement-empty');
  if (slot) return { element: slot, index: Number(slot.dataset.index), layer: false };
  const step = target.closest('.sequence-step');
  if (step) {
    const index = Number(step.dataset.step), rect = step.getBoundingClientRect();
    const edge = Math.min(24, rect.width / 3);
    if (x - rect.left < edge) return { element: step, index, layer: false, edge: 'before' };
    if (rect.right - x < edge) return { element: step, index: index + 1, layer: false, edge: 'after' };
    return { element: step, index, layer: true };
  }
  const container = target.closest('#arrangement-items');
  return container ? { element: container, index: arrangement.length, layer: false } : null;
}
$('grid').addEventListener('pointerdown', event => {
  const pad = padAt(event.target);
  if (!pad || (event.pointerType === 'mouse' && event.button !== 0)) return;
  const id = Number(pad.dataset.id);
  const source = sampleFor(id)?.songID;
  if (source && source !== song?.id) showSong(source);
  event.preventDefault();
  pad.focus({ preventScroll: true });
  if (pointer || (!editing && disabled.has(id))) return;
  pad.setPointerCapture(event.pointerId);
  pointer = { pointerId: event.pointerId, id, x: event.clientX, y: event.clientY, lastY: event.clientY,
    started: performance.now(), touch: event.pointerType === 'touch', dragging: false, scrolling: false,
    shift: event.shiftKey, alt: event.altKey, target: null };
});
$('grid').addEventListener('pointermove', event => {
  if (!pointer || pointer.pointerId !== event.pointerId) return;
  const distance = Math.hypot(event.clientX - pointer.x, event.clientY - pointer.y);
  if (!pointer.dragging && distance > 8) {
    if (pointer.touch && performance.now() - pointer.started < 220) pointer.scrolling = true;
    else if (!editing && !pointer.scrolling) pointer.dragging = true;
  }
  if (pointer.scrolling) { $('grid').scrollTop -= event.clientY - pointer.lastY; pointer.lastY = event.clientY; return; }
  if (!pointer.dragging) return;
  const sample = sampleFor(pointer.id), preview = $('drag-preview');
  preview.hidden = false; preview.textContent = `${sample.songName} · ${String(sample.number).padStart(2, '0')}`;
  preview.style.left = `${event.clientX + 12}px`; preview.style.top = `${event.clientY + 12}px`;
  document.querySelectorAll('.drop-active, .drop-before, .drop-after').forEach(element => element.classList.remove('drop-active', 'drop-before', 'drop-after'));
  pointer.target = dropAt(event.clientX, event.clientY);
  pointer.target?.element.classList.add(pointer.target.edge ? `drop-${pointer.target.edge}` : 'drop-active');
  const rect = $('arrangement-items').getBoundingClientRect();
  if (event.clientY >= rect.top && event.clientY <= rect.bottom) {
    if (event.clientX < rect.left + 42) $('arrangement-items').scrollLeft -= 14;
    if (event.clientX > rect.right - 42) $('arrangement-items').scrollLeft += 14;
  }
});
for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
  $('grid').addEventListener(type, event => {
    if (!pointer || pointer.pointerId !== event.pointerId) return;
    const finished = pointer;
    if (type === 'pointerup' && !finished.scrolling) {
      if (finished.dragging) {
        const target = dropAt(event.clientX, event.clientY);
        if (target) addSample(finished.id, target.index, target.layer);
      } else if (editing) toggleDisabled(finished.id);
      else if (finished.shift) addSample(finished.id, arrangement.length);
      else if (finished.alt && arrangement.length) addSample(finished.id, Math.max(0, arrangement.findIndex(step => step.some(clip => clip.token === selectedToken))), true);
      else addSample(finished.id, arrangement.length);
    }
    clearPointer();
  });
}
window.addEventListener('blur', clearPointer);
$('grid').addEventListener('contextmenu', event => event.preventDefault());
$('grid').addEventListener('click', event => {
  // Native keyboard and assistive-technology activation produces detail 0.
  if (event.detail !== 0) return;
  const pad = padAt(event.target);
  if (!pad) return;
  const id = Number(pad.dataset.id);
  const source = sampleFor(id)?.songID;
  if (source && source !== song?.id) showSong(source);
  if (editing) toggleDisabled(id);
  else if (!disabled.has(id)) {
    if (event.shiftKey) addSample(id, arrangement.length);
    else if (event.altKey && arrangement.length) addSample(id, Math.max(0, arrangement.findIndex(step => step.some(clip => clip.token === selectedToken))), true);
    else addSample(id, arrangement.length);
  }
});
$('grid').addEventListener('keydown', event => {
  if (event.altKey && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
    const pad = padAt(event.target); if (!pad) return;
    event.preventDefault(); if (event.repeat || editing) return;
    const id = Number(pad.dataset.id), source = sampleFor(id)?.songID;
    if (source && source !== song?.id) showSong(source);
    const selected = arrangement.findIndex(step => step.some(clip => clip.token === selectedToken));
    const index = selected < 0 ? (event.key === 'ArrowLeft' ? 0 : arrangement.length) : selected + (event.key === 'ArrowRight' ? 1 : 0);
    addSample(id, index);
    return;
  }
  // Modified Enter/Space is not consistently translated into a native click,
  // especially Option-Enter on macOS, so handle those shortcuts directly.
  if ((event.key === 'Enter' || event.key === ' ') && (event.shiftKey || event.altKey)) {
    event.preventDefault();
    if (event.repeat) return;
    const pad = padAt(event.target);
    if (!pad) return;
    const id = Number(pad.dataset.id);
    const source = sampleFor(id)?.songID;
    if (source && source !== song?.id) showSong(source);
    if (editing) toggleDisabled(id);
    else if (!disabled.has(id)) {
      if (event.shiftKey) addSample(id, arrangement.length);
      else if (arrangement.length) addSample(id, Math.max(0, arrangement.findIndex(step => step.some(clip => clip.token === selectedToken))), true);
      else addSample(id, arrangement.length);
    }
    return;
  }
  if (event.key !== 'ArrowUp' && event.key !== 'ArrowDown') return;
  const items = [...pads.values()].map(item => item.element).filter(item => item.offsetParent);
  const index = items.indexOf(event.target); if (index < 0) return;
  event.preventDefault(); items[Math.min(items.length - 1, Math.max(0, index + (event.key === 'ArrowUp' ? -1 : 1)))].focus();
});

function setPartsMask(clip, mask) {
  if (!clip) return;
  clip.mask = mask & 15;
  selectClip(clip.token);
  audio.setClipMask(clip.token, clip.mask);
  const row = document.querySelector(`.clip-row[data-token="${clip.token}"]`), sample = sampleFor(clip.id);
  if (row && sample) updateClipPartsUI(row, clip, sample, Number(row.dataset.beats));
  prepareUpcoming();
}
$('arrangement-items').addEventListener('click', event => {
  const choose = event.target.closest('[data-select]'), remove = event.target.closest('[data-remove]');
  const part = event.target.closest('[data-part]'), all = event.target.closest('[data-parts-all]');
  if (part || all) {
    const row = event.target.closest('.clip-row'), clip = allClips().find(item => item.token === Number(row?.dataset.token));
    if (!clip) return;
    setPartsMask(clip, all ? (clip.mask === 15 ? 0 : 15) : clip.mask ^ (1 << Number(part.dataset.part)));
  } else if (choose) {
    selectClip(Number(choose.dataset.select)); prepareUpcoming();
  } else if (remove) {
    const token = Number(remove.dataset.remove);
    arrangement = arrangement.map(step => step.filter(clip => clip.token !== token)).filter(step => step.length);
    if (selectedToken === token) selectedToken = null;
    paintArrangement(); submitArrangement(false);
  }
});
function applyClipFilter(input) {
  const clip = allClips().find(item => item.token === Number(input.dataset.filter)); if (!clip) return;
  const settings = filterFromPosition(Number(input.value) / 100);
  clip.filterType = settings.type; clip.filterHz = settings.hz;
  selectClip(clip.token); audio.setClipFilter(clip.token, clip.filterType, clip.filterHz);
  updateClipFilterUI(input.closest('.clip-row'), clip);
}
$('arrangement-items').addEventListener('input', event => {
  const filter = event.target.closest('input[data-filter]');
  if (filter) { applyClipFilter(filter); return; }
  const slider = event.target.closest('input[data-level]'); if (!slider) return;
  const clip = allClips().find(item => item.token === Number(slider.dataset.level)); if (!clip) return;
  clip.level = Number(slider.value) / 100;
  selectClip(clip.token);
  slider.closest('.clip-level').querySelector('output').textContent = `${slider.value}%`;
  audio.setClipLevel(clip.token, clip.level);
});
let dialDrag = null;
$('arrangement-items').addEventListener('pointerdown', event => {
  const input = event.target.closest('input[data-filter]');
  if (!input || event.button !== 0) return;
  event.preventDefault(); input.focus({ preventScroll: true }); input.setPointerCapture(event.pointerId);
  dialDrag = { input, id: event.pointerId, y: event.clientY, value: Number(input.value) };
});
$('arrangement-items').addEventListener('pointermove', event => {
  if (!dialDrag || event.pointerId !== dialDrag.id) return;
  dialDrag.input.value = Math.max(-100, Math.min(100, Math.round(dialDrag.value + dialDrag.y - event.clientY)));
  applyClipFilter(dialDrag.input);
});
for (const type of ['pointerup', 'pointercancel', 'lostpointercapture']) {
  $('arrangement-items').addEventListener(type, event => { if (dialDrag && event.pointerId === dialDrag.id) dialDrag = null; });
}
$('arrangement-items').addEventListener('dblclick', event => {
  const input = event.target.closest('input[data-filter]');
  if (input) { input.value = '0'; applyClipFilter(input); }
});
$('clear-arrangement').addEventListener('click', () => {
  arrangement = []; selectedToken = null; paintArrangement(); submitArrangement(false);
});
$('retry-parts').addEventListener('click', () => {
  const clip = selectedClip(); if (clip) partFailures.delete(clip.id);
  renderPartStatus(); prepareUpcoming();
});
$('master-filter-modes').addEventListener('click', event => {
  const button = event.target.closest('button[data-mode]'); if (!button) return;
  filterMode = Number(button.dataset.mode); audio.setFilter(filterMode, filterHz);
  for (const item of $('master-filter-modes').querySelectorAll('button')) item.setAttribute('aria-pressed', String(item === button));
});
$('master-cutoff').value = sliderPosition(filterHz);
$('master-cutoff').addEventListener('input', event => {
  filterHz = 40 * (18000 / 40) ** (Number(event.target.value) / 1000);
  $('master-cutoff-value').textContent = formatHz(filterHz); audio.setFilter(filterMode, filterHz);
});
$('zoom-fit').addEventListener('click', () => { zoom = 1; applyZoom(); $('arrangement-items').scrollLeft = 0; });
$('zoom-in').addEventListener('click', () => { zoom = Math.min(128, zoom * 1.5); applyZoom(); });
$('zoom-out').addEventListener('click', () => { zoom = Math.max(1, zoom / 1.5); applyZoom(); });


$('transport').addEventListener('click', () => {
  if (state.playing || loading) { stop(); return; }
  const first = song.loops.find(sample => !disabled.has(sample.id));
  if (arrangement.length) submitArrangement();
  else if (first) addSample(first.id, 0);
  else notice('Every loop in this folder is excluded. Use Edit to restore a loop.');
});
function setupNudge(button, milliseconds) {
  let delay, interval, handledPointer = false;
  const clear = () => { clearTimeout(delay); clearInterval(interval); delay = interval = undefined; };
  button.addEventListener('pointerdown', event => {
    if (event.button !== 0 || button.disabled) return;
    handledPointer = true;
    button.setPointerCapture(event.pointerId);
    audio.nudge(milliseconds);
    delay = setTimeout(() => {
      interval = setInterval(() => { if (!button.disabled) audio.nudge(milliseconds); }, 100);
    }, 350);
  });
  button.addEventListener('pointerup', clear);
  button.addEventListener('pointercancel', () => { clear(); handledPointer = false; });
  button.addEventListener('lostpointercapture', clear);
  button.addEventListener('blur', clear);
  button.addEventListener('click', event => {
    if (event.detail === 0 || !handledPointer) audio.nudge(milliseconds);
    handledPointer = false;
  });
  document.addEventListener('visibilitychange', () => { if (document.hidden) clear(); });
}
setupNudge($('nudge-earlier'), 10);
setupNudge($('nudge-later'), -10);
$('retry').addEventListener('click', () => {
  if (!songs.length) loadCatalog();
  else if (arrangement.length) submitArrangement();
});
$('edit').addEventListener('click', () => {
  editing = !editing;
  clearPointer();
  $('edit').textContent = editing ? 'Done' : 'Edit';
  $('edit').setAttribute('aria-pressed', String(editing));
  $('grid').classList.toggle('editing', editing);
  updateHint();
  paintLibrary(); paint();
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
    const config = await fetch(new URL('./asset-config.json', import.meta.url), { cache: 'no-cache' });
    if (!config.ok) throw new Error(`Asset configuration HTTP ${config.status}`);
    const base = assetBase((await config.json()).assetBaseURL, import.meta.url);
    audio.assetBaseURL = base;
    const response = await fetch(assetURL(base, 'catalog.json'), { cache: 'no-cache' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const catalog = await response.json();
    if (!Array.isArray(catalog) || !catalog.length || catalog.some(item => !Array.isArray(item.loops) || !item.loops.length)) throw new Error('Empty sample catalog');
    songs = catalog;
    samples = songs.flatMap(item => item.loops.map(sample => ({ ...sample, songName: item.name, songID: item.id })));
    for (const item of songs) audio.setPartMask(item.loops.map(sample => sample.id), songMask(item));
    $('transport').disabled = $('edit').disabled = false;
    $('grid').setAttribute('aria-busy', 'false');
    buildLibrary(); paintArrangement();
  } catch (error) {
    $('grid').setAttribute('aria-busy', 'false');
    notice(`The sample library couldn't load. Check your connection and retry. (${error.message})`, true);
  }
}
loadCatalog();
