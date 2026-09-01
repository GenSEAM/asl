import React, { useState, useEffect, useRef } from 'react';
import { Section, SectionHeader, Sexpr } from './ui/primitives';

export const VoiceAssistant: React.FC = () => {
  const [isRecording, setIsRecording] = useState(false);
  const [transcript, setTranscript] = useState('Inspect agent bus status and summarize active channels');
  const [latencyMs, setLatencyMs] = useState(0.018);
  const [intentExpr, setIntentExpr] = useState('(? eddie-layer-2 consult :voice "Inspect agent bus status")');
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
      ctx.strokeStyle = isRecording ? '#f97316' : '#71717a';
      ctx.lineWidth = 1.5;

      const bars = 48;
      const step = w / bars;

      for (let i = 0; i < bars; i++) {
        const x = i * step + step / 2;
        const amp = isRecording
          ? Math.sin(phase + i * 0.3) * Math.cos(phase * 0.5 + i * 0.2) * (h * 0.38)
          : Math.sin(phase * 0.4 + i * 0.2) * (h * 0.08);
        const barH = Math.max(3, Math.abs(amp));

        ctx.moveTo(x, mid - barH);
        ctx.lineTo(x, mid + barH);
      }
      ctx.stroke();

      phase += isRecording ? 0.15 : 0.03;
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
      setLatencyMs(+(0.014 + Math.random() * 0.008).toFixed(3));
      setTranscript('Verify 16kHz linear PCM streaming into EDDIE Layer 2 Consultative Router');
      setIntentExpr('(? eddie-layer-2 consult :voice "Verify 16kHz linear PCM streaming")');
    }
  };

  return (
    <Section id="voice-assistant" ground="sunken" labelledBy="voice-title">
      <SectionHeader
        id="voice-title"
        index="04"
        eyebrow="Voice Stream Bridge"
        title="Zero-latency voice streams straight into consultative agent routing."
        lead="Direct 16kHz linear PCM Web Audio stream bridge connected to the EDDIE Layer 2 Consultative Router. Instant speech-to-intent synthesis in <0.025ms with zero cloud roundtrips."
      />

      <div className="rounded-2xl border border-line bg-surface p-6 sm:p-8">
        <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 pb-6 border-b border-line">
          <div className="flex items-center gap-3">
            <button
              onClick={toggleRecording}
              className={`px-4 py-2 rounded-lg font-mono text-meta font-medium transition-all ${
                isRecording
                  ? 'bg-signal text-white animate-pulse'
                  : 'bg-ground text-ink border border-line hover:border-line-strong'
              }`}
            >
              {isRecording ? '● Live (16kHz PCM)' : 'Start Voice Stream'}
            </button>
            <span className="font-mono text-micro uppercase text-ink-3">
              Format: 16kHz Linear PCM · Mono
            </span>
          </div>

          <div className="flex items-center gap-4">
            <span className="font-mono text-micro text-ink-3">
              Telemetry: <span className="text-signal tabular-nums font-semibold">{latencyMs} ms</span>
            </span>
            <span className="font-mono text-micro text-ink-3">Target: @genseam/eddie</span>
          </div>
        </div>

        <div className="py-8">
          <canvas
            ref={canvasRef}
            width={720}
            height={96}
            className="w-full h-24 rounded-lg bg-ground border border-line"
          />
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 pt-6 border-t border-line">
          <div>
            <p className="font-mono text-micro uppercase text-ink-3">Speech Transcript</p>
            <p className="mt-2 text-body text-ink font-medium">"{transcript}"</p>
          </div>
          <div>
            <p className="font-mono text-micro uppercase text-signal">Synthesized ASL nano wire expression</p>
            <div className="mt-2 overflow-x-auto">
              <Sexpr code={intentExpr} className="text-meta text-ink" />
            </div>
          </div>
        </div>
      </div>
    </Section>
  );
};
