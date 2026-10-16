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
void midiBarReplacement(){
 Rig r;bw_external(r.e,1);r.queue({0});bw_midi(r.e,0xfa,0,r.now);double next=r.now;
 bool firstQueued=false,firstPlayed=false,secondQueued=false,secondPlayed=false;
 for(int tick=0;tick<24*10;tick++){
  r.seconds(std::max(0.0,next-r.now));bw_midi(r.e,0xf8,0,next);r.frames(1);auto s=r.snapshot();
  if(!firstQueued&&s.beat>1){r.queue({1});firstQueued=true;}
  if(firstQueued&&s.beat<3.9)assert(r.snapshot().activeLoop==0);
  if(firstQueued&&s.beat>4.1&&!firstPlayed){assert(s.activeLoop==1);firstPlayed=true;}
  if(firstPlayed&&!secondQueued&&s.beat>5){r.queue({2});secondQueued=true;}
  if(secondQueued&&s.beat<7.9)assert(r.snapshot().activeLoop==1);
  if(secondQueued&&s.beat>8.1&&!secondPlayed){assert(s.activeLoop==2);secondPlayed=true;}
  next+=60.0/(24*120);
 }
 assert(firstPlayed&&secondPlayed);puts("PASS single-tap replacements reach the next bar while MIDI clock stays locked");
}

void partsAndFilters(){
 constexpr int frames=96000; const double pi=3.141592653589793; const int frequencies[4]={180,600,2400,7000};
 std::vector<float> pcm(frames*2),parts(frames*8);
 for(int i=0;i<frames;i++)for(int p=0;p<4;p++){float v=float(.1*std::sin(2*pi*frequencies[p]*i/48000));for(int ch=0;ch<2;ch++){parts[p*frames*2+i*2+ch]=v;pcm[i*2+ch]+=v;}}
 // Simulate the difference between lossy encoded parts and the original.
 for(int i=0;i<frames;i++)for(int ch=0;ch<2;ch++)pcm[i*2+ch]+=float(.04*std::sin(2*pi*1000*i/48000));
 int32_t slice=0,id=0;BWEngine e=bw_create(48000);assert(bw_load_loop(e,0,pcm.data(),frames,4,&slice,1));
 bw_set_parts(e,0,bw_create_parts(parts.data(),frames));bw_queue(e,&id,1);
 std::vector<float> l(48000),r(48000);bw_render(e,l.data(),r.data(),48000,10);
 bw_part_mask(e,0,14);bw_render(e,l.data(),r.data(),48000,11);
 auto amplitude=[&](int hz){double a=0,b=0;for(int i=2000;i<48000;i++){a+=l[i]*std::sin(2*pi*hz*i/48000);b+=l[i]*std::cos(2*pi*hz*i/48000);}return 2*std::hypot(a,b)/46000;};
 assert(amplitude(180)<.005);assert(amplitude(600)>.07);
 bw_part_mask(e,0,1);bw_render(e,l.data(),r.data(),48000,11.5);assert(amplitude(180)>.07);assert(amplitude(1000)<.005);
 bw_part_mask(e,0,0);bw_render(e,l.data(),r.data(),48000,12);for(int i=1000;i<48000;i++)assert(std::abs(l[i])<1e-6);
 bw_part_mask(e,0,15);bw_render(e,l.data(),r.data(),48000,13);assert(amplitude(180)>.07);assert(amplitude(1000)>.025);
 for(int i=0;i<80;i++){bw_filter(e,i%4,40*std::pow(450.0,(i%17)/16.0));bw_render(e,l.data(),r.data(),256,14+i*256.0/48000);for(int j=0;j<256;j++)assert(std::isfinite(l[j])&&std::abs(l[j])<2);}
 bw_set_parts(e,0,nullptr);bw_render(e,l.data(),r.data(),256,15);bw_destroy(e);
 auto level=[&](int mode,int hz){BWEngine f=bw_create(48000);std::vector<float> tone(frames*2);for(int i=0;i<frames;i++)tone[i*2]=tone[i*2+1]=float(.5*std::sin(2*pi*hz*i/48000));assert(bw_load_loop(f,0,tone.data(),frames,4,&slice,1));bw_filter(f,mode,1000);bw_queue(f,&id,1);std::vector<float>a(48000),b(48000);bw_render(f,a.data(),b.data(),48000,20);double rms=0;for(int i=24000;i<48000;i++)rms+=a[i]*a[i];bw_destroy(f);return std::sqrt(rms/24000);};
 assert(level(1,200)>10*level(1,6000));assert(level(3,6000)>10*level(3,200));assert(level(2,1000)>4*level(2,100));
 puts("PASS separated-part mute/fade/restore and low/band/high output filtering");
}
int main(){partsAndFilters();missingFirstClock();positionWithinPhrase();queuedExclusion();midiContinue();midiBarReplacement();barQueueAndCycle();exclusions();tempoChanges();clockLock();pitchModes();stopStart();puts("All audio-core tests passed.");}
