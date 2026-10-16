// Thin host adapter. All transport, mixing and DSP execute in the Rust module.
const MAX_FRAMES = 2048;
const MAX_CLIPS = 64;
export class WasmEngine {
  constructor(instance, sampleRate) {
    this.exports = instance.exports;
    this.memory = this.exports.memory;
    this.sampleRate = sampleRate;
    this.handle = this.exports.bw_create_web(sampleRate);
    if (!this.handle) throw new Error('Could not create the audio engine');
    this.audio = this.exports.bw_scratch_alloc(MAX_FRAMES);
    this.control = this.exports.bw_scratch_alloc(MAX_CLIPS * 4);
    this.snapshotBuffer = this.exports.bw_scratch_alloc(Math.ceil(this.exports.bw_snapshot_size() / 8));
    this.offsets = Array.from({ length: 14 }, (_, i) => this.exports.bw_snapshot_offset(i));
    this.clockFrames = 0;
    this.frameCounts = new Map();
    this.refresh();
  }
  refresh() {
    if (this.buffer === this.memory.buffer) return;
    this.buffer = this.memory.buffer;
    this.left = new Float32Array(this.buffer, this.audio, MAX_FRAMES);
    this.right = new Float32Array(this.buffer, this.audio + MAX_FRAMES * 4, MAX_FRAMES);
    this.controlInts = new Int32Array(this.buffer, this.control, MAX_CLIPS * 7);
    this.view = new DataView(this.buffer, this.snapshotBuffer, this.exports.bw_snapshot_size());
  }
  destroy() {
    if (!this.handle) return;
    this.exports.bw_destroy(this.handle);
    this.exports.bw_scratch_free(this.audio, MAX_FRAMES);
    this.exports.bw_scratch_free(this.control, MAX_CLIPS * 4);
    this.exports.bw_scratch_free(this.snapshotBuffer, Math.ceil(this.exports.bw_snapshot_size() / 8));
    this.handle = 0;
  }
  beginLoad(id, channels, beats) {
    if (!Number.isInteger(id) || id < 0 || id >= this.exports.bw_max_loops() ||
        !Array.isArray(channels) || !channels.length || channels.length > 2 ||
        channels[0].length < 2 || channels.some(c => !(c instanceof Float32Array) || c.length !== channels[0].length) ||
        !Number.isInteger(beats) || beats < 1) throw new Error('Invalid sample data');
    const frames = channels[0].length;
    const object = this.exports.bw_prepare_loop(frames, beats);
    if (!object) throw new Error('Could not allocate loop');
    const destination = this.exports.bw_prepared_loop_pcm(object);
    return { type: 'load', id, object, destination, frames, channels: [channels[0], channels[1] || channels[0]], channel: 0, offset: 0 };
  }
  beginParts(id, parts) {
    if (!Array.isArray(parts) || parts.length !== 4 || parts.some(p => p.length !== 2)) throw new Error('Invalid part data');
    const channels = parts.flat(), frames = channels[0]?.length;
    if (!frames || frames < 2 || frames !== this.frameCounts.get(id) || channels.some(c => !(c instanceof Float32Array) || c.length !== frames)) throw new Error('Invalid part data');
    const object = this.exports.bw_prepare_parts(frames);
    if (!object) throw new Error('Could not allocate parts');
    const destination = this.exports.bw_prepared_parts_pcm(object);
    return { type: 'parts', id, object, destination, frames, channels, channel: 0, offset: 0 };
  }
  copy(job, budget) {
    this.refresh();
    while (budget > 0 && job.channel < job.channels.length) {
      const count = Math.min(budget, job.frames - job.offset);
      const destination = new Float32Array(this.buffer, job.destination + (job.channel * job.frames + job.offset) * 4, count);
      destination.set(job.channels[job.channel].subarray(job.offset, job.offset + count));
      job.offset += count; budget -= count;
      if (job.offset === job.frames) { job.offset = 0; job.channel++; }
    }
    return job.channel === job.channels.length;
  }
  finish(job) {
    const object = job.object;
    job.object = 0; // Both installation functions consume the allocation, including on failure.
    if (job.type === 'load') {
      if (!this.exports.bw_install_loop(this.handle, job.id, object)) throw new Error('Loop already loaded or invalid');
      this.frameCounts.set(job.id, job.frames);
    } else this.exports.bw_set_parts(this.handle, job.id, object);
  }
  discard(job) {
    if (!job?.object) return;
    if (job.type === 'load') this.exports.bw_discard_loop(job.object);
    else this.exports.bw_discard_parts(job.object);
    job.object = 0;
  }
  // Useful to offline hosts; the live worklet copies incrementally instead.
  load(id, channels, beats) { const job = this.beginLoad(id, channels, beats); try { this.copy(job, Infinity); this.finish(job); } catch (error) { this.discard(job); throw error; } }
  setParts(id, parts) {
    if (!parts) { this.exports.bw_set_parts(this.handle, id, 0); return; }
    const job = this.beginParts(id, parts); try { this.copy(job, Infinity); this.finish(job); } catch (error) { this.discard(job); throw error; }
  }
  queue(ids) {
    this.refresh(); const unique = [...new Set(ids)].slice(0, MAX_CLIPS); this.controlInts.set(unique);
    this.exports.bw_queue(this.handle, this.control, unique.length);
  }
  arrange(items) {
    this.refresh(); const count = Math.min(MAX_CLIPS, items.length);
    for (let i = 0; i < count; i++) {
      const clip = items[i];
      this.controlInts.set([clip.id, clip.token, clip.step, clip.mask, clip.filterType ?? 0, Math.round(clip.filterHz ?? 1200), Math.round((clip.level ?? 1) * 1000)], i * 7);
    }
    this.exports.bw_arrange_with_levels(this.handle, this.control, count);
  }
  setClipMask(token, mask) { this.exports.bw_clip_mask(this.handle, token, mask); }
  setClipFilter(token, mode, hz) { this.exports.bw_clip_filter(this.handle, token, mode, hz); }
  setClipLevel(token, level) { this.exports.bw_clip_level(this.handle, token, level); }
  setPartMask(id, mask) { this.exports.bw_part_mask(this.handle, id, mask); }
  enable(id, enabled) { this.exports.bw_enable(this.handle, id, Number(enabled)); }
  setTempo(bpm) { this.exports.bw_web_tempo(this.handle, bpm); }
  nudge(ms) { this.exports.bw_nudge(this.handle, ms); }
  setFilter(type, hz) { this.exports.bw_filter(this.handle, type, hz); }
  stop() { this.exports.bw_web_stop(this.handle); }
  render(left, right, hostTime = this.clockFrames / this.sampleRate) {
    if (left.length !== right.length) throw new Error('Mismatched audio channels');
    for (let start = 0; start < left.length; start += MAX_FRAMES) {
      const count = Math.min(MAX_FRAMES, left.length - start);
      this.exports.bw_render(this.handle, this.audio, this.audio + MAX_FRAMES * 4, count, hostTime + start / this.sampleRate);
      this.refresh();
      left.set(this.left.subarray(0, count), start); right.set(this.right.subarray(0, count), start);
    }
    this.clockFrames += left.length;
  }
  snapshot() {
    this.exports.bw_snapshot(this.handle, this.snapshotBuffer); this.refresh();
    const o = this.offsets, v = this.view;
    const i = n => v.getInt32(o[n], true), d = n => v.getFloat64(o[n], true);
    const count = i(6), activeCount = i(8), active = i(4);
    const ints = (field, length) => Array.from({ length }, (_, n) => v.getInt32(o[field] + n * 4, true));
    return { beat: d(0), bpm: d(1), progress: d(2), playing: !!i(3), active: active < 0 ? null : active,
      pending: !!i(5), queue: ints(7, count), activeStep: i(9), activeLoops: ints(10, activeCount),
      activeTokens: ints(11, activeCount), activeProgress: Array.from({ length: activeCount }, (_, n) => v.getFloat64(o[12] + n * 8, true)),
      droppedCommands: v.getUint32(o[13], true) };
  }
}
