// Aether Observatory — HUD Controller
// Updates HTML overlay panels with data from DataBridge

import { ACTIVITY_ICONS } from '../config.js';
import { HudCharts } from './hud-charts.js';

export class HudController {
  constructor(dataBridge) {
    this.data = dataBridge;
    this.charts = new HudCharts();

    // Pipeline animation
    this._pipeStages = ['pp-tsfr', 'pp-hampel', 'pp-bw', 'pp-avecsi', 'pp-fuse', 'pp-brain'];
    this._pipeIdx = 0;
    this._pipeInterval = setInterval(() => this._animPipe(), 300);

    // Chart update intervals
    this._heatmapInterval = setInterval(() => {
      this.charts.drawHeatmap(this.data.csiHistory);
    }, 200);

    this._sparkInterval = setInterval(() => {
      this.charts.drawSparkline(this.data.rssiHistory);
    }, 500);
  }

  // Called every frame
  update() {
    this._updateStatus();
    this._updateVitals();
    this._updateSignal();
    this._updateLatency();
    this._updatePresence();
    this._updateActivity();
    this._updateLocation();
  }

  _updateStatus() {
    const wd = document.getElementById('wd');
    const wl = document.getElementById('wl');
    if (wd && wl) {
      wd.className = this.data.connected ? 'dt dt-on' : 'dt dt-off';
      wl.textContent = this.data.connected ? 'LIVE' : 'OFFLINE';
    }

    // FPS is set by main.js render counter, not here
    const fc = document.getElementById('fc');
    if (fc) fc.textContent = this.data.frameCount;
  }

  _updateVitals() {
    const v = this.data.vitals;

    const hr = document.getElementById('hr');
    const br = document.getElementById('br');
    const hv = document.getElementById('hv');
    if (hr) {
      hr.textContent = v.heart_bpm > 0 ? v.heart_bpm.toFixed(0) : '--';
      if (v.heart_bpm > 0) hr.style.animationDuration = `${60 / v.heart_bpm}s`;
    }
    if (br) br.textContent = v.breath_bpm > 0 ? v.breath_bpm.toFixed(0) : '--';
    if (hv) hv.textContent = v.hrv > 0 ? v.hrv.toFixed(0) : '--';

    const hrb = document.getElementById('hrb');
    const brb = document.getElementById('brb');
    const hvb = document.getElementById('hvb');
    if (hrb) hrb.style.width = `${Math.min(100, ((v.heart_bpm - 40) / 80) * 100)}%`;
    if (brb) brb.style.width = `${Math.min(100, ((v.breath_bpm - 6) / 24) * 100)}%`;
    if (hvb) hvb.style.width = `${Math.min(100, v.hrv * 1.5)}%`;
  }

  _updateSignal() {
    const rssi = this.data.rssiHistory;
    const last = rssi.length > 0 ? rssi[rssi.length - 1] : -44;

    const el = document.getElementById('rssi');
    if (el) el.textContent = last.toFixed(0) + ' dBm';

    const varV = document.getElementById('var-v');
    if (varV) varV.textContent = (Math.random() * 0.3 + 0.05).toFixed(3);

    const motV = document.getElementById('mot-v');
    if (motV) motV.textContent = (Math.random() * 0.5).toFixed(3);
  }

  _updateLatency() {
    const l = this.data.latency;

    const set = (id, val) => {
      const el = document.getElementById(id);
      if (el) el.textContent = val;
    };

    set('lat-cond', l.condition.toFixed(1) + 'ms');
    set('lat-inf', l.brain.toFixed(1) + 'ms');
    set('lat-tot', l.total.toFixed(1) + 'ms');
    set('l-cond', l.condition.toFixed(1) + 'ms');
    set('l-fuse', l.fusion.toFixed(2) + 'ms');
    set('l-brain', l.brain.toFixed(1) + 'ms');
    set('l-tot', l.total.toFixed(1) + 'ms');
  }

  _updatePresence() {
    const n = this.data.presence.total;
    const pn = document.getElementById('pn');
    if (pn) {
      pn.textContent = n;
      pn.style.color = n > 0 ? 'var(--g)' : 'var(--t3)';
    }

    const pd = document.getElementById('pd');
    if (pd) {
      pd.innerHTML = '';
      for (let i = 0; i < n; i++) {
        const s = document.createElement('span');
        s.className = 'pd';
        pd.appendChild(s);
      }
    }
  }

  _updateActivity() {
    const a = this.data.activity;
    const an = document.getElementById('an');
    const ai = document.getElementById('ai');
    const ac = document.getElementById('ac');

    if (an) an.textContent = a.label.charAt(0).toUpperCase() + a.label.slice(1);
    if (ai) ai.textContent = ACTIVITY_ICONS[a.label] || '\u25A0';
    if (ac) ac.textContent = `${(a.confidence * 100).toFixed(0)}%`;
  }

  _updateLocation() {
    const loc = this.data.location;
    const lv = document.getElementById('lv');
    const la = document.getElementById('la');

    if (lv) lv.textContent = `${loc.x.toFixed(1)} , ${loc.y.toFixed(1)} , ${loc.z.toFixed(1)}`;
    if (la) la.textContent = loc.accuracy.toFixed(1);
  }

  _animPipe() {
    this._pipeStages.forEach((id, i) => {
      const el = document.getElementById(id);
      if (el) el.classList.toggle('active', i === this._pipeIdx);
    });
    this._pipeIdx = (this._pipeIdx + 1) % this._pipeStages.length;
  }

  dispose() {
    clearInterval(this._pipeInterval);
    clearInterval(this._heatmapInterval);
    clearInterval(this._sparkInterval);
    this.charts.dispose();
  }
}
