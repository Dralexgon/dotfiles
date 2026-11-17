// Predatoria's crest: an evil bat diving at you, in a blood gradient with a crimson glow.
// Bat shape: "Evil bat" by Lorc, https://game-icons.net/1x1/lorc/evil-bat.html (CC BY 3.0),
// drawn from its SVG path on the canvas so the greeter doesn't need the Qt SVG module.
import QtQuick

Canvas {
    id: c
    antialiasing: true
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    // in the icon's 512x512 viewBox; the bat itself spans 475x453 from (17, 39)
    readonly property string bat: "M200.87 39.725C44.31 80.87-16.78 302.325 36.948 433.995 23.912 307.28 59.464 188.886 126.674 116.51c-22.972 99.05-25 194.382 10.353 258.826-18.214-78.32-11.397-174.74 18.254-239.406-1.843 54.862 7.87 111.337 31.788 155.718-12.736-108.023 47.59-42.41 65.168-8.06 4.94 15.805 3.993 29.124-.433 40.47-5.83 14.942-18.294 26.96-34.018 34.897-35.8 18.074-54.695 40.503-60.52 62.78-5.824 22.28 1.996 43.443 16.5 56.396 14.5 12.952 36.138 18.04 56.32 9.233 16.745-7.305 31.693-23.562 41.895-50.072 8.293 6.156 15.268 13.8 20.868 23 .4-33.196 9.715-61.208 23.945-86.364-34.537 9.54-63.36 25.552-88.33 45.94 9.908 1.663 18.956 4.295 27.123 7.92-8.903 24.836-21.404 37.37-32.984 42.42-13.44 5.866-26.794 2.587-36.39-5.985-9.598-8.57-14.97-22.088-10.878-37.74 4.092-15.65 18.256-34.373 50.883-50.845 18.94-9.56 35.138-24.64 42.998-44.787 7-17.947 6.885-39.556-2.85-62.885 23.456-33.637 66.618-69.27 55.658 23.683 23.918-44.38 33.632-100.856 31.788-155.718 29.652 64.666 36.466 161.086 18.252 239.406 35.354-64.444 33.326-159.775 10.354-258.826 67.21 72.377 102.764 190.772 89.73 317.488C525.87 302.324 464.78 80.87 308.22 39.726h-.003c31.215 86.954 42.704 157.88-53.672 190.813-96.376-32.935-84.888-103.86-53.672-190.815h-.002zm16.083 57.62c-4.84 10.928-8.443 22.143-8.443 34.83 0 33.612 18.97 61.84 46.437 77.044 27.21-15.274 45.383-43.624 45.383-77.046 0-12.776-3.644-23.793-8.443-34.83 0 0-21.217 54.584-36.94 67.68-15.87-13.032-37.994-67.68-37.994-67.68z"

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const s = Math.min(width / 475, height / 453);
        ctx.translate(width / 2, height / 2);
        ctx.scale(s, s);
        ctx.translate(-254.5, -265.5); // center of the bat's bounding box

        const g = ctx.createLinearGradient(0, 39, 180, 492);
        g.addColorStop(0, "#FF4A5E");
        g.addColorStop(0.55, "#D3203C");
        g.addColorStop(1, "#5C0A14");

        ctx.path = bat;
        ctx.shadowColor = Qt.rgba(211 / 255, 32 / 255, 60 / 255, 0.5);
        ctx.shadowBlur = 14;
        ctx.fillStyle = g;
        ctx.fill();
        ctx.shadowBlur = 0;
        ctx.lineWidth = 2 / s;
        ctx.strokeStyle = "#2A0008";
        ctx.stroke();
    }
}
