import { AudioPlayer } from './audio.js';
import { assetBase, assetURL } from './assets.js';

const $ = id => document.getElementById(id);
const storageKey = 'breakwater.web.v1';
let saved = {};
try { saved = JSON.parse(localStorage.getItem(storageKey)) || {}; } catch { /* Private browsing or invalid saved data. */ }
const bounded = (value, fallback, min, max) => Number.isFinite(value) ? Math.min(max, Math.max(min, value)) : fallback;
let tempo = bounded(saved.tempo, 120, 30, 300);
let volume = bounded(saved.volume, .8, 0, 1);
const disabled = new Set(Array.isArray(saved.disabled) ? saved.disabled.filter(Number.isInteger) : []);
const partMasks = saved.partMasks && typeof saved.partMasks === 'object' ? saved.partMasks : {};
let tray = false, filterMode = 0, filterHz = 1200, partError = '';
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
  $('song').value = song.id;
  $('artist').textContent = song.artist;
  $('source-bpm').textContent = `≈${song.sourceBPM}`;
  $('source-bpm').title = song.sourceBPMRange ? `Loop range: ${song.sourceBPMRange.join('–')} BPM. ${song.timingNote || ''}` : 'Approximate source tempo';
  $('grid').setAttribute('aria-label', `${song.name} loop pads`);
  pads = new Map();
  const fragment = document.createDocumentFragment();
  for (const sample of song.loops) {
    const pad = document.createElement('button');
    pad.type = 'button';
    pad.className = 'pad';
    pad.dataset.id = sample.id;
    pad.setAttribute('aria-describedby', 'keyboard-help');
    pad.title = `${song.name} · ${sample.sourceStart}–${sample.sourceEnd} · ${sample.bpm.toFixed(1)} BPM`;
    // Numeric waveform data and metadata come from the catalog.
    pad.innerHTML = `<span class="sweep"></span><span class="pad-header"><span class="pad-number">${String(sample.number).padStart(2, '0')}</span><span class="pad-bars">${sample.bars} ${sample.bars === 1 ? 'bar' : 'bars'}</span></span><svg class="waveform" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true"><path d="${waveform(sample.waveform)}"/></svg><span class="pad-status"></span>`;
    pads.set(sample.id, { element: pad, status: pad.querySelector('.pad-status'), sample });
    fragment.append(pad);
  }
  $('grid').replaceChildren(fragment);
  paintPartButtons();
  paintArrangement();
  paintWaveforms();
  layout();
  paint();
  persist();
}

function layout() {
  const grid = $('grid');
  const width = grid.clientWidth;
  const columns = width < 260 ? 2 : width < 460 ? 3 : width < 650 ? 4 : width > grid.clientHeight * 1.12 ? 6 : 5;
  grid.style.setProperty('--columns', columns);
  grid.style.setProperty('--rows', Math.ceil((song?.loops.length || 30) / columns));
  grid.classList.toggle('scrollable', grid.scrollHeight > grid.clientHeight + 1);
  updateHint();
}
new ResizeObserver(layout).observe($('grid'));

function songMask(item = song) { return (Number.isInteger(partMasks[item?.id]) ? partMasks[item.id] : 15) & 15; }
function allClips() { return arrangement.flat(); }
function selectedClip() { return allClips().find(clip => clip.token === selectedToken); }
function sampleFor(id) { return samples.find(sample => sample.id === id); }
function clipForWaveform(id) {
  const selected = selectedClip();
  if (selected?.id === id) return selected;
  return allClips().find(clip => clip.id === id && (state.activeTokens || []).includes(clip.token));
}
function paintPartButtons() {
  const clip = selectedClip(), sample = clip && sampleFor(clip.id);
  const source = sample && songs.find(item => item.id === sample.songID);
  $('part-target').textContent = sample ? `${sample.songName} · ${String(sample.number).padStart(2, '0')} · approximate layers may overlap.` : 'Tap a sample in the sequence to edit its parts.';
  $('parts-off').disabled = $('parts-on').disabled = !clip;
  $('part-buttons').replaceChildren(...(source?.partLabels || []).map((name, index) => {
    const button = document.createElement('button');
    const on = !!(clip.mask & (1 << index));
    button.type = 'button'; button.dataset.part = index; button.setAttribute('aria-pressed', String(on));
    button.innerHTML = `<span>${name}</span><span>${on ? 'ON' : 'OFF'}</span>`;
    return button;
  }));
}
function paintWaveforms() {
  for (const { element, sample } of pads.values()) {
    const svg = element.querySelector('.waveform');
    const clip = clipForWaveform(sample.id), mask = clip?.mask ?? 15;
    if (sample.parts && clip) {
      svg.innerHTML = sample.parts.waveforms.map((values, index) => `<path class="${mask & (1 << index) ? '' : 'muted-part'}" d="${waveform(values, 12.5 + index * 25, 11)}"/>`).join('');
    } else svg.innerHTML = `<path d="${waveform(sample.waveform)}"/>`;
  }
}
function setTray(next) {
  tray = next;
  $('tray').hidden = !tray;
  $('show-sound').setAttribute('aria-expanded', String(tray));
  paintWaveforms();
  layout();
}
function prepareUpcoming() {
  if (!state.playing) return;
  const index = arrangement.findIndex(step => step.some(clip => (state.activeTokens || []).includes(clip.token)));
  const upcoming = [...(arrangement[index] || []), ...(arrangement[(index + 1) % arrangement.length] || []), ...(selectedClip() ? [selectedClip()] : [])];
  const ids = [...new Set(upcoming.filter(clip => clip.mask !== 15).map(clip => clip.id))];
  audio.pinParts([...new Set([...(state.activeLoops || []), ...ids])]);
  for (const id of ids) {
    const sample = sampleFor(id);
    if (!sample || !audio.loaded.has(id) || audio.partCache.has(id) || audio.partInFlight.has(id)) continue;
    if (partError) continue;
    if (id === selectedClip()?.id) $('part-message').textContent = 'Preparing parts · full mix plays until ready';
    audio.loadParts(sample).then(() => {
      if (id === selectedClip()?.id) $('part-message').textContent = '';
    }).catch(error => {
      partError = `Parts could not load (${error.message}). The full mix remains available.`;
      $('part-message').textContent = partError; $('retry-parts').hidden = false;
    });
  }
}

function updateHint() {
  $('hint').textContent = editing ? 'Tap pads to exclude or restore them. Changes are saved on this browser.'
    : 'Tap a pad to replace the sequence. Drag it below to layer or add a step. On touch, hold briefly to drag; swipe to scroll.';
}

function paintArrangement() {
  const container = $('arrangement-items');
  const content = document.createDocumentFragment();
  function gap(index) {
    const slot = document.createElement('div'); slot.className = 'arrangement-gap'; slot.dataset.index = index;
    slot.setAttribute('aria-hidden', 'true'); slot.textContent = '+'; return slot;
  }
  if (!arrangement.length) {
    const empty = document.createElement('div'); empty.className = 'arrangement-empty'; empty.dataset.index = '0';
    empty.textContent = 'Drag a sample here to start'; content.append(empty);
  } else arrangement.forEach((step, index) => {
    content.append(gap(index));
    const group = document.createElement('div'); group.className = 'sequence-step'; group.dataset.step = index;
    const heading = document.createElement('div'); heading.className = 'step-heading'; heading.textContent = `STEP ${String(index + 1).padStart(2, '0')}  ·  ${step.length} ${step.length === 1 ? 'SAMPLE' : 'LAYERS'}`;
    group.append(heading);
    for (const clip of step) {
      const sample = sampleFor(clip.id); if (!sample) continue;
      const row = document.createElement('div'); row.className = 'clip-row'; row.dataset.token = clip.token;
      const choose = document.createElement('button'); choose.type = 'button'; choose.className = 'clip-select'; choose.dataset.select = clip.token;
      choose.setAttribute('aria-pressed', String(clip.token === selectedToken));
      choose.setAttribute('aria-label', `Edit parts for ${sample.songName}, loop ${sample.number}, step ${index + 1}`);
      const label = document.createElement('span'); label.className = 'clip-label'; label.textContent = `${sample.songName} · ${String(sample.number).padStart(2, '0')}`;
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg'); svg.setAttribute('viewBox', '0 0 100 100'); svg.setAttribute('preserveAspectRatio', 'none'); svg.classList.add('clip-waveform'); svg.setAttribute('aria-hidden', 'true');
      svg.innerHTML = sample.parts ? sample.parts.waveforms.map((values, p) => `<path class="${clip.mask & (1 << p) ? '' : 'muted-part'}" d="${waveform(values, 12.5 + p * 25, 11)}"/>`).join('') : `<path d="${waveform(sample.waveform)}"/>`;
      choose.append(label, svg);
      const remove = document.createElement('button'); remove.type = 'button'; remove.className = 'clip-remove'; remove.dataset.remove = clip.token;
      remove.setAttribute('aria-label', `Remove ${sample.songName}, loop ${sample.number}, from step ${index + 1}`); remove.textContent = '×';
      row.append(choose, remove); group.append(row);
    }
    content.append(group);
  });
  if (arrangement.length) content.append(gap(arrangement.length));
  container.replaceChildren(content);
  $('clear-arrangement').disabled = !arrangement.length;
  paintArrangementState();
}
function paintArrangementState() {
  const active = new Set(state.playing ? state.activeTokens || [] : []);
  document.querySelectorAll('.clip-row').forEach(row => row.classList.toggle('active', active.has(Number(row.dataset.token))));
  document.querySelectorAll('.sequence-step').forEach(group => group.classList.toggle('active', [...group.querySelectorAll('.clip-row')].some(row => active.has(Number(row.dataset.token)))));
}

function paint() {
  const queue = allClips().map(clip => clip.id);
  const playingIDs = new Set(state.playing ? (state.activeLoops || [state.active]) : []);
  for (const [id, { element, status, sample }] of pads) {
    const excluded = disabled.has(id);
    const playing = playingIDs.has(id);
    const order = arrangement.findIndex(step => step.some(clip => clip.id === id));
    const pending = (state.pending || loading) && order >= 0;
    element.classList.toggle('playing', playing);
    element.classList.toggle('queued', order >= 0 && !playing);
    element.classList.toggle('pending', pending);
    element.classList.toggle('excluded', excluded);
    element.setAttribute('aria-disabled', String(excluded && !editing));
    element.setAttribute('aria-pressed', String(playing));
    if (playing) {
      const selected = selectedClip();
      const index = selected?.id === id ? (state.activeTokens || []).indexOf(selected.token) : (state.activeLoops || []).indexOf(id);
      element.style.setProperty('--progress', state.activeProgress?.[index] ?? state.progress);
    }
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
  $('nudge-earlier').disabled = $('nudge-later').disabled = !playing || state.active === null;
  const current = samples.find(sample => sample.id === state.active);
  $('playing-label').textContent = playing && current ? `${current.songName} · ${String(current.number).padStart(2, '0')}` : loading ? 'Loading samples' : 'Pick a loop';
  if (playing && (state.activeLoops || []).length > 1) $('playing-label').textContent += ` + ${(state.activeLoops || []).length - 1}`;
  $('playing-label').title = $('playing-label').textContent;
  [...document.querySelectorAll('.beat-dots i')].forEach((dot, index) => dot.classList.toggle('on', playing && Math.floor(state.beat) % 4 === index));
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
  return { id, token: nextToken++, mask: songMask({ id: sample?.songID }) };
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
  paintArrangement(); paintPartButtons(); paintWaveforms();
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
    paintArrangement(); paintPartButtons(); paintWaveforms(); submitArrangement(false);
  }
  persist();
  paint();
}
function padAt(target) { return target instanceof Element ? target.closest('.pad') : null; }
function clearPointer() {
  pointer = null; $('drag-preview').hidden = true;
  document.querySelectorAll('.drop-active').forEach(element => element.classList.remove('drop-active'));
}
function dropAt(x, y) {
  const target = document.elementFromPoint(x, y);
  if (!(target instanceof Element)) return null;
  const slot = target.closest('.arrangement-gap, .arrangement-empty');
  if (slot) return { element: slot, index: Number(slot.dataset.index), layer: false };
  const step = target.closest('.sequence-step');
  if (step) return { element: step, index: Number(step.dataset.step), layer: true };
  const container = target.closest('#arrangement-items');
  return container ? { element: container, index: arrangement.length, layer: false } : null;
}
$('grid').addEventListener('pointerdown', event => {
  const pad = padAt(event.target);
  if (!pad || (event.pointerType === 'mouse' && event.button !== 0)) return;
  const id = Number(pad.dataset.id);
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
  document.querySelectorAll('.drop-active').forEach(element => element.classList.remove('drop-active'));
  pointer.target = dropAt(event.clientX, event.clientY);
  pointer.target?.element.classList.add('drop-active');
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
      else addSample(finished.id, 0, false, true);
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
  if (editing) toggleDisabled(id);
  else if (!disabled.has(id)) {
    if (event.shiftKey) addSample(id, arrangement.length);
    else if (event.altKey && arrangement.length) addSample(id, Math.max(0, arrangement.findIndex(step => step.some(clip => clip.token === selectedToken))), true);
    else addSample(id, 0, false, true);
  }
});
$('grid').addEventListener('keydown', event => {
  // Modified Enter/Space is not consistently translated into a native click,
  // especially Option-Enter on macOS, so handle those shortcuts directly.
  if ((event.key === 'Enter' || event.key === ' ') && (event.shiftKey || event.altKey)) {
    event.preventDefault();
    if (event.repeat) return;
    const pad = padAt(event.target);
    if (!pad) return;
    const id = Number(pad.dataset.id);
    if (editing) toggleDisabled(id);
    else if (!disabled.has(id)) {
      if (event.shiftKey) addSample(id, arrangement.length);
      else if (arrangement.length) addSample(id, Math.max(0, arrangement.findIndex(step => step.some(clip => clip.token === selectedToken))), true);
      else addSample(id, 0, false, true);
    }
    return;
  }
  const offsets = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -Number($('grid').style.getPropertyValue('--columns')), ArrowDown: Number($('grid').style.getPropertyValue('--columns')) };
  if (!(event.key in offsets)) return;
  const items = [...pads.values()].map(item => item.element);
  const index = items.indexOf(event.target);
  if (index < 0) return;
  event.preventDefault();
  items[Math.min(items.length - 1, Math.max(0, index + offsets[event.key]))].focus();
});

$('song').addEventListener('change', () => showSong($('song').value));
$('show-sound').addEventListener('click', () => setTray(!tray));
$('close-tray').addEventListener('click', () => setTray(false));
$('arrangement-items').addEventListener('click', event => {
  const choose = event.target.closest('[data-select]'), remove = event.target.closest('[data-remove]');
  if (choose) {
    selectedToken = Number(choose.dataset.select); partError = ''; $('retry-parts').hidden = true; $('part-message').textContent = '';
    paintArrangement(); paintPartButtons(); paintWaveforms(); setTray(true); prepareUpcoming();
    document.querySelector(`[data-select="${selectedToken}"]`)?.focus({ preventScroll: true });
  } else if (remove) {
    const token = Number(remove.dataset.remove);
    arrangement = arrangement.map(step => step.filter(clip => clip.token !== token)).filter(step => step.length);
    if (selectedToken === token) selectedToken = null;
    paintArrangement(); paintPartButtons(); paintWaveforms(); submitArrangement(false);
  }
});
$('clear-arrangement').addEventListener('click', () => {
  arrangement = []; selectedToken = null; paintArrangement(); paintPartButtons(); paintWaveforms(); submitArrangement(false);
});
function setPartsMask(mask) {
  const clip = selectedClip(); if (!clip) return;
  clip.mask = mask & 15;
  audio.setClipMask(clip.token, clip.mask);
  partError = ''; $('retry-parts').hidden = true; $('part-message').textContent = '';
  paintArrangement(); paintPartButtons(); paintWaveforms(); prepareUpcoming();
}
$('part-buttons').addEventListener('click', event => {
  const button = event.target.closest('button[data-part]'), clip = selectedClip(); if (!button || !clip) return;
  const part = Number(button.dataset.part);
  setPartsMask(clip.mask ^ (1 << part));
  document.querySelector(`[data-part="${part}"]`)?.focus({ preventScroll: true });
});
$('parts-off').addEventListener('click', () => setPartsMask(0));
$('parts-on').addEventListener('click', () => setPartsMask(15));
$('retry-parts').addEventListener('click', () => { partError = ''; $('retry-parts').hidden = true; $('part-message').textContent = ''; prepareUpcoming(); });
$('filter-modes').addEventListener('click', event => {
  const button = event.target.closest('button[data-mode]'); if (!button) return;
  filterMode = Number(button.dataset.mode); audio.setFilter(filterMode, filterHz);
  for (const item of $('filter-modes').querySelectorAll('button')) item.setAttribute('aria-pressed', String(item === button));
});
$('cutoff').value = Math.round(1000 * Math.log(filterHz / 40) / Math.log(18000 / 40));
$('cutoff').addEventListener('input', event => {
  filterHz = 40 * (18000 / 40) ** (Number(event.target.value) / 1000);
  $('cutoff-value').textContent = filterHz >= 1000 ? `${(filterHz / 1000).toFixed(1)} kHz` : `${Math.round(filterHz)} Hz`;
  audio.setFilter(filterMode, filterHz);
});
$('transport').addEventListener('click', () => {
  if (state.playing || loading) { stop(); return; }
  const first = song.loops.find(sample => !disabled.has(sample.id));
  if (arrangement.length) submitArrangement();
  else if (first) addSample(first.id, 0);
  else notice('Every pad on this page is excluded. Use Edit pads to restore a loop.');
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
