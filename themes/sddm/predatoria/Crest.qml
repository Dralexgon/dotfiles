// Predatoria's crest: bat wings around a drop of blood, with two fangs
import QtQuick

Canvas {
    id: c
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const s = Math.min(width / 300, height / 130);
        ctx.translate(width / 2, height * 0.5);
        ctx.scale(s, s);

        // wings
        for (const side of [1, -1]) {
            ctx.save();
            ctx.scale(side, 1);
            ctx.beginPath();
            ctx.moveTo(-18, -14);
            ctx.quadraticCurveTo(-70, -62, -145, -46);
            ctx.quadraticCurveTo(-122, -20, -128, 10);
            ctx.quadraticCurveTo(-106, -6, -92, 22);
            ctx.quadraticCurveTo(-72, 0, -54, 28);
            ctx.quadraticCurveTo(-36, 8, -18, 26);
            ctx.closePath();
            const g = ctx.createLinearGradient(-145, -50, -18, 26);
            g.addColorStop(0, "#2A0008");
            g.addColorStop(1, "#8A0012");
            ctx.fillStyle = g;
            ctx.fill();
            ctx.lineWidth = 2;
            ctx.strokeStyle = "#D3203C";
            ctx.stroke();
            // wing bones
            ctx.beginPath();
            ctx.moveTo(-18, -10);
            ctx.lineTo(-128, 8);
            ctx.moveTo(-18, -6);
            ctx.lineTo(-92, 20);
            ctx.moveTo(-18, -2);
            ctx.lineTo(-54, 26);
            ctx.lineWidth = 1;
            ctx.strokeStyle = "#5C0A14";
            ctx.stroke();
            ctx.restore();
        }

        // blood drop
        ctx.beginPath();
        ctx.moveTo(0, -52);
        ctx.bezierCurveTo(8, -30, 24, -10, 24, 12);
        ctx.arc(0, 12, 24, 0, Math.PI, false);
        ctx.bezierCurveTo(-24, -10, -8, -30, 0, -52);
        ctx.closePath();
        const dg = ctx.createLinearGradient(-20, -50, 20, 36);
        dg.addColorStop(0, "#FF4A5E");
        dg.addColorStop(0.55, "#D3203C");
        dg.addColorStop(1, "#5C0A14");
        ctx.fillStyle = dg;
        ctx.fill();
        ctx.lineWidth = 2;
        ctx.strokeStyle = "#2A0008";
        ctx.stroke();
        // glint
        ctx.beginPath();
        ctx.ellipse(-18, -14, 12, 24); // x, y, w, h
        ctx.fillStyle = "rgba(255,240,241,0.45)";
        ctx.fill();

        // fangs under the drop
        for (const side of [1, -1]) {
            ctx.beginPath();
            ctx.moveTo(side * 6, 40);
            ctx.lineTo(side * 16, 40);
            ctx.lineTo(side * 11, 60);
            ctx.closePath();
            ctx.fillStyle = "#EFE3E4";
            ctx.fill();
        }
    }
}
