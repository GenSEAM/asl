import React, { useState, useEffect, useRef } from 'react';
import { Section, SectionHeader } from './ui/primitives';
import { Mic, Radio, Zap, ShieldAlert, Cpu } from 'lucide-react';

export const VoiceAssistant: React.FC = () => {
  const [isRecording, setIsRecording] = useState(false);
  const [transcript, setTranscript] = useState('Verify 16kHz linear PCM streaming into EDDIE Layer 2 Consultative Router');
  const [latencyMs, setLatencyMs] = useState(0.018);
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const animFrameRef = useRef<number | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    let phase = 0;
    const render = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const w = canvas.width;
      const h = canvas.height;
      const mid = h / 2;

      ctx.beginPath();
      ctx.strokeStyle = isRecording ? '#a855f7' : '#71717a';
      ctx.lineWidth = 2;

      const bars = 56;
      const step = w / bars;

      for (let i = 0; i < bars; i++) {
        const x = i * step + step / 2;
        const amp = isRecording
          ? Math.sin(phase + i * 0.25) * Math.cos(phase * 0.4 + i * 0.15) * (h * 0.42)
          : Math.sin(phase * 0.3 + i * 0.2) * (h * 0.09);
        const barH = Math.max(3, Math.abs(amp));

        ctx.moveTo(x, mid - barH);
        ctx.lineTo(x, mid + barH);
      }
      ctx.stroke();

      phase += isRecording ? 0.16 : 0.03;
      animFrameRef.current = requestAnimationFrame(render);
    };

    render();

    return () => {
      if (animFrameRef.current) cancelAnimationFrame(animFrameRef.current);
    };
  }, [isRecording]);

  const toggleRecording = () => {
    const next = !isRecording;
    setIsRecording(next);
    if (next) {
      setLatencyMs(+(0.014 + Math.random() * 0.007).toFixed(3));
      setTranscript('Capture voice stream and synthesize autonomous action on mesh bus');
    }
  };

  return (
    <Section id="voice-assistant" ground="sunken" labelledBy="voice-title" className="bg-dot-grid overflow-hidden">
      {/* Atmospheric Glow */}
      <div className="glow-orb -top-24 right-10 w-96 h-96" aria-hidden="true" />

      <SectionHeader
        id="voice-title"
        index="04"
        eyebrow="Voice Stream Bridge"
        title="Zero-latency voice streams straight into consultative agent routing."
        lead="Direct 16kHz linear PCM Web Audio stream bridge connected to the EDDIE Layer 2 Consultative Router. Instant speech-to-intent synthesis in <0.025ms with zero cloud roundtrips."
      />

      <div className="rounded-3xl border border-line bg-surface/90 backdrop-blur-xl shadow-e3 p-6 sm:p-8">
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 pb-6 border-b border-line">
          <div className="flex items-center gap-3">
            <button
              onClick={toggleRecording}
              className={`flex items-center gap-2 px-5 py-2.5 rounded-full font-sans text-meta font-semibold transition-all ${
                isRecording
                  ? 'bg-signal text-white animate-pulse shadow-e2'
                  : 'bg-ground text-ink border border-line hover:border-line-strong'
              }`}
            >
              <Mic className="w-4 h-4" />
              {isRecording ? 'Streaming 16kHz PCM' : 'Simulate Voice Stream'}
            </button>
            <span className="font-mono text-micro uppercase text-ink-3">
              16kHz Linear PCM · Mono
            </span>
          </div>

          <div className="flex items-center gap-5">
            <span className="font-mono text-micro text-ink-3 flex items-center gap-1.5">
              <Zap className="w-3.5 h-3.5 text-signal" />
              Latency: <span className="text-signal tabular-nums font-bold">{latencyMs} ms</span>
            </span>
            <span className="font-mono text-micro text-ink-3 flex items-center gap-1.5">
              <Cpu className="w-3.5 h-3.5 text-signal" />
              Target: EDDIE Layer 2
            </span>
          </div>
        </div>

        {/* Live Audio Waveform Canvas */}
        <div className="py-6">
          <canvas
            ref={canvasRef}
            width={840}
            height={100}
            className="w-full h-24 rounded-2xl bg-ground/80 border border-line"
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-6 border-t border-line">
          <div className="p-5 rounded-2xl border border-line bg-ground/60">
            <p className="font-mono text-micro uppercase text-ink-3 font-semibold">Speech Stream Input</p>
            <p className="mt-2 text-body text-ink font-medium leading-relaxed">"{transcript}"</p>
          </div>
          <div className="p-5 rounded-2xl border border-line bg-ground/60">
            <p className="font-mono text-micro uppercase text-signal font-semibold">EDDIE Intent Resolution</p>
            <div className="mt-2 flex items-center justify-between">
              <span className="text-body text-ink font-semibold">Consultative Autonomous Action</span>
              <span className="px-3 py-1 rounded-full bg-signal/10 text-signal font-mono text-micro font-bold uppercase">
                Verified Safe
              </span>
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};
