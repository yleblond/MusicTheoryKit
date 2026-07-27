/* Builds the circle-of-fifths dial (#cof-dial): a wedge-per-note
   color ring, computed from polar geometry rather than hand-typed
   coordinates, so the twelve keys read as twelve distinct colors. */

(function () {
  var NOTES = ["C", "G", "D", "A", "E", "B", "F♯", "D♭", "A♭", "E♭", "B♭", "F"];
  var CX = 190, CY = 190;
  var R_RING_OUT = 172, R_RING_IN = 132, R_LABEL = 152, R_STAR = 108;

  function polar(r, deg) {
    var rad = ((deg - 90) * Math.PI) / 180;
    return { x: CX + r * Math.cos(rad), y: CY + r * Math.sin(rad) };
  }

  function el(tag, attrs) {
    var node = document.createElementNS("http://www.w3.org/2000/svg", tag);
    for (var k in attrs) node.setAttribute(k, attrs[k]);
    return node;
  }

  function wedgePath(rIn, rOut, d0, d1) {
    var p0o = polar(rOut, d0), p1o = polar(rOut, d1);
    var p1i = polar(rIn, d1), p0i = polar(rIn, d0);
    return [
      "M", p0o.x.toFixed(1), p0o.y.toFixed(1),
      "A", rOut, rOut, 0, 0, 1, p1o.x.toFixed(1), p1o.y.toFixed(1),
      "L", p1i.x.toFixed(1), p1i.y.toFixed(1),
      "A", rIn, rIn, 0, 0, 0, p0i.x.toFixed(1), p0i.y.toFixed(1),
      "Z"
    ].join(" ");
  }

  var svg = document.getElementById("cof-dial");
  if (!svg) return;

  var rotor = document.getElementById("cof-rotor");
  var starPts = [];

  for (var i = 0; i < 12; i++) {
    var d0 = i * 30 - 15, d1 = i * 30 + 15;
    var hue = i * 30;
    var isRoot = i === 0;

    rotor.appendChild(
      el("path", {
        class: "wedge" + (isRoot ? " wedge--root" : ""),
        d: wedgePath(R_RING_IN, R_RING_OUT, d0, d1),
        fill: "hsl(" + hue + ", 68%, 56%)"
      })
    );

    var pLabel = polar(R_LABEL, i * 30);
    var label = el("text", { class: "tick-label", x: pLabel.x, y: pLabel.y });
    label.textContent = NOTES[i];
    rotor.appendChild(label);

    starPts.push(polar(R_STAR, i * 30));
  }

  var starPath = "";
  for (var s = 0; s < 12; s++) {
    var from = starPts[s];
    var to = starPts[(s + 7) % 12];
    starPath += (s === 0 ? "M" : "L") + from.x.toFixed(1) + "," + from.y.toFixed(1) + " ";
    starPath += "L" + to.x.toFixed(1) + "," + to.y.toFixed(1) + " ";
  }
  var star = el("path", { class: "fifths-path", d: starPath });
  rotor.insertBefore(star, rotor.firstChild);
})();
