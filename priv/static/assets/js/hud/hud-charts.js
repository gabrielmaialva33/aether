// Aether Observatory — HUD Charts
// CSI heatmap canvas + RSSI sparkline (migrated from index.html)

export class HudCharts {
  constructor() {
    this.hmCanvas = document.getElementById('hm');
    this.hmCtx = this.hmCanvas?.getContext('2d');
    this.sparkCanvas = document.getElementById('spark');
    this.sparkCtx = this.sparkCanvas?.getContext('2d');
  }

  drawHeatmap(csiHistory) {
    const ctx = this.hmCtx;
    if (!ctx) return;
    const c = this.hmCanvas;

    ctx.clearRect(0, 0, c.width, c.height);

    if (csiHistory.length < 2) {
      ctx.fillStyle = '#0a0510';
      ctx.fillRect(0, 0, c.width, c.height);
      ctx.font = '9px JetBrains Mono';
      ctx.fillStyle = 'rgba(255,255,255,.2)';
      ctx.fillText('Waiting for CSI...', 6, 42);
      return;
    }

    const rows = csiHistory.length;
    const cols = csiHistory[0].length;
    const cw = c.width / cols;
    const ch = c.height / rows;

    for (let y = 0; y < rows; y++) {
      for (let x = 0; x < cols; x++) {
        const v = Math.min(1, Math.max(0, csiHistory[y][x]));
        ctx.fillStyle = this._hmColor(v);
        ctx.fillRect(x * cw, y * ch, cw + 0.5, ch + 0.5);
      }
    }
  }

  _hmColor(v) {
    if (v < 0.25) {
      const t = v / 0.25;
      return `rgb(${t * 20 | 0},${10 + t * 40 | 0},${40 + t * 80 | 0})`;
    }
    if (v < 0.5) {
      const t = (v - 0.25) / 0.25;
      return `rgb(${20 + t * 30 | 0},${50 + t * 130 | 0},${120 - t * 40 | 0})`;
    }
    if (v < 0.75) {
      const t = (v - 0.5) / 0.25;
      return `rgb(${50 + t * 170 | 0},${180 + t * 60 | 0},${80 - t * 60 | 0})`;
    }
    const t = (v - 0.75) / 0.25;
    return `rgb(${220 + t * 35 | 0},${240 - t * 100 | 0},${20 - t * 20 | 0})`;
  }

  drawSparkline(rssiHistory) {
    const ctx = this.sparkCtx;
    if (!ctx) return;
    const c = this.sparkCanvas;

    ctx.clearRect(0, 0, c.width, c.height);
    if (rssiHistory.length < 2) return;

    ctx.beginPath();
    for (let i = 0; i < rssiHistory.length; i++) {
      const x = i / (rssiHistory.length - 1) * c.width;
      const y = c.height - ((rssiHistory[i] + 80) / 60) * c.height;
      i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
    }
    ctx.strokeStyle = 'rgba(0,255,65,.4)';
    ctx.lineWidth = 1.2;
    ctx.shadowBlur = 3;
    ctx.shadowColor = 'rgba(0,255,65,.2)';
    ctx.stroke();
    ctx.shadowBlur = 0;
  }

  dispose() {
    // Nothing to clean up
  }
}
