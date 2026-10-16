#include "BreakwaterAudio.h"
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

extern "C" {
BWEngine legacy_create(double); void legacy_destroy(BWEngine);
int32_t legacy_load_loop(BWEngine,int32_t,const float*,int32_t,int32_t,const int32_t*,int32_t);
void legacy_queue(BWEngine,const int32_t*,int32_t); void legacy_arrange(BWEngine,const BWClip*,int32_t);
void legacy_clip_mask(BWEngine,int32_t,int32_t); void legacy_tempo(BWEngine,double); void legacy_mode(BWEngine,int32_t);
void legacy_external(BWEngine,int32_t); void legacy_midi(BWEngine,uint8_t,int32_t,double); void legacy_nudge(BWEngine,double);
BWParts legacy_create_parts(const float*,int32_t); void legacy_set_parts(BWEngine,int32_t,BWParts); void legacy_filter(BWEngine,int32_t,double);
void legacy_render(BWEngine,float*,float*,uint32_t,double); void legacy_snapshot(BWEngine,BWSnapshot*);
}
struct Engines {
 BWEngine rust,cpp;
 explicit Engines(double sr):rust(bw_create(sr)),cpp(legacy_create(sr)){assert(rust&&cpp);}
 ~Engines(){bw_destroy(rust);legacy_destroy(cpp);}
 void load(int id,const std::vector<float>& pcm,int frames,int beats,const std::vector<int32_t>& slices){
  assert(bw_load_loop(rust,id,pcm.data(),frames,beats,slices.data(),int(slices.size()))==1);
  assert(legacy_load_loop(cpp,id,pcm.data(),frames,beats,slices.data(),int(slices.size()))==1);
 }
 void parts(int id,const std::vector<float>& pcm,int frames){bw_set_parts(rust,id,bw_create_parts(pcm.data(),frames));legacy_set_parts(cpp,id,legacy_create_parts(pcm.data(),frames));}
};
static void trace(int sr){
 Engines e(sr);const int frames=sr*2;std::vector<float> pcm(frames*2),parts(frames*8);
 for(int i=0;i<frames;i++){for(int p=0;p<4;p++){float x=float(.08*std::sin((2+p*3)*6.283185307179586*i/371));for(int ch=0;ch<2;ch++)parts[p*frames*2+i*2+ch]=x*(ch?0.8f:1.f);}
  for(int ch=0;ch<2;ch++){float x=0;for(int p=0;p<4;p++)x+=parts[p*frames*2+i*2+ch];pcm[i*2+ch]=x;}}
 const std::vector<int32_t> slices{0,frames/4,frames/2,3*frames/4};
 e.load(0,pcm,frames,4,slices);e.load(1,pcm,frames,8,slices);
 int32_t ids[]{0,1};bw_queue(e.rust,ids,2);legacy_queue(e.cpp,ids,2);
 const BWClip clips[]{{0,101,0,1},{1,102,0,14},{0,103,1,15}};
 std::vector<float> rl(128),rr(128),cl(128),cr(128);double maxError=0;int stableSingleFrames=0,comparedFrames=0;
 int nextPulse=0;bool clock=false;
 for(int block=0;block<3600;block++){
  int frame=block*128;double time=double(frame)/sr;
  if(block==200){e.parts(0,parts,frames);e.parts(1,parts,frames);}
  if(block==300){bw_arrange(e.rust,clips,3);legacy_arrange(e.cpp,clips,3);}
  if(block==500){bw_clip_mask(e.rust,101,2);legacy_clip_mask(e.cpp,101,2);}
  if(block==650){bw_filter(e.rust,1,900);legacy_filter(e.cpp,1,900);}
  if(block==900){bw_tempo(e.rust,180);legacy_tempo(e.cpp,180);bw_nudge(e.rust,10);legacy_nudge(e.cpp,10);}
  if(block==1100){bw_mode(e.rust,1);legacy_mode(e.cpp,1);}
  if(block==1500){bw_mode(e.rust,0);legacy_mode(e.cpp,0);e.parts(0,parts,frames);}
  if(block==1800){bw_external(e.rust,1);legacy_external(e.cpp,1);bw_midi(e.rust,0xfa,0,time);legacy_midi(e.cpp,0xfa,0,time);nextPulse=frame;clock=true;}
  if(clock&&frame>=nextPulse&&block<3200){double tick=double(nextPulse)/sr;bw_midi(e.rust,0xf8,0,tick);legacy_midi(e.cpp,0xf8,0,tick);nextPulse+=sr/48;}
  if(block==2200){bw_nudge(e.rust,-10);legacy_nudge(e.cpp,-10);}
  if(block==2500){bw_filter(e.rust,3,2000);legacy_filter(e.cpp,3,2000);}
  bw_render(e.rust,rl.data(),rr.data(),128,time);legacy_render(e.cpp,cl.data(),cr.data(),128,time);
  BWSnapshot a{},b{};bw_snapshot(e.rust,&a);legacy_snapshot(e.cpp,&b);
  if(std::abs(a.beat-b.beat)>1e-9||std::abs(a.bpm-b.bpm)>1e-9||a.playing!=b.playing||a.activeLoop!=b.activeLoop||a.pending!=b.pending||a.activeCount!=b.activeCount||a.activeStep!=b.activeStep){std::fprintf(stderr,"State differs at sample %d\n",frame);std::abort();}
  for(int i=0;i<a.activeCount;i++)assert(a.activeTokens[i]==b.activeTokens[i]&&a.activeLoops[i]==b.activeLoops[i]);
  // The historical C++ mixer averages stacks. Compare PCM only after a
  // single-layer passage has settled; transport is checked for the full trace.
  // The separate mixer tests cover intentional changes to layered output.
  stableSingleFrames=a.activeCount==1?stableSingleFrames+128:0;
  if(stableSingleFrames>sr/5){
   for(int i=0;i<128;i++){maxError=std::max(maxError,double(std::abs(rl[i]-cl[i])));maxError=std::max(maxError,double(std::abs(rr[i]-cr[i])));}
   comparedFrames+=128;
  }
 }
 std::printf("Differential %d Hz maximum settled single-layer PCM error: %.9g (%d frames)\n",sr,maxError,comparedFrames);
 assert(comparedFrames>sr);
 assert(maxError<0.0001);
}
int main(){trace(44100);trace(48000);std::puts("Rust and reference C++ transport agree across both traces.");}
