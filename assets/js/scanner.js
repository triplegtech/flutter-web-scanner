/**
 * omni_qrcode_barcode_web_reader — browser interop layer.
 *
 * Injected at runtime by WebScannerPlatform and exposed as `window.omniScanner`.
 * Every entry point resolves with a JSON envelope and never rejects:
 *
 *   {"ok": true,  "data": <payload>}
 *   {"ok": false, "kind": "<ScannerFailureKind>", "message": "<detail>"}
 *
 * `kind` values must stay in sync with the ScannerFailureKind enum in
 * lib/src/models/scanner_failure.dart.
 */
(function () {
  'use strict';

  var VERSION = 2;

  // Re-injection happens on hot restart. Redefining the namespace would orphan
  // the sessions the previous closure still owns, so bail out when a compatible
  // build is already installed.
  if (window.omniScanner && window.omniScanner.version === VERSION) {
    return;
  }

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  /**
   * Camera selection and constraint negotiation can only be debugged against
   * real hardware, usually through a browser console on someone else's phone.
   * Logging stays available but silent until switched on with
   * `window.omniScanner.debug = true`.
   *
   * @param {string} message
   * @param {...*} details
   */
  function logDebug(message) {
    if (!window.omniScanner || !window.omniScanner.debug) return;
    var args = Array.prototype.slice.call(arguments, 1);
    console.debug.apply(console, ['[omniScanner] ' + message].concat(args));
  }

  // ---------------------------------------------------------------------------
  // Envelope helpers
  // ---------------------------------------------------------------------------

  var Kind = {
    permissionDenied: 'permissionDenied',
    noCameraFound: 'noCameraFound',
    cameraInUse: 'cameraInUse',
    overconstrained: 'overconstrained',
    engineUnavailable: 'engineUnavailable',
    insecureContext: 'insecureContext',
    startFailed: 'startFailed',
    unknown: 'unknown',
  };

  /**
   * @param {*} data
   * @returns {string} success envelope
   */
  function ok(data) {
    return JSON.stringify({ ok: true, data: data === undefined ? null : data });
  }

  /**
   * @param {string} kind a ScannerFailureKind name
   * @param {*} message
   * @returns {string} failure envelope
   */
  function fail(kind, message) {
    return JSON.stringify({ ok: false, kind: kind, message: String(message) });
  }

  /**
   * Maps a getUserMedia DOMException onto a ScannerFailureKind.
   *
   * @param {*} error
   * @returns {string}
   */
  function kindFromError(error) {
    var name = (error && error.name) || '';
    switch (name) {
      case 'NotAllowedError':
      case 'PermissionDeniedError':
      case 'SecurityError':
        return Kind.permissionDenied;
      case 'NotFoundError':
      case 'DevicesNotFoundError':
        return Kind.noCameraFound;
      case 'NotReadableError':
      case 'TrackStartError':
      case 'AbortError':
        return Kind.cameraInUse;
      case 'OverconstrainedError':
      case 'ConstraintNotSatisfiedError':
        return Kind.overconstrained;
      default:
        return Kind.unknown;
    }
  }

  /**
   * @param {*} error
   * @returns {string}
   */
  function describe(error) {
    if (!error) return 'unknown error';
    if (typeof error === 'string') return error;
    var name = error.name ? error.name + ': ' : '';
    return name + (error.message || String(error));
  }

  // ---------------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------------

  /**
   * Reads ZXing off `window` at call time rather than at script-evaluation
   * time. 1.x captured it into a module-level const, so an app whose ZXing tag
   * finished loading after Flutter booted saw `undefined` forever.
   *
   * @returns {*} the ZXing namespace, or undefined
   */
  function zxing() {
    return window.ZXing;
  }

  /** @returns {boolean} */
  function hasNativeDetector() {
    return typeof window.BarcodeDetector === 'function';
  }

  /** @returns {boolean} */
  function hasMediaDevices() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia);
  }

  /** @returns {string} envelope describing engine and platform support */
  function probeEnvironment() {
    return ok({
      zxingLoaded: !!zxing(),
      nativeSupported: hasNativeDetector(),
      // getUserMedia is simply absent outside a secure context, so this
      // distinguishes "blocked by HTTP" from "denied by the user".
      secureContext: window.isSecureContext === true && hasMediaDevices(),
      // Format support is resolved lazily when a native session starts, since
      // getSupportedFormats is async and this probe is not.
      nativeFormats: [],
    });
  }

  // ---------------------------------------------------------------------------
  // Capabilities
  // ---------------------------------------------------------------------------

  /**
   * Serialises MediaTrackCapabilities into plain JSON.
   *
   * @param {*} source a MediaStreamTrack or InputDeviceInfo
   * @returns {?Object}
   */
  function readCapabilities(source) {
    if (!source || typeof source.getCapabilities !== 'function') return null;
    var caps;
    try {
      caps = source.getCapabilities();
    } catch (error) {
      // Firefox throws NotSupportedError rather than returning an empty object.
      return null;
    }
    if (!caps) return null;
    return {
      facingMode: caps.facingMode || null,
      focusDistance: caps.focusDistance || null,
      zoom: caps.zoom || null,
      width: caps.width || null,
      height: caps.height || null,
      focusMode: caps.focusMode || null,
      torch: caps.torch === undefined ? null : caps.torch,
    };
  }

  /** @param {?MediaStream} stream */
  function stopStream(stream) {
    if (!stream) return;
    try {
      stream.getTracks().forEach(function (track) {
        track.stop();
      });
    } catch (error) {
      logDebug('track already ended', error);
    }
  }

  // ---------------------------------------------------------------------------
  // Camera enumeration
  // ---------------------------------------------------------------------------

  /**
   * Enumerates video inputs, requesting permission first.
   *
   * Before permission is granted browsers report devices with an empty
   * `deviceId` and `label`, which leaves every selection heuristic with nothing
   * to work from. The throwaway stream forces the prompt so the real list can
   * be read.
   *
   * @returns {Promise<string>} envelope wrapping an array of camera descriptors
   */
  async function listCameras() {
    if (!hasMediaDevices()) {
      return fail(Kind.insecureContext, 'navigator.mediaDevices is unavailable');
    }

    var primer = null;
    try {
      primer = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' },
        audio: false,
      });
    } catch (error) {
      var primerKind = kindFromError(error);
      // A denied permission is terminal, but a device that cannot satisfy
      // facingMode still deserves an enumeration attempt.
      if (primerKind === Kind.permissionDenied) {
        return fail(primerKind, describe(error));
      }
      logDebug('permission primer failed, continuing', error);
    } finally {
      stopStream(primer);
    }

    try {
      var devices = await navigator.mediaDevices.enumerateDevices();
      var cameras = devices
        .filter(function (device) {
          return device.kind === 'videoinput';
        })
        .map(function (device) {
          return {
            deviceId: device.deviceId,
            label: device.label || '',
            groupId: device.groupId || null,
            // InputDeviceInfo.getCapabilities is Chromium-only and is the only
            // way to learn facingMode without opening a stream.
            capabilities: readCapabilities(device),
          };
        });

      if (cameras.length === 0) {
        return fail(Kind.noCameraFound, 'no videoinput devices reported');
      }
      logDebug('enumerated ' + cameras.length + ' cameras', cameras);
      return ok(cameras);
    } catch (error) {
      return fail(kindFromError(error), describe(error));
    }
  }

  /**
   * Opens a camera briefly purely to measure its live capabilities.
   *
   * @param {string} deviceId
   * @returns {Promise<string>} envelope wrapping a capability object or null
   */
  async function probeCamera(deviceId) {
    if (!hasMediaDevices()) {
      return fail(Kind.insecureContext, 'navigator.mediaDevices is unavailable');
    }
    var stream = null;
    try {
      stream = await navigator.mediaDevices.getUserMedia({
        video: { deviceId: { exact: deviceId } },
        audio: false,
      });
      var capabilities = readCapabilities(stream.getVideoTracks()[0]);
      logDebug('probed ' + deviceId, capabilities);
      return ok(capabilities);
    } catch (error) {
      return fail(kindFromError(error), describe(error));
    } finally {
      stopStream(stream);
    }
  }

  // ---------------------------------------------------------------------------
  // Constraints
  // ---------------------------------------------------------------------------

  /**
   * Builds the constraint ladder tried in order until one opens.
   *
   * Requesting an explicit resolution is the highest-impact change for 1D
   * barcodes: with no size hint browsers hand back 640x480, at which the bars
   * of an EAN-13 held at arm's length land on fewer pixels than the decoder
   * needs. `ideal` degrades gracefully where `exact` would throw.
   *
   * Later tiers drop constraints one at a time, so a device that cannot honour
   * an exact deviceId ends up scanning instead of failing outright — the gap
   * that made 1.x surface OverconstrainedError as a dead end.
   *
   * @param {Object} config
   * @returns {Array<MediaStreamConstraints>}
   */
  function constraintLadder(config) {
    var size = {
      width: { ideal: config.idealWidth || 1920 },
      height: { ideal: config.idealHeight || 1080 },
      frameRate: { ideal: config.idealFrameRate || 30 },
    };

    var ladder = [];
    if (config.deviceId) {
      ladder.push({
        video: Object.assign({ deviceId: { exact: config.deviceId } }, size),
        audio: false,
      });
      ladder.push({
        video: Object.assign({ deviceId: { ideal: config.deviceId } }, size),
        audio: false,
      });
    }
    ladder.push({
      video: Object.assign({ facingMode: { ideal: 'environment' } }, size),
      audio: false,
    });
    // Last resort: whatever the browser is willing to give us.
    ladder.push({ video: true, audio: false });
    return ladder;
  }

  /**
   * @param {Object} config
   * @returns {Promise<MediaStream>}
   */
  async function openStream(config) {
    var ladder = constraintLadder(config);
    var lastError = null;
    for (var i = 0; i < ladder.length; i++) {
      try {
        var stream = await navigator.mediaDevices.getUserMedia(ladder[i]);
        logDebug('opened stream at constraint tier ' + i, ladder[i]);
        return stream;
      } catch (error) {
        lastError = error;
        // A denied permission fails identically at every tier.
        if (kindFromError(error) === Kind.permissionDenied) throw error;
        logDebug('constraint tier ' + i + ' rejected', error);
      }
    }
    throw lastError || new Error('no constraint set could be satisfied');
  }

  /**
   * Picks a zoom factor when the caller did not specify one.
   *
   * A lens that focuses closer than ~6 cm is an ultra-wide or macro module. It
   * gets chosen for that short focus distance, but it spreads the target across
   * fewer pixels and bends straight edges near the frame border — both bad for
   * 1D decoding. Zooming crops toward the frame centre, which is exactly where
   * the overlay asks the user to hold the code, recovering detail without
   * giving up the close focus.
   *
   * @param {?Object} capabilities
   * @returns {?number}
   */
  function autoZoom(capabilities) {
    if (!capabilities || !capabilities.zoom || !capabilities.focusDistance) {
      return null;
    }
    var focus = capabilities.focusDistance;
    var zoom = capabilities.zoom;
    if (typeof focus.min !== 'number' || focus.min > 0.06) return null;
    if (typeof zoom.max !== 'number' || zoom.max <= 1) return null;
    return Math.min(1.8, zoom.max);
  }

  /**
   * Applies focus, zoom and torch to a live track.
   *
   * Each is applied separately: `advanced` constraints are best-effort by
   * specification, and browsers disagree about whether an unsupported one is
   * ignored or throws. Batching them would let a missing torch cancel the
   * continuous focus that actually matters for close-range scanning.
   *
   * @param {MediaStreamTrack} track
   * @param {Object} config
   * @param {?Object} capabilities
   */
  async function tuneTrack(track, config, capabilities) {
    async function apply(constraint, label) {
      try {
        await track.applyConstraints({ advanced: [constraint] });
        logDebug('applied ' + label);
      } catch (error) {
        logDebug('could not apply ' + label, error);
      }
    }

    var focusModes = (capabilities && capabilities.focusMode) || [];
    if (
      config.continuousFocus !== false &&
      focusModes.indexOf('continuous') >= 0
    ) {
      // Without this many Android devices keep a fixed focus set for distant
      // subjects and never sharpen on a code held close to the lens.
      await apply({ focusMode: 'continuous' }, 'continuous focus');
    }

    var zoom =
      typeof config.zoom === 'number' ? config.zoom : autoZoom(capabilities);
    if (zoom && capabilities && capabilities.zoom) {
      var bounded = Math.max(
        capabilities.zoom.min || 1,
        Math.min(zoom, capabilities.zoom.max)
      );
      await apply({ zoom: bounded }, 'zoom ' + bounded);
    }

    if (config.torch === true && capabilities && capabilities.torch) {
      await apply({ torch: true }, 'torch');
    }
  }

  // ---------------------------------------------------------------------------
  // DOM
  // ---------------------------------------------------------------------------

  /**
   * Resolves once the platform view's container exists.
   *
   * Flutter mounts platform views asynchronously, so the container is reliably
   * absent on the first frame. Observing mutations reacts as soon as it lands
   * instead of paying a fixed polling interval.
   *
   * @param {string} id
   * @param {number=} timeoutMs
   * @returns {Promise<HTMLElement>}
   */
  function waitForElement(id, timeoutMs) {
    var existing = document.getElementById(id);
    if (existing) return Promise.resolve(existing);

    return new Promise(function (resolve, reject) {
      var observer = new MutationObserver(function () {
        var element = document.getElementById(id);
        if (!element) return;
        clearTimeout(timer);
        observer.disconnect();
        resolve(element);
      });

      var timer = setTimeout(function () {
        observer.disconnect();
        reject(new Error('timed out waiting for element #' + id));
      }, timeoutMs || 10000);

      observer.observe(document.body, { childList: true, subtree: true });
    });
  }

  /**
   * @param {string} sessionId
   * @returns {HTMLVideoElement}
   */
  function createVideoElement(sessionId) {
    var video = document.createElement('video');
    video.id = 'omni-video-' + sessionId;
    video.style.width = '100%';
    video.style.height = '100%';
    video.style.objectFit = 'cover';
    // Required on iOS Safari, which otherwise takes the stream fullscreen.
    video.setAttribute('playsinline', 'true');
    video.setAttribute('muted', 'true');
    video.muted = true;
    return video;
  }

  // ---------------------------------------------------------------------------
  // Decoders
  // ---------------------------------------------------------------------------

  /**
   * ZXing exceptions that mean "nothing decodable in this frame".
   *
   * This list fixes the most damaging bug in 1.x: only NotFoundException was
   * tolerated, so a ChecksumException or FormatException — both routine on a
   * moving or partially covered symbol — was reported as fatal and tore down
   * the camera mid-scan.
   */
  var TRANSIENT_DECODE_ERRORS = [
    'NotFoundException',
    'ChecksumException',
    'FormatException',
  ];

  /**
   * @param {*} error
   * @returns {boolean}
   */
  function isTransientDecodeError(error) {
    if (!error) return true;
    var name =
      error.name || (error.constructor && error.constructor.name) || '';
    for (var i = 0; i < TRANSIENT_DECODE_ERRORS.length; i++) {
      if (name.indexOf(TRANSIENT_DECODE_ERRORS[i]) >= 0) return true;
    }
    // Minification can erase constructor names, so fall back to instanceof
    // while the classes are reachable.
    var Z = zxing();
    if (Z) {
      if (Z.NotFoundException && error instanceof Z.NotFoundException) return true;
      if (Z.ChecksumException && error instanceof Z.ChecksumException) return true;
      if (Z.FormatException && error instanceof Z.FormatException) return true;
    }
    return false;
  }

  /**
   * Builds a ZXing reader restricted to the requested formats.
   *
   * @param {Array<string>} formats ZXing BarcodeFormat names
   * @returns {*} a BrowserMultiFormatReader
   */
  function createZXingReader(formats) {
    var Z = zxing();
    if (!Z) throw new Error('ZXing library is not loaded');

    var hints = new Map();
    var possible = (formats || [])
      .map(function (name) {
        return Z.BarcodeFormat[name];
      })
      .filter(function (value) {
        return value !== undefined;
      });

    // Restricting the format set is the cheapest available speedup: an
    // unrestricted reader runs every symbology decoder over every frame, which
    // costs time and widens the surface for false positives.
    if (possible.length > 0) {
      hints.set(Z.DecodeHintType.POSSIBLE_FORMATS, possible);
    }
    hints.set(Z.DecodeHintType.TRY_HARDER, true);

    return new Z.BrowserMultiFormatReader(hints, 100);
  }

  /**
   * @param {Object} session
   * @param {Object} config
   */
  function startZXingSession(session, config) {
    var reader = createZXingReader(config.formats);
    session.reader = reader;

    reader.decodeFromStream(
      session.stream,
      session.video,
      function (result, error) {
        if (session.stopped) return;
        if (result) {
          session.onDecode(result.getText(), String(result.getBarcodeFormat()));
          return;
        }
        // Transient errors are the normal case and must never reach onFailure.
        if (error && !isTransientDecodeError(error)) {
          logDebug('non-transient decode error', error);
        }
      }
    );
  }

  /**
   * Builds a native BarcodeDetector restricted to supported formats.
   *
   * @param {Array<string>} formats BarcodeDetector format names
   * @returns {Promise<*>}
   */
  async function createNativeDetector(formats) {
    if (!hasNativeDetector()) {
      throw new Error('BarcodeDetector is not implemented in this browser');
    }
    var supported = [];
    try {
      supported = await window.BarcodeDetector.getSupportedFormats();
    } catch (error) {
      supported = [];
    }
    // An unsupported format string makes the constructor throw, so intersect
    // before constructing.
    var requested = (formats || []).filter(function (name) {
      return supported.indexOf(name) >= 0;
    });
    if (requested.length === 0) {
      throw new Error(
        'none of the requested formats are supported by BarcodeDetector'
      );
    }
    return new window.BarcodeDetector({ formats: requested });
  }

  /** Minimum gap between native detect() calls, in milliseconds. */
  var NATIVE_DETECT_INTERVAL_MS = 60;

  /**
   * @param {Object} session
   * @param {Object} config
   */
  async function startNativeSession(session, config) {
    var detector = await createNativeDetector(config.formats);
    session.detector = detector;

    var lastRun = 0;
    var busy = false;

    async function scan(now) {
      if (session.stopped) return;
      schedule();

      // detect() is async; without this guard a slow frame would stack calls.
      if (busy) return;
      var timestamp = typeof now === 'number' ? now : Date.now();
      if (timestamp - lastRun < NATIVE_DETECT_INTERVAL_MS) return;
      // HAVE_CURRENT_DATA. Detecting before this yields nothing but costs work.
      if (session.video.readyState < 2) return;

      busy = true;
      lastRun = timestamp;
      try {
        var codes = await detector.detect(session.video);
        if (!session.stopped && codes && codes.length > 0) {
          session.onDecode(codes[0].rawValue, codes[0].format || '');
        }
      } catch (error) {
        // detect() rejects on frames it cannot read, which is routine.
      } finally {
        busy = false;
      }
    }

    function schedule() {
      if (session.stopped) return;
      // requestVideoFrameCallback fires once per decoded video frame, pacing
      // detection to the stream rather than to the display refresh rate.
      if (typeof session.video.requestVideoFrameCallback === 'function') {
        session.frameHandle = session.video.requestVideoFrameCallback(scan);
        session.usesFrameCallback = true;
      } else {
        session.frameHandle = setTimeout(scan, NATIVE_DETECT_INTERVAL_MS);
        session.usesFrameCallback = false;
      }
    }

    schedule();
  }

  // ---------------------------------------------------------------------------
  // Session lifecycle
  // ---------------------------------------------------------------------------

  /**
   * Live sessions keyed by id.
   *
   * 1.x kept a single module-level state object, so mounting a second scanner
   * silently tore down the first and stopping either one cleared both.
   */
  var sessions = new Map();

  /**
   * @param {string} requested one of 'auto', 'native', 'zxing'
   * @returns {string} the engine actually usable
   */
  function resolveEngine(requested) {
    if (requested === 'native') {
      if (hasNativeDetector()) return 'native';
      throw {
        kind: Kind.engineUnavailable,
        message: 'BarcodeDetector is not implemented in this browser',
      };
    }
    if (requested === 'auto') {
      if (hasNativeDetector()) return 'native';
      if (zxing()) return 'zxing';
      throw {
        kind: Kind.engineUnavailable,
        message: 'neither BarcodeDetector nor the ZXing bundle is available',
      };
    }
    if (zxing()) return 'zxing';
    throw {
      kind: Kind.engineUnavailable,
      message:
        'the ZXing library was not found on window; add its script tag to ' +
        'web/index.html',
    };
  }

  /**
   * Starts a camera and begins decoding.
   *
   * @param {string} configJson
   * @param {function(string, string)} onDecode called as (value, format)
   * @param {function(string, string)} onFailure called as (kind, message)
   * @returns {Promise<string>} envelope wrapping the session descriptor
   */
  async function startSession(configJson, onDecode, onFailure) {
    var config;
    try {
      config = JSON.parse(configJson);
    } catch (error) {
      return fail(Kind.unknown, 'invalid session config: ' + describe(error));
    }

    if (!hasMediaDevices()) {
      return fail(Kind.insecureContext, 'navigator.mediaDevices is unavailable');
    }

    // Restarting over a live session of the same id must not leak its tracks.
    if (sessions.has(config.sessionId)) {
      await stopSession(config.sessionId);
    }

    var engine;
    try {
      engine = resolveEngine(config.engine);
    } catch (thrown) {
      return fail(
        thrown.kind || Kind.engineUnavailable,
        thrown.message || thrown
      );
    }

    var session = {
      id: config.sessionId,
      stopped: false,
      stream: null,
      video: null,
      reader: null,
      detector: null,
      frameHandle: null,
      usesFrameCallback: false,
      onDecode: onDecode,
      onFailure: onFailure,
    };
    sessions.set(session.id, session);

    try {
      var container = await waitForElement(config.containerId);
      if (session.stopped) return ok(null);

      session.stream = await openStream(config);

      var track = session.stream.getVideoTracks()[0];
      if (!track) throw new Error('stream contains no video track');

      var capabilities = readCapabilities(track);
      await tuneTrack(track, config, capabilities);

      // A track can end without an error — the OS revoking the camera, a webcam
      // unplugged, another tab taking over. Without this the preview just
      // freezes with no indication anything went wrong.
      track.addEventListener('ended', function () {
        if (session.stopped) return;
        session.onFailure(Kind.cameraInUse, 'the camera track ended');
      });

      session.video = createVideoElement(session.id);
      container.appendChild(session.video);

      if (engine === 'native') {
        session.video.srcObject = session.stream;
        await session.video.play();
        await startNativeSession(session, config);
      } else {
        startZXingSession(session, config);
      }

      var settings =
        typeof track.getSettings === 'function' ? track.getSettings() : {};
      logDebug('session ' + session.id + ' started on ' + engine, settings);

      return ok({
        sessionId: session.id,
        deviceId: settings.deviceId || config.deviceId || '',
        label: track.label || '',
        groupId: settings.groupId || null,
        capabilities: readCapabilities(track),
        width: settings.width || null,
        height: settings.height || null,
        engine: engine,
      });
    } catch (error) {
      await stopSession(session.id);
      var kind = kindFromError(error);
      return fail(
        kind === Kind.unknown ? Kind.startFailed : kind,
        describe(error)
      );
    }
  }

  /**
   * Stops a session and releases its camera. Safe to call for unknown ids.
   *
   * @param {string} sessionId
   * @returns {Promise<void>}
   */
  async function stopSession(sessionId) {
    var session = sessions.get(sessionId);
    if (!session) return;
    sessions.delete(sessionId);
    session.stopped = true;

    if (session.frameHandle !== null) {
      try {
        if (
          session.usesFrameCallback &&
          session.video &&
          typeof session.video.cancelVideoFrameCallback === 'function'
        ) {
          session.video.cancelVideoFrameCallback(session.frameHandle);
        } else {
          clearTimeout(session.frameHandle);
        }
      } catch (error) {
        logDebug('frame handle already invalid', error);
      }
      session.frameHandle = null;
    }

    if (session.reader) {
      try {
        session.reader.reset();
      } catch (error) {
        logDebug('reader already torn down', error);
      }
      session.reader = null;
    }

    stopStream(session.stream);
    session.stream = null;

    if (session.video) {
      try {
        session.video.srcObject = null;
        if (session.video.parentNode) {
          session.video.parentNode.removeChild(session.video);
        }
      } catch (error) {
        logDebug('video element already detached', error);
      }
      session.video = null;
    }
    logDebug('session ' + sessionId + ' stopped');
  }

  // ---------------------------------------------------------------------------
  // Still-image decoding
  // ---------------------------------------------------------------------------

  /**
   * @param {Blob} blob
   * @returns {Promise<HTMLImageElement>}
   */
  function loadImageElement(blob) {
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(blob);
      var image = new Image();
      image.onload = function () {
        URL.revokeObjectURL(url);
        resolve(image);
      };
      image.onerror = function () {
        URL.revokeObjectURL(url);
        reject(new Error('the bytes could not be decoded as an image'));
      };
      image.src = url;
    });
  }

  /**
   * Decodes a still image from raw bytes.
   *
   * @param {Uint8Array} bytes
   * @param {string} mimeType
   * @param {string} configJson
   * @returns {Promise<string>} envelope wrapping {value, format} or null
   */
  async function decodeImage(bytes, mimeType, configJson) {
    var config;
    try {
      config = JSON.parse(configJson);
    } catch (error) {
      return fail(Kind.unknown, 'invalid decode config: ' + describe(error));
    }

    var engine;
    try {
      engine = resolveEngine(config.engine);
    } catch (thrown) {
      return fail(
        thrown.kind || Kind.engineUnavailable,
        thrown.message || thrown
      );
    }

    var blob = new Blob([bytes], { type: mimeType });

    try {
      if (engine === 'native') {
        var detector = await createNativeDetector(config.formats);
        var bitmap = await createImageBitmap(blob);
        try {
          var codes = await detector.detect(bitmap);
          if (!codes || codes.length === 0) return ok(null);
          return ok({
            value: codes[0].rawValue,
            format: codes[0].format || '',
          });
        } finally {
          if (typeof bitmap.close === 'function') bitmap.close();
        }
      }

      var reader = createZXingReader(config.formats);
      var image = await loadImageElement(blob);
      try {
        var result = await reader.decodeFromImageElement(image);
        if (!result) return ok(null);
        // 1.x reported 'EAN-13' here regardless of what was actually decoded.
        return ok({
          value: result.getText(),
          format: String(result.getBarcodeFormat()),
        });
      } finally {
        try {
          reader.reset();
        } catch (error) {
          logDebug('nothing to release on reader', error);
        }
      }
    } catch (error) {
      // "No code in this image" is an answer, not a failure.
      if (isTransientDecodeError(error)) return ok(null);
      return fail(Kind.unknown, describe(error));
    }
  }

  // ---------------------------------------------------------------------------
  // Public namespace
  // ---------------------------------------------------------------------------

  window.omniScanner = {
    version: VERSION,
    debug: false,
    probeEnvironment: probeEnvironment,
    listCameras: listCameras,
    probeCamera: probeCamera,
    startSession: startSession,
    stopSession: stopSession,
    decodeImage: decodeImage,
  };
})();
