# Concept Paper: Real-Time Audio → MIDI 2.0 with SDLKit (with In-Markdown Diagram)

## 1) Purpose
Design a **low-latency, chunk-based, real-time audio-to-MIDI 2.0** pipeline using **SDLKit**. We will:
- Extend SDLKit with **SDL3 audio capture** (new `AudioAgent`).
- Build an **overlapped framing** + **feature extraction** stage (CPU first, optional GPU via SDLKit Compute).
- Run **AMT** (e.g., Spotify **Basic Pitch**) per chunk.
- Emit **MIDI 2.0 UMP** events through SDLKit’s MIDI2 stack (or MIDIKit).

---

## 2) Architecture (Mermaid Diagram, renders inline)

```mermaid
flowchart LR
  %% --- Capture ---
  subgraph CAP[SDL3 Audio Capture (to be added in SDLKit)]
    Dev[Device: Guitar / Line-In<br/>(sampleRate, channels, format)]
    Str["SDL_OpenAudioDeviceStream (capture)"]
    RB["Lock-Free Ring Buffer (audio frames)"]
    Dev --> Str --> RB
  end

  %% --- Pipeline ---
  subgraph PIPE[Real-Time Chunk Pipeline]
    FR["Framer + Overlap<br/>(win=2048–4096, hop=25–50%)"]
    FEAT["Features: STFT + Mel + Onset"]
    GPU["Optional GPU Path (SDLKit Compute)<br/>HLSL → Metal/Vulkan/DX12"]
    CTX["Context Buffer<br/>(previous frames for continuity)"]
    RB -- "non-blocking pull, fixed-size chunks" --> FR
    FR --> FEAT
    FR --> GPU
    FEAT --> INFER
    GPU --> INFER
    CTX --> INFER
  end

  %% --- Inference ---
  subgraph INFER[Model Inference]
    M["Basic Pitch (CoreML / TFLite / ONNX)"]
    POST["Post-Processing<br/>(note merge, smoothing,<br/>latency compensation)"]
    M --> POST
  end

  %% --- MIDI 2.0 Output ---
  subgraph MIDI[MIDI 2.0 Output]
    MAP["Note Mapping<br/>(pitch, velocity, per-note bends)"]
    UMP["UMP Encoding<br/>(MIDI 2.0 Note On/Off, Per-Note Pitch Bend)"]
    ROUTE["Routing<br/>(SDLKit MIDI2 / MIDIKit → CoreMIDI / ALSA / Win MIDI Services)"]
    MAP --> UMP --> ROUTE
  end

  POST -- "notes + timing + bends" --> MAP
```

**Latency budget (typical, tunable):**
- Device buffer (capture stream): **3–6 ms**  
- Framing (win/2 at 2048 samples @ 44.1 kHz): **≈23 ms**  
- Inference (desktop-class CoreML/TFLite/ONNX): **<10 ms**  
- **Total target:** ~**50–100 ms**, lower with smaller windows/hops (trade accuracy).

---

## 3) Components & Responsibilities

### 3.1 `AudioAgent` (new, SDLKit)
- Wrap **SDL3** capture (`SDL_OpenAudioDeviceStream`).
- Expose:
  - `startCapture(sampleRate, channels, format, framesPerChunk)`
  - `onAudioChunk(_ buffer: UnsafeBufferPointer<Float>)` (push mode)
  - `readFrames(count:) -> [Float]` (pull mode)
- Internals: **lock-free ring buffer** between SDL audio thread and analysis thread; never block the audio callback.

### 3.2 Framer & Overlap
- Fixed frame sizes **2048–4096** samples, **50–75%** overlap.
- Emits windows with timestamping; maintains **hop** pacing independent of device callback cadence.

### 3.3 Features
- **CPU (initial):** Accelerate/vDSP (macOS/iOS) or portable FFT for STFT → mel-spectrogram + onset energy.
- **GPU (optional):** SDLKit Compute dispatch (HLSL) for batched STFT/mel to reduce CPU load and latency.

### 3.4 Model Inference
- **Basic Pitch** (lightweight AMT model) per overlapped chunk; retains a **context buffer** of prior frames.
- Backends by platform:
  - macOS/iOS → **CoreML**
  - Linux → **TFLite**
  - Windows → **ONNX**
- Threading: inference on a **background worker**; if it falls behind, **drop** late windows (never stall capture).

### 3.5 Post-Processing
- Merge frame-wise activations into **discrete notes** with onset/offset.
- **Smoothing & hysteresis** to reduce flicker; apply **latency compensation** (half-window minus pipeline slack).

### 3.6 MIDI 2.0 Eventing
- Map notes to **MIDI number + velocity + per-note pitch-bend** streams.
- Encode as **UMP** (Note On/Off, per-note bend); route via **SDLKit MIDI2** or **MIDIKit** to OS drivers/DAWs.

---

## 4) Execution Model & Back-Pressure

- **Audio thread:** capture → ring-buffer (lock-free), minimal work, never blocks.  
- **Pipeline thread:** pull **fixed-size chunks**, run framing/feature/model/post; enqueue MIDI.  
- **Drop policy:** if queue > threshold, **skip overlaps** or **drop frames**; prefer stable latency over completeness.  
- **Clocking:** timestamps from device + hop schedule; MIDI timestamps aligned to audio timebase.

---

## 5) Pseudocode (core loop, simplified)

```swift
while running {
  // 1) Pull exactly hopSize frames (with overlap from local window buffer)
  let newFrames = ringBuffer.readFrames(count: hopSize)
  window.append(newFrames)
  if window.count >= frameSize {
    let frame = window.last(frameSize) * hannWindow
    // 2) Features (CPU or GPU)
    let spec = stft(frame)
    let mel  = melFilter(spec)
    let onset = onsetEnergy(spec)
    // 3) Inference
    let notesChunk = model.predict(mel, context: ctx)
    // 4) Post / Map
    let events = postProcessAndMap(notesChunk, ts: now())
    midiOut.sendUMP(events)
    // 5) Maintain overlap
    window.removeFirst(hopSize)
    ctx.update(with: mel)
  }
}
```

---

## 6) Cross-Platform Notes

- **SDL3 capture** is portable; inference backends differ by OS as above.  
- Start with **CPU features** everywhere; add **GPU compute** where Metal/Vulkan/DX12 is available.  
- **MIDI 2.0** routing differs by OS (CoreMIDI, ALSA seq, Windows MIDI Services) but UMP stays uniform.

---

## 7) Risks & Mitigations

- **Latency vs. accuracy:** Smaller windows reduce latency but hurt frequency resolution → provide presets (“Live”, “Balanced”, “Studio”).  
- **Polyphonic guitar:** Complex spectra cause false positives → stronger onset gating, note-merge thresholds, and per-string heuristics (optional).  
- **Inference hiccups:** Strict drop policy + telemetry (CPU/GPU time, queue depth) to auto-tune hop/window.

---

## 8) Phased Delivery

1. **MVP:** SDL3 capture + CPU features + CoreML inference (macOS) + MIDI 2.0 out.  
2. **Cross-platform:** ONNX/TFLite bindings; uniform SDLKit APIs.  
3. **GPU uplift:** HLSL compute shaders for STFT/mel; benchmark latency wins.  
4. **Expressiveness:** Per-note pitch-bend smoothing; MPE-style mapping options.  
5. **QA & Bench:** End-to-end latency measurement, polyphony stress tests, DAW integration tests.

---

## 9) Target Latency (initial)
- **Live preset:** 1024 win / 256 hop → ~12 ms frame/2 + ~6 ms device + ~5–8 ms inference ⇒ **~25–35 ms**.  
- **Balanced:** 2048 / 512 → **~40–60 ms**.  
- **Studio:** 4096 / 1024 → **~70–100 ms**, highest accuracy.

---

## 10) Outcome
Extending SDLKit with **AudioAgent** and implementing the **chunked streaming AMT** path yields a practical, expressive, cross-platform **real-time Audio → MIDI 2.0** solution in Swift—suitable for guitar and other instruments, with clear upgrade paths (GPU compute, advanced post-processing, and richer MIDI 2.0 profiles).
