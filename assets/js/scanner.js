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
    videoElement.setAttribute('playsinline', 'true');
    videoElement.setAttribute('autoplay', 'true');
    videoElement.setAttribute('muted', 'true');
    videoContainer.appendChild(videoElement);
    window.scannerState.videoElement = videoElement;
    console.log(`[JS] Video element created and appended: ${videoElement.id}`);

    // --- Add Video Event Listeners for Debugging ---
    videoElement.addEventListener('loadedmetadata', (e) => { console.log(`[JS][Video Event] loadedmetadata - ViewId: ${viewId}`); });
    videoElement.addEventListener('canplay', (e) => { console.log(`[JS][Video Event] canplay - ViewId: ${viewId}`); });
    videoElement.addEventListener('playing', (e) => { console.log(`[JS][Video Event] playing - ViewId: ${viewId}`); });
    videoElement.addEventListener('error', (e) => {
        console.error(`[JS][Video Event] error - ViewId: ${viewId}`, videoElement.error);
        // Report this error if it seems relevant
        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback(`Video element error: ${videoElement.error?.message || 'Unknown video error'}`);
        }
    });
    videoElement.addEventListener('stalled', (e) => {
        console.warn(`[JS][Video Event] stalled - ViewId: ${viewId}. Video playback may have stopped.`);
        // Maybe report this as a potential issue?
        if (window.scannerState.onErrorCallback) {
            window.scannerState.onErrorCallback(`Video playback stalled. Check connection or permissions.`);
        }
    });
    // --- End Video Event Listeners ---


    // --- Multi-Attempt Camera Acquisition (Keep from previous version) ---
    let stream = null;
    let selectedDeviceId = null;

    // Attempt 1: Exact Device ID
    if (requestedDeviceId && requestedDeviceId.length > 0) { /* ... try exact ... */ }
    // Attempt 2: Ideal Device ID or FacingMode
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
            // If this attempt also fails, report the *latest* error and stop.
            _reportCameraError(error, requestedDeviceId, window.scannerState.onErrorCallback);
            await stopCamera(viewId);
            return;
        }
    }

    // --- Process Successful Stream ---
    if (stream) {
        window.scannerState.stream = stream;

        // --- Verify Stream State ---
        console.log(`[JS] Stream obtained. Active: ${stream.active}`);
        const videoTracks = stream.getVideoTracks();
        if (videoTracks.length === 0) {
            console.error("[JS] Error: Stream obtained but has no video tracks!");
            _reportCameraError({ name: 'NoVideoTracksError', message: 'Stream has no video tracks.' }, requestedDeviceId, window.scannerState.onErrorCallback);
            await stopCamera(viewId);
            return;
        }
        console.log(`[JS] Video Tracks: ${videoTracks.length}`);
        videoTracks.forEach(track => {
            console.log(`[JS] - Track ID: ${track.id}, Label: ${track.label}, ReadyState: ${track.readyState}, Enabled: ${track.enabled}`);
            if (track.readyState !== 'live') {
                console.warn(`[JS] - Track ${track.id} is not live! State: ${track.readyState}`);
                // This might indicate an issue, but proceed for now
            }
            // Listen for track ending prematurely
            track.onended = () => {
                console.warn(`[JS] Video track ended unexpectedly! ID: ${track.id}, Label: ${track.label}`);
                if (window.scannerState.onErrorCallback) {
                    window.scannerState.onErrorCallback(`Camera track ended unexpectedly. (ViewId: ${viewId})`);
                }
                // Consider stopping the whole process if a track ends?
                stopCamera(viewId);
            };
        });
        // --- End Stream State Verification ---


        // --- Attach Stream and Attempt Play ---
        console.log(`[JS] Attaching stream to video element (srcObject)`);
        videoElement.srcObject = stream;

        // Try explicitly playing the video - crucial for iOS sometimes
        try {
            console.log('[JS] Attempting videoElement.play()...');
            await videoElement.play();
            console.log('[JS] videoElement.play() promise resolved.');
            // If play() succeeds, wait for 'playing' event OR proceed to decode

            // --- Initiate Decoding (Option A: Immediately after play starts) ---
            // console.log(`[JS] Initiating decodeFromStream immediately after play() resolves.`);
            // initiateDecoding(stream, videoElement, viewId); // Call helper

            // --- Initiate Decoding (Option B: Wait for 'playing' event - Safer for iOS) ---
            // Add a one-time listener for the 'playing' event
            let decodeInitiated = false;
            const playingListener = async () => {
                if (decodeInitiated) return; // Prevent multiple calls
                decodeInitiated = true;
                console.log(`[JS] 'playing' event fired. Initiating decodeFromStream.`);
                initiateDecoding(stream, videoElement, viewId); // Call helper
                videoElement.removeEventListener('playing', playingListener); // Clean up listener
            };
            videoElement.addEventListener('playing', playingListener);
            // Add a timeout in case 'playing' never fires
            setTimeout(() => {
                if (!decodeInitiated && !window.scannerState.stream) { // Check if already stopped
                    console.warn("[JS] Timeout waiting for 'playing' event. Video might not start.");
                    videoElement.removeEventListener('playing', playingListener); // Clean up listener
                    // Decide: report error or try initiating decode anyway?
                    // _reportCameraError({ name: 'VideoPlaybackTimeout', message: 'Video did not start playing.' }, requestedDeviceId, window.scannerState.onErrorCallback);
                    initiateDecoding(stream, videoElement, viewId); // Risky: Try anyway?
                }
            }, 3000);


        } catch (playError) {
            console.error('[JS] Error calling videoElement.play():', playError.name, playError.message);
            _reportCameraError(playError, selectedDeviceId || requestedDeviceId, window.scannerState.onErrorCallback);
            await stopCamera(viewId);
            return;
        }

    } else {
        console.error("[JS] Failed to obtain camera stream after all attempts (final check).");
        await stopCamera(viewId);
    }
}


// Helper function to start the decoding loop
function initiateDecoding(stream, videoElement, viewId) {
    // Check if reader still exists (might have been cleared by an error/stop)
    if (!window.scannerState.codeReader) {
        console.warn(`[JS] initiateDecoding called, but codeReader is null (viewId: ${viewId}). Skipping.`);
        return;
    }
    console.log(`[JS] Starting ZXing decodeFromStream for viewId: ${viewId}`);
    try {
        window.scannerState.codeReader.decodeFromStream(stream, videoElement, (result, err) => {
            // Check if the current state still belongs to this viewId before processing
            if (window.scannerState.viewId !== viewId) return;

            if (result) {
                // console.log(`[JS] Code detected (viewId: ${viewId}):`, result.getText()); // Can be noisy
                if (window.scannerState.onDetectCallback) {
                    window.scannerState.onDetectCallback(result.getText(), result.getBarcodeFormat().toString());
                }
            }
            if (err && !(err instanceof ZXing.NotFoundException)) {
                console.error(`[JS] Decode loop error (viewId: ${viewId}):`, err);
                // Consider if/how to report these non-fatal errors
                // if (window.scannerState.onErrorCallback) { ... }
            }
        });
        console.log(`[JS] decodeFromStream initiated successfully for viewId: ${viewId}`);
    } catch (decodeError) {
        console.error("[JS] Error initiating decodeFromStream:", decodeError);
        // Report error (use the main error reporter)
        _reportCameraError(decodeError, window.scannerState.stream?.getVideoTracks()[0]?.getSettings().deviceId || 'N/A', window.scannerState.onErrorCallback);
        // Don't necessarily stop camera here, maybe just decoding failed? Monitor.
        stopCamera(viewId);
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