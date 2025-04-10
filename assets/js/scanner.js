const ZXing = window.ZXing;

window.scannerState = {
    codeReader: null,
    videoElement: null,
    stream: null,
    onDetectCallback: null,
    onErrorCallback: null,
    videoContainerId: null,
    viewId: null,
};

async function waitForElement(selector, timeout = 5000) {
    const start = Date.now();
    while (Date.now() - start < timeout) {
        const element = document.getElementById(selector);
        if (element) return element;
        await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error(`Timeout waiting for element: ${selector}`);
}

async function getVideoInputDevices() {
    console.log("[JS] getVideoInputDevices called");
    try {

        await navigator.mediaDevices.getUserMedia({ video: true })
            .then(stream => {
                stream.getTracks().forEach(track => track.stop());
                console.log("[JS] Temporary stream acquired for permissions check.");
            }).catch(err => {
                console.warn(`[JS] Error acquiring temp stream for permissions (may be expected if denied/busy): ${err.name} - ${err.message}`);
            });


        const devices = await navigator.mediaDevices.enumerateDevices();
        const videoDevices = devices.filter(device => device.kind === 'videoinput');

        console.log("[JS] Found video devices:", videoDevices);
        return videoDevices.map(device => ({
            deviceId: device.deviceId,
            label: device.label || `Camera ${videoDevices.indexOf(device) + 1}`
        }));
    } catch (error) {
        console.error('[JS] Error in getVideoInputDevices:', error);
        return [];
    }
}


async function startCamera(videoContainerId, viewId, requestedDeviceId, onDetect, onError) { // Renamed deviceId -> requestedDeviceId for clarity
    console.log(`[JS] startCamera called for viewId: ${viewId}, requestedDeviceId: ${requestedDeviceId || 'Default'}`);
    window.scannerState.onDetectCallback = onDetect;
    window.scannerState.onErrorCallback = onError;
    window.scannerState.videoContainerId = videoContainerId;
    window.scannerState.viewId = viewId;

    if (!window.ZXing) {
        console.error("[JS] ZXing library not loaded!");
        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback("ZXing library not loaded");
        }
        return;
    }

    if (window.scannerState.codeReader && window.scannerState.viewId === viewId) {
        console.warn(`[JS] Scanner already running for viewId: ${viewId}. Stopping previous instance first.`);
        await stopCamera(viewId);
    }

    window.scannerState.codeReader = new ZXing.BrowserMultiFormatReader();

    const videoContainer = await waitForElement(videoContainerId);
    if (!videoContainer) {
        console.error(`[JS] Video container not found after wait: ${videoContainerId}`);
        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback(`Video container not found: ${videoContainerId}`);
        }
        return;
    }

    const videoElement = document.createElement('video');
    videoElement.id = `video-${viewId}`;
    videoElement.style.width = '100%';
    videoElement.style.height = '100%';
    videoElement.style.objectFit = 'cover';
    videoElement.setAttribute('playsinline', '');
    videoContainer.appendChild(videoElement);
    window.scannerState.videoElement = videoElement;

    console.log(`[JS] Video element created and appended: ${videoElement.id}`);

    let stream = null;
    let currentConstraints = null;
    let selectedDeviceId = null;

    if (requestedDeviceId && requestedDeviceId.length > 0) {
        currentConstraints = { video: { deviceId: { exact: requestedDeviceId } } };
        console.log(`[JS] Attempt 1: Trying getUserMedia with exact deviceId: ${requestedDeviceId}`);
        try {
            stream = await navigator.mediaDevices.getUserMedia(currentConstraints);
            selectedDeviceId = requestedDeviceId;
            console.log(`[JS] Attempt 1 SUCCESS: Got stream with exact deviceId: ${selectedDeviceId}`);
        } catch (error) {
            console.warn(`[JS] Attempt 1 FAILED (exact deviceId: ${requestedDeviceId}): ${error.name}`);
            if (error.name !== 'OverconstrainedError' && error.name !== 'NotFoundError' && error.name !== 'DevicesNotFoundError') {
                _reportCameraError(error, requestedDeviceId, window.scannerState.onErrorCallback);
                return;
            }
        }
    }

    if (!stream) {
        if (requestedDeviceId && requestedDeviceId.length > 0) {
            currentConstraints = { video: { deviceId: { ideal: requestedDeviceId } } };
            console.log(`[JS] Attempt 2: Trying getUserMedia with ideal deviceId: ${requestedDeviceId}`);
        } else {
            currentConstraints = { video: { facingMode: { ideal: 'environment' } } };
            console.log("[JS] Attempt 2: Trying getUserMedia with ideal facingMode: environment");
        }
        try {
            stream = await navigator.mediaDevices.getUserMedia(currentConstraints);
            console.log(`[JS] Attempt 2 SUCCESS: Got stream with ideal constraints.`);
        } catch (error) {
            console.warn(`[JS] Attempt 2 FAILED (ideal constraints): ${error.name}`);
            _reportCameraError(error, requestedDeviceId, window.scannerState.onErrorCallback);
            await stopCamera(viewId);
            return;
        }
    }

    if (stream) {
        window.scannerState.stream = stream;

        try {
            const videoTracks = stream.getVideoTracks();
            if (videoTracks.length > 0) {
                const settings = videoTracks[0].getSettings();
                selectedDeviceId = settings.deviceId; // Update with actual ID
                console.log(`[JS] Actual settings for track: ${videoTracks[0].label}`, settings);
                console.log(`[JS] Actual deviceId being used: ${selectedDeviceId}`);
            }
        } catch (e) { console.warn("[JS] Could not get settings from video track:", e); }


        console.log(`[JS] Starting ZXing decodeFromStream for viewId: ${viewId}`);
        try {
            window.scannerState.codeReader.decodeFromStream(stream, videoElement, (result, err) => {
                if (result) {
                    console.log(`[JS] Code detected (viewId: ${viewId}):`, result.getText());
                    if (window.scannerState.onDetectCallback) {
                        window.scannerState.onDetectCallback(result.getText(), result.getBarcodeFormat().toString());
                    }
                }
                if (err && !(err instanceof ZXing.NotFoundException)) {
                    console.error(`[JS] Decode loop error (viewId: ${viewId}):`, err);

                    if (window.scannerState.onErrorCallback) {
                        window.scannerState.onErrorCallback(`Decode Error: ${err.message}`);
                    }
                }
            });

            console.log(`[JS] decodeFromStream initiated successfully for viewId: ${viewId}`);

        } catch (decodeError) {
            console.error("[JS] Error initiating decodeFromStream:", decodeError);
            _reportCameraError(decodeError, selectedDeviceId || requestedDeviceId, window.scannerState.onErrorCallback);
            await stopCamera(viewId);
            return;
        }
    } else {
        console.error("[JS] Failed to obtain camera stream after all attempts.");
        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback("Could not start camera after multiple attempts.");
        }
        await stopCamera(viewId);
    }
}

async function stopCamera(viewId) {
    console.log(`[JS] stopCamera called for viewId: ${viewId}`);
    if (window.scannerState.viewId !== viewId && window.scannerState.viewId !== null) {
        console.warn(`[JS] Stop request for viewId ${viewId}, but current viewId is ${window.scannerState.viewId}. Ignoring unless state is null.`);
        if (window.scannerState.viewId !== null) return;
    }

    if (window.scannerState.stream) {
        try {
            const tracks = window.scannerState.stream.getTracks();
            console.log(`[JS] Stopping ${tracks.length} tracks.`);
            tracks.forEach(track => track.stop());
            console.log("[JS] All MediaStream tracks stopped.");
        } catch (e) { console.error("[JS] Error stopping MediaStream tracks:", e); }
        window.scannerState.stream = null;
    }

    if (window.scannerState.codeReader) {
        try {
            window.scannerState.codeReader.reset();
            console.log("[JS] ZXing reader reset.");
        } catch (e) { console.error("[JS] Error resetting ZXing reader:", e); }
        window.scannerState.codeReader = null;
    }

    if (window.scannerState.videoElement) {
        if (window.scannerState.videoElement.parentNode) {
            window.scannerState.videoElement.parentNode.removeChild(window.scannerState.videoElement);
            console.log("[JS] Video element removed from DOM.");
        } else { console.warn("[JS] Video element parent not found during cleanup."); }
        window.scannerState.videoElement = null;
    }

    window.scannerState.onDetectCallback = null;
    window.scannerState.onErrorCallback = null;
    window.scannerState.videoContainerId = null;
    window.scannerState.viewId = null;
    console.log(`[JS] Scanner stopped and cleaned up for viewId: ${viewId}`);
}

function _reportCameraError(error, requestedDeviceId, onErrorCallback) {
    console.error('[JS] Camera Access or Start Error:', error.name, error.message);
    let errorMessage = "Unknown camera error";
    if (error.name === 'NotReadableError' || error.name === 'TrackStartError' || error.name === 'AbortError') {
        errorMessage = 'Failed to access camera. It might be already in use by this page (another component?) or another application/tab. Please ensure only one camera component is active.';
    } else if (error.name === 'NotAllowedError') {
        errorMessage = 'Camera permission denied. Please grant permission in your browser settings.';
    } else if (error.name === 'NotFoundError' || error.name === 'DevicesNotFoundError') {
        errorMessage = 'No suitable camera found, or the specified camera was not found.';
    } else if (error.name === 'OverconstrainedError' || error.name === 'ConstraintNotSatisfiedError') {
        errorMessage = `The requested camera constraints (e.g., specific device ID ${requestedDeviceId || ''}, resolution) could not be satisfied. The camera might be busy or not support the request.`;
    } else if (error instanceof DOMException) {
        errorMessage = `Camera error: ${error.message} (${error.name})`;
    } else {
        errorMessage = `Failed to start camera: ${error}`;
    }

    if (onErrorCallback) {
        onErrorCallback(errorMessage);
    }
}