// Cherry blossom petals drifting over the login screen, the greeter twin of the Caelestia lock's
// PetalField (config/caelestia/lock/PetalField.qml), without the shell's services.
// - they fall slowly, blown by the same wind as windowfx's petals
// - the mouse pointer pushes them away
// - burst(): the login box bursts into petals that a gust blows away
pragma ComponentBehavior: Bound

import QtQuick

Item {
    id: root

    property var colours: ["#FFA8CF"]
    // Where the burst comes from (the login box), in this item's coordinates
    property rect burstRect: Qt.rect(width / 2 - 100, height / 2 - 100, 200, 200)

    readonly property real unit: Math.max(0.6, height / 1440)
    readonly property int ambientCount: 60
    readonly property int burstCount: 120
    // Wind, the same direction as windowfx (wind_x = 1.0, wind_y = -0.45)
    readonly property real windX: 1.0
    readonly property real windY: -0.45

    property bool bursting
    property real time
    property var sim: []

    function pickColour(): color {
        // One petal in a hundred is a deep red rose petal
        if (Math.random() < 0.01)
            return "#B0102C";
        return colours[Math.floor(Math.random() * colours.length)];
    }

    // An ambient petal, either anywhere on screen (first frame) or just above it
    function spawnAmbient(p: var, anywhere: bool): void {
        p.depth = 0.35 + Math.random() * 0.65;
        p.size = (9 + 17 * p.depth) * unit;
        p.x = -0.25 * width + Math.random() * 1.25 * width;
        p.y = anywhere ? Math.random() * height : -40 - Math.random() * 120;
        p.vx = 0;
        p.vy = 0;
        p.rot = Math.random() * 360;
        p.spin = (Math.random() - 0.5) * 90;
        p.phase = Math.random() * Math.PI * 2;
        p.flipSpeed = 0.6 + Math.random() * 1.4;
        p.sway = 0.4 + Math.random() * 0.8;
        p.alpha = 0.45 + 0.5 * p.depth;
        p.live = true;
        p.colour = pickColour();
    }

    function spawnBurst(p: var): void {
        const r = burstRect;
        p.depth = 0.6 + Math.random() * 0.4;
        p.size = (12 + 16 * p.depth) * unit;
        p.x = r.x + Math.random() * r.width;
        p.y = r.y + Math.random() * r.height;
        // Outwards from the centre of the box, then the wind takes them
        const dx = p.x - (r.x + r.width / 2);
        const dy = p.y - (r.y + r.height / 2);
        const d = Math.max(1, Math.hypot(dx, dy));
        const speed = (150 + Math.random() * 450) * unit;
        p.vx = dx / d * speed + windX * 250 * unit * Math.random();
        p.vy = dy / d * speed + windY * 250 * unit * Math.random();
        p.rot = Math.random() * 360;
        p.spin = (Math.random() - 0.5) * 720;
        p.phase = Math.random() * Math.PI * 2;
        p.flipSpeed = 2 + Math.random() * 4;
        p.sway = 0.3;
        p.alpha = 0.95;
        p.live = true;
        p.colour = pickColour();
    }

    function init(): void {
        const s = [];
        for (let i = 0; i < ambientCount + burstCount; i++) {
            const p = {
                live: false,
                x: -100,
                y: -100,
                alpha: 0
            };
            if (i < ambientCount)
                spawnAmbient(p, true);
            s.push(p);
        }
        sim = s;
    }

    function burst(): void {
        if (bursting)
            return;
        bursting = true;
        for (let i = ambientCount; i < sim.length; i++)
            spawnBurst(sim[i]);
    }

    // After a wrong password: the gust calms down, new petals fall again
    function calm(): void {
        bursting = false;
        for (let i = 0; i < ambientCount; i++)
            if (!sim[i].live)
                spawnAmbient(sim[i], false);
    }

    function step(dt: real): void {
        time += dt;
        const w = width;
        const h = height;
        const hovered = hover.hovered;
        const mx = hover.point.position.x;
        const my = hover.point.position.y;
        const pushRadius = 150 * unit;
        const drag = Math.exp(-(bursting ? 0.6 : 2.2) * dt);

        for (let i = 0; i < sim.length; i++) {
            const p = sim[i];
            const item = petals.itemAt(i);
            if (!item)
                continue;
            if (!p.live) {
                item.visible = false;
                continue;
            }

            // Pushed away by the mouse pointer
            if (hovered && !bursting) {
                const dx = p.x - mx;
                const dy = p.y - my;
                const d = Math.hypot(dx, dy);
                if (d < pushRadius && d > 0.5) {
                    const f = (1 - d / pushRadius) * 2600 * unit * dt;
                    p.vx += dx / d * f;
                    p.vy += dy / d * f;
                    p.spin += (Math.random() - 0.5) * 400 * dt;
                }
            }

            if (bursting) {
                // A gust: everything is blown away
                p.vx += windX * 1100 * unit * dt;
                p.vy += windY * 1100 * unit * dt;
            }
            p.vx *= drag;
            p.vy *= drag;

            // Slow fall, a light breeze and some sway; far petals are slower
            const fall = bursting ? 0 : (35 + 45 * p.depth) * unit;
            const breeze = bursting ? 0 : (25 + 35 * p.depth) * unit;
            const sway = Math.sin(time * p.sway + p.phase) * 30 * unit;
            p.x += (breeze * windX + sway + p.vx) * dt;
            p.y += (fall + p.vy) * dt;
            p.rot += p.spin * dt;

            const margin = 60 * unit;
            if (p.y > h + margin || p.x > w + margin || p.x < -0.3 * w - margin || p.y < -h) {
                if (i < ambientCount && !bursting)
                    spawnAmbient(p, false);
                else
                    p.live = false;
            }

            item.visible = p.live;
            item.x = p.x - p.size / 2;
            item.y = p.y - p.size / 2;
            item.width = p.size;
            item.height = p.size * 1.12;
            item.rotation = p.rot;
            item.flip = Math.cos(time * p.flipSpeed + p.phase);
            item.opacity = p.alpha;
            item.colour = p.colour;
        }
    }

    // The size is only known once laid out
    onWidthChanged: if (width > 0 && height > 0 && sim.length === 0) init()
    onHeightChanged: if (width > 0 && height > 0 && sim.length === 0) init()

    // Passive: it does not take the mouse from the controls above
    HoverHandler {
        id: hover
    }

    FrameAnimation {
        running: root.visible && root.sim.length > 0
        onTriggered: root.step(Math.min(frameTime, 0.05))
    }

    Repeater {
        id: petals

        model: root.ambientCount + root.burstCount

        PetalShape {
            visible: false
        }
    }
}
