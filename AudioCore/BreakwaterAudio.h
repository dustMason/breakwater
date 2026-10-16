#ifndef BREAKWATER_AUDIO_H
#define BREAKWATER_AUDIO_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void* BWEngine;
typedef void* BWParts;
// A clip belongs to one ordered step; clips in the same step play together.
typedef struct { int32_t loop, token, step, mask; } BWClip;
// Extended clip descriptor. Filter cutoff is expressed in whole Hz.
typedef struct { int32_t loop, token, step, mask, filterType, filterHz; } BWClipWithFilter;
// Level is linear thousandths: 0 is silence, 1000 is unity.
typedef struct { int32_t loop, token, step, mask, filterType, filterHz, levelMilli; } BWClipWithLevel;
typedef struct {
 double beat, bpm, loopProgress;
 int32_t playing, activeLoop, mode, externalClock, clockState, pending, queueCount;
 int32_t queue[64];
 int32_t activeCount, activeStep;
 int32_t activeLoops[16], activeTokens[16];
 double activeProgress[16];
 uint32_t droppedCommands;
} BWSnapshot;
BWEngine bw_create(double sampleRate);
void bw_destroy(BWEngine engine);
// Load each ID once. May run on a background thread during playback; audio is copied.
int32_t bw_load_loop(BWEngine engine,int32_t id,const float* interleaved,int32_t frames,int32_t beats,const int32_t* slices,int32_t sliceCount);
// All commands must come from one serialized producer; render is the consumer.
void bw_queue(BWEngine engine,const int32_t* ids,int32_t count);
// Up to 64 clips total, eight simultaneously. Steps are zero-based and ordered.
void bw_arrange(BWEngine engine,const BWClip* clips,int32_t count);
// Change the arrangement without starting a stopped transport.
void bw_edit_arrangement(BWEngine engine,const BWClip* clips,int32_t count);
void bw_arrange_with_filters(BWEngine engine,const BWClipWithFilter* clips,int32_t count);
void bw_edit_arrangement_with_filters(BWEngine engine,const BWClipWithFilter* clips,int32_t count);
void bw_arrange_with_levels(BWEngine engine,const BWClipWithLevel* clips,int32_t count);
void bw_edit_arrangement_with_levels(BWEngine engine,const BWClipWithLevel* clips,int32_t count);
// Two concurrent stacks; descriptor step selects A (0) or B (1), up to eight clips each.
void bw_stacks(BWEngine engine,const BWClipWithLevel* clips,int32_t count,int32_t start);
// 0 = A, 0.5 = equal-power center, 1 = B. Smoothed on the audio thread.
void bw_crossfade(BWEngine engine,double position);
void bw_clip_mask(BWEngine engine,int32_t token,int32_t mask);
void bw_clip_filter(BWEngine engine,int32_t token,int32_t type,double cutoffHz);
void bw_clip_level(BWEngine engine,int32_t token,double level);
void bw_enable(BWEngine engine,int32_t id,int32_t enabled);
void bw_tempo(BWEngine engine,double bpm);
void bw_mode(BWEngine engine,int32_t mode);
void bw_external(BWEngine engine,int32_t external);
void bw_transport(BWEngine engine,int32_t action); // 0 stop, 1 start, 2 continue, 3 align next downbeat now
void bw_midi(BWEngine engine,uint8_t status,int32_t value,double hostSeconds);
void bw_offset(BWEngine engine,double milliseconds);
// Positive moves the playing loop earlier; negative moves it later.
void bw_nudge(BWEngine engine,double milliseconds);
// Construct/decode on a worker. Install/retire on the serialized control queue.
// Parts are planar by part, then interleaved stereo, with exactly `frames` frames.
// bw_set_parts consumes its parts argument, including for an invalid ID/length.
BWParts bw_create_parts(const float* pcm,int32_t frames);
void bw_set_parts(BWEngine engine,int32_t id,BWParts parts);
void bw_part_mask(BWEngine engine,int32_t id,int32_t mask);
void bw_filter(BWEngine engine,int32_t type,double cutoffHz); // 0 off, 1 low, 2 band, 3 high
void bw_render(BWEngine engine,float* left,float* right,uint32_t frames,double hostSeconds);
void bw_snapshot(BWEngine engine,BWSnapshot* snapshot);
#ifdef __cplusplus
}
#endif
#endif
