// Releases leave a cycle latched. A new gesture replaces it.
export class PadGesture {
  constructor() { this.held = new Map(); this.order = []; }
  begin(pointer, id, append = false, existing = []) {
    if (!this.held.size) this.order = append ? [...existing] : [];
    this.held.set(pointer, id);
    if (!this.order.includes(id)) this.order.push(id);
    return [...this.order];
  }
  move(pointer, id) {
    if (!this.held.has(pointer) || this.held.get(pointer) === id) return null;
    this.held.set(pointer, id);
    if (this.order.includes(id)) return null;
    this.order.push(id);
    return [...this.order];
  }
  end(pointer) { this.held.delete(pointer); }
  cancel() { this.held.clear(); }
}
