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
