#include "BreakwaterAudio.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <vector>

namespace {
constexpr int maxLoops=1024, maxQueue=64, ringSize=4096;
struct Parts { std::vector<float> pcm; int frames=0; };
struct Loop {
 std::vector<float> pcm; std::vector<int> slices; int frames=0,beats=4;
 std::atomic<Parts*> parts{nullptr}; int partMask=15; std::array<float,4> partGain{1,1,1,1};
 float partBlend=0, audible=1;
};
struct Stereo { float l=0,r=0; Stereo operator*(double a) const{return {float(l*a),float(r*a)};} Stereo operator+(Stereo b)const{return{l+b.l,r+b.r};} };
struct Command { int type=0,value=0,count=0; double number=0,time=0; std::array<int,maxQueue> ids{}; };
enum { Queue,Enable,Tempo,Mode,External,Transport,MIDI,Offset,Nudge,PartMask,Filter };
struct Voice {
 Loop* loop=nullptr; int mode=0,slice=-1,previousSlice=-1; double position=0,oldPosition=0,localBeat=0,rate=1; int fade=0;
 Stereo at(double index)const {
  if(!loop||loop->frames<2)return{};
  index=std::clamp(index,0.0,double(loop->frames-1));int a=int(index),b=std::min(a+1,loop->frames-1);double f=index-a;
  Stereo out{float(loop->pcm[a*2]*(1-f)+loop->pcm[b*2]*f),float(loop->pcm[a*2+1]*(1-f)+loop->pcm[b*2+1]*f)};
  if(auto* parts=loop->parts.load(std::memory_order_acquire)){
   // For a solo layer, avoid leaving the AAC reconstruction residual from
   // three subtracted layers behind. At two or more, retain the original mix
   // minus muted layers. Interpolating the residual keeps changes continuous.
   float sum=0;for(float gain:loop->partGain)sum+=gain;
   float originalWeight=std::clamp(sum-1.0f,0.0f,1.0f);
   out=out*(1-loop->partBlend+loop->partBlend*originalWeight);
   for(int p=0;p<4;p++){
    float amount=(loop->partGain[p]-originalWeight)*loop->partBlend;
    if(amount==0)continue;
    const auto base=size_t(p)*loop->frames*2;
    out.l+=amount*float(parts->pcm[base+a*2]*(1-f)+parts->pcm[base+b*2]*f);
    out.r+=amount*float(parts->pcm[base+a*2+1]*(1-f)+parts->pcm[base+b*2+1]*f);
   }
  }
  return out*loop->audible;
 }
 Stereo sliceAt(int index,double elapsed,double sr)const {
  if(index<0||!loop)return{};
  int start=loop->slices[index];int end=index+1<int(loop->slices.size())?loop->slices[index+1]:loop->frames;
  int length=end-start;if(length<=1)return{};
  // Attacks play at the original sample rate. Slow tempos extend only the
  // decaying end of the slice with a short crossfaded tail, never the attack.
  if(elapsed<length)return at(start+elapsed);
  int grain=std::min(int(sr*.035),length/2),blend=std::min(int(sr*.004),grain/4);
  if(grain<16)return{};
  double tail=elapsed-length,phase=std::fmod(tail,double(grain-blend));
  Stereo result=at(end-grain+phase);
  if(phase<blend){double f=phase/blend;result=at(end-blend+phase)*(1-f)+result*f;}
  double decay=std::exp(-tail/(sr*.075));
  return result*decay;
 }
 void begin(Loop* l,int m,double phase=0) {
  loop=l;mode=m;localBeat=phase;position=l?phase/l->beats*l->frames:0;slice=previousSlice=-1;fade=0;
  if(l&&m==1){for(int i=0;i<int(l->slices.size());i++)if(double(l->slices[i])/l->frames*l->beats<=phase)slice=i;
   if(slice<0)slice=0;position=phase/l->beats*l->frames-l->slices[slice];}
 }
 Stereo render(double phase,double deltaBeat,double sr) {
  if(!loop)return{};localBeat=phase;rate=deltaBeat/loop->beats*loop->frames;
  if(mode==0){double p=phase/loop->beats*loop->frames;return at(p);}
  int wanted=slice;
  while(wanted+1<int(loop->slices.size())&&double(loop->slices[wanted+1])/loop->frames*loop->beats<=phase+1e-10)wanted++;
  if(wanted!=slice){previousSlice=slice;oldPosition=position;slice=wanted;position=0;fade=int(sr*.002);}
  Stereo sample=sliceAt(slice,position++,sr);
  if(fade>0&&previousSlice>=0){double f=double(fade)/(sr*.002);sample=sample*(1-f)+sliceAt(previousSlice,oldPosition++,sr)*f;fade--;}
  return sample;
 }
 Stereo continueTail(double deltaBeat,double sr){localBeat+=deltaBeat;return render(localBeat,deltaBeat,sr);}
};
// A smoothed biquad; bypass and coefficient changes fade without changing phase.
struct OutputFilter {
 double sr,slew; int type=0; double cutoff=1200;
 std::array<double,5> current{1,0,0,0,0},target{1,0,0,0,0};
 std::array<double,2> z1{},z2{}; double mix=0;
 explicit OutputFilter(double rate):sr(rate),slew(1-std::exp(-1/(rate*.012))){}
 void set(int kind,double hz){
  type=std::clamp(kind,0,3); cutoff=std::clamp(hz,20.0,sr*.45);
  if(!type)return;
  double omega=2*3.141592653589793*cutoff/sr, c=std::cos(omega), a=std::sin(omega)/(2*.7071067811865476), d=1+a;
  if(type==1)target={(1-c)/(2*d),(1-c)/d,(1-c)/(2*d),-2*c/d,(1-a)/d};
  else if(type==2)target={a/d,0,-a/d,-2*c/d,(1-a)/d};
  else target={(1+c)/(2*d),-(1+c)/d,(1+c)/(2*d),-2*c/d,(1-a)/d};
 }
 Stereo process(Stereo input){
  for(int i=0;i<5;i++)current[i]+=(target[i]-current[i])*slew;
  mix+=((type?1.0:0.0)-mix)*slew;
  double in[2]={input.l,input.r},out[2];
  for(int i=0;i<2;i++){double y=current[0]*in[i]+z1[i];z1[i]=current[1]*in[i]-current[3]*y+z2[i];z2[i]=current[2]*in[i]-current[4]*y;out[i]=in[i]+mix*(y-in[i]);}
  return {float(out[0]),float(out[1])};
 }
};
struct Engine {
 double sr,beat=0,bpm=120,targetBPM=120,clockBPM=120,offset=0,nudgeOffset=0,nudgeRemaining=0;
 std::array<Loop,maxLoops> loops; std::array<bool,maxLoops> enabled;
 std::array<Command,ringSize> commands;std::atomic<uint32_t> head{0},tail{0},dropped{0};
 std::array<int,maxQueue> cycle{},pendingIDs{};int cycleCount=0,cyclePos=0,pendingCount=0;
 bool pending=false,running=false,external=false,haveTick=false,transportClock=false;
 int active=-1,mode=0,clockState=0,intervalCount=0,intervalIndex=0;double startBeat=0,nextBar=4,lastTick=-1,clockPulse=-1;
 std::array<double,12> intervals{};
 Voice voice,outgoing;int transition=0;float gain=0; OutputFilter filter;
 std::atomic<uint64_t> completedBlocks{0};
 struct Retired { Parts* parts; uint64_t epoch; }; std::vector<Retired> retired;
 std::atomic<double> snapBeat{0},snapBPM{120},snapProgress{0};
 std::atomic<int> snapPlaying{0},snapActive{-1},snapMode{0},snapExternal{0},snapClock{0},snapPending{0},snapCount{0};
 std::array<std::atomic<int>,maxQueue> snapQueue{};
 explicit Engine(double s):sr(s),filter(s){enabled.fill(true);}
 ~Engine(){for(auto& l:loops)delete l.parts.load();for(auto& r:retired)delete r.parts;}
 void setParts(int id,Parts* next){
  if(id<0||id>=maxLoops||(next&&next->frames!=loops[id].frames)){delete next;return;}
  auto* old=loops[id].parts.exchange(next,std::memory_order_acq_rel);
  if(old)retired.push_back({old,completedBlocks.load(std::memory_order_acquire)});
  auto epoch=completedBlocks.load(std::memory_order_acquire);
  retired.erase(std::remove_if(retired.begin(),retired.end(),[&](Retired r){if(epoch>r.epoch){delete r.parts;return true;}return false;}),retired.end());
 }
 void advanceParts(Loop* l){if(!l)return;float step=float(1/(sr*.008));
  for(int p=0;p<4;p++){float wanted=(l->partMask&(1<<p))?1:0;l->partGain[p]+=std::clamp(wanted-l->partGain[p],-step,step);}
  float wanted=l->parts.load(std::memory_order_acquire)?1:0;l->partBlend+=std::clamp(wanted-l->partBlend,-step,step);
  wanted=l->partMask?1:0;l->audible+=std::clamp(wanted-l->audible,-step,step);
 }
 bool valid(int id)const{return id>=0&&id<maxLoops&&enabled[id]&&loops[id].frames>0;}
 void push(Command c){auto h=head.load(std::memory_order_relaxed),n=(h+1)%ringSize;if(n==tail.load(std::memory_order_acquire)){dropped.fetch_add(1);return;}commands[h]=c;head.store(n,std::memory_order_release);}
 void launch(int id,double atBeat){outgoing=voice;transition=int(sr*.005);active=id;startBeat=atBeat;voice.begin(valid(id)?&loops[id]:nullptr,mode);}
 void applyPending(double atBeat){cycleCount=0;for(int i=0;i<pendingCount;i++)if(valid(pendingIDs[i]))cycle[cycleCount++]=pendingIDs[i];cyclePos=0;pending=false;
  if(cycleCount)launch(cycle[0],atBeat);else{running=false;active=-1;} }
 void cleanQueue(){int count=0;for(int i=0;i<cycleCount;i++)if(valid(cycle[i]))cycle[count++]=cycle[i];cycleCount=count;cyclePos=0;for(int i=0;i<count;i++)if(cycle[i]==active)cyclePos=i;
  count=0;for(int i=0;i<pendingCount;i++)if(valid(pendingIDs[i]))pendingIDs[count++]=pendingIDs[i];pendingCount=count;
  if(pending&&pendingCount==0&&valid(active))pending=false;
  if(active>=0&&!valid(active)&&!pending){pending=true;pendingCount=cycleCount;std::copy_n(cycle.begin(),cycleCount,pendingIDs.begin());}}
 void start(bool reset){if(reset){beat=0;nextBar=4;startBeat=0;clockPulse=-1;}
  if(pending)applyPending(beat);else if(!reset&&valid(active)){outgoing=voice;transition=int(sr*.005);voice.begin(&loops[active],mode,std::max(0.0,beat-startBeat));}else if(cycleCount){cyclePos=0;launch(cycle[0],beat);}else if(valid(active))launch(active,beat);
  running=true;transportClock=true;}
 void midi(int status,int value,double time){
  if(!external)return;
  if(status==0xf8){
   if(lastTick>=0){double dt=time-lastTick;if(dt>.005&&dt<.15){intervals[intervalIndex++%12]=dt;intervalCount=std::min(intervalCount+1,12);double total=0;for(int i=0;i<intervalCount;i++)total+=intervals[i];clockBPM=std::clamp(60*intervalCount/(24*total),30.0,300.0);targetBPM=clockBPM;}}
   lastTick=time;haveTick=true;if(transportClock)clockPulse+=1;clockState=intervalCount>=3?2:1;
  }else if(status==0xfa){start(true);lastTick=time;haveTick=true;intervalCount=0;intervalIndex=0;clockState=1;}
  else if(status==0xfc){running=false;transportClock=false;}
  else if(status==0xfb){clockPulse=std::round((beat-(offset+nudgeOffset)*clockBPM/60)*24)-1;start(false);lastTick=time;haveTick=true;}
  else if(status==0xf2){beat=value*.25;clockPulse=beat*24-1;nextBar=(std::floor(beat/4)+1)*4;
   if(valid(active)){startBeat=std::floor(beat/loops[active].beats)*loops[active].beats;voice.begin(&loops[active],mode,beat-startBeat);}else startBeat=beat;}
 }
 void consume(){auto t=tail.load(std::memory_order_relaxed);const auto h=head.load(std::memory_order_acquire);while(t!=h){const auto& c=commands[t];
  switch(c.type){
   case Queue:pendingCount=0;for(int i=0;i<c.count;i++)if(valid(c.ids[i]))pendingIDs[pendingCount++]=c.ids[i];if(!pendingCount)break;pending=true;
    if(!running&&!external){applyPending(beat);if(active>=0){running=true;nextBar=(std::floor(beat/4)+1)*4;}}break;
   case Enable:if(c.value>=0&&c.value<maxLoops){enabled[c.value]=c.number!=0;cleanQueue();}break;
   case Tempo:if(!external)targetBPM=std::clamp(c.number,30.0,300.0);break;
   case Mode:if(mode!=c.value){mode=c.value?1:0;outgoing=voice;transition=int(sr*.005);if(active>=0)voice.begin(&loops[active],mode,std::max(0.0,beat-startBeat));}break;
   case External:external=c.value;haveTick=false;lastTick=-1;clockPulse=-1;intervalCount=0;intervalIndex=0;clockState=external?1:0;transportClock=false;nudgeOffset=0;nudgeRemaining=0;if(external)running=false;break;
   case Transport:if(c.value==0){running=false;transportClock=false;}else if(c.value==1){start(true);}else if(c.value==2){start(false);}else{beat=0;nextBar=4;clockPulse=-1;haveTick=false;if(active>=0)launch(active,0);}break;
   case MIDI:midi(c.value,c.count,c.time);break;
   case Offset:offset=std::clamp(c.number,-200.0,200.0)/1000;break;
   case Nudge:if(running&&active>=0&&std::isfinite(c.number)){
    double step=std::clamp(c.number,-100.0,100.0)/1000;
    if(external){double target=std::clamp(nudgeOffset+step,-2.0,2.0);step=target-nudgeOffset;nudgeOffset=target;}
    if(!external||!transportClock||clockState!=2||clockPulse<0)nudgeRemaining+=step*bpm/60;
   }break;
   case PartMask:if(c.value>=0&&c.value<maxLoops)loops[c.value].partMask=c.count&15;break;
   case Filter:filter.set(c.value,c.number);break;
  }t=(t+1)%ringSize;}
  tail.store(t,std::memory_order_release);
 }
 void render(float* left,float* right,uint32_t frames,double host){
  consume();double tempoSlew=1-std::exp(-1/(sr*.09));
  for(uint32_t i=0;i<frames;i++){
   double now=host+i/sr;bpm+=(targetBPM-bpm)*tempoSlew;
   double correction=0;
   if(external&&haveTick){double elapsed=std::max(0.0,now-lastTick);
    if(elapsed>2){clockState=4;running=false;transportClock=false;}
    else if(elapsed>.25)clockState=3;
    else if(intervalCount>=3)clockState=2;
    if(running&&transportClock&&clockState==2&&clockPulse>=0){double desired=clockPulse/24+(elapsed+offset+nudgeOffset)*clockBPM/60;double error=desired-beat;
     // Phase is gently pulled into lock; jitter never jumps an audio cursor.
     correction=std::clamp(error*60/.12,-bpm*.18,bpm*.18);nudgeRemaining=0;}
   }
   if(running&&nudgeRemaining!=0){double adjust=std::clamp(nudgeRemaining*60/.12,-bpm*.18,bpm*.18);
    double applied=adjust/(60*sr);if(std::abs(applied)>std::abs(nudgeRemaining))applied=nudgeRemaining;
    correction+=applied*60*sr;nudgeRemaining-=applied;}
   double delta=(bpm+correction)/(60*sr);
   if(running){
    if(beat+1e-9>=nextBar){double boundary=nextBar;nextBar+=4;if(pending)applyPending(boundary);}
    if(active>=0&&valid(active)&&beat-startBeat+1e-9>=loops[active].beats){double boundary=startBeat+loops[active].beats;
     if(cycleCount){cyclePos=(cyclePos+1)%cycleCount;launch(cycle[cyclePos],boundary);}else launch(active,boundary);}
   }
   double desiredGain=running&&active>=0?1:0;gain+=float(std::clamp(desiredGain-gain,-1/(sr*.008),1/(sr*.003)));
   advanceParts(voice.loop);if(outgoing.loop!=voice.loop)advanceParts(outgoing.loop);
   Stereo sample{};
   if(gain>0&&voice.loop){sample=running?voice.render(std::max(0.0,beat-startBeat),delta,sr):voice.continueTail(delta,sr);
    if(transition>0){double f=double(transition)/(sr*.005);sample=sample*(1-f)+outgoing.continueTail(delta,sr)*f;transition--;}}
   sample=filter.process(sample);left[i]=sample.l*gain*.8f;right[i]=sample.r*gain*.8f;
   if(running)beat+=delta;
  }
  snapBeat.store(beat,std::memory_order_relaxed);snapBPM.store(bpm,std::memory_order_relaxed);
  snapProgress.store(active>=0&&loops[active].beats?std::clamp((beat-startBeat)/loops[active].beats,0.0,1.0):0,std::memory_order_relaxed);
  snapPlaying.store(running);snapActive.store(active);snapMode.store(mode);snapExternal.store(external);snapClock.store(clockState);snapPending.store(pending);
  int count=pending?pendingCount:cycleCount;for(int i=0;i<count;i++)snapQueue[i].store(pending?pendingIDs[i]:cycle[(cyclePos+i)%std::max(1,cycleCount)]);snapCount.store(count);
  completedBlocks.fetch_add(1,std::memory_order_release);
 }
};
Engine* E(BWEngine p){return static_cast<Engine*>(p);}void command(BWEngine p,int type,int value=0,double number=0){Command c;c.type=type;c.value=value;c.number=number;E(p)->push(c);}
}
extern "C" {
BWEngine bw_create(double sr){return new Engine(sr);}
void bw_destroy(BWEngine p){delete E(p);}
int32_t bw_load_loop(BWEngine p,int32_t id,const float* pcm,int32_t frames,int32_t beats,const int32_t* slices,int32_t count){if(id<0||id>=maxLoops||frames<2||beats<1||count<1||slices[0]!=0)return 0;for(int i=0;i<count;i++)if(slices[i]<0||slices[i]>=frames||(i&&slices[i]<=slices[i-1]))return 0;auto& l=E(p)->loops[id];l.frames=frames;l.beats=beats;l.pcm.assign(pcm,pcm+frames*2);l.slices.assign(slices,slices+count);return 1;}
void bw_queue(BWEngine p,const int32_t* ids,int32_t n){Command c;c.type=Queue;c.count=std::clamp(int(n),0,maxQueue);std::copy_n(ids,c.count,c.ids.begin());E(p)->push(c);}
void bw_enable(BWEngine p,int32_t id,int32_t enabled){command(p,Enable,id,enabled);}
void bw_tempo(BWEngine p,double bpm){command(p,Tempo,0,bpm);}
void bw_mode(BWEngine p,int32_t mode){command(p,Mode,mode);}
void bw_external(BWEngine p,int32_t external){command(p,External,external);}
void bw_transport(BWEngine p,int32_t action){command(p,Transport,action);}
void bw_midi(BWEngine p,uint8_t status,int32_t value,double seconds){Command c;c.type=MIDI;c.value=status;c.count=value;c.time=seconds;E(p)->push(c);}
void bw_offset(BWEngine p,double ms){command(p,Offset,0,ms);}
void bw_nudge(BWEngine p,double ms){command(p,Nudge,0,ms);}
BWParts bw_create_parts(const float* pcm,int32_t frames){if(!pcm||frames<2)return nullptr;auto* b=new Parts;b->frames=frames;b->pcm.assign(pcm,pcm+size_t(frames)*8);return b;}
void bw_set_parts(BWEngine p,int32_t id,BWParts parts){E(p)->setParts(id,static_cast<Parts*>(parts));}
void bw_part_mask(BWEngine p,int32_t id,int32_t mask){Command c;c.type=PartMask;c.value=id;c.count=mask;E(p)->push(c);}
void bw_filter(BWEngine p,int32_t type,double hz){command(p,Filter,type,hz);}
void bw_render(BWEngine p,float* l,float* r,uint32_t n,double t){E(p)->render(l,r,n,t);}
void bw_snapshot(BWEngine p,BWSnapshot* s){auto e=E(p);s->beat=e->snapBeat.load();s->bpm=e->snapBPM.load();s->loopProgress=e->snapProgress.load();s->playing=e->snapPlaying.load();s->activeLoop=e->snapActive.load();s->mode=e->snapMode.load();s->externalClock=e->snapExternal.load();s->clockState=e->snapClock.load();s->pending=e->snapPending.load();s->queueCount=e->snapCount.load();for(int i=0;i<s->queueCount;i++)s->queue[i]=e->snapQueue[i].load();s->droppedCommands=e->dropped.load();}
}
