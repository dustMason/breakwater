import SwiftUI
import UIKit

struct PadGrid: UIViewRepresentable {
    let samples: [LoopSample]
    let state: PlaybackState
    let disabled: Set<Int32>
    let editing: Bool
    let ready: Bool
    let queue: ([Int32]) -> Void
    let toggle: (Int32) -> Void
    func makeUIView(context: Context) -> PadGridView { PadGridView() }
    func updateUIView(_ view: PadGridView, context: Context) {
        view.queue = queue; view.toggle = toggle
        view.update(samples: samples, state: state, disabled: disabled, editing: editing, ready: ready)
    }
}

final class PadGridView: UIView {
    var queue: ([Int32]) -> Void = { _ in }
    var toggle: (Int32) -> Void = { _ in }
    private var pads: [WavePad] = []
    private var ids: [Int32] = []
    private var disabled: Set<Int32> = []
    private var editing = false
    private var ready = false
    private var gesture = PadGesture()
    private var editTouches: [Int: Int32] = [:]
    override init(frame: CGRect) {
        super.init(frame: frame); isMultipleTouchEnabled = true
        accessibilityIdentifier = "padGrid"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(samples: [LoopSample], state: PlaybackState, disabled: Set<Int32>, editing: Bool, ready: Bool) {
        if ids != samples.map(\.id) {
            gesture.cancel(); editTouches.removeAll()
            pads.forEach { $0.removeFromSuperview() }
            ids = samples.map(\.id)
            pads = samples.map { sample in
                let pad = WavePad(sample: sample)
                pad.activate = { [weak self] in
                    guard let self, self.ready else { return false }
                    if self.editing { self.toggle(sample.id) }
                    else if !self.disabled.contains(sample.id) { self.queue([sample.id]) }
                    else { return false }
                    return true
                }
                pad.exclude = { [weak self] in self?.toggle(sample.id); return true }
                addSubview(pad); return pad
            }
            accessibilityElements = pads
            setNeedsLayout()
        }
        if self.editing != editing { gesture.cancel(); editTouches.removeAll() }
        self.disabled = disabled; self.editing = editing; self.ready = ready
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for pad in pads {
            let order = state.queue.firstIndex(of: pad.sample.id).map { $0 + 1 }
            pad.update(active: state.playing && state.active == pad.sample.id,
                       pending: state.pending, order: order, progress: state.progress,
                       disabled: disabled.contains(pad.sample.id), editing: editing, ready: ready)
        }
        CATransaction.commit()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let columns = bounds.width > bounds.height * 1.12 ? 6 : 5
        let rows = max(1, Int(ceil(Double(pads.count) / Double(columns))))
        let gap: CGFloat = 7
        let width = max(1, (bounds.width - CGFloat(columns-1)*gap) / CGFloat(columns))
        let height = max(1, (bounds.height - CGFloat(rows-1)*gap) / CGFloat(rows))
        for (index, pad) in pads.enumerated() {
            pad.frame = CGRect(x: CGFloat(index % columns)*(width+gap), y: CGFloat(index / columns)*(height+gap), width: width, height: height)
        }
    }
    private func token(_ touch: UITouch) -> Int { ObjectIdentifier(touch).hashValue }
    private func pad(at touch: UITouch) -> WavePad? { let point=touch.location(in:self); return pads.first { $0.frame.contains(point) } }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard ready else { return }
        var cycle: [Int32]?
        let sorted = touches.sorted { a,b in
            if a.timestamp != b.timestamp { return a.timestamp < b.timestamp }
            let p=a.location(in:self), q=b.location(in:self)
            return p.y == q.y ? p.x < q.x : p.y < q.y
        }
        for touch in sorted {
            guard let pad = pad(at:touch) else { continue }
            if editing { editTouches[token(touch)] = pad.sample.id; toggle(pad.sample.id) }
            else if !disabled.contains(pad.sample.id) { cycle = gesture.began(token: token(touch), pad: pad.sample.id) }
        }
        if let cycle { queue(cycle) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var cycle: [Int32]?
        for touch in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let pad = pad(at:touch) else { continue }
            if editing {
                if editTouches[token(touch)] != pad.sample.id { editTouches[token(touch)] = pad.sample.id; toggle(pad.sample.id) }
            } else if !disabled.contains(pad.sample.id), let next = gesture.moved(token: token(touch), pad: pad.sample.id) { cycle = next }
        }
        if let cycle { queue(cycle) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { gesture.ended(token: token(touch)); editTouches.removeValue(forKey: token(touch)) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with:event) }
}

final class WavePad: UIView {
    let sample: LoopSample
    var activate: () -> Bool = { false }
    var exclude: () -> Bool = { false }
    private let number = UILabel(), bars = UILabel(), status = UILabel()
    private let waveform = CAShapeLayer(), progressFill = CALayer(), playhead = CALayer(), queueFlash = CALayer()
    private let exclusion = UIImageView(image: UIImage(systemName: "nosign"))
    private var active = false, pending = false, excluded = false, editing = false, ready = false
    private var order: Int?, progress = 0.0
    private var lastSize = CGSize.zero

    init(sample: LoopSample) {
        self.sample = sample
        super.init(frame: .zero)
        isUserInteractionEnabled = false; isAccessibilityElement = true
        accessibilityIdentifier = "pad_\(sample.id)"
        layer.cornerRadius = 7; layer.borderWidth = 0.75; layer.masksToBounds = true
        layer.addSublayer(queueFlash); layer.addSublayer(progressFill); layer.addSublayer(waveform); layer.addSublayer(playhead)
        [number,bars,status].forEach { addSubview($0); $0.adjustsFontForContentSizeCategory = true }
        number.text = sample.label; bars.textAlignment = .right
        exclusion.contentMode = .scaleAspectFit; addSubview(exclusion)
        updateFonts()
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitPreferredContentSizeCategory.self, UITraitAccessibilityContrast.self]) { (view: WavePad, _: UITraitCollection) in
            view.updateFonts(); view.lastSize = .zero; view.applyStyle(); view.setNeedsLayout()
        }
        accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Exclude or restore pad", target: self, selector: #selector(toggleExclusion))]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityActivate() -> Bool { activate() }
    @objc private func toggleExclusion() -> Bool { exclude() }
    private func updateFonts() {
        number.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold), maximumPointSize: 23)
        bars.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12), maximumPointSize: 19)
        status.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: .systemFont(ofSize: 11, weight: .semibold), maximumPointSize: 16)
        bars.text = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? "\(sample.bars)b" : "\(sample.bars) \(sample.bars == 1 ? "bar" : "bars")"
    }
    func update(active: Bool, pending: Bool, order: Int?, progress: Double, disabled: Bool, editing: Bool, ready: Bool) {
        let changed = self.active != active || self.pending != pending || self.order != order || excluded != disabled || self.editing != editing || self.ready != ready
        self.active=active; self.pending=pending; self.order=order; self.progress=progress; excluded=disabled; self.editing=editing; self.ready=ready
        if changed { applyStyle() }
        updateProgress()
    }
    private func applyStyle() {
        let blue=Palette.tint
        let queued = order != nil && !active && !excluded
        let ink: UIColor = active ? .white : (excluded ? .tertiaryLabel : queued ? blue : .label)
        backgroundColor = active ? Palette.playing : excluded ? .secondarySystemBackground : queued ? blue.withAlphaComponent(0.10) : .systemBackground
        layer.borderColor = (editing ? blue.withAlphaComponent(0.5) : queued ? blue.withAlphaComponent(0.4) : UIColor.separator.withAlphaComponent(0.3)).resolvedColor(with:traitCollection).cgColor
        number.textColor = ink
        bars.textColor = active ? UIColor.white : Palette.secondaryText
        waveform.fillColor = (active ? UIColor.white : excluded ? .tertiaryLabel : queued ? blue : .secondaryLabel).resolvedColor(with:traitCollection).cgColor
        progressFill.backgroundColor = UIColor.white.withAlphaComponent(0.14).cgColor
        playhead.backgroundColor = UIColor.white.cgColor
        progressFill.isHidden = !active; playhead.isHidden = !active
        status.textColor = active ? .white : blue
        if excluded { status.text = editing ? "RESTORE" : "EXCLUDED"; status.textColor = Palette.secondaryText }
        else if active { status.text = "PLAYING\(order.map { " · \($0)" } ?? "")" }
        else if let order { status.text = "\(order)  \(pending ? "NEXT BAR" : "CYCLE")" }
        else { status.text = editing ? "EXCLUDE" : "" }
        exclusion.isHidden = !excluded; exclusion.tintColor = .tertiaryLabel
        queueFlash.isHidden = !queued || !pending
        queueFlash.backgroundColor = blue.withAlphaComponent(0.12).resolvedColor(with:traitCollection).cgColor
        queueFlash.removeAnimation(forKey:"queuedPulse")
        if queued && pending && !UIAccessibility.isReduceMotionEnabled {
            let pulse = CABasicAnimation(keyPath:"opacity"); pulse.fromValue=0; pulse.toValue=1
            pulse.duration=0.55; pulse.autoreverses=true; pulse.repeatCount = .infinity
            queueFlash.add(pulse, forKey:"queuedPulse")
        }
        alpha = ready ? 1 : 0.45
        accessibilityLabel = "Loop \(sample.label), \(sample.bars) \(sample.bars == 1 ? "bar" : "bars")"
        accessibilityValue = excluded ? "Excluded" : active ? "Playing" : order != nil ? "\(pending ? "Queued" : "Cycle") \(order!)" : "Ready"
        accessibilityHint = editing ? "Double tap to \(excluded ? "restore" : "exclude") this loop" : "Double tap to queue for the next bar"
        accessibilityTraits = [.button]
        if excluded && !editing || !ready { accessibilityTraits.insert(.notEnabled) }
        if active { accessibilityTraits.insert(.selected) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        queueFlash.frame = bounds
        let inset: CGFloat = 10, top: CGFloat = 5
        let labelHeight = max(22,number.font.lineHeight)
        number.frame = CGRect(x:inset,y:top,width:40,height:labelHeight)
        bars.frame = CGRect(x:50,y:top,width:max(0,bounds.width-60),height:labelHeight)
        status.frame = CGRect(x:inset,y:bounds.height-23,width:bounds.width-20,height:20)
        exclusion.frame = CGRect(x:bounds.width-28,y:bounds.height-24,width:17,height:17)
        if bounds.size != lastSize {
            lastSize=bounds.size
            let rect=CGRect(x:inset,y:top+labelHeight+4,width:bounds.width-inset*2,height:max(12,bounds.height-labelHeight-39))
            let path=UIBezierPath(), count=sample.waveform.count
            if count>1 {
                for (i,amplitude) in sample.waveform.enumerated() {
                    let p=CGPoint(x:rect.minX+CGFloat(i)*rect.width/CGFloat(count-1),y:rect.midY-CGFloat(amplitude)*rect.height/2)
                    if i==0 { path.move(to:p) } else { path.addLine(to:p) }
                }
                for i in (0..<count).reversed() { path.addLine(to:CGPoint(x:rect.minX+CGFloat(i)*rect.width/CGFloat(count-1),y:rect.midY+CGFloat(sample.waveform[i])*rect.height/2)) }
                path.close()
            }
            waveform.path=path.cgPath
        }
        updateProgress()
    }
    private func updateProgress() {
        let x=bounds.width*min(1,max(0,progress))
        progressFill.frame=CGRect(x:0,y:0,width:x,height:bounds.height)
        playhead.frame=CGRect(x:x,y:0,width:1.5,height:bounds.height)
    }
}
