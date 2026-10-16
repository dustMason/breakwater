#ifndef BREAKWATER_AUDIO_H
#define BREAKWATER_AUDIO_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void* BWEngine;
typedef void* BWParts;
typedef struct {
 double beat, bpm, loopProgress;
 int32_t playing, activeLoop, mode, externalClock, clockState, pending, queueCount;
 int32_t queue[64];
 uint32_t droppedCommands;
} BWSnapshot;
BWEngine bw_create(double sampleRate);
void bw_destroy(BWEngine engine);
// Load only before the audio engine starts. Audio is copied into owned memory.
int32_t bw_load_loop(BWEngine engine,int32_t id,const float* interleaved,int32_t frames,int32_t beats,const int32_t* slices,int32_t sliceCount);
// All commands must come from one serialized producer; render is the consumer.
void bw_queue(BWEngine engine,const int32_t* ids,int32_t count);
void bw_enable(BWEngine engine,int32_t id,int32_t enabled);
void bw_tempo(BWEngine engine,double bpm);
void bw_mode(BWEngine engine,int32_t mode);
void bw_external(BWEngine engine,int32_t external);
void bw_transport(BWEngine engine,int32_t action); // 0 stop, 1 start, 2 continue, 3 align next downbeat now
void bw_midi(BWEngine engine,uint8_t status,int32_t value,double hostSeconds);
void bw_offset(BWEngine engine,double milliseconds);
// Construct/decode on a worker. Install/retire on the serialized control queue.
// Parts are planar by part, then interleaved stereo, with exactly `frames` frames.
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
