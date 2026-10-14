import Foundation
@main struct InteractionTests {
 static func main() {
  var g=PadGesture()
  assert(g.began(token:1,pad:5)==[5])
  assert(g.began(token:2,pad:8)==[5,8])
  assert(g.began(token:3,pad:13)==[5,8,13])
  g.ended(token:2);g.ended(token:1);g.ended(token:3)
  assert(g.order==[5,8,13])
  assert(g.began(token:4,pad:2)==[2])
  assert(g.moved(token:4,pad:9)==[2,9]);assert(g.moved(token:4,pad:9)==nil)
  g.cancel();assert(g.began(token:5,pad:20)==[20])
  var p=MIDIByteParser(),events:[(UInt8,Int32)]=[]
  for b: UInt8 in [0x90,60,0xF8,100,61,0xF8,90,0x80,60,0,0xF2,4,0xF8,1,0xF0,1,2,0xF8,3,0xF7,0xFA,0xFC,0xFB] { p.feed(b){events.append(($0,$1))} }
  assert(events.filter{$0.0==0xF8}.count==4)
  assert(events.contains{$0.0==0x90 && $0.1==(60|100<<8)})
  assert(events.contains{$0.0==0x90 && $0.1==(61|90<<8)})
  assert(events.contains{$0.0==0xF2 && $0.1==132})
  assert(events.suffix(3).map{$0.0}==[0xFA,0xFC,0xFB])
  let songs = try! JSONDecoder().decode([Song].self, from: Data(contentsOf: URL(fileURLWithPath: "Samples/catalog.json")))
  for song in songs {
   for loop in song.loops { assert(song.midiPads[Int32(35 + loop.number)] == loop.id) }
  }
  let curated = songs.first { $0.id == "cy" }!
  for note: Int32 in 36...41 { assert(curated.midiPads[note] == nil) }
  assert(curated.midiPads[42] == 246 && curated.midiPads[53] == 257)
  print("PASS: MIDI notes follow displayed pad numbers; removed Can You See? pads stay unmapped")
  print("PASS: multi-touch order, release latch, new-gesture replacement, MIDI running status, interleaved clock, SysEx and transport")
 }
}
