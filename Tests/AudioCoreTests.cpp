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

void nudgeAgainstMidi(){
 for(int mode=0;mode<=1;mode++){
  Rig reference, nudged;
  for(Rig* r:{&reference,&nudged}){bw_mode(r->e,mode);bw_offset(r->e,40);bw_external(r->e,1);r->queue({0});bw_midi(r->e,0xfa,0,r->now);}
  auto ticks=[&](int count,int bpm){
   for(int i=0;i<count;i++){
    for(Rig* r:{&reference,&nudged}){bw_midi(r->e,0xf8,0,r->now);r->frames(1);r->seconds(60.0/(24*bpm)-1.0/48000);}
   }
  };
  ticks(120,120);
  assert(reference.snapshot().clockState==2&&nudged.snapshot().clockState==2);
  bw_nudge(nudged.e,10);double before=nudged.snapshot().beat;nudged.frames(1);reference.frames(1);
  assert(nudged.snapshot().beat>before&&nudged.snapshot().beat-before<.001);
  ticks(72,120);
  assert(std::abs((nudged.snapshot().beat-reference.snapshot().beat)-.02)<.002);
  assert(std::abs(nudged.snapshot().bpm-120)<.01);
  for(Rig* r:{&reference,&nudged})r->queue({1});
  ticks(110,120);
  assert(reference.snapshot().activeLoop==1&&nudged.snapshot().activeLoop==1);
  assert(std::abs((nudged.snapshot().beat-reference.snapshot().beat)-.02)<.002);
  ticks(120,150);
  assert(std::abs(nudged.snapshot().bpm-150)<.1);
  assert(std::abs((nudged.snapshot().beat-reference.snapshot().beat)-.025)<.003);
  bw_nudge(nudged.e,-10);ticks(72,150);
  assert(std::abs(nudged.snapshot().beat-reference.snapshot().beat)<.002);
  // During clock loss, nudging still moves smoothly; reacquiring the master
  // must not apply the same adjustment a second time.
  reference.seconds(.4);nudged.seconds(.4);assert(nudged.snapshot().clockState==3);
  bw_nudge(nudged.e,10);reference.seconds(.8);nudged.seconds(.8);
  assert(std::abs((nudged.snapshot().beat-reference.snapshot().beat)-.025)<.003);
  ticks(96,150);
  assert(nudged.snapshot().clockState==2);
  assert(std::abs((nudged.snapshot().beat-reference.snapshot().beat)-.025)<.003);
  for(Rig* r:{&reference,&nudged}){bw_midi(r->e,0xfc,0,r->now);r->frames(1);r->seconds(.2);bw_midi(r->e,0xfb,0,r->now);}
  ticks(96,150);
  assert(nudged.snapshot().clockState==2);
  assert(std::abs((nudged.snapshot().beat-reference.snapshot().beat)-.025)<.003);
  assert(nudged.snapshot().droppedCommands==0);
 }
 puts("PASS nudge follows MIDI phase smoothly through pad changes, tempo changes and freewheel");
}

void nudgeInternal(){
 Rig reference,nudged;reference.queue({0});nudged.queue({0});reference.seconds(.5);nudged.seconds(.5);
 bw_nudge(nudged.e,10);reference.frames(1);nudged.frames(1);
 assert(nudged.snapshot().beat-reference.snapshot().beat<.001);
 reference.seconds(1);nudged.seconds(1);
 assert(std::abs((nudged.snapshot().beat-reference.snapshot().beat)-.02)<.001);
 bw_nudge(nudged.e,-10);reference.seconds(1);nudged.seconds(1);
 assert(std::abs(nudged.snapshot().beat-reference.snapshot().beat)<.001);
 puts("PASS internal-clock nudge advances and delays without jumping");
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
 assert(amplitude(1000)<.005); // Three selected estimates must not retain original-only residuals.
 bw_part_mask(e,0,3);bw_render(e,l.data(),r.data(),48000,11.25);assert(amplitude(180)>.07);assert(amplitude(600)>.07);assert(amplitude(1000)<.005);assert(amplitude(2400)<.005);
 bw_part_mask(e,0,1);bw_render(e,l.data(),r.data(),48000,11.5);assert(amplitude(180)>.07);assert(amplitude(1000)<.005);
 bw_part_mask(e,0,0);bw_render(e,l.data(),r.data(),48000,12);for(int i=1000;i<48000;i++)assert(std::abs(l[i])<1e-6);
 bw_part_mask(e,0,15);bw_render(e,l.data(),r.data(),48000,13);assert(amplitude(180)>.07);assert(amplitude(1000)>.025);
 for(int i=0;i<80;i++){bw_filter(e,i%4,40*std::pow(450.0,(i%17)/16.0));bw_render(e,l.data(),r.data(),256,14+i*256.0/48000);for(int j=0;j<256;j++)assert(std::isfinite(l[j])&&std::abs(l[j])<2);}
 bw_set_parts(e,0,nullptr);bw_render(e,l.data(),r.data(),256,15);bw_destroy(e);
 auto level=[&](int mode,int hz){BWEngine f=bw_create(48000);std::vector<float> tone(frames*2);for(int i=0;i<frames;i++)tone[i*2]=tone[i*2+1]=float(.5*std::sin(2*pi*hz*i/48000));assert(bw_load_loop(f,0,tone.data(),frames,4,&slice,1));bw_filter(f,mode,1000);bw_queue(f,&id,1);std::vector<float>a(48000),b(48000);bw_render(f,a.data(),b.data(),48000,20);double rms=0;for(int i=24000;i<48000;i++)rms+=a[i]*a[i];bw_destroy(f);return std::sqrt(rms/24000);};
 assert(level(1,200)>10*level(1,6000));assert(level(3,6000)>10*level(3,200));assert(level(2,1000)>4*level(2,100));
 puts("PASS separated-part mute/fade/restore and low/band/high output filtering");
}
void layeredArrangement(){
 Rig r;BWClip initial[]={{0,101,0,15},{1,102,0,15},{2,103,1,15}};
 bw_arrange(r.e,initial,3);r.frames(1);auto s=r.snapshot();assert(s.playing&&s.activeCount==2&&s.activeTokens[0]==101&&s.activeTokens[1]==102);
 r.untilBeat(7.99);s=r.snapshot();assert(s.activeCount==2&&s.activeLoop==0&&s.activeStep==0);
 r.untilBeat(8.01);s=r.snapshot();assert(s.activeCount==1&&s.activeLoop==2&&s.activeStep==1);
 r.untilBeat(12.01);assert(r.snapshot().activeCount==2);
 BWClip edited[]={{0,101,0,15},{1,102,1,15},{2,103,1,15}};
 r.untilBeat(13);bw_arrange(r.e,edited,3);r.frames(1);assert(r.snapshot().pending&&r.snapshot().activeCount==2);
 r.untilBeat(15.99);assert(r.snapshot().activeCount==2);r.untilBeat(16.01);assert(r.snapshot().activeCount==1&&r.snapshot().activeTokens[0]==101);
 r.untilBeat(20.01);assert(r.snapshot().activeCount==2&&r.snapshot().activeTokens[0]==102);
 bw_enable(r.e,1,0);r.frames(1);assert(r.snapshot().pending);r.untilBeat(24.01);assert(r.snapshot().activeCount==1&&r.snapshot().activeLoop==2);
 puts("PASS layered steps repeat shorter loops, sequence full phrases and apply edits at the next bar");
}
void futureStepPreservesCurrentPhrase(){
 Rig r;BWClip initial[]={{1,101,0,15}};bw_arrange(r.e,initial,1);r.frames(1);r.untilBeat(1);
 BWClip edited[]={{1,101,0,15},{0,102,1,15}};bw_arrange(r.e,edited,2);
 r.untilBeat(4.01);assert(r.snapshot().activeTokens[0]==101&&r.snapshot().activeProgress[0]>.49);
 r.untilBeat(8.01);assert(r.snapshot().activeTokens[0]==102);
 puts("PASS editing a future step preserves the current phrase and its end");
}
void editingStoppedArrangement(){
 Rig r;BWClip initial[]={{0,101,0,15},{1,102,1,15}};bw_arrange(r.e,initial,2);r.frames(1);
 bw_transport(r.e,0);r.frames(1);BWClip edited[]={{1,102,0,15}};bw_edit_arrangement(r.e,edited,1);r.seconds(.1);
 assert(!r.snapshot().playing&&r.snapshot().pending);
 bw_transport(r.e,2);r.frames(1);assert(r.snapshot().playing&&r.snapshot().activeTokens[0]==102);
 Rig external;bw_external(external.e,1);bw_arrange(external.e,initial,2);external.frames(1);
 bw_edit_arrangement(external.e,nullptr,0);external.frames(1);bw_midi(external.e,0xfa,0,external.now);external.frames(1);
 assert(external.snapshot().activeLoop<0&&external.snapshot().activeCount==0);
 puts("PASS stopped edits stay stopped and clearing a MIDI-pending arrangement prevents stale playback");
}
void independentClipParts(){
 constexpr int frames=96000;const double pi=3.141592653589793;const int frequencies[4]={180,600,2400,7000};
 std::vector<float> pcm(frames*2),parts(frames*8),l(48000),r(48000);
 for(int i=0;i<frames;i++)for(int p=0;p<4;p++){float v=float(.1*std::sin(2*pi*frequencies[p]*i/48000));for(int ch=0;ch<2;ch++){parts[p*frames*2+i*2+ch]=v;pcm[i*2+ch]+=v;}}
 auto e=bw_create(48000);int32_t slice=0;assert(bw_load_loop(e,7,pcm.data(),frames,4,&slice,1));bw_set_parts(e,7,bw_create_parts(parts.data(),frames));
 BWClip clips[]={{7,201,0,1},{7,202,0,2}};bw_arrange(e,clips,2);bw_render(e,l.data(),r.data(),48000,10);
 auto amplitude=[&](int hz){double a=0,b=0;for(int i=2000;i<48000;i++){a+=l[i]*std::sin(2*pi*hz*i/48000);b+=l[i]*std::cos(2*pi*hz*i/48000);}return 2*std::hypot(a,b)/46000;};
 assert(amplitude(180)>.035&&amplitude(600)>.035);
 bw_clip_mask(e,201,0);bw_render(e,l.data(),r.data(),48000,11);assert(amplitude(180)<.002&&amplitude(600)>.035);
 bw_clip_mask(e,202,0);bw_clip_mask(e,201,1);bw_render(e,l.data(),r.data(),48000,12);assert(amplitude(180)>.035&&amplitude(600)<.002);
 bw_destroy(e);puts("PASS repeated copies have independent part controls");
}
void independentClipLevels(){
 constexpr int frames=96000;int32_t slice=0;
 std::vector<float> pcm(frames*2,.4f),l(5000),r(5000);
 auto e=bw_create(48000);assert(bw_load_loop(e,7,pcm.data(),frames,4,&slice,1));
 BWClipWithLevel clips[]={{7,201,0,15,0,1200,1000},{7,202,0,15,0,1200,250}};
 bw_arrange_with_levels(e,clips,2);bw_render(e,l.data(),r.data(),5000,10);
 const float expected=.4f*1.25f/std::sqrt(1.f+.25f*.25f)*.8f;
 assert(std::abs(l.back()-expected)<1e-5f&&std::abs(r.back()-expected)<1e-5f);
 float before=l.back();bw_clip_level(e,201,0);bw_render(e,l.data(),r.data(),5000,10+5000.0/48000);
 assert(std::abs(l.front()-before)<.001f&&std::abs(l.back()-.08f)<1e-5f);
 bw_clip_level(e,202,1);bw_render(e,l.data(),r.data(),5000,10+10000.0/48000);
 assert(std::abs(l.back()-.32f)<1e-5f);
 bw_destroy(e);puts("PASS per-clip levels are independent and change smoothly");
}
void layeredWrapFade(){
 auto e=bw_create(48000);int32_t slice=0;std::vector<float> shortPCM(96000*2),longPCM(192000*2,0);
 for(int i=0;i<96000;i++)shortPCM[i*2]=shortPCM[i*2+1]=i<48000?.6f:-.6f;
 assert(bw_load_loop(e,0,shortPCM.data(),96000,4,&slice,1));assert(bw_load_loop(e,1,longPCM.data(),192000,8,&slice,1));
 BWClip clips[]={{0,1,0,15},{1,2,0,15}};bw_arrange(e,clips,2);
 std::vector<float> l(95000),r(95000);bw_render(e,l.data(),r.data(),95000,10);float previous=l.back();
 l.resize(2000);r.resize(2000);bw_render(e,l.data(),r.data(),2000,10+95000.0/48000);
 float maxJump=0;for(float sample:l){maxJump=std::max(maxJump,std::abs(sample-previous));previous=sample;}
 assert(maxJump<.01);bw_destroy(e);puts("PASS shorter layered loops crossfade their wrap");
}
void layeredMidi(){
 Rig r;bw_external(r.e,1);BWClip clips[]={{0,1,0,15},{1,2,0,15},{2,3,1,15}};bw_arrange(r.e,clips,3);r.frames(1);
 bw_midi(r.e,0xfa,0,r.now);double next=r.now;bool advanced=false;
 for(int tick=0;tick<260;tick++){
  r.seconds(std::max(0.0,next-r.now));bw_midi(r.e,0xf8,0,next);r.frames(1);
  if(tick==80)bw_nudge(r.e,10);
  auto s=r.snapshot();if(s.beat>1&&s.beat<7.8)assert(s.activeCount==2&&s.activeTokens[0]==1&&s.activeTokens[1]==2);
  if(s.beat>8.2){assert(s.activeCount==1&&s.activeTokens[0]==3);advanced=true;}
  next+=60.0/(24*(tick<150?120:145));
 }
 assert(advanced&&r.snapshot().clockState==2&&std::abs(r.snapshot().bpm-145)<1);puts("PASS layered sequence follows MIDI tempo and nudge");
}
int main(){layeredArrangement();futureStepPreservesCurrentPhrase();editingStoppedArrangement();independentClipParts();independentClipLevels();layeredWrapFade();layeredMidi();nudgeInternal();nudgeAgainstMidi();partsAndFilters();missingFirstClock();positionWithinPhrase();queuedExclusion();midiContinue();midiBarReplacement();barQueueAndCycle();exclusions();tempoChanges();clockLock();pitchModes();stopStart();puts("All audio-core tests passed.");}
