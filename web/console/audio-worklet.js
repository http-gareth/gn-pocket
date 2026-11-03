import { Ring } from './ring.js'

class PocketAudio extends AudioWorkletProcessor {
  constructor() {
    super()
    this.ring = new Ring(sampleRate)
    this.port.onmessage = ({ data }) => this.ring.push(data)
  }

  process(_, outputs) {
    const [first, ...rest] = outputs[0]
    this.ring.pull(first)
    for (const channel of rest) channel.set(first)
    return true
  }
}

registerProcessor('pocket-audio', PocketAudio)
