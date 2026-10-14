#include "BreakwaterAudio.h"
#include <cassert>
#include <cmath>
#include <cstdio>
#include <vector>
#include <algorithm>
struct Rig {
 BWEngine e=bw_create(48000);double now=10;std::vector<float> l,r;
 Rig(){for(int id=0;id<3;id++){int beats=id==1?8:4;int frames=24000*beats;std::vector<float> pcm(frames*2);for(int i=0;i<frames;i++)pcm[i*2]=pcm[i*2+1]=float(.4*std::sin(2*3.141592653589793*440*i/48000));std::vector<int32_t> slices;for(int i=0;i<frames;i+=12000)slices.push_back(i);assert(bw_load_loop(e,id,pcm.data(),frames,beats,slices.data(),int(slices.size())));}}
 ~Rig(){bw_destroy(e);}
 BWSnapshot snapshot(){BWSnapshot s{};bw_snapshot(e,&s);return s;}
 void frames(int n){l.resize(n);r.resize(n);bw_render(e,l.data(),r.data(),n,now);now+=n/48000.0;for(float v:l)assert(std::isfinite(v)&&std::abs(v)<=1);}
 void seconds(double sec){int n=int(std::round(sec*48000));while(n){int part=std::min(256,n);frames(part);n-=part;}}
 void untilBeat(double beat){int watchdog=0;while(snapshot().beat<beat){frames(1);assert(++watchdog<48000*60);}}
 void queue(std::initializer_list<int32_t> q){std::vector<int32_t> ids(q);bw_queue(e,ids.data(),int(ids.size()));frames(1);}
};
void barQueueAndCycle(){Rig r;r.queue({0});r.seconds(.25);assert(r.snapshot().activeLoop==0);r.queue({1});r.untilBeat(3.999);assert(r.snapshot().activeLoop==0);r.untilBeat(4.001);assert(r.snapshot().activeLoop==1);r.untilBeat(12.01);assert(r.snapshot().activeLoop==1);r.queue({2,0});r.untilBeat(16.01);assert(r.snapshot().activeLoop==2);r.untilBeat(20.01);assert(r.snapshot().activeLoop==0);r.untilBeat(24.01);assert(r.snapshot().activeLoop==2);r.queue({1});r.untilBeat(28.01);assert(r.snapshot().activeLoop==1);puts("PASS next-bar replacement, full-length cycling, latched replacement");}
void exclusions(){Rig r;r.queue({0,2});bw_enable(r.e,2,0);r.seconds(4.1);assert(r.snapshot().activeLoop==0);bw_enable(r.e,0,0);r.untilBeat(11.99);r.seconds(.02);assert(!r.snapshot().playing);r.queue({0,2});assert(!r.snapshot().playing);bw_enable(r.e,2,1);r.queue({2});assert(r.snapshot().playing&&r.snapshot().activeLoop==2);puts("PASS excluded pads skipped; all-excluded cycle stops; restore works");}
void tempoChanges(){Rig r;r.queue({0});r.seconds(3);double before=r.snapshot().beat;bw_tempo(r.e,180);r.frames(1);assert(r.snapshot().beat>before&&r.snapshot().beat-before<.001);r.seconds(2);assert(std::abs(r.snapshot().bpm-180)<.01);bw_tempo(r.e,60);r.seconds(2);assert(std::abs(r.snapshot().bpm-60)<.01);assert(r.snapshot().droppedCommands==0);puts("PASS tempo smoothing, continuous beat position");}
void clockLock(){Rig r;bw_external(r.e,1);r.queue({0});assert(!r.snapshot().playing);bw_midi(r.e,0xfa,0,r.now);double next=r.now;double expectedBeat=0;double previous=0;
 for(int tick=0;tick<24*4*80;tick++){
  double bpm=tick<24*4*40?120:145;double interval=60/(24*bpm);
  r.seconds(std::max(0.0,next-r.now));double jitter=(tick%5-2)*.0003;bw_midi(r.e,0xf8,0,next+jitter);r.frames(1);
  if(tick>30){assert(r.snapshot().beat>=previous);}
  previous=r.snapshot().beat;expectedBeat=tick/24.0;
  next+=interval;
 }
 auto s=r.snapshot();assert(s.clockState==2);assert(std::abs(s.bpm-145)<1);assert(std::abs(s.beat-expectedBeat)<.09);r.seconds(.4);assert(r.snapshot().clockState==3&&r.snapshot().playing);r.seconds(2);assert(r.snapshot().clockState==4&&!r.snapshot().playing);puts("PASS MIDI clock jitter, tempo change, phase lock, freewheel and timeout");}
void pitchModes(){
 auto frequency=[](int mode){Rig r;bw_mode(r.e,mode);bw_tempo(r.e,90);r.queue({0});r.seconds(3);std::vector<float> audio;for(int i=0;i<100;i++){r.frames(256);audio.insert(audio.end(),r.l.begin(),r.l.end());}int crossings=0;for(size_t i=1;i<audio.size();i++)if(audio[i-1]<0&&audio[i]>=0)crossings++;return crossings*48000.0/audio.size();};
 double tape=frequency(0),slice=frequency(1);assert(std::abs(tape-330)<5);assert(std::abs(slice-440)<12);printf("PASS rate-vs-slice pitch: tape %.1f Hz; slice %.1f Hz (source 440 Hz)\n",tape,slice);
}
void stopStart(){Rig r;r.queue({0});r.seconds(.5);bw_transport(r.e,0);r.seconds(.02);assert(!r.snapshot().playing);for(float x:r.l)assert(x==0);double b=r.snapshot().beat;r.seconds(.1);assert(r.snapshot().beat==b);bw_transport(r.e,2);r.seconds(.05);assert(r.snapshot().playing);puts("PASS stop fade and resume");}
void queuedExclusion(){Rig r;r.queue({0});r.seconds(.3);r.queue({1});bw_enable(r.e,1,0);r.seconds(2);assert(r.snapshot().playing&&r.snapshot().activeLoop==0);r.queue({2});bw_enable(r.e,0,0);r.untilBeat(8.01);assert(r.snapshot().activeLoop==2);r.queue({0});r.seconds(2.1);assert(r.snapshot().activeLoop==2);puts("PASS disabling a queued pad preserves current playback; disabling active preserves valid pending replacement");}
void midiContinue(){Rig r;bw_external(r.e,1);r.queue({1});bw_midi(r.e,0xfa,0,r.now);r.seconds(.7);bw_midi(r.e,0xfc,0,r.now);r.frames(1);auto a=r.snapshot();r.seconds(.2);bw_midi(r.e,0xfb,0,r.now);r.frames(1);auto b=r.snapshot();assert(std::abs(b.loopProgress-a.loopProgress)<.001);assert(std::abs(b.beat-a.beat)<.001);bw_midi(r.e,0xf2,32,r.now);r.frames(1);assert(std::abs(r.snapshot().beat-8)<.001);puts("PASS MIDI Continue keeps phrase phase; Song Position Pointer seeks correctly");}
void missingFirstClock(){Rig r;bw_external(r.e,1);r.queue({0});bw_midi(r.e,0xfa,0,r.now);r.seconds(2.1);assert(!r.snapshot().playing&&r.snapshot().clockState==4);puts("PASS external Start without any clocks times out safely");}
void positionWithinPhrase(){Rig r;bw_external(r.e,1);r.queue({1});bw_midi(r.e,0xfa,0,r.now);r.frames(1);bw_midi(r.e,0xf2,20,r.now);r.frames(1);assert(std::abs(r.snapshot().loopProgress-.625)<.001);puts("PASS Song Position Pointer preserves position inside a multi-bar phrase");}
int main(){missingFirstClock();positionWithinPhrase();queuedExclusion();midiContinue();barQueueAndCycle();exclusions();tempoChanges();clockLock();pitchModes();stopStart();puts("All audio-core tests passed.");}
