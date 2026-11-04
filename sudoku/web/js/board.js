// Renders a 9x9 board into a container and keeps the DOM in sync with a view model.
import { rowOf, colOf, boxOf, UNITS, PEERS } from './engine.js';

export class Board {
  constructor(el, { onSelect } = {}) {
    this.el = el;
    this.el.classList.add('board');
    this.cells = [];
    for (let i = 0; i < 81; i++) {
      const c = document.createElement('div');
      c.className = 'cell';
      c.dataset.i = i;
      if (colOf(i) % 3 === 2 && colOf(i) !== 8) c.classList.add('br');
      if (rowOf(i) % 3 === 2 && rowOf(i) !== 8) c.classList.add('bb');
      c.setAttribute('role', 'gridcell');
      c.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        onSelect && onSelect(i);
      });
      this.el.appendChild(c);
      this.cells.push(c);
    }
    this.el.setAttribute('role', 'grid');
    this.el.setAttribute('aria-label', 'Sudoku board');
  }

  // model: {grid, given, notes (masks), selected, solution?, showMistakes,
  //         highlightPeers, highlightSame, overlay?: {cand, units, cells, marks, places, elims, reveal}}
  render(m) {
    const sel = m.selected ?? -1;
    const selVal = sel >= 0 ? m.grid[sel] : 0;
    const peers = new Set(sel >= 0 && m.highlightPeers !== false ? PEERS[sel] : []);
    const conflicts = conflictSet(m.grid);
    const ov = m.overlay;
    const unitCells = new Set();
    if (ov && ov.units) for (const u of ov.units) for (const c of UNITS[u].cells) unitCells.add(c);
    const patternCells = new Set(ov && ov.reveal ? ov.cells || [] : []);
    const placeMap = new Map(ov && ov.reveal ? (ov.places || []).map(([c, d]) => [c, d]) : []);
    const elimMap = new Map();
    const markMap = new Map();
    if (ov && ov.reveal) {
      for (const [c, d] of ov.elims || []) elimMap.set(c * 10 + d, true);
      for (const [c, d, k] of ov.marks || []) markMap.set(c * 10 + d, k);
    }
    for (let i = 0; i < 81; i++) {
      const c = this.cells[i];
      const v = m.grid[i];
      const cls = ['cell'];
      if (colOf(i) % 3 === 2 && colOf(i) !== 8) cls.push('br');
      if (rowOf(i) % 3 === 2 && rowOf(i) !== 8) cls.push('bb');
      if (m.given[i]) cls.push('given');
      else if (v) cls.push('entered');
      if (i === sel) cls.push('selected');
      else if (peers.has(i)) cls.push('peer');
      if (v && selVal && v === selVal && m.highlightSame !== false && i !== sel) cls.push('same');
      if (v && !m.given[i] && m.showMistakes && m.solution && m.solution[i] !== v) cls.push('wrong');
      else if (v && conflicts.has(i)) cls.push('conflict');
      if (unitCells.has(i)) cls.push('hl-unit');
      if (patternCells.has(i)) cls.push('hl-pattern');
      if (placeMap.has(i)) cls.push('hl-place');
      if (m.flash && m.flash.has(i)) cls.push('flash');
      const clsStr = cls.join(' ');
      if (c.className !== clsStr) c.className = clsStr;

      let html;
      if (v) {
        html = `<span class="v">${v}</span>`;
      } else if (placeMap.has(i)) {
        html = `<span class="v ghost">${placeMap.get(i)}</span>`;
      } else {
        const mask = ov && ov.cand ? ov.cand[i] : m.notes[i];
        if (mask) {
          html = '<div class="notes">';
          for (let d = 1; d <= 9; d++) {
            if (!(mask & (1 << d))) { html += '<span></span>'; continue; }
            const key = i * 10 + d;
            let k = '';
            if (elimMap.has(key)) k = 'elim';
            else if (markMap.has(key)) k = markMap.get(key);
            else if (selVal && d === selVal && m.highlightSame !== false) k = 'samenote';
            html += `<span class="${k}">${d}</span>`;
          }
          html += '</div>';
        } else html = '';
      }
      if (c._html !== html) { c.innerHTML = html; c._html = html; }
      c.setAttribute('aria-label', `Row ${rowOf(i) + 1} column ${colOf(i) + 1}${v ? ', ' + v : ', empty'}`);
    }
  }
}

export function conflictSet(grid) {
  const out = new Set();
  for (const u of UNITS) {
    const seen = new Map();
    for (const c of u.cells) {
      const v = grid[c];
      if (!v) continue;
      if (seen.has(v)) { out.add(c); out.add(seen.get(v)); } else seen.set(v, c);
    }
  }
  return out;
}

export { boxOf };
