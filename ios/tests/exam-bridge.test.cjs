const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const swift = fs.readFileSync(path.join(__dirname, '../GeoGebraIOS/GeoGebraViewController.swift'), 'utf8');
const script = swift.match(/private static let nativeBridgeScript = #"""\n([\s\S]*?)\n    """#/)[1];

function host() {
    const events = [];
    const handlers = new Proxy({}, {
        get: (_, name) => ({ postMessage: body => events.push({ name, body }) })
    });
    const context = { window: { webkit: { messageHandlers: handlers } } };
    vm.runInNewContext(script, context);
    return { window: context.window, events };
}

test('engine start requires native confirmation and rejects a revoked lock', () => {
    const { window, events } = host();
    assert.equal(window.GeoGebraIOSExamBridge.canStart(), false);
    assert.equal(events.pop().name, 'examLockRequired');
    window.GeoGebraIOSExamLockReady = true;
    assert.equal(window.GeoGebraIOSExamBridge.canStart(), true);
    window.GeoGebraIOSExamLockReady = false;
    assert.equal(window.GeoGebraIOSExamBridge.canStart(), false);
});

test('engine lifecycle transitions reach the native host in order', () => {
    const { window, events } = host();
    for (const state of ['ACTIVE', 'FINISHED', 'IDLE']) {
        window.GeoGebraIOSExamBridge.stateChanged(state);
    }
    assert.deepEqual(events.map(event => event.name), ['examState', 'examState', 'examState']);
    assert.deepEqual(events.map(event => event.body.state), ['ACTIVE', 'FINISHED', 'IDLE']);
});

test('a fresh web process never inherits a previous lock confirmation', () => {
    const first = host();
    first.window.GeoGebraIOSExamLockReady = true;
    const recovered = host();
    assert.equal(recovered.window.GeoGebraIOSExamBridge.canStart(), false);
});

test('recovery start time and checkpoint metadata cross the bridge unchanged', () => {
    const { window, events } = host();
    assert.equal(window.GeoGebraIOSExamBridge.resumeStartTime(), 0);
    window.GeoGebraIOSResumeStart = 1700000000123;
    assert.equal(window.GeoGebraIOSExamBridge.resumeStartTime(), 1700000000123);
    window.GeoGebraIOSExamBridge.checkpointMeta(1700000000123, 'GENERIC');
    assert.equal(events[0].name, 'examMeta');
    assert.equal(events[0].body.startTime, 1700000000123);
    assert.equal(events[0].body.examType, 'GENERIC');
});

test('skibidi command accepts either case, ignores other input and IME composition', () => {
    const script = swift.match(/private static let examCommandScript = #"""\n([\s\S]*?)\n    """#/)[1];
    let listener;
    let requests = 0;
    vm.runInNewContext(script, {
        document: { addEventListener: (_, callback) => { listener = callback; } },
        window: { webkit: { messageHandlers: { examToggle: { postMessage: () => requests++ } } } }
    });
    for (const [text, composing, expected] of [
        ['skibidi', false, 1], ['Skibidi', false, 2], ['x+1', false, 2], ['skibidi', true, 2]
    ]) {
        listener({ key: 'Enter', isComposing: composing,
            target: { closest: () => ({ value: text }) },
            preventDefault() {}, stopImmediatePropagation() {} });
        assert.equal(requests, expected);
    }
});

test('native interruptions can reach the engine summary', () => {
    const { window } = host();
    let interruptions = 0;
    window.GeoGebraIOSExamBridge.setInterruptionHandler(() => interruptions++);
    window.GeoGebraIOSInterruptionHandler();
    assert.equal(interruptions, 1);
});
