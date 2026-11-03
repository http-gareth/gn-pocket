import { Ring } from './ring.js'

export class Speaker {
  muted = false
  #context: AudioContext | null = null
  #sink: ((samples: Float32Array) => void) | null = null

  get sampleRate() {
    return this.#context?.sampleRate ?? null
  }

  wake() {
    this.#context ??= this.#open()
    if (this.#context.state === 'suspended') this.#context.resume()
  }

  play(samples: Float32Array) {
    if (this.muted || !this.#sink || this.#context?.state !== 'running' || !samples.length) return
    this.#sink(samples)
  }

  #open() {
    const context = new AudioContext({ latencyHint: 'interactive' })
    if (context.audioWorklet) {
      context.audioWorklet.addModule(new URL('audio-worklet.js', import.meta.url).href).then(() => {
        const node = new AudioWorkletNode(context, 'pocket-audio', { outputChannelCount: [2] })
        node.connect(context.destination)
        this.#sink = samples => node.port.postMessage(samples, [samples.buffer])
      }).catch(error => console.error(error))
    } else {
      const ring = new Ring(context.sampleRate)
      const node = context.createScriptProcessor(1024, 0, 1)
      node.onaudioprocess = e => ring.pull(e.outputBuffer.getChannelData(0))
      node.connect(context.destination)
      this.#sink = samples => ring.push(samples)
    }
    return context
  }
}
