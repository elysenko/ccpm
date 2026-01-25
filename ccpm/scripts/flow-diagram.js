#!/usr/bin/env node

/**
 * ASCII Flow Diagram Renderer
 *
 * Generates static ASCII user flow diagrams using Unicode box-drawing characters.
 * No external dependencies - pure JavaScript implementation.
 *
 * Usage:
 *   node flow-diagram.js < graph.json
 *   echo '{"nodes":[], "edges":[]}' | node flow-diagram.js
 */

class FlowDiagram {
  constructor() {
    this.nodes = new Map();
    this.edges = [];
    this.minBoxWidth = 17;
    this.maxBoxWidth = 40;
  }

  /**
   * Add a node to the diagram
   * @param {string} id - Unique node identifier
   * @param {string} label - Display text for the node
   * @param {string} type - Node type: 'start', 'process', 'decision', 'end'
   */
  addNode(id, label, type = 'process') {
    this.nodes.set(id, { id, label, type, row: -1, col: -1 });
  }

  /**
   * Add an edge between nodes
   * @param {string} from - Source node ID
   * @param {string} to - Target node ID
   * @param {string} label - Optional edge label (e.g., 'yes', 'no')
   */
  addEdge(from, to, label = '') {
    this.edges.push({ from, to, label });
  }

  /**
   * Load graph from JSON object
   * @param {Object} data - Graph data with nodes and edges arrays
   */
  loadFromJSON(data) {
    if (data.nodes) {
      for (const node of data.nodes) {
        this.addNode(node.id, node.label, node.type || 'process');
      }
    }
    if (data.edges) {
      for (const edge of data.edges) {
        this.addEdge(edge.from, edge.to, edge.label || '');
      }
    }
  }

  /**
   * Perform topological sort and assign grid positions
   */
  layoutNodes() {
    const inDegree = new Map();
    const outEdges = new Map();

    // Initialize
    for (const [id] of this.nodes) {
      inDegree.set(id, 0);
      outEdges.set(id, []);
    }

    // Count incoming edges
    for (const edge of this.edges) {
      if (this.nodes.has(edge.to)) {
        inDegree.set(edge.to, (inDegree.get(edge.to) || 0) + 1);
      }
      if (this.nodes.has(edge.from)) {
        outEdges.get(edge.from).push(edge.to);
      }
    }

    // Find starting nodes (no incoming edges)
    const queue = [];
    for (const [id, degree] of inDegree) {
      if (degree === 0) {
        queue.push(id);
      }
    }

    // Assign rows using BFS-based topological sort
    let row = 0;
    const rowNodes = [];

    while (queue.length > 0) {
      const currentRow = [...queue];
      rowNodes.push(currentRow);
      queue.length = 0;

      // Assign positions to current row
      for (let col = 0; col < currentRow.length; col++) {
        const node = this.nodes.get(currentRow[col]);
        node.row = row;
        node.col = col;
      }

      // Process children
      for (const id of currentRow) {
        for (const childId of outEdges.get(id)) {
          const newDegree = inDegree.get(childId) - 1;
          inDegree.set(childId, newDegree);
          if (newDegree === 0) {
            queue.push(childId);
          }
        }
      }

      row++;
    }

    return rowNodes;
  }

  /**
   * Calculate box width for text content
   */
  calcBoxWidth(text) {
    const padding = 4; // 2 chars on each side
    const width = text.length + padding;
    return Math.max(this.minBoxWidth, Math.min(width, this.maxBoxWidth));
  }

  /**
   * Wrap text to fit within max width
   */
  wrapText(text, maxWidth) {
    const words = text.split(' ');
    const lines = [];
    let currentLine = '';

    for (const word of words) {
      if (currentLine.length + word.length + 1 <= maxWidth) {
        currentLine += (currentLine ? ' ' : '') + word;
      } else {
        if (currentLine) lines.push(currentLine);
        currentLine = word;
      }
    }
    if (currentLine) lines.push(currentLine);

    return lines;
  }

  /**
   * Render a box with the appropriate style for the node type
   */
  renderBox(label, type, width) {
    const innerWidth = width - 2;
    const lines = this.wrapText(label, innerWidth - 2);
    const result = [];

    // Box characters by type
    const chars = {
      start: { tl: '\u256D', tr: '\u256E', bl: '\u2570', br: '\u256F', h: '\u2500', v: '\u2502' },
      end:   { tl: '\u256D', tr: '\u256E', bl: '\u2570', br: '\u256F', h: '\u2500', v: '\u2502' },
      process: { tl: '\u250C', tr: '\u2510', bl: '\u2514', br: '\u2518', h: '\u2500', v: '\u2502' },
      decision: { tl: '\u25C7', tr: '\u25C7', bl: '\u25C7', br: '\u25C7', h: '\u2500', v: '\u2502' }
    };

    const c = chars[type] || chars.process;

    // Top border
    result.push(c.tl + c.h.repeat(innerWidth) + c.tr);

    // Content lines
    for (const line of lines) {
      const padding = innerWidth - line.length;
      const leftPad = Math.floor(padding / 2);
      const rightPad = padding - leftPad;
      let suffix = type === 'decision' ? '?' : '';
      if (lines.indexOf(line) !== lines.length - 1) suffix = '';
      const content = ' '.repeat(leftPad) + line + suffix + ' '.repeat(rightPad - suffix.length);
      result.push(c.v + content + c.v);
    }

    // Bottom border
    result.push(c.bl + c.h.repeat(innerWidth) + c.br);

    return result;
  }

  /**
   * Center text within a given width
   */
  centerText(text, width) {
    if (text.length >= width) {
      return text; // Text is already wider than target width
    }
    const padding = width - text.length;
    const leftPad = Math.floor(padding / 2);
    return ' '.repeat(leftPad) + text + ' '.repeat(padding - leftPad);
  }

  /**
   * Render the complete diagram
   */
  render(title = '') {
    if (this.nodes.size === 0) {
      return 'No nodes to render.';
    }

    const rowNodes = this.layoutNodes();
    const output = [];

    // Calculate column widths
    const colWidths = [];
    const maxCols = Math.max(...rowNodes.map(r => r.length));

    for (let col = 0; col < maxCols; col++) {
      let maxWidth = this.minBoxWidth;
      for (const row of rowNodes) {
        if (col < row.length) {
          const node = this.nodes.get(row[col]);
          const width = this.calcBoxWidth(node.label);
          maxWidth = Math.max(maxWidth, width);
        }
      }
      colWidths.push(maxWidth);
    }

    // Add title if provided
    if (title) {
      const baseWidth = colWidths.reduce((a, b) => a + b, 0) + (colWidths.length - 1) * 4;
      const titleText = `User Flow: ${title}`;
      const totalWidth = Math.max(baseWidth, titleText.length);
      output.push('');
      output.push(this.centerText(titleText, totalWidth));
      output.push('');
    }

    // Render each row
    for (let rowIdx = 0; rowIdx < rowNodes.length; rowIdx++) {
      const row = rowNodes[rowIdx];
      const boxes = [];

      // Render boxes for this row
      for (let colIdx = 0; colIdx < row.length; colIdx++) {
        const node = this.nodes.get(row[colIdx]);
        const width = colWidths[colIdx];
        boxes.push(this.renderBox(node.label, node.type, width));
      }

      // Calculate indent to center single-column rows
      let indent = '';
      if (row.length === 1 && maxCols > 1) {
        const totalWidth = colWidths.reduce((a, b) => a + b, 0) + (colWidths.length - 1) * 4;
        const boxWidth = colWidths[0];
        indent = ' '.repeat(Math.floor((totalWidth - boxWidth) / 2));
      }

      // Output box lines
      const maxLines = Math.max(...boxes.map(b => b.length));
      for (let lineIdx = 0; lineIdx < maxLines; lineIdx++) {
        const lineParts = [];
        for (let colIdx = 0; colIdx < boxes.length; colIdx++) {
          const box = boxes[colIdx];
          const line = lineIdx < box.length ? box[lineIdx] : ' '.repeat(colWidths[colIdx]);
          lineParts.push(line);
        }
        output.push(indent + lineParts.join('    '));
      }

      // Draw connectors to next row
      if (rowIdx < rowNodes.length - 1) {
        const nextRow = rowNodes[rowIdx + 1];
        const currentNode = row[0];
        const node = this.nodes.get(currentNode);

        // Find edges from current row to next row
        const edgesToNext = this.edges.filter(e =>
          row.includes(e.from) && nextRow.includes(e.to)
        );

        // Simple connector for single path
        if (row.length === 1 && nextRow.length === 1) {
          const width = colWidths[0];
          const center = Math.floor(width / 2);
          output.push(indent + ' '.repeat(center) + '\u2502');
          output.push(indent + ' '.repeat(center) + '\u25BC');
        }
        // Branching connector for decision nodes
        else if (row.length === 1 && nextRow.length > 1 && node.type === 'decision') {
          const totalWidth = colWidths.reduce((a, b) => a + b, 0) + (colWidths.length - 1) * 4;
          const boxWidth = colWidths[0];
          const boxCenter = Math.floor((totalWidth - boxWidth) / 2) + Math.floor(boxWidth / 2);

          // Find edge labels
          const leftEdge = edgesToNext.find(e => e.to === nextRow[0]);
          const rightEdge = edgesToNext.find(e => e.to === nextRow[nextRow.length - 1]);
          const leftLabel = leftEdge?.label || 'yes';
          const rightLabel = rightEdge?.label || 'no';

          // Draw branching lines with labels
          const leftCenter = Math.floor(colWidths[0] / 2);
          const sliceForRight = colWidths.slice(0, -1);
          const rightStart = (sliceForRight.length > 0 ? sliceForRight.reduce((a, b) => a + b, 0) : 0) + (colWidths.length - 1) * 4;
          const rightCenter = rightStart + Math.floor(colWidths[colWidths.length - 1] / 2);

          // Vertical from decision
          output.push(' '.repeat(boxCenter) + '\u2502');

          // Label line
          const labelLine = ' '.repeat(Math.max(0, leftCenter - 2)) + leftLabel.padEnd(4) +
                           '\u2502' + ' '.repeat(Math.max(0, rightCenter - leftCenter - leftLabel.length - 6)) + rightLabel;
          output.push(labelLine);

          // Horizontal branch line
          let branchLine = ' '.repeat(leftCenter) + '\u250C' +
                          '\u2500'.repeat(Math.max(0, boxCenter - leftCenter - 1)) +
                          '\u2534' +
                          '\u2500'.repeat(Math.max(0, rightCenter - boxCenter - 1)) +
                          '\u2510';
          output.push(branchLine);

          // Down arrows
          output.push(' '.repeat(leftCenter) + '\u25BC' +
                     ' '.repeat(Math.max(0, rightCenter - leftCenter - 1)) + '\u25BC');
        }
        // Multiple paths converging
        else if (row.length > 1 && nextRow.length === 1) {
          const totalWidth = colWidths.reduce((a, b) => a + b, 0) + (colWidths.length - 1) * 4;
          const nextBoxWidth = colWidths[0];
          const nextCenter = Math.floor((totalWidth - nextBoxWidth) / 2) + Math.floor(nextBoxWidth / 2);

          // Down arrows from each box
          let arrowLine = '';
          for (let colIdx = 0; colIdx < row.length; colIdx++) {
            const offset = colWidths.slice(0, colIdx).reduce((a, b) => a + b, 0) + colIdx * 4;
            const center = offset + Math.floor(colWidths[colIdx] / 2);
            arrowLine = arrowLine.padEnd(center) + '\u2502';
          }
          output.push(arrowLine);

          // Converging horizontal line
          const leftCenter = Math.floor(colWidths[0] / 2);
          const sliceForConv = colWidths.slice(0, -1);
          const rightStart = (sliceForConv.length > 0 ? sliceForConv.reduce((a, b) => a + b, 0) : 0) + (row.length - 1) * 4;
          const rightCenter = rightStart + Math.floor(colWidths[row.length - 1] / 2);

          let convergeLine = ' '.repeat(leftCenter) + '\u2514' +
                            '\u2500'.repeat(Math.max(0, nextCenter - leftCenter - 1)) +
                            '\u252C' +
                            '\u2500'.repeat(Math.max(0, rightCenter - nextCenter - 1)) +
                            '\u2518';
          output.push(convergeLine);

          // Down arrow to next
          output.push(' '.repeat(Math.floor((totalWidth - nextBoxWidth) / 2) + Math.floor(nextBoxWidth / 2)) + '\u25BC');
        }
        // Simple single connector for aligned rows
        else {
          const width = colWidths[0];
          const center = Math.floor(width / 2);
          output.push(indent + ' '.repeat(center) + '\u2502');
          output.push(indent + ' '.repeat(center) + '\u25BC');
        }
      }
    }

    return output.join('\n');
  }
}

// CLI interface
if (typeof process !== 'undefined' && process.argv) {
  const args = process.argv.slice(2);

  // Check for help
  if (args.includes('-h') || args.includes('--help')) {
    console.log(`
ASCII Flow Diagram Renderer

Usage:
  echo '<json>' | node flow-diagram.js [options]
  node flow-diagram.js [options] < graph.json

Options:
  -t, --title <text>  Set diagram title
  -h, --help          Show this help

JSON Format:
  {
    "title": "Optional title",
    "nodes": [
      { "id": "start", "label": "Begin", "type": "start" },
      { "id": "step1", "label": "Do something", "type": "process" },
      { "id": "check", "label": "Is valid", "type": "decision" },
      { "id": "end", "label": "Done", "type": "end" }
    ],
    "edges": [
      { "from": "start", "to": "step1" },
      { "from": "step1", "to": "check" },
      { "from": "check", "to": "end", "label": "yes" }
    ]
  }

Node Types:
  start    - Rounded box (entry point)
  process  - Square box (action step)
  decision - Diamond box (branch point)
  end      - Rounded box (exit point)
`);
    process.exit(0);
  }

  // Parse title argument
  let title = '';
  const titleIdx = args.findIndex(a => a === '-t' || a === '--title');
  if (titleIdx !== -1 && args[titleIdx + 1]) {
    title = args[titleIdx + 1];
  }

  // Read from stdin
  let input = '';
  process.stdin.setEncoding('utf8');

  process.stdin.on('data', (chunk) => {
    input += chunk;
  });

  process.stdin.on('end', () => {
    try {
      const data = JSON.parse(input);
      const diagram = new FlowDiagram();
      diagram.loadFromJSON(data);

      const diagramTitle = title || data.title || '';
      console.log(diagram.render(diagramTitle));
    } catch (err) {
      console.error('Error:', err.message);
      process.exit(1);
    }
  });
}

// Export for use as module
if (typeof module !== 'undefined' && module.exports) {
  module.exports = FlowDiagram;
}
